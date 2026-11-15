// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITextResource} from "../../../resources/ITextResource.sol";
import {IXMLRepresentableStatePart} from "../../../IRepresentableState.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IProductDefinitionRegistry} from "./IProductDefinitionRegistry.sol";
import {IProductIndication} from "../ProductIndication/IProductIndication.sol";
import {IProductFactory} from "../ProductFactory/IProductFactory.sol";
import {IClientRegistry} from "../ClientRegistry/IClientRegistry.sol";
import {IProduct} from "../Product/IProduct.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title ProductDefinitionRegistry
 * @notice Registry for product definitions, indication assignments, eligible
 *         trade requests, and product deployment.
 *
 * @dev Each product definition anchors the exact factory and finalized text
 *      resources used for deployment. The registry validates the anchored
 *      components, manages lifecycle state, and deploys products directly
 *      through the selected factory.
 *
 *      Product definition ids are derived as:
 *
 *          keccak256(abi.encode(name, address(this)))
 *
 *      The corresponding state-part id is uint256(productDefinitionId).
 *
 * @author Raphael Prandtl
 */
contract ProductDefinitionRegistry is IProductDefinitionRegistry, IXMLRepresentableStatePart, Ownable2Step, ReentrancyGuard {
    using Strings for uint256;
    using ERC165Checker for address;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a state-part id does not represent a product definition.
    error UnknownPart(uint256 partId);

    /// @notice Thrown when a required hash is zero.
    error ZeroHash(string field);

    /// @notice Thrown when an address has no contract code.
    error EmptyContract(address contractAddress);

    /// @notice Thrown when a contract does not implement the expected interface.
    error InvalidInterface(address contractAddress);

    /// @notice Thrown when a factory is configured for another registry.
    error FactoryNotConfigured(address configuredRegistry);

    /// @notice Thrown when an external validation call fails.
    error ContractCallFailed(address contractAddress, string functionName);

    /// @notice Thrown when a text resource is not finalized.
    error ResourceNotFinalized(address resource);

    /// @notice Thrown when a text resource has an unexpected type.
    error InvalidResourceType(address resource, bytes32 expected, bytes32 actual);

    /// @notice Thrown when a factory does not accept an indication category.
    error UnsupportedIndicationCategory(address productIndication, bytes32 indicationCategory);

    /// @notice Thrown when an indication cannot be assigned in its current status.
    error InvalidIndicationStatus(address productIndication, IProductIndication.IndicationStatus status);

    /// @notice Thrown when a product definition has no product indication assigned.
    error MissingProductIndication(bytes32 productDefinitionId);

    /// @notice Thrown when a factory exposes an invalid specification.
    error InvalidProductFactory(address factory);

    /// @notice Thrown when the caller is not eligible for the product definition.
    error ClientNotEligible(address client, bytes32 productDefinitionId);

    /// @notice Thrown when querying a trade that does not exist.
    error UnknownTrade(bytes32 tradeId);

    /// @notice Thrown when a tradeId has already been used for a deployment.
    error TradeIdAlreadyUsed(bytes32 tradeId);

    error ProductDeploymentFailed(address factory, bytes32 tradeId);

    error InvalidDeployedProduct(address product);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a rendered product-definition state part changes.
    event StatePartUpdated(address indexed sender, address indexed stateContract, uint256 indexed partId, uint256 partVersion);

    /// @notice Emitted when a product definition's product indication is assigned or replaced.
    event ProductIndicationAssigned(bytes32 indexed productDefinitionId, address indexed productIndication, bytes32 indicationId);

    /// @notice Emitted when a product definition's indication is cleared.
    event ProductIndicationCleared(bytes32 indexed productDefinitionId);

    /// @notice Emitted when a trade request creates a product.
    event TradeRequestCreated(bytes32 indexed tradeId, address indexed productProvider, address indexed client, bytes32 productDefinitionId, address product);

    // ------------------------------ Storage ------------------------------ */

    /// @dev partId is not stored because it is derivable from the key.
    struct ProductDefinitionStorage {
        ProductDefinitionStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string name;
        uint256 version;
        ProductDefinition productDefinition;
    }

    /// @notice Indication assigned to a product definition.
    struct ProductIndicationAssignment {
        address productIndication;
        bytes32 indicationId;
        uint256 partId;
    }

    /**
     * @notice Client-supplied parameters for a trade request.
     * @param productDefinitionId Product definition to trade against.
     * @param productPayload ABI-encoded product payload.
     */
    struct TradeRequestParams {
        bytes32 productDefinitionId;
        bytes productPayload;
    }

    mapping(bytes32 => ProductDefinitionStorage) internal _productDefinitionsById;

    /// @dev Keyed by the same productDefinitionId as _productDefinitionsById.
    mapping(bytes32 => ProductIndicationAssignment) internal _indicationsByDefinitionId;

    /// @notice Client registry used for eligibility checks.
    address public immutable clientRegistryAddress;

    /// @dev Monotonic nonce feeding tradeId derivation.
    uint256 internal _tradeIdNonce;

    /// @dev Maps a trade id to its deployed product.
    mapping(bytes32 => address) internal _productByTradeId;

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param owner_                 Initial owner / product provider.
     * @param clientRegistryAddress_ Client registry for eligibility checks.
     */
    constructor(address owner_, address clientRegistryAddress_) Ownable(owner_) {
        _validateContractAddress(clientRegistryAddress_, "clientRegistry");
        clientRegistryAddress = clientRegistryAddress_;
    }

    // ------------------------------ Product Definition Publication and Lifecycle Management ------------------------------ */

    function publishProductDefinition(ProductDefinitionPublicationParams calldata params) external override onlyOwner returns (bytes32 productDefinitionId) {
        _validateProductDefinitionPublicationParams(params);

        productDefinitionId = _productDefinitionId(params.name);
        ProductDefinitionStorage storage definitionStorage = _productDefinitionsById[productDefinitionId];
        if (definitionStorage.status != ProductDefinitionStatus.Unknown) {
            revert ProductDefinitionAlreadyExists(productDefinitionId);
        }

        definitionStorage.status = ProductDefinitionStatus.Active;
        definitionStorage.name = params.name;
        definitionStorage.publishedAt = uint64(block.timestamp);
        definitionStorage.productDefinition = params.productDefinition;

        _touchProductDefinition(definitionStorage);

        emit ProductDefinitionPublished(productDefinitionId, params.productDefinition.productFactory, params.productDefinition.productTermsTemplate, params.productDefinition.productDocumentationTemplate);
        emit ProductDefinitionStatusChanged(productDefinitionId, ProductDefinitionStatus.Unknown, ProductDefinitionStatus.Active);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definitionStorage.version);
    }

    function updateProductDefinition(bytes32 productDefinitionId, ProductDefinition calldata productDefinition) external override onlyOwner {
        _validateProductDefinition(productDefinition);

        ProductDefinitionStorage storage definitionStorage = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definitionStorage.status);
        // Revalidate existing indication assignment if factory is updated
        ProductIndicationAssignment storage assignment = _indicationsByDefinitionId[productDefinitionId];
        if (assignment.productIndication != address(0) && definitionStorage.productDefinition.productFactory != productDefinition.productFactory) {
            _validateProductIndication(productDefinition.productFactory, assignment.productIndication, assignment.indicationId);
        }

        definitionStorage.productDefinition = productDefinition;
        _touchProductDefinition(definitionStorage);

        emit ProductDefinitionUpdated(productDefinitionId, productDefinition.productFactory, productDefinition.productTermsTemplate, productDefinition.productDocumentationTemplate, definitionStorage.version);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definitionStorage.version);
    }

    function setProductDefinitionStatus(bytes32 productDefinitionId, ProductDefinitionStatus newStatus) external override onlyOwner {
        ProductDefinitionStorage storage definitionStorage = _existingProductDefinition(productDefinitionId);
        ProductDefinitionStatus oldStatus = definitionStorage.status;

        if (oldStatus == newStatus) {
            return;
        }
        _validateStatusTransition(oldStatus, newStatus);

        definitionStorage.status = newStatus;
        _touchProductDefinition(definitionStorage);

        emit ProductDefinitionStatusChanged(productDefinitionId, oldStatus, newStatus);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definitionStorage.version);
    }

    // ------------------------------ Product Definition Read API ------------------------------ */

    function getProductDefinition(bytes32 productDefinitionId) external view override returns (ProductDefinitionView memory) {
        ProductDefinitionStorage storage definitionStorage = _existingProductDefinition(productDefinitionId);
        return ProductDefinitionView({
            status: definitionStorage.status,
            publishedAt: definitionStorage.publishedAt,
            updatedAt: definitionStorage.updatedAt,
            name: definitionStorage.name,
            partId: _partIdFromProductDefinitionId(productDefinitionId),
            version: definitionStorage.version,
            productDefinition: definitionStorage.productDefinition
        });
    }

    function getProductFactoryByDefinitionId(bytes32 productDefinitionId) external view override returns (address productFactory) {
        return _existingProductDefinition(productDefinitionId).productDefinition.productFactory;
    }

    function getProductDefinitionStatus(bytes32 productDefinitionId) external view override returns (ProductDefinitionStatus) {
        return _productDefinitionsById[productDefinitionId].status;
    }

    // ------------------------------ Product Indication Assignment ------------------------------ */

    /// @notice Assigns (or replaces) the product indication of a product definition.
    function setProductIndication(bytes32 productDefinitionId, address productIndication, bytes32 indicationId) external onlyOwner {
        ProductDefinitionStorage storage definitionStorage = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definitionStorage.status);

        uint256 partId = _validateProductIndication(definitionStorage.productDefinition.productFactory, productIndication, indicationId);

        ProductIndicationAssignment storage assignment = _indicationsByDefinitionId[productDefinitionId];
        assignment.productIndication = productIndication;
        assignment.indicationId = indicationId;
        assignment.partId = partId;

        _touchProductDefinition(definitionStorage);

        emit ProductIndicationAssigned(productDefinitionId, productIndication, indicationId);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definitionStorage.version);
    }

    /// @notice Clears the indication assigned to a product definition.
    function clearProductIndication(bytes32 productDefinitionId) external onlyOwner {
        ProductDefinitionStorage storage definitionStorage = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definitionStorage.status);

        _existingProductIndicationAssignment(productDefinitionId);
        delete _indicationsByDefinitionId[productDefinitionId];

        _touchProductDefinition(definitionStorage);

        emit ProductIndicationCleared(productDefinitionId);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definitionStorage.version);
    }

    /**
     * @notice Returns the indication assigned to a product definition.
     * @dev Does not revalidate the indication's current lifecycle status.
     */
    function productIndicationOfDefinition(bytes32 productDefinitionId) external view returns (address productIndication, bytes32 indicationId, uint256 partId) {
        ProductIndicationAssignment storage assignment = _existingProductIndicationAssignment(productDefinitionId);
        return (assignment.productIndication, assignment.indicationId, assignment.partId);
    }

    // ------------------------------ Trade Request Creation ------------------------------ */

    /**
     * @notice Creates a trade request and deploys the corresponding product.
     * @dev The caller is the client and the registry owner is the product provider.
     */
    function createTradeRequest(TradeRequestParams calldata params) external nonReentrant returns (bytes32 tradeId, address product) {
        bytes32 productDefinitionId = params.productDefinitionId;

        ProductDefinitionStorage storage definitionStorage = _existingProductDefinition(productDefinitionId);
        if (definitionStorage.status != ProductDefinitionStatus.Active) {
            revert ProductDefinitionNotActive(productDefinitionId, definitionStorage.status);
        }

        address client = msg.sender;
        if (!_isEligibleClient(client, productDefinitionId)) {
            revert ClientNotEligible(client, productDefinitionId);
        }

        ProductDefinition memory productDefinition = definitionStorage.productDefinition;
        IProductFactory factory = IProductFactory(productDefinition.productFactory);

        address productProvider = owner();
        tradeId = _nextTradeId(client, productDefinitionId);

        if (_productByTradeId[tradeId] != address(0)) {
            revert TradeIdAlreadyUsed(tradeId);
        }

        bytes32 deploymentStateHash = _deploymentStateHash(tradeId, productProvider, client, productDefinitionId, definitionStorage.version,
            productDefinition, params.productPayload);

        product = factory.deployProduct(
            ProductDeploymentParams({
                common: CommonDeploymentParams({
                productRegistry: address(this),
                tradeId: tradeId,
                productProvider: productProvider,
                client: client,
                productDefinitionId: productDefinitionId,
                productDefinitionVersion: definitionStorage.version,
                productTermsTemplate: productDefinition.productTermsTemplate,
                productDocumentationTemplate: productDefinition.productDocumentationTemplate,
                deploymentStateHash: deploymentStateHash
            }),
                productPayload: params.productPayload
            })
        );
        // Verify external factory result
        if (product == address(0) || product.code.length == 0) {
            revert ProductDeploymentFailed(address(factory), tradeId);
        }
        if (!factory.isFactoryDeployedProduct(product)) {
            revert InvalidDeployedProduct(product);
        }
        // Validate immutable common deployment parameters
        IProduct deployedProduct = IProduct(product);
        if (deployedProduct.productRegistry() != address(this) ||
        deployedProduct.productFactory() != address(factory) ||
        deployedProduct.tradeId() != tradeId ||
        deployedProduct.productProvider() != productProvider ||
        deployedProduct.client() != client ||
        deployedProduct.productDefinitionId() != productDefinitionId ||
        deployedProduct.productDefinitionVersion() != definitionStorage.version ||
        deployedProduct.productTermsTemplate() != productDefinition.productTermsTemplate ||
        deployedProduct.productDocumentationTemplate() != productDefinition.productDocumentationTemplate ||
        deployedProduct.deploymentStateHash() != deploymentStateHash) {
            revert InvalidDeployedProduct(product);
        }

        _productByTradeId[tradeId] = product;
        emit TradeRequestCreated(tradeId, productProvider, client, productDefinitionId, product);
    }

    /// @notice Returns the product instance deployed for a trade.
    function productOf(bytes32 tradeId) external view returns (address product) {
        product = _productByTradeId[tradeId];
        if (product == address(0)) {
            revert UnknownTrade(tradeId);
        }
    }

    // ------------------------------ XML View ------------------------------ */

    function statePartXmlTemplate(uint256 partId) external view override returns (string memory) {
        bytes32 productDefinitionId = _productDefinitionIdFromPartId(partId);
        ProductDefinitionStorage storage definition = _productDefinitionsById[productDefinitionId];
        if (definition.status == ProductDefinitionStatus.Unknown) {
            revert UnknownPart(partId);
        }
        return _productDefinitionStateXml(productDefinitionId, definition);
    }


    /// @notice Returns the XML representation of a product definition.
    function _productDefinitionStateXml(bytes32 productDefinitionId, ProductDefinitionStorage storage definitionStorage) internal view returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<ProductDefinition xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\"",
            " productDefinitionId=\"", _bytes32ToHexString(productDefinitionId), "\"",
            " status=\"", uint256(definitionStorage.status).toString(), "\"",
            " productDefinitionVersion=\"", definitionStorage.version.toString(), "\"",
            " updatedAt=\"", uint256(definitionStorage.updatedAt).toString(), "\"",
            ">",
            "<ProductFactory contractAddress=\"", Strings.toHexString(definitionStorage.productDefinition.productFactory),
            "\"/>",
            "<ProductResources>",
                "<ProductTermsTemplate>",
                    _include(definitionStorage.productDefinition.productTermsTemplate),
                "</ProductTermsTemplate>",
                _resourceReference(
                    "ProductDocumentationTemplate",
                    definitionStorage.productDefinition.productDocumentationTemplate
                ),
            "</ProductResources>",
            _productIndicationAssignmentXml(productDefinitionId),
            "</ProductDefinition>"
        );
    }

    function _include(address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory href = textResource.web3Url();
        string memory integrity = string.concat(
            "keccak256-", _bytes32ToHexString(textResource.contentHash())
        );
        return string.concat(
            "<xi:include href=\"", href,
            "\" parse=\"text\" evmstate:integrity=\"", integrity, "\"/>"
        );
    }

    function _productIndicationAssignmentXml(bytes32 productDefinitionId) internal view returns (string memory) {
        ProductIndicationAssignment storage assignment = _indicationsByDefinitionId[productDefinitionId];
        if (assignment.productIndication == address(0)) {
            return "<ProductIndicationAssignment assigned=\"false\"/>";
        }

        return string.concat(
            "<ProductIndicationAssignment assigned=\"true\"",
            " contractAddress=\"", Strings.toHexString(assignment.productIndication), "\"",
            " indicationId=\"", _bytes32ToHexString(assignment.indicationId), "\"",
            " partId=\"", assignment.partId.toString(), "\"",
            "/>"
        );
    }

    /// @notice Returns an XML reference to a finalized text resource.
    function _resourceReference(string memory elementName, address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory integrity = string.concat("keccak256-", uint256(textResource.contentHash()).toHexString(32));
        return string.concat(
            "<",
            elementName,
            " href=\"",
            textResource.web3Url(),
            "\" integrity=\"",
            integrity,
            "\"/>"
        );
    }

    // ------------------------------ Internal Key / Hash Logic ------------------------------ */

    function computeProductDefinitionId(string calldata name) external view override returns (bytes32 productDefinitionId) {
        return _productDefinitionId(name);
    }

    function _productDefinitionId(string memory name) internal view returns (bytes32) {
        return keccak256(abi.encode(name, address(this)));
    }

    function _productDefinitionIdFromPartId(uint256 partId) internal pure returns (bytes32) {
        return bytes32(partId);
    }

    function _partIdFromProductDefinitionId(bytes32 productDefinitionId) internal pure returns (uint256) {
        return uint256(productDefinitionId);
    }

    function _touchProductDefinition(ProductDefinitionStorage storage definitionStorage) internal {
        unchecked { definitionStorage.version += 1; }
        definitionStorage.updatedAt = uint64(block.timestamp);
    }

    // ------------------------------ Client Validation ------------------------------ */

    function _isEligibleClient(address client, bytes32 productDefinitionId) internal view returns (bool) {
        return IClientRegistry(clientRegistryAddress).isEligibleClient(client, productDefinitionId);
    }

    // ------------------------------ Internal Trade Helpers ------------------------------ */

    function _nextTradeId(address client, bytes32 productDefinitionId) internal returns (bytes32) {
        unchecked { ++_tradeIdNonce; }
        return keccak256(abi.encode(address(this), block.chainid, _tradeIdNonce, client, productDefinitionId));
    }

    /// @notice Computes the integrity hash anchored in the deployed product.
    function _deploymentStateHash(bytes32 tradeId, address productProvider, address client, bytes32 productDefinitionId, uint256 productDefinitionVersion, ProductDefinition memory productDefinition, bytes calldata productPayload) internal view returns (bytes32) {
        bytes32 productTermsTemplateContentHash = ITextResource(productDefinition.productTermsTemplate).contentHash();
        bytes32 productDocumentationTemplateContentHash = ITextResource(productDefinition.productDocumentationTemplate).contentHash();

        return keccak256(abi.encode(address(this), block.chainid, tradeId, productProvider, client, productDefinitionId, productDefinitionVersion, productDefinition.productFactory,
            productDefinition.productTermsTemplate, productTermsTemplateContentHash, productDefinition.productDocumentationTemplate, productDocumentationTemplateContentHash, keccak256(productPayload)));
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    function _existingProductDefinition(bytes32 productDefinitionId) internal view returns (ProductDefinitionStorage storage definition) {
        definition = _productDefinitionsById[productDefinitionId];
        if (definition.status == ProductDefinitionStatus.Unknown) {
            revert UnknownProductDefinition(productDefinitionId);
        }
    }

    function _existingProductIndicationAssignment(bytes32 productDefinitionId) internal view returns (ProductIndicationAssignment storage assignment) {
        assignment = _indicationsByDefinitionId[productDefinitionId];
        if (assignment.productIndication == address(0)) {
            revert MissingProductIndication(productDefinitionId);
        }
    }

    function _ensureProductDefinitionWritable(bytes32 productDefinitionId, ProductDefinitionStatus status) internal pure {
        if (status == ProductDefinitionStatus.Retired || status == ProductDefinitionStatus.Archived) {
            revert ProductDefinitionNotWritable(productDefinitionId, status);
        }
    }

    /**
     * @dev Allowed transitions:
     *      Active    -> Suspended | Retired
     *      Suspended -> Active | Retired
     *      Retired    -> Archived
     *      Archived  -> (terminal)
     */
    function _validateStatusTransition(ProductDefinitionStatus  oldStatus, ProductDefinitionStatus  newStatus) internal pure {
        bool valid = (oldStatus == ProductDefinitionStatus.Active && (newStatus == ProductDefinitionStatus.Suspended || newStatus == ProductDefinitionStatus.Retired)) ||
            (oldStatus == ProductDefinitionStatus.Suspended && (newStatus == ProductDefinitionStatus.Active || newStatus == ProductDefinitionStatus.Retired)) ||
            (oldStatus == ProductDefinitionStatus.Retired && newStatus == ProductDefinitionStatus.Archived);
        if (!valid) revert InvalidStatusTransition(oldStatus, newStatus);
    }

    function _validateProductDefinitionPublicationParams(ProductDefinitionPublicationParams calldata params) internal view {
        if (bytes(params.name).length == 0) {
            revert EmptyString("name");
        }
        _validateProductDefinition(params.productDefinition);
    }

    function _validateProductDefinition(ProductDefinition calldata productDefinition) internal view {
        IProductFactory factory = IProductFactory(productDefinition.productFactory);
        _validateProductFactory(productDefinition.productFactory);
        _validateTextResource(productDefinition.productTermsTemplate, factory.productTermsTemplateResourceType());
        _validateTextResource(productDefinition.productDocumentationTemplate, factory.productDocumentationTemplateResourceType());
    }

    function _validateProductFactory(address factory) internal view {
        _validateContractAddress(factory, "productFactory");
        // Must advertise IProductFactory via ERC-165
        if (!factory.supportsInterface(type(IProductFactory).interfaceId)) {
            revert InvalidInterface(factory);
        }
        IProductFactory productFactory = IProductFactory(factory);
        // Factory must be configured for this registry
        try productFactory.productRegistryAddress() returns (address configuredAddress) {
            if (configuredAddress != address(this)) revert FactoryNotConfigured(configuredAddress);
        } catch {
            revert ContractCallFailed(factory, "productRegistryAddress()");
        }
        // Factory must implement meaningful product specifications: productPayloadSchema, productTermsTemplateResourceType, productDocumentationTemplateResourceType
        if (bytes(productFactory.productPayloadSchema()).length == 0) {
            revert InvalidProductFactory(factory);
        }
        if (productFactory.productTermsTemplateResourceType() == bytes32(0) || productFactory.productDocumentationTemplateResourceType() == bytes32(0)) {
            revert InvalidProductFactory(factory);
        }
    }

    function _validateTextResource(address resource, bytes32 expectedResourceType) internal view {
        _validateContractAddress(resource, "textResource");
        // Must advertise ITextResource via ERC-165
        if(!resource.supportsInterface(type(ITextResource).interfaceId)) {
            revert InvalidInterface(resource);
        }
        ITextResource textResource = ITextResource(resource);
        // TextResource must be finalized (immutable).
        try textResource.isFinalized() returns (bool finalized) {
            if (!finalized)  revert ResourceNotFinalized(resource);
        } catch {
            revert ContractCallFailed(resource, "isFinalized()");
        }
        // Must carry an accepted resource type
        try textResource.resourceType() returns (bytes32 actualResourceType) {
            if (actualResourceType != expectedResourceType) revert InvalidResourceType(resource, expectedResourceType, actualResourceType);
        } catch {
            revert ContractCallFailed(resource, "resourceType()");
        }
    }

    function _validateProductIndication(address productFactory, address productIndication, bytes32 indicationId) internal view returns (uint256 partId) {
        _validateContractAddress(productIndication, "productIndication");
        if (indicationId == bytes32(0)) revert ZeroHash("indicationId");
        // Must advertise IProductIndication via ERC-165
        if (!productIndication.supportsInterface(type(IProductIndication).interfaceId)) {
            revert InvalidInterface(productIndication);
        }
        IProductIndication indication = IProductIndication(productIndication);
        // Indication must be in valid state
        try indication.indicationStatus(indicationId) returns (IProductIndication.IndicationStatus status) {
            if (status != IProductIndication.IndicationStatus.Active && status != IProductIndication.IndicationStatus.Suspended) {
                revert InvalidIndicationStatus(productIndication, status);
            }
        } catch {
            revert ContractCallFailed(productIndication, "indicationStatus()");
        }
        // Indication must be of a category accepted by the product / product factory
        try indication.indicationCategory() returns (bytes32 category) {
            if (!IProductFactory(productFactory).isAcceptedIndicationCategory(category)) {
                revert UnsupportedIndicationCategory(productIndication, category);
            }
        } catch {
            revert ContractCallFailed(productIndication, "indicationCategory()");
        }
        // Get partId of the indication (used for rendering)
        try indication.partIdForIndication(indicationId) returns (uint256 resolvedPartId) {
            partId = resolvedPartId;
        } catch {
            revert ContractCallFailed(productIndication, "partIdForIndication()");
        }
    }

    function _validateContractAddress(address contractAddress, string memory field) internal view {
        if (contractAddress == address(0)) revert ZeroAddress(field);
        if (contractAddress.code.length == 0) revert EmptyContract(contractAddress);
    }

    // ------------------------------ String Helpers ------------------------------ */

    function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        return uint256(value).toHexString(32);
    }

}
