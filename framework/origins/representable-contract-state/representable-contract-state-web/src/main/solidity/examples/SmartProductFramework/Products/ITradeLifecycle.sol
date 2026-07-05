// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITradeLifecycle
/// @notice Generic trade inception/confirmation lifecycle for deployed products,
///         inspired by ERC-6123 (ISDCTrade) but adapted to a deployment-driven
///         model: the investor's request deploys the product (status Requested),
///         the issuer accepts (inceptTrade), and the investor confirms
///         (confirmTrade) to activate.
///
/// @dev PARTIES
///      issuer and investor are fixed at deployment (see IProduct); they are not
///      passed as arguments here (unlike ERC-6123's withParty).
///
/// @dev TERMS AGREEMENT
///      Both parties commit to agreedTermsHash == the product's current terms
///      fingerprint at inception. Terms are frozen once Incepted.
///
/// @author Raphael Prandtl
interface ITradeLifecycle {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Lifecycle status of a trade.
    /// @dev Requested: created, terms amendable by investor.
    ///      Incepted:  issuer accepted; terms frozen; awaiting investor confirm.
    ///      Active:    investor confirmed; trade live.
    ///      Cancelled: terminated pre-activation by either party.
    enum TradeStatus {
        Requested,
        Incepted,
        Active,
        Cancelled
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when the caller is not the issuer.
    error NotIssuer(address caller);

    /// @notice Thrown when the caller is not the investor.
    error NotInvestor(address caller);

    /// @notice Thrown when the caller is not the investor or the issuer.
    error NotTradeParty(address caller);

    /// @notice Thrown when the action is not allowed in the current status.
    error InvalidTradeStatus(TradeStatus current);

    /// @notice Thrown when the supplied agreed terms hash does not match.
    error AgreedTermsMismatch(bytes32 expected, bytes32 actual);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when the investor amends the requested terms.
    event TermsUpdated(address indexed investor, bytes32 newTermsHash);

    /// @notice Emitted when the issuer incepts (accepts) the trade.
    event TradeIncepted(address indexed initiator, bytes32 agreedTermsHash);

    /// @notice Emitted when the investor confirms the incepted trade.
    event TradeConfirmed(address indexed confirmer, bytes32 agreedTermsHash);

    /// @notice Emitted when the trade becomes active.
    event TradeActivated();

    /// @notice Emitted when the trade is cancelled before activation.
    event TradeCanceled(address indexed initiator);

    /// @notice Emitted on every status change (uniform tracking stream).
    event TradeStatusChanged(TradeStatus oldStatus, TradeStatus newStatus);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       TRADE LIFECYCLE                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Amends the requested trade terms (investor only, Requested only).
    /// @param productSpecificPayload Full replacement terms, same schema as
    ///        deployment; decoded and validated by the concrete product.
    function updateTerms(bytes calldata productSpecificPayload) external;

    /// @notice Issuer accepts the current terms, freezing them.
    /// @dev Requires agreedTermsHash == currentTermsHash(); Requested -> Incepted.
    /// @param agreedTermsHash The terms fingerprint the issuer accepts.
    function inceptTrade(bytes32 agreedTermsHash) external;

    /// @notice Investor confirms the incepted terms, activating the trade.
    /// @dev Requires agreedTermsHash == the incepted hash; Incepted -> Active.
    /// @param agreedTermsHash The terms fingerprint the investor confirms.
    function confirmTrade(bytes32 agreedTermsHash) external;

    /// @notice Cancels the trade before activation (issuer or investor).
    /// @dev Allowed in Requested or Incepted; sets Cancelled (terminal).
    function cancelTrade() external;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          VIEWS                            */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the current trade status.
    function tradeStatus() external view returns (TradeStatus);

    /// @notice Returns the current product terms fingerprint.
    /// @dev Equals the concrete product's terms hash over its live economics.
    function currentTermsHash() external view returns (bytes32);

    /// @notice Returns the agreed terms hash fixed at inception (0 before).
    function agreedTermsHash() external view returns (bytes32);
}
