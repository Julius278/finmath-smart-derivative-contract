// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILockingContractWithKeyGeneration} from "@finmath.net/dvp/contracts/ILockingContractWithKeyGeneration.sol";
import {IDecryptionContractWithKeyGeneration} from "@finmath.net/dvp/contracts/IDecryptionContractWithKeyGeneration.sol";
import {IDecryptionContractInceptionCallback} from "@finmath.net/dvp/contracts/IDecryptionContractInceptionCallback.sol";

/// @notice Small local ERC-20 escrow for the bond example's generated-key flow.
/// @dev Fresh demo implementation. The configured payment operator is trusted to release
///      exactly one outcome secret. No cross-chain finality or encryption is modeled.
abstract contract DemoAssetLocking is ILockingContractWithKeyGeneration {
    using SafeERC20 for IERC20;

    enum LockState { None, Incepted, Locked, Claimed, Reclaimed, Cancelled }
    uint256 public settlementId;
    LockState public lockState;
    address internal _lockBeneficiary;
    address private _source;
    address private _token;
    uint256 private _units;
    uint96 private _nextAttempt = 1;
    bytes32 private _transactionHash;
    bytes32 private _success;
    bytes32 private _failure;
    mapping(uint256 => bool) private _known;
    mapping(uint256 => bool) private _cancelled;
    bool private _entered;

    error DemoLockError();
    error UnsupportedFlow();
    event AssetInceptionCancelled(uint256 indexed id, address indexed sender);

    modifier escrowGuard() {
        if (_entered) revert DemoLockError();
        _entered = true;
        _;
        _entered = false;
    }

    function currentTransferId() public view returns (uint256) {
        return _isSettlementActive() ? settlementId : (uint256(uint160(address(this))) << 96) | _nextAttempt;
    }

    function _isSettlementActive() internal view returns (bool) {
        return lockState == LockState.Incepted || lockState == LockState.Locked;
    }

    function inceptTransfer(uint256 id, int256 amount, address from, address to,
        bytes memory transaction, IDecryptionContractWithKeyGeneration payment) external override escrowGuard
    {
        _requireDvpReady();
        if (msg.sender != _dvpBuyer() || _isSettlementActive() || id != currentTransferId()
            || from != _dvpSeller() || to != _dvpBuyer() || amount <= 0
            || uint256(amount) != _dvpAssetAmount() || transaction.length == 0
            || address(payment) != _dvpPaymentContract()) revert DemoLockError();
        ++_nextAttempt;
        settlementId = id;
        _known[id] = true;
        lockState = LockState.Incepted;
        _transactionHash = keccak256(abi.encode(id, transaction));
        _success = bytes32(0);
        _failure = bytes32(0);
        _touchState();
        emit TransferInceptedWithKeyGeneration(id, amount, from, to, transaction, payment);
    }

    function cancelTransfer(uint256 id) external override escrowGuard {
        if ((msg.sender != _dvpSeller() && msg.sender != _dvpBuyer())
            || id != settlementId || lockState != LockState.Incepted) revert DemoLockError();
        lockState = LockState.Cancelled;
        _cancelled[id] = true;
        _touchState();
        emit AssetInceptionCancelled(id, msg.sender);
    }

    function completeLock(uint256 id) external override { _complete(id); }

    function onInceptionCompleted(uint256 id) public virtual override returns (bytes4) {
        if (msg.sender != _dvpPaymentContract() || !_known[id]) revert DemoLockError();
        if (id == settlementId && lockState == LockState.Incepted) _complete(id);
        return IDecryptionContractInceptionCallback.onInceptionCompleted.selector;
    }

    function _complete(uint256 id) private escrowGuard {
        if (id != settlementId) revert DemoLockError();
        if (lockState == LockState.Locked) return;
        if (lockState != LockState.Incepted) revert DemoLockError();
        _requireDvpReady();
        IDecryptionContractWithKeyGeneration payment = IDecryptionContractWithKeyGeneration(_dvpPaymentContract());
        {
            (bool exists, int256 amount, address payer, address payee, bytes memory transaction,
                IDecryptionContractInceptionCallback callback) = payment.getInceptionContext(id);
            if (!exists || amount <= 0 || uint256(amount) != _dvpPaymentAmount()
                || payer != _dvpBuyer() || payee != _dvpSeller() || address(callback) != address(this)
                || keccak256(abi.encode(id, transaction)) != _transactionHash) revert DemoLockError();
        }
        (bool available, , bytes memory success, , bytes memory failure) = payment.getInceptionKeyMaterial(id);
        if (!available || success.length != 32 || failure.length != 32) revert DemoLockError();
        _success = abi.decode(success, (bytes32));
        _failure = abi.decode(failure, (bytes32));
        if (_success == bytes32(0) || _failure == bytes32(0) || _success == _failure) revert DemoLockError();
        _source = _dvpSeller();
        _lockBeneficiary = _dvpBuyer();
        _token = _dvpAssetToken();
        _units = _dvpAssetAmount();
        if (_source == address(0) || _lockBeneficiary == address(0) || _source == _lockBeneficiary
            || _token.code.length == 0 || _units == 0) revert DemoLockError();
        lockState = LockState.Locked;
        uint256 beforeBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(_source, address(this), _units);
        if (IERC20(_token).balanceOf(address(this)) != beforeBalance + _units) revert DemoLockError();
        _touchState();
        emit TokenLocked(id);
    }

    function transferWithKey(uint256 id, bytes memory key) public virtual override escrowGuard {
        // Outcome keys are visible in pending settlement transactions. Requiring the cash
        // adapter prevents a third party releasing the asset before that transaction pays.
        if (msg.sender != _dvpPaymentContract()) revert DemoLockError();
        // The payment demo may finish a cancelled attempt without a token movement.
        // Only the trusted payment adapter can acknowledge that otherwise unused failure key.
        if (_cancelled[id] && msg.sender == _dvpPaymentContract()) {
            (bool available, , , , bytes memory failure) =
                IDecryptionContractWithKeyGeneration(msg.sender).getInceptionKeyMaterial(id);
            if (!available || failure.length != 32 || sha256(key) != abi.decode(failure, (bytes32))) {
                revert DemoLockError();
            }
            return;
        }
        if (id != settlementId || lockState != LockState.Locked) revert DemoLockError();
        bytes32 digest = sha256(key);
        bool success = digest == _success;
        if (!success && digest != _failure) revert DemoLockError();
        lockState = success ? LockState.Claimed : LockState.Reclaimed;
        IERC20(_token).safeTransfer(success ? _lockBeneficiary : _source, _units);
        _touchState();
        if (success) {
            emit TokenClaimed(id, key);
            _onAssetClaimed();
        } else {
            emit TokenReclaimed(id, key);
            _onAssetReclaimed();
        }
    }

    function dvpPaymentContext() external view returns (address payer, address payee, uint256 amount) {
        return (_dvpBuyer(), _dvpSeller(), _dvpPaymentAmount());
    }
    function settlementContext() external view returns (bytes32) { return _transactionHash; }

    // The example intentionally supports only the generated-key overload.
    function inceptTransfer(uint256, int256, address, address, bytes memory, bytes memory, bytes memory)
        external pure override { revert UnsupportedFlow(); }
    function confirmTransfer(uint256, int256, address, address, bytes memory, bytes memory, bytes memory)
        external pure override { revert UnsupportedFlow(); }
    function cancelTransfer(uint256, int256, address, address, bytes memory, bytes memory, bytes memory)
        external pure override { revert UnsupportedFlow(); }

    function _dvpSeller() internal view virtual returns (address);
    function _dvpBuyer() internal view virtual returns (address);
    function _dvpAssetAmount() internal view virtual returns (uint256);
    function _dvpAssetToken() internal view virtual returns (address);
    function _dvpPaymentAmount() internal view virtual returns (uint256);
    function _dvpPaymentContract() internal view virtual returns (address);
    function _requireDvpReady() internal view virtual;
    function _touchState() internal virtual;
    function _onAssetClaimed() internal virtual;
    function _onAssetReclaimed() internal virtual;
}
