// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@finmath.net/dvp/contracts/IKeyDecryptionOracle.sol";
import "@finmath.net/dvp/contracts/IKeyDecryptionOracleCallback.sol";

/**
 * @title Key Decryption Oracle Contract. On-chain proxy for an off-chain key-decryption-oracle
 * @notice Decryption Oracle (On-Chain Proxy). Proxy of an Off-Chain Decryption Oracle.
 * - Consumer calls request* which emits an event with a requestId (correlation-id)
 * - Off-Chain oracle calls fulfill* with requestId
 * - Proxy calls the consumer callback with requestId and fulfillment data.
 *
 * Fulfillment semantics (selectable at deployment):
 * - StrictRevert: fulfill* reverts if callback fails (incl. OOG). Off-chain oracle can use receipt.status.
 * - BestEffort: fulfill* does not revert solely because callback fails; it emits CallbackFailed and keeps request pending.
 * - A request is marked in-flight before the external callback so the same request cannot be fulfilled reentrantly.
 *
 * Gas forwarding:
 * - Off-chain oracle controls tx gasLimit (total budget).
 * - Proxy forwards "all but a reserve" to callback, keeping gasReserve to execute catch + emit + finalize.
 *
 * Request permissioning:
 * - If requestsPermissionless == true, anyone may call request*.
 * - If requestsPermissionless == false, only allowlisted requesters may call request*.
 *
 * Multi-Oracle (default + extras):
 * - `oracle` is the default oracle / treasury recipient for fundOracle()
 * - Additional oracles can be allowlisted (extras) to call fulfill*.
 * - Invariant: the default `oracle` is NOT stored in the extra-oracle list.
 * - Authorization check: (o == oracle) || (oracleIndexPlus1[o] != 0)
 *
 * @author Christian Fries.
 */
