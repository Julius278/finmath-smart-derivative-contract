# Smart Product Framework

This directory contains the Smart Product Framework and demo implementations
originally distributed through the ERC-8100 repository
(`representable-contract-state`). The maintained core includes product definitions,
factories, client approval, indications, XML representation and settlement helpers.
The original bond and interest-rate-swap demos and the FX atomic swap demo have
separate Foundry projects.
The maintained [fixed-rate bond example](contracts/examples/fixedRateBond/README.md)
runs with the core Hardhat tests and uses an existing ERC-20 asset and a local
payment adapter for delivery, coupon payments and redemption between participant wallets.

## Build and test

Use Node.js 22.13 or later for the core package:

```sh
npm ci
npm run build
npm test
```

The lockfile pins dependencies. Hardhat downloads the Solidity compilers on the
first build. Tests use an isolated chain with normal deployment-size limits and
require no RPC endpoint, wallet or deployment configuration.

Run the original product demos with Node.js and Foundry:

```sh
cd examples/erc8100-products
npm ci
forge test
```

The independent [FX atomic swap demo](examples/fx-atomic-swap/README.md) needs Foundry:

```sh
cd examples/fx-atomic-swap
forge test
```

Each `cd` command above starts from `framework/`. The example guides describe the
product lifecycles and ERC-8100 representation. Their existing source copies in
`representable-contract-state` remain available.

## Contents

| Location | Purpose |
| --- | --- |
| `contracts/smartProductFramework/` | Core product interfaces, definitions, factories, client registry and indications |
| `contracts/erc8100/` | Representable-state interfaces and text resources |
| `contracts/dvp/` | Settlement and decryption helpers |
| [`contracts/examples/fixedRateBond/`](contracts/examples/fixedRateBond/README.md) | FixedRateBond, its library and factory, with local demo adapters |
| `contracts/mocks/`, `test/` | Core framework, representation and settlement regression tests |
| [`examples/erc8100-products/`](examples/erc8100-products/README.md) | Original bond and interest-rate-swap framework demos, with their own dependencies and tests |
| [`examples/fx-atomic-swap/`](examples/fx-atomic-swap/README.md) | FX atomic swap contracts, tests and renderer walkthrough |
| `origins/representable-contract-state/` | Original extracted source history and reference material |
| `origins/product-framework/` | Retained source license |

The original product demos use their original framework interfaces and an isolated
OpenZeppelin dependency. They are tested separately from the maintained core package.
The general ERC-8100 renderer remains a separate project and service.

Use `getActiveTradeRequests` for a definition's active requests,
`tradeRequestState` for a known request, and `isRegisteredProduct` to verify an
issued contract. Index the registry events for historical discovery.
The active-request getter is unbounded and intended for small active request sets.
Definition discovery remains paginated and bounded.

## History and licensing

The 98 original ERC-8100 framework commits by Christian Fries (`cfries`) and
Raphael Prandtl (`RKP1101`), including the framework branch, retain their history
and author dates. Subsequent integration changes are consolidated into one commit.
Use a merge commit to retain that history when integrating this migration.

Preserve individual SPDX identifiers and license notices. Source licenses and
notices are retained under `origins/`; dependency licenses remain applicable.
The private npm package metadata does not replace individual file licenses.
