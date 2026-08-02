// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "../Product/AbstractProduct.sol";
import {CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title InterestRateSwap
 * @notice Example fixed-versus-floating interest-rate swap product.
 *
 * @dev Decodes and validates the swap product payload during deployment and
 *      subsequent term updates.
 *
 * @author Raphael Prandtl
 */
contract InterestRateSwap is AbstractProduct {
    // ------------------------------ Enums ------------------------------ */

    /// @notice Client role on the fixed-rate leg.
    enum FixedRateRole {
        Payer,
        Receiver
    }

    // ------------------------------ Constants ------------------------------ */

    /// @notice Decimal scale of notional: 100 represents 1.00 currency units.
    uint8 public constant NOTIONAL_SCALE = 2;

    /// @notice Decimal scale of swapRate: 250 represents the decimal rate 0.0250.
    uint8 public constant SWAP_RATE_SCALE = 4;

    // ------------------------------ Immutable State ------------------------------ */

    /// @notice Trade date represented by the deployment timestamp.
    uint256 public immutable tradeDate;

    /// @notice Effective date represented by the deployment timestamp.
    uint256 public immutable effectiveDate;

    // ------------------------------ Mutable State ------------------------------ */

    /// @notice Current notional with NOTIONAL_SCALE decimal places.
    uint256 public notional;

    /// @notice Three-letter uppercase currency code.
    string public currency;

    /// @notice Current maturity as a Unix timestamp.
    uint256 public maturity;

    /// @notice Current fixed rate with SWAP_RATE_SCALE decimal places.
    int256 public swapRate;

    /// @notice Current client role on the fixed-rate leg.
    FixedRateRole public clientFixedRateRole;

    /// @notice Forward curve symbol used by the floating-rate leg.
    string public forwardCurveSymbol;

    /// @notice Discount curve symbol used for valuation.
    string public discountCurveSymbol;

    // ------------------------------ Structs ------------------------------ */

    /// @notice ABI-decoded payload used to set the swap terms.
    struct InterestRateSwapDeploymentPayload {
        uint256 notional;
        string currency;
        uint256 maturity;
        int256 swapRate;
        uint8 clientFixedRateRole;
        string forwardCurveSymbol;
        string discountCurveSymbol;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the notional is zero.
    error InvalidNotional();

    /// @notice Thrown when the currency is not three uppercase ASCII letters.
    error InvalidCurrency(string currency);

    /// @notice Thrown when the maturity is not in the future.
    error InvalidMaturity();

    /// @notice Thrown when the fixed-rate role is invalid.
    error InvalidFixedRateRole(uint8 role);

    /// @notice Thrown when a required string is empty.
    error EmptyString(string field);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param common         Common deployment parameters.
     * @param productPayload ABI-encoded InterestRateSwapDeploymentPayload.
     */
    constructor(CommonDeploymentParams memory common, bytes memory productPayload) AbstractProduct(common) {
        tradeDate = block.timestamp;
        effectiveDate = block.timestamp;
        _applyTerms(productPayload);
        emit StateUpdated(msg.sender, address(this), currentTermsHash());
    }

    // ------------------------------ Terms Hooks ------------------------------ */

    /// @inheritdoc AbstractProduct
    function _updateTerms(bytes calldata productPayload) internal override {
        _applyTerms(productPayload);
    }

    /// @inheritdoc AbstractProduct
    function _economicTermsHash() internal view override returns (bytes32) {
        return keccak256(abi.encode(notional, currency, maturity, swapRate, clientFixedRateRole, forwardCurveSymbol, discountCurveSymbol, tradeDate, effectiveDate));
    }

    /// @notice Decodes, validates, and applies a complete product payload.
    function _applyTerms(bytes memory productPayload) internal {
        InterestRateSwapDeploymentPayload memory payload = abi.decode(productPayload, (InterestRateSwapDeploymentPayload));
        if (payload.notional == 0) {
            revert InvalidNotional();
        }
        if (!_isCurrencyCode(payload.currency)) {
            revert InvalidCurrency(payload.currency);
        }
        if (payload.maturity <= block.timestamp) {
            revert InvalidMaturity();
        }
        if (payload.clientFixedRateRole > uint8(FixedRateRole.Receiver)) {
            revert InvalidFixedRateRole(payload.clientFixedRateRole);
        }
        if (bytes(payload.forwardCurveSymbol).length == 0) {
            revert EmptyString("forwardCurveSymbol");
        }
        if (bytes(payload.discountCurveSymbol).length == 0) {
            revert EmptyString("discountCurveSymbol");
        }

        notional = payload.notional;
        currency = payload.currency;
        maturity = payload.maturity;
        swapRate = payload.swapRate;
        clientFixedRateRole = FixedRateRole(payload.clientFixedRateRole);
        forwardCurveSymbol = payload.forwardCurveSymbol;
        discountCurveSymbol = payload.discountCurveSymbol;
    }

    // ------------------------------ Validation Helpers ------------------------------

    function _isCurrencyCode(string memory value) internal pure returns (bool) {
        bytes memory characters = bytes(value);
        return characters.length == 3 && _isUppercaseAsciiLetter(characters[0]) &&
                _isUppercaseAsciiLetter(characters[1]) &&
                _isUppercaseAsciiLetter(characters[2]);
    }

    function _isUppercaseAsciiLetter(bytes1 character) internal pure returns (bool) {
        return character >= 0x41 && character <= 0x5A;
    }

    // ------------------------------ FpML Party References ------------------------------ */

    /// @notice Returns the client's fixed-rate role name.
    function clientFixedRateRoleName() external view returns (string memory){
        return clientFixedRateRole == FixedRateRole.Payer ? "Payer" : "Receiver";
    }

    /// @notice Returns the XML party id paying the fixed-rate leg.
    function fixedLegPayerPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "client" : "productProvider";
    }

    /// @notice Returns the XML party id receiving the fixed-rate leg.
    function fixedLegReceiverPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "productProvider" : "client";
    }

    /// @notice Returns the XML party id paying the floating-rate leg.
    function floatingLegPayerPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "productProvider" : "client";
    }

    /// @notice Returns the XML party id receiving the floating-rate leg.
    function floatingLegReceiverPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "client" : "productProvider";
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc AbstractProduct
    function _productSpecificStateXml() internal view override returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<InterestRateSwap xmlns=\"urn:smart-product-framework:interest-rate-swap:1.0\"",
            " xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\">",
            _deploymentStateXml(),
            "<ProductResources>",
                "<ProductTermsTemplate>",
                    _include(productTermsTemplate),
                "</ProductTermsTemplate>",
                _resourceReference(
                    "ProductDocumentationTemplate",
                    productDocumentationTemplate
                ),
            "</ProductResources>",
            "</InterestRateSwap>"
        );
    }
}
