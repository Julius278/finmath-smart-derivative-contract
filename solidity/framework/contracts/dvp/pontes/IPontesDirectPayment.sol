// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/** @notice Direct EUR payments without an asset exchange or ERC-7573 key flow. */
interface IPontesDirectPayment {
    /// @dev requestId must contain the eligible requester's address in its high 160 bits.
    function requestDirectPayment(
        bytes32 requestId,
        address payer,
        address payee,
        uint256 amount,
        uint8 amountScale
    ) external;

    function isDirectPaymentSettled(bytes32 requestId) external view returns (bool);
}

interface IPontesDirectPaymentCallback {
    function onDirectPaymentSettled(bytes32 requestId) external;
}
