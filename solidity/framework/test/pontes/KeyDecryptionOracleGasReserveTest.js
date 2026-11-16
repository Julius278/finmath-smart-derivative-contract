import hre from "hardhat";
import { expect } from "chai";
import { toBeHex, zeroPadValue } from "ethers";

describe("KeyDecryptionOracle gas reserve", function () {
  const BATCH_SIZE = 32;
  const MIN_CONFIGURABLE_RESERVE = 10_000;
  const TRANSACTION = "0x1234";

  let ethers;
  let owner;
  let oracleAccount;
  let oracle;
  let callback;

  beforeEach(async function () {
    ({ ethers } = await hre.network.create());
    [owner, oracleAccount] = await ethers.getSigners();

    oracle = await (await ethers.getContractFactory("KeyDecryptionOracle"))
      .deploy(oracleAccount.address, 0, true);
    callback = await (await ethers.getContractFactory("GasBurningKeyDecryptionCallback"))
      .deploy();
    await oracle.waitForDeployment();
    await callback.waitForDeployment();
    await oracle.setGasReserve(MIN_CONFIGURABLE_RESERVE);
  });

  function keyId(index) {
    return zeroPadValue(toBeHex(index + 1), 32);
  }

  function generatedKeys() {
    return Array.from({ length: BATCH_SIZE }, (_, index) => [
      keyId(index),
      toBeHex(index + 1),
      toBeHex(index + 101)
    ]);
  }

  it("retains enough gas to consume a maximum generation batch after a gas-griefing callback", async function () {
    const keys = generatedKeys();
    await oracle.requestGenerateEncryptedHashedKeys(
      1,
      callback.target,
      owner.address,
      TRANSACTION,
      keys.map(([id]) => id)
    );

    await expect(oracle.connect(oracleAccount).fulfillEncryptedHashedKeysGeneration(
      1,
      keys,
      owner.address,
      TRANSACTION,
      { gasLimit: 3_000_000 }
    )).to.emit(oracle, "CallbackSucceeded");

    await expect(oracle.connect(oracleAccount).fulfillEncryptedHashedKeysGeneration(
      1,
      keys,
      owner.address,
      TRANSACTION
    )).to.be.revertedWithCustomError(oracle, "UnknownRequest");
  });

  it("retains enough gas to consume a maximum verification batch after a gas-griefing callback", async function () {
    const keys = generatedKeys();
    await oracle.requestVerifyEncryptedKeys(
      2,
      keys.map(([id, encryptedKey]) => [id, encryptedKey]),
      callback.target
    );

    await expect(oracle.connect(oracleAccount).fulfillEncryptedKeysVerification(
      1,
      true,
      keys,
      owner.address,
      TRANSACTION,
      { gasLimit: 3_000_000 }
    )).to.emit(oracle, "CallbackSucceeded");

    await expect(oracle.connect(oracleAccount).fulfillEncryptedKeysVerification(
      1,
      true,
      keys,
      owner.address,
      TRANSACTION
    )).to.be.revertedWithCustomError(oracle, "UnknownRequest");
  });
});
