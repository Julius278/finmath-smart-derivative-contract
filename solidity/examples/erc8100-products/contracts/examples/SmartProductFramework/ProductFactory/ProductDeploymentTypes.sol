// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProductDeploymentTypes
 * @notice Shared parameters used to deploy product contracts.
 *
 * @author Raphael Prandtl
 */

/**
 * @notice Product-independent deployment context assembled by the product registry.
 * @param productRegistry              Product registry initiating the deployment.
 * @param tradeId                      Unique identifier of the trade.
 * @param productProvider              Provider of the product.
 * @param client                       Client entering into the trade.
 * @param productDefinitionId          Product definition used for the deployment.
 * @param productDefinitionVersion     Version of the product definition at deployment.
 * @param productTermsTemplate         Product terms text resource.
 * @param productDocumentationTemplate Product documentation text resource.
 * @param deploymentStateHash          Integrity hash of the anchored deployment state.
 */
struct CommonDeploymentParams {
    address productRegistry;
    bytes32 tradeId;
    address productProvider;
    address client;
    bytes32 productDefinitionId;
    uint256 productDefinitionVersion;
    address productTermsTemplate;
    address productDocumentationTemplate;
    bytes32 deploymentStateHash;
}

/**
 * @notice Complete parameters passed to a product factory.
 * @param common         Product-independent deployment context.
 * @param productPayload ABI-encoded product-specific payload.
 */
struct ProductDeploymentParams {
    CommonDeploymentParams common;
    bytes productPayload;
}
