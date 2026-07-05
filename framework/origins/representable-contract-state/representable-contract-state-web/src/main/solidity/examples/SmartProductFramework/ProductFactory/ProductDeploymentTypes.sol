// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ProductDeploymentTypes
/// @notice Shared data types for product deployment, used by the product
///         factory, product-specific factories, and all deployable products.
/// @dev File-level structs (no library/interface wrapper) so any contract can
///      import them directly without pulling in unrelated ABI surface.
///
/// @author Raphael Prandtl

/// @notice Product-agnostic deployment context assembled by the registry.
/// @param productRegistry      The calling registry.
/// @param tradeId              Unique trade identifier.
/// @param issuer               The issuer (program owner).
/// @param investor             The investor initiating the trade.
/// @param programId            The program the product is created under.
/// @param programVersion       The version of the program at deployment time.
/// @param productTermsResource ITextResource holding the product terms.
/// @param styleSheetResource   ITextResource holding the stylesheet.
/// @param productTypeId        Identifies the deployable product type.
/// @param deploymentStateHash  Integrity anchor of the program state and agreed
///                             payload at trade time (see registry docs).
    struct CommonDeploymentParams {
        address productRegistry;
        bytes32 tradeId;
        address issuer;
        address investor;
        bytes32 programId;
        uint256 programVersion;
        address productTermsResource;
        address styleSheetResource;
        bytes32 productTypeId;
        bytes32 deploymentStateHash;
    }

/// @notice Full deployment parameters (common + product-specific payload).
/// @param common                    Product-agnostic context.
/// @param productSpecificSchemaHash Identifies the schema of the payload.
/// @param productSpecificPayload    ABI-encoded, product-specific economics,
///                                  opaque to the generic factory.
    struct ProductDeploymentParams {
        CommonDeploymentParams common;
        bytes32 productSpecificSchemaHash;
        bytes productSpecificPayload;
    }
