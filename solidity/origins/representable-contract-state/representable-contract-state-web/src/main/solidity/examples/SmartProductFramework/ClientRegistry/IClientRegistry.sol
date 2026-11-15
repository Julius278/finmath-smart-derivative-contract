// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IClientRegistry
 * @notice Manages client identity and lifecycle, and validates whether an
 *         client is eligible to use a given financial product definition.
 *
 * @dev OWNERSHIP
 *      Implementations are expected to be Ownable (OpenZeppelin Ownable2Step):
 *      owner() and ownership transfer come from that module and are therefore
 *      not redeclared here.
 *
 * @dev RELATIONSHIP TO PRODUCT REGISTRY
 *      A product registry consumes this contract's read API:
 *        - isEligibleClient(client, productDefinitionId) to check whether
 *          the client may use a specific product definition.
 *
 * @dev ELIGIBILITY MODEL (derived, not stored)
 *      Eligibility is derived from client state at call time, not stored as
 *      an explicit (client, productDefinitionId) grant. The baseline rule is:
 *        eligible == status is Active AND product-definition-specific criteria
 *        are met.
 *      The first implementation may treat all product definitions uniformly
 *      (criteria always satisfied for active clients); future versions can
 *      derive per-definition eligibility from stored client attributes without
 *      changing this interface.
 *
 * @dev TERMINOLOGY
 *      - "registered": the client is known to the system (status != Unknown),
 *        regardless of whether currently Active. Once registered, a client
 *        is never fully removed; only their status changes.
 *      - "eligible": the client may currently use a specific product
 *        definition.
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
        Active,
        Suspended,
        Revoked
    }

    // ------------------------------ Structs ------------------------------ */

    /**
     * @notice Parameters supplied when registering or updating a client.
     * @dev `client` is the immutable key; only ancillary fields (e.g. `lei`)
     *      are mutable via updateClient. May be extended in future versions.
     */
    struct ClientRegistrationParams {
        address client;
        string lei;
    }

    /**
     * @notice Full client record as stored on-chain.
     * @param status       Current lifecycle status.
     * @param lei          Legal Entity Identifier (ISO 17442).
     * @param registeredAt Unix timestamp of initial registration.
     * @param updatedAt    Unix timestamp of the last mutation.
     */
    struct ClientView {
        ClientStatus status;
        string lei;
        uint64 registeredAt;
        uint64 updatedAt;
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

    /**
     * @notice Thrown when a status transition is not allowed
     *         (e.g. to Unknown, or away from terminal Revoked).
     */
    error InvalidStatusTransition(ClientStatus from, ClientStatus to);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a new client is registered (initial status Active).
    event ClientRegistered(address indexed client);

    /// @notice Emitted when an existing client's ancillary data is updated.
    event ClientUpdated(address indexed client);

    /**
     * @notice Emitted on every status change, including the initial
     *         Unknown -> Active transition at registration.
     */
    event ClientStatusChanged(address indexed client, ClientStatus oldStatus, ClientStatus newStatus);

    // ------------------------------ Client Lifecycle Management ------------------------------ */

    /// @notice Registers a new client with initial status Active.
    function registerClient(ClientRegistrationParams calldata params) external;

    /// @notice Updates an existing client's ancillary data (e.g. LEI).
    function updateClient(ClientRegistrationParams calldata params) external;

    /// @notice Sets the status of an existing client.
    function setClientStatus(address client, ClientStatus newStatus) external;

    // ------------------------------ Client Read API ------------------------------ */

    /// @notice Returns the full stored record of a client.
    function getClient(address client) external view returns (ClientView memory);

    /// @notice Returns the current status of a client.
    function clientStatus(address client) external view returns (ClientStatus);

    // ------------------------------ Client Validation API ------------------------------ */

    /// @notice Returns whether a client is known to the system.
    function isRegisteredClient(address client) external view returns (bool);

    /**
     * @notice Returns whether a client may currently use a given product
     *         definition.
     * @dev Derived at call time. Baseline: status == Active and
     *      product-definition-specific criteria are met.
     *      `productDefinitionId` may be unused in simple implementations.
     */
    function isEligibleClient(address client, bytes32 productDefinitionId) external view returns (bool);
}
