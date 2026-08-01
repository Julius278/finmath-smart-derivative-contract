// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITextResource} from "../../../resources/ITextResource.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IProduct} from "./IProduct.sol";
import {ITradeLifecycle} from "./ITradeLifecycle.sol";
import {CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title AbstractProduct
 * @notice Base contract for deployed products with immutable deployment state,
 *         a generic trade lifecycle, and XML rendering helpers.
 *
 * @dev Concrete products implement product-specific term updates, term hashing,
 *      and XML state construction.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProduct is IProduct, ITradeLifecycle {
    using Strings for uint256;

    // ------------------------------ Immutable State ------------------------------

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

    /// @dev Current trade lifecycle status.
    TradeStatus internal _status;

    /// @dev Terms hash accepted at inception.
    bytes32 internal _agreedTermsHash;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address is zero.
    error ZeroAddress(string field);

    /// @notice Thrown when a required bytes32 value is zero.
    error ZeroHash(string field);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param common Common deployment parameters assembled by the registry.
     */
    constructor(CommonDeploymentParams memory common) {
        if (common.productRegistry == address(0)) {
            revert ZeroAddress("productRegistry");
        }
        if (common.tradeId == bytes32(0)) {
            revert ZeroHash("tradeId");
        }
        if (common.productProvider == address(0)) {
            revert ZeroAddress("productProvider");
        }
        if (common.client == address(0)) {
            revert ZeroAddress("client");
        }
        if (common.productDefinitionId == bytes32(0)) {
            revert ZeroHash("productDefinitionId");
        }
        if (common.productTermsTemplate == address(0)) {
            revert ZeroAddress("productTermsTemplate");
        }
        if (common.productDocumentationTemplate == address(0)) {
            revert ZeroAddress("productDocumentationTemplate");
        }
        if (common.deploymentStateHash == bytes32(0)) {
            revert ZeroHash("deploymentStateHash");
        }

        productRegistry = common.productRegistry;
        productFactory = msg.sender;
        tradeId = common.tradeId;
        productProvider = common.productProvider;
        client = common.client;
        productDefinitionId = common.productDefinitionId;
        productDefinitionVersion = common.productDefinitionVersion;
        productTermsTemplate = common.productTermsTemplate;
        productDocumentationTemplate = common.productDocumentationTemplate;
        deploymentStateHash = common.deploymentStateHash;

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

    /// @inheritdoc ITradeLifecycle
    function updateTerms(bytes calldata productPayload) external override onlyClient {
        if (_status != TradeStatus.Requested) {
            revert InvalidTradeStatus(_status);
        }

        _updateTerms(productPayload);

        bytes32 newHash = currentTermsHash();
        emit TermsUpdated(msg.sender, newHash);
        emit StateUpdated(msg.sender, address(this), newHash);
    }

    /// @inheritdoc ITradeLifecycle
    function inceptTrade(bytes32 agreedTermsHash_) external override onlyProductProvider {
        if (_status != TradeStatus.Requested) {
            revert InvalidTradeStatus(_status);
        }

        bytes32 current = currentTermsHash();
        if (agreedTermsHash_ != current) {
            revert AgreedTermsMismatch(current, agreedTermsHash_);
        }

        _agreedTermsHash = agreedTermsHash_;
        _setStatus(TradeStatus.Incepted);

        emit TradeIncepted(msg.sender, agreedTermsHash_);
    }

    /// @inheritdoc ITradeLifecycle
    function confirmTrade(bytes32 agreedTermsHash_) external override onlyClient {
        if (_status != TradeStatus.Incepted) {
            revert InvalidTradeStatus(_status);
        }
        if (agreedTermsHash_ != _agreedTermsHash) {
            revert AgreedTermsMismatch(_agreedTermsHash, agreedTermsHash_);
        }

        _setStatus(TradeStatus.Active);

        emit TradeConfirmed(msg.sender, agreedTermsHash_);
        emit TradeActivated();

        _onActivated();
    }

    /// @inheritdoc ITradeLifecycle
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

    /// @inheritdoc ITradeLifecycle
    function currentTermsHash() public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), deploymentStateHash, _economicTermsHash()));
    }

    // ------------------------------ Internal Lifecycle ------------------------------ */

    /// @dev Updates the current trade status and emits the status change.
    function _setStatus(TradeStatus newStatus) internal {
        TradeStatus oldStatus = _status;
        _status = newStatus;
        emit TradeStatusChanged(oldStatus, newStatus);
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc IProduct
    function stateXmlTemplate() external view override returns (string memory) {
        return _productSpecificStateXml();
    }

    /// @dev Returns the complete XML state template of the concrete product.
    function _productSpecificStateXml() internal view virtual returns (string memory);

    /// @dev Returns the common deployment and lifecycle XML bindings.
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
            "<TradeStatus evmstate:call=\"tradeStatus()(uint8)\"/>",
            "</DeploymentState>"
        );
    }

    /// @dev Builds an XML include for a text resource.
    function _include(address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory integrity = string.concat("keccak256-", uint256(textResource.contentHash()).toHexString(32));

        return string.concat(
            "<xi:include href=\"",
            textResource.web3Url(),
            "\" parse=\"xml\" evmstate:integrity=\"",
            integrity,
            "\"/>"
        );
    }

    /// @dev Builds an XML reference to a text resource.
    function _resourceReference(string memory elementName, address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory integrity = string.concat("keccak256-", uint256(textResource.contentHash()).toHexString(32));

        return string.concat(
            "<", elementName,
            " href=\"", textResource.web3Url(),
            "\" integrity=\"", integrity,
            "\"/>"
        );
    }

    // ------------------------------ Concrete Hooks ------------------------------

    /// @dev Applies a full replacement product payload.
    function _updateTerms(bytes calldata productPayload) internal virtual;

    /// @dev Returns a hash of all negotiable product terms.
    function _economicTermsHash() internal view virtual returns (bytes32);

    /// @dev Hook called when the trade becomes active.
    function _onActivated() internal virtual {}
}
