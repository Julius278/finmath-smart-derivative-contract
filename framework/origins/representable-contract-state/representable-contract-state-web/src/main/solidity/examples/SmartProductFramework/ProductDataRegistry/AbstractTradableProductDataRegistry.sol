// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractIndicatedProductDataRegistry} from "./AbstractIndicatedProductDataRegistry.sol";
import {IProductFactory} from "../ProductFactory/IProductFactory.sol";
import {IInvestorRegistry} from "../InvestorRegistry/IInvestorRegistry.sol";
import {ITextResource} from "./TextResource/ITextResource.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/// @title AbstractTradableProductDataRegistry
/// @notice Layer 3: on top of programs + indications, lets eligible investors
///         create trade requests that deploy a concrete product via the product
///         factory. Persists a tradeId -> product record and anchors the exact
///         program state in force at trade time.
/// @dev Still product-agnostic: the concrete contract implements the
///      _isAcceptedResourceType / _isAcceptedIndication hooks.
///
/// @author Raphael Prandtl
abstract contract AbstractTradableProductDataRegistry is AbstractIndicatedProductDataRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       IMMUTABLE STATE                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Investor registry consulted for eligibility.
    address public immutable investorRegistryAddress;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                        MUTABLE STATE                      */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Product factory used to deploy products. Owner-settable and
    ///         replaceable (see setProductFactory).
    address public productFactory;

    /// @dev Monotonic nonce feeding tradeId derivation.
    uint256 internal _tradeIdNonce;

    /// @dev tradeId -> deployed product address.
    mapping(bytes32 => address) internal _productByTradeId;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STRUCTS                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Investor-supplied parameters for a trade request.
    struct TradeRequestParams {
        bytes32 programId;
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

    /// @notice Thrown when the caller is not eligible for the program.
    error InvestorNotEligible(address investor, bytes32 programId);

    /// @notice Thrown when the factory cannot deploy the program's product type.
    error ProductTypeNotDeployable(bytes32 productTypeId);

    /// @notice Thrown when querying a trade that does not exist.
    error UnknownTrade(bytes32 tradeId);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when the product factory is set or replaced.
    event ProductFactorySet(address indexed previousFactory, address indexed newFactory);

    /// @notice Emitted when a trade request is created and its product deployed.
    event TradeRequestCreated(bytes32 indexed tradeId, address indexed issuer, address indexed investor, bytes32 programId, bytes32 productTypeId, address product);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  CONSTRUCTOR / MODIFIERS                  */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_                   Initial owner / issuer.
    /// @param investorRegistryAddress_ Investor registry for eligibility checks.
    constructor(address owner_, address investorRegistryAddress_)
    AbstractIndicatedProductDataRegistry(owner_) {
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

    /// @notice Creates a trade request: validates the program, the caller's
    ///         eligibility, and the product type, then deploys the product and
    ///         records the tradeId -> product mapping.
    /// @dev The caller (msg.sender) is the investor; owner() is the issuer.
    function createTradeRequest(TradeRequestParams calldata params) external onlyAfterFactorySet returns (bytes32 tradeId, address product) {
        bytes32 programId = params.programId;

        ProgramStorage storage program = _existingProgram(programId);
        if (program.status != ProgramStatus.Active) {
            revert ProgramNotActive(programId, program.status);
        }

        address investor = msg.sender;
        if (!_isEligibleInvestor(investor, programId)) {
            revert InvestorNotEligible(investor, programId);
        }

        ProgramResources memory resources = program.resources;
        address factory = productFactory;
        if (!IProductFactory(factory).canDeployProduct(resources.productTypeId)) {
            revert ProductTypeNotDeployable(resources.productTypeId);
        }

        address issuer = owner();
        tradeId = _nextTradeId(investor, programId);

        bytes32 deploymentStateHash = _deploymentStateHash(tradeId, issuer, investor, programId, program.programVersion,
            resources, params.productSpecificSchemaHash, params.productSpecificPayload);

        product = IProductFactory(factory).deployProduct(
            ProductDeploymentParams({
                common: CommonDeploymentParams({
                productRegistry: address(this),
                tradeId: tradeId,
                issuer: issuer,
                investor: investor,
                programId: programId,
                programVersion: program.programVersion,
                productTermsResource: resources.productTermsResource,
                styleSheetResource: resources.styleSheetResource,
                productTypeId: resources.productTypeId,
                deploymentStateHash: deploymentStateHash
            }),
                productSpecificSchemaHash: params.productSpecificSchemaHash,
                productSpecificPayload: params.productSpecificPayload
            })
        );

        _productByTradeId[tradeId] = product;

        emit TradeRequestCreated(tradeId, issuer, investor, programId, resources.productTypeId, product);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         READ API                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the product deployed for a trade.
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

    function _isEligibleInvestor(address investor, bytes32 programId) internal view returns (bool) {
        return IInvestorRegistry(investorRegistryAddress).isEligibleInvestor(investor, programId);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  INTERNAL MUTATION HELPERS               */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _nextTradeId(address investor, bytes32 programId) internal returns (bytes32) {
        unchecked { ++_tradeIdNonce; }
        return keccak256(abi.encode(address(this), block.chainid, _tradeIdNonce, investor, programId));
    }

    /// @dev Integrity anchor recorded in the product at deployment. Binds the
    ///      trade identity to the exact program state (version + immutable
    ///      resource contents) and the agreed product-specific payload, so it
    ///      can be independently recomputed and verified later.
    function _deploymentStateHash(bytes32 tradeId, address issuer, address investor, bytes32 programId, uint256 programVersion, ProgramResources memory resources, bytes32 productSpecificSchemaHash, bytes calldata productSpecificPayload) internal view returns (bytes32) {
        bytes32 termsContentHash = ITextResource(resources.productTermsResource).contentHash();
        bytes32 styleSheetContentHash = ITextResource(resources.styleSheetResource).contentHash();

        return keccak256(abi.encode(address(this), block.chainid, tradeId, issuer, investor, programId, programVersion, resources.productTypeId,
                resources.productTermsResource, termsContentHash, resources.styleSheetResource, styleSheetContentHash, productSpecificSchemaHash,keccak256(productSpecificPayload)));
    }
}
