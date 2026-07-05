// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BondConstants
/// @notice Canonical shared identifiers for the bond product stack. Centralized
///         so that product types, indication categories, and resource types
///         cannot drift between the registry, factories, indication registries,
///         and the text resources they classify.
/// @dev File-level constants: import the specific names where needed, e.g.
///      `import {SIMPLE_BOND_TYPE} from ".../BondConstants.sol";`
///
/// @author Raphael Prandtl

/*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
/*                       PRODUCT TYPES                       */
/*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

/// @dev Product type served by SimpleBondFactory. Used as:
///      - SimpleBondFactory.productTypeId(),
///      - a program's productTypeId when publishing a demo-bond program,
///      - an accepted type for curve indications in the bond registry.
bytes32 constant SIMPLE_BOND_TYPE = keccak256("SIMPLE_BOND");

/// @dev Product type for commercial paper (future factory).
bytes32 constant COMMERCIAL_PAPER_TYPE = keccak256("COMMERCIAL_PAPER");

/*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
/*                   INDICATION CATEGORIES                   */
/*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

/// @dev Category advertised by CurveIndications.indicationCategory() and
///      accepted for bond product types in the bond registry.
bytes32 constant CURVE_INDICATION_CATEGORY = keccak256("CURVE");

/*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
/*                      RESOURCE TYPES                       */
/*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

/// @dev resourceType() a text resource must declare to back the product-terms
///      slot of a bond program.
bytes32 constant BOND_TERMS_RESOURCE_TYPE = keccak256("BOND_TERMS");

/// @dev resourceType() a text resource must declare to back the stylesheet slot
///      of a bond program.
bytes32 constant BOND_STYLESHEET_RESOURCE_TYPE = keccak256("BOND_STYLESHEET");
