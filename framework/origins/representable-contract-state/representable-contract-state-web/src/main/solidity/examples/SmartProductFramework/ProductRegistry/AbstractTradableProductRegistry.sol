// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITextResource} from "../../../resources/ITextResource.sol";

import {AbstractIndicatedProductRegistry} from "./AbstractIndicatedProductRegistry.sol";
import {IProductFactory} from "../ProductFactory/IProductFactory.sol";
import {IClientRegistry} from "../ClientRegistry/IClientRegistry.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title AbstractTradableProductRegistry.sol
 * @notice Layer 3: on top of product definitions and product indications,
 *         lets eligible clients create trade requests that deploy concrete
 *         product instances via the product factory.
 *
 * @dev Persists a tradeId -> product instance record and anchors the exact
 *      product definition state in force at trade time.
 *      Still product-agnostic: the concrete contract implements the
 *      _isAcceptedResourceType / _isAcceptedIndication hooks.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractTradableProductRegistry is AbstractIndicatedProductRegistry {
    // ------------------------------ Immutable State ------------------------------ */

    /// @notice Client registry consulted for eligibility.
    address public immutable clientRegistryAddress;

    // ------------------------------ Mutable State ------------------------------ */

    /**
     * @notice Product factory used to deploy product instances.
     *         Owner-settable and replaceable (see setProductFactory).
     */
    address public productFactory;

    /// @dev Monotonic nonce feeding tradeId derivation.
    uint256 internal _tradeIdNonce;

    /// @dev tradeId -> deployed product instance address.
    mapping(bytes32 => address) internal _productByTradeId;

    // ------------------------------ Structs ------------------------------ */

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


    // ------------------------------ Custom Errors ------------------------------ */

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

    /// @notice Emitted when the product factory is set or replaced.
    event ProductFactorySet(address indexed previousFactory, address indexed newFactory);

    /// @notice Emitted when a trade request is created and its product deployed.
    event TradeRequestCreated(bytes32 indexed tradeId, address indexed productProvider, address indexed client, bytes32 productDefinitionId, bytes32 productTypeId, address product);

    // ------------------------------ Constructor / Modifiers ------------------------------ */

    /**
     * @param owner_                   Initial owner / product provider.
     * @param clientRegistryAddress_ Client registry for eligibility checks.
     */
    constructor(address owner_, address clientRegistryAddress_)
    AbstractIndicatedProductRegistry(owner_) {
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

        ProductDefinitionResources  memory resources = definition.resources;
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

    // ------------------------------ Read API ------------------------------ */

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

    // ------------------------------ Client Validation ------------------------------ */

    function _isEligibleClient(address client, bytes32 productDefinitionId) internal view returns (bool) {
        return IClientRegistry(clientRegistryAddress).isEligibleClient(client, productDefinitionId);
    }

    // ------------------------------ Internal Mutation Helpers ------------------------------ */

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
}
