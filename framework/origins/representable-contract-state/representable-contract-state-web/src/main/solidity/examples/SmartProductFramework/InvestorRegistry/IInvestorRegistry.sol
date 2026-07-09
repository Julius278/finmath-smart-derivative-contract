// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IInvestorRegistry
/// @notice Manages investor identity and lifecycle, and validates whether an
///         investor is eligible to use a given financial product definition.
///
/// @dev OWNERSHIP
///      Implementations are expected to be Ownable (OpenZeppelin Ownable2Step):
///      owner() and ownership transfer come from that module and are therefore
///      not redeclared here.
///
/// @dev RELATIONSHIP TO PRODUCT REGISTRY
///      A tradable product registry consumes this contract's read API:
///        - isEligibleInvestor(investor, productDefinitionId) to check whether
///          the investor may use a specific product definition.
///
/// @dev ELIGIBILITY MODEL (derived, not stored)
///      Eligibility is derived from investor state at call time, not stored as
///      an explicit (investor, productDefinitionId) grant. The baseline rule is:
///        eligible == status is Active AND product-definition-specific criteria
///        are met.
///      The first implementation may treat all product definitions uniformly
///      (criteria always satisfied for active investors); future versions can
///      derive per-definition eligibility from stored investor attributes without
///      changing this interface.
///
/// @dev TERMINOLOGY
///      - "registered": the investor is known to the system (status != Unknown),
///        regardless of whether currently Active. Once registered, an investor
///        is never fully removed; only their status changes.
///      - "eligible": the investor may currently use a specific product
///        definition.
///
/// @author Raphael Prandtl
interface IInvestorRegistry {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Lifecycle status of an investor.
    /// @dev `Unknown` is the default value and acts as the "not registered"
    ///      sentinel. `Revoked` is terminal (see implementation rules).
    enum InvestorStatus {
        Unknown,
        Active,
        Suspended,
        Revoked
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STRUCTS                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Parameters supplied when registering or updating an investor.
    /// @dev `investor` is the immutable key; only ancillary fields (e.g. `lei`)
    ///      are mutable via updateInvestor. May be extended in future versions.
    struct InvestorRegistrationParams {
        address investor;
        string lei;
    }

    /// @notice Full investor record as stored on-chain.
    /// @param status       Current lifecycle status.
    /// @param lei          Legal Entity Identifier (ISO 17442).
    /// @param registeredAt Unix timestamp of initial registration.
    /// @param updatedAt    Unix timestamp of the last mutation.
    struct InvestorView {
        InvestorStatus status;
        string lei;
        uint64 registeredAt;
        uint64 updatedAt;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress(string fieldName);

    /// @notice Thrown when a required string argument is empty.
    error EmptyString(string fieldName);

    /// @notice Thrown when referencing an investor not known to the system.
    error UnknownInvestor(address investor);

    /// @notice Thrown when registering an investor that already exists.
    error InvestorAlreadyRegistered(address investor);

    /// @notice Thrown when a status transition is not allowed
    ///         (e.g. to Unknown, or away from terminal Revoked).
    error InvalidStatusTransition(InvestorStatus from, InvestorStatus to);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when a new investor is registered (initial status Active).
    event InvestorRegistered(address indexed investor);

    /// @notice Emitted when an existing investor's ancillary data is updated.
    event InvestorUpdated(address indexed investor);

    /// @notice Emitted on every status change, including the initial
    ///         Unknown -> Active transition at registration.
    event InvestorStatusChanged(address indexed investor, InvestorStatus oldStatus, InvestorStatus newStatus);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*              INVESTOR LIFECYCLE MANAGEMENT                */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Registers a new investor with initial status Active.
    function registerInvestor(InvestorRegistrationParams calldata params) external;

    /// @notice Updates an existing investor's ancillary data (e.g. LEI).
    function updateInvestor(InvestorRegistrationParams calldata params) external;

    /// @notice Sets the status of an existing investor.
    function setInvestorStatus(address investor, InvestorStatus newStatus) external;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                   INVESTOR READ API                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the full stored record of an investor.
    function getInvestor(address investor) external view returns (InvestorView memory);

    /// @notice Returns the current status of an investor.
    function investorStatus(address investor) external view returns (InvestorStatus);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                 INVESTOR VALIDATION API                   */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns whether an investor is known to the system.
    function isRegisteredInvestor(address investor) external view returns (bool);

    /// @notice Returns whether an investor may currently use a given product
    ///         definition.
    /// @dev Derived at call time. Baseline: status == Active and
    ///      product-definition-specific criteria are met.
    ///      `productDefinitionId` may be unused in simple implementations.
    function isEligibleInvestor(address investor, bytes32 productDefinitionId) external view returns (bool);
}
