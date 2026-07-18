// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BondConstants
 * @notice Canonical shared identifiers for the bond product stack. Centralized
 *         so that product types, indication categories, and resource types
 *         cannot drift between the registry, factories, indication registries,
 *         and the text resources they classify.
 * @dev File-level constants: import the specific names where needed, e.g.
 *      `import {SIMPLE_BOND_TYPE} from ".../BondConstants.sol";`
 *
 * @author Raphael Prandtl
 */

// ------------------------------ Product Types ------------------------------ */

/**
 * @dev Product type served by SimpleBondFactory. Used as:
 *      - SimpleBondFactory.productTypeId(),
 *      - a product definition's productTypeId when publishing a demo-bond product,
 *      - an accepted type for curve indications in the bond registry.
 */
bytes32 constant SIMPLE_BOND_TYPE = keccak256("SIMPLE_BOND");

/// @dev Product type for commercial paper (future factory).
bytes32 constant COMMERCIAL_PAPER_TYPE = keccak256("COMMERCIAL_PAPER");

// ------------------------------ Indication Categories ------------------------------ */

/**
 * @dev Category advertised by CurveIndications.indicationCategory() and
 *      accepted for bond product types in the bond registry.
 */
bytes32 constant CURVE_INDICATION_CATEGORY = keccak256("CURVE");

// ------------------------------ Resource Types ------------------------------ */

/**
 * @dev resourceType() a text resource must declare to back the product terms
 *      template slot of a bond product.
 */
bytes32 constant BOND_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE = keccak256("BOND_PRODUCT_TERMS_TEMPLATE");

/**
 * @dev resourceType() a text resource must declare to back the product
 *      documentation template slot of a bond product.
 */
bytes32 constant BOND_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE = keccak256("BOND_PRODUCT_DOCUMENTATION_TEMPLATE");
