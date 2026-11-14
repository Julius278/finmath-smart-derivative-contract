// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IClientRegistry} from "./IClientRegistry.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title ClientRegistry
 * @notice Client-only registry: identity, lifecycle and derived eligibility.
 * @dev Independently deployable, without a product-registry dependency.
 *      Ownership uses OpenZeppelin Ownable2Step.
 *
 * @author Raphael Prandtl
 */
contract ClientRegistry is IClientRegistry, Ownable2Step {
    // ------------------------------ Storage ------------------------------ */

    /// @dev The same Client type is used for storage and getClient's return value.
    mapping(address => Client) private _clients;
    mapping(address => ClientDataProposal) private _pendingClientData;
    mapping(address => uint256) private _proposalRevisions;
    mapping(address => bool) private _hasConfirmedData;
    uint256 public override ownershipEpoch;

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to manage clients.
    constructor(address owner_) {
        _transferOwnership(owner_);
    }
    // ------------------------------ Client Lifecycle Management ------------------------------ */

    function registerClient(ClientRegistrationParams calldata params) external override onlyOwner {
        _validateRegistrationParams(params);

        address client = params.client;
        Client storage stored = _clients[client];
        if (stored.status != ClientStatus.Unknown) {
            revert ClientAlreadyRegistered(client);
        }

        uint64 nowTs = uint64(block.timestamp);
        stored.status = ClientStatus.Pending;
        stored.registeredAt = nowTs;
        stored.updatedAt = nowTs;

        emit ClientRegistered(client);
        emit ClientStatusChanged(client, ClientStatus.Unknown, ClientStatus.Pending);
        _proposeClientData(params);
    }

    function updateClient(ClientRegistrationParams calldata params) external override onlyOwner {
        _validateRegistrationParams(params);

        _requireNotRevoked(params.client, _existingClient(params.client));
        _proposeClientData(params);
    }

    function confirmClientData(uint256 expectedRevision, bytes32 expectedDataHash) external override {
        address client = _msgSender();
        Client storage stored = _existingClient(client);
        _requireNotRevoked(client, stored);
        ClientDataProposal storage proposal = _currentProposal(client);
        if (proposal.revision != expectedRevision || proposal.dataHash != expectedDataHash) {
            revert InvalidClientDataConfirmation(client);
        }

        stored.lei = proposal.lei;
        stored.bic = proposal.bic;
        stored.updatedAt = uint64(block.timestamp);
        _hasConfirmedData[client] = true;
        delete _pendingClientData[client];

        // A client may approve its data while suspended, but cannot lift an owner-imposed suspension.
        if (stored.status == ClientStatus.Pending) {
            stored.status = ClientStatus.Active;
            emit ClientStatusChanged(client, ClientStatus.Pending, ClientStatus.Active);
        }
        emit ClientUpdated(client);
        emit ClientDataConfirmed(client, expectedRevision, expectedDataHash);
    }

    function cancelClientDataProposal(address client, uint256 expectedRevision) external override {
        if (_msgSender() != owner() && _msgSender() != client) {
            revert UnauthorizedClientDataAction(client);
        }
        _existingClient(client);
        if (_currentProposal(client).revision != expectedRevision) {
            revert InvalidClientDataConfirmation(client);
        }
        delete _pendingClientData[client];
        emit ClientDataProposalCancelled(client, expectedRevision);
    }

    function setClientStatus(address client, ClientStatus newStatus) external override onlyOwner {
        Client storage stored = _existingClient(client);
        ClientStatus oldStatus = stored.status;
        if (oldStatus == newStatus) {
            return;
        }

        _validateStatusTransition(oldStatus, newStatus);
        if (newStatus == ClientStatus.Active && !_hasConfirmedData[client]) {
            revert ClientDataNotConfirmed(client);
        }

        if (newStatus == ClientStatus.Revoked && _pendingClientData[client].revision != 0) {
            emit ClientDataProposalCancelled(client, _pendingClientData[client].revision);
            delete _pendingClientData[client];
        }

        stored.status = newStatus;
        stored.updatedAt = uint64(block.timestamp);

        emit ClientStatusChanged(client, oldStatus, newStatus);
    }

    // ------------------------------ Client Read API ------------------------------ */

    function getClient(address client) external view override returns (Client memory) {
        return _existingClient(client);
    }

    function getPendingClientData(address client) external view override returns (ClientDataProposal memory) {
        _existingClient(client);
        return _currentProposal(client);
    }

    function clientStatus(address client) external view override returns (ClientStatus) {
        return _clients[client].status;
    }

    // ------------------------------ Client Validation API ------------------------------ */

    function isRegisteredClient(address client) external view override returns (bool) {
        return _clients[client].status != ClientStatus.Unknown;
    }

    function isEligibleClient(address client, bytes32 productDefinitionId) external view override returns (bool) {
        Client storage stored = _clients[client];
        if (stored.status != ClientStatus.Active) {
            return false;
        }
        return _isEligibleForProductDefinition(client, productDefinitionId, stored);
    }

    // ------------------------------ Business Rules ------------------------------ */

    /**
     * @dev First version: every Active client is eligible for every definition.
     *      Derived implementations can use the client address, definition or data.
     */
    function _isEligibleForProductDefinition(address, bytes32, Client storage) internal view virtual returns (bool) {
        return true;
    }

    /**
     * @dev Disallows owner transitions to Unknown/Pending and away from terminal Revoked.
     *      An unchanged status is handled as a no-op by setClientStatus.
     */
    function _validateStatusTransition(ClientStatus oldStatus, ClientStatus newStatus) internal pure virtual {
        if (newStatus == ClientStatus.Unknown || newStatus == ClientStatus.Pending || oldStatus == ClientStatus.Revoked) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    // ------------------------------ Internal Validation Helpers ------------------------------ */

    function _proposeClientData(ClientRegistrationParams calldata params) private {
        uint256 revision = ++_proposalRevisions[params.client];
        bytes32 dataHash = keccak256(abi.encode(
            block.chainid, address(this), params.client, revision, ownershipEpoch, params.lei, params.bic
        ));
        _pendingClientData[params.client] = ClientDataProposal(
            revision, ownershipEpoch, dataHash, params.lei, params.bic
        );
        emit ClientDataProposed(params.client, revision, dataHash);
    }

    function _currentProposal(address client) private view returns (ClientDataProposal storage proposal) {
        proposal = _pendingClientData[client];
        if (proposal.revision == 0 || proposal.ownershipEpoch != ownershipEpoch) {
            revert NoPendingClientData(client);
        }
    }

    function _requireNotRevoked(address client, Client storage stored) private view {
        if (stored.status == ClientStatus.Revoked) {
            revert RevokedClient(client);
        }
    }

    /// @dev Invalidate outstanding proposals without iteration, including owner A -> B -> A and renunciation.
    function _transferOwnership(address newOwner) internal override {
        super._transferOwnership(newOwner);
        ++ownershipEpoch;
    }

    /**
     * @dev Preserves the original address, LEI and BIC requirements.
     *      Neither LEI nor BIC format is validated by this baseline implementation.
     *      Override to impose additional identity-data requirements.
     */
    function _validateRegistrationParams(ClientRegistrationParams calldata params) internal pure virtual {
        if (params.client == address(0)) {
            revert ZeroAddress("client");
        }
        if (bytes(params.lei).length == 0) {
            revert EmptyString("lei");
        }
        if (bytes(params.bic).length == 0) {
            revert EmptyString("bic");
        }
    }

    function _existingClient(address client) internal view returns (Client storage storedClient) {
        storedClient = _clients[client];
        if (storedClient.status == ClientStatus.Unknown) {
            revert UnknownClient(client);
        }
    }
}
