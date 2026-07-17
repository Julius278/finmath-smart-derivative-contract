// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IXMLRepresentableStatePart} from "../../../IRepresentableState.sol";

import {IProductIndication} from "./IProductIndication.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title AbstractProductIndication.sol
 * @notice Generic base for indication registries. Owns the indication
 *         lifecycle (status, versioning, id/partId derivation, rendering
 *         dispatch) that is identical across indication types. Concrete
 *         contracts (e.g. CurveIndications) add their typed publish logic,
 *         data model, indicationCategory(), and the _indicationStateXml hook.
 *
 * @dev PUBLISH-OVERWRITES SEMANTIC
 *      A concrete publish may fully (re)write an indication's payload. Use
 *      _openForPublish to begin a publish: it creates the indication on first
 *      use (emitting IndicationPublished once) or asserts writability on
 *      subsequent re-publishes. After writing payload, call _touchIndication.
 *
 * @dev ID / PART ID SCHEME
 *      indicationId : keccak256(abi.encode(name, address(this)))
 *      partId       : uint256(indicationId)   (bijective)
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProductIndication is IProductIndication, Ownable2Step {
    // ------------------------------ Storage ------------------------------ */

    /**
     * @dev Generic per-indication lifecycle state. Type-specific payload
     *      (e.g. curve quotes) is stored by the concrete contract, keyed by
     *      the same indicationId.
     */
    struct IndicationCore {
        IndicationStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        uint256 version;
    }

    mapping(bytes32 => IndicationCore) private _cores;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Requested partId does not map to a known indication.
    error UnknownPart(uint256 partId);

    /**
     * @notice Indication cannot be modified in its current status
     *         (Closed or Archived).
     */
    error IndicationNotWritable(bytes32 indicationId, IndicationStatus status);

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to publish and manage indications.
    constructor(address owner_) Ownable(owner_) {}

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
        emit IndicationStatusChanged(indicationId, oldStatus, newStatus);

        _touchIndication(indicationId, core);
    }

    // ------------------------------ ERC-165 ------------------------------ */

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IProductIndication).interfaceId || interfaceId == type(IXMLRepresentableStatePart).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------ Indication Read API ------------------------------ */

    function indicationStatus(bytes32 indicationId) external view override returns (IndicationStatus) {
        return _cores[indicationId].status;
    }

    function isIndication(bytes32 indicationId) external view override returns (bool) {
        return _cores[indicationId].status != IndicationStatus.Unknown;
    }

    function partIdForIndication(bytes32 indicationId) external view override returns (uint256) {
        _existingCore(indicationId);
        return _partIdFromIndicationId(indicationId);
    }

    function indicationForPartId(uint256 partId) external view override returns (bytes32 indicationId) {
        indicationId = _indicationIdFromPartId(partId);
        _existingCore(indicationId);
    }

    // ------------------------------ XML View ------------------------------ */

    function statePartXmlTemplate(uint256 partId) external view override returns (string memory) {
        bytes32 indicationId = _indicationIdFromPartId(partId);
        if (_cores[indicationId].status == IndicationStatus.Unknown) {
            revert UnknownPart(partId);
        }
        return _indicationStateXml(indicationId);
    }

    // ------------------------------ Internal Lifecycle Helpers ------------------------------ */

    /**
     * @dev Begins a publish. On first use of `indicationId`, creates it as
     *      Active and emits IndicationPublished + the initial status change.
     *      On re-publish, asserts the indication is writable.
     */
    function _openForPublish(bytes32 indicationId) internal returns (IndicationCore storage core) {
        core = _cores[indicationId];
        if (core.status == IndicationStatus.Unknown) {
            core.status = IndicationStatus.Active;
            core.publishedAt = uint64(block.timestamp);
            emit IndicationPublished(indicationId);
            emit IndicationStatusChanged(indicationId, IndicationStatus.Unknown, IndicationStatus.Active);
        } else {
            _ensureWritable(indicationId, core.status);
        }
    }

    /**
     * @dev Bumps version + updatedAt and emits the ERC-8100 StatePartUpdated.
     *      Call after every payload or status mutation.
     */
    function _touchIndication(bytes32 indicationId, IndicationCore storage core) internal {
        unchecked { core.version += 1;}
        core.updatedAt = uint64(block.timestamp);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromIndicationId(indicationId), core.version);
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    function _existingCore(bytes32 indicationId) internal view returns (IndicationCore storage core) {
        core = _cores[indicationId];
        if (core.status == IndicationStatus.Unknown) {
            revert UnknownIndication(indicationId);
        }
    }

    /**
     * @dev Raw (non-reverting) access to a lifecycle record, for callers that
     *      already established existence (e.g. the render path).
     */
    function _core(bytes32 indicationId) internal view returns (IndicationCore storage) {
        return _cores[indicationId];
    }

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
        if (newStatus == IndicationStatus.Unknown) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == IndicationStatus.Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == IndicationStatus.Closed && newStatus != IndicationStatus.Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    // ------------------------------ Internal Key / Hash Logic ------------------------------ */

    function _indicationIdFromName(string memory name) internal view returns (bytes32) {
        return keccak256(abi.encode(name, address(this)));
    }

    function _indicationIdFromPartId(uint256 partId) internal pure returns (bytes32) {
        return bytes32(partId);
    }

    function _partIdFromIndicationId(bytes32 indicationId) internal pure returns (uint256) {
        return uint256(indicationId);
    }

    // ------------------------------ Concrete Hooks ------------------------------ */

    /// @dev Concrete contracts return their fixed category constant.
    function indicationCategory() external view virtual override returns (bytes32);

    /// @dev Renders the full XML for an existing indication.
    function _indicationStateXml(bytes32 indicationId) internal view virtual returns (string memory);
}
