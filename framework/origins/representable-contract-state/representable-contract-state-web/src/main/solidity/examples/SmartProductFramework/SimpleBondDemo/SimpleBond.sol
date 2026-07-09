// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "./Product/AbstractProduct.sol";
import {CommonDeploymentParams} from "./ProductFactory/ProductDeploymentTypes.sol";

/// @title SimpleBond
/// @notice Minimal demo product: a bond with negotiable notional and maturity.
/// @dev The product owns its payload format: it decodes the raw
///      productSpecificPayload once (in _applyTerms), used both at construction
///      and on investor updates. Economic bindings (Notional, Maturity) live in
///      the product terms XML resource and resolve against notional()/maturity().
///
/// @author Raphael Prandtl
contract SimpleBond is AbstractProduct {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                        MUTABLE STATE                      */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Requested/negotiated notional. Resolves the terms' Notional binding.
    uint256 public notional;
    /// @notice Requested/negotiated maturity (unix timestamp).
    uint256 public maturity;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STRUCTS                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Decoded product-specific payload for a SimpleBond.
    struct ProductSpecificPayload {
        uint256 notional;
        uint256 maturity;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when the requested notional is zero.
    error InvalidNotional();
    /// @notice Thrown when the requested maturity is not in the future.
    error InvalidMaturity();

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param c                     Common deployment parameters.
    /// @param productSpecificPayload Raw ABI-encoded ProductSpecificPayload.
    constructor(CommonDeploymentParams memory c, bytes memory productSpecificPayload)
    AbstractProduct(c)
    {
        _applyTerms(productSpecificPayload);
        emit StateUpdated(msg.sender, address(this), currentTermsHash());
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       TERMS HOOKS                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc AbstractProduct
    function _updateTerms(bytes calldata productSpecificPayload) internal override {
        _applyTerms(productSpecificPayload);
    }

    /// @inheritdoc AbstractProduct
    function _economicTermsHash() internal view override returns (bytes32) {
        return keccak256(abi.encode(notional, maturity));
    }

    /// @dev Single decode + validate + set, shared by construction and updates.
    ///      Accepts memory so it is callable from both the constructor and the
    ///      calldata-based _updateTerms path.
    function _applyTerms(bytes memory productSpecificPayload) internal {
        ProductSpecificPayload memory p = abi.decode(productSpecificPayload, (ProductSpecificPayload));

        if (p.notional == 0) {
            revert InvalidNotional();
        }
        if (p.maturity <= block.timestamp) {
            revert InvalidMaturity();
        }
        notional = p.notional;
        maturity = p.maturity;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          XML VIEW                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc AbstractProduct
    function _productSpecificStateXml() internal view override returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<SimpleBond xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\">",
            _deploymentStateXml(),
            _include(termsResource),
            _include(stylesheetResource),
            "</SimpleBond>"
        );
    }
}
