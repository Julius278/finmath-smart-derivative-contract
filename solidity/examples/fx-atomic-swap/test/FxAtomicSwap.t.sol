// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {FxAtomicSwap} from "../contracts/FxAtomicSwap.sol";
import {FxAtomicSwapFactory} from "../contracts/FxAtomicSwapFactory.sol";
import {ERC20TokenExample} from "../contracts/ERC20TokenExample.sol";
import {
    IERC20RouterToken,
    IAtomicSwapSettlement,
    ERC20AtomicSwapSettlementRouter
} from "../contracts/ERC20AtomicSwapSettlementRouter.sol";
import {Vm, ReturnToken, ReentrantCounterparty} from "./TestSupport.sol";

contract FxAtomicSwapTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant PARTY_A = address(0xA);
    address private constant PARTY_B = address(0xB);
    address private constant OUTSIDER = address(0xC);
    uint256 private constant INITIAL_BALANCE = 1_000;
    int256 private constant POSITION = 100;
    int256 private constant PAYMENT = -200;

    FxAtomicSwapFactory private factory;
    ERC20AtomicSwapSettlementRouter private router;
    ERC20TokenExample private base;
    ERC20TokenExample private quote;
    FxAtomicSwap private swap;

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
    event TradeTerminated(string tradeId, string cause);
    event TradeCanceled(address initiator, string tradeId);

    function setUp() public {
        factory = new FxAtomicSwapFactory();
        router = factory.settlementRouter();
        base = new ERC20TokenExample("Base", "BASE", 18);
        quote = new ERC20TokenExample("Quote", "QUOTE", 6);
        swap = _createSwap(_token(base), _token(quote), PARTY_A, PARTY_B);
        _fundAndApprove(base, PARTY_A);
        _fundAndApprove(base, PARTY_B);
        _fundAndApprove(quote, PARTY_A);
        _fundAndApprove(quote, PARTY_B);
    }

    function testFactoryRegistersFixedConfiguration() public view {
        require(router.factory() == address(factory), "router factory");
        require(router.activeSwap(address(swap)), "not registered");
        require(swap.phase() == FxAtomicSwap.Phase.Created, "phase");
        require(swap.partyA() == PARTY_A && swap.partyB() == PARTY_B, "parties");
        require(address(swap.baseToken()) == address(base), "base token");
        require(address(swap.quoteToken()) == address(quote), "quote token");
        require(address(swap.settlementRouter()) == address(router), "router");
        require(keccak256(bytes(swap.tradeId())) == keccak256("1"), "trade id");
    }

    function testInceptionStoresExactTermsAndEmitsEvent() public {
        vm.expectEmit(false, false, false, true, address(swap));
        emit TradeIncepted(PARTY_A, PARTY_B, "1", "terms", POSITION, PAYMENT, "settlement");
        _incept();
        require(swap.phase() == FxAtomicSwap.Phase.Incepted, "phase");
        require(swap.inceptor() == PARTY_A, "inceptor");
        require(swap.position() == POSITION && swap.paymentAmount() == PAYMENT, "amounts");
        require(keccak256(bytes(swap.tradeData())) == keccak256("terms"), "trade data");
        require(keccak256(bytes(swap.initialSettlementData())) == keccak256("settlement"), "data");
        _assertOriginalBalancesAndAllowances();
    }

    function testConfirmationSettlesExactlyAndEmitsTerminalEvents() public {
        _incept();
        vm.expectEmit(false, false, false, true, address(swap));
        emit TradeConfirmed(PARTY_B, "1");
        vm.expectEmit(false, false, false, true, address(swap));
        emit TradeTerminated("1", "atomic settlement completed");
        _confirm();
        _assertSettled();
    }

    function testFuzzBothInceptorsAndDirections(
        bool bIncepts,
        bool receivesBase,
        uint128 baseAmountSeed,
        uint128 quoteAmountSeed
    ) public {
        // uint128 inputs leave ample room for signed conversion and initial balances.
        uint256 baseAmount = uint256(baseAmountSeed) + 1;
        uint256 quoteAmount = uint256(quoteAmountSeed) + 1;
        address inceptor = bIncepts ? PARTY_B : PARTY_A;
        address confirmer = bIncepts ? PARTY_A : PARTY_B;
        address basePayer = receivesBase ? confirmer : inceptor;
        address baseReceiver = receivesBase ? inceptor : confirmer;
        address quotePayer = baseReceiver;
        address quoteReceiver = basePayer;
        base.mint(basePayer, baseAmount);
        quote.mint(quotePayer, quoteAmount);
        vm.prank(basePayer);
        base.approve(address(router), baseAmount);
        vm.prank(quotePayer);
        quote.approve(address(router), quoteAmount);
        int256 position = receivesBase ? int256(baseAmount) : -int256(baseAmount);
        int256 payment = receivesBase ? -int256(quoteAmount) : int256(quoteAmount);

        vm.prank(inceptor);
        swap.inceptTrade(confirmer, "terms", position, payment, "settlement");
        vm.prank(confirmer);
        swap.confirmTrade(inceptor, "terms", -position, -payment, "settlement");

        require(swap.phase() == FxAtomicSwap.Phase.Settled, "phase");
        require(!router.activeSwap(address(swap)), "authorization");
        require(base.balanceOf(basePayer) == INITIAL_BALANCE, "base paid");
        require(base.balanceOf(baseReceiver) == INITIAL_BALANCE + baseAmount, "base received");
        require(quote.balanceOf(quotePayer) == INITIAL_BALANCE, "quote paid");
        require(quote.balanceOf(quoteReceiver) == INITIAL_BALANCE + quoteAmount, "quote received");
        require(base.allowance(basePayer, address(router)) == 0, "base allowance");
        require(quote.allowance(quotePayer, address(router)) == 0, "quote allowance");
    }

    function testCancellationExpiresQuoteAndClearsAuthorizationWithoutSpending() public {
        _incept();
        vm.expectEmit(false, false, false, true, address(swap));
        emit TradeCanceled(PARTY_A, "1");
        _cancel();
        require(swap.phase() == FxAtomicSwap.Phase.Canceled, "phase");
        require(!router.activeSwap(address(swap)), "authorization survives cancellation");
        require(swap.position() == POSITION && swap.paymentAmount() == PAYMENT, "lost terms");
        _assertOriginalBalancesAndAllowances();
        _assertTerminalCallsRevert();
    }

    function testPartyBCanInceptAndCancel() public {
        vm.prank(PARTY_B);
        swap.inceptTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
        vm.prank(PARTY_B);
        swap.cancelTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
        require(swap.phase() == FxAtomicSwap.Phase.Canceled, "phase");
        require(!router.activeSwap(address(swap)), "authorization");
        _assertOriginalBalancesAndAllowances();
    }

    function testRouterRejectionRollsBackCancellationPhase() public {
        // Direct deployment deliberately omits the factory's router registration.
        FxAtomicSwap unregistered =
            new FxAtomicSwap(_token(base), _token(quote), PARTY_A, PARTY_B, router);
        vm.prank(PARTY_A);
        unregistered.inceptTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InactiveSwap.selector);
        vm.prank(PARTY_A);
        unregistered.cancelTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
        require(
            unregistered.phase() == FxAtomicSwap.Phase.Incepted,
            "cancellation phase survived revert"
        );
        require(router.activeSwap(address(swap)), "unrelated authorization changed");
        _assertOriginalBalancesAndAllowances();
    }

    function testSettlementPreventsCancellationAndReplay() public {
        _incept();
        _confirm();
        _assertTerminalCallsRevert();
        _assertSettled();
    }

    function testSeparateSwapsUseIndependentAuthorizations() public {
        FxAtomicSwap second = _createSwap(_token(base), _token(quote), PARTY_B, PARTY_A);
        _incept();
        _cancel();
        require(router.activeSwap(address(second)), "cancellation affected another swap");
        vm.prank(PARTY_A);
        second.inceptTrade(PARTY_B, "new terms", POSITION, PAYMENT, "settlement");
        vm.prank(PARTY_B);
        second.confirmTrade(PARTY_A, "new terms", -POSITION, -PAYMENT, "settlement");
        require(second.phase() == FxAtomicSwap.Phase.Settled, "second swap did not settle");
        require(!router.activeSwap(address(second)), "second authorization");
        require(swap.phase() == FxAtomicSwap.Phase.Canceled, "first swap changed");
    }

    function testOnlyNamedPartyCanCreateSwap() public {
        vm.expectRevert(FxAtomicSwapFactory.CreatorNotParty.selector);
        vm.prank(OUTSIDER);
        factory.createSwap(_token(base), _token(quote), PARTY_A, PARTY_B);
    }

    function testConstructorRejectsInvalidTokensPartiesAndRouter() public {
        vm.expectRevert(FxAtomicSwap.InvalidToken.selector);
        new FxAtomicSwap(IERC20RouterToken(address(0)), _token(quote), PARTY_A, PARTY_B, router);
        vm.expectRevert(FxAtomicSwap.InvalidToken.selector);
        new FxAtomicSwap(_token(base), _token(base), PARTY_A, PARTY_B, router);
        vm.expectRevert(FxAtomicSwap.InvalidToken.selector);
        new FxAtomicSwap(_token(base), IERC20RouterToken(OUTSIDER), PARTY_A, PARTY_B, router);
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        new FxAtomicSwap(_token(base), _token(quote), PARTY_A, address(0), router);
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        new FxAtomicSwap(_token(base), _token(quote), PARTY_A, PARTY_A, router);
        vm.expectRevert(FxAtomicSwap.InvalidRouter.selector);
        new FxAtomicSwap(
            _token(base), _token(quote), PARTY_A, PARTY_B, IAtomicSwapSettlement(OUTSIDER)
        );
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InvalidFactory.selector);
        new ERC20AtomicSwapSettlementRouter(address(0));
    }

    function testRouterRejectsUnregisteredCallersAndUnauthorizedRegistration() public {
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.NotFactory.selector);
        router.registerSwap(address(swap));
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InactiveSwap.selector);
        router.settleAtomicSwap(_token(base), _token(quote), PARTY_A, PARTY_B, POSITION, PAYMENT);
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InactiveSwap.selector);
        router.cancelAtomicSwap();
        require(router.activeSwap(address(swap)), "outsider changed authorization");
        _assertOriginalBalancesAndAllowances();
    }

    function testRouterRejectsInvalidAndDuplicateRegistration() public {
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InvalidSwap.selector);
        vm.prank(address(factory));
        router.registerSwap(OUTSIDER);
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InvalidSwap.selector);
        vm.prank(address(factory));
        router.registerSwap(address(swap));
    }

    function testInceptionRejectsWrongPartiesAndRepeatedInception() public {
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(OUTSIDER);
        swap.inceptTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(PARTY_A);
        swap.inceptTrade(OUTSIDER, "terms", POSITION, PAYMENT, "settlement");
        _incept();
        vm.expectRevert(FxAtomicSwap.InvalidPhase.selector);
        _incept();
    }

    function testInceptionRejectsZeroEqualSignsAndMinimumInteger() public {
        int256[6] memory positions =
            [int256(0), int256(100), int256(100), int256(-100), type(int256).min, int256(100)];
        int256[6] memory payments =
            [int256(-200), int256(0), int256(200), int256(-200), int256(200), type(int256).min];
        for (uint256 i; i < positions.length; i++) {
            vm.expectRevert(FxAtomicSwap.InvalidLegs.selector);
            vm.prank(PARTY_A);
            swap.inceptTrade(PARTY_B, "terms", positions[i], payments[i], "settlement");
        }
        require(swap.phase() == FxAtomicSwap.Phase.Created, "failed inception changed phase");
    }

    function testConfirmAndCancelRequireInception() public {
        vm.expectRevert(FxAtomicSwap.InvalidPhase.selector);
        _confirm();
        vm.expectRevert(FxAtomicSwap.InvalidPhase.selector);
        _cancel();
        require(router.activeSwap(address(swap)), "authorization changed");
    }

    function testConfirmationRequiresCounterpartyAndOriginalInceptor() public {
        _incept();
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(PARTY_A);
        swap.confirmTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(OUTSIDER);
        swap.confirmTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(PARTY_B);
        swap.confirmTrade(OUTSIDER, "terms", -POSITION, -PAYMENT, "settlement");
    }

    function testConfirmationRequiresEveryTermToMatch() public {
        _incept();
        for (uint256 field; field < 4; field++) {
            vm.expectRevert(FxAtomicSwap.TermsMismatch.selector);
            vm.prank(PARTY_B);
            swap.confirmTrade(
                PARTY_A,
                field == 0 ? "changed" : "terms",
                field == 1 ? -POSITION + 1 : -POSITION,
                field == 2 ? -PAYMENT + 1 : -PAYMENT,
                field == 3 ? "changed" : "settlement"
            );
        }
        _assertOpenAndUnspent();
    }

    function testCancellationRequiresInceptorAndEveryTermToMatch() public {
        _incept();
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(PARTY_B);
        swap.cancelTrade(PARTY_A, "terms", POSITION, PAYMENT, "settlement");
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(OUTSIDER);
        swap.cancelTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
        vm.expectRevert(FxAtomicSwap.InvalidParty.selector);
        vm.prank(PARTY_A);
        swap.cancelTrade(OUTSIDER, "terms", POSITION, PAYMENT, "settlement");
        for (uint256 field; field < 4; field++) {
            vm.expectRevert(FxAtomicSwap.TermsMismatch.selector);
            vm.prank(PARTY_A);
            swap.cancelTrade(
                PARTY_B,
                field == 0 ? "changed" : "terms",
                field == 1 ? POSITION + 1 : POSITION,
                field == 2 ? PAYMENT + 1 : PAYMENT,
                field == 3 ? "changed" : "settlement"
            );
        }
        _assertOpenAndUnspent();
    }

    function testSecondLegAllowanceFailureRollsBackAndCanRetry() public {
        _incept();
        vm.prank(PARTY_A);
        quote.approve(address(router), 199);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20AtomicSwapSettlementRouter.TransferFromFailed.selector, address(quote)
            )
        );
        _confirm();
        require(swap.phase() == FxAtomicSwap.Phase.Incepted, "phase not restored");
        require(router.activeSwap(address(swap)), "authorization not restored");
        require(base.balanceOf(PARTY_A) == INITIAL_BALANCE, "first transfer survived");
        require(base.balanceOf(PARTY_B) == INITIAL_BALANCE, "base payer balance");
        require(base.allowance(PARTY_B, address(router)) == INITIAL_BALANCE, "base allowance");
        require(quote.balanceOf(PARTY_A) == INITIAL_BALANCE, "quote payer balance");
        require(quote.balanceOf(PARTY_B) == INITIAL_BALANCE, "quote receiver balance");
        require(quote.allowance(PARTY_A, address(router)) == 199, "quote allowance");
        vm.prank(PARTY_A);
        quote.approve(address(router), INITIAL_BALANCE);
        _confirm();
        _assertSettled();
    }

    function testSecondLegBalanceFailureCanBeCanceled() public {
        _incept();
        vm.prank(PARTY_A);
        quote.transfer(OUTSIDER, INITIAL_BALANCE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20AtomicSwapSettlementRouter.TransferFromFailed.selector, address(quote)
            )
        );
        _confirm();
        require(base.balanceOf(PARTY_A) == INITIAL_BALANCE, "first transfer survived");
        require(base.balanceOf(PARTY_B) == INITIAL_BALANCE, "base payer balance");
        require(base.allowance(PARTY_B, address(router)) == INITIAL_BALANCE, "base allowance");
        _cancel();
        require(swap.phase() == FxAtomicSwap.Phase.Canceled, "cannot cancel failed settlement");
        require(!router.activeSwap(address(swap)), "authorization survives cancellation");
    }

    function testFirstLegFailureLeavesQuoteUnspent() public {
        _incept();
        vm.prank(PARTY_B);
        base.approve(address(router), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20AtomicSwapSettlementRouter.TransferFromFailed.selector, address(base)
            )
        );
        _confirm();
        require(swap.phase() == FxAtomicSwap.Phase.Incepted, "phase");
        require(router.activeSwap(address(swap)), "authorization");
        require(quote.balanceOf(PARTY_A) == INITIAL_BALANCE, "quote spent");
        require(quote.balanceOf(PARTY_B) == INITIAL_BALANCE, "quote credited");
        require(quote.allowance(PARTY_A, address(router)) == INITIAL_BALANCE, "quote allowance");
    }

    function testNoReturnDataTokenSettlesExactly() public {
        (FxAtomicSwap customSwap, ReturnToken customQuote) = _customQuoteSwap();
        customQuote.setBehavior(ReturnToken.Behavior.NoData);
        vm.prank(PARTY_B);
        customSwap.confirmTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
        require(customSwap.phase() == FxAtomicSwap.Phase.Settled, "phase");
        require(!router.activeSwap(address(customSwap)), "authorization");
        require(base.balanceOf(PARTY_A) == INITIAL_BALANCE + 100, "base receipt");
        require(customQuote.balanceOf(PARTY_A) == 0, "quote payment");
        require(customQuote.balanceOf(PARTY_B) == 200, "quote receipt");
        require(customQuote.allowance(PARTY_A, address(router)) == 0, "quote allowance");
    }

    function testFalseRevertingAndMalformedTokenResponsesRollBackAllEffects() public {
        (FxAtomicSwap customSwap, ReturnToken customQuote) = _customQuoteSwap();
        ReturnToken.Behavior[3] memory failures = [
            ReturnToken.Behavior.False, ReturnToken.Behavior.Revert, ReturnToken.Behavior.ShortData
        ];
        for (uint256 i; i < failures.length; i++) {
            customQuote.setBehavior(failures[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ERC20AtomicSwapSettlementRouter.TransferFromFailed.selector,
                    address(customQuote)
                )
            );
            vm.prank(PARTY_B);
            customSwap.confirmTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
            require(customSwap.phase() == FxAtomicSwap.Phase.Incepted, "phase not restored");
            require(router.activeSwap(address(customSwap)), "authorization not restored");
            require(base.balanceOf(PARTY_A) == INITIAL_BALANCE, "first transfer survived");
            require(base.balanceOf(PARTY_B) == INITIAL_BALANCE, "base payer balance");
            require(base.allowance(PARTY_B, address(router)) == INITIAL_BALANCE, "base allowance");
            require(customQuote.balanceOf(PARTY_A) == 200, "token side effects survived");
            require(customQuote.balanceOf(PARTY_B) == 0, "quote recipient balance");
            require(customQuote.allowance(PARTY_A, address(router)) == 200, "quote allowance");
        }
    }

    function testCounterpartyCannotReenterConfirmationDuringTransfer() public {
        ReturnToken callbackToken = new ReturnToken();
        ReentrantCounterparty counterparty = new ReentrantCounterparty();
        FxAtomicSwap callbackSwap =
            _createSwap(callbackToken, _token(quote), PARTY_A, address(counterparty));
        callbackToken.mint(address(counterparty), 100);
        counterparty.approve(callbackToken, address(router), 100);
        callbackToken.setHook(counterparty);
        vm.prank(PARTY_A);
        callbackSwap.inceptTrade(address(counterparty), "terms", POSITION, PAYMENT, "settlement");
        counterparty.confirm(callbackSwap, PARTY_A);
        require(counterparty.attempted(), "callback not reached");
        require(counterparty.reentryError() == FxAtomicSwap.InvalidPhase.selector, "reentry guard");
        require(callbackSwap.phase() == FxAtomicSwap.Phase.Settled, "outer settlement failed");
        require(!router.activeSwap(address(callbackSwap)), "authorization");
        require(callbackToken.balanceOf(PARTY_A) == 100, "base not transferred exactly once");
        require(quote.balanceOf(address(counterparty)) == 200, "quote not transferred exactly once");
    }

    function testUnsupportedTerminationOperationsRevert() public {
        vm.expectRevert(FxAtomicSwap.TerminationNotSupported.selector);
        swap.requestTradeTermination("1", 0, "terms");
        vm.expectRevert(FxAtomicSwap.TerminationNotSupported.selector);
        swap.confirmTradeTermination("1", 0, "terms");
        vm.expectRevert(FxAtomicSwap.TerminationNotSupported.selector);
        swap.cancelTradeTermination("1", 0, "terms");
    }

    function _customQuoteSwap() private returns (FxAtomicSwap customSwap, ReturnToken customQuote) {
        customQuote = new ReturnToken();
        customSwap = _createSwap(_token(base), customQuote, PARTY_A, PARTY_B);
        customQuote.mint(PARTY_A, 200);
        vm.prank(PARTY_A);
        customQuote.approve(address(router), 200);
        vm.prank(PARTY_A);
        customSwap.inceptTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
    }

    function _createSwap(
        IERC20RouterToken baseToken,
        IERC20RouterToken quoteToken,
        address a,
        address b
    ) private returns (FxAtomicSwap) {
        vm.prank(a);
        return FxAtomicSwap(factory.createSwap(baseToken, quoteToken, a, b));
    }

    function _fundAndApprove(ERC20TokenExample token, address party) private {
        token.mint(party, INITIAL_BALANCE);
        vm.prank(party);
        token.approve(address(router), INITIAL_BALANCE);
    }

    function _token(ERC20TokenExample token) private pure returns (IERC20RouterToken) {
        return IERC20RouterToken(address(token));
    }

    function _incept() private {
        vm.prank(PARTY_A);
        swap.inceptTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
    }

    function _confirm() private {
        vm.prank(PARTY_B);
        swap.confirmTrade(PARTY_A, "terms", -POSITION, -PAYMENT, "settlement");
    }

    function _cancel() private {
        vm.prank(PARTY_A);
        swap.cancelTrade(PARTY_B, "terms", POSITION, PAYMENT, "settlement");
    }

    function _assertTerminalCallsRevert() private {
        vm.expectRevert(FxAtomicSwap.InvalidPhase.selector);
        _confirm();
        vm.expectRevert(FxAtomicSwap.InvalidPhase.selector);
        _cancel();
        vm.expectRevert(FxAtomicSwap.InvalidPhase.selector);
        _incept();
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InactiveSwap.selector);
        vm.prank(address(swap));
        router.settleAtomicSwap(_token(base), _token(quote), PARTY_A, PARTY_B, POSITION, PAYMENT);
        vm.expectRevert(ERC20AtomicSwapSettlementRouter.InactiveSwap.selector);
        vm.prank(address(swap));
        router.cancelAtomicSwap();
    }

    function _assertOriginalBalancesAndAllowances() private view {
        require(base.balanceOf(PARTY_A) == INITIAL_BALANCE, "base A balance");
        require(base.balanceOf(PARTY_B) == INITIAL_BALANCE, "base B balance");
        require(quote.balanceOf(PARTY_A) == INITIAL_BALANCE, "quote A balance");
        require(quote.balanceOf(PARTY_B) == INITIAL_BALANCE, "quote B balance");
        require(base.allowance(PARTY_A, address(router)) == INITIAL_BALANCE, "base A allowance");
        require(base.allowance(PARTY_B, address(router)) == INITIAL_BALANCE, "base B allowance");
        require(quote.allowance(PARTY_A, address(router)) == INITIAL_BALANCE, "quote A allowance");
        require(quote.allowance(PARTY_B, address(router)) == INITIAL_BALANCE, "quote B allowance");
    }

    function _assertOpenAndUnspent() private view {
        require(swap.phase() == FxAtomicSwap.Phase.Incepted, "phase");
        require(router.activeSwap(address(swap)), "authorization");
        _assertOriginalBalancesAndAllowances();
    }

    function _assertSettled() private view {
        require(swap.phase() == FxAtomicSwap.Phase.Settled, "phase");
        require(!router.activeSwap(address(swap)), "authorization");
        require(base.balanceOf(PARTY_A) == INITIAL_BALANCE + 100, "base A balance");
        require(base.balanceOf(PARTY_B) == INITIAL_BALANCE - 100, "base B balance");
        require(quote.balanceOf(PARTY_A) == INITIAL_BALANCE - 200, "quote A balance");
        require(quote.balanceOf(PARTY_B) == INITIAL_BALANCE + 200, "quote B balance");
        require(base.allowance(PARTY_B, address(router)) == INITIAL_BALANCE - 100, "base allowance");
        require(
            quote.allowance(PARTY_A, address(router)) == INITIAL_BALANCE - 200, "quote allowance"
        );
    }
}
