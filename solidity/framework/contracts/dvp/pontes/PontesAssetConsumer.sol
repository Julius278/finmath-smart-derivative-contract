// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ILockingContractWithKeyGeneration} from "@finmath.net/dvp/contracts/ILockingContractWithKeyGeneration.sol";
import {IDecryptionContractWithKeyGeneration} from "@finmath.net/dvp/contracts/IDecryptionContractWithKeyGeneration.sol";
import {IDecryptionContractInceptionCallback} from "@finmath.net/dvp/contracts/IDecryptionContractInceptionCallback.sol";

/**
 * @title PontesAssetConsumer
 * @notice Deployable ERC-7573 locking harness for a Pontes-backed asset leg.
 * @dev This contract models locking and terminal ownership but intentionally does not mint or
 *      transfer a particular token. Production asset contracts can reuse its exact payment-context,
 *      generated-key and key-consumption checks around their token-specific lock/transfer calls.
 *      Payment verification is owned and enforced by the payment contract before it releases an
 *      execution key. The seller and buyer are known trade participants configured at deployment.
 */
contract PontesAssetConsumer is ILockingContractWithKeyGeneration {
    enum State {
        None,
        Incepted,
        Locked,
        Claimed,
        Reclaimed
    }

    struct Lock {
        address seller;
        address buyer;
        int256 amount;
        bytes32 executionHash;
        bytes32 cancellationHash;
        bytes encryptedExecutionKey;
        bytes encryptedCancellationKey;
        address paymentContract;
        bytes transaction;
        bool generatedKeys;
        bool generatedKeyCompletionRecorded;
        State state;
    }

    struct PaymentInceptionContext {
        bool exists;
        int256 amount;
        address from;
        address to;
        bytes transaction;
        IDecryptionContractInceptionCallback callback;
    }

    struct GeneratedKeyMaterial {
        bool available;
        bytes encryptedSuccess;
        bytes hashedSuccess;
        bytes encryptedFailure;
        bytes hashedFailure;
    }

    IDecryptionContractWithKeyGeneration public immutable generatedKeyPaymentContract;
    address public immutable expectedSeller;
    address public immutable expectedBuyer;
    address public immutable sellerOperator;
    address public immutable buyerOperator;
    mapping(uint256 => Lock) private locks;

    error ZeroAddress();
    error InvalidId();
    error InvalidState(State expected, State actual);
    error InvalidParticipant();
    error InvalidTransferContext();
    error UnauthorizedOperator();
    error InvalidKeyMaterial();
    error InvalidKeyGenerationMode();
    error InvalidCallbackContext();

    constructor(
        IDecryptionContractWithKeyGeneration generatedKeyPaymentContract_,
        address seller_,
        address buyer_,
        address sellerOperator_,
        address buyerOperator_
    ) {
        if (
            address(generatedKeyPaymentContract_) == address(0)
                || seller_ == address(0)
                || buyer_ == address(0)
                || sellerOperator_ == address(0)
                || buyerOperator_ == address(0)
        ) revert ZeroAddress();
        if (seller_ == buyer_) revert InvalidParticipant();
        generatedKeyPaymentContract = generatedKeyPaymentContract_;
        expectedSeller = seller_;
        expectedBuyer = buyer_;
        sellerOperator = sellerOperator_;
        buyerOperator = buyerOperator_;
    }

    modifier onlySellerOperator() {
        if (msg.sender != sellerOperator) revert UnauthorizedOperator();
        _;
    }

    modifier onlyBuyerOperator() {
        if (msg.sender != buyerOperator) revert UnauthorizedOperator();
        _;
    }

    /** @notice Buyer incepts the asset lock with the Pontes cancellation material. */
    function inceptTransfer(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyHashedSeller,
        bytes memory keyEncryptedSeller
    ) external override onlyBuyerOperator {
        if (id == 0) revert InvalidId();
        if (
            from != expectedSeller
                || to != expectedBuyer
                || amount <= 0
                || transaction.length == 0
        ) revert InvalidParticipant();
        if (locks[id].state != State.None) revert InvalidState(State.None, locks[id].state);
        if (keyHashedSeller.length != 32 || keyEncryptedSeller.length == 0) revert InvalidKeyMaterial();

        Lock storage lock = locks[id];
        lock.seller = from;
        lock.buyer = to;
        lock.amount = amount;
        lock.transaction = transaction;
        lock.cancellationHash = bytes32(keyHashedSeller);
        lock.encryptedCancellationKey = keyEncryptedSeller;
        lock.generatedKeys = false;
        lock.state = State.Incepted;
        emit TransferIncepted(
            id,
            amount,
            from,
            to,
            transaction,
            keyHashedSeller,
            keyEncryptedSeller
        );
    }

    /** @notice Buyer incepts an asset lock whose keys will be generated by Payment. */
    function inceptTransfer(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractWithKeyGeneration decryptionContract
    ) external override onlyBuyerOperator {
        if (id == 0) revert InvalidId();
        if (
            from != expectedSeller
                || to != expectedBuyer
                || amount <= 0
                || transaction.length == 0
                || address(decryptionContract) != address(generatedKeyPaymentContract)
        ) revert InvalidParticipant();
        if (locks[id].state != State.None) revert InvalidState(State.None, locks[id].state);

        Lock storage lock = locks[id];
        lock.seller = from;
        lock.buyer = to;
        lock.amount = amount;
        lock.transaction = transaction;
        lock.paymentContract = address(decryptionContract);
        lock.generatedKeys = true;
        lock.state = State.Incepted;
        emit TransferInceptedWithKeyGeneration(
            id,
            amount,
            from,
            to,
            transaction,
            decryptionContract
        );
    }

    /** @notice Seller confirms and locks the asset with the Pontes execution material. */
    function confirmTransfer(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyHashedBuyer,
        bytes memory keyEncryptedBuyer
    ) external override onlySellerOperator {
        Lock storage lock = locks[id];
        if (lock.state != State.Incepted) revert InvalidState(State.Incepted, lock.state);
        if (lock.generatedKeys) revert InvalidKeyGenerationMode();
        if (
            from != lock.seller
                || to != lock.buyer
                || amount != lock.amount
                || keccak256(transaction) != keccak256(lock.transaction)
        ) revert InvalidTransferContext();
        if (keyHashedBuyer.length != 32 || keyEncryptedBuyer.length == 0) revert InvalidKeyMaterial();

        bytes32 executionHash = bytes32(keyHashedBuyer);
        if (
            executionHash == lock.cancellationHash
                || keccak256(keyEncryptedBuyer) == keccak256(lock.encryptedCancellationKey)
        ) revert InvalidKeyMaterial();

        lock.executionHash = executionHash;
        lock.encryptedExecutionKey = keyEncryptedBuyer;
        lock.state = State.Locked;
        emit TransferConfirmed(
            id,
            amount,
            lock.seller,
            lock.buyer,
            lock.transaction,
            keyHashedBuyer,
            keyEncryptedBuyer
        );
        emit TokenLocked(id);
    }

    /**
     * @notice Completes a generated-key lock without relying on caller identity.
     * @dev All authority is loaded from the pending lock and its trusted Payment contract.
     */
    function completeLock(uint256 id) external override {
        _completeLock(id);
    }

    function onInceptionCompleted(uint256 id) external override returns (bytes4 acknowledgement) {
        Lock storage lock = locks[id];
        if (!lock.generatedKeys) revert InvalidKeyGenerationMode();
        if (msg.sender != lock.paymentContract) revert InvalidCallbackContext();

        _completeLock(id);
        return IDecryptionContractInceptionCallback.onInceptionCompleted.selector;
    }

    /**
     * @notice Applies a public Pontes outcome key to the locked asset state.
     * @dev Knowledge of the publicly released key is the authorization. The payment contract
     *      verifies the payment references before releasing the execution key. Anyone may relay
     *      a key: the terminal destination is fixed in storage, so a keeper cannot redirect value.
     */
    function transferWithKey(uint256 id, bytes memory key) external override {
        Lock storage lock = locks[id];
        if (lock.state != State.Locked) revert InvalidState(State.Locked, lock.state);
        bytes32 keyHash = sha256(key);

        if (keyHash == lock.executionHash) {
            lock.state = State.Claimed;
            emit TokenClaimed(id, key);
            return;
        }

        if (keyHash == lock.cancellationHash) {
            lock.state = State.Reclaimed;
            emit TokenReclaimed(id, key);
            return;
        }

        revert InvalidKeyMaterial();
    }

    /** @notice Cancels an asset inception before the seller has locked an asset. */
    function cancelTransfer(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyHashedSeller,
        bytes memory keyEncryptedSeller
    ) external override onlyBuyerOperator {
        Lock storage lock = locks[id];
        if (lock.state != State.Incepted) revert InvalidState(State.Incepted, lock.state);
        if (lock.generatedKeys) revert InvalidKeyGenerationMode();
        if (
            amount != lock.amount
                || from != lock.seller
                || to != lock.buyer
                || keccak256(transaction) != keccak256(lock.transaction)
                || keyHashedSeller.length != 32
                || bytes32(keyHashedSeller) != lock.cancellationHash
                || keccak256(keyEncryptedSeller) != keccak256(lock.encryptedCancellationKey)
        ) {
            revert InvalidParticipant();
        }
        lock.state = State.Reclaimed;
        emit TokenReclaimed(id, bytes(""));
    }

    /** @notice Cancels a generated-key inception before the asset has been locked. */
    function cancelTransfer(uint256 id) external override onlyBuyerOperator {
        Lock storage lock = locks[id];
        if (lock.state != State.Incepted) revert InvalidState(State.Incepted, lock.state);
        if (!lock.generatedKeys) revert InvalidKeyGenerationMode();
        // Keep the context as a tombstone so a delayed authenticated callback can be acknowledged.
        lock.state = State.Reclaimed;
        emit TokenReclaimed(id, bytes(""));
    }

    function stateOf(uint256 id) external view returns (State) {
        return locks[id].state;
    }

    function partiesOf(uint256 id) external view returns (address seller, address buyer) {
        Lock storage lock = locks[id];
        return (lock.seller, lock.buyer);
    }

    function hashesOf(uint256 id) external view returns (bytes32 executionHash, bytes32 cancellationHash) {
        Lock storage lock = locks[id];
        return (lock.executionHash, lock.cancellationHash);
    }

    function generatedKeyCompletionOf(
        uint256 id
    ) external view returns (bool completionRecorded, bool generatedKeys) {
        Lock storage lock = locks[id];
        return (lock.generatedKeyCompletionRecorded, lock.generatedKeys);
    }

    function _completeLock(uint256 id) internal {
        Lock storage lock = locks[id];
        if (!lock.generatedKeys) revert InvalidKeyGenerationMode();

        if (lock.generatedKeyCompletionRecorded) return;
        if (lock.state != State.Incepted && lock.state != State.Reclaimed) {
            revert InvalidState(State.Incepted, lock.state);
        }

        IDecryptionContractWithKeyGeneration payment =
            IDecryptionContractWithKeyGeneration(lock.paymentContract);
        PaymentInceptionContext memory context = _getPaymentContext(payment, id);
        _validatePaymentContext(lock, context);

        GeneratedKeyMaterial memory material = _getPaymentKeyMaterial(payment, id);
        if (!material.available) revert InvalidKeyMaterial();
        if (
            material.encryptedSuccess.length == 0
                || material.encryptedFailure.length == 0
                || material.hashedSuccess.length != 32
                || material.hashedFailure.length != 32
                || bytes32(material.hashedSuccess) == bytes32(material.hashedFailure)
                || keccak256(material.encryptedSuccess) == keccak256(material.encryptedFailure)
        ) revert InvalidKeyMaterial();

        lock.generatedKeyCompletionRecorded = true;

        // A buyer may have cancelled while asynchronous key generation was pending.
        // Retain the authenticated completion as a tombstone but never re-open or lock it.
        if (lock.state == State.Reclaimed) return;

        lock.executionHash = bytes32(material.hashedSuccess);
        lock.cancellationHash = bytes32(material.hashedFailure);
        lock.state = State.Locked;
        emit TransferConfirmed(
            id,
            lock.amount,
            lock.seller,
            lock.buyer,
            lock.transaction,
            material.hashedSuccess,
            material.encryptedSuccess
        );
        emit TokenLocked(id);
    }

    function _getPaymentContext(
        IDecryptionContractWithKeyGeneration payment,
        uint256 id
    ) internal view returns (PaymentInceptionContext memory context) {
        (
            context.exists,
            context.amount,
            context.from,
            context.to,
            context.transaction,
            context.callback
        ) = payment.getInceptionContext(id);
    }

    function _validatePaymentContext(
        Lock storage lock,
        PaymentInceptionContext memory context
    ) internal view {
        if (
            !context.exists
                || context.from != lock.buyer
                || context.to != lock.seller
                || keccak256(context.transaction) != keccak256(lock.transaction)
                || address(context.callback) != address(this)
        ) revert InvalidCallbackContext();
    }

    function _getPaymentKeyMaterial(
        IDecryptionContractWithKeyGeneration payment,
        uint256 id
    ) internal view returns (GeneratedKeyMaterial memory material) {
        (
            material.available,
            material.encryptedSuccess,
            material.hashedSuccess,
            material.encryptedFailure,
            material.hashedFailure
        ) = payment.getInceptionKeyMaterial(id);
    }

}
