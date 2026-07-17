// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductSpecificFactory} from "../ProductFactory/AbstractProductSpecificFactory.sol";
import {ProductDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";
import {SimpleBond} from "./SimpleBond.sol";
import {SIMPLE_BOND_TYPE} from "./BondConstants.sol";

/**
 * @title SimpleBondFactory
 * @notice Product-specific factory that deploys SimpleBond products.
 * @dev Caller restriction (onlyGenericFactory) and schema validation are
 *      handled by AbstractProductSpecificFactory.sol.sol; this contract only decodes
 *      the payload, validates the economics, and constructs the bond.
 *
 * @author Raphael Prandtl
 */
contract SimpleBondFactory is AbstractProductSpecificFactory {
    // ------------------------------ Constants ------------------------------ */

    /// @notice Human-readable schema of the expected productSpecificPayload.
    string internal constant PRODUCT_SPECIFIC_PAYLOAD_SCHEMA = "v1:SimpleBondDeploymentPayload(uint256 notional,uint256 maturity)";

    /// @notice Hash of the payload schema, matched against incoming params.
    bytes32 internal constant PRODUCT_SPECIFIC_SCHEMA_HASH = keccak256(bytes(PRODUCT_SPECIFIC_PAYLOAD_SCHEMA));

    // ------------------------------ Constructor ------------------------------ */

    /// @param genericFactory_ The generic factory that will invoke this factory.
    constructor(address genericFactory_) AbstractProductSpecificFactory(genericFactory_) {}

    // ------------------------------ Product Specification ------------------------------ */

    function productTypeId() public pure override returns (bytes32) {
        return SIMPLE_BOND_TYPE;
    }

    function productSpecificPayloadSchema() external pure override returns (string memory) {
        return PRODUCT_SPECIFIC_PAYLOAD_SCHEMA;
    }

    function productSpecificSchemaHash() public pure override returns (bytes32) {
        return PRODUCT_SPECIFIC_SCHEMA_HASH;
    }

    // ------------------------------ Product-Specific Deploy ------------------------------ */

    function _deployProduct(ProductDeploymentParams calldata params) internal override returns (address product) {
        product = address(new SimpleBond(params.common, params.productSpecificPayload));
    }

}
