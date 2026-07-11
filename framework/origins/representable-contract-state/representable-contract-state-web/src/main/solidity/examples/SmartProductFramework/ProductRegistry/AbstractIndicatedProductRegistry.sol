// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductDefinitionRegistry} from "./AbstractProductDefinitionRegistry.sol";
import {IProductIndication} from "../ProductIndication/IProductIndication.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AbstractIndicatedProductRegistry.sol
/// @notice Layer 2: extends the product definition registry so each product
///         definition can carry a single, replaceable reference to a product indication
///         (IProductIndication) — e.g. a curve indication for a bond definition.
///
/// @dev The indication is stored per productDefinitionId as a tuple
///      (productIndication, indicationId, partId). Assignment validates the
///      target via ERC-165, the specific indication's status, and a
///      product-specific compatibility hook (_isAcceptedIndication).
///
///      Liveness at consumption time is NOT guaranteed here. A consuming or
///      trading layer should re-check the current indication status before
///      presenting or trading against an indication.
///
/// @author Raphael Prandtl
abstract contract AbstractIndicatedProductRegistry is AbstractProductDefinitionRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STORAGE                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Per-product-definition indication reference.
    struct ProductIndicationAssignment {
        address productIndication;
        bytes32 indicationId;
        uint256 partId;
    }

    /// @dev Keyed by the same productDefinitionId as _productDefinitionsById.
    mapping(bytes32 => ProductIndicationAssignment) internal _indicationsByDefinitionId;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when the indication address has no contract code.
    error InvalidIndicationContract(address productIndication);

    /// @notice Thrown when the target does not implement IProductIndication.
    error InvalidIndicationInterface(address productIndication);

    /// @notice Thrown when the indication category is not accepted for the
    ///         product definition's product type.
    error InvalidIndicationCategory(address productIndication, bytes32 indicationCategory);

    /// @notice Thrown when the referenced indication is not in an assignable
    ///         status. Assignable statuses are Active and Suspended.
    error InvalidIndicationStatus(address productIndication, IProductIndication.IndicationStatus status);

    /// @notice Thrown when a product definition has no product indication assigned.
    error MissingProductIndication(bytes32 productDefintionId);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

/// @notice Emitted when a product definition's product indication is assigned or replaced.
    event ProductIndicationAssigned(bytes32 indexed productDefinitionId, address indexed productIndication, bytes32 indicationId);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_ Initial owner authorized to manage product definitions and indication assignments.
    constructor(address owner_) AbstractProductDefinitionRegistry(owner_) {}

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                 PRODUCT INDICATION ASSIGNMENT            */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Assigns (or replaces) the product indication of a product definition.
    function assignProductIndication(bytes32 productDefinitionId, address productIndication, bytes32 indicationId) external onlyOwner {
        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definition.status);

        uint256 partId = _validateProductIndication(definition.resources.productTypeId, productIndication, indicationId);

        ProductIndicationAssignment storage assignment = _indicationsByDefinitionId[productDefinitionId];
        assignment.productIndication = productIndication;
        assignment.indicationId = indicationId;
        assignment.partId = partId;

        _touchProductDefinition(definition);

        emit ProductIndicationAssigned(productDefinitionId, productIndication, indicationId);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         READ API                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the product indication assigned to a product definition,
    ///         together with the partId to render it on the indication contract.
    /// @dev Does not check the indication's current status — consumers should
    ///      verify liveness if required.
    function productIndicationOfDefinition(bytes32 productDefinitionId) external view returns (address productIndication, bytes32 indicationId, uint256 partId) {
        ProductIndicationAssignment storage assignment = _existingProductIndicationAssignment(productDefinitionId);
        return (assignment.productIndication, assignment.indicationId, assignment.partId);
    }


    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    VALIDATION HELPERS                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _existingProductIndicationAssignment(bytes32 productDefinitionId) internal view returns (ProductIndicationAssignment storage assignment) {
        assignment = _indicationsByDefinitionId[productDefinitionId];
        if (assignment.productIndication == address(0)) {
            revert MissingProductIndication(productDefinitionId);
        }
    }

    function _validateProductIndication(bytes32 productTypeId, address productIndication, bytes32 indicationId) internal view returns (uint256 partId) {
        if (productIndication == address(0)) {
            revert ZeroAddress("productIndication");
        }
        if (indicationId == bytes32(0)) {
            revert ZeroHash("indicationId");
        }
        if (productIndication.code.length == 0) {
            revert InvalidIndicationContract(productIndication);
        }

        try IERC165(productIndication).supportsInterface(type(IProductIndication).interfaceId) returns (bool ok) {
            if (!ok) {
                revert InvalidIndicationInterface(productIndication);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        IProductIndication indicationRegistry = IProductIndication(productIndication);

        try indicationRegistry.indicationStatus(indicationId) returns (IProductIndication.IndicationStatus status) {
            if (status != IProductIndication.IndicationStatus.Active && status != IProductIndication.IndicationStatus.Suspended) {
                revert InvalidIndicationStatus(productIndication, status);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        try indicationRegistry.indicationCategory() returns (bytes32 category) {
            if (!_isAcceptedIndication(productTypeId, category)) {
                revert InvalidIndicationCategory(productIndication, category);
            }
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }

        try indicationRegistry.partIdForIndication(indicationId) returns (uint256 resolvedPartId) {
            partId = resolvedPartId;
        } catch {
            revert InvalidIndicationInterface(productIndication);
        }
    }


    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    FINAL-CONTRACT HOOK                    */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Product-specific rule: may an indication of `indicationCategory` be
    ///      attached to a product definition of `productTypeId`?
    function _isAcceptedIndication(bytes32 productTypeId, bytes32 indicationCategory) internal view virtual returns (bool);
}
