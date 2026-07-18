// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ProductDeploymentParams} from "./ProductDeploymentTypes.sol";

/**
 * @title IProductFactory
 * @notice Generic, registry-facing product factory. Resolves a productTypeId
 *         to a registered product-specific factory and forwards the deployment
 *         request to it.
 *
 * @dev ARCHITECTURE
 *      This is the factory the product trade-request registry (layer 3) talks to.
 *      It maintains a mapping productTypeId -> product-specific factory and
 *      delegates the actual construction. The product-specific payload is
 *      opaque to it and passed through untouched.
 *
 * @dev TRUST / VALIDATION BOUNDARY
 *      - The registry validates product definition status, client eligibility,
 *        and product-type deployability (via canDeployProduct) before calling.
 *      - deployProduct MUST be callable only by productRegistryAddress() and
 *        MUST re-enforce deployability (the registry's pre-check and this call
 *        are not atomic w.r.t. a factory swap).
 *
 * @author Raphael Prandtl
 */
interface IProductFactory is IERC165 {
    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when the caller is not the configured product registry.
    error NotProductRegistry(address caller);

    /**
     * @notice Thrown when no product-specific factory is registered (and
     *         active) for the given product type.
     */
    error UnknownProductType(bytes32 productTypeId);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a product is deployed.
    event ProductDeployed(bytes32 indexed tradeId, bytes32 indexed productDefinitionId, bytes32 indexed productTypeId, address product, address productProvider, address client);

    // ------------------------------ Factory Views ------------------------------ */

    /// @notice Returns the registry authorized to call deployProduct.
    function productRegistryAddress() external view returns (address);

    /**
     * @notice Returns whether an active product-specific factory exists for
     *         the given product type.
     */
    function canDeployProduct(bytes32 productTypeId) external view returns (bool);

    // ------------------------------ Product Deployment ------------------------------ */

    /**
     * @notice Deploys a product for the given parameters by delegating to the
     *         product-specific factory registered for its product type.
     * @dev MUST be callable only by productRegistryAddress(); MUST revert
     *      UnknownProductType if the type is not deployable; MUST emit
     *      ProductDeployed.
     */
    function deployProduct(ProductDeploymentParams calldata params) external returns (address product);
}

/**
 * @title IProductSpecificFactory
 * @notice A factory that constructs exactly one product type. Registered in a
 *         generic IProductFactory and invoked only by it.
 *
 * @dev PAYLOAD OWNERSHIP
 *      The generic factory resolves productTypeId to this factory and forwards
 *      the deployment. This factory understands the product-specific payload:
 *      it validates productSpecificSchemaHash and ABI-decodes
 *      productSpecificPayload to construct the product.
 *
 * @dev PRODUCT TYPE ID SCHEME
 *      The factory is the single source of truth for its productTypeId. The id
 *      is a stable, address-INDEPENDENT logical type identifier, derived as a
 *      semantic constant:
 *          productTypeId == keccak256(bytes("<PRODUCT_TYPE_NAME>"))
 *      e.g. keccak256("SIMPLE_BOND").
 *
 *      Rationale for address-independence: the generic factory supports
 *      re-pointing a productTypeId to an upgraded factory (updateProductFactory).
 *      An address-derived id would break on redeployment, so the id MUST NOT
 *      fold in address(this). Uniqueness across factories is enforced
 *      operationally by the generic factory (one factory per id, owner-gated
 *      registration + a productTypeId self-declaration match), not by the id
 *      derivation itself.
 *
 *      WORKFLOW: an product provider reads productTypeId() from the deployed factory and
 *      supplies that exact value when publishing a product definition. Trade requests then
 *      route through the generic factory back to this factory by that id.
 *
 * @dev TRUST BOUNDARY
 *      deployProduct MUST be callable only by the generic factory that
 *      registered this factory (the eligibility/product definition checks
 *      happen upstream in the registry, so direct calls must be rejected).
 */

interface IProductSpecificFactory is IERC165 {
    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the caller is not the generic factory.
    error NotGenericFactory(address caller);

    /**
     * @notice Thrown when the supplied payload schema hash does not match the
     *         schema this factory expects.
     */
    error SchemaMismatch(bytes32 expected, bytes32 actual);

    /**
     * @notice Thrown when the deployment params target a different product type
     *         than this factory serves.
     */
    error ProductTypeMismatch(bytes32 expected, bytes32 actual);

    // ------------------------------ Factory Views ------------------------------ */

    /**
     * @notice Returns the single product type this factory serves.
     * @dev Address-independent semantic constant; see the contract-level
     *      "PRODUCT TYPE ID SCHEME". Used by the generic factory to verify a
     *      registration maps a product type to a matching factory, and by
     *      product providers as the productTypeId when publishing a product definition.
     */
    function productTypeId() external view returns (bytes32);

    /**
     * @notice Returns the schema hash of the productSpecificPayload this
     *         factory expects.
     * @dev Authoritative source of the schema hash: a product exposes its
     *      deploying factory via IProduct.productSpecificFactory(), and consumers read
     *      the schema from here rather than from a copy stored in the product.
     *      Compared against params.productSpecificSchemaHash in deployProduct.
     */
    function productSpecificSchemaHash() external view returns (bytes32);

    /**
     * @notice Returns whether the given product was deployed by this factory.
     * @dev Authenticity check: combined with IProduct.productSpecificFactory(), forms a
     *      bidirectional proof (product points to factory; factory confirms it
     *      built the product). Returns false for any address this factory did
     *      not deploy.
     */
    function isFactoryDeployedProduct(address product) external view returns (bool);

    // ------------------------------ Product Deployment ------------------------------ */

    /**
     * @notice Deploys the product for the given parameters.
     * @dev MUST be callable only by the generic factory; SHOULD validate
     *      params.productSpecificSchemaHash and revert SchemaMismatch on
     *      mismatch before decoding the payload.
     */
    function deployProduct(ProductDeploymentParams calldata params) external returns (address product);
}
