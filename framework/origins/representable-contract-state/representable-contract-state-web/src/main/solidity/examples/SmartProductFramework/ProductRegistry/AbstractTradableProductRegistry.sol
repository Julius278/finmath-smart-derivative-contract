// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractIndicatedProductRegistry} from "./AbstractIndicatedProductRegistry.sol";
import {IProductFactory} from "../ProductFactory/IProductFactory.sol";
import {IInvestorRegistry} from "../InvestorRegistry/IInvestorRegistry.sol";
import {ITextResource} from "../TextResource/ITextResource.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/// @title AbstractTradableProductRegistry.sol
/// @notice Layer 3: on top of product definitions and product indications,
///         lets eligible investors create trade requests that deploy concrete
///         product instances via the product factory.
///
/// @dev Persists a tradeId -> product instance record and anchors the exact
///      product definition state in force at trade time.
///      Still product-agnostic: the concrete contract implements the
///      _isAcceptedResourceType / _isAcceptedIndication hooks.
///
/// @author Raphael Prandtl
abstract contract AbstractTradableProductRegistry is AbstractIndicatedProductRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       IMMUTABLE STATE                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Investor registry consulted for eligibility.
    address public immutable investorRegistryAddress;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                        MUTABLE STATE                      */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Product factory used to deploy product instances.
    ///         Owner-settable and replaceable (see setProductFactory).
    address public productFactory;

    /// @dev Monotonic nonce feeding tradeId derivation.
    uint256 internal _tradeIdNonce;

    /// @dev tradeId -> deployed product instance address.
    mapping(bytes32 => address) internal _productByTradeId;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STRUCTS                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Investor-supplied parameters for a trade request.
    /// @param productDefinitionId       Product definition to trade against.
    /// @param productSpecificSchemaHash Hash of the product-specific payload schema.
    /// @param productSpecificPayload    Product-specific deployment payload.
    struct TradeRequestParams {
        bytes32 productDefinitionId;
        bytes32 productSpecificSchemaHash;
        bytes productSpecificPayload;
    }


    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when a trade is attempted before a factory is set.
    error MissingProductFactory();

    /// @notice Thrown when the provided investor registry address is invalid.
    error MissingInvestorRegistry();

    /// @notice Thrown when the provided factory is invalid or does not point
    ///         back at this registry.
    error InvalidProductFactory(address factory);

    /// @notice Thrown when the caller is not eligible for the product definition.
    error InvestorNotEligible(address investor, bytes32 productDefinitionId);

    /// @notice Thrown when the factory cannot deploy the product definition's type.
    error ProductTypeNotDeployable(bytes32 productTypeId);

    /// @notice Thrown when querying a trade that does not exist.
    error UnknownTrade(bytes32 tradeId);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when the product factory is set or replaced.
    event ProductFactorySet(address indexed previousFactory, address indexed newFactory);

    /// @notice Emitted when a trade request is created and its product deployed.
    event TradeRequestCreated(bytes32 indexed tradeId, address indexed productProvider, address indexed investor, bytes32 productDefinitionId, bytes32 productTypeId, address product);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  CONSTRUCTOR / MODIFIERS                  */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_                   Initial owner / product provider.
    /// @param investorRegistryAddress_ Investor registry for eligibility checks.
    constructor(address owner_, address investorRegistryAddress_)
    AbstractIndicatedProductRegistry(owner_) {
        if (investorRegistryAddress_ == address(0) || investorRegistryAddress_.code.length == 0) {
            revert MissingInvestorRegistry();
        }
        investorRegistryAddress = investorRegistryAddress_;
    }

    modifier onlyAfterFactorySet() {
        if (productFactory == address(0)) {
            revert MissingProductFactory();
        }
        _;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                   TRADE REQUEST CREATION                  */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Creates a trade request, validates the product definition,
    ///         the caller's eligibility and the product type, then deploys the
    ///         product instance and records the tradeId -> product mapping.
    /// @dev The caller (msg.sender) is the investor; owner() is the product provider.
    function createTradeRequest(TradeRequestParams calldata params) external onlyAfterFactorySet returns (bytes32 tradeId, address product) {
        bytes32 productDefinitionId = params.productDefinitionId;

        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        if (definition.status != ProductDefinitionStatus.Active) {
            revert ProductDefinitionNotActive(productDefinitionId, definition.status);
        }

        address investor = msg.sender;
        if (!_isEligibleInvestor(investor, productDefinitionId)) {
            revert InvestorNotEligible(investor, productDefinitionId);
        }

        ProductDefinitionResources  memory resources = definition.resources;
        address factory = productFactory;
        if (!IProductFactory(factory).canDeployProduct(resources.productTypeId)) {
            revert ProductTypeNotDeployable(resources.productTypeId);
        }

        address productProvider = owner();
        tradeId = _nextTradeId(investor, productDefinitionId);

        bytes32 deploymentStateHash = _deploymentStateHash(tradeId, productProvider, investor, productDefinitionId, definition.version,
            resources, params.productSpecificSchemaHash, params.productSpecificPayload);

        product = IProductFactory(factory).deployProduct(
            ProductDeploymentParams({
                common: CommonDeploymentParams({
                productRegistry: address(this),
                tradeId: tradeId,
                productProvider: productProvider,
                investor: investor,
                productDefinitionId: productDefinitionId,
                productDefinitionVersion: definition.version,
                termsResource: resources.termsResource,
                stylesheetResource: resources.stylesheetResource,
                productTypeId: resources.productTypeId,
                deploymentStateHash: deploymentStateHash
            }),
                productSpecificSchemaHash: params.productSpecificSchemaHash,
                productSpecificPayload: params.productSpecificPayload
            })
        );

        _productByTradeId[tradeId] = product;

        emit TradeRequestCreated(tradeId, productProvider, investor, productDefinitionId, resources.productTypeId, product);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         READ API                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the product instance deployed for a trade.
    function productOf(bytes32 tradeId) external view returns (address product) {
        product = _productByTradeId[tradeId];
        if (product == address(0)) {
            revert UnknownTrade(tradeId);
        }
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                     FACTORY MANAGEMENT                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Sets or replaces the product factory.
    /// @dev The factory must have code and point back at this registry.
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

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    INVESTOR VALIDATION                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _isEligibleInvestor(address investor, bytes32 productDefinitionId) internal view returns (bool) {
        return IInvestorRegistry(investorRegistryAddress).isEligibleInvestor(investor, productDefinitionId);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  INTERNAL MUTATION HELPERS               */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _nextTradeId(address investor, bytes32 productDefinitionId) internal returns (bytes32) {
        unchecked { ++_tradeIdNonce; }
        return keccak256(abi.encode(address(this), block.chainid, _tradeIdNonce, investor, productDefinitionId));
    }

    /// @dev Integrity anchor recorded in the product instance at deployment.
    ///      Binds the trade identity to the exact product definition state
    ///      at trade time, including version and immutable resource contents,
    ///      and to the agreed product-specific payload, so it can be
    ///      independently recomputed and verified later.
    function _deploymentStateHash(bytes32 tradeId, address productProvider, address investor, bytes32 productDefinitionId, uint256 productDefinitionVersion, ProductDefinitionResources memory resources, bytes32 productSpecificSchemaHash, bytes calldata productSpecificPayload) internal view returns (bytes32) {
        bytes32 termsContentHash = ITextResource(resources.termsResource).contentHash();
        bytes32 stylesheetContentHash = ITextResource(resources.stylesheetResource).contentHash();

        return keccak256(abi.encode(address(this), block.chainid, tradeId, productProvider, investor, productDefinitionId, productDefinitionVersion, resources.productTypeId,
                resources.termsResource, termsContentHash, resources.stylesheetResource, stylesheetContentHash, productSpecificSchemaHash,keccak256(productSpecificPayload)));
    }
}
