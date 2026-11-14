// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IProductDefinitionRegistry
 * @notice Interface for publishing product definitions and managing their lifecycle.
 *
 * @dev Each definition anchors the exact product factory and finalized text
 *      resources used to deploy products. Implementations must validate the
 *      resources against the specification exposed by the factory.
 *
 *      Product definition ids are derived as:
 *
 *          keccak256(abi.encode(name, address(registry)))
 *
 * @author Raphael Prandtl
 */
interface IProductDefinitionRegistry {
    // ------------------------------ Enums -------------------------------------- */

    /**
     * @notice Lifecycle status of a product definition.
     * @dev `Unknown` represents a definition that has not been published.
     */
    enum ProductDefinitionStatus {
        Unknown,
        Active,
        Suspended,
        Retired,
        Archived
    }

    // ------------------------------ Structs ------------------------------------ */

    /**
     * @notice Components anchored by a product definition.
     * @param productFactory Exact factory used for product deployment.
     * @param productTermsTemplate Finalized product terms text resource.
     * @param productDocumentationTemplate Finalized documentation text resource.
     */
    struct ProductDefinition {
        address productFactory;
        address productTermsTemplate;
        address productDocumentationTemplate;
    }

    /**
     * @notice Parameters for publishing a product definition.
     * @param name Human-readable name and uniqueness key.
     * @param productDefinition Components to anchor.
     */
    struct ProductDefinitionPublicationParams {
        string name;
        ProductDefinition productDefinition;
    }

    /**
     * @notice Complete product definition record.
     * @param status Current lifecycle status.
     * @param publishedAt Timestamp of initial publication.
     * @param updatedAt Timestamp of the latest component, lifecycle or indication-assignment update.
     * @param name Human-readable name and uniqueness key.
     * @param partId State-part id used for rendering.
     * @param version Anchored-component revision; lifecycle and indication-assignment updates do not change it.
     * @param productDefinition Currently anchored components.
     */
    struct ProductDefinitionView {
        ProductDefinitionStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string name;
        uint256 partId;
        uint256 version;
        ProductDefinition productDefinition;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when a required string is empty.
    error EmptyString(string field);

    /// @notice Thrown when the derived product definition id already exists.
    error ProductDefinitionAlreadyExists(bytes32 productDefinitionId);

    /// @notice Thrown when a product definition is unknown.
    error UnknownProductDefinition(bytes32 productDefinitionId);

    /// @notice Thrown when an operation requires an active product definition.
    error ProductDefinitionNotActive(bytes32 productDefinitionId, ProductDefinitionStatus status);

    /// @notice Thrown when a product definition cannot be modified.
    error ProductDefinitionNotWritable(bytes32 productDefinitionId, ProductDefinitionStatus status);

    /// @notice Thrown when a lifecycle transition is not permitted.
    error InvalidStatusTransition(ProductDefinitionStatus from, ProductDefinitionStatus to);

    // ------------------------------ Events ------------------------------------- */

    /// @notice Emitted when a product definition is published.
    event ProductDefinitionPublished(bytes32 indexed productDefinitionId, address indexed productFactory, address productTermsTemplate, address productDocumentationTemplate);

    /// @notice Emitted when the anchored components are updated.
    event ProductDefinitionUpdated(bytes32 indexed productDefinitionId, address indexed productFactory, address productTermsTemplate, address productDocumentationTemplate, uint256 version);

    /// @notice Emitted when the lifecycle status changes.
    event ProductDefinitionStatusChanged(bytes32 indexed productDefinitionId, ProductDefinitionStatus oldStatus, ProductDefinitionStatus newStatus);

    // ------------------------------ Lifecycle ------------------------------ */

    /// @notice Publishes a new product definition with initial status `Active`.
    function publishProductDefinition(ProductDefinitionPublicationParams calldata params) external returns (bytes32 productDefinitionId);

    /// @notice Updates the components anchored by a product definition.
    function updateProductDefinition(bytes32 productDefinitionId, ProductDefinition calldata productDefinition) external;

    /// @notice Changes the lifecycle status of a product definition.
    function setProductDefinitionStatus(bytes32 productDefinitionId, ProductDefinitionStatus newStatus) external;

    // ------------------------------ Read API ------------------------------ */

    /// @notice Returns the client registry of the product definition registry.
    function clientRegistryAddress() external view returns (address clientRegistryAddress);

    /// @notice Returns the complete record of a product definition.
    function getProductDefinition(bytes32 productDefinitionId) external view returns (ProductDefinitionView memory);

    /// @notice Returns the current lifecycle status of a product definition.
    function getProductDefinitionStatus(bytes32 productDefinitionId) external view returns (ProductDefinitionStatus status);

    /// @notice Returns the factory anchored by a product definition.
    function getProductFactoryByDefinitionId(bytes32 productDefinitionId) external view returns (address productFactory);

    /// @notice Returns whether a product was issued and registered by this registry.
    function isRegisteredProduct(address product) external view returns (bool);

    /**
     * @notice Derives the canonical id for a product definition name.
     * @dev Does not check whether the definition exists.
     */
    function computeProductDefinitionId(string calldata name) external view returns (bytes32 productDefinitionId);
}
