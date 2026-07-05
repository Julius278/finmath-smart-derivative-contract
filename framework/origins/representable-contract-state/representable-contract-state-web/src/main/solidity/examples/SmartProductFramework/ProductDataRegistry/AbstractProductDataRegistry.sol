// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductDataRegistry} from "./IProductDataRegistry.sol";
import {ITextResource} from "./TextResource/ITextResource.sol";
import {IXMLRepresentableStatePart} from "../IRepresentableState.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";


/// @title AbstractProductDataRegistry
/// @notice Layer 1: completes the program publication lifecycle on top of the
///         IProductDataRegistry base interface. Product-agnostic; product
///         specifics (e.g. accepted resource types) are supplied by the
///         concrete contract via _isAcceptedResourceType.
/// @dev PROGRAM ID / PART ID
///      programId == keccak256(abi.encode(programName, address(this)))
///      partId    == uint256(programId)   (bijective; not stored)
///
/// @author Raphael Prandtl
abstract contract AbstractProductDataRegistry is IProductDataRegistry, IXMLRepresentableStatePart, Ownable2Step {
    using Strings for uint256;
    using Strings for address;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Logical slot a resource occupies within a program.
    enum ResourceSlot {
        Unknown,
        ProductTerms,
        StyleSheet
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice ERC-8100: requested partId does not map to a known program.
    error UnknownPart(uint256 partId);

    /// @notice Resource address has no contract code.
    error InvalidResourceContract(address resource);

    /// @notice Resource does not implement the ITextResource interface.
    error InvalidResourceInterface(address resource);

    /// @notice Resource is not finalized (and thus not immutable).
    error ResourceNotFinalized(address resource);

    /// @notice Resource type is not accepted for the given slot.
    error InvalidResourceType(address resource, ResourceSlot slot, bytes32 actualResourceType);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Generic ERC-8100-style state-part update event.
    event StatePartUpdated(address indexed sender, address indexed stateContract, uint256 indexed partId, uint256 partVersion);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                        STORAGE                            */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev partId is not stored (derivable from the key).
    struct ProgramStorage {
        ProgramStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string programName;
        uint256 programVersion;
        ProgramResources resources;
    }

    mapping(bytes32 => ProgramStorage) internal _programsById;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_ Initial owner authorized to manage investors.
    constructor(address owner_) Ownable(owner_) {}

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*      PROGRAM PUBLICATION AND LIFECYCLE MANAGEMENT         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function publishProgram(ProgramPublicationParams calldata params) external override onlyOwner returns (bytes32 programId) {
        _validateProgramPublicationParams(params);

        programId = _programId(params.programName);
        ProgramStorage storage program = _programsById[programId];
        if (program.status != ProgramStatus.Unknown) {
            revert ProgramAlreadyExists(programId);
        }
        program.status = ProgramStatus.Active;
        program.programName = params.programName;
        program.publishedAt = uint64(block.timestamp);
        program.resources = params.resources;

        _touchProgram(program);

        emit ProgramPublished(programId, params.resources.productTypeId, params.resources.productTermsResource, params.resources.styleSheetResource);
        emit ProgramStatusChanged(programId, ProgramStatus.Unknown, ProgramStatus.Active);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProgramId(programId), program.programVersion);
    }

    function updateProgramResources(bytes32 programId, ProgramResources calldata resources) external override onlyOwner {
        _validateProgramResources(resources);

        ProgramStorage storage program = _existingProgram(programId);
        _ensureProgramWritable(programId, program.status);

        program.resources = resources;
        _touchProgram(program);

        emit ProgramResourcesUpdated(programId, resources.productTypeId, resources.productTermsResource, resources.styleSheetResource, program.programVersion);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProgramId(programId), program.programVersion);
    }

    function setProgramStatus(bytes32 programId, ProgramStatus newStatus) external override onlyOwner {
        ProgramStorage storage program = _existingProgram(programId);
        ProgramStatus oldStatus = program.status;

        if (oldStatus == newStatus) {
            return;
        }
        _validateStatusTransition(oldStatus, newStatus);

        program.status = newStatus;
        _touchProgram(program);

        emit ProgramStatusChanged(programId, oldStatus, newStatus);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProgramId(programId), program.programVersion);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                     PROGRAM READ API                      */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function getProgram(bytes32 programId) external view override returns (ProgramView memory) {
        ProgramStorage storage program = _existingProgram(programId);
        return ProgramView({
            status: program.status,
            publishedAt: program.publishedAt,
            updatedAt: program.updatedAt,
            programName: program.programName,
            partId: _partIdFromProgramId(programId),
            programVersion: program.programVersion,
            resources: program.resources
        });
    }

    function getProgramStatus(bytes32 programId) external view override returns (ProgramStatus) {
        return _programsById[programId].status;
    }

    function productTypeByProgramId(bytes32 programId) external view override returns (bytes32) {
        return _existingProgram(programId).resources.productTypeId;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          XML VIEW                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function statePartXmlTemplate(uint256 partId) external view override returns (string memory) {
        bytes32 programId = _programIdFromPartId(partId);
        ProgramStorage storage program = _programsById[programId];
        if (program.status == ProgramStatus.Unknown) {
            revert UnknownPart(partId);
        }
        return _programStateXml(programId, program);
    }


    /// @dev The registry only anchors the XML/XSLT documents; it does not resolve
    ///      the `evmstate:call` bindings itself (those are served by the deployed
    ///      product implementing the declared product type interface).
    function _programStateXml(bytes32 programId, ProgramStorage storage program) internal view returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<ProgramTerms xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\"",
            " programId=\"", _bytes32ToHexString(programId), "\"",
            " status=\"", uint256(program.status).toString(), "\"",
            " programVersion=\"", program.programVersion.toString(), "\"",
            " updatedAt=\"", uint256(program.updatedAt).toString(), "\"",
            ">",
            _include(program.resources.productTermsResource),
            _include(program.resources.styleSheetResource),
            "</ProgramTerms>"
        );
    }

    function _include(address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory href = string.concat(
            "web3://", resource.toHexString(), ":", block.chainid.toString(), "/text"
        );
        string memory integrity = string.concat(
            "keccak256-", _bytes32ToHexString(textResource.contentHash())
        );
        return string.concat(
            "<xi:include href=\"", href,
            "\" parse=\"text\" evmstate:integrity=\"", integrity, "\"/>"
        );
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  INTERNAL KEY / HASH LOGIC                */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function computeProgramId(string calldata programName) external view override returns (bytes32) {
        return _programId(programName);
    }

    function _programId(string memory programName) internal view returns (bytes32) {
        return keccak256(abi.encode(programName, address(this)));
    }

    function _programIdFromPartId(uint256 partId) internal pure returns (bytes32) {
        return bytes32(partId);
    }

    function _partIdFromProgramId(bytes32 programId) internal pure returns (uint256) {
        return uint256(programId);
    }

    function _touchProgram(ProgramStorage storage program) internal {
        unchecked { program.programVersion += 1; }
        program.updatedAt = uint64(block.timestamp);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    VALIDATION HELPERS                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _existingProgram(bytes32 programId) internal view returns (ProgramStorage storage program) {
        program = _programsById[programId];
        if (program.status == ProgramStatus.Unknown) {
            revert UnknownProgram(programId);
        }
    }

    function _ensureProgramWritable(bytes32 programId, ProgramStatus status) internal pure {
        if (status == ProgramStatus.Closed || status == ProgramStatus.Archived) {
            revert ProgramNotWritable(programId, status);
        }
    }

    /// @dev Allowed transitions:
    ///      Active    -> Suspended | Closed
    ///      Suspended -> Active | Closed
    ///      Closed    -> Archived
    ///      Archived  -> (terminal)
    function _validateStatusTransition(ProgramStatus oldStatus, ProgramStatus newStatus) internal pure {
        if (newStatus == ProgramStatus.Unknown) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == ProgramStatus.Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == ProgramStatus.Closed && newStatus != ProgramStatus.Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    function _validateProgramPublicationParams(ProgramPublicationParams calldata params) internal pure {
        if (bytes(params.programName).length == 0) {
            revert EmptyString("programName");
        }
        _validateProgramResources(params.resources);
    }

    function _validateProgramResources(ProgramResources calldata resources) internal pure {
        _validateTextResource(resources.productTermsResource, ResourceSlot.ProductTerms);
        _validateTextResource(resources.styleSheetResource, ResourceSlot.StyleSheet);

        if (resources.productTypeId == bytes32(0)) {
            revert ZeroHash("productTypeId");
        }
    }

    function _validateTextResource(address resource, ResourceSlot slot) internal view {
        if (resource == address(0)) {
            revert ZeroAddress("resource");
        }
        if (resource.code.length == 0) {
            revert InvalidResourceContract(resource);
        }

        // Must advertise ITextResource via ERC-165.
        try IERC165(resource).supportsInterface(type(ITextResource).interfaceId) returns (bool ok) {
            if (!ok) revert InvalidResourceInterface(resource);
        } catch {
            revert InvalidResourceInterface(resource);
        }

        ITextResource textResource = ITextResource(resource);

        // Must be finalized (immutable).
        try textResource.isFinalized() returns (bool finalized) {
            if (!finalized) revert ResourceNotFinalized(resource);
        } catch {
            revert InvalidResourceInterface(resource);
        }

        // Must carry an accepted resource type for this slot.
        try textResource.resourceType() returns (bytes32 actualResourceType) {
            if (!_isAcceptedResourceType(slot, actualResourceType)) {
                revert InvalidResourceType(resource, slot, actualResourceType);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    FINAL-CONTRACT HOOK                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Product-specific rule: which resource types are accepted per slot.
    function _isAcceptedResourceType(ResourceSlot slot, bytes32 resourceType) internal view virtual returns (bool);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       STRING HELPERS                      */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        return uint256(value).toHexString(32);
    }

}