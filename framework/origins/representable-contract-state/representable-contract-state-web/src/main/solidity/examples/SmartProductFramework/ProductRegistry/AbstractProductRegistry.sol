// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITextResource} from "../../../resources/ITextResource.sol";
import {IXMLRepresentableStatePart} from "../../../IRepresentableState.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IProductDefinitionRegistry} from "./IProductDefinitionRegistry.sol";
import {IProductIndication} from "../ProductIndication/IProductIndication.sol";
import {IProductFactory} from "../ProductFactory/IProductFactory.sol";
import {IClientRegistry} from "../ClientRegistry/IClientRegistry.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title AbstractProductRegistry.sol
 * @notice Product-agnostic registry implementation covering product-definition
 *         publication and lifecycle, product-indication assignment, eligible
 *         client trade requests, and product deployment.
 *
 * @dev Product-specific policy remains in the concrete registry through the
 *      _isAcceptedResourceType and _isAcceptedIndication hooks.
 *
 * @dev PRODUCT DEFINITION ID / PART ID
 *      productDefinitionId == keccak256(abi.encode(name, address(this)))
 *      partId    == uint256(productDefinitionId)   (bijective; not stored)
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProductRegistry is IProductDefinitionRegistry, IXMLRepresentableStatePart, Ownable2Step {
    using Strings for uint256;

    // ------------------------------ Enums ------------------------------ */

    /// @notice Logical slot a resource occupies within a product definition.
    enum ResourceSlot {
        Unknown,
        ProductTermsTemplate,
        ProductDocumentationTemplate
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice ERC-8100: requested partId does not map to a known product definition.
    error UnknownPart(uint256 partId);

    /// @notice Resource address has no contract code.
    error InvalidResourceContract(address resource);

    /// @notice Resource does not implement the ITextResource interface.
    error InvalidResourceInterface(address resource);

    /// @notice Resource is not finalized (and thus not immutable).
    error ResourceNotFinalized(address resource);

    /// @notice Resource type is not accepted for the given slot.
    error InvalidResourceType(address resource, ResourceSlot slot, bytes32 actualResourceType);

    /// @notice Thrown when the indication address has no contract code.
    error InvalidIndicationContract(address productIndication);

    /// @notice Thrown when the target does not implement IProductIndication.
    error InvalidIndicationInterface(address productIndication);

    /**
     * @notice Thrown when the indication category is not accepted for the
     *         product definition's product type.
     */
    error InvalidIndicationCategory(address productIndication, bytes32 indicationCategory);

    /**
     * @notice Thrown when the referenced indication is not in an assignable
     *         status. Assignable statuses are Active and Suspended.
     */
    error InvalidIndicationStatus(address productIndication, IProductIndication.IndicationStatus status);

    /// @notice Thrown when a product definition has no product indication assigned.
    error MissingProductIndication(bytes32 productDefintionId);

    /// @notice Thrown when a trade is attempted before a factory is set.
    error MissingProductFactory();

    /// @notice Thrown when the provided client registry address is invalid.
    error MissingClientRegistry();

    /**
     * @notice Thrown when the provided factory is invalid or does not point
     *         back at this registry.
     */
    error InvalidProductFactory(address factory);

    /// @notice Thrown when the caller is not eligible for the product definition.
    error ClientNotEligible(address client, bytes32 productDefinitionId);

    /// @notice Thrown when the factory cannot deploy the product definition's type.
    error ProductTypeNotDeployable(bytes32 productTypeId);

    /// @notice Thrown when querying a trade that does not exist.
    error UnknownTrade(bytes32 tradeId);

    // ------------------------------ Events ------------------------------ */

    /// @notice Generic ERC-8100-style state-part update event.
    event StatePartUpdated(address indexed sender, address indexed stateContract, uint256 indexed partId, uint256 partVersion);

    /// @notice Emitted when a product definition's product indication is assigned or replaced.
    event ProductIndicationAssigned(bytes32 indexed productDefinitionId, address indexed productIndication, bytes32 indicationId);

    /// @notice Emitted when the product factory is set or replaced.
    event ProductFactorySet(address indexed previousFactory, address indexed newFactory);

    /// @notice Emitted when a trade request is created and its product deployed.
    event TradeRequestCreated(bytes32 indexed tradeId, address indexed productProvider, address indexed client, bytes32 productDefinitionId, bytes32 productTypeId, address product);

    // ------------------------------ Storage ------------------------------ */

    /// @dev partId is not stored because it is derivable from the key.
    struct ProductDefinitionStorage {
        ProductDefinitionStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string name;
        uint256 version;
        ProductDefinitionResources resources;
    }

    /// @notice Per-product-definition indication reference.
    struct ProductIndicationAssignment {
        address productIndication;
        bytes32 indicationId;
        uint256 partId;
    }

    /**
     * @notice Client-supplied parameters for a trade request.
     * @param productDefinitionId       Product definition to trade against.
     * @param productSpecificSchemaHash Hash of the product-specific payload schema.
     * @param productSpecificPayload    Product-specific deployment payload.
     */
    struct TradeRequestParams {
        bytes32 productDefinitionId;
        bytes32 productSpecificSchemaHash;
        bytes productSpecificPayload;
    }

    mapping(bytes32 => ProductDefinitionStorage) internal _productDefinitionsById;

    /// @dev Keyed by the same productDefinitionId as _productDefinitionsById.
    mapping(bytes32 => ProductIndicationAssignment) internal _indicationsByDefinitionId;

    /// @notice Client registry consulted for eligibility.
    address public immutable clientRegistryAddress;

    /**
     * @notice Product factory used to deploy product instances.
     *         Owner-settable and replaceable (see setProductFactory).
     */
    address public productFactory;

    /// @dev Monotonic nonce feeding tradeId derivation.
    uint256 internal _tradeIdNonce;

    /// @dev tradeId -> deployed product instance address.
    mapping(bytes32 => address) internal _productByTradeId;

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param owner_                 Initial owner / product provider.
     * @param clientRegistryAddress_ Client registry for eligibility checks.
     */
    constructor(address owner_, address clientRegistryAddress_) Ownable(owner_) {
        if (clientRegistryAddress_ == address(0) || clientRegistryAddress_.code.length == 0) {
            revert MissingClientRegistry();
        }
        clientRegistryAddress = clientRegistryAddress_;
    }

    modifier onlyAfterFactorySet() {
        if (productFactory == address(0)) {
            revert MissingProductFactory();
        }
        _;
    }

    // ------------------------------ Product Definition Publication and Lifecycle Management ------------------------------ */

    function publishProductDefinition(ProductDefinitionPublicationParams calldata params) external override onlyOwner returns (bytes32 productDefinitionId) {
        _validateProductDefinitionPublicationParams(params);

        productDefinitionId = _productDefinitionId(params.name);
        ProductDefinitionStorage storage definition = _productDefinitionsById[productDefinitionId];
        if (definition.status != ProductDefinitionStatus.Unknown) {
            revert ProductDefinitionAlreadyExists(productDefinitionId);
        }

        definition.status = ProductDefinitionStatus.Active;
        definition.name = params.name;
        definition.publishedAt = uint64(block.timestamp);
        definition.resources = params.resources;

        _touchProductDefinition(definition);

        emit ProductDefinitionPublished(productDefinitionId, params.resources.productTypeId, params.resources.productTermsTemplate, params.resources.productDocumentationTemplate);
        emit ProductDefinitionStatusChanged(productDefinitionId, ProductDefinitionStatus.Unknown, ProductDefinitionStatus.Active);
        emit StatePartUpdated(msg.sender, address(this),             _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    function updateProductDefinitionResources(bytes32 productDefinitionId, ProductDefinitionResources calldata resources) external override onlyOwner {
        _validateProductDefinitionResources(resources);

        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definition.status);

        definition.resources = resources;
        _touchProductDefinition(definition);

        emit ProductDefinitionResourcesUpdated(productDefinitionId, resources.productTypeId, resources.productTermsTemplate, resources.productDocumentationTemplate, definition.version);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    function setProductDefinitionStatus(bytes32 productDefinitionId, ProductDefinitionStatus newStatus) external override onlyOwner {
        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        ProductDefinitionStatus oldStatus = definition.status;

        if (oldStatus == newStatus) {
            return;
        }
        _validateStatusTransition(oldStatus, newStatus);

        definition.status = newStatus;
        _touchProductDefinition(definition);

        emit ProductDefinitionStatusChanged(productDefinitionId, oldStatus, newStatus);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    // ------------------------------ Product Definition Read API ------------------------------ */

    function getProductDefinition(bytes32 productDefinitionId) external view override returns (ProductDefinitionView memory) {
        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        return ProductDefinitionView({
            status: definition.status,
            publishedAt: definition.publishedAt,
            updatedAt: definition.updatedAt,
            name: definition.name,
            partId: _partIdFromProductDefinitionId(productDefinitionId),
            version: definition.version,
            resources: definition.resources
        });
    }

    function getProductDefinitionStatus(bytes32 productDefinitionId) external view override returns (ProductDefinitionStatus) {
        return _productDefinitionsById[productDefinitionId].status;
    }

    function productTypeByDefinitionId(bytes32 productDefinitionId) external view override returns (bytes32 productTypeId) {
        return _existingProductDefinition(productDefinitionId).resources.productTypeId;
    }

    // ------------------------------ Product Indication Assignment ------------------------------ */

    /// @notice Assigns (or replaces) the product indication of a product definition.
    function assignProductIndication(bytes32 productDefinitionId, address productIndication, bytes32 indicationId) external onlyOwner {
        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definition.status);

        uint256 partId = _validateProductIndication(definition.resources.productTypeId, productIndication, indicationId);

        ProductIndicationAssignment storage assignment = _indicationsByDefinitionId[productDefinitionId];
        assignment.productIndication = productIndication;
        assignment.indicationId = indicationId;
        assignment.partId = partId;

        _touchProductDefinition(definition);

        emit ProductIndicationAssigned(productDefinitionId, productIndication, indicationId);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    /**
     * @notice Returns the product indication assigned to a product definition,
     *         together with the partId to render it on the indication contract.
     * @dev Does not check the indication's current status — consumers should
     *      verify liveness if required.
     */
    function productIndicationOfDefinition(bytes32 productDefinitionId) external view returns (address productIndication, bytes32 indicationId, uint256 partId) {
        ProductIndicationAssignment storage assignment = _existingProductIndicationAssignment(productDefinitionId);
        return (assignment.productIndication, assignment.indicationId, assignment.partId);
    }

    // ------------------------------ Trade Request Creation ------------------------------ */

    /**
     * @notice Creates a trade request, validates the product definition,
     *         the caller's eligibility and the product type, then deploys the
     *         product instance and records the tradeId -> product mapping.
     * @dev The caller (msg.sender) is the client; owner() is the product provider.
     */
    function createTradeRequest(TradeRequestParams calldata params) external onlyAfterFactorySet returns (bytes32 tradeId, address product) {
        bytes32 productDefinitionId = params.productDefinitionId;

        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        if (definition.status != ProductDefinitionStatus.Active) {
            revert ProductDefinitionNotActive(productDefinitionId, definition.status);
        }

        address client = msg.sender;
        if (!_isEligibleClient(client, productDefinitionId)) {
            revert ClientNotEligible(client, productDefinitionId);
        }

        ProductDefinitionResources memory resources = definition.resources;
        address factory = productFactory;
        if (!IProductFactory(factory).canDeployProduct(resources.productTypeId)) {
            revert ProductTypeNotDeployable(resources.productTypeId);
        }

        address productProvider = owner();
        tradeId = _nextTradeId(client, productDefinitionId);

        bytes32 deploymentStateHash = _deploymentStateHash(tradeId, productProvider, client, productDefinitionId, definition.version,
            resources, params.productSpecificSchemaHash, params.productSpecificPayload);

        product = IProductFactory(factory).deployProduct(
            ProductDeploymentParams({
                common: CommonDeploymentParams({
                    productRegistry: address(this),
                    tradeId: tradeId,
                    productProvider: productProvider,
                    client: client,
                    productDefinitionId: productDefinitionId,
                    productDefinitionVersion: definition.version,
                    productTermsTemplate: resources.productTermsTemplate,
                    productDocumentationTemplate: resources.productDocumentationTemplate,
                    productTypeId: resources.productTypeId,
                    deploymentStateHash: deploymentStateHash
                }),
                productSpecificSchemaHash: params.productSpecificSchemaHash,
                productSpecificPayload: params.productSpecificPayload
            })
        );

        _productByTradeId[tradeId] = product;

        emit TradeRequestCreated(tradeId, productProvider, client, productDefinitionId, resources.productTypeId, product);
    }

    /// @notice Returns the product instance deployed for a trade.
    function productOf(bytes32 tradeId) external view returns (address product) {
        product = _productByTradeId[tradeId];
        if (product == address(0)) {
            revert UnknownTrade(tradeId);
        }
    }

    // ------------------------------ Factory Management ------------------------------ */

    /**
     * @notice Sets or replaces the product factory.
     * @dev The factory must have code and point back at this registry.
     */
    function setProductFactory(address factory) external onlyOwner {
        if (factory == address(0) || factory.code.length == 0) {
            revert InvalidProductFactory(factory);
        }
        if (IProductFactory(factory).productRegistryAddress() != address(this)) {
            revert InvalidProductFactory(factory);
        }

        emit ProductFactorySet(productFactory, factory);
        productFactory = factory;
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


    /**
     * @dev The registry exposes the product terms template and product
     *      documentation template under role-labelled resource wrappers. It does
     *      not resolve the `evmstate:call` bindings itself (those are served by the
     *      deployed product implementing the declared product type interface).
     */
    function _productDefinitionStateXml(bytes32 productDefinitionId, ProductDefinitionStorage storage definition) internal view returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<ProductDefinition xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\"",
            " productDefinitionId=\"", _bytes32ToHexString(productDefinitionId), "\"",
            " status=\"", uint256(definition.status).toString(), "\"",
            " productDefinitionVersion=\"", definition.version.toString(), "\"",
            " updatedAt=\"", uint256(definition.updatedAt).toString(), "\"",
            ">",
            "<ProductResources>",
                "<ProductTermsTemplate>",
                    _include(definition.resources.productTermsTemplate),
                "</ProductTermsTemplate>",
                "<ProductDocumentationTemplate>",
                    _include(definition.resources.productDocumentationTemplate),
                "</ProductDocumentationTemplate>",
            "</ProductResources>",
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

    function _touchProductDefinition(ProductDefinitionStorage storage definition) internal {
        unchecked { definition.version += 1; }
        definition.updatedAt = uint64(block.timestamp);
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

    /**
     * @dev Integrity anchor recorded in the product instance at deployment.
     *      Binds the trade identity to the exact product definition state
     *      at trade time, including version and immutable resource contents,
     *      and to the agreed product-specific payload, so it can be
     *      independently recomputed and verified later.
     */
    function _deploymentStateHash(bytes32 tradeId, address productProvider, address client, bytes32 productDefinitionId, uint256 productDefinitionVersion, ProductDefinitionResources memory resources, bytes32 productSpecificSchemaHash, bytes calldata productSpecificPayload) internal view returns (bytes32) {
        bytes32 productTermsTemplateContentHash = ITextResource(resources.productTermsTemplate).contentHash();
        bytes32 productDocumentationTemplateContentHash = ITextResource(resources.productDocumentationTemplate).contentHash();

        return keccak256(abi.encode(address(this), block.chainid, tradeId, productProvider, client, productDefinitionId, productDefinitionVersion, resources.productTypeId,
                resources.productTermsTemplate, productTermsTemplateContentHash, resources.productDocumentationTemplate, productDocumentationTemplateContentHash,
                productSpecificSchemaHash, keccak256(productSpecificPayload)));
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    function _existingProductDefinition(bytes32 productDefinitionId) internal view returns (ProductDefinitionStorage storage definition) {
        definition = _productDefinitionsById[productDefinitionId];
        if (definition.status == ProductDefinitionStatus.Unknown) {
            revert UnknownProductDefinition(productDefinitionId);
        }
    }

    function _ensureProductDefinitionWritable(bytes32 productDefinitionId, ProductDefinitionStatus status) internal pure {
        if (status == ProductDefinitionStatus.Retired || status == ProductDefinitionStatus.Archived) {
            revert ProductDefinitionNotWritable(productDefinitionId, status);
        }
    }

    function _existingProductIndicationAssignment(bytes32 productDefinitionId) internal view returns (ProductIndicationAssignment storage assignment) {
        assignment = _indicationsByDefinitionId[productDefinitionId];
        if (assignment.productIndication == address(0)) {
            revert MissingProductIndication(productDefinitionId);
        }
    }

    function _validateProductIndication(bytes32 productTypeId, address productIndication, bytes32 indicationId) internal view returns (uint256 partId) {
        if (productIndication == address(0)) {
            revert ZeroAddress("productIndication");
        }
        if (indicationId == bytes32(0)) {
            revert ZeroHash("indicationId");
        }
        if (productIndication.code.length == 0) {
            revert InvalidIndicationContract(productIndication);
        }

        try IERC165(productIndication).supportsInterface(type(IProductIndication).interfaceId) returns (bool ok) {
            if (!ok) {
                revert InvalidIndicationInterface(productIndication);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        IProductIndication indicationRegistry = IProductIndication(productIndication);

        try indicationRegistry.indicationStatus(indicationId) returns (IProductIndication.IndicationStatus status) {
            if (status != IProductIndication.IndicationStatus.Active && status != IProductIndication.IndicationStatus.Suspended) {
                revert InvalidIndicationStatus(productIndication, status);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        try indicationRegistry.indicationCategory() returns (bytes32 category) {
            if (!_isAcceptedIndication(productTypeId, category)) {
                revert InvalidIndicationCategory(productIndication, category);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        try indicationRegistry.partIdForIndication(indicationId) returns (uint256 resolvedPartId) {
            partId = resolvedPartId;
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }
    }

    /**
     * @dev Allowed transitions:
     *      Active    -> Suspended | Closed
     *      Suspended -> Active | Closed
     *      Closed    -> Archived
     *      Archived  -> (terminal)
     */
    function _validateStatusTransition(ProductDefinitionStatus  oldStatus, ProductDefinitionStatus  newStatus) internal pure {
        if (newStatus == ProductDefinitionStatus .Unknown) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == ProductDefinitionStatus .Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == ProductDefinitionStatus .Retired && newStatus != ProductDefinitionStatus .Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    function _validateProductDefinitionPublicationParams(ProductDefinitionPublicationParams calldata params) internal view {
        if (bytes(params.name).length == 0) {
            revert EmptyString("name");
        }
        _validateProductDefinitionResources(params.resources);
    }

    function _validateProductDefinitionResources(ProductDefinitionResources calldata resources) internal view {
        _validateTextResource(resources.productTermsTemplate, ResourceSlot.ProductTermsTemplate);
        _validateTextResource(resources.productDocumentationTemplate, ResourceSlot.ProductDocumentationTemplate);

        if (resources.productTypeId == bytes32(0)) {
            revert ZeroHash("productTypeId");
        }
    }

    function _validateTextResource(address resource, ResourceSlot slot) internal view {
        if (resource == address(0)) {
            revert ZeroAddress("resource");
        }
        if (resource.code.length == 0) {
            revert InvalidResourceContract(resource);
        }

        // Must advertise ITextResource via ERC-165.
        try IERC165(resource).supportsInterface(type(ITextResource).interfaceId) returns (bool ok) {
            if (!ok) {
                revert InvalidResourceInterface(resource);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }

        ITextResource textResource = ITextResource(resource);

        // Must be finalized (immutable).
        try textResource.isFinalized() returns (bool finalized) {
            if (!finalized) {
                revert ResourceNotFinalized(resource);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }

        // Must carry an accepted resource type for this slot.
        try textResource.resourceType() returns (bytes32 actualResourceType) {
            if (!_isAcceptedResourceType(slot, actualResourceType)) {
                revert InvalidResourceType(resource, slot, actualResourceType);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }
    }

    // ------------------------------ Final-Contract Hook ------------------------------ */

    /// @dev Product-specific rule: which resource types are accepted per slot.
    function _isAcceptedResourceType(ResourceSlot slot, bytes32 resourceType) internal view virtual returns (bool);

    /**
     * @dev Product-specific rule: may an indication of `indicationCategory` be
     *      attached to a product definition of `productTypeId`?
     */
    function _isAcceptedIndication(bytes32 productTypeId, bytes32 indicationCategory) internal view virtual returns (bool);

    // ------------------------------ String Helpers ------------------------------ */

    function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        return uint256(value).toHexString(32);
    }

}
