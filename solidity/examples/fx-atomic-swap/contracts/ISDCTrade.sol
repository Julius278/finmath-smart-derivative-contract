// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title ERC-6123 Smart Derivative Contract — trade interface
 * @notice Trade-inception, confirmation, cancellation, and termination surface
 *         used by FxAtomicSwap.
 */
interface ISDCTrade {
    event TradeIncepted(
        address initiator,
        address withParty,
        string tradeId,
        string tradeData,
        int256 position,
        int256 paymentAmount,
        string initialSettlementData
    );

    event TradeConfirmed(address confirmer, string tradeId);
    event TradeCanceled(address initiator, string tradeId);
    event TradeActivated(string tradeId);
    event TradeTerminated(string tradeId, string cause);
    event TradeTerminationRequest(
        address initiator,
        string tradeId,
        int256 terminationPayment,
        string terminationTerms
    );
    event TradeTerminationConfirmed(
        address confirmer,
        string tradeId,
        int256 terminationPayment,
        string terminationTerms
    );
    event TradeTerminationCanceled(
        address initiator,
        string tradeId,
        string terminationTerms
    );

    function inceptTrade(
        address withParty,
        string memory tradeData,
        int256 position,
        int256 paymentAmount,
        string memory initialSettlementData
    ) external returns (string memory);

    function confirmTrade(
        address withParty,
        string memory tradeData,
        int256 position,
        int256 paymentAmount,
        string memory initialSettlementData
    ) external;

    function cancelTrade(
        address withParty,
        string memory tradeData,
        int256 position,
        int256 paymentAmount,
        string memory initialSettlementData
    ) external;

    function requestTradeTermination(
        string memory tradeId,
        int256 terminationPayment,
        string memory terminationTerms
    ) external;

    function confirmTradeTermination(
        string memory tradeId,
        int256 terminationPayment,
        string memory terminationTerms
    ) external;

    function cancelTradeTermination(
        string memory tradeId,
        int256 terminationPayment,
        string memory terminationTerms
    ) external;
}
