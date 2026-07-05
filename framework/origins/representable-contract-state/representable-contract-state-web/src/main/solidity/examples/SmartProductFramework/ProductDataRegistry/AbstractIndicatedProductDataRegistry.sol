// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductDataRegistry} from "./AbstractProductDataRegistry.sol";
import {IProductIndications} from "./ProductIndications/IProductIndications.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AbstractIndicatedProductDataRegistry
/// @notice Layer 2: extends the program registry so each program can carry a
///         single, replaceable reference to a product indication
///         (IProductIndications) — e.g. a curve indication for a bond program.
/// @dev The indication is stored per program (same programId key) as a pair
///      (indicationContract, indicationId). Assignment validates the target via
///      ERC-165, the specific indication's status, and a product-specific
///      compatibility hook (_isAcceptedIndication). Liveness at consumption
///      time is NOT guaranteed here — a consuming/trade layer should re-check
///      the current status before presenting or trading against an indication.
///
/// @author Raphael Prandtl
abstract contract AbstractIndicatedProductDataRegistry is AbstractProductDataRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STORAGE                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Per-program indication reference.
    struct IndicationStorage {
        address productIndication;
        bytes32 indicationId;
        uint256 partId;
    }

    /// @dev Keyed by the same programId as _programsById (extends a program).
    mapping(bytes32 => IndicationStorage) internal _indicationsById;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when the indication address has no contract code.
    error InvalidIndicationContract(address productIndication);

    /// @notice Thrown when the target does not implement IProductIndications.
    error InvalidIndicationInterface(address productIndication);

    /// @notice Thrown when the indication category is not accepted for the
    ///         program's product type.
    error InvalidIndicationCategory(address productIndication, bytes32 indicationCategory);

    /// @notice Thrown when the referenced indication is not in an assignable
    ///         status (must be Active or Suspended).
    error InvalidIndicationStatus(address productIndication, IProductIndications.IndicationStatus status);

    /// @notice Thrown when a program has no product indication assigned.
    error MissingProductIndication(bytes32 programId);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when a program's product indication is assigned or replaced.
    event ProductIndicationAssigned(bytes32 indexed programId, address indexed productIndication, bytes32 indicationId);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_ Initial owner authorized to manage programs and indication assignments.
    constructor(address owner_) AbstractProductDataRegistry(owner_) {}

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                 PRODUCT INDICATION ASSIGNMENT            */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Assigns (or replaces) the product indication of a program.
    function assignProductIndication(bytes32 programId, address productIndication, bytes32 indicationId) external onlyOwner {
        ProgramStorage storage program = _existingProgram(programId);
        _ensureProgramWritable(programId, program.status);

        uint256 partId = _validateProductIndication(program.resources.productTypeId, productIndication, indicationId);

        IndicationStorage storage indication = _indicationsById[programId];
        indication.productIndication = productIndication;
        indication.indicationId = indicationId;
        indication.partId = partId;

        _touchProgram(program);

        emit ProductIndicationAssigned(programId, productIndication, indicationId);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProgramId(programId), program.programVersion);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         READ API                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the product indication assigned to a program, together
    ///         with the partId to render it on the indication contract.
    /// @dev Does not check the indication's current status — consumers should
    ///      verify liveness if required.
    function productIndicationOfProgram(bytes32 programId) external view returns (address productIndication, bytes32 indicationId, uint256 partId) {
        IndicationStorage storage indication = _existingIndication(programId);
        return (indication.productIndication, indication.indicationId, indication.partId);
    }


    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    VALIDATION HELPERS                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _existingIndication(bytes32 programId) internal view returns (IndicationStorage storage indication) {
        indication = _indicationsById[programId];
        if (indication.productIndication == address(0)) {
            revert MissingProductIndication(programId);
        }
    }

    function _validateProductIndication(bytes32 productTypeId, address productIndication, bytes32 indicationId) internal view returns (uint256 partId) {
        if (productIndication == address(0)) {
            revert ZeroAddress("productIndication");
        }
        if (productIndication.code.length == 0) {
            revert InvalidIndicationContract(productIndication);
        }

        try IERC165(productIndication).supportsInterface(type(IProductIndications).interfaceId) returns (bool ok) {
            if (!ok) {
                revert InvalidIndicationInterface(productIndication);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        IProductIndications registry = IProductIndications(productIndication);

        try registry.indicationStatus(indicationId) returns (IProductIndications.IndicationStatus status) {
            if (status != IProductIndications.IndicationStatus.Active && status != IProductIndications.IndicationStatus.Suspended) {
                revert InvalidIndicationStatus(productIndication, status);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        try registry.indicationCategory() returns (bytes32 category) {
            if (!_isAcceptedIndication(productTypeId, category)) {
                revert InvalidIndicationCategory(productIndication, category);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        try registry.partIdForIndication(indicationId) returns (uint256 resolvedPartId) {
            partId = resolvedPartId;
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }
    }


    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    FINAL-CONTRACT HOOK                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Product-specific rule: may an indication of `indicationCategory` be
    ///      attached to a program of `productTypeId`?
    function _isAcceptedIndication(bytes32 productTypeId, bytes32 indicationCategory) internal view virtual returns (bool);
}
