// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "../Product/AbstractProduct.sol";
import {CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title InterestRateSwap
 * @notice Lightweight fixed-versus-floating interest-rate swap whose client
 *         and product provider agree its terms through the shared
 *         incept/confirm lifecycle.
 * @dev The requested payload deliberately contains only the seven terms that
 *      vary in the demo. The trade and effective dates are both anchored to
 *      deployment time, while schedule conventions remain in the immutable
 *      product terms template.
 *
 * @author Raphael Prandtl
 */
contract InterestRateSwap is AbstractProduct {
    // ------------------------------ Enums ------------------------------ */

    /// @notice The client's role on the fixed-rate leg.
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

    /// @notice Trade date used by the FpML view (deployment unix timestamp).
    uint256 public immutable tradeDate;

    /// @notice Effective date used by the FpML view (deployment unix timestamp).
    uint256 public immutable effectiveDate;

    // ------------------------------ Mutable State ------------------------------ */

    /// @notice Notional as an integer with two decimal places.
    uint256 public notional;

    /// @notice Three-letter uppercase ISO-style currency code.
    string public currency;

    /// @notice Contractual maturity as a unix timestamp.
    uint256 public maturity;

    /// @notice Fixed swap rate as a signed decimal with four decimal places.
    int256 public swapRate;

    /// @notice Whether the client pays or receives the fixed-rate leg.
    FixedRateRole public clientFixedRateRole;

    /// @notice Symbolic identifier of the forward curve used for projection.
    string public forwardCurveSymbol;

    /// @notice Symbolic identifier of the discount curve used for discounting.
    string public discountCurveSymbol;

    // ------------------------------ Structs ------------------------------ */

    /**
     * @notice Decoded interest-rate-swap payload.
     * @dev clientFixedRateRole uses 0 for Payer and 1 for Receiver. uint8 is
     *      used in the wire schema so an invalid value can be rejected with a
     *      descriptive custom error before conversion to the enum.
     */
    struct ProductSpecificPayload {
        uint256 notional;
        string currency;
        uint256 maturity;
        int256 swapRate;
        uint8 clientFixedRateRole;
        string forwardCurveSymbol;
        string discountCurveSymbol;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the requested notional is zero.
    error InvalidNotional();

    /// @notice Thrown when the requested currency is not three uppercase ASCII letters.
    error InvalidCurrency(string currency);

    /// @notice Thrown when the requested maturity is not in the future.
    error InvalidMaturity();

    /// @notice Thrown when the wire value does not identify a FixedRateRole.
    error InvalidFixedRateRole(uint8 role);

    /// @notice Thrown when a required curve symbol is empty.
    error EmptyString(string field);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param c                      Common deployment parameters.
     * @param productSpecificPayload Raw ABI-encoded ProductSpecificPayload.
     */
    constructor(CommonDeploymentParams memory c, bytes memory productSpecificPayload)
    AbstractProduct(c)
    {
        tradeDate = block.timestamp;
        effectiveDate = block.timestamp;
        _applyTerms(productSpecificPayload);
        emit StateUpdated(msg.sender, address(this), currentTermsHash());
    }

    // ------------------------------ Terms Hooks ------------------------------ */

    /// @inheritdoc AbstractProduct
    function _updateTerms(bytes calldata productSpecificPayload) internal override {
        _applyTerms(productSpecificPayload);
    }

    /// @inheritdoc AbstractProduct
    function _economicTermsHash() internal view override returns (bytes32) {
        return keccak256(abi.encode(
            notional,
            currency,
            maturity,
            swapRate,
            clientFixedRateRole,
            forwardCurveSymbol,
            discountCurveSymbol,
            tradeDate,
            effectiveDate
        ));
    }

    /**
     * @dev Decodes, validates, and fully replaces the requested terms. This is
     *      shared by construction and client updates before inception.
     */
    function _applyTerms(bytes memory productSpecificPayload) internal {
        ProductSpecificPayload memory p = abi.decode(productSpecificPayload, (ProductSpecificPayload));

        if (p.notional == 0) {
            revert InvalidNotional();
        }
        if (!_isCurrencyCode(p.currency)) {
            revert InvalidCurrency(p.currency);
        }
        if (p.maturity <= block.timestamp) {
            revert InvalidMaturity();
        }
        if (p.clientFixedRateRole > uint8(FixedRateRole.Receiver)) {
            revert InvalidFixedRateRole(p.clientFixedRateRole);
        }
        if (bytes(p.forwardCurveSymbol).length == 0) {
            revert EmptyString("forwardCurveSymbol");
        }
        if (bytes(p.discountCurveSymbol).length == 0) {
            revert EmptyString("discountCurveSymbol");
        }

        notional = p.notional;
        currency = p.currency;
        maturity = p.maturity;
        swapRate = p.swapRate;
        clientFixedRateRole = FixedRateRole(p.clientFixedRateRole);
        forwardCurveSymbol = p.forwardCurveSymbol;
        discountCurveSymbol = p.discountCurveSymbol;
    }

    function _isCurrencyCode(string memory value) internal pure returns (bool) {
        bytes memory characters = bytes(value);
        return characters.length == 3
            && _isUppercaseAsciiLetter(characters[0])
            && _isUppercaseAsciiLetter(characters[1])
            && _isUppercaseAsciiLetter(characters[2]);
    }

    function _isUppercaseAsciiLetter(bytes1 character) internal pure returns (bool) {
        uint8 code = uint8(character);
        return code >= 65 && code <= 90;
    }

    // ------------------------------ FpML Party References ------------------------------ */

    /// @notice Human-readable name of the client's fixed-rate role.
    function clientFixedRateRoleName() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "Payer" : "Receiver";
    }

    /// @notice XML id of the party paying the fixed-rate leg.
    function fixedLegPayerPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "client" : "productProvider";
    }

    /// @notice XML id of the party receiving the fixed-rate leg.
    function fixedLegReceiverPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "productProvider" : "client";
    }

    /// @notice XML id of the party paying the floating-rate leg.
    function floatingLegPayerPartyReference() external view returns (string memory) {
        return clientFixedRateRole == FixedRateRole.Payer ? "productProvider" : "client";
    }

    /// @notice XML id of the party receiving the floating-rate leg.
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
                "<ProductDocumentationTemplate>",
                    _include(productDocumentationTemplate),
                "</ProductDocumentationTemplate>",
            "</ProductResources>",
            "</InterestRateSwap>"
        );
    }
}
