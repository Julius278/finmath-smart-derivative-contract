import { defineConfig } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";

// Tests run on an isolated chain with normal deployment-size limits.
export default defineConfig({
  plugins: [hardhatToolboxMochaEthers],
  defaultNetwork: "default",
  networks: {
    default: { type: "edr-simulated", chainType: "l1", allowUnlimitedContractSize: false }
  },
  solidity: {
    compilers: ["0.8.24", "0.8.26"].map(version => ({
      version, settings: { optimizer: { enabled: true, runs: 200 } }
    })),
    overrides: {
      "contracts/smartProductFramework/products/ProductLib.sol": {
        version: "0.8.26",
        settings: { evmVersion: "shanghai", optimizer: { enabled: true, runs: 200 } }
      },
      "contracts/examples/fixedRateBond/FixedRateBondLib.sol": {
        version: "0.8.26",
        settings: { evmVersion: "shanghai", optimizer: { enabled: true, runs: 200 } }
      },
      ...Object.fromEntries(["FixedRateBond", "FixedRateBondFactory"].map(name => [
        `contracts/examples/fixedRateBond/${name}.sol`,
        {
          version: "0.8.26",
          settings: {
            evmVersion: "shanghai", viaIR: true,
            metadata: { bytecodeHash: "none" },
            optimizer: { enabled: true, runs: 1 }
          }
        }
      ]))
    }
  },
  test: { mocha: { timeout: 120000 } }
});
