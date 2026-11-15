// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Narrow callback/payment context APIs used by the local settlement example.
interface IDemoKeyRecipient {
    function transferWithKey(uint256 id, bytes calldata key) external;
}

interface IDemoAssetPaymentContext {
    function settlementId() external view returns (uint256);
    function lockState() external view returns (uint8);
    function dvpPaymentContext() external view returns (address payer, address payee, uint256 amount);
    function settlementContext() external view returns (bytes32);
}
