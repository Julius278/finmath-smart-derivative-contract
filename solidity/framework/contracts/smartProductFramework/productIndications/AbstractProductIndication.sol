// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductIndication} from "./IProductIndication.sol";

import {IXMLRepresentableStatePart, IRepresentableStateVersioned} from "../../erc8100/IRepresentableState.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title AbstractProductIndication
 * @notice Base contract for product indication registries.
 *
 * @dev Manages indication lifecycle state, versioning, state-part ids, and
 *      rendering dispatch. Concrete implementations define the indication
 *      category, payload, publication logic, and XML representation.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProductIndication is IProductIndication, IRepresentableStateVersioned, Ownable2Step {
    /// @notice Maximum number of fixed-size summaries returned by a discovery page.
    uint256 public constant MAX_DISCOVERY_PAGE_SIZE = 100;

    // ------------------------------ Storage ------------------------------ */

    /// @dev Lifecycle state shared by all indication implementations.
    ///      version tracks content revisions; updatedAt also tracks lifecycle changes.
    struct IndicationCore {
        IndicationStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        uint256 version;
    }

    /// @notice Fixed-size lifecycle summary; excludes product-specific payload and XML.
    struct IndicationState {
        bytes32 indicationId;
        IndicationStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        uint256 version;
    }

    mapping(bytes32 indicationId => IndicationCore core) private _cores;
    /// @dev Append-only: status changes and republication never move or duplicate ids.
    bytes32[] private _indicationIds;

    /// @inheritdoc IRepresentableStateVersioned
    /// @dev Contract-wide revision of all indication representations, including lifecycle changes.
    ///      Separate from per-indication content versions. Ownership is not represented by the XML.
    ///      Subclasses must call _touchIndication after every payload mutation and must not expose
    ///      external or time-dependent XML bindings without extending this invalidation policy.
    uint256 public override stateVersion;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a state-part id does not represent an indication.
    error UnknownPart(uint256 partId);

    /// @notice Thrown when an indication cannot be modified in its current status.
    error IndicationNotWritable(bytes32 indicationId, IndicationStatus status);

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to manage indications.
    // TODO switch to constructor Ownable(owner_) instead of calling _transferOwnership(owner_) when upgrading to openzeppelin 5.x
    constructor(address owner_) {
        _transferOwnership(owner_);
    }

    // ------------------------------ Indication Lifecycle ------------------------------ */

    /// @inheritdoc IProductIndication
    function setIndicationStatus(bytes32 indicationId, IndicationStatus newStatus) external override onlyOwner {
        IndicationCore storage core = _existingCore(indicationId);
        IndicationStatus oldStatus = core.status;
        if (oldStatus == newStatus) {
            return;
        }
        _validateStatusTransition(oldStatus, newStatus);

        core.status = newStatus;
        core.updatedAt = uint64(block.timestamp);
        ++stateVersion;
        emit IndicationStatusChanged(indicationId, oldStatus, newStatus);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromIndicationId(indicationId), core.version);
    }

    // ------------------------------ ERC-165 ------------------------------ */

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IProductIndication).interfaceId
            || interfaceId == type(IXMLRepresentableStatePart).interfaceId
            || interfaceId == type(IRepresentableStateVersioned).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------ Indication Read API ------------------------------ */

    /// @notice Number of distinct indications ever published, including archived entries.
    function indicationCount() external view returns (uint256) {
        return _indicationIds.length;
    }

    /// @notice Lifecycle summary of an existing indication; unknown ids revert.
    function indicationState(bytes32 indicationId) public view returns (IndicationState memory) {
        IndicationCore storage core = _existingCore(indicationId);
        return IndicationState(indicationId, core.status, core.publishedAt, core.updatedAt, core.version);
    }

    /**
     * @notice Returns lifecycle summaries in first-publication order, without status filtering.
     * @dev At most min(limit, MAX_DISCOVERY_PAGE_SIZE, remaining) entries. Zero limit or an
     *      offset at/past the end returns an empty page. Advance by the actual returned length.
     *      Pin reads to one block when a consistent multi-call snapshot is required.
     */
    function getIndications(uint256 offset, uint256 limit) external view returns (IndicationState[] memory states) {
        uint256 count = _discoveryPageLength(_indicationIds.length, offset, limit);
        states = new IndicationState[](count);
        for (uint256 i; i < count; ++i) {
            states[i] = indicationState(_indicationIds[offset + i]);
        }
    }

    /// @inheritdoc IProductIndication
    function indicationStatus(bytes32 indicationId) external view override returns (IndicationStatus) {
        return _cores[indicationId].status;
    }

    /// @inheritdoc IProductIndication
    function isIndication(bytes32 indicationId) external view override returns (bool) {
        return _cores[indicationId].status != IndicationStatus.Unknown;
    }

    /// @inheritdoc IProductIndication
    function partIdForIndication(bytes32 indicationId) external view override returns (uint256 partId) {
        _existingCore(indicationId);
        return _partIdFromIndicationId(indicationId);
    }

    /// @inheritdoc IProductIndication
    function indicationForPartId(uint256 partId) external view override returns (bytes32 indicationId) {
        indicationId = _indicationIdFromPartId(partId);
        _existingCore(indicationId);
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc IXMLRepresentableStatePart
    function statePartXmlTemplate(uint256 partId) external view override returns (string memory) {
        bytes32 indicationId = _indicationIdFromPartId(partId);
        if (_cores[indicationId].status == IndicationStatus.Unknown) {
            revert UnknownPart(partId);
        }
        return _indicationStateXml(indicationId);
    }

    // ------------------------------ Internal Lifecycle Helpers ------------------------------ */

    /**
     * @notice Opens an indication for publication.
     * @dev Creates a new active indication or verifies that an existing one is writable.
     */
    function _openForPublish(bytes32 indicationId) internal returns (IndicationCore storage core) {
        core = _cores[indicationId];
        if (core.status == IndicationStatus.Unknown) {
            _indicationIds.push(indicationId);
            core.status = IndicationStatus.Active;
            core.publishedAt = uint64(block.timestamp);
            emit IndicationPublished(indicationId);
            emit IndicationStatusChanged(indicationId, IndicationStatus.Unknown, IndicationStatus.Active);
        } else {
            _ensureWritable(indicationId, core.status);
        }
    }

    /// @notice Advances the content version on publication or payload updates.
    /// @dev Lifecycle-only changes retain the version, matching ProductDefinitionRegistry.
    function _touchIndication(bytes32 indicationId, IndicationCore storage core) internal {
        unchecked { core.version += 1; }
        core.updatedAt = uint64(block.timestamp);
        ++stateVersion;
        emit StatePartUpdated(msg.sender, address(this), _partIdFromIndicationId(indicationId), core.version);
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    /// @notice Returns the lifecycle state of an existing indication.
    function _existingCore(bytes32 indicationId) internal view returns (IndicationCore storage core) {
        core = _cores[indicationId];
        if (core.status == IndicationStatus.Unknown) {
            revert UnknownIndication(indicationId);
        }
    }

    /// @notice Returns the lifecycle state without checking existence.
    function _core(bytes32 indicationId) internal view returns (IndicationCore storage) {
        return _cores[indicationId];
    }

    /// @notice Ensures that an indication may still be modified.
    function _ensureWritable(bytes32 indicationId, IndicationStatus status) internal pure {
        if (status == IndicationStatus.Closed || status == IndicationStatus.Archived) {
            revert IndicationNotWritable(indicationId, status);
        }
    }

    /**
     * @dev Allowed transitions:
     *      Active    -> Suspended | Closed
     *      Suspended -> Active | Closed
     *      Closed    -> Archived
     *      Archived  -> (terminal)
     */
    function _validateStatusTransition(IndicationStatus oldStatus, IndicationStatus newStatus) internal pure virtual {
        bool validTransition =
            (oldStatus == IndicationStatus.Active && (newStatus == IndicationStatus.Suspended || newStatus == IndicationStatus.Closed)) ||
            (oldStatus == IndicationStatus.Suspended && (newStatus == IndicationStatus.Active || newStatus == IndicationStatus.Closed)) ||
            (oldStatus == IndicationStatus.Closed && newStatus == IndicationStatus.Archived);
        if (!validTransition) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    // ------------------------------ Internal Id Logic ------------------------------ */

    /// @dev Bound work before allocating memory; subtract first to avoid offset + limit overflow.
    function _discoveryPageLength(uint256 length, uint256 offset, uint256 limit) internal pure returns (uint256) {
        if (offset >= length) {
            return 0;
        }
        uint256 count = length - offset;
        if (count > limit) count = limit;
        if (count > MAX_DISCOVERY_PAGE_SIZE) count = MAX_DISCOVERY_PAGE_SIZE;
        return count;
    }

    /// @notice Derives an indication id from its unique name.
    function _indicationIdFromName(string memory name) internal view returns (bytes32) {
        return keccak256(abi.encode(name, address(this)));
    }

    /// @notice Converts a state-part id to its indication id.
    function _indicationIdFromPartId(uint256 partId) internal pure returns (bytes32) {
        return bytes32(partId);
    }

    /// @notice Converts an indication id to its state-part id.
    function _partIdFromIndicationId(bytes32 indicationId) internal pure returns (uint256) {
        return uint256(indicationId);
    }

    // ------------------------------ Concrete Hooks ------------------------------

    /// @inheritdoc IProductIndication
    function indicationCategory() external view virtual override returns (bytes32);

    /// @notice Returns the XML representation of an existing indication.
    function _indicationStateXml(bytes32 indicationId) internal view virtual returns (string memory);
}
