// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IDecryptionContractWithKeyGeneration} from "@finmath.net/dvp/contracts/IDecryptionContractWithKeyGeneration.sol";
import {IDecryptionContractInceptionCallback} from "@finmath.net/dvp/contracts/IDecryptionContractInceptionCallback.sol";
import {IKeyDecryptionOracle} from "@finmath.net/dvp/contracts/IKeyDecryptionOracle.sol";
import {IKeyDecryptionOracleCallback} from "@finmath.net/dvp/contracts/IKeyDecryptionOracleCallback.sol";
import {ILockingContract} from "@finmath.net/dvp/contracts/ILockingContract.sol";
import {IPontesDirectPayment, IPontesDirectPaymentCallback} from "./IPontesDirectPayment.sol";

/**
 * @title PontesPaymentContract
 * @notice Asset-agnostic, multi-leg ERC-7573 payment contract for Pontes.
 * @dev An eligible requester opens a leg and chooses its complete context and callback. The contract never inspects
 *      the callback or imports product, registry, token or client-registry interfaces.
 *      The payer's oracle verifies both generated references before execution is enabled.
 */
contract PontesPaymentContract is
    IDecryptionContractWithKeyGeneration,
    IKeyDecryptionOracleCallback,
    IPontesDirectPayment
{
    bytes32 public constant KEY_EXECUTION = keccak256("KEY_EXECUTION");
    bytes32 public constant KEY_CANCELLATION = keccak256("KEY_CANCELLATION");

    uint256 private constant INCEPTION_CALLBACK_GAS_RESERVE = 50_000;
    uint256 private constant KEY_RELAY_GAS_LIMIT = 500_000;
    uint256 private constant KEY_RELAY_GAS_RESERVE = 50_000;

    enum State {
        None,
        Generating,
        Ready,
        Confirmed,
        ExecutionPending,
        CancellationPending,
        Settled,
        Cancelled
    }

    // Values 1..4 are part of the adapter authorization ABI. Keep their order stable.
    enum Operation {
        None,
        Generate,
        Execute,
        Cancel,
        Verify
    }

    enum VerificationState {
        None,
        Pending,
        Verified,
        Rejected
    }

    struct Leg {
        address requester;
        address payer;
        address payee;
        int256 amount;
        bytes transaction;
        bytes encryptedExecutionKey;
        bytes encryptedCancellationKey;
        bytes32 executionHash;
        bytes32 cancellationHash;
        IDecryptionContractInceptionCallback callback;
        IKeyDecryptionOracle generationOracle;
        IKeyDecryptionOracle executionOracle;
        State state;
        VerificationState verification;
    }

    struct PendingRequest {
        bytes32 legKey;
        uint256 id;
        Operation operation;
        bool active;
        bool recoveryOnly;
    }

    struct DirectPayment {
        address requester;
        address payer;
        address payee;
        uint256 amount;
        uint8 amountScale;
        address agent;
        bool settled;
        bool delivered;
    }

    struct PaymentBics {
        string payerBic;
        string payeeBic;
    }

    address public immutable owner;
    mapping(address => bool) public isRequester;
    mapping(address => IKeyDecryptionOracle) public oracleOf;
    mapping(address => uint256) public feeBalance;
    mapping(address => address) public directPaymentAgentOf;
    mapping(address => string) public paymentBicOf;
    mapping(bytes32 => DirectPayment) public directPayments;
    mapping(bytes32 => PaymentBics) public directPaymentBics;
    mapping(bytes32 => Leg) private _legs;
    mapping(bytes32 => PendingRequest) private _pendingRequests;

    /// @notice Monotonic revision of oracleOf, including changes back to an earlier address.
    /// @dev Used by represented-state consumers whose XML reads participant oracle routing.
    uint256 public oracleConfigurationVersion;

    event RequesterSet(address indexed requester, bool allowed);
    event ParticipantOracleSet(
        address indexed participant,
        address indexed previousOracle,
        address indexed newOracle
    );
    event PontesLegIncepted(
        address indexed callback,
        uint256 indexed id,
        bytes32 legKey,
        address requester,
        address payer
    );
    event PontesOracleRequest(
        uint256 indexed id,
        address indexed oracle,
        uint256 indexed requestId,
        Operation operation
    );
    event PontesVerificationRequested(
        address indexed callback,
        uint256 indexed id,
        address indexed oracle,
        uint256 requestId
    );
    event PontesVerificationCompleted(address indexed callback, uint256 indexed id, bool verified);
    event PontesOutcome(uint256 indexed id, address indexed callback, bool success, bytes key);
    event CallbackKeyRelayAttempted(uint256 indexed id, address indexed callback, bool success);
    event DirectPaymentAgentSet(address indexed payer, address indexed agent);
    event DirectPaymentRequested(
        bytes32 indexed requestId,
        address indexed requester,
        address indexed payer,
        address payee,
        uint256 amount,
        uint8 amountScale,
        address agent,
        string payerBic,
        string payeeBic
    );
    event DirectPaymentSettled(bytes32 indexed requestId, address indexed requester);
    event DirectPaymentDeliveryAttempted(
        bytes32 indexed requestId,
        address indexed requester,
        bool success
    );

    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidId();
    error InvalidParticipant();
    error IneligibleRequester();
    error UnauthorizedOperator();
    error UnregisteredParticipantOracle(address participant);
    error TrustDomainsMustDiffer();
    error InvalidState(State expected, State actual);
    error InvalidVerificationState();
    error VerificationRequired();
    error InvalidTransferContext();
    error InvalidCallbackContext();
    error InvalidGenerationResult();
    error InvalidVerificationResult();
    error InvalidHash();
    error UnknownSettlement();
    error UnknownOracleRequest();
    error UnexpectedOracleRequest();
    error InsufficientOracleFee(address requester, uint256 required, uint256 available);
    error TransferFailed();
    error DirectKeyInceptionDisabled();
    error DirectKeyReleaseDisabled();
    error InceptionCallbackRejected();
    error DuplicateDirectPayment(bytes32 requestId);
    error UnknownDirectPayment(bytes32 requestId);
    error DirectPaymentNotSettled(bytes32 requestId);
    error UnregisteredDirectPaymentAgent(address payer);
    error MissingPaymentBic(address participant);
    error InvalidDirectPaymentAmount(uint256 amount, uint8 amountScale);

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    receive() external payable {
        feeBalance[owner] += msg.value;
    }

    /* --------------------------- Configuration --------------------------- */

    function setRequester(address requester, bool allowed) external onlyOwner {
        if (requester == address(0)) revert ZeroAddress();
        isRequester[requester] = allowed;
        emit RequesterSet(requester, allowed);
    }

    function setOracleFor(address participant, IKeyDecryptionOracle oracle) external onlyOwner {
        if (participant == address(0)) revert ZeroAddress();
        address previous = address(oracleOf[participant]);
        if (previous != address(oracle)) ++oracleConfigurationVersion;
        oracleOf[participant] = oracle;
        emit ParticipantOracleSet(participant, previous, address(oracle));
    }

    function setDirectPaymentAgent(address payer, address agent) external onlyOwner {
        if (payer == address(0)) revert ZeroAddress();
        directPaymentAgentOf[payer] = agent;
        emit DirectPaymentAgentSet(payer, agent);
    }

    function setPaymentBic(address participant, string calldata bic) external onlyOwner {
        if (participant == address(0)) revert ZeroAddress();
        paymentBicOf[participant] = bic;
    }

    function depositFor(address requester) external payable {
        if (requester == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        feeBalance[requester] += msg.value;
    }

    function withdrawFees(uint256 amount, address payable to) external {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 available = feeBalance[msg.sender];
        if (available < amount) revert InsufficientOracleFee(msg.sender, amount, available);
        unchecked {
            feeBalance[msg.sender] = available - amount;
        }
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /* ------------------------ Direct EUR payments ------------------------ */

    function requestDirectPayment(
        bytes32 requestId,
        address payer,
        address payee,
        uint256 amount,
        uint8 amountScale
    ) external override {
        if (!isRequester[msg.sender]) revert IneligibleRequester();
        if (address(uint160(uint256(requestId) >> 96)) != msg.sender) revert InvalidId();
        if (directPayments[requestId].requester != address(0)) {
            revert DuplicateDirectPayment(requestId);
        }
        if (payer == address(0) || payee == address(0) || payer == payee) {
            revert InvalidParticipant();
        }
        _validateCashAmount(amount, amountScale);
        address agent = directPaymentAgentOf[payer];
        if (agent == address(0)) revert UnregisteredDirectPaymentAgent(payer);
        _validateAuthorityRoute(address(0), agent);

        string memory payerBic = paymentBicOf[payer];
        string memory payeeBic = paymentBicOf[payee];
        if (bytes(payerBic).length == 0) revert MissingPaymentBic(payer);
        if (bytes(payeeBic).length == 0) revert MissingPaymentBic(payee);

        directPayments[requestId] = DirectPayment(
            msg.sender, payer, payee, amount, amountScale, agent, false, false
        );
        directPaymentBics[requestId] = PaymentBics(payerBic, payeeBic);
        emit DirectPaymentRequested(
            requestId,
            msg.sender,
            payer,
            payee,
            amount,
            amountScale,
            agent,
            payerBic,
            payeeBic
        );
    }

    function fulfillDirectPayment(bytes32 requestId) external {
        DirectPayment storage payment = directPayments[requestId];
        if (payment.requester == address(0)) revert UnknownDirectPayment(requestId);
        if (msg.sender != payment.agent) revert UnauthorizedOperator();
        _validateAuthorityRoute(address(0), payment.agent);
        if (!payment.settled) {
            payment.settled = true;
            emit DirectPaymentSettled(requestId, payment.requester);
        }
        _deliverDirectPayment(requestId, payment);
    }

    function isDirectPaymentSettled(bytes32 requestId) external view override returns (bool) {
        return directPayments[requestId].settled;
    }

    function retryDirectPaymentDelivery(bytes32 requestId) external {
        DirectPayment storage payment = directPayments[requestId];
        if (!payment.settled) revert DirectPaymentNotSettled(requestId);
        _deliverDirectPayment(requestId, payment);
    }

    /// @dev Validate the frozen route when it becomes actionable. Direct payments have no
    ///      generation authority (zero); atomic legs have two separately registered oracles.
    ///      Neither authority may share this payment contract's trust domain.
    function _validateAuthorityRoute(address generationAuthority, address executionAuthority) private view {
        if (
            generationAuthority == executionAuthority || generationAuthority == address(this)
                || executionAuthority == address(this)
        ) revert TrustDomainsMustDiffer();
    }

    function _validateCashAmount(uint256 amount, uint8 scale) private pure {
        if (amount == 0 || scale > 77) revert InvalidDirectPaymentAmount(amount, scale);
        uint256 maxCents = 99_999_999_999_999_999;
        if (scale < 2) {
            uint256 factor = 10 ** (2 - scale);
            if (amount > maxCents / factor) revert InvalidDirectPaymentAmount(amount, scale);
            return;
        }
        uint256 unitsPerCent = 10 ** (scale - 2);
        if (amount % unitsPerCent != 0 || amount / unitsPerCent > maxCents) {
            revert InvalidDirectPaymentAmount(amount, scale);
        }
    }

    /* ------------------------- ERC-7573 lifecycle ------------------------ */

    function inceptTransfer(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback
    ) external override {
        if (!isRequester[msg.sender]) revert IneligibleRequester();
        if (id == 0) revert InvalidId();
        if (
            amount <= 0 || from == address(0) || to == address(0) || from == to
                || transaction.length == 0
        ) revert InvalidParticipant();

        bytes32 legKey = _legKey(address(callback), id);
        Leg storage leg = _legs[legKey];
        if (leg.state != State.None) revert InvalidState(State.None, leg.state);

        IKeyDecryptionOracle generationOracle = _oracleFor(to);
        IKeyDecryptionOracle executionOracle = _oracleFor(from);
        _validateAuthorityRoute(address(generationOracle), address(executionOracle));

        leg.requester = msg.sender;
        leg.payer = from;
        leg.payee = to;
        leg.amount = amount;
        leg.transaction = transaction;
        leg.callback = callback;
        leg.generationOracle = generationOracle;
        leg.executionOracle = executionOracle;
        leg.state = State.Generating;

        emit PontesLegIncepted(address(callback), id, legKey, msg.sender, from);
        _requestGeneration(legKey, id);
    }

    function inceptTransfer(
        uint256,
        int256,
        address,
        address,
        bytes memory,
        bytes memory,
        bytes memory
    ) external pure override {
        revert DirectKeyInceptionDisabled();
    }

    /**
     * @notice Requests atomic verification through the payer's frozen oracle.
     * @dev The payer calls directly and names the callback that identifies the leg. Any attached
     *      value is credited to the leg's requester before fees are charged.
     */
    function requestVerification(
        address callback,
        uint256 id
    ) external payable returns (uint256 requestId) {
        bytes32 legKey = _legKey(callback, id);
        Leg storage leg = _legs[legKey];
        if (leg.state == State.None) revert UnknownSettlement();
        if (msg.sender != leg.payer) revert UnauthorizedOperator();
        if (leg.state != State.Ready) revert InvalidState(State.Ready, leg.state);
        if (leg.verification != VerificationState.None) revert InvalidVerificationState();

        if (msg.value != 0) {
            feeBalance[leg.requester] += msg.value;
        }

        IKeyDecryptionOracle.EncryptedKey[] memory keys = new IKeyDecryptionOracle.EncryptedKey[](2);
        keys[0] = IKeyDecryptionOracle.EncryptedKey(KEY_EXECUTION, leg.encryptedExecutionKey);
        keys[1] = IKeyDecryptionOracle.EncryptedKey(KEY_CANCELLATION, leg.encryptedCancellationKey);

        uint256 fee = _readFee(address(leg.executionOracle), bytes4(keccak256("feeVerify()"))) * 2;
        _charge(leg.requester, fee);
        leg.verification = VerificationState.Pending;
        requestId = leg.executionOracle.requestVerifyEncryptedKeys{value: fee}(
            id, keys, IKeyDecryptionOracleCallback(address(this))
        );
        _recordRequest(address(leg.executionOracle), requestId, legKey, id, Operation.Verify);
        emit PontesVerificationRequested(callback, id, address(leg.executionOracle), requestId);
    }

    function confirmTransfer(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback,
        bytes memory keyEncryptedSuccess,
        bytes memory keyEncryptedFailure
    ) external override {
        bytes32 legKey = _resolveByCallback(callback, id);
        Leg storage leg = _legs[legKey];
        if (msg.sender != leg.payer) revert UnauthorizedOperator();
        if (leg.state != State.Ready) revert InvalidState(State.Ready, leg.state);
        if (leg.verification != VerificationState.Verified) revert VerificationRequired();
        _requireTransferContext(
            leg,
            amount,
            from,
            to,
            transaction,
            callback,
            keyEncryptedSuccess,
            keyEncryptedFailure
        );
        leg.state = State.Confirmed;
        emit TransferConfirmed(
            id,
            leg.amount,
            leg.payer,
            leg.payee,
            leg.transaction,
            leg.callback,
            leg.encryptedExecutionKey,
            leg.encryptedCancellationKey
        );
        _transferAndDecrypt(legKey, id, leg.payer);
    }

    function transferAndDecrypt(uint256) external pure override {
        // Confirmation already requests execution atomically; there is no intermediate callable state.
        revert InvalidTransferContext();
    }

    function cancelAndDecrypt(
        uint256 id,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback,
        bytes memory keyEncryptedSuccess,
        bytes memory keyEncryptedFailure
    ) external override {
        bytes32 legKey = _resolveByCallback(callback, id);
        Leg storage leg = _legs[legKey];
        if (msg.sender != leg.requester) revert UnauthorizedOperator();
        if (leg.state != State.Ready) {
            revert InvalidState(State.Ready, leg.state);
        }
        _requireTransferContext(
            leg,
            amount,
            from,
            to,
            transaction,
            callback,
            keyEncryptedSuccess,
            keyEncryptedFailure
        );
        leg.state = State.CancellationPending;
        emit TransferKeyRequested(msg.sender, id, leg.encryptedCancellationKey);
        _requestDecryption(legKey, id, Operation.Cancel, false);
    }

    function releaseKey(uint256, bytes memory) external pure override {
        revert DirectKeyReleaseDisabled();
    }

    /* -------------------------- Oracle callbacks ------------------------- */

    function onEncryptedHashedKeysGenerated(
        uint256 requestId,
        EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external override {
        PendingRequest memory pending = _requireRequest(msg.sender, requestId, Operation.Generate);
        Leg storage leg = _legs[pending.legKey];
        if (msg.sender != address(leg.generationOracle)) revert UnexpectedOracleRequest();
        if (leg.state != State.Generating) revert InvalidState(State.Generating, leg.state);
        if (receiverContract != address(this) || keccak256(transaction) != keccak256(leg.transaction)) {
            revert InvalidCallbackContext();
        }

        (
            leg.encryptedExecutionKey,
            leg.executionHash,
            leg.encryptedCancellationKey,
            leg.cancellationHash
        ) = _validatedGeneratedKeys(keys);
        leg.state = State.Ready;
        _consumeRequest(msg.sender, requestId);

        emit EncryptedHashedKeysGenerated(msg.sender, requestId, keys, receiverContract, transaction);
        emit TransferIncepted(
            pending.id,
            leg.amount,
            leg.payer,
            leg.payee,
            leg.transaction,
            leg.encryptedExecutionKey,
            leg.encryptedCancellationKey
        );
        _notifyInceptionCallback(pending.id, leg.callback);
    }

    function onEncryptedKeysVerificationCompleted(
        uint256 requestId,
        bool verified,
        EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external override {
        PendingRequest memory pending = _requireRequest(msg.sender, requestId, Operation.Verify);
        Leg storage leg = _legs[pending.legKey];
        if (
            msg.sender != address(leg.executionOracle)
                || leg.verification != VerificationState.Pending
        ) revert UnexpectedOracleRequest();

        _validateVerification(leg, verified, keys, receiverContract, transaction);
        _consumeRequest(msg.sender, requestId);
        leg.verification = verified ? VerificationState.Verified : VerificationState.Rejected;

        emit EncryptedKeysVerificationCompleted(
            msg.sender, requestId, verified, keys, receiverContract, transaction
        );
        emit PontesVerificationCompleted(address(leg.callback), pending.id, verified);
    }

    function onKeyReleased(uint256 requestId, bytes calldata key) external override {
        PendingRequest memory pending = _requireRequest(msg.sender, requestId, Operation.None);
        Leg storage leg = _legs[pending.legKey];
        bytes32 actualHash = sha256(key);

        if (pending.operation == Operation.Execute) {
            if (
                msg.sender != address(leg.executionOracle) || leg.state != State.ExecutionPending
            ) revert UnexpectedOracleRequest();
            if (actualHash != leg.executionHash) revert InvalidHash();
            _consumeRequest(msg.sender, requestId);
            leg.state = State.Settled;
            emit KeyReleased(msg.sender, requestId, key);
            emit TransferKeyReleased(msg.sender, pending.id, true, key);
            emit PontesOutcome(pending.id, address(leg.callback), true, key);
            _tryRelayKey(pending.id, leg.callback, key);
            return;
        }

        if (pending.operation == Operation.Cancel) {
            if (
                msg.sender != address(leg.generationOracle)
                    || leg.state != State.CancellationPending
            ) revert UnexpectedOracleRequest();
            if (actualHash != leg.cancellationHash) revert InvalidHash();
            _consumeRequest(msg.sender, requestId);
            leg.state = State.Cancelled;
            emit KeyReleased(msg.sender, requestId, key);
            emit TransferKeyReleased(msg.sender, pending.id, false, key);
            emit PontesOutcome(pending.id, address(leg.callback), false, key);
            _tryRelayKey(pending.id, leg.callback, key);
            return;
        }

        revert UnexpectedOracleRequest();
    }

    /** @notice Reconciles a denied outcome by reading the opposite terminal key. */
    function onKeyDenied(uint256 requestId) external override {
        PendingRequest memory pending = _requireRequest(msg.sender, requestId, Operation.None);
        Leg storage leg = _legs[pending.legKey];

        if (pending.operation == Operation.Execute) {
            if (
                msg.sender != address(leg.executionOracle) || leg.state != State.ExecutionPending
            ) revert UnexpectedOracleRequest();
            _consumeRequest(msg.sender, requestId);
            emit DecryptionDenied(msg.sender, requestId);
            leg.state = State.CancellationPending;
            emit TransferKeyRequested(leg.payer, pending.id, leg.encryptedCancellationKey);
            _requestDecryption(pending.legKey, pending.id, Operation.Cancel, false);
            return;
        }

        if (pending.operation == Operation.Cancel) {
            if (
                msg.sender != address(leg.generationOracle)
                    || leg.state != State.CancellationPending
            ) revert UnexpectedOracleRequest();
            _consumeRequest(msg.sender, requestId);
            emit DecryptionDenied(msg.sender, requestId);
            leg.state = State.ExecutionPending;
            emit TransferKeyRequested(leg.requester, pending.id, leg.encryptedExecutionKey);
            _requestDecryption(pending.legKey, pending.id, Operation.Execute, true);
            return;
        }

        revert UnexpectedOracleRequest();
    }

    /* -------------------------------- Views ------------------------------ */

    function stateOf(address callback, uint256 id) external view returns (State) {
        return _legs[_legKey(callback, id)].state;
    }

    function verificationStateOf(
        address callback,
        uint256 id
    ) external view returns (VerificationState) {
        return _legs[_legKey(callback, id)].verification;
    }

    function requesterOf(address callback, uint256 id) external view returns (address) {
        return _legs[_legKey(callback, id)].requester;
    }

    function oraclesOf(
        address callback,
        uint256 id
    ) external view returns (address generationOracle, address executionOracle) {
        Leg storage leg = _legs[_legKey(callback, id)];
        return (address(leg.generationOracle), address(leg.executionOracle));
    }

    function legKeyOf(address callback, uint256 id) external pure returns (bytes32) {
        return _legKey(callback, id);
    }

    function getInceptionContext(
        uint256 id
    ) external view override returns (
        bool exists,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback
    ) {
        return _inceptionContext(_legKey(msg.sender, id));
    }

    function getInceptionContextFor(
        address callback,
        uint256 id
    ) external view returns (
        bool exists,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback inceptionCallback
    ) {
        return _inceptionContext(_legKey(callback, id));
    }

    function getInceptionKeyMaterial(
        uint256 id
    ) external view override returns (
        bool available,
        bytes memory keyEncryptedSuccess,
        bytes memory keyHashedSuccess,
        bytes memory keyEncryptedFailure,
        bytes memory keyHashedFailure
    ) {
        return _inceptionKeyMaterial(_legKey(msg.sender, id));
    }

    function getInceptionKeyMaterialFor(
        address callback,
        uint256 id
    ) external view returns (
        bool available,
        bytes memory keyEncryptedSuccess,
        bytes memory keyHashedSuccess,
        bytes memory keyEncryptedFailure,
        bytes memory keyHashedFailure
    ) {
        return _inceptionKeyMaterial(_legKey(callback, id));
    }

    function requiredVerificationFee(address callback, uint256 id) external view returns (uint256) {
        Leg storage leg = _legs[_legKey(callback, id)];
        if (leg.state == State.None) revert UnknownSettlement();
        return _readFee(address(leg.executionOracle), bytes4(keccak256("feeVerify()"))) * 2;
    }

    function isPaymentRecoveryRequest(address oracle, uint256 requestId) external view returns (bool) {
        return _pendingRequests[_requestKey(oracle, requestId)].recoveryOnly;
    }

    /** @notice Returns the immutable routing context of an oracle request. */
    function paymentRequestContext(
        address oracle,
        uint256 requestId
    ) external view returns (
        Operation operation,
        address generationOracle,
        address executionOracle
    ) {
        PendingRequest storage request = _pendingRequests[_requestKey(oracle, requestId)];
        Leg storage leg = _legs[request.legKey];
        return (
            request.operation,
            address(leg.generationOracle),
            address(leg.executionOracle)
        );
    }

    /**
     * @notice Authenticates an oracle event against immutable leg data.
     * @dev Consumed records remain as tombstones for journal reconciliation, but `active` is false.
     */
    function authorizedPaymentRequest(
        address oracle,
        uint256 requestId,
        uint256 consumerId,
        uint8 operation,
        bytes calldata transaction,
        bytes calldata encryptedKey
    ) external view returns (bool authorized, bool active) {
        PendingRequest storage request = _pendingRequests[_requestKey(oracle, requestId)];
        if (
            operation == 0 || operation > uint8(Operation.Cancel)
                || uint8(request.operation) != operation || request.id != consumerId
        ) return (false, false);

        Leg storage leg = _legs[request.legKey];
        if (leg.state == State.None || keccak256(transaction) != keccak256(leg.transaction)) {
            return (false, false);
        }
        if (request.operation == Operation.Generate) {
            authorized = oracle == address(leg.generationOracle) && encryptedKey.length == 0;
        } else if (request.operation == Operation.Execute) {
            authorized = oracle == address(leg.executionOracle)
                && keccak256(encryptedKey) == keccak256(leg.encryptedExecutionKey);
        } else {
            authorized = oracle == address(leg.generationOracle)
                && keccak256(encryptedKey) == keccak256(leg.encryptedCancellationKey);
        }
        active = authorized && request.active;
    }

    /* ------------------------------- Internals --------------------------- */

    function _requestGeneration(bytes32 legKey, uint256 id) internal {
        Leg storage leg = _legs[legKey];
        bytes32[] memory keyIds = new bytes32[](2);
        keyIds[0] = KEY_EXECUTION;
        keyIds[1] = KEY_CANCELLATION;

        uint256 fee = _readFee(
            address(leg.generationOracle), bytes4(keccak256("feeGenerate()"))
        ) * 2;
        _charge(leg.requester, fee);
        uint256 requestId = leg.generationOracle.requestGenerateEncryptedHashedKeys{value: fee}(
            id,
            IKeyDecryptionOracleCallback(address(this)),
            address(this),
            leg.transaction,
            keyIds
        );
        _recordRequest(address(leg.generationOracle), requestId, legKey, id, Operation.Generate);
    }

    function _transferAndDecrypt(bytes32 legKey, uint256 id, address actor) internal {
        Leg storage leg = _legs[legKey];
        if (leg.state != State.Confirmed) revert InvalidState(State.Confirmed, leg.state);
        if (leg.verification != VerificationState.Verified) revert VerificationRequired();
        leg.state = State.ExecutionPending;
        emit TransferKeyRequested(actor, id, leg.encryptedExecutionKey);
        _requestDecryption(legKey, id, Operation.Execute, false);
    }

    function _requestDecryption(
        bytes32 legKey,
        uint256 id,
        Operation operation,
        bool recoveryOnly
    ) internal {
        Leg storage leg = _legs[legKey];
        // A normal execution may create a payment and therefore requires payer verification.
        // Cancel-denial recovery is GET-only in the adapter and may only reconcile an already
        // terminal payment, so it must remain possible even if verification was never requested.
        if (
            operation == Operation.Execute && !recoveryOnly
                && leg.verification != VerificationState.Verified
        ) {
            revert VerificationRequired();
        }
        IKeyDecryptionOracle oracle = operation == Operation.Execute
            ? leg.executionOracle
            : leg.generationOracle;
        bytes memory encryptedKey = operation == Operation.Execute
            ? leg.encryptedExecutionKey
            : leg.encryptedCancellationKey;
        uint256 fee = _readFee(address(oracle), bytes4(keccak256("feeDecrypt()")));
        _charge(leg.requester, fee);
        uint256 requestId = oracle.requestDecrypt{value: fee}(
            id, encryptedKey, IKeyDecryptionOracleCallback(address(this)), leg.transaction
        );
        _recordRequest(address(oracle), requestId, legKey, id, operation);
        _pendingRequests[_requestKey(address(oracle), requestId)].recoveryOnly = recoveryOnly;
    }

    function _validateVerification(
        Leg storage leg,
        bool verified,
        EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) internal view {
        if (!verified) {
            if (receiverContract != address(0) || transaction.length != 0) {
                revert InvalidVerificationResult();
            }
            return;
        }
        if (
            receiverContract != address(this) || keccak256(transaction) != keccak256(leg.transaction)
                || keys.length != 2
        ) revert InvalidVerificationResult();

        uint256 roles;
        for (uint256 i; i < 2; ++i) {
            uint256 role;
            bytes32 expectedHash;
            if (keys[i].keyId == KEY_EXECUTION) {
                role = 1;
                expectedHash = leg.executionHash;
            } else if (keys[i].keyId == KEY_CANCELLATION) {
                role = 2;
                expectedHash = leg.cancellationHash;
            } else {
                revert InvalidVerificationResult();
            }
            if (
                roles & role != 0 || keys[i].hashedKey.length != 32
                    || bytes32(keys[i].hashedKey) != expectedHash
            ) revert InvalidVerificationResult();
            roles |= role;
        }
    }

    function _validatedGeneratedKeys(
        EncryptedHashedKey[] calldata keys
    ) internal pure returns (
        bytes memory encryptedExecution,
        bytes32 executionHash,
        bytes memory encryptedCancellation,
        bytes32 cancellationHash
    ) {
        if (keys.length != 2) revert InvalidGenerationResult();
        uint256 roles;
        for (uint256 i; i < 2; ++i) {
            if (keys[i].encryptedKey.length == 0 || keys[i].hashedKey.length != 32) {
                revert InvalidGenerationResult();
            }
            if (keys[i].keyId == KEY_EXECUTION && roles & 1 == 0) {
                roles |= 1;
                encryptedExecution = keys[i].encryptedKey;
                executionHash = bytes32(keys[i].hashedKey);
            } else if (keys[i].keyId == KEY_CANCELLATION && roles & 2 == 0) {
                roles |= 2;
                encryptedCancellation = keys[i].encryptedKey;
                cancellationHash = bytes32(keys[i].hashedKey);
            } else {
                revert InvalidGenerationResult();
            }
        }
        if (
            roles != 3 || executionHash == bytes32(0) || cancellationHash == bytes32(0)
                || executionHash == cancellationHash
                || keccak256(encryptedExecution) == keccak256(encryptedCancellation)
        ) revert InvalidGenerationResult();
    }

    function _requireTransferContext(
        Leg storage leg,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback,
        bytes memory keyEncryptedSuccess,
        bytes memory keyEncryptedFailure
    ) internal view {
        if (
            amount != leg.amount || from != leg.payer || to != leg.payee
                || keccak256(transaction) != keccak256(leg.transaction)
                || address(callback) != address(leg.callback)
                || keccak256(keyEncryptedSuccess) != keccak256(leg.encryptedExecutionKey)
                || keccak256(keyEncryptedFailure) != keccak256(leg.encryptedCancellationKey)
        ) revert InvalidTransferContext();
    }

    function _notifyInceptionCallback(
        uint256 id,
        IDecryptionContractInceptionCallback callback
    ) internal {
        if (address(callback) == address(0)) return;
        uint256 availableGas = gasleft();
        if (availableGas <= INCEPTION_CALLBACK_GAS_RESERVE) revert InceptionCallbackRejected();
        (bool success, bytes memory result) = address(callback).call{
            gas: availableGas - INCEPTION_CALLBACK_GAS_RESERVE
        }(abi.encodeCall(IDecryptionContractInceptionCallback.onInceptionCompleted, (id)));
        if (
            !success || result.length != 32
                || abi.decode(result, (bytes4))
                    != IDecryptionContractInceptionCallback.onInceptionCompleted.selector
        ) revert InceptionCallbackRejected();
    }

    function _tryRelayKey(
        uint256 id,
        IDecryptionContractInceptionCallback callback,
        bytes calldata key
    ) internal {
        address target = address(callback);
        if (target.code.length == 0) {
            emit CallbackKeyRelayAttempted(id, target, false);
            return;
        }
        uint256 availableGas = gasleft();
        if (availableGas <= KEY_RELAY_GAS_RESERVE) {
            emit CallbackKeyRelayAttempted(id, target, false);
            return;
        }
        uint256 relayGas = availableGas - KEY_RELAY_GAS_RESERVE;
        if (relayGas > KEY_RELAY_GAS_LIMIT) relayGas = KEY_RELAY_GAS_LIMIT;
        (bool success,) = target.call{gas: relayGas}(
            abi.encodeCall(ILockingContract.transferWithKey, (id, key))
        );
        emit CallbackKeyRelayAttempted(id, target, success);
    }

    function _deliverDirectPayment(bytes32 requestId, DirectPayment storage payment) internal {
        if (payment.delivered) return;
        address requester = payment.requester;
        uint256 availableGas = gasleft();
        if (requester.code.length == 0 || availableGas <= KEY_RELAY_GAS_RESERVE) {
            emit DirectPaymentDeliveryAttempted(requestId, requester, false);
            return;
        }
        uint256 callbackGas = availableGas - KEY_RELAY_GAS_RESERVE;
        if (callbackGas > KEY_RELAY_GAS_LIMIT) callbackGas = KEY_RELAY_GAS_LIMIT;
        payment.delivered = true;
        (bool success,) = requester.call{gas: callbackGas}(
            abi.encodeCall(IPontesDirectPaymentCallback.onDirectPaymentSettled, (requestId))
        );
        if (!success) payment.delivered = false;
        emit DirectPaymentDeliveryAttempted(requestId, requester, success);
    }

    function _inceptionContext(
        bytes32 legKey
    ) internal view returns (
        bool exists,
        int256 amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback
    ) {
        Leg storage leg = _legs[legKey];
        exists = leg.state != State.None;
        if (!exists) {
            return (
                false,
                0,
                address(0),
                address(0),
                bytes(""),
                IDecryptionContractInceptionCallback(address(0))
            );
        }
        return (true, leg.amount, leg.payer, leg.payee, leg.transaction, leg.callback);
    }

    function _inceptionKeyMaterial(
        bytes32 legKey
    ) internal view returns (
        bool available,
        bytes memory keyEncryptedSuccess,
        bytes memory keyHashedSuccess,
        bytes memory keyEncryptedFailure,
        bytes memory keyHashedFailure
    ) {
        Leg storage leg = _legs[legKey];
        available = uint256(leg.state) >= uint256(State.Ready);
        if (!available) return (false, bytes(""), bytes(""), bytes(""), bytes(""));
        return (
            true,
            leg.encryptedExecutionKey,
            abi.encodePacked(leg.executionHash),
            leg.encryptedCancellationKey,
            abi.encodePacked(leg.cancellationHash)
        );
    }

    function _oracleFor(address participant) internal view returns (IKeyDecryptionOracle oracle) {
        oracle = oracleOf[participant];
        if (address(oracle) == address(0)) revert UnregisteredParticipantOracle(participant);
    }

    function _resolveByCallback(
        IDecryptionContractInceptionCallback callback,
        uint256 id
    ) internal view returns (bytes32 legKey) {
        legKey = _legKey(address(callback), id);
        if (_legs[legKey].state == State.None) revert UnknownSettlement();
    }

    function _charge(address requester, uint256 amount) internal {
        if (amount == 0) return;
        uint256 available = feeBalance[requester];
        if (available < amount) revert InsufficientOracleFee(requester, amount, available);
        unchecked {
            feeBalance[requester] = available - amount;
        }
    }

    function _recordRequest(
        address oracle,
        uint256 requestId,
        bytes32 legKey,
        uint256 id,
        Operation operation
    ) internal {
        bytes32 key = _requestKey(oracle, requestId);
        if (_pendingRequests[key].operation != Operation.None) revert UnexpectedOracleRequest();
        _pendingRequests[key] = PendingRequest(legKey, id, operation, true, false);
        emit PontesOracleRequest(id, oracle, requestId, operation);
    }

    function _requireRequest(
        address oracle,
        uint256 requestId,
        Operation expected
    ) internal view returns (PendingRequest memory pending) {
        pending = _pendingRequests[_requestKey(oracle, requestId)];
        if (!pending.active) revert UnknownOracleRequest();
        if (expected != Operation.None && pending.operation != expected) {
            revert UnexpectedOracleRequest();
        }
    }

    function _consumeRequest(address oracle, uint256 requestId) internal {
        _pendingRequests[_requestKey(oracle, requestId)].active = false;
    }

    function _requestKey(address oracle, uint256 requestId) internal pure returns (bytes32) {
        return keccak256(abi.encode(oracle, requestId));
    }

    function _legKey(address callback, uint256 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(callback, id));
    }

    function _readFee(address oracle, bytes4 selector) internal view returns (uint256 fee) {
        (bool ok, bytes memory data) = oracle.staticcall(abi.encodeWithSelector(selector));
        if (ok && data.length >= 32) fee = abi.decode(data, (uint256));
    }
}
