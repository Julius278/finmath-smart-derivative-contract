// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ProductDeploymentParams} from "./ProductDeploymentTypes.sol";

/**
 * @title IProductFactory
 * @notice Interface for a factory defining and deploying one product specification.
 *
 * @dev A product definition anchors the exact factory used for deployment.
 *      The factory provides the expected payload schema, required resource
 *      types, accepted indication categories, and product deployment.
 *
 * @author Raphael Prandtl
 */
interface IProductFactory is IERC165 {
    // ------------------------------ Events ------------------------------------- */

    /// @notice Emitted after a product has been deployed.
    event ProductDeployed(address indexed productProvider, bytes32 indexed productDefinitionId, address product);

    // ------------------------------ Factory Configuration ------------------------------ */

    /// @notice Returns the product registry authorized to deploy through this factory.
    function productRegistryAddress() external view returns (address);

    // ------------------------------ Product Specification ------------------------------ */

    /// @notice Returns a human-readable description of the expected product payload.
    function productPayloadSchema() external view returns (string memory);

    /// @notice Returns the required resource type of the product terms template.
    function productTermsTemplateResourceType() external view returns (bytes32);

    /// @notice Returns the required resource type of the product documentation template.
    function productDocumentationTemplateResourceType() external view returns (bytes32);

    // ------------------------------ Product Indication ------------------------------ */

    /// @notice Returns whether an indication category is accepted by this factory.
    function isAcceptedIndicationCategory(bytes32 indicationCategory) external view returns (bool);

    // ------------------------------ Product Authenticity ------------------------------ */

    /// @notice Returns whether a product was deployed by this factory.
    function isFactoryDeployedProduct(address product) external view returns (bool);

    // ------------------------------ Product Deployment ------------------------------ */

    /**
     * @notice Deploys a product using the supplied deployment parameters.
     * @dev Must only be callable by productRegistryAddress().
     */
    function deployProduct(ProductDeploymentParams calldata params) external returns (address product);
}
