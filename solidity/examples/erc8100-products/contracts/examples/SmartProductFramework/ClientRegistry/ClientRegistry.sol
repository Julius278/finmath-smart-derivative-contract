// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IClientRegistry} from "./IClientRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title ClientRegistry
 * @notice Single-contract implementation of IClientRegistry.
 *         Clients are registered with an initial Active status; their
 *         lifecycle status can be changed by the owner. Revoked is terminal.
 *         Eligibility is derived at call time: in this first version any
 *         Active client is eligible for any product definition.
 * @dev Ownership uses OpenZeppelin Ownable2Step (two-step transfer).
 *
 * @author Raphael Prandtl
 */
contract ClientRegistry is IClientRegistry, Ownable2Step {
    // ------------------------------ Storage ------------------------------ */

    struct ClientStorage {
        ClientStatus status;
        uint64 registeredAt;
        uint64 updatedAt;
        string lei;
    }

    mapping(address => ClientStorage) private _clients;

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to manage clients.
    constructor(address owner_) Ownable(owner_) {}

    // ------------------------------ Client Lifecycle Management ------------------------------ */

    function registerClient(ClientRegistrationParams calldata params) external override onlyOwner {
        _validateRegistrationParams(params);

        address client = params.client;
        ClientStorage storage stored = _clients[client];
        if (stored.status != ClientStatus.Unknown) {
            revert ClientAlreadyRegistered(client);
        }
        uint64 nowTs = uint64(block.timestamp);
        stored.status = ClientStatus.Active;
        stored.lei = params.lei;
        stored.registeredAt = nowTs;
        stored.updatedAt = nowTs;

        emit ClientRegistered(client);
        emit ClientStatusChanged(client, ClientStatus.Unknown, ClientStatus.Active);

    }

    function updateClient(ClientRegistrationParams calldata params) external override onlyOwner {
        _validateRegistrationParams(params);

        ClientStorage storage stored = _existingClient(params.client);
        stored.lei = params.lei;
        stored.updatedAt = uint64(block.timestamp);

        emit ClientUpdated(params.client);
    }

    function setClientStatus(address client, ClientStatus newStatus) external override onlyOwner {
        ClientStorage storage stored = _existingClient(client);
        ClientStatus oldStatus = stored.status;
        if (oldStatus == newStatus) {
            return;
        }

        _validateStatusTransition(oldStatus, newStatus);

        stored.status = newStatus;
        stored.updatedAt = uint64(block.timestamp);

        emit ClientStatusChanged(client, oldStatus, newStatus);
    }

    // ------------------------------ Client Read API ------------------------------ */

    function getClient(address client) external view override returns (ClientView memory) {
        ClientStorage storage stored = _existingClient(client);
        return ClientView({
            status: stored.status,
            lei: stored.lei,
            registeredAt: stored.registeredAt,
            updatedAt: stored.updatedAt
        });
    }

    function clientStatus(address client) external view override returns (ClientStatus) {
        return _clients[client].status;
    }

    // ------------------------------ Client Validation API ------------------------------ */

    function isRegisteredClient(address client) external view override returns (bool) {
        return _clients[client].status != ClientStatus.Unknown;
    }

    function isEligibleClient(address client, bytes32 productDefinitionId) external view override returns (bool) {
        ClientStorage storage stored = _clients[client];
        if (stored.status != ClientStatus.Active) {
            return false;
        }
        return _isEligibleForProductDefinition(client, productDefinitionId, stored);
    }

    // ------------------------------ Business Rules ------------------------------ */

    /**
     * @dev Product-definition-specific eligibility. First version: any active
     *      client is eligible for any product definition, so
     *      `productDefinitionId` and stored data are unused.
     */
    function _isEligibleForProductDefinition(address, bytes32, ClientStorage storage) internal view virtual returns (bool) {
        return true;
    }

    /**
     * @dev Allowed transitions: any -> {Active, Suspended, Revoked}, except
     *      transitions to Unknown and any transition away from Revoked.
     */
    function _validateStatusTransition(ClientStatus oldStatus, ClientStatus newStatus) internal pure virtual  {
        if (newStatus == ClientStatus.Unknown || oldStatus == ClientStatus.Revoked) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    // ------------------------------ Internal Validation Helpers ------------------------------ */

    function _validateRegistrationParams(ClientRegistrationParams calldata params) internal pure {
        if (params.client == address(0)) {
            revert ZeroAddress("client");
        }
        if (bytes(params.lei).length == 0) {
            revert EmptyString("lei");
        }
    }

    function _existingClient(address client) internal view returns (ClientStorage storage storedClient) {
        storedClient = _clients[client];
        if (storedClient.status == ClientStatus.Unknown) {
            revert UnknownClient(client);
        }
    }

}
