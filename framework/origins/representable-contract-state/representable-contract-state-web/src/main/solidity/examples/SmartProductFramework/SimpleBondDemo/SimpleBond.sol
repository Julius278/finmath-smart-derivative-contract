// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "../Product/AbstractProduct.sol";
import {CommonDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";

/**
 * @title SimpleBond
 * @notice Minimal demo product: a bond with negotiable notional and maturity.
 * @dev The product owns its payload format: it decodes the raw
 *      productPayload once (in _applyTerms), used both at construction
 *      and on client updates. Economic bindings (Notional, Maturity) live in
 *      the product terms template and resolve against notional()/maturity().
 *
 * @author Raphael Prandtl
 */
contract SimpleBond is AbstractProduct {
    // ------------------------------ Mutable State ------------------------------ */

    /// @notice Requested/negotiated notional. Resolves the product terms template's Notional binding.
    uint256 public notional;
    /// @notice Requested/negotiated maturity (unix timestamp).
    uint256 public maturity;

    // ------------------------------ Structs ------------------------------ */

    /// @notice Decoded product-specific payload for a SimpleBond.
    struct ProductPayload {
        uint256 notional;
        uint256 maturity;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the requested notional is zero.
    error InvalidNotional();
    /// @notice Thrown when the requested maturity is not in the future.
    error InvalidMaturity();

    error InvalidPayloadLength(uint256 expected, uint256 actual);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param c                     Common deployment parameters.
     * @param productPayload        Raw ABI-encoded ProductPayload.
     */
    constructor(CommonDeploymentParams memory c, bytes memory productPayload)
    AbstractProduct(c)
    {
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

    /**
     * @dev Single decode + validate + set, shared by construction and updates.
     *      Accepts memory so it is callable from both the constructor and the
     *      calldata-based _updateTerms path.
     */
    function _applyTerms(bytes memory productPayload) internal {
        if (productPayload.length != 64) {
            revert InvalidPayloadLength(64, productPayload.length);
        }
        ProductPayload memory p = abi.decode(productPayload, (ProductPayload));

        if (p.notional == 0) {
            revert InvalidNotional();
        }
        if (p.maturity <= block.timestamp) {
            revert InvalidMaturity();
        }
        notional = p.notional;
        maturity = p.maturity;
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
