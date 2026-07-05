// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractTradableProductDataRegistry} from "./ProductDataRegistry/AbstractTradableProductDataRegistry.sol";
import {SIMPLE_BOND_TYPE, COMMERCIAL_PAPER_TYPE, CURVE_INDICATION_CATEGORY, BOND_TERMS_RESOURCE_TYPE, BOND_STYLESHEET_RESOURCE_TYPE} from "../SimpleBondDemo/BondConstants.sol";


/// @title TradableBondDataRegistry
/// @notice Concrete, deployable registry for bond programs. Specializes the
///         generic tradable product data stack with bond-specific acceptance
///         rules: which resource types may back a program, and which indication
///         categories may be attached to which bond product types.
/// @dev Completes the layer chain:
///      ProductDataRegistry (programs + resources)
///        -> IndicatedProductDataRegistry (program indications)
///          -> TradableProductDataRegistry (trade requests + deployment)
///            -> TradableBondDataRegistry (bond acceptance rules).
///
/// @author Raphael Prandtl
contract TradableBondDataRegistry is AbstractTradableProductDataRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_                   Initial owner / issuer.
    /// @param investorRegistryAddress_ Investor registry for eligibility checks.
    constructor(address owner_, address investorRegistryAddress_)
    AbstractTradableProductDataRegistry(owner_, investorRegistryAddress_)
    {}

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    BUSINESS-RULE HOOKS                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc AbstractProductDataRegistry
    /// @dev Each slot accepts exactly its designated bond resource type.
    function _isAcceptedResourceType(ResourceSlot slot, bytes32 resourceType) internal pure override returns (bool) {
        if (slot == ResourceSlot.ProductTerms) {
            return resourceType == BOND_TERMS_RESOURCE_TYPE;
        }
        if (slot == ResourceSlot.StyleSheet) {
            return resourceType == BOND_STYLESHEET_RESOURCE_TYPE;
        }
        return false;
    }

    /// @inheritdoc AbstractIndicatedProductDataRegistry
    /// @dev Curve indications may back either bond product type (many-to-many:
    ///      one category serves multiple product types).
    function _isAcceptedIndication(bytes32 productTypeId, bytes32 indicationCategory) internal pure override returns (bool) {
        if (indicationCategory == CURVE_INDICATION_CATEGORY) {
            return productTypeId == SIMPLE_BOND_TYPE || productTypeId == COMMERCIAL_PAPER_TYPE;
        }
        return false;
    }
}
