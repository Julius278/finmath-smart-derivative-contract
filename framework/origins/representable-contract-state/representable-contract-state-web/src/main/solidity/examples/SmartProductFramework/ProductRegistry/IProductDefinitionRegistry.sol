// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IProductDefinitionRegistry
 * @notice Interface for publishing financial product definitions and managing their lifecycle.
 *         A product definition is a reusable, published product specification consisting of:
 *         - the exact product-specific factory used for deployment;
 *         - a product terms template; and
 *         - a corresponding product documentation template.
 *
 *         Concrete product contracts can later be deployed from an active product definition.
 *
 * @dev INTERFACE SCOPE
 *      This interface defines product-definition publication, updates, lifecycle management, and read access.
 *      The framework's product registry may additionally coordinate product indications, client eligibility,
 *      trade requests, and deployment.
 *
 * @dev FACTORY ANCHORING
 *      Each product definition anchors the exact product-specific factory that owns the complete deployable
 *      product specification. The factory is the authoritative source for:
 *      - the product type;
 *      - the product-specific payload schema;
 *      - the payload schema hash;
 *      - the required product terms resource type;
 *      - the required documentation resource type; and
 *      - the product deployment implementation.
 *
 *      During publication and updates, the registry validates the concrete product terms and documentation
 *      templates against the resource types exposed by the selected factory.
 *
 *      Replacing the factory requires an explicit product-definition update and therefore increments
 *      the product-definition version.
 *
 *      Product-specific factories are expected to be immutable specification contracts. A changed
 *      implementation or specification should be represented by a newly deployed factory address.
 *
 * @dev PRODUCT DEFINITION ID SCHEME
 *      The canonical product definition id is:
 *          productDefinitionId == keccak256(abi.encode(name, address(registry)))
 *
 *      Consequently:
 *      - the name is the uniqueness key;
 *      - duplicate names are not allowed;
 *      - product definitions cannot be renamed; and
 *      - ids are scoped to a particular registry deployment.
 *
 * @dev OWNERSHIP
 *      Implementations are expected to use OpenZeppelin Ownable2Step. owner() and ownership-transfer
 *      functions are inherited from that module and are not redeclared here.
 *
 * @author Raphael Prandtl
 */
interface IProductDefinitionRegistry {
    // ------------------------------ Enums -------------------------------------- */

    /**
     * @notice Lifecycle status of a product definition.
     * @dev `Unknown` is the default value and represents a product definition that has not been published.
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
     * @notice Components that fully identify a deployable product definition.
     * @param productFactory                Exact product-specific factory responsible for the product type, payload specification, required resource types, and deployment.
     * @param productTermsTemplate          Finalized ITextResource containing the product-specific legal terms template, typically represented as XML.
     * @param productDocumentationTemplate  Finalized ITextResource containing the corresponding product documentation template, typically represented as XSLT.
     */
    struct ProductDefinition {
        address productFactory;
        address productTermsTemplate;
        address productDocumentationTemplate;
    }

    /**
     * @notice Parameters for publishing a new product definition.
     * @param name          Human-readable product-definition name and uniqueness key.
     * @param definition    Factory and concrete legal-document resources defining the deployable product specification.
     */
    struct ProductDefinitionPublicationParams {
        string name;
        ProductDefinition definition;
    }

    /**
     * @notice Full product definition record as returned by the read API.
     * @param status         Current lifecycle status.
     * @param publishedAt    Unix timestamp of initial publication.
     * @param updatedAt      Unix timestamp of the last mutation.
     * @param name           Human-readable name (also the uniqueness key).
     * @param partId         ERC-8100 partId used to render this product definition's state.
     * @param version        Monotonic version, bumped on resource updates.
     * @param definition     Currently anchored factory, product terms template, and product documentation template.
     */
    struct ProductDefinitionView {
        ProductDefinitionStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string name;
        uint256 partId;
        uint256 version;
        ProductDefinition definition;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address value is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when a required string value is empty.
    error EmptyString(string field);

    /// @notice Thrown when a required hash value is bytes32(0).
    error ZeroHash(string field);

    /// @notice Thrown when publishing a product definition whose derived id already exists.
    error ProductDefinitionAlreadyExists(bytes32 productDefinitionId);

    /// @notice Thrown when referencing a product definition not known to the registry.
    error UnknownProductDefinition(bytes32 productDefinitionId);

    /// @notice Thrown when an operation requires an active product definition.
    error ProductDefinitionNotActive(bytes32 productDefinitionId, ProductDefinitionStatus status);

    /// @notice Thrown when an operation requires a writable product definition.
    error ProductDefinitionNotWritable(bytes32 productDefinitionId, ProductDefinitionStatus status);

    /// @notice Thrown when a status transition is not allowed (e.g. to Unknown, or away from Archived).
    error InvalidStatusTransition(ProductDefinitionStatus from, ProductDefinitionStatus to);

    // ------------------------------ Events ------------------------------------- */

    /// @notice Emitted when a new product definition is published (initial status Active).
    event ProductDefinitionPublished(bytes32 indexed productDefinitionId, address indexed productFactory, address productTermsTemplate, address productDocumentationTemplate);

    /// @notice Emitted when the anchored components of a product definition are updated.
    event ProductDefinitionUpdated(bytes32 indexed productDefinitionId, address indexed productFactory, address productTermsTemplate, address productDocumentationTemplate, uint256 version);

    /// @notice Emitted whenever the lifecycle status of a product definitio changes, including its initial publication.
    event ProductDefinitionStatusChanged(bytes32 indexed productDefinitionId, ProductDefinitionStatus oldStatus, ProductDefinitionStatus newStatus);

    // ------------------------------ Product Definition Publication and Lifecycle Management ------------------------------ */

    /// @notice Publishes and activates a new product definition.
    function publishProductDefinition(ProductDefinitionPublicationParams calldata params) external returns (bytes32 productDefinitionId);

    /**
     * @notice Updates the factory and/or legal-document resources anchored to an existing product definition.
     * @dev A successful update should always increment the product-definition version.
     */
    function updateProductDefinition(bytes32 productDefinitionId, ProductDefinition calldata definition) external;

    /// @notice Changes the lifecycle status of a product definition.
    function setProductDefinitionStatus(bytes32 productDefinitionId, ProductDefinitionStatus newStatus) external;

    // ------------------------------ Product Definition Read API ------------------------------ */

    /// @notice Returns the complete current record of a product definition.
    function getProductDefinition(bytes32 productDefinitionId) external view returns (ProductDefinitionView memory);

    /// @notice Returns the current lifecycle status of a product definition.
    function getProductDefinitionStatus(bytes32 productDefinitionId) external view returns (ProductDefinitionStatus status);

    // @notice Returns the product type exposed by the factory anchored in the product definition.
    function productTypeByDefinitionId(bytes32 productDefinitionId) external view returns (bytes32 productTypeId);

    /**
     * @notice Derives the canonical product-definition id for a given name.
     * @dev This is an off-chain convenience function. It mirrors the canonical id scheme but does not check whether the definition exists.
     */
    function computeProductDefinitionId(string calldata name) external view returns (bytes32 productDefinitionId);
}