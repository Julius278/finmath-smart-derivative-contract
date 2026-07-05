// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IXMLRepresentableStatePart} from "../IRepresentableState.sol";

/// @title IProductIndications
/// @notice Minimal, product-agnostic base for registries that publish price
///         indications for a product (e.g. curve indications for bonds)
///         Each concrete registry serves exactly one indication category.
///
/// @dev PURPOSE / LAYERING
///      A product-data layer references an indication by the pair
///      (indicationContract, indicationId). It never calls type-specific
///      publish functions; it only relies on this generic surface to:
///        - validate the contract is an IProductIndications (via ERC-165),
///        - read its indicationCategory() to decide compatibility with a
///          program's productTypeId (via a consuming-layer business hook),
///        - validate a specific indicationId exists / is presentable,
///        - manage its lifecycle status (setIndicationStatus),
///        - derive the partId and render via statePartXmlTemplate(partId).
///      Concrete implementations add their own typed publish function(s) that
///      MUST return the indicationId and emit IndicationPublished. The internal
///      composition of an indication (e.g. individual curve quotes and their
///      own sub-status) is implementation-defined and NOT exposed here.
///
/// @dev CATEGORY VS. PRODUCT TYPE (many-to-many)
///      indicationCategory() is a coarse self-declared tag (e.g.
///      keccak256("CURVE")), NOT a productTypeId. One category may serve many
///      product types (e.g. a curve indication used by fixed-rate bonds AND
///      commercial paper). The mapping category -> accepted productTypeIds is
///      business logic evaluated in the consuming layer, not stored here.
///
/// @dev ID / PART ID SCHEME
///      indicationId : opaque bytes32 key. Derivation is implementation-defined
///                     and SHOULD include address(this) for global uniqueness.
///      partId       : implementation-defined, bijective with indicationId and
///                     immutable for the lifetime of an indication. Consumers
///                     MUST obtain it via partIdForIndication(indicationId) and
///                     MUST NOT assume any particular derivation; the mapping is
///                     exposed both ways via partIdForIndication / indicationForPartId.
///
/// @author Raphael Prandtl
interface IProductIndications is IERC165, IXMLRepresentableStatePart {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Lifecycle status of an indication as a whole.
    /// @dev `Unknown` is the default value and the "not published" sentinel.
    enum IndicationStatus {
        Unknown,
        Active,
        Suspended,
        Closed,
        Archived
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when referencing an indication not known to the system.
    error UnknownIndication(bytes32 indicationId);

    /// @notice Thrown when a status transition is not allowed
    ///         (e.g. to Unknown, away from Archived).
    error InvalidStatusTransition(IndicationStatus from, IndicationStatus to);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when a new indication is published (initial status Active).
    /// @dev For "publish overwrites" implementations this is emitted on the
    ///      initial creation of an indicationId; subsequent full re-publishes
    ///      of the same id emit StatePartUpdated (and, if status changes,
    ///      IndicationStatusChanged) rather than IndicationPublished again.
    event IndicationPublished(bytes32 indexed indicationId);

    /// @notice Emitted on every indication status change, including the initial
    ///         Unknown -> Active transition at publication.
    event IndicationStatusChanged(bytes32 indexed indicationId, IndicationStatus oldStatus, IndicationStatus newStatus);

    /// @notice Generic ERC-8100-style state-part update event.
    event StatePartUpdated(address indexed sender, address indexed stateContract, uint256 indexed partId, uint256 partVersion);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                   INDICATION LIFECYCLE                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Sets the lifecycle status of an existing indication.
    function setIndicationStatus(bytes32 indicationId, IndicationStatus newStatus) external;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                     INDICATION READ API                   */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the coarse category of indications this registry serves
    ///         (e.g. keccak256("CURVE")). Used by the consuming layer to decide
    ///         compatibility with a program's productTypeId.
    function indicationCategory() external view returns (bytes32);

    /// @notice Returns the current status of an indication.
    function indicationStatus(bytes32 indicationId) external view returns (IndicationStatus);

    /// @notice Returns whether an indication is known to the system.
    function isIndication(bytes32 indicationId) external view returns (bool);

    /// @notice Returns the ERC-8100 partId used to render an indication.
    function partIdForIndication(bytes32 indicationId) external view returns (uint256 partId);

    /// @notice Returns the indicationId for a given partId (inverse mapping).
    function indicationForPartId(uint256 partId) external view returns (bytes32 indicationId);
}
