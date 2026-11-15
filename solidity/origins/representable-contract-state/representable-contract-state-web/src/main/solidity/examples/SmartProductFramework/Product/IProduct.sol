// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IXMLRepresentableState} from "../../../IRepresentableState.sol";

/**
 * @title IProduct
 * @notice Interface for a deployed product exposing its immutable deployment
 *         context and XML-representable state.
 *
 * @dev The product records the factory that deployed it and the deployment
 *      state hash assembled by the product registry.
 *
 * @author Raphael Prandtl
 */
interface IProduct is IXMLRepresentableState {
    // ------------------------------ Events ------------------------------

    /// @notice Emitted when the product state changes.
    event StateUpdated(address indexed sender, address indexed stateContract, bytes32 currentStateHash);

    // ------------------------------ Deployment State ------------------------------

    /// @notice Returns the product registry that initiated deployment.
    function productRegistry() external view returns (address);

    /// @notice Returns the factory that deployed the product.
    function productFactory() external view returns (address);

    /// @notice Returns the trade identifier associated with the product.
    function tradeId() external view returns (bytes32);

    /// @notice Returns the product provider.
    function productProvider() external view returns (address);

    /// @notice Returns the client.
    function client() external view returns (address);

    /// @notice Returns the product definition used for deployment.
    function productDefinitionId() external view returns (bytes32);

    /// @notice Returns the product definition version used for deployment.
    function productDefinitionVersion() external view returns (uint256);

    /// @notice Returns the product terms template resource.
    function productTermsTemplate() external view returns (address);

    /// @notice Returns the product documentation template resource.
    function productDocumentationTemplate() external view returns (address);

    /// @notice Returns the deployment state integrity hash.
    function deploymentStateHash() external view returns (bytes32);
}
