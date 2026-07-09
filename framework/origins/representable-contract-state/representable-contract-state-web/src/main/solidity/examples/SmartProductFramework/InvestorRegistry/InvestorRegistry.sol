// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IInvestorRegistry} from "./InvestorRegistry/IInvestorRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";



/// @title InvestorRegistry
/// @notice Single-contract implementation of IInvestorRegistry.
///         Investors are registered with an initial Active status; their
///         lifecycle status can be changed by the owner. Revoked is terminal.
///         Eligibility is derived at call time: in this first version any
///         Active investor is eligible for any product definition.
/// @dev Ownership uses OpenZeppelin Ownable2Step (two-step transfer).
///
/// @author Raphael Prandtl
contract InvestorRegistry is IInvestorRegistry, Ownable2Step {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                        STORAGE                            */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    struct InvestorStorage {
        InvestorStatus status;
        uint64 registeredAt;
        uint64 updatedAt;
        string lei;
    }

    mapping(address => InvestorStorage) private _investors;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_ Initial owner authorized to manage investors.
    constructor(address owner_) Ownable(owner_) {}

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*              INVESTOR LIFECYCLE MANAGEMENT                */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function registerInvestor(InvestorRegistrationParams calldata params) external override onlyOwner {
        _validateRegistrationParams(params);

        address investor = params.investor;
        InvestorStorage storage stored = _investors[investor];
        if (stored.status != InvestorStatus.Unknown) {
            revert InvestorAlreadyRegistered(investor);
        }
        uint64 nowTs = uint64(block.timestamp);
        stored.status = InvestorStatus.Active;
        stored.lei = params.lei;
        stored.registeredAt = nowTs;
        stored.updatedAt = nowTs;

        emit InvestorRegistered(investor);
        emit InvestorStatusChanged(investor, InvestorStatus.Unknown, InvestorStatus.Active);

    }

    function updateInvestor(InvestorRegistrationParams calldata params) external override onlyOwner {
        _validateRegistrationParams(params);

        InvestorStorage storage stored = _existingInvestor(params.investor);
        stored.lei = params.lei;
        stored.updatedAt = uint64(block.timestamp);

        emit InvestorUpdated(params.investor);
    }

    function setInvestorStatus(address investor, InvestorStatus newStatus) external override onlyOwner {
        InvestorStorage storage stored = _existingInvestor(investor);
        InvestorStatus oldStatus = stored.status;
        if (oldStatus == newStatus) {
            return;
        }

        _validateStatusTransition(oldStatus, newStatus);

        stored.status = newStatus;
        stored.updatedAt = uint64(block.timestamp);

        emit InvestorStatusChanged(investor, oldStatus, newStatus);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                     INVESTOR READ API                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function getInvestor(address investor) external view override returns (InvestorView memory) {
        InvestorStorage storage stored = _existingInvestor(investor);
        return InvestorView({
            status: stored.status,
            lei: stored.lei,
            registeredAt: stored.registeredAt,
            updatedAt: stored.updatedAt
        });
    }

    function investorStatus(address investor) external view override returns (InvestorStatus) {
        return _investors[investor].status;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                 INVESTOR VALIDATION API                   */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function isRegisteredInvestor(address investor) external view override returns (bool) {
        return _investors[investor].status != InvestorStatus.Unknown;
    }

    function isEligibleInvestor(address investor, bytes32 productDefinitionId) external view override returns (bool) {
        InvestorStorage storage stored = _investors[investor];
        if (stored.status != InvestorStatus.Active) {
            return false;
        }
        return _isEligibleForProductDefinition(investor, productDefinitionId, stored);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                      BUSINESS RULES                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Product-definition-specific eligibility. First version: any active
    ///      investor is eligible for any product definition, so
    ///      `productDefinitionId` and stored data are unused.
    function _isEligibleForProductDefinition(address, bytes32, InvestorStorage storage) internal view virtual returns (bool) {
        return true;
    }

    /// @dev Allowed transitions: any -> {Active, Suspended, Revoked}, except
    ///      transitions to Unknown and any transition away from Revoked.
    function _validateStatusTransition(InvestorStatus oldStatus, InvestorStatus newStatus) internal pure virtual  {
        if (newStatus == InvestorStatus.Unknown || oldStatus == InvestorStatus.Revoked) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*               INTERNAL VALIDATION HELPERS                 */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _validateRegistrationParams(InvestorRegistrationParams calldata params) internal pure {
        if (params.investor == address(0)) {
            revert ZeroAddress("investor");
        }
        if (bytes(params.lei).length == 0) {
            revert EmptyString("lei");
        }
    }

    function _existingInvestor(address investor) internal view returns (InvestorStorage storage storedInvestor) {
        storedInvestor = _investors[investor];
        if (storedInvestor.status == InvestorStatus.Unknown) {
            revert UnknownInvestor(investor);
        }
    }

}