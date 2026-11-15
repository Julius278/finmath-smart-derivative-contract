// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IPontesDirectPayment, IPontesDirectPaymentCallback} from "../IPontesDirectPayment.sol";

interface IDirectPaymentRetry {
    function retryDirectPaymentDelivery(bytes32 requestId) external;
}

/** Test-only product for failed and reentrant settlement notifications. */
contract DirectPaymentProductStub is IPontesDirectPaymentCallback {
    address public immutable productProvider;
    address public immutable paymentContract;
    uint8 public callbackBehavior;
    uint256 public notifications;

    constructor(address paymentContract_, address provider_) {
        paymentContract = paymentContract_;
        productProvider = provider_;
    }

    function setCallbackBehavior(uint8 behavior) external { callbackBehavior = behavior; }

    function requestId(uint96 nonce) external view returns (bytes32) {
        return bytes32((uint256(uint160(address(this))) << 96) | nonce);
    }

    function request(bytes32 id, address payer, address payee, uint256 amount, uint8 scale) external {
        IPontesDirectPayment(paymentContract).requestDirectPayment(id, payer, payee, amount, scale);
    }

    function onDirectPaymentSettled(bytes32 id) external override {
        require(msg.sender == paymentContract, "payment contract only");
        require(callbackBehavior != 1, "delivery unavailable");
        notifications++;
        if (callbackBehavior == 2) {
            IDirectPaymentRetry(paymentContract).retryDirectPaymentDelivery(id);
        }
    }
}
