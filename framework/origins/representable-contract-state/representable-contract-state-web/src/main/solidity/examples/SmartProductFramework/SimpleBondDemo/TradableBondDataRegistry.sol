// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractTradableProductRegistry} from "../ProductRegistry/AbstractTradableProductRegistry.sol";
import {SIMPLE_BOND_TYPE, COMMERCIAL_PAPER_TYPE, CURVE_INDICATION_CATEGORY, BOND_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE, BOND_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE} from "./BondConstants.sol";


/**
 * @title TradableBondDataRegistry
 * @notice Concrete, deployable registry for bond products. Specializes the
 *         generic tradable product data stack with bond-specific acceptance
 *         rules: which resource types may back a product definition, and which indication
 *         categories may be attached to which bond product types.
 * @dev Completes the layer chain:
 *      ProductDataRegistry (product definition + resources)
 *        -> IndicatedProductDataRegistry (product definition indications)
 *          -> TradableProductDataRegistry (trade requests + deployment)
 *            -> TradableBondDataRegistry (bond acceptance rules).
 *
 * @author Raphael Prandtl
 */
contract TradableBondDataRegistry is AbstractTradableProductRegistry {
    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param owner_                   Initial owner / product provider.
     * @param clientRegistryAddress_ Client registry for eligibility checks.
     */
    constructor(address owner_, address clientRegistryAddress_)
    AbstractTradableProductRegistry(owner_, clientRegistryAddress_)
    {}

    // ------------------------------ Business-Rule Hooks ------------------------------ */

    /// @dev Each slot accepts exactly its designated bond resource type.
    function _isAcceptedResourceType(ResourceSlot slot, bytes32 resourceType) internal pure override returns (bool) {
        if (slot == ResourceSlot.ProductTermsTemplate) {
            return resourceType == BOND_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE;
        }
        if (slot == ResourceSlot.ProductDocumentationTemplate) {
            return resourceType == BOND_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE;
        }
        return false;
    }

    /**
     * @dev Curve indications may back either bond product type (many-to-many:
     *      one category serves multiple product types).
     */
    function _isAcceptedIndication(bytes32 productTypeId, bytes32 indicationCategory) internal pure override returns (bool) {
        if (indicationCategory == CURVE_INDICATION_CATEGORY) {
            return productTypeId == SIMPLE_BOND_TYPE || productTypeId == COMMERCIAL_PAPER_TYPE;
        }
        return false;
    }
}
