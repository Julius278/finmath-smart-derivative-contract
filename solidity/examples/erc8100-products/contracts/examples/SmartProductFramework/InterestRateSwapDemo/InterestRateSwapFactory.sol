// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductFactory} from "../ProductFactory/AbstractProductFactory.sol";
import {ProductDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";
import {InterestRateSwap} from "./InterestRateSwap.sol";

/**
 * @title InterestRateSwapFactory
 * @notice Factory defining and deploying the InterestRateSwap product specification.
 *
 * @dev Defines the product payload schema and required resource types.
 *      This product specification does not accept product indications.
 *
 * @author Raphael Prandtl
 */
contract InterestRateSwapFactory is AbstractProductFactory {
    // ------------------------------ Constants ------------------------------ */

    /// @notice Human-readable schema of the expected product payload.
    string internal constant PRODUCT_PAYLOAD_SCHEMA = "v1:InterestRateSwapDeploymentPayload(uint256 notional,string currency,uint256 maturity,int256 swapRate,uint8 clientFixedRateRole,string forwardCurveSymbol,string discountCurveSymbol)";

    /// @notice Required resource type of the product terms template.
    bytes32 internal constant PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE = keccak256("SPF:INTEREST_RATE_SWAP:PRODUCT_TERMS_TEMPLATE:V1");

    /// @notice Required resource type of the product documentation template.
    bytes32 internal constant PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE = keccak256("SPF:INTEREST_RATE_SWAP:PRODUCT_DOCUMENTATION_TEMPLATE:V1");

    // ------------------------------ Constructor ------------------------------ */

    /// @param productRegistry_ Product registry authorized to use this factory.
    constructor(address productRegistry_)AbstractProductFactory(productRegistry_) {}

    // ------------------------------ Product Specification ------------------------------ */

    /// @inheritdoc AbstractProductFactory
    function productPayloadSchema() external pure override returns (string memory) {
        return PRODUCT_PAYLOAD_SCHEMA;
    }

    /// @inheritdoc AbstractProductFactory
    function productTermsTemplateResourceType() external pure override returns (bytes32) {
        return PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE;
    }

    /// @inheritdoc AbstractProductFactory
    function productDocumentationTemplateResourceType() external pure override returns (bytes32) {
        return PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE;
    }

    // ------------------------------ Product Indication ------------------------------ */

    /// @inheritdoc AbstractProductFactory
    function isAcceptedIndicationCategory(bytes32) external pure override returns (bool){
        return false;
    }

    // ------------------------------ Product-Specific Deploy ------------------------------ */

    /// @inheritdoc AbstractProductFactory
    function _deployProduct(ProductDeploymentParams calldata params) internal override returns (address product){
        product = address(new InterestRateSwap(params.common, params.productPayload));
    }
}
