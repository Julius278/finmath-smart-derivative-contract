// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProductDeploymentTypes
 * @notice Shared data types for product deployment, used by the product
 *         factory, product-specific factories, and all deployable products.
 * @dev File-level structs (no library/interface wrapper) so any contract can
 *      import them directly without pulling in unrelated ABI surface.
 *
 * @author Raphael Prandtl
 */

/**
 * @notice Product-agnostic deployment context assembled by the registry.
 * @param productRegistry           The calling tradable product registry.
 * @param tradeId                   Unique trade identifier.
 * @param productProvider           The product provider, usually the registry
 *                                  owner at deployment time.
 * @param investor                  The investor initiating the trade.
 * @param productDefinitionId       The product definition the product is
 *                                  created under.
 * @param productDefinitionVersion  The version of the product definition at
 *                                  deployment time.
 * @param termsResource             ITextResource holding the product terms.
 * @param stylesheetResource        ITextResource holding the stylesheet.
 * @param productTypeId             Identifies the deployable product type.
 * @param deploymentStateHash       Integrity anchor of the product definition
 *                                  state and agreed payload at trade time.
 */
struct CommonDeploymentParams {
    address productRegistry;
    bytes32 tradeId;
    address productProvider;
    address investor;
    bytes32 productDefinitionId;
    uint256 productDefinitionVersion;
    address termsResource;
    address stylesheetResource;
    bytes32 productTypeId;
    bytes32 deploymentStateHash;
}

/**
 * @notice Full deployment parameters: common context plus product-specific
 *         payload.
 * @param common                    Product-agnostic deployment context.
 * @param productSpecificSchemaHash Identifies the schema of the payload.
 * @param productSpecificPayload    ABI-encoded product-specific economics,
 *                                  opaque to the generic factory.
 */
struct ProductDeploymentParams {
    CommonDeploymentParams common;
    bytes32 productSpecificSchemaHash;
    bytes productSpecificPayload;
}
