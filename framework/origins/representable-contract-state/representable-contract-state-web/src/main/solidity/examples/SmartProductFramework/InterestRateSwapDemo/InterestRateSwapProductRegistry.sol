// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductRegistry} from "../ProductRegistry/AbstractProductRegistry.sol";
import {
    INTEREST_RATE_SWAP_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE,
    INTEREST_RATE_SWAP_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE
} from "./SwapConstants.sol";

/**
 * @title InterestRateSwapProductRegistry
 * @notice Product registry specialized for the interest-rate-swap templates.
 * @dev Forward and discount curves are symbolic product terms in this minimal
 *      example, so no separate product-indication category is accepted.
 *
 * @author Raphael Prandtl
 */
contract InterestRateSwapProductRegistry is AbstractProductRegistry {
    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param owner_                 Initial owner / product provider.
     * @param clientRegistryAddress_ Client registry for eligibility checks.
     */
    constructor(address owner_, address clientRegistryAddress_)
    AbstractProductRegistry(owner_, clientRegistryAddress_)
    {}

    // ------------------------------ Business-Rule Hooks ------------------------------ */

    /// @dev Each slot accepts exactly its designated swap resource type.
    function _isAcceptedResourceType(ResourceSlot slot, bytes32 resourceType) internal pure override returns (bool) {
        if (slot == ResourceSlot.ProductTermsTemplate) {
            return resourceType == INTEREST_RATE_SWAP_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE;
        }
        if (slot == ResourceSlot.ProductDocumentationTemplate) {
            return resourceType == INTEREST_RATE_SWAP_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE;
        }
        return false;
    }

    /// @dev This minimal swap represents curve references as terms, not indications.
    function _isAcceptedIndication(bytes32, bytes32) internal pure override returns (bool) {
        return false;
    }
}
