// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IXMLRepresentableState} from "../../../IRepresentableState.sol";

/**
 * @title IProduct
 * @notice A deployed product instance. Exposes the deployment state captured
 *         from CommonDeploymentParams and resolves its own on-chain state for
 *         rendering (IXMLRepresentableState).
 *
 * @dev DEPLOYMENT ANCHOR & VERIFICATION
 *      deploymentStateHash() is an integrity anchor computed by the tradable
 *      product registry at trade time over the exact product definition state
 *      (version + immutable resource contents) and the agreed product-specific
 *      payload. It is stored immutably here and can be recomputed off-chain from
 *      this product's getters (plus the original payload) to verify the product
 *      was minted against the agreed terms.
 *
 * @dev AUTHENTICITY
 *      productFactory() returns the product-specific factory that deployed this
 *      product (its constructor's msg.sender). Combined with
 *      IProductSpecificFactory.isFactoryDeployedProduct(this), it forms a
 *      bidirectional authenticity proof, and lets consumers read the product's
 *      schema/type from the authoritative factory.
 *
 * @dev STATE RENDERING
 *      The product definition registry anchors the product terms template and
 *      product documentation template as inert text; the deployed product is
 *      the concrete instance that RESOLVES the product terms template's
 *      evmstate:call bindings against its own getters (e.g. notional()). The
 *      getter surface MUST match the bindings referenced by the product terms template
 *      for the product's productTypeId.
 *
 * @author Raphael Prandtl
 */
interface IProduct is IXMLRepresentableState {
    // ------------------------------ Events ------------------------------ */

    /**
     * @notice Emitted whenever the product's mutable state changes (including
     *         the initial state set at construction). Lets off-chain consumers
     *         track the product through its lifecycle.
     */
    event StateUpdated(address indexed sender, address indexed stateContract, bytes32 currentStateHash);

    // ------------------------------ Deployment State ------------------------------ */

    /// @notice Returns the tradable product registry that initiated deployment.
    function productRegistry() external view returns (address);

    /**
     * @notice Returns the product-specific factory that deployed this product.
     * @dev Captured as the constructor's msg.sender. Enables authenticity
     *      verification via
     *      IProductSpecificFactory(productFactory()).isFactoryDeployedProduct(this).
     */
    function productSpecificFactory() external view returns (address);

    /// @notice Returns the unique trade identifier this product was created for.
    function tradeId() external view returns (bytes32);

    /**
     * @notice Returns the product provider of the product.
     * @dev This is the registry owner at deployment time.
     */
    function productProvider() external view returns (address);

    /// @notice Returns the client the product was created for.
    function client() external view returns (address);

    /// @notice Returns the product definition this product was created under.
    function productDefinitionId() external view returns (bytes32);

    /**
     * @notice Returns the product definition version in force at deployment time.
     * @dev Pins the exact product definition revision the product was deployed
     *      against. This value is part of the deploymentStateHash preimage.
     */
    function productDefinitionVersion() external view returns (uint256);

    /// @notice Returns the ITextResource holding the product terms template.
    function productTermsTemplate() external view returns (address);

    /// @notice Returns the ITextResource holding the product documentation template.
    function productDocumentationTemplate() external view returns (address);

    /**
     * @notice Returns the product type identifier.
     * @dev Matches the deploying product-specific factory's productTypeId()
     *      and the product definition's productTypeId.
     */
    function productTypeId() external view returns (bytes32);

    /**
     * @notice Returns the deployment integrity anchor.
     * @dev See the contract-level "DEPLOYMENT ANCHOR & VERIFICATION" note.
     */
    function deploymentStateHash() external view returns (bytes32);
}
