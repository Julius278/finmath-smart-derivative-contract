// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SwapConstants
 * @notice Canonical identifiers shared by the lightweight interest-rate-swap
 *         product, factory, registry, and text resources.
 *
 * @author Raphael Prandtl
 */

// ------------------------------ Product Types ------------------------------ */

/// @dev Product type served by InterestRateSwapFactory.
bytes32 constant INTEREST_RATE_SWAP_TYPE = keccak256("INTEREST_RATE_SWAP");

// ------------------------------ Resource Types ------------------------------ */

/// @dev Resource type accepted for an interest-rate swap's product terms template.
bytes32 constant INTEREST_RATE_SWAP_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE =
    keccak256("INTEREST_RATE_SWAP_PRODUCT_TERMS_TEMPLATE");

/// @dev Resource type accepted for an interest-rate swap's documentation template.
bytes32 constant INTEREST_RATE_SWAP_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE =
    keccak256("INTEREST_RATE_SWAP_PRODUCT_DOCUMENTATION_TEMPLATE");
