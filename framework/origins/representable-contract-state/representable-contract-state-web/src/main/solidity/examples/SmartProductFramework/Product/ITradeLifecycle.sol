// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ITradeLifecycle
 * @notice Generic trade inception/confirmation lifecycle for deployed products,
 *         inspired by ERC-6123 (ISDCTrade) but adapted to a deployment-driven
 *         model.
 *
 * @dev LIFECYCLE
 *      Requested -> Incepted -> Active
 *                \-> Cancelled  (from Requested or Incepted)
 *
 *      Requested: the product exists, no counterparty is bound yet. The product
 *                 provider may still amend the negotiable terms.
 *      Incepted:  the product provider accepted the terms and bound a specific
 *                 client as counterparty. Terms are frozen from here on.
 *      Active:    the bound client confirmed the frozen terms; the trade is live.
 *      Cancelled: terminal, reached before activation by either party.
 *
 * @dev PARTIES
 *      The product provider is fixed at deployment (see IProduct.productProvider).
 *      The client is NOT known at deployment time: a product may be issued without
 *      any preceding trade request. The counterparty is therefore bound during
 *      inceptTrade() and is immutable afterwards.
 *
 * @dev TERMS AGREEMENT
 *      Both parties commit to the same fingerprint: the product provider passes
 *      the currently rendered currentTermsHash() into inceptTrade(), the client
 *      passes the identical value into confirmTrade(). Any divergence reverts
 *      with AgreedTermsMismatch, so neither party can be bound to terms it did
 *      not explicitly see.
 *
 * @author Raphael Prandtl
 */
interface ITradeLifecycle {
    // ------------------------------ Enums ------------------------------ */

    /**
     * @notice Lifecycle status of a trade.
     * @dev Requested: created, no client bound, terms amendable by the product provider.
     *      Incepted:  product provider accepted and bound a client; terms frozen;
     *                 awaiting client confirmation.
     *      Active:    client confirmed; trade live.
     *      Cancelled: terminated pre-activation by either party (terminal).
     */
    enum TradeStatus {
        Requested,
        Incepted,
        Active,
        Cancelled
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the caller is not the product provider.
    error NotProductProvider(address caller);

    /// @notice Thrown when the caller is not the bound client.
    /// @dev Also thrown for every caller while no client is bound (status Requested).
    error NotClient(address caller);

    /// @notice Thrown when the caller is neither the bound client nor the product provider.
    error NotTradeParty(address caller);

    /// @notice Thrown when the action is not allowed in the current status.
    error InvalidTradeStatus(TradeStatus current);

    /// @notice Thrown when the supplied agreed terms hash does not match.
    /// @param expected The hash the contract requires.
    /// @param actual   The hash supplied by the caller.
    error AgreedTermsMismatch(bytes32 expected, bytes32 actual);

    /// @notice Thrown when the counterparty supplied at inception is invalid.
    /// @dev Zero address or the product provider itself (self-dealing).
    error InvalidCounterparty(address party);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when the negotiable terms are amended before inception.
    event TermsUpdated(address indexed sender, bytes32 newTermsHash);

    /// @notice Emitted when the product provider incepts the trade and binds the client.
    event TradeIncepted(address indexed productProvider, address indexed client, bytes32 agreedTermsHash);

    /// @notice Emitted when the bound client confirms the incepted trade.
    event TradeConfirmed(address indexed confirmer, bytes32 agreedTermsHash);

    /// @notice Emitted when the trade becomes active.
    event TradeActivated();

    /// @notice Emitted when the trade is cancelled before activation.
    event TradeCanceled(address indexed initiator);

    /// @notice Emitted on every status change (uniform tracking stream).
    event TradeStatusChanged(TradeStatus oldStatus, TradeStatus newStatus);

    // ------------------------------ Trade Lifecycle ------------------------------ */

    /**
     * @notice Replaces the negotiable product terms.
     * @dev Only callable by the product provider and only while Requested, i.e.
     *      before any counterparty is bound and before the terms are frozen.
     *      A client's trade request payload is a non-binding indication of
     *      interest; the binding terms are set here by the product provider.
     * @param productPayload ABI-encoded, product-specific terms (full replacement).
     */
    function updateTerms(bytes calldata productPayload) external;

    /**
     * @notice Product provider accepts the current terms and binds the counterparty.
     * @dev Requested -> Incepted. Freezes the terms via agreedTermsHash().
     *      Reverts if withParty is the zero address or the product provider itself,
     *      or if agreedTermsHash does not equal currentTermsHash().
     * @param withParty       The client this trade is concluded with.
     * @param agreedTermsHash The terms fingerprint the product provider accepts.
     */
    function inceptTrade(address withParty, bytes32 agreedTermsHash) external;

    /**
     * @notice Bound client confirms the incepted terms, activating the trade.
     * @dev Incepted -> Active. Only callable by the client bound in inceptTrade().
     * @param agreedTermsHash The frozen terms fingerprint the client confirms.
     */
    function confirmTrade(bytes32 agreedTermsHash) external;

    /**
     * @notice Cancels the trade before activation.
     * @dev Allowed in Requested or Incepted; sets Cancelled (terminal).
     *      While Requested no client is bound, so only the product provider can cancel.
     */
    function cancelTrade() external;

    // ------------------------------ Views ------------------------------ */

    /// @notice Returns the current trade status.
    function tradeStatus() external view returns (TradeStatus);

    /**
     * @notice Returns the counterparty bound at inception.
     * @return The client address, or address(0) while the trade is Requested.
     */
    function client() external view returns (address);

    /**
     * @notice Returns the current product terms fingerprint.
     * @dev Derived from the concrete product's live economics. Changes with every
     *      updateTerms() call; stable once the trade is Incepted.
     */
    function currentTermsHash() external view returns (bytes32);

    /// @notice Returns the terms hash frozen at inception (0 before inception).
    function agreedTermsHash() external view returns (bytes32);
}
