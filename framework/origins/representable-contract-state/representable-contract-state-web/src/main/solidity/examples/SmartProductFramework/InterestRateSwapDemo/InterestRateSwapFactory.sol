// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductSpecificFactory} from "../ProductFactory/AbstractProductSpecificFactory.sol";
import {ProductDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";
import {InterestRateSwap} from "./InterestRateSwap.sol";
import {INTEREST_RATE_SWAP_TYPE} from "./SwapConstants.sol";

/**
 * @title InterestRateSwapFactory
 * @notice Product-specific factory for lightweight fixed-versus-floating swaps.
 * @dev notional has decimal scale 2, swapRate has decimal scale 4, and
 *      clientFixedRateRole is encoded as 0 (Payer) or 1 (Receiver).
 *
 * @author Raphael Prandtl
 */
contract InterestRateSwapFactory is AbstractProductSpecificFactory {
    // ------------------------------ Constants ------------------------------ */

    /// @notice Human-readable schema of the expected productSpecificPayload.
    string internal constant PRODUCT_SPECIFIC_PAYLOAD_SCHEMA =
        "v1:InterestRateSwapDeploymentPayload(uint256 notional,string currency,uint256 maturity,int256 swapRate,uint8 clientFixedRateRole,string forwardCurveSymbol,string discountCurveSymbol)";

    /// @notice Hash of the payload schema, matched against incoming parameters.
    bytes32 internal constant PRODUCT_SPECIFIC_SCHEMA_HASH =
        keccak256(bytes(PRODUCT_SPECIFIC_PAYLOAD_SCHEMA));

    // ------------------------------ Constructor ------------------------------ */

    /// @param genericFactory_ The generic factory that will invoke this factory.
    constructor(address genericFactory_) AbstractProductSpecificFactory(genericFactory_) {}

    // ------------------------------ Product Specification ------------------------------ */

    function productTypeId() public pure override returns (bytes32) {
        return INTEREST_RATE_SWAP_TYPE;
    }

    function productSpecificPayloadSchema() external pure override returns (string memory) {
        return PRODUCT_SPECIFIC_PAYLOAD_SCHEMA;
    }

    function productSpecificSchemaHash() public pure override returns (bytes32) {
        return PRODUCT_SPECIFIC_SCHEMA_HASH;
    }

    // ------------------------------ Product-Specific Deploy ------------------------------ */

    function _deployProduct(ProductDeploymentParams calldata params) internal override returns (address product) {
        product = address(new InterestRateSwap(params.common, params.productSpecificPayload));
    }
}
