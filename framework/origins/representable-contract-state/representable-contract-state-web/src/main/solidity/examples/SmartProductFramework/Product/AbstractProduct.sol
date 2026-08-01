// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IXMLRepresentableState} from "../../../IRepresentableState.sol";
import {ITextResource} from "../../../resources/ITextResource.sol";

import {IProduct} from "./IProduct.sol";
import {ITradeLifecycle} from "./ITradeLifecycle.sol";
import {CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title AbstractProduct
 * @notice Product-agnostic base for deployed products. Stores immutable
 *         deployment state, captures the deploying factory (msg.sender),
 *         drives the generic trade inception/confirmation lifecycle, and
 *         provides XML rendering scaffolding.
 *
 * @dev LIFECYCLE (ITradeLifecycle, ERC-6123-inspired)
 *      Requested -> Incepted -> Active, with Cancelled as a pre-activation
 *      terminal state. The base owns status, guards, and the agreed-terms-hash
 *      handshake; concrete products implement the term storage/update and the
 *      terms fingerprint via _updateTerms / _economicTermsHash. Product-specific
 *      lifecycles (e.g. issuance, coupons, redemption) can be layered on top of
 *      Active via the _onActivated hook.
 *
 * @dev TERMS FROZEN AFTER INCEPTION
 *      updateTerms is only allowed in Requested. Concrete products MUST NOT
 *      mutate agreement-relevant economic state after Incepted, or the agreed
 *      terms hash would no longer match live state.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProduct is IProduct, ITradeLifecycle {
    using Strings for uint256;

    // ------------------------------ Immutable State ------------------------------ */

    /// @inheritdoc IProduct
    address public immutable override productRegistry;
    /// @inheritdoc IProduct
    address public immutable override productFactory;
    /// @inheritdoc IProduct
    bytes32 public immutable override tradeId;
    /// @inheritdoc IProduct
    address public immutable override productProvider;
    /// @inheritdoc IProduct
    address public immutable override client;
    /// @inheritdoc IProduct
    bytes32 public immutable override productDefinitionId;
    /// @inheritdoc IProduct
    uint256 public immutable override productDefinitionVersion;
    /// @inheritdoc IProduct
    address public immutable override productTermsTemplate;
    /// @inheritdoc IProduct
    address public immutable override productDocumentationTemplate;
    /// @inheritdoc IProduct
    bytes32 public immutable override deploymentStateHash;

    // ------------------------------ Mutable State ------------------------------ */

    /// @dev Current trade status.
    TradeStatus internal _status;

    /// @dev Agreed terms hash fixed at inception (0 before Incepted).
    bytes32 internal _agreedTermsHash;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address field is the zero address.
    error ZeroAddress(string field);
    /// @notice Thrown when a required bytes32 field is zero.
    error ZeroHash(string field);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param c Common deployment parameters assembled by the registry.
     * @dev The deploying product-specific factory is captured as msg.sender.
     *      The concrete product sets its initial terms after this constructor.
     */
    constructor(CommonDeploymentParams memory c) {
        if (c.productRegistry == address(0)) revert ZeroAddress("productRegistry");
        if (c.tradeId == bytes32(0)) revert ZeroHash("tradeId");
        if (c.productProvider  == address(0)) revert ZeroAddress("productProvider ");
        if (c.client == address(0)) revert ZeroAddress("client");
        if (c.productDefinitionId  == bytes32(0)) revert ZeroHash("productDefinitionId ");
        if (c.productTermsTemplate == address(0)) revert ZeroAddress("productTermsTemplate");
        if (c.productDocumentationTemplate == address(0)) revert ZeroAddress("productDocumentationTemplate");
        if (c.deploymentStateHash == bytes32(0)) revert ZeroHash("deploymentStateHash");

        productRegistry = c.productRegistry;
        productFactory = msg.sender;
        tradeId = c.tradeId;
        productProvider = c.productProvider;
        client = c.client;
        productDefinitionId = c.productDefinitionId;
        productDefinitionVersion  = c.productDefinitionVersion ;
        productTermsTemplate = c.productTermsTemplate;
        productDocumentationTemplate = c.productDocumentationTemplate;
        deploymentStateHash = c.deploymentStateHash;

        _status = TradeStatus.Requested;
        emit TradeStatusChanged(TradeStatus.Requested, TradeStatus.Requested);
    }

    // ------------------------------ Modifiers ------------------------------ */

    modifier onlyProductProvider() {
        if (msg.sender != productProvider) {
            revert NotProductProvider(msg.sender);
        }
        _;
    }

    modifier onlyClient() {
        if (msg.sender != client) {
            revert NotClient(msg.sender);
        }
        _;
    }

    // ------------------------------ Trade Lifecycle ------------------------------ */

    function updateTerms(bytes calldata productSpecificPayload) external override onlyClient {
        if (_status != TradeStatus.Requested) revert InvalidTradeStatus(_status);

        _updateTerms(productSpecificPayload);

        bytes32 newHash = currentTermsHash();
        emit TermsUpdated(msg.sender, newHash);
        emit StateUpdated(msg.sender, address(this), newHash);
    }

    function inceptTrade(bytes32 agreedTermsHash_) external override onlyProductProvider {
        if (_status != TradeStatus.Requested) revert InvalidTradeStatus(_status);

        bytes32 current = currentTermsHash();
        if (agreedTermsHash_ != current) revert AgreedTermsMismatch(current, agreedTermsHash_);

        _agreedTermsHash = agreedTermsHash_;
        _setStatus(TradeStatus.Incepted);

        emit TradeIncepted(msg.sender, agreedTermsHash_);
    }

    function confirmTrade(bytes32 agreedTermsHash_) external override onlyClient {
        if (_status != TradeStatus.Incepted) revert InvalidTradeStatus(_status);
        if (agreedTermsHash_ != _agreedTermsHash) {
            revert AgreedTermsMismatch(_agreedTermsHash, agreedTermsHash_);
        }

        _setStatus(TradeStatus.Active);

        emit TradeConfirmed(msg.sender, agreedTermsHash_);
        emit TradeActivated();

        _onActivated();
    }

    function cancelTrade() external override {
        if (msg.sender != productProvider && msg.sender != client) {
            revert NotTradeParty(msg.sender);
        }
        if (_status != TradeStatus.Requested && _status != TradeStatus.Incepted) {
            revert InvalidTradeStatus(_status);
        }

        _setStatus(TradeStatus.Cancelled);
        emit TradeCanceled(msg.sender);
    }

    // ------------------------------ Lifecycle Views ------------------------------ */

    /// @inheritdoc ITradeLifecycle
    function tradeStatus() external view override returns (TradeStatus) {
        return _status;
    }

    /// @inheritdoc ITradeLifecycle
    function agreedTermsHash() external view override returns (bytes32) {
        return _agreedTermsHash;
    }

    /**
     * @inheritdoc ITradeLifecycle
     * @dev Binds the economic terms to this instance and its deployment anchor,
     *      so an agreed hash cannot be replayed against another product.
     */
    function currentTermsHash() public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), deploymentStateHash, _economicTermsHash()));
    }

    // ------------------------------ Internal Lifecycle ------------------------------ */

    function _setStatus(TradeStatus newStatus) internal {
        TradeStatus old = _status;
        _status = newStatus;
        emit TradeStatusChanged(old, newStatus);
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc IXMLRepresentableState
    function stateXmlTemplate() external view override returns (string memory) {
        return _productSpecificStateXml();
    }

    /**
     * @dev Concrete product renders its root element and places the deployment
     *      state plus role-labelled product resource includes beneath it. Economic
     *      bindings live in the included product terms template.
     */
    function _productSpecificStateXml() internal view virtual returns (string memory);

    /**
     * @dev Generic deployment + lifecycle bindings as child elements (resolved
     *      by the renderer against this product's getters). Placed inside the
     *      concrete product's root element.
     */
    function _deploymentStateXml() internal pure returns (string memory) {
        return string.concat(
            "<DeploymentState>",
                "<ProductRegistry evmstate:call=\"productRegistry()(address)\"/>",
                "<ProductFactory evmstate:call=\"productFactory()(address)\"/>",
                "<TradeId evmstate:call=\"tradeId()(bytes32)\"/>",
                "<ProductProvider evmstate:call=\"productProvider()(address)\"/>",
                "<Client evmstate:call=\"client()(address)\"/>",
                "<ProductDefinitionId evmstate:call=\"productDefinitionId()(bytes32)\"/>",
                "<ProductDefinitionVersion evmstate:call=\"productDefinitionVersion()(uint256)\"/>",
                "<DeploymentStateHash evmstate:call=\"deploymentStateHash()(bytes32)\"/>",
                "<TradeStatus evmstate:call=\"tradeStatus()(uint8)\"/>"
            "</DeploymentState>"
        );
    }

    /**
     * @dev Builds an xi:include for a text resource, parsed as XML so its
     *      evmstate:call bindings resolve, with a keccak256 integrity hint.
     */
    function _include(address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory href = textResource.web3Url();
        string memory integrity = string.concat(
            "keccak256-", uint256(textResource.contentHash()).toHexString(32)
        );
        return string.concat(
            "<xi:include href=\"", href,
            "\" parse=\"xml\" evmstate:integrity=\"", integrity, "\"/>"
        );
    }

    /**
     * @dev References a finalized TextResource without including its content in
     *      the canonical XML. The term-sheet stylesheet is therefore loaded
     *      only by the optional post-processing step.
     */
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

    // ------------------------------ Concrete Hooks ------------------------------ */

    /**
     * @dev Decodes and applies a full-replacement terms payload. Called only in
     *      Requested (client). Must validate the decoded economics.
     */
    function _updateTerms(bytes calldata productSpecificPayload) internal virtual;

    /**
     * @dev Fingerprint of the product's economic terms (folded into
     *      currentTermsHash). Must reflect all negotiable terms.
     */
    function _economicTermsHash() internal view virtual returns (bytes32);

    /**
     * @dev Optional hook invoked once when the trade becomes Active. Default
     *      no-op; product-specific lifecycles extend here.
     */
    function _onActivated() internal virtual {}
}
