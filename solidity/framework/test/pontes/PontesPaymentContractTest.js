import hre from "hardhat";
import { expect } from "chai";
import { AbiCoder, id, sha256, toUtf8Bytes, ZeroAddress, ZeroHash } from "ethers";

describe("PontesPaymentContract", function () {
  const KEY_EXECUTION = id("KEY_EXECUTION");
  const KEY_CANCELLATION = id("KEY_CANCELLATION");
  const EXECUTION_KEY = toUtf8Bytes("pontes-execution-key");
  const CANCELLATION_KEY = toUtf8Bytes("pontes-cancellation-key");
  const ENCRYPTED_EXECUTION = toUtf8Bytes("opaque:E(S)");
  const ENCRYPTED_CANCELLATION = toUtf8Bytes("opaque:E(F)");
  const EXECUTION_HASH = sha256(EXECUTION_KEY);
  const CANCELLATION_HASH = sha256(CANCELLATION_KEY);
  const TRANSACTION = AbiCoder.defaultAbiCoder().encode(
    Array(6).fill("string"),
    ["MARKDEFFXXX", "MDO-SELLER", "BUYRDEFFXXX", "9000.00", "EUR", "DVP"]
  );
  const CLASSIC_INCEPT = "inceptTransfer(uint256,int256,address,address,bytes,bytes,bytes)";
  const CLASSIC_CONFIRM = "confirmTransfer(uint256,int256,address,address,bytes,bytes,bytes)";
  const ASYNC_INCEPT = "inceptTransfer(uint256,int256,address,address,bytes,address)";

  const PAYMENT_AMOUNT = 900_000;
  const ASSET_AMOUNT = 100;
  const FEE_DECRYPT = 5n;
  const FEE_VERIFY = 7n;
  const FEE_GENERATE = 11n;
  const GENERATION_COST = FEE_GENERATE * 2n;
  const VERIFICATION_COST = FEE_VERIFY * 2n;

  const GENERATING = 1n;
  const READY = 2n;
  const EXECUTION_PENDING = 4n;
  const SETTLED = 6n;
  const CANCELLED = 7n;
  const ASSET_LOCKED = 2n;
  const ASSET_CLAIMED = 3n;
  const ASSET_RECLAIMED = 4n;

  let ethers;
  let owner;
  let requester;
  let otherRequester;
  let seller;
  let buyer;
  let sellerAdapter;
  let buyerAdapter;
  let agent;
  let outsider;
  let sellerOracle;
  let buyerOracle;
  let payment;

  beforeEach(async function () {
    ({ ethers } = await hre.network.create());
    [
      owner,
      requester,
      otherRequester,
      seller,
      buyer,
      sellerAdapter,
      buyerAdapter,
      agent,
      outsider
    ] = await ethers.getSigners();

    const Oracle = await ethers.getContractFactory("KeyDecryptionOracle");
    sellerOracle = await Oracle.deploy(sellerAdapter.address, 0, true);
    buyerOracle = await Oracle.deploy(buyerAdapter.address, 0, true);
    await sellerOracle.waitForDeployment();
    await buyerOracle.waitForDeployment();
    await sellerOracle.setFees(FEE_DECRYPT, FEE_VERIFY, FEE_GENERATE);
    await buyerOracle.setFees(FEE_DECRYPT, FEE_VERIFY, FEE_GENERATE);

    payment = await (await ethers.getContractFactory("PontesPaymentContract"))
      .deploy(owner.address);
    await payment.waitForDeployment();
    await payment.setRequester(requester.address, true);
    await payment.setOracleFor(seller.address, sellerOracle.target);
    await payment.setOracleFor(buyer.address, buyerOracle.target);
  });

  function generatedKeys(
    encryptedExecution = ENCRYPTED_EXECUTION,
    encryptedCancellation = ENCRYPTED_CANCELLATION
  ) {
    return [
      [KEY_EXECUTION, encryptedExecution, EXECUTION_HASH],
      [KEY_CANCELLATION, encryptedCancellation, CANCELLATION_HASH]
    ];
  }

  function completionArgs(callback, transferId, transaction = TRANSACTION) {
    return [
      transferId,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      transaction,
      callback.target,
      ENCRYPTED_EXECUTION,
      ENCRYPTED_CANCELLATION
    ];
  }

  async function fund(who, amount) {
    await payment.depositFor(who.address ?? who, { value: amount });
  }

  async function deployRecorder() {
    const recorder = await (await ethers.getContractFactory("InceptionCallbackRecorder"))
      .deploy(payment.target);
    await recorder.waitForDeployment();
    return recorder;
  }

  async function expectInception(callback, transferId) {
    await callback.expectInception(
      transferId,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      TRANSACTION
    );
  }

  async function incept(callback, transferId, caller = requester) {
    await payment.connect(caller)[ASYNC_INCEPT](
      transferId,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      TRANSACTION,
      callback.target
    );
    return sellerOracle.lastRequestId();
  }

  async function ready(
    callback,
    transferId,
    caller = requester,
    keys = generatedKeys(),
    recordsInception = false
  ) {
    if (recordsInception) await expectInception(callback, transferId);
    const requestId = await incept(callback, transferId, caller);
    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      requestId,
      keys,
      payment.target,
      TRANSACTION
    );
    expect(await payment.stateOf(callback.target, transferId)).to.equal(READY);
    return requestId;
  }

  async function verify(callback, transferId) {
    await payment.connect(buyer).requestVerification(callback.target, transferId);
    const requestId = await buyerOracle.lastRequestId();
    await buyerOracle.connect(buyerAdapter).fulfillEncryptedKeysVerification(
      requestId,
      true,
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    expect(await payment.verificationStateOf(callback.target, transferId)).to.equal(2);
    return requestId;
  }

  async function deployAssetContract() {
    const asset = await (await ethers.getContractFactory("PontesAssetConsumer")).deploy(
      payment.target,
      seller.address,
      buyer.address,
      requester.address,
      buyer.address
    );
    await asset.waitForDeployment();
    return asset;
  }

  async function deployAsset(transferId) {
    const asset = await deployAssetContract();
    await asset.connect(buyer)[ASYNC_INCEPT](
      transferId,
      ASSET_AMOUNT,
      seller.address,
      buyer.address,
      TRANSACTION,
      payment.target
    );
    return asset;
  }

  it("emits TokenLocked when a classic confirmation locks the asset", async function () {
    const transferId = 9;
    const asset = await deployAssetContract();
    await asset.connect(buyer)[CLASSIC_INCEPT](
      transferId,
      ASSET_AMOUNT,
      seller.address,
      buyer.address,
      TRANSACTION,
      CANCELLATION_HASH,
      ENCRYPTED_CANCELLATION
    );

    await expect(asset.connect(requester)[CLASSIC_CONFIRM](
      transferId,
      ASSET_AMOUNT,
      seller.address,
      buyer.address,
      TRANSACTION,
      EXECUTION_HASH,
      ENCRYPTED_EXECUTION
    )).to.emit(asset, "TokenLocked").withArgs(transferId);
  });

  it("lets an authorized requester use a newly deployed callback and revoke only future legs", async function () {
    await expect(payment.connect(outsider).setRequester(outsider.address, true))
      .to.be.revertedWithCustomError(payment, "NotOwner");

    // The callback is deployed after requester authorization; there is no callback allowlist.
    const callback = await deployRecorder();
    await expectInception(callback, 1);
    await fund(requester, GENERATION_COST);
    const generationId = await incept(callback, 1);
    expect(await payment.stateOf(callback.target, 1)).to.equal(GENERATING);

    await payment.setRequester(requester.address, false);
    const laterCallback = await deployRecorder();
    await expect(payment.connect(requester)[ASYNC_INCEPT](
      2,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      TRANSACTION,
      laterCallback.target
    )).to.be.revertedWithCustomError(payment, "IneligibleRequester");

    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      generationId,
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    expect(await payment.stateOf(callback.target, 1)).to.equal(READY);
  });

  it("supports callback-free legs and rejects generated zero hashes", async function () {
    await fund(requester, GENERATION_COST * 2n);

    await payment.connect(requester)[ASYNC_INCEPT](
      2,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      TRANSACTION,
      ZeroAddress
    );
    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      await sellerOracle.lastRequestId(),
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    expect(await payment.stateOf(ZeroAddress, 2)).to.equal(READY);

    await payment.connect(requester)[ASYNC_INCEPT](
      3,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      TRANSACTION,
      ZeroAddress
    );
    const unusableKeys = generatedKeys();
    unusableKeys[0] = [KEY_EXECUTION, ENCRYPTED_EXECUTION, ZeroHash];
    await expect(sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      await sellerOracle.lastRequestId(),
      unusableKeys,
      payment.target,
      TRANSACTION
    )).to.be.revertedWithCustomError(sellerOracle, "CallbackReverted");
    expect(await payment.stateOf(ZeroAddress, 3)).to.equal(GENERATING);
  });

  it("runs generate -> direct buyer verification -> confirm -> settle with exact contexts", async function () {
    const transferId = 10;
    const asset = await deployAsset(transferId);
    await fund(requester, GENERATION_COST + VERIFICATION_COST + FEE_DECRYPT);
    const generationId = await incept(asset, transferId);
    await expect(sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      generationId,
      generatedKeys(),
      payment.target,
      TRANSACTION
    )).to.emit(asset, "TokenLocked").withArgs(transferId);
    expect(await payment.stateOf(asset.target, transferId)).to.equal(READY);
    expect(await asset.stateOf(transferId)).to.equal(ASSET_LOCKED);

    await expect(asset.completeLock(transferId)).to.not.emit(asset, "TokenLocked");

    await expect(payment.connect(outsider).requestVerification(asset.target, transferId))
      .to.be.revertedWithCustomError(payment, "UnauthorizedOperator");
    await verify(asset, transferId);

    await expect(payment.connect(buyer).confirmTransfer(
      ...completionArgs(asset, transferId, `${TRANSACTION}00`)
    )).to.be.revertedWithCustomError(payment, "InvalidTransferContext");
    await payment.connect(buyer).confirmTransfer(...completionArgs(asset, transferId));
    expect(await payment.stateOf(asset.target, transferId)).to.equal(EXECUTION_PENDING);

    const executionId = await buyerOracle.lastRequestId();
    // The payment contract deliberately treats the asset callback as best effort.
    // Give the nested callback explicit headroom because gas estimation therefore
    // cannot infer the gas needed by transferWithKey.
    await buyerOracle.connect(buyerAdapter).fulfillDecryption(
      executionId,
      EXECUTION_KEY,
      { gasLimit: 1_500_000 }
    );
    expect(await payment.stateOf(asset.target, transferId)).to.equal(SETTLED);
    expect(await asset.stateOf(transferId)).to.equal(ASSET_CLAIMED);
    expect(await payment.feeBalance(requester.address)).to.equal(0);
  });

  it("cancels a ready payment and relays the cancellation key to the asset", async function () {
    const transferId = 11;
    const asset = await deployAsset(transferId);
    await fund(requester, GENERATION_COST + FEE_DECRYPT);
    await ready(asset, transferId);

    await payment.connect(requester).cancelAndDecrypt(...completionArgs(asset, transferId));
    const cancellationId = await sellerOracle.lastRequestId();
    await sellerOracle.connect(sellerAdapter).fulfillDecryption(
      cancellationId,
      CANCELLATION_KEY,
      { gasLimit: 1_500_000 }
    );

    expect(await payment.stateOf(asset.target, transferId)).to.equal(CANCELLED);
    expect(await asset.stateOf(transferId)).to.equal(ASSET_RECLAIMED);
  });

  it("freezes oracle routing per leg and isolates every requester's fee balance", async function () {
    const callback = await deployRecorder();
    await fund(requester, GENERATION_COST + VERIFICATION_COST + FEE_DECRYPT);
    await ready(callback, 20, requester, generatedKeys(), true);

    const Oracle = await ethers.getContractFactory("KeyDecryptionOracle");
    const newSellerOracle = await Oracle.deploy(outsider.address, 0, true);
    const newBuyerOracle = await Oracle.deploy(outsider.address, 0, true);
    await newSellerOracle.waitForDeployment();
    await newBuyerOracle.waitForDeployment();
    await payment.setOracleFor(seller.address, newSellerOracle.target);
    await payment.setOracleFor(buyer.address, newBuyerOracle.target);

    expect(await payment.oraclesOf(callback.target, 20)).to.deep.equal([
      sellerOracle.target,
      buyerOracle.target
    ]);
    await verify(callback, 20);
    expect(await newBuyerOracle.lastRequestId()).to.equal(0);
    await payment.connect(requester).cancelAndDecrypt(...completionArgs(callback, 20));
    expect(await newSellerOracle.lastRequestId()).to.equal(0);
    await sellerOracle.connect(sellerAdapter).fulfillDecryption(
      await sellerOracle.lastRequestId(),
      CANCELLATION_KEY
    );

    // A second requester cannot spend the first requester's funds.
    await payment.setOracleFor(seller.address, sellerOracle.target);
    await payment.setOracleFor(buyer.address, buyerOracle.target);
    await payment.setRequester(otherRequester.address, true);
    const first = await deployRecorder();
    const second = await deployRecorder();
    await expectInception(first, 21);
    await expectInception(second, 22);
    await fund(requester, GENERATION_COST);
    await fund(otherRequester, GENERATION_COST - 1n);
    await incept(first, 21);
    await expect(incept(second, 22, otherRequester))
      .to.be.revertedWithCustomError(payment, "InsufficientOracleFee")
      .withArgs(otherRequester.address, GENERATION_COST, GENERATION_COST - 1n);
    await fund(otherRequester, 1n);
    await incept(second, 22, otherRequester);
    expect(await payment.feeBalance(requester.address)).to.equal(0);
    expect(await payment.feeBalance(otherRequester.address)).to.equal(0);
  });

  it("exposes active adapter authorization, durable tombstones, and cancel-denial recovery", async function () {
    const transferId = 30;
    const callback = await deployRecorder();
    await expectInception(callback, transferId);
    await fund(requester, GENERATION_COST + VERIFICATION_COST + FEE_DECRYPT * 2n);

    const generationId = await incept(callback, transferId);
    expect(await payment.paymentRequestContext(sellerOracle.target, generationId))
      .to.deep.equal([1n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.authorizedPaymentRequest(
      sellerOracle.target,
      generationId,
      transferId,
      1,
      TRANSACTION,
      "0x"
    )).to.deep.equal([true, true]);
    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      generationId,
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    expect(await payment.paymentRequestContext(sellerOracle.target, generationId))
      .to.deep.equal([1n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.authorizedPaymentRequest(
      sellerOracle.target,
      generationId,
      transferId,
      1,
      TRANSACTION,
      "0x"
    )).to.deep.equal([true, false]);

    const verificationId = await verify(callback, transferId);
    expect(await payment.paymentRequestContext(buyerOracle.target, verificationId))
      .to.deep.equal([4n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.authorizedPaymentRequest(
      buyerOracle.target,
      verificationId,
      transferId,
      4,
      TRANSACTION,
      ENCRYPTED_EXECUTION
    )).to.deep.equal([false, false]);

    await payment.connect(requester).cancelAndDecrypt(...completionArgs(callback, transferId));
    const cancellationId = await sellerOracle.lastRequestId();
    expect(await payment.paymentRequestContext(sellerOracle.target, cancellationId))
      .to.deep.equal([3n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.authorizedPaymentRequest(
      sellerOracle.target,
      cancellationId,
      transferId,
      3,
      TRANSACTION,
      ENCRYPTED_CANCELLATION
    )).to.deep.equal([true, true]);

    await sellerOracle.connect(sellerAdapter).fulfillDecryption(cancellationId, "0x");
    expect(await payment.paymentRequestContext(sellerOracle.target, cancellationId))
      .to.deep.equal([3n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.authorizedPaymentRequest(
      sellerOracle.target,
      cancellationId,
      transferId,
      3,
      TRANSACTION,
      ENCRYPTED_CANCELLATION
    )).to.deep.equal([true, false]);

    const recoveryId = await buyerOracle.lastRequestId();
    expect(await payment.paymentRequestContext(buyerOracle.target, recoveryId))
      .to.deep.equal([2n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.isPaymentRecoveryRequest(buyerOracle.target, recoveryId)).to.equal(true);
    expect(await payment.authorizedPaymentRequest(
      buyerOracle.target,
      recoveryId,
      transferId,
      2,
      TRANSACTION,
      ENCRYPTED_EXECUTION
    )).to.deep.equal([true, true]);
    await buyerOracle.connect(buyerAdapter).fulfillDecryption(recoveryId, EXECUTION_KEY);
    expect(await payment.stateOf(callback.target, transferId)).to.equal(SETTLED);
    expect(await payment.paymentRequestContext(buyerOracle.target, recoveryId))
      .to.deep.equal([2n, sellerOracle.target, buyerOracle.target]);
    expect(await payment.authorizedPaymentRequest(
      buyerOracle.target,
      recoveryId,
      transferId,
      2,
      TRANSACTION,
      ENCRYPTED_EXECUTION
    )).to.deep.equal([true, false]);
  });

  it("returns zero context for unknown requests and reverses routing with payment direction", async function () {
    expect(await payment.paymentRequestContext(sellerOracle.target, 999))
      .to.deep.equal([0n, ZeroAddress, ZeroAddress]);

    const transferId = 31;
    await fund(requester, GENERATION_COST);
    await payment.connect(requester)[ASYNC_INCEPT](
      transferId,
      PAYMENT_AMOUNT,
      seller.address,
      buyer.address,
      TRANSACTION,
      ZeroAddress
    );
    const generationId = await buyerOracle.lastRequestId();
    const reversed = [1n, buyerOracle.target, sellerOracle.target];
    expect(await payment.paymentRequestContext(buyerOracle.target, generationId))
      .to.deep.equal(reversed);

    await buyerOracle.connect(buyerAdapter).fulfillEncryptedHashedKeysGeneration(
      generationId,
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    expect(await payment.paymentRequestContext(buyerOracle.target, generationId))
      .to.deep.equal(reversed);
  });

  it("keeps equal ids independent across parallel callbacks", async function () {
    const transferId = 40;
    const first = await deployRecorder();
    const second = await deployRecorder();
    await expectInception(first, transferId);
    await expectInception(second, transferId);
    await fund(requester, GENERATION_COST * 2n);

    const firstRequest = await incept(first, transferId);
    const secondRequest = await incept(second, transferId);
    expect(await payment.legKeyOf(first.target, transferId))
      .to.not.equal(await payment.legKeyOf(second.target, transferId));

    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      secondRequest,
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      firstRequest,
      generatedKeys(),
      payment.target,
      TRANSACTION
    );
    expect(await payment.stateOf(first.target, transferId)).to.equal(READY);
    expect(await payment.stateOf(second.target, transferId)).to.equal(READY);
    expect(await first.completions()).to.equal(1);
    expect(await second.completions()).to.equal(1);
  });

  it("supports namespaced direct payments with frozen routing and retry-safe delivery", async function () {
    const Product = await ethers.getContractFactory("DirectPaymentProductStub");
    const product = await Product.deploy(payment.target, buyer.address);
    await product.waitForDeployment();
    const requestId = await product.requestId(1);

    await payment.setRequester(product.target, true);
    await payment.setDirectPaymentAgent(buyer.address, agent.address);
    await payment.setPaymentBic(buyer.address, "BUYRDEFFXXX");
    await payment.setPaymentBic(seller.address, "MARKDEFFXXX");
    await product.request(requestId, buyer.address, seller.address, 900_000, 2);

    await payment.setDirectPaymentAgent(buyer.address, outsider.address);
    await payment.setPaymentBic(seller.address, "CHANGEDBIC");
    const snapshot = await payment.directPayments(requestId);
    expect(snapshot.agent).to.equal(agent.address);
    expect(await payment.directPaymentBics(requestId)).to.deep.equal([
      "BUYRDEFFXXX",
      "MARKDEFFXXX"
    ]);

    await expect(payment.connect(outsider).fulfillDirectPayment(requestId))
      .to.be.revertedWithCustomError(payment, "UnauthorizedOperator");
    await product.setCallbackBehavior(1);
    await payment.connect(agent).fulfillDirectPayment(requestId);
    expect(await payment.isDirectPaymentSettled(requestId)).to.equal(true);
    expect((await payment.directPayments(requestId)).delivered).to.equal(false);

    await product.setCallbackBehavior(2);
    await payment.connect(outsider).retryDirectPaymentDelivery(
      requestId,
      { gasLimit: 1_000_000 }
    );
    expect(await product.notifications()).to.equal(1);
    expect((await payment.directPayments(requestId)).delivered).to.equal(true);
    await payment.connect(agent).fulfillDirectPayment(requestId);
    expect(await product.notifications()).to.equal(1);

    const otherProduct = await Product.deploy(payment.target, outsider.address);
    await otherProduct.waitForDeployment();
    await payment.setRequester(otherProduct.target, true);
    await expect(otherProduct.request(requestId, buyer.address, seller.address, 100, 2))
      .to.be.revertedWithCustomError(payment, "InvalidId");
    await expect(otherProduct.request(
      await otherProduct.requestId(1),
      buyer.address,
      seller.address,
      101,
      3
    )).to.be.revertedWithCustomError(payment, "InvalidDirectPaymentAmount");
  });

  it("validates direct-payment routes before freezing them and preserves pending authority", async function () {
    const product = await (await ethers.getContractFactory("DirectPaymentProductStub"))
      .deploy(payment.target, buyer.address);
    await product.waitForDeployment();
    await payment.setRequester(product.target, true);
    await payment.setPaymentBic(buyer.address, "BUYRDEFFXXX");
    await payment.setPaymentBic(seller.address, "MARKDEFFXXX");
    const firstId = await product.requestId(1);
    const nextId = await product.requestId(2);

    // Configuration is staged freely; only a valid external authority can become a live route.
    await payment.setDirectPaymentAgent(buyer.address, payment.target);
    await expect(product.request(firstId, buyer.address, seller.address, 900_000, 2))
      .to.be.revertedWithCustomError(payment, "TrustDomainsMustDiffer");
    expect((await payment.directPayments(firstId)).requester).to.equal(ZeroAddress);
    await expect(payment.connect(agent).fulfillDirectPayment(firstId))
      .to.be.revertedWithCustomError(payment, "UnknownDirectPayment");

    await payment.setDirectPaymentAgent(buyer.address, agent.address);
    await product.request(firstId, buyer.address, seller.address, 900_000, 2);
    await payment.setDirectPaymentAgent(buyer.address, payment.target);
    expect((await payment.directPayments(firstId)).agent).to.equal(agent.address);
    await expect(product.request(nextId, buyer.address, seller.address, 900_000, 2))
      .to.be.revertedWithCustomError(payment, "TrustDomainsMustDiffer");
    await expect(payment.connect(outsider).fulfillDirectPayment(firstId))
      .to.be.revertedWithCustomError(payment, "UnauthorizedOperator");
    await payment.connect(agent).fulfillDirectPayment(firstId);
    expect(await payment.isDirectPaymentSettled(firstId)).to.equal(true);

    await payment.setDirectPaymentAgent(buyer.address, ZeroAddress);
    await expect(product.request(nextId, buyer.address, seller.address, 900_000, 2))
      .to.be.revertedWithCustomError(payment, "UnregisteredDirectPaymentAgent");
    await payment.setDirectPaymentAgent(buyer.address, outsider.address);
    await product.request(nextId, buyer.address, seller.address, 900_000, 2);
    await payment.connect(outsider).fulfillDirectPayment(nextId);
    expect(await payment.isDirectPaymentSettled(nextId)).to.equal(true);

    await expect(payment.setDirectPaymentAgent(ZeroAddress, agent.address))
      .to.be.revertedWithCustomError(payment, "ZeroAddress");
  });

  it("separates both oracle authorities from each other and the payment contract", async function () {
    const callback = await deployRecorder();
    const transferId = 49;
    await fund(requester, GENERATION_COST);

    for (const [generation, execution] of [
      [sellerOracle.target, sellerOracle.target],
      [payment.target, buyerOracle.target],
      [sellerOracle.target, payment.target]
    ]) {
      await payment.setOracleFor(seller.address, generation);
      await payment.setOracleFor(buyer.address, execution);
      await expect(incept(callback, transferId))
        .to.be.revertedWithCustomError(payment, "TrustDomainsMustDiffer");
      expect(await payment.stateOf(callback.target, transferId)).to.equal(0);
      expect(await payment.feeBalance(requester.address)).to.equal(GENERATION_COST);
    }

    await payment.setOracleFor(seller.address, sellerOracle.target);
    await payment.setOracleFor(buyer.address, buyerOracle.target);
    await incept(callback, transferId);
    expect(await payment.stateOf(callback.target, transferId)).to.equal(GENERATING);
  });

  it("accepts production-sized encrypted references in the asset callback", async function () {
    const transferId = 50;
    const asset = await deployAsset(transferId);
    const executionReference = `0x${"ab".repeat(1790)}`;
    const cancellationReference = `0x${"cd".repeat(1793)}`;
    await fund(requester, GENERATION_COST);

    await payment.connect(requester)[ASYNC_INCEPT](
      transferId,
      PAYMENT_AMOUNT,
      buyer.address,
      seller.address,
      TRANSACTION,
      asset.target
    );
    await sellerOracle.connect(sellerAdapter).fulfillEncryptedHashedKeysGeneration(
      await sellerOracle.lastRequestId(),
      generatedKeys(executionReference, cancellationReference),
      payment.target,
      TRANSACTION,
      { gasLimit: 10_000_000 }
    );

    expect(await payment.stateOf(asset.target, transferId)).to.equal(READY);
    expect(await asset.stateOf(transferId)).to.equal(ASSET_LOCKED);
  });
});
