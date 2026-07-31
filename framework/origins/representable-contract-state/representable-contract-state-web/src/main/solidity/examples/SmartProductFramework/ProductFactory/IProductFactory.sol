// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from"@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ProductDeploymentParams} from "./ProductDeploymentTypes.sol";

/**
 * @title IProductFactory
 * @notice Interface for an immutable product-specific factory that defines and deploys exactly one product implementation and specification.
 *         A product factory is anchored directly in a product definition and is the authoritative source for:
 *         - the product type;
 *         - the product-specific payload schema;
 *         - the payload schema hash;
 *         - the required product terms template resource type;
 *         - the required product documentation template resource type; and
 *         - deployment of concrete product instances.
 *
 * @dev ARCHITECTURE
 *      A product definition stores the exact factory address that belongs to it. The product registry therefore calls this factory directly when
 *      creating a product from that definition.
 *      There is no intermediate factory registry and no productTypeId-to-factory routing layer.
 *      During product-definition publication or update, the product registry queries the factory to validate:
 *      - that the factory supports this interface;
 *      - that the factory is bound to the publishing product registry;
 *      - that the product terms template has the required resource type; and
 *      - that the documentation template has the required resource type.
 *
 * @dev FACTORY IMMUTABILITY
 *      A factory address represents one immutable product implementation and specification.
 *      A change to the product implementation, payload schema, resource types, or deployment behavior should be represented by a
 *      newly deployed factory address and an explicit product-definition update.
 *
 *      Upgradeable proxy factories should not be used because their behavior could change without changing the factory address
 *      anchored in the product definition.
 *
 * @dev PRODUCT TYPE
 *      The factory is the single source of truth for its productTypeId.
 *      The identifier is an address-independent semantic identifier:
 *          productTypeId == keccak256(bytes("<PRODUCT_TYPE_NAME>"))
 *      Example:
 *          keccak256(bytes("SIMPLE_BOND"))
 *
 *      Multiple factory versions may expose the same logical product type while differing in implementation, payload schema, or required
 *      resource types. The exact factory address distinguishes those  specifications.
 *
 * @dev PAYLOAD SPECIFICATION
 *      The factory defines the ABI encoding of productSpecificPayload through productPayloadSchema() and productPayloadSchemaHash().
 *      It is responsible for decoding and validating that payload before or during product construction.
 *
 * @dev TRUST BOUNDARY
 *      deployProduct() must only be callable by productRegistryAddress().
 *      The product registry performs product-definition lifecycle, client eligibility, indication, and trade-request validation before invoking
 *      the factory. Direct deployment calls from other addresses must be rejected.
 *
 * @dev AUTHENTICITY
 *      The factory records every product address it deploys.
 *      Combined with the product's factory getter, this provides a bidirectional authenticity relationship:
 *      - the product identifies its deploying factory; and
 *      - the factory confirms that it deployed the product.
 *
 * @author Raphael Prandtl
 */
interface IProductFactory is IERC165 {
    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address value is the zero address.
    error ZeroAddress(string field);

     /// @notice Thrown when deployProduct is called by an address other than the configured product registry.
    error NotProductRegistry(address caller);

    // ------------------------------ Events ------------------------------------- */

    /// @notice Emitted after this factory successfully deploys a product.
    event ProductDeployed(bytes32 indexed tradeId, bytes32 indexed productDefinitionId, bytes32 indexed productTypeId, address product, address productProvider, address client);

    // ------------------------------ Factory Configuration ------------------------------ */

    /// @notice Returns the product registry authorized to invoke deployProduct.
    function productRegistryAddress() external view returns (address);

    // ------------------------------ Product Specification ------------------------------ */

    /**
     * @notice Returns the logical product type implemented by this factory.
     * @dev This value is descriptive product metadata, not a routing key.
     *      Deployment routing is determined by the exact factory address anchored in the product definition.
     */
    function productTypeId() external view returns (bytes32);

    /**
     * @notice Returns a human-readable description of the expected ABI encoding of ProductDeploymentParams.productSpecificPayload.
     * @dev Intended for documentation, integration tooling, and off-chain payload construction.
     */
    function productPayloadSchema() external view returns (string memory);

    /// @notice Returns the canonical hash of the product-specific payload schema.
    function productPayloadSchemaHash() external view returns (bytes32);

    /// @notice Returns the resource type required for the product terms template.
    function productTermsTemplateResourceType() external view returns (bytes32);

    /// @notice Returns the resource type required for the product documentation template.
    function productDocumentationTemplateResourceType() external view returns (bytes32);

    // ------------------------------ Product Authenticity ------------------------------ */

    /// @notice Returns whether a product address was deployed by this factory.
    function isFactoryDeployedProduct(address product) external view returns (bool);

    // ------------------------------ Product Deployment ------------------------------ */

    /**
     * @notice Deploys a concrete product using the supplied common context and product-specific payload.
     * @dev Requirements:
     *
     *      - the caller must equal productRegistryAddress();
     *      - the supplied productTypeId must match productTypeId();
     *      - the supplied schema hash must match productPayloadSchemaHash();
     *      - the product-specific payload must be valid for the declared
     *        schema; and
     *      - the deployed product should be recorded for later authenticity
     *        checks.
     */
    function deployProduct(ProductDeploymentParams calldata params) external returns (address product);
}