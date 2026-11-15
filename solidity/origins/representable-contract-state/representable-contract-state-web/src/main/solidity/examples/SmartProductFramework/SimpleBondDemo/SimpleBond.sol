// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "../Product/AbstractProduct.sol";
import {CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title SimpleBond
 * @notice Example bond product with negotiable notional and maturity.
 *
 * @dev Decodes and validates the SimpleBond product payload during deployment
 *      and subsequent term updates.
 *
 * @author Raphael Prandtl
 */
contract SimpleBond is AbstractProduct {
    // ------------------------------ Constants ------------------------------ */

    uint256 private constant PRODUCT_PAYLOAD_LENGTH = 64;

    // ------------------------------ Mutable State ------------------------------ */

    /// @notice Current bond notional.
    uint256 public notional;
    /// @notice Current bond maturity as a Unix timestamp.
    uint256 public maturity;

    // ------------------------------ Structs ------------------------------ */

    /// @notice ABI-decoded payload used to set the bond terms.
    struct SimpleBondDeploymentPayload {
        uint256 notional;
        uint256 maturity;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the notional is zero.
    error InvalidNotional();
    /// @notice Thrown when the maturity is not in the future.
    error InvalidMaturity();

    /// @notice Thrown when the encoded payload has an invalid length.
    error InvalidPayloadLength(uint256 expected, uint256 actual);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param common         Common deployment parameters.
     * @param productPayload ABI-encoded SimpleBondDeploymentPayload.
     */
    constructor(CommonDeploymentParams memory common, bytes memory productPayload) AbstractProduct(common) {
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
        return keccak256(abi.encode(notional, maturity));
    }

    /// @notice Decodes, validates, and applies a complete product payload.
    function _applyTerms(bytes memory productPayload) internal {
        if (productPayload.length != PRODUCT_PAYLOAD_LENGTH) {
            revert InvalidPayloadLength(PRODUCT_PAYLOAD_LENGTH, productPayload.length);
        }
        SimpleBondDeploymentPayload memory payload = abi.decode(productPayload, (SimpleBondDeploymentPayload));
        if (payload.notional == 0) {
            revert InvalidNotional();
        }
        if (payload.maturity <= block.timestamp) {
            revert InvalidMaturity();
        }
        notional = payload.notional;
        maturity = payload.maturity;
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc AbstractProduct
    function _productSpecificStateXml() internal view override returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<SimpleBond xmlns=\"urn:smart-product-framework:simple-bond:1.0\"",
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
            "</SimpleBond>"
        );
    }
}
