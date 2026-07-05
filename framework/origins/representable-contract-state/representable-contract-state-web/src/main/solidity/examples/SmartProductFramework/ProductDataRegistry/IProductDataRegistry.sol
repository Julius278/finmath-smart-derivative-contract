// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IProductDataRegistry
/// @notice Base layer for publishing financial *programs* and managing their
///         lifecycle. A program is a reusable, published product definition
///         (terms + stylesheet + product type) under which concrete products
///         can later be deployed.
///
/// @dev LAYERING
///      This is the base publication layer. Higher layers build on top:
///        1. lifecycle completion (abstract base contract),
///        2. Inclusion of program indications (e.g. curve indications for bonds),
///        3. tradable product data (trade requests, investor entry).
///
/// @dev PROGRAM ID SCHEME (canonical)
///      programId == keccak256(abi.encode(programName, address(registry)))
///      Consequences: programName is the unique key (no duplicate names, no
///      renaming), and ids are scoped to a specific registry deployment.
///
/// @dev OWNERSHIP
///      Implementations are Ownable (OpenZeppelin Ownable2Step); owner() and
///      ownership transfer come from that module and are not redeclared here.
///
/// @author Raphael Prandtl
interface IProductDataRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Lifecycle status of a program.
    /// @dev `Unknown` is the default value and the "not published" sentinel.
    enum ProgramStatus {
        Unknown,
        Active,
        Suspended,
        Closed,
        Archived
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STRUCTS                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Essential resources defining a program's product terms.
    /// @param productTermsResource ITextResource holding the product terms.
    /// @param styleSheetResource   ITextResource holding the (XSLT) stylesheet.
    /// @param productTypeId    Identifies the deployable product type that matches
    ///        these terms and stylesheet. Obtained from the product-specific
    ///        factory's productTypeId() (see IProductSpecificFactory's PRODUCT TYPE
    ///        ID SCHEME); must equal a type registered in the product factory.
    struct ProgramResources {
        address productTermsResource;
        address styleSheetResource;
        bytes32 productTypeId;
    }

    /// @notice Parameters for publishing a new program.
    struct ProgramPublicationParams {
        string programName;
        ProgramResources resources;
    }

    /// @notice Full program record as returned by the read API.
    /// @param status         Current lifecycle status.
    /// @param publishedAt    Unix timestamp of initial publication.
    /// @param updatedAt      Unix timestamp of the last mutation.
    /// @param programName    Human-readable name (also the uniqueness key).
    /// @param partId         ERC-8100 partId used to render this program's state.
    /// @param programVersion Monotonic version, bumped on resource updates.
    /// @param resources      Anchored resource set (terms, stylesheet, type).
    struct ProgramView {
        ProgramStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string programName;
        uint256 partId;
        uint256 programVersion;
        ProgramResources resources;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when a required string argument is zero.
    error EmptyString(string field);

    /// @notice Thrown when a required bytes32 argument is zero.
    error ZeroHash(string field);

    /// @notice Thrown when publishing a program whose id already exists.
    error ProgramAlreadyExists(bytes32 programId);

    /// @notice Thrown when referencing a program not known to the system.
    error UnknownProgram(bytes32 programId);

    /// @notice Thrown when an operation requires an active program.
    error ProgramNotActive(bytes32 programId, ProgramStatus status);

    /// @notice Thrown when an operation requires a writable program
    error ProgramNotWritable(bytes32 programId, ProgramStatus status);

    /// @notice Thrown when a status transition is not allowed
    ///         (e.g. to Unknown, or away from Archived).
    error InvalidStatusTransition(ProgramStatus from, ProgramStatus to);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when a new program is published (initial status Active).
    event ProgramPublished(bytes32 indexed programId, bytes32 indexed productTypeId, address productTermsResource, address styleSheetResource);

    /// @notice Emitted when a program's resources are updated.
    event ProgramResourcesUpdated(bytes32 indexed programId, bytes32 indexed productTypeId, address productTermsResource, address styleSheetResource, uint256 programVersion);

    /// @notice Emitted on every status change, including the initial publication
    event ProgramStatusChanged(bytes32 indexed programId, ProgramStatus oldStatus, ProgramStatus newStatus);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*      PROGRAM PUBLICATION AND LIFECYCLE MANAGEMENT         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Publishes a new program and anchors its resources.
    function publishProgram(ProgramPublicationParams calldata params) external returns (bytes32 programId);

    /// @notice Updates the resources of an existing program (bumps version).
    function updateProgramResources(bytes32 programId, ProgramResources calldata resources) external;

    /// @notice Changes the lifecycle status of a program.
    function setProgramStatus(bytes32 programId, ProgramStatus newStatus) external;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    PROGRAM READ API                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the full resource set of a program.
    function getProgram(bytes32 programId) external view returns (ProgramView memory);

    /// @notice Returns the current lifecycle status of a program.
    function getProgramStatus(bytes32 programId) external view returns (ProgramStatus status);

    /// @notice Returns the product type anchored for a program.
    function productTypeByProgramId(bytes32 programId) external view returns (bytes32);

    /// @notice Derives the program id for a given name (off-chain convenience).
    /// @dev Mirrors the canonical id scheme; does not check existence.
    function computeProgramId(string calldata programName) external view returns (bytes32 programId);
}

