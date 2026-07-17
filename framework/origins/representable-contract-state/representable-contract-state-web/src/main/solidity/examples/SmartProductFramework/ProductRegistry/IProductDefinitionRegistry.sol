// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IProductDefinitionRegistry.sol
 * @notice Base layer for publishing financial product definitions and managing
 *         their lifecycle. A product definition is a reusable, published
 *         product specification consisting of terms, stylesheet and product type,
 *         under which concrete product contracts can later be deployed.
 *
 * @dev LAYERING
 *      This is the base publication layer. Higher layers build on top:
 *        1. lifecycle completion (abstract base contract),
 *        2. inclusion of product definition indications
 *           (e.g. curve indications for bonds),
 *        3. tradable product data (trade requests, investor entry).
 *
 * @dev PRODUCT DEFINITION ID SCHEME (canonical)
 *      productDefinitionId == keccak256(abi.encode(name, address(registry)))
 *      Consequences: name is the unique key (no duplicate names, no renaming),
 *      and ids are scoped to a specific registry deployment.
 *
 * @dev OWNERSHIP
 *      Implementations are Ownable (OpenZeppelin Ownable2Step); owner() and
 *      ownership transfer come from that module and are not redeclared here.
 *
 * @author Raphael Prandtl
 */
interface IProductDefinitionRegistry {
    // ------------------------------ Enums ------------------------------ */

    /**
     * @notice Lifecycle status of a product definition.
     * @dev `Unknown` is the default value and the "not published" sentinel.
     */
    enum ProductDefinitionStatus {
        Unknown,
        Active,
        Suspended,
        Retired,
        Archived
    }

    // ------------------------------ Structs ------------------------------ */

    /**
     * @notice Essential resources defining a product definition.
     * @param termsResource      ITextResource holding the product terms.
     * @param stylesheetResource ITextResource holding the XSLT stylesheet.
     * @param productTypeId      Identifies the deployable product type that
     *        matches these terms and stylesheet. Obtained from the
     *        product-type-specific factory's productTypeId(); (see IProductTypeFactory's
     *        PRODUCT TYPE ID SCHEME); must equal a type registered in the product factory.
     */
    struct ProductDefinitionResources {
        address termsResource;
        address stylesheetResource;
        bytes32 productTypeId;
    }

    /**
     * @notice Parameters for publishing a new product definition.
     * @param name      Human-readable name, also the uniqueness key.
     * @param resources Anchored resource set: terms, stylesheet, product type.
     */
    struct ProductDefinitionPublicationParams {
        string name;
        ProductDefinitionResources resources;
    }

    /**
     * @notice Full product definition record as returned by the read API.
     * @param status         Current lifecycle status.
     * @param publishedAt    Unix timestamp of initial publication.
     * @param updatedAt      Unix timestamp of the last mutation.
     * @param name           Human-readable name (also the uniqueness key).
     * @param partId         ERC-8100 partId used to render this product definition's state.
     * @param version        Monotonic version, bumped on resource updates.
     * @param resources      Anchored resource set (terms, stylesheet, type).
     */
    struct ProductDefinitionView {
        ProductDefinitionStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string name;
        uint256 partId;
        uint256 version;
        ProductDefinitionResources resources;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when a required string argument is zero.
    error EmptyString(string field);

    /// @notice Thrown when a required bytes32 argument is zero.
    error ZeroHash(string field);

    /// @notice Thrown when publishing a product definition whose id already exists.
    error ProductDefinitionAlreadyExists(bytes32 productDefinitionId);

    /// @notice Thrown when referencing a product definition not known to the system.
    error UnknownProductDefinition(bytes32 productDefinitionId);

    /// @notice Thrown when an operation requires an active product definition.
    error ProductDefinitionNotActive(bytes32 productDefinitionId, ProductDefinitionStatus status);

    /// @notice Thrown when an operation requires a writable product definition.
    error ProductDefinitionNotWritable(bytes32 productDefinitionId, ProductDefinitionStatus status);

    /**
     * @notice Thrown when a status transition is not allowed
     *         (e.g. to Unknown, or away from Archived).
     */
    error InvalidStatusTransition(ProductDefinitionStatus from, ProductDefinitionStatus to);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a new product definition is published (initial status Active).
    event ProductDefinitionPublished(bytes32 indexed productDefinitionId, bytes32 indexed productTypeId, address termsResource, address stylesheetResource);

    /// @notice Emitted when a product definition's resources are updated.
    event ProductDefinitionResourcesUpdated(bytes32 indexed productDefinitionId, bytes32 indexed productTypeId, address termsResource, address stylesheetResource, uint256 version);

    /// @notice Emitted on every status change, including initial publication.
    event ProductDefinitionStatusChanged(bytes32 indexed productDefinitionId, ProductDefinitionStatus oldStatus, ProductDefinitionStatus newStatus);

    // ------------------------------ Product Definition Publication and Lifecycle Management ------------------------------ */
    /// @notice Publishes a new product definition and anchors its resources.
    function publishProductDefinition(ProductDefinitionPublicationParams calldata params) external returns (bytes32 productDefinitionId);

    /// @notice Updates the resources of an existing product definition (bumps version).
    function updateProductDefinitionResources(bytes32 productDefinitionId, ProductDefinitionResources calldata resources) external;

    /// @notice Changes the lifecycle status of a product definition.
    function setProductDefinitionStatus(bytes32 productDefinitionId, ProductDefinitionStatus newStatus) external;

    // ------------------------------ Product Definition Read API ------------------------------ */

    /// @notice Returns the full record of a product definition.
    function getProductDefinition(bytes32 productDefinitionId) external view returns (ProductDefinitionView memory);

    /// @notice Returns the current lifecycle status of a product definition.
    function getProductDefinitionStatus(bytes32 productDefinitionId) external view returns (ProductDefinitionStatus status);

    /// @notice Returns the product type anchored for a product definition.
    function productTypeByDefinitionId(bytes32 productDefinitionId) external view returns (bytes32 productTypeId);

    /**
     * @notice Derives the product definition id for a given name (off-chain convenience).
     * @dev Mirrors the canonical id scheme; does not check existence.
     */
    function computeProductDefinitionId(string calldata name) external view returns (bytes32 productDefinitionId);
}
