// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IClientRegistry
 * @notice Manages client identity, lifecycle and product-definition eligibility.
 * @dev Defines participant onboarding and eligibility independently of products.
 *
 *      Implementations are expected to use Ownable2Step. Ownership functions
 *      belong to that module and are not redeclared here.
 *
 *      A client is registered whenever its status is not Unknown. Revoked is a
 *      terminal lifecycle status, but does not delete the client record.
 *      Eligibility is derived, not stored as an explicit per-definition grant.
 *
 * @author Raphael Prandtl
 */
interface IClientRegistry {
    // ------------------------------ Enums ------------------------------ */

    /**
     * @notice Lifecycle status of a client.
     * @dev `Unknown` is the default value and acts as the "not registered"
     *      sentinel. `Revoked` is terminal (see implementation rules).
     */
    enum ClientStatus {
        Unknown,
        Pending,
        Active,
        Suspended,
        Revoked
    }

    // ------------------------------ Structs ------------------------------ */

    /**
     * @notice Input for registration or a full update of client identity data.
     * @param client Immutable lookup key; not duplicated inside the stored record.
     * @param lei Required, non-empty Legal Entity Identifier.
     * @param bic Required, non-empty Business Identifier Code.
     * @dev Status and timestamps are managed by the registry, not by this input.
     *      updateClient proposes replacement of both lei and bic;
     *      This interface does not prescribe identifier-format validation.
     */
    struct ClientRegistrationParams {
        address client;
        string lei;
        string bic;
    }

    /**
     * @notice Canonical client record, used both in storage and as a read result.
     * @param status Current lifecycle status.
     * @param registeredAt Unix timestamp of initial registration.
     * @param updatedAt Unix timestamp of the last client-record mutation.
     * @param lei Legal Entity Identifier.
     * @param bic Business Identifier Code.
     */
    struct Client {
        ClientStatus status;
        uint64 registeredAt;
        uint64 updatedAt;
        string lei;
        string bic;
    }

    /// @notice Owner-proposed data awaiting approval by the exact client address.
    struct ClientDataProposal {
        uint256 revision;
        uint256 ownershipEpoch;
        bytes32 dataHash;
        string lei;
        string bic;
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress(string fieldName);
    /// @notice Thrown when a required string argument is empty.
    error EmptyString(string fieldName);
    /// @notice Thrown when referencing a client not known to the system.
    error UnknownClient(address client);
    /// @notice Thrown when registering a client that already exists.
    error ClientAlreadyRegistered(address client);
    /// @notice Thrown when a status transition is not allowed (e.g. to Unknown, or away from terminal Revoked).
    error InvalidStatusTransition(ClientStatus from, ClientStatus to);
    error ClientDataNotConfirmed(address client);
    error NoPendingClientData(address client);
    error InvalidClientDataConfirmation(address client);
    error UnauthorizedClientDataAction(address client);
    error RevokedClient(address client);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a new client is registered (initial status Pending).
    event ClientRegistered(address indexed client);
    /// @notice Emitted when client confirmation makes identity data effective.
    event ClientUpdated(address indexed client);
    event ClientDataProposed(address indexed client, uint256 revision, bytes32 dataHash);
    event ClientDataConfirmed(address indexed client, uint256 revision, bytes32 dataHash);
    event ClientDataProposalCancelled(address indexed client, uint256 revision);
    /**
     * @notice Emitted on every status change, including the initial
     *         Unknown -> Pending transition at registration.
     */
    event ClientStatusChanged(address indexed client, ClientStatus oldStatus, ClientStatus newStatus);

    // ------------------------------ Client Lifecycle Management ------------------------------ */

    /// @notice Owner registers a Pending client and proposes its initial identity data.
    function registerClient(ClientRegistrationParams calldata params) external;

    /// @notice Owner proposes new identity data; confirmed data remain effective until approval.
    function updateClient(ClientRegistrationParams calldata params) external;

    /**
     * @notice Approves the caller's exact current proposal. No identity data are supplied by the client.
     * @dev expectedDataHash = keccak256(abi.encode(chainId, registry, client, revision, ownershipEpoch, lei, bic)).
     *      Compute this from reviewed values. Only Pending transitions to Active; Suspended stays Suspended.
     */
    function confirmClientData(uint256 expectedRevision, bytes32 expectedDataHash) external;

    /// @notice Owner or affected client cancels the exact pending revision, leaving effective data and status unchanged.
    function cancelClientDataProposal(address client, uint256 expectedRevision) external;

    /// @notice Changes a registered client's status; Revoked is terminal.
    function setClientStatus(address client, ClientStatus newStatus) external;

    // ------------------------------ Client Read API ------------------------------ */

    /// @notice Returns confirmed identity data (empty before first confirmation); reverts for an unknown client.
    function getClient(address client) external view returns (Client memory);

    /// @notice Returns the current proposal; reverts if absent or invalidated by an ownership change.
    function getPendingClientData(address client) external view returns (ClientDataProposal memory);

    /// @notice Completed ownership transfers and renunciation invalidate proposals from older epochs.
    function ownershipEpoch() external view returns (uint256);

    /// @notice Returns Unknown for an address that has never been registered.
    function clientStatus(address client) external view returns (ClientStatus);

    // ------------------------------ Client Validation API ------------------------------ */

    /// @notice Returns whether the client is known, regardless of current status.
    function isRegisteredClient(address client) external view returns (bool);

    /**
     * @notice Returns whether a client may use the given product definition.
     * @dev Baseline rule: Active plus product-definition-specific criteria.
     */
    function isEligibleClient(address client, bytes32 productDefinitionId) external view returns (bool);
}
