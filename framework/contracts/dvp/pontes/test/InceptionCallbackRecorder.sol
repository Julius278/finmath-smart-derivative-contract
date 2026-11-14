// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDecryptionContractInceptionCallback} from "@finmath.net/dvp/contracts/IDecryptionContractInceptionCallback.sol";
import {IDecryptionContractWithKeyGeneration} from "@finmath.net/dvp/contracts/IDecryptionContractWithKeyGeneration.sol";

/**
 * @dev Test-only callback that models the authentication and pending-inception
 * checks required of an on-chain settlement consumer.
 */
contract InceptionCallbackRecorder is IDecryptionContractInceptionCallback {
    address public immutable expectedPaymentContract;
    address public immutable owner;

    uint256 public expectedId;
    int256 public expectedAmount;
    address public expectedFrom;
    address public expectedTo;
    bytes public expectedTransaction;
    bool public pending;
    bool public acknowledge = true;

    uint256 public completions;
    bytes public lastKeyEncryptedSuccess;
    bytes public lastKeyHashedSuccess;
    bytes public lastKeyEncryptedFailure;
    bytes public lastKeyHashedFailure;

    event InceptionCompletionRecorded(
        address indexed paymentContract,
        uint256 indexed id,
        bytes keyEncryptedSuccess,
        bytes keyHashedSuccess,
        bytes keyEncryptedFailure,
        bytes keyHashedFailure
    );

    error UnexpectedPaymentContract();
    error UnexpectedInception();
    error InvalidInceptionContext();
    error InvalidKeyMaterial();
    error NotOwner();
    error ZeroAddress();

    constructor(address expectedPaymentContract_) {
        if (expectedPaymentContract_ == address(0)) revert ZeroAddress();
        expectedPaymentContract = expectedPaymentContract_;
        owner = msg.sender;
    }

    function expectInception(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes calldata transaction
    ) external {
        if (msg.sender != owner) revert NotOwner();
        expectedId = id;
        expectedAmount = amount;
        expectedFrom = from;
        expectedTo = to;
        expectedTransaction = transaction;
        pending = true;
    }

    function setAcknowledge(bool acknowledge_) external {
        if (msg.sender != owner) revert NotOwner();
        acknowledge = acknowledge_;
    }

    function onInceptionCompleted(uint256 id) external override returns (bytes4 acknowledgement) {
        if (msg.sender != expectedPaymentContract) revert UnexpectedPaymentContract();
        if (!pending || id != expectedId) {
            revert UnexpectedInception();
        }

        (
            bool exists,
            int256 amount,
            address from,
            address to,
            bytes memory transaction,
            IDecryptionContractInceptionCallback callback
        ) = IDecryptionContractWithKeyGeneration(msg.sender).getInceptionContext(id);
        if (
            !exists
                || amount != expectedAmount
                || from != expectedFrom
                || to != expectedTo
                || keccak256(transaction) != keccak256(expectedTransaction)
                || address(callback) != address(this)
        ) revert InvalidInceptionContext();

        (
            bool available,
            bytes memory keyEncryptedSuccess,
            bytes memory keyHashedSuccess,
            bytes memory keyEncryptedFailure,
            bytes memory keyHashedFailure
        ) = IDecryptionContractWithKeyGeneration(msg.sender).getInceptionKeyMaterial(id);
        if (
            !available
                || keyEncryptedSuccess.length == 0
                || keyHashedSuccess.length != 32
                || keyEncryptedFailure.length == 0
                || keyHashedFailure.length != 32
                || keccak256(keyEncryptedSuccess) == keccak256(keyEncryptedFailure)
                || keccak256(keyHashedSuccess) == keccak256(keyHashedFailure)
        ) {
            revert InvalidKeyMaterial();
        }

        pending = false;
        completions++;
        lastKeyEncryptedSuccess = keyEncryptedSuccess;
        lastKeyHashedSuccess = keyHashedSuccess;
        lastKeyEncryptedFailure = keyEncryptedFailure;
        lastKeyHashedFailure = keyHashedFailure;

        emit InceptionCompletionRecorded(
            msg.sender,
            id,
            keyEncryptedSuccess,
            keyHashedSuccess,
            keyEncryptedFailure,
            keyHashedFailure
        );

        return acknowledge
            ? IDecryptionContractInceptionCallback.onInceptionCompleted.selector
            : bytes4(0);
    }
}
