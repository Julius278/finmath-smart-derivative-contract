// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDecryptionContractInceptionCallback} from "@finmath.net/dvp/contracts/IDecryptionContractInceptionCallback.sol";
import {IDemoKeyRecipient, IDemoAssetPaymentContext} from "./DemoInterfaces.sol";

/// @notice Local cash-token settlement with operator-supplied outcome hashes.
/// @dev Implements only the generated-key APIs needed by this example. The operator is
///      trusted to keep both preimages secret until settlement; no encryption is implemented.
///      Payers approve each payment and ERC-20 allowance separately. Cancellation moves no cash.
contract DemoPayment is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    enum Status { Unknown, Pending, Ready, Paid, Cancelled }
    struct Payment {
        int256 amount;
        address payer;
        address payee;
        bytes transaction;
        IDecryptionContractInceptionCallback callback;
        bytes32 successHash;
        bytes32 failureHash;
        bool approved;
        Status status;
    }
    IERC20 public immutable cashToken;
    uint256 public oracleConfigurationVersion;
    mapping(address => bool) public authorizedProducts;
    mapping(uint256 => Payment) private _payments;
    error DemoPaymentError();
    event PaymentIncepted(uint256 indexed id, address payer, address payee, uint256 amount);
    event PaymentCompleted(uint256 indexed id, bool success, bytes key);

    constructor(address owner_, address cashToken_) {
        require(owner_ != address(0) && cashToken_.code.length != 0, "configuration required");
        _transferOwnership(owner_);
        cashToken = IERC20(cashToken_);
    }

    function setProductAuthorized(address product, bool allowed) external onlyOwner {
        require(product.code.length != 0, "product required");
        authorizedProducts[product] = allowed;
    }

    function oracleOf(address) external view returns (address) { return owner(); }

    function _transferOwnership(address nextOwner) internal override {
        super._transferOwnership(nextOwner);
        ++oracleConfigurationVersion;
    }

    function inceptTransfer(uint256 id, int256 amount, address from, address to,
        bytes memory transaction, IDecryptionContractInceptionCallback callback) external nonReentrant
    {
        if (id == 0 || _payments[id].status != Status.Unknown || amount <= 0 || from == address(0)
            || to == address(0) || from == to || transaction.length == 0
            || !authorizedProducts[address(callback)]
            || (msg.sender != address(callback) && msg.sender != from && msg.sender != to)) revert DemoPaymentError();
        if (msg.sender != address(callback)) {
            // Participants may request only the exact asset attempt already opened by the
            // buyer. This prevents reserving a future coupon/settlement id with bogus data.
            IDemoAssetPaymentContext asset = IDemoAssetPaymentContext(address(callback));
            (address payer, address payee, uint256 expectedAmount) = asset.dvpPaymentContext();
            if (asset.settlementId() != id || asset.lockState() != 1 || from != payer || to != payee
                || uint256(amount) != expectedAmount
                || keccak256(abi.encode(id, transaction)) != asset.settlementContext()) revert DemoPaymentError();
        }
        _payments[id] = Payment(amount, from, to, transaction, callback, 0, 0, msg.sender == from, Status.Pending);
        emit PaymentIncepted(id, from, to, uint256(amount));
    }

    /// @notice Commit two private, distinct preimages, then let the bond authenticate its lock.
    function completeInception(uint256 id, bytes32 successHash, bytes32 failureHash) external onlyOwner nonReentrant {
        Payment storage payment = _payments[id];
        if (payment.status != Status.Pending || successHash == bytes32(0)
            || failureHash == bytes32(0) || successHash == failureHash) revert DemoPaymentError();
        payment.successHash = successHash;
        payment.failureHash = failureHash;
        payment.status = Status.Ready;
        if (payment.callback.onInceptionCompleted(id)
            != IDecryptionContractInceptionCallback.onInceptionCompleted.selector) revert DemoPaymentError();
    }

    function approvePayment(uint256 id) external {
        Payment storage payment = _payments[id];
        if (msg.sender != payment.payer || (payment.status != Status.Pending && payment.status != Status.Ready)) {
            revert DemoPaymentError();
        }
        payment.approved = true;
    }

    function settle(uint256 id, bool success, bytes calldata key) external onlyOwner nonReentrant {
        Payment storage payment = _payments[id];
        if (payment.status != Status.Ready || sha256(key) != (success ? payment.successHash : payment.failureHash)
            || (success && !payment.approved)) revert DemoPaymentError();
        payment.status = success ? Status.Paid : Status.Cancelled;
        if (success) cashToken.safeTransferFrom(payment.payer, payment.payee, uint256(payment.amount));
        IDemoKeyRecipient(address(payment.callback)).transferWithKey(id, key);
        emit PaymentCompleted(id, success, key);
    }

    function paymentStatus(uint256 id) external view returns (Status) { return _payments[id].status; }

    function getInceptionContext(uint256 id) external view returns (bool exists, int256 amount,
        address from, address to, bytes memory transaction, IDecryptionContractInceptionCallback callback)
    {
        Payment storage payment = _payments[id];
        return (payment.status != Status.Unknown, payment.amount, payment.payer, payment.payee,
            payment.transaction, payment.callback);
    }

    function getInceptionKeyMaterial(uint256 id) external view returns (bool available,
        bytes memory encryptedSuccess, bytes memory hashedSuccess, bytes memory encryptedFailure, bytes memory hashedFailure)
    {
        Payment storage payment = _payments[id];
        return (payment.status >= Status.Ready, "", abi.encode(payment.successHash), "", abi.encode(payment.failureHash));
    }
}
