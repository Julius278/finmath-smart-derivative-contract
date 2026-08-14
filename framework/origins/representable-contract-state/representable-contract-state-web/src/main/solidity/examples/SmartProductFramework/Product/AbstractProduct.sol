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
 * @dev The deployment context contains no counterparty: products may be issued
 *      with or without preceding trade requests. The client is bound during
 *      inceptTrade() and immutable afterwards.
 *
 * @dev Concrete products implement product-specific term updates, term hashing,
 *      and XML state construction via the hooks at the bottom of this contract.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProduct is IProduct, ITradeLifecycle {
    using Strings for uint256;

    // ------------------------------ Immutable State ------------------------------ */

    /// @inheritdoc IProduct
    address public immutable override productFactory;
    /// @inheritdoc IProduct
    address public immutable override productRegistry;
    /// @inheritdoc IProduct
    address public immutable override productProvider;
    /// @inheritdoc IProduct
    bytes32 public immutable override productDefinitionId;
    /// @inheritdoc IProduct
    uint256 public immutable override productDefinitionVersion;
    /// @inheritdoc IProduct
    address public immutable override productTermsTemplate;
    /// @inheritdoc IProduct
    address public immutable override productDocumentationTemplate;

    // ------------------------------ Mutable State ------------------------------ */

    /// @dev Counterparty bound at inception; address(0) while Requested.
    address internal _client;

    /// @dev Current trade lifecycle status.
    TradeStatus internal _status;

    /// @dev Terms hash frozen at inception.
    bytes32 internal _agreedTermsHash;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address is zero.
    error ZeroAddress(string field);

    /// @notice Thrown when a required bytes32 value is zero.
    error ZeroHash(string field);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @notice Initializes the immutable deployment context.
     * @dev Called by the product factory; msg.sender is recorded as productFactory.
     *      The trade starts in status Requested with no counterparty bound.
     * @param common Common deployment parameters assembled by the product registry.
     */
    constructor(CommonDeploymentParams memory common) {
        if (common.productRegistry == address(0)) {
            revert ZeroAddress("productRegistry");
        }
        if (common.productProvider == address(0)) {
            revert ZeroAddress("productProvider");
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

        productFactory = msg.sender;
        productRegistry = common.productRegistry;
        productProvider = common.productProvider;
        productDefinitionId = common.productDefinitionId;
        productDefinitionVersion = common.productDefinitionVersion;
        productTermsTemplate = common.productTermsTemplate;
        productDocumentationTemplate = common.productDocumentationTemplate;

        // Status defaults to Requested (enum slot 0); no event emitted here since
        // no transition occurred. Indexers derive the initial state from deployment.
        _status = TradeStatus.Requested;
    }

    // ------------------------------ Modifiers ------------------------------ */

    /// @dev Restricts access to the product provider fixed at deployment.
    modifier onlyProductProvider() {
        if (msg.sender != productProvider) {
            revert NotProductProvider(msg.sender);
        }
        _;
    }

    /// @dev Restricts access to the client bound at inception.
    ///      While Requested, _client is address(0), so no caller can pass.
    modifier onlyClient() {
        if (msg.sender != _client) {
            revert NotClient(msg.sender);
        }
        _;
    }

    /// @dev Requires the trade to be in a specific status.
    modifier inStatus(TradeStatus expected) {
        if (_status != expected) {
            revert InvalidTradeStatus(_status);
        }
        _;
    }

    // ------------------------------ Trade Lifecycle ------------------------------ */

    /// @inheritdoc ITradeLifecycle
    function updateTerms(bytes calldata productPayload) external override onlyProductProvider inStatus(TradeStatus.Requested) {
        _updateTerms(productPayload);

        bytes32 newHash = currentTermsHash();
        emit TermsUpdated(msg.sender, newHash);
        emit StateUpdated(msg.sender, address(this), newHash);
    }

    /// @inheritdoc ITradeLifecycle
    function inceptTrade(address withParty, bytes32 agreedTermsHash_) external override onlyProductProvider inStatus(TradeStatus.Requested) {
        if (withParty == address(0) || withParty == productProvider) {
            revert InvalidCounterparty(withParty);
        }

        bytes32 current = currentTermsHash();
        if (agreedTermsHash_ != current) {
            revert AgreedTermsMismatch(current, agreedTermsHash_);
        }

        _client = withParty;
        _agreedTermsHash = agreedTermsHash_;
        _setStatus(TradeStatus.Incepted);

        emit TradeIncepted(msg.sender, withParty, agreedTermsHash_);
    }

    /// @inheritdoc ITradeLifecycle
    function confirmTrade(bytes32 agreedTermsHash_) external override onlyClient inStatus(TradeStatus.Incepted) {
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
        // While Requested, _client is address(0), so only the provider can cancel.
        if (msg.sender != productProvider && msg.sender != _client) {
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
    function client() external view override returns (address) {
        return _client;
    }

    /// @inheritdoc ITradeLifecycle
    function agreedTermsHash() external view override returns (bytes32) {
        return _agreedTermsHash;
    }

    /// @inheritdoc ITradeLifecycle
    function currentTermsHash() public view override returns (bytes32) {
        return keccak256(abi.encode(address(this), _economicTermsHash()));
    }

    // ------------------------------ Internal Lifecycle ------------------------------ */

    /// @dev Updates the current trade status and emits the status change.
    function _setStatus(TradeStatus newStatus) internal {
        TradeStatus oldStatus = _status;
        _status = newStatus;
        emit TradeStatusChanged(oldStatus, newStatus);
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc IXMLRepresentableState
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
            "<ProductProvider evmstate:call=\"productProvider()(address)\"/>",
            "<ProductDefinitionId evmstate:call=\"productDefinitionId()(bytes32)\"/>",
            "<ProductDefinitionVersion evmstate:call=\"productDefinitionVersion()(uint256)\"/>",
            "<Client evmstate:call=\"client()(address)\"/>",
            "<TradeStatus evmstate:call=\"tradeStatus()(uint8)\"/>",
            "</DeploymentState>"
        );
    }

    /// @dev Builds an XML include for a text resource.
    function _include(address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        return string.concat(
            "<xi:include href=\"",
            textResource.web3Url(),
            "\" parse=\"xml\" evmstate:integrity=\"",
            _integrity(textResource),
            "\"/>"
        );
    }

    /// @dev Builds an XML reference to a text resource.
    function _resourceReference(string memory elementName, address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        return string.concat(
            "<", elementName,
            " href=\"", textResource.web3Url(),
            "\" integrity=\"", _integrity(textResource),
            "\"/>"
        );
    }

    /// @dev Formats the integrity attribute value of a text resource.
    function _integrity(ITextResource resource) private view returns (string memory) {
        return string.concat("keccak256-", uint256(resource.contentHash()).toHexString(32));
    }

    // ------------------------------ Concrete Hooks ------------------------------ */

    /// @dev Applies a full replacement of the product-specific terms.
    /// @param productPayload ABI-encoded, product-specific terms.
    function _updateTerms(bytes calldata productPayload) internal virtual;

    /// @dev Returns a hash over all negotiable product terms.
    function _economicTermsHash() internal view virtual returns (bytes32);

    /// @dev Hook invoked once the trade transitions to Active.
    function _onActivated() internal virtual {}
}