contract KeyDecryptionOracle is IKeyDecryptionOracle {
    /* ---------------- Errors ---------------- */

    error NotOracle();
    error UnknownRequest();
    error CallbackReverted(); // used in StrictRevert mode
    error EtherNotAccepted();
    error IncorrectFee();
    error NotRequester();
    error ZeroAddress();
    error EmptyKeyIds();
    error TooManyKeyIds(uint256 provided, uint256 maximum);
    error DuplicateKeyId(bytes32 keyId);
    error EmptyVerificationBatch();
    error TooManyVerificationKeys(uint256 provided, uint256 maximum);
    error EmptyEncryptedKey(bytes32 keyId);
    error InvalidVerifiedKeySet();
    error InvalidVerificationResult();
    error InvalidGeneratedKeySet();
    error GenerationContextMismatch();

    // Multi-oracle management
    error OracleAlreadyAdded();
    error OracleNotFound();
    error CannotAddDefaultOracle();
    error CannotRemoveDefaultOracle();

    /* -------------------------------- Types -------------------------------- */

    enum FulfillmentMode {
        StrictRevert,
        BestEffort
    }

    enum Kind {
        None,
        Decrypt,
        Verify,
        Generate
    }

    uint256 public constant MAX_GENERATION_BATCH_SIZE = 32;
    uint256 public constant MAX_VERIFICATION_BATCH_SIZE = 32;
    // Glamsterdam raises an existing-slot write to 10,000 execution gas (EIP-8038).
    // Keep this protocol-owned cleanup budget separate from the configurable reserve:
    // generation clears one array element per key, verification clears two.
    uint256 private constant FIXED_CLEANUP_GAS = 100_000;
    uint256 private constant GENERATION_CLEANUP_GAS_PER_KEY = 13_000;
    uint256 private constant VERIFICATION_CLEANUP_GAS_PER_KEY = 25_000;

    struct Request {
        IKeyDecryptionOracleCallback callback;
        uint256 consumerId;
        Kind kind;
        bool inFlight;
    }

    struct GenerationSpecification {
        address receiverContract;
        bytes32 transactionHash;
        bytes32[] keyIds;
    }

    struct VerificationSpecification {
        bytes32[] keyIds;
        bytes32[] encryptedKeyHashes;
    }

    /* ------------------------------- Storage -------------------------------- */

    /// @notice Default off-chain relayer/oracle (allowed to call fulfill*), and default fee recipient for fundOracle().
    address public oracle;

    /// @dev Extra allowlisted oracles (NOT including `oracle`) with O(1) add/remove (swap & pop).
    address[] private extraOracles;
    mapping(address => uint256) private oracleIndexPlus1; // 0 => not present; else index+1 into extraOracles

    /// @notice Admin
    address public owner;

    /// @notice Fee schedule (in wei). feeGenerate is charged per generated key.
    uint256 public feeDecrypt;
    uint256 public feeVerify;
    uint256 public feeGenerate;

    /// @notice Fulfillment semantics (immutable per deployment)
    FulfillmentMode public immutable fulfillmentMode;

    /// @notice Configurable gas reserve kept by fulfill* after forwarding gas to the callback.
    /// @dev Unit: gas (NOT wei). This is retained in addition to the fixed and per-key
    ///      cleanup allowances so an owner cannot configure away the protocol-safety margin.
    uint256 public gasReserve = 50_000;

    /// @notice If true, request* is permissionless. If false, only allowlisted requesters may call request*.
    bool public requestsPermissionless;

    /// @notice Allowlist of addresses permitted to call request* when requestsPermissionless == false.
    mapping(address => bool) public isRequester;

    uint256 public lastRequestId;
    mapping(uint256 => Request) private requests;
    mapping(uint256 => GenerationSpecification) private generationSpecifications;
    mapping(uint256 => VerificationSpecification) private verificationSpecifications;

    /* ---------------- Events ---------------- */

    event FeesUpdated(uint256 decryptWei, uint256 verifyWei, uint256 generateWei);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeesWithdrawn(address indexed to, uint256 amount);

    event GasReserveUpdated(uint256 gasReserve);
    event RequestsPermissionlessUpdated(bool permissionless);
    event RequesterUpdated(address indexed requester, bool allowed);

    // Multi-oracle events
    event OracleUpdated(address indexed oracle, bool allowed); // extras only
    event DefaultOracleUpdated(address indexed previousOracle, address indexed newOracle);

    /* ---------------- Modifiers ---------------- */

    modifier onlyOracle() {
        if (!_isOracle(msg.sender)) revert NotOracle();
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyRequesters() {
        if (!requestsPermissionless && !isRequester[msg.sender]) revert NotRequester();
        _;
    }

    /* --- constructor ------------------------------------------------------ */

    constructor(address _oracle, FulfillmentMode _mode, bool _requestsPermissionless) {
        if (_oracle == address(0)) revert ZeroAddress();

        oracle = _oracle;
        fulfillmentMode = _mode;

        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);

        emit DefaultOracleUpdated(address(0), _oracle);

        requestsPermissionless = _requestsPermissionless;
        emit RequestsPermissionlessUpdated(_requestsPermissionless);

        // Optional convenience: if permissioned, allow owner by default.
        if (!_requestsPermissionless) {
            isRequester[msg.sender] = true;
            emit RequesterUpdated(msg.sender, true);
        }
    }

    fallback() external payable {
        revert EtherNotAccepted();
    }

    receive() external payable {
        revert EtherNotAccepted();
    }

    /* ---------------- Public / View ---------------- */

    /// @notice Returns true if `o` is the default oracle or an allowlisted extra oracle.
    function isOracle(address o) external view returns (bool) {
        return _isOracle(o);
    }

    /// @notice Number of total allowed oracles (default + extras).
    function oracleCount() external view returns (uint256) {
        return 1 + extraOracles.length;
    }

    /// @notice Returns the extra allowlisted oracles (does NOT include the default `oracle`).
    function getExtraOracles() external view returns (address[] memory) {
        return extraOracles;
    }

    /// @notice Returns all allowed oracles, with the default `oracle` at index 0, followed by extras.
    function getOracles() external view returns (address[] memory all) {
        all = new address[](1 + extraOracles.length);
        all[0] = oracle;
        for (uint256 i = 0; i < extraOracles.length; i++) {
            all[i + 1] = extraOracles[i];
        }
    }

    /* ---------------- Admin: Ownership ---------------- */

    /**
     * @notice Transfer ownership of this oracle proxy contract.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "KeyDecryptionOracle: owner zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /* ---------------- Admin: Oracle ---------------- */

    /**
     * @notice Change default oracle address (e.g. upgrade or switch instance).
     * @dev Enforces invariant that default `oracle` is NOT in extra-oracle list.
     *      If `newOracle` exists in extras, it will be removed from extras.
     */
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();

        address prev = oracle;
        if (newOracle == prev) return;

        // If the new default oracle is currently in the extras list, remove it to enforce invariant.
        if (oracleIndexPlus1[newOracle] != 0) {
            _removeExtraOracle(newOracle); // emits OracleUpdated(newOracle, false)
        }

        oracle = newOracle;
        emit DefaultOracleUpdated(prev, newOracle);
    }

    /**
     * @notice Add an extra oracle address that is allowed to call fulfill*.
     * @dev Default `oracle` cannot be added as an extra.
     */
    function addOracle(address o) external onlyOwner {
        if (o == address(0)) revert ZeroAddress();
        if (o == oracle) revert CannotAddDefaultOracle();
        _addExtraOracle(o);
    }

    /**
     * @notice Remove an extra oracle address so it can no longer call fulfill*.
     * @dev Cannot remove the default `oracle` with this function.
     */
    function removeOracle(address o) external onlyOwner {
        if (o == oracle) revert CannotRemoveDefaultOracle();
        _removeExtraOracle(o);
    }

    /* ---------------- Admin: Fees, Gas, Permission ---------------- */

    function setFees(uint256 decryptWei, uint256 verifyWei, uint256 generateWei) external onlyOwner {
        feeDecrypt = decryptWei;
        feeVerify = verifyWei;
        feeGenerate = generateWei;
        emit FeesUpdated(decryptWei, verifyWei, generateWei);
    }

    function setGasReserve(uint256 newReserve) external onlyOwner {
        // Conservative bounds: avoid accidental misconfiguration (too small to finish, too large to be useful).
        require(newReserve >= 10_000 && newReserve <= 300_000, "KeyDecryptionOracle: reserve out of bounds");
        gasReserve = newReserve;
        emit GasReserveUpdated(newReserve);
    }

    function setRequestsPermissionless(bool permissionless) external onlyOwner {
        requestsPermissionless = permissionless;
        emit RequestsPermissionlessUpdated(permissionless);
    }

    function setRequester(address requester, bool allowed) external onlyOwner {
        if (requester == address(0)) revert ZeroAddress();
        isRequester[requester] = allowed;
        emit RequesterUpdated(requester, allowed);
    }

    /**
     * @notice Route accumulated fees to the off-chain oracle EOA or a treasury.
     */
    function withdraw(uint256 amount, address payable to) public onlyOwner {
        require(to != address(0), "KeyDecryptionOracle: zero address");
        require(amount <= address(this).balance, "KeyDecryptionOracle: insufficient balance");

        (bool s, ) = to.call{value: amount}("");
        require(s, "KeyDecryptionOracle: withdraw failed");

        emit FeesWithdrawn(to, amount);
    }

    /**
     * @notice Transfers all fees to the default oracle.
     */
    function fundOracle() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "KeyDecryptionOracle: no balance");
        withdraw(amount, payable(oracle));
    }

    /* ---------------- Requests ------------------------- */

    function requestGenerateEncryptedHashedKeys(
        uint256 id,
        IKeyDecryptionOracleCallback callback,
        address receiverContract,
        bytes calldata transaction,
        bytes32[] calldata keyIds
    ) external payable override onlyRequesters returns (uint256 requestId) {
        require(address(callback) != address(0), "KeyDecryptionOracle: callback zero address");
        _validateRequestedKeyIds(keyIds);
        if (msg.value != feeGenerate * keyIds.length) revert IncorrectFee();

        requestId = ++lastRequestId;
        requests[requestId] = Request({
            callback: callback,
            consumerId: id,
            kind: Kind.Generate,
            inFlight: false
        });

        GenerationSpecification storage specification = generationSpecifications[requestId];
        specification.receiverContract = receiverContract;
        // ERC-7573 transaction bytes are opaque and must be fulfilled unchanged.
        specification.transactionHash = keccak256(transaction);
        for (uint256 i = 0; i < keyIds.length; i++) {
            specification.keyIds.push(keyIds[i]);
        }

        emit EncryptedHashedKeysGenerationRequested(
            msg.sender,
            id,
            callback,
            receiverContract,
            transaction,
            keyIds,
            requestId
        );
    }

    function requestVerifyEncryptedKeys(
        uint256 id,
        EncryptedKey[] calldata keys,
        IKeyDecryptionOracleCallback callback
    ) external payable override onlyRequesters returns (uint256 requestId) {
        if (msg.value != feeVerify * keys.length) revert IncorrectFee();
        require(address(callback) != address(0), "KeyDecryptionOracle: callback zero address");
        _validateRequestedVerificationKeys(keys);

        requestId = ++lastRequestId;
        requests[requestId] = Request({
            callback: callback,
            consumerId: id,
            kind: Kind.Verify,
            inFlight: false
        });

        VerificationSpecification storage specification = verificationSpecifications[requestId];
        for (uint256 i = 0; i < keys.length; i++) {
            specification.keyIds.push(keys[i].keyId);
            specification.encryptedKeyHashes.push(keccak256(keys[i].encryptedKey));
        }

        emit EncryptedKeysVerificationRequested(msg.sender, id, keys, callback, requestId);
    }

    function requestDecrypt(
        uint256 id,
        bytes calldata encryptedKey,
        IKeyDecryptionOracleCallback callback,
        bytes calldata transaction
    ) external payable override onlyRequesters returns (uint256 requestId) {
        if (msg.value != feeDecrypt) revert IncorrectFee();
        require(address(callback) != address(0), "KeyDecryptionOracle: callback zero address");

        requestId = ++lastRequestId;
        requests[requestId] = Request({
            callback: callback,
            consumerId: id,
            kind: Kind.Decrypt,
            inFlight: false
        });
        emit DecryptionRequested(msg.sender, id, encryptedKey, callback, transaction, requestId);
    }

    /* ------------------------------ Fulfillments ---------------------------- */

    /**
     * @notice Fulfillment for requestGenerateEncryptedHashedKeys.
     * @dev Off-chain fallback: arguments are in tx calldata; see fulfillDecryption @dev for details.
     */
    function fulfillEncryptedHashedKeysGeneration(
        uint256 requestId,
        IKeyDecryptionOracleCallback.EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external override onlyOracle {
        Request memory r = _beginFulfillment(requestId, Kind.Generate);
        _validateGenerationFulfillment(requestId, keys, receiverContract, transaction);

        // Forward as much as possible while keeping a reserve for catch + event + finalization.
        // Clearing the stored keyIds after a successful callback costs gas proportional to the batch.
        uint256 g = _gasToForward(
            gasReserve + FIXED_CLEANUP_GAS + keys.length * GENERATION_CLEANUP_GAS_PER_KEY
        );
        require(g > 0, "KeyDecryptionOracle: insufficient gas to forward");

        bytes4 sel = IKeyDecryptionOracleCallback.onEncryptedHashedKeysGenerated.selector;
        try r.callback.onEncryptedHashedKeysGenerated{gas: g}(
            requestId,
            keys,
            receiverContract,
            transaction
        ) {
            emit CallbackSucceeded(requestId, address(r.callback), sel, r.consumerId);
            _consume(requestId);
        } catch (bytes memory reason) {
            _onCallbackFailure(requestId, r, sel, reason);
        }
    }

    /**
     * @notice Fulfillment for Verify.
     * @dev Off-chain fallback: arguments are in tx calldata; see fulfillDecryption @dev for details.
     */
    function fulfillEncryptedKeysVerification(
        uint256 requestId,
        bool verified,
        IKeyDecryptionOracleCallback.EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external override onlyOracle {
        Request memory r = _beginFulfillment(requestId, Kind.Verify);
        _validateVerificationFulfillment(requestId, verified, keys, receiverContract, transaction);

        // Forward as much as possible while keeping a reserve for catch + event + finalization.
        uint256 g = _gasToForward(
            gasReserve + FIXED_CLEANUP_GAS + keys.length * VERIFICATION_CLEANUP_GAS_PER_KEY
        );
        require(g > 0, "KeyDecryptionOracle: insufficient gas to forward");

        bytes4 sel = IKeyDecryptionOracleCallback.onEncryptedKeysVerificationCompleted.selector;
        try r.callback.onEncryptedKeysVerificationCompleted{gas: g}(
            requestId,
            verified,
            keys,
            receiverContract,
            transaction
        ) {
            emit CallbackSucceeded(requestId, address(r.callback), sel, r.consumerId);
            _consume(requestId);
        } catch (bytes memory reason) {
            _onCallbackFailure(requestId, r, sel, reason);
        }
    }

    /**
     * @notice Fulfillment for Decrypt.
     *
     * @dev Off-chain fallback:
     *      The fulfillment payload (e.g. `key`) is present in the transaction calldata of this fulfill call.
     *      If the callback fails (BestEffort mode emits CallbackFailed), indexers can use the emitted log's
     *      transactionHash to fetch the transaction input and decode it with this contract's ABI.
     *
     *      Practical caveat: some RPC providers prune old transaction bodies; store decoded payload off-chain
     *      when processing the event if long-term retention is required.
     */
    function fulfillDecryption(uint256 requestId, bytes calldata key) external override onlyOracle {
        Request memory r = _beginFulfillment(requestId, Kind.Decrypt);

        // Forward as much as possible while keeping a reserve for catch + event + finalization.
        uint256 g = _gasToForward(gasReserve + FIXED_CLEANUP_GAS);
        require(g > 0, "KeyDecryptionOracle: insufficient gas to forward");

        if (key.length == 0) {
            bytes4 sel = IKeyDecryptionOracleCallback.onKeyDenied.selector;
            try r.callback.onKeyDenied{gas: g}(requestId) {
                emit CallbackSucceeded(requestId, address(r.callback), sel, r.consumerId);
                _consume(requestId);
            } catch (bytes memory reason) {
                _onCallbackFailure(requestId, r, sel, reason);
            }
        } else {
            bytes4 sel = IKeyDecryptionOracleCallback.onKeyReleased.selector;
            try r.callback.onKeyReleased{gas: g}(requestId, key) {
                emit CallbackSucceeded(requestId, address(r.callback), sel, r.consumerId);
                _consume(requestId);
            } catch (bytes memory reason) {
                _onCallbackFailure(requestId, r, sel, reason);
            }
        }
    }

    /* ------------------------------- Internals ------------------------------ */

    function _isOracle(address o) internal view returns (bool) {
        return (o == oracle) || (oracleIndexPlus1[o] != 0);
    }

    function _beginFulfillment(uint256 requestId, Kind expected) internal returns (Request memory r) {
        r = requests[requestId];
        if (address(r.callback) == address(0) || r.kind != expected || r.inFlight) {
            revert UnknownRequest();
        }
        requests[requestId].inFlight = true;
    }

    function _consume(uint256 requestId) internal {
        delete requests[requestId];
        delete generationSpecifications[requestId];
        delete verificationSpecifications[requestId];
    }

    function _validateRequestedKeyIds(bytes32[] calldata keyIds) internal pure {
        if (keyIds.length == 0) revert EmptyKeyIds();
        if (keyIds.length > MAX_GENERATION_BATCH_SIZE) {
            revert TooManyKeyIds(keyIds.length, MAX_GENERATION_BATCH_SIZE);
        }

        for (uint256 i = 0; i < keyIds.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (keyIds[i] == keyIds[j]) revert DuplicateKeyId(keyIds[i]);
            }
        }
    }

    function _validateRequestedVerificationKeys(EncryptedKey[] calldata keys) internal pure {
        if (keys.length == 0) revert EmptyVerificationBatch();
        if (keys.length > MAX_VERIFICATION_BATCH_SIZE) {
            revert TooManyVerificationKeys(keys.length, MAX_VERIFICATION_BATCH_SIZE);
        }

        for (uint256 i = 0; i < keys.length; i++) {
            if (keys[i].encryptedKey.length == 0) revert EmptyEncryptedKey(keys[i].keyId);
            for (uint256 j = 0; j < i; j++) {
                if (keys[i].keyId == keys[j].keyId) revert DuplicateKeyId(keys[i].keyId);
            }
        }
    }

    function _validateVerificationFulfillment(
        uint256 requestId,
        bool verified,
        IKeyDecryptionOracleCallback.EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) internal view {
        VerificationSpecification storage specification = verificationSpecifications[requestId];
        if (keys.length != specification.keyIds.length) revert InvalidVerifiedKeySet();

        if (verified && receiverContract == address(0)) {
            revert InvalidVerificationResult();
        }
        if (!verified && (receiverContract != address(0) || transaction.length != 0)) {
            revert InvalidVerificationResult();
        }

        for (uint256 i = 0; i < keys.length; i++) {
            bool requested;
            for (uint256 j = 0; j < specification.keyIds.length; j++) {
                if (keys[i].keyId == specification.keyIds[j]) {
                    if (keccak256(keys[i].encryptedKey) != specification.encryptedKeyHashes[j]) {
                        revert InvalidVerifiedKeySet();
                    }
                    requested = true;
                    break;
                }
            }
            if (!requested) revert InvalidVerifiedKeySet();
            if (verified && keys[i].hashedKey.length == 0) revert InvalidVerificationResult();

            for (uint256 j = 0; j < i; j++) {
                if (keys[i].keyId == keys[j].keyId) revert InvalidVerifiedKeySet();
            }
        }
    }

    function _validateGenerationFulfillment(
        uint256 requestId,
        IKeyDecryptionOracleCallback.EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) internal view {
        GenerationSpecification storage specification = generationSpecifications[requestId];

        if (
            receiverContract != specification.receiverContract
                || keccak256(transaction) != specification.transactionHash
        ) {
            revert GenerationContextMismatch();
        }

        if (keys.length != specification.keyIds.length) revert InvalidGeneratedKeySet();

        for (uint256 i = 0; i < keys.length; i++) {
            bool requested;
            for (uint256 j = 0; j < specification.keyIds.length; j++) {
                if (keys[i].keyId == specification.keyIds[j]) {
                    requested = true;
                    break;
                }
            }
            if (!requested) revert InvalidGeneratedKeySet();

            for (uint256 j = 0; j < i; j++) {
                if (keys[i].keyId == keys[j].keyId) revert InvalidGeneratedKeySet();
            }
        }
    }

    function _gasToForward(uint256 reserve) internal view returns (uint256) {
        uint256 g = gasleft();
        if (g <= reserve) return 0;
        // EIP-150 caps forwarded gas to <= g - g/64 anyway; this keeps explicit headroom.
        return g - reserve;
    }

    function _onCallbackFailure(uint256 requestId, Request memory r, bytes4 selector, bytes memory reason) internal {
        if (fulfillmentMode == FulfillmentMode.StrictRevert) {
            // In StrictRevert mode, we do not emit failure events (they would be rolled back by revert).
            revert CallbackReverted();
        }

        // BestEffort mode: restore the request to Pending, emit failure, and allow retry.
        requests[requestId].inFlight = false;
        emit CallbackFailed(requestId, address(r.callback), selector, r.consumerId, reason);
    }

    /* ---------------------- Extra-oracle internals -------------------------- */

    function _addExtraOracle(address o) internal {
        if (oracleIndexPlus1[o] != 0) revert OracleAlreadyAdded();

        extraOracles.push(o);
        oracleIndexPlus1[o] = extraOracles.length; // index + 1
        emit OracleUpdated(o, true);
    }

    function _removeExtraOracle(address o) internal {
        uint256 idxPlus1 = oracleIndexPlus1[o];
        if (idxPlus1 == 0) revert OracleNotFound();

        uint256 idx = idxPlus1 - 1;
        uint256 lastIdx = extraOracles.length - 1;

        // Swap oracle with last position
        if (idx != lastIdx) {
            address last = extraOracles[lastIdx];
            extraOracles[idx] = last;
            oracleIndexPlus1[last] = idx + 1;
        }

        // Remove last element
        extraOracles.pop();
        oracleIndexPlus1[o] = 0;

        emit OracleUpdated(o, false);
    }
}

// ---- Convenience wrappers / “overloaded constructor” equivalents ----

/**
 * @notice Permissionless Decryption Oracle (On-Chain Proxy) with strict revert fulfillment mode.
 */
contract KeyDecryptionOracle_Default is KeyDecryptionOracle {
    constructor(address _oracle) KeyDecryptionOracle(_oracle, FulfillmentMode.StrictRevert, true) {}
}

/**
 * @notice Permissioned Decryption Oracle (On-Chain Proxy) with strict revert fulfillment mode.
 */
contract KeyDecryptionOracle_DefaultPermissioned is KeyDecryptionOracle {
    constructor(address _oracle) KeyDecryptionOracle(_oracle, FulfillmentMode.StrictRevert, false) {}
}
