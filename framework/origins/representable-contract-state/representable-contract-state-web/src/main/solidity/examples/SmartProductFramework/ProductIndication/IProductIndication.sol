// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IXMLRepresentableStatePart} from "../../../IRepresentableState.sol";

/**
 * @title IProductIndication
 * @notice Interface for publishing and rendering product indications of one category.
 *
 * @dev A product definition may reference an indication by its contract and id.
 *      Product factories determine whether the indication category is compatible.
 *
 * @author Raphael Prandtl
 */
interface IProductIndication is IERC165, IXMLRepresentableStatePart {
    // ------------------------------ Enums ------------------------------ */

    /**
     * @notice Lifecycle status of an indication.
     * @dev `Unknown` represents an indication that has not been published.
     */
    enum IndicationStatus {
        Unknown,
        Active,
        Suspended,
        Closed,
        Archived
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when an indication is not known to the contract.
    error UnknownIndication(bytes32 indicationId);

    /// @notice Thrown when a lifecycle transition is not permitted.
    error InvalidStatusTransition(IndicationStatus from, IndicationStatus to);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a new indication is published.
    event IndicationPublished(bytes32 indexed indicationId);

    /// @notice Emitted when the status of an indication changes.
    event IndicationStatusChanged(bytes32 indexed indicationId, IndicationStatus oldStatus, IndicationStatus newStatus);

    /// @notice Emitted when the representable state of an indication changes.
    event StatePartUpdated(address indexed sender, address indexed stateContract, uint256 indexed partId, uint256 partVersion);

    // ------------------------------ Indication Lifecycle ------------------------------ */

    /**
     * @notice Changes the lifecycle status of an existing indication.
     * @dev Implementations must reject unsupported status transitions.
     */
    function setIndicationStatus(bytes32 indicationId, IndicationStatus newStatus) external;

    // ------------------------------ Indication Read API ------------------------------ */

    /// @notice Returns the category of indications provided by this contract.
    function indicationCategory() external view returns (bytes32);

    /// @notice Returns the current status of an indication.
    function indicationStatus(bytes32 indicationId) external view returns (IndicationStatus);

    /// @notice Returns whether an indication has been published.
    function isIndication(bytes32 indicationId) external view returns (bool);

    /// @notice Returns the state-part id used to render an indication.
    function partIdForIndication(bytes32 indicationId) external view returns (uint256 partId);

    /// @notice Returns the indication corresponding to a state-part id.
    function indicationForPartId(uint256 partId) external view returns (bytes32 indicationId);
}
