// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Minimal ERC-20 interface used by the settlement router.
interface IERC20RouterToken {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Synchronous settlement and cancellation interface called by factory-created FX swaps.
interface IAtomicSwapSettlement {
    /// @notice Revokes the calling swap's unused settlement authorization.
    function cancelAtomicSwap() external;

    /// @notice Completes both token legs before returning, or reverts the entire settlement.
    function settleAtomicSwap(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address inceptor,
        address counterparty,
        int256 position,
        int256 paymentAmount
    ) external;
}

/**
 * @title ERC-20 Atomic Swap Settlement Router
 * @notice Common ERC-20 spender for all swaps created by one factory.
 * @dev Token holders approve this router once. The router stores only whether a
 *      factory-created swap still has an unused, uncanceled settlement authorization. The
 *      immutable swap itself is the source of its tokens, parties, and amounts.
 *      Supported tokens transfer exactly the requested amount on success.
 *      Fee-on-transfer and rebasing tokens are outside this example's scope;
 *      the router does not verify balance deltas.
 */
contract ERC20AtomicSwapSettlementRouter is IAtomicSwapSettlement {
    error InvalidFactory();
    error InvalidSwap();
    error NotFactory();
    error InactiveSwap();
    error TransferFromFailed(address token);

    address public immutable factory;
    mapping(address swap => bool active) public activeSwap;

    /**
     * @notice Creates a settlement router controlled by one immutable factory.
     * @param factory_ Factory allowed to register newly created swaps.
     */
    constructor(address factory_) {
        if (factory_ == address(0)) revert InvalidFactory();
        factory = factory_;
    }

    /**
     * @notice Gives one factory-created swap a single settlement authorization.
     * @dev The factory deploys the exact trusted swap implementation and calls this method in the same transaction.
     * @param swap Newly deployed swap contract.
     */
    function registerSwap(address swap) external {
        if (msg.sender != factory) revert NotFactory();
        if (swap.code.length == 0 || activeSwap[swap]) revert InvalidSwap();

        activeSwap[swap] = true;
    }

    /**
     * @notice Revokes the calling swap's settlement authorization without moving tokens.
     * @dev Only a registered, active swap can revoke its own authorization. The
     *      trusted swap checks the inceptor and matching terms before calling.
     *      ERC-20 allowances remain available for other swaps using this router.
     */
    function cancelAtomicSwap() external override {
        if (!activeSwap[msg.sender]) revert InactiveSwap();

        activeSwap[msg.sender] = false;
    }

    /**
     * @notice Transfers both token legs for one authorized single-use swap.
     * @dev `msg.sender` must be a swap registered by the immutable factory. Its
     *      authorization is consumed before either external token call. This is
     *      the per-swap reentrancy guard: a callback cannot reuse the same swap;
     *      independent swaps do not need a global lock. Any failure reverts both
     *      transfers and restores the authorization atomically.
     *
     *      Signed amounts are viewed from `inceptor`: positive means receive the
     *      token and negative means deliver it. The trusted swap has already
     *      validated that both legs are nonzero, opposite in sign, and not
     *      `type(int256).min`.
     * @param baseToken ERC-20 token represented by `position`.
     * @param quoteToken ERC-20 token represented by `paymentAmount`.
     * @param inceptor Party from whose perspective both amounts are signed.
     * @param counterparty Opposite fixed party.
     * @param position Signed base-token amount.
     * @param paymentAmount Signed quote-token amount.
     */
    function settleAtomicSwap(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address inceptor,
        address counterparty,
        int256 position,
        int256 paymentAmount
    ) external override {
        if (!activeSwap[msg.sender]) revert InactiveSwap();

        // Consume the authorization before calling either ERC-20 contract.
        activeSwap[msg.sender] = false;

        _move(baseToken, inceptor, counterparty, position);
        _move(quoteToken, inceptor, counterparty, paymentAmount);
    }

    /**
     * @notice Executes one signed token leg from `viewParty`'s perspective.
     * @param token ERC-20 token of the leg.
     * @param viewParty Party from whose perspective `signedAmount` is stated.
     * @param otherParty Opposite party.
     * @param signedAmount Positive to receive, negative to deliver.
     */
    function _move(
        IERC20RouterToken token,
        address viewParty,
        address otherParty,
        int256 signedAmount
    ) private {
        if (signedAmount > 0) {
            // This branch proves the value is positive and therefore representable as uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            _safeTransferFrom(token, otherParty, viewParty, uint256(signedAmount));
        } else {
            // The trusted swap rejects zero and type(int256).min, so negation is positive and safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            _safeTransferFrom(token, viewParty, otherParty, uint256(-signedAmount));
        }
    }

    /**
     * @notice Calls `transferFrom`, accepting true or no return data and rejecting false or a revert.
     * @param token ERC-20 token to call.
     * @param from Token owner that approved this router.
     * @param to Token recipient.
     * @param value Amount in the token's smallest unit.
     */
    function _safeTransferFrom(
        IERC20RouterToken token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeCall(IERC20RouterToken.transferFrom, (from, to, value))
        );

        if (!success || (data.length != 0 && (data.length < 32 || !abi.decode(data, (bool))))
        ) {
            revert TransferFromFailed(address(token));
        }
    }
}
