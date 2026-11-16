// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@finmath.net/dvp/contracts/IKeyDecryptionOracleCallback.sol";

/**
 * @dev Test callback that returns successfully after consuming almost all gas forwarded to it.
 *      It exercises the oracle's post-callback reserve instead of relying on EIP-150 headroom.
 */
contract GasBurningKeyDecryptionCallback is IKeyDecryptionOracleCallback {
    function onKeyReleased(uint256, bytes calldata) external override {
        _burnForwardedGas();
    }

    function onKeyDenied(uint256) external override {
        _burnForwardedGas();
    }

    function onEncryptedKeysVerificationCompleted(
        uint256,
        bool,
        EncryptedHashedKey[] calldata,
        address,
        bytes calldata
    ) external override {
        _burnForwardedGas();
    }

    function onEncryptedHashedKeysGenerated(
        uint256,
        EncryptedHashedKey[] calldata,
        address,
        bytes calldata
    ) external override {
        _burnForwardedGas();
    }

    function _burnForwardedGas() private view {
        // Leave just enough for the callback's return path. The caller must retain all gas
        // needed for its success event and storage cleanup before making this call.
        assembly ("memory-safe") {
            for { } gt(gas(), 5000) { } { pop(keccak256(0, 0)) }
        }
    }
}
