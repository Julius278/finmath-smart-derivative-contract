// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IProduct
 * @notice Interface for a deployed product exposing its immutable deployment
 *         context.
 *
 * @dev The deployment context is assembled by the product registry and fixed at
 *      construction time. It deliberately contains NO counterparty information:
 *      a product may be issued with or without preceding trade requests, and the
 *      client is only bound later during trade inception.
 *
 * @author Raphael Prandtl
 */
interface IProduct {
    // ------------------------------ Deployment State ------------------------------ */

    /// @notice Returns the factory that deployed the product.
    function productFactory() external view returns (address);

    /// @notice Returns the product registry that initiated deployment.
    function productRegistry() external view returns (address);

    /// @notice Returns the product provider (issuer/seller) of this product.
    function productProvider() external view returns (address);

    /// @notice Returns the product definition used for deployment.
    function productDefinitionId() external view returns (bytes32);

    /// @notice Returns the product definition version used for deployment.
    function productDefinitionVersion() external view returns (uint256);

    /// @notice Returns the product terms template resource.
    function productTermsTemplate() external view returns (address);

    /// @notice Returns the product documentation template resource.
    function productDocumentationTemplate() external view returns (address);
}