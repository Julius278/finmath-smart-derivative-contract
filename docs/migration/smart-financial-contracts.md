# Smart Financial Contracts: layout and compatibility

## Repository and documentation URLs

The repository is `finmath/smart-financial-contracts`. The former GitHub URL
redirects to it. Documentation is published at
`https://www.finmath.net/smart-financial-contracts/`; existing documentation URLs
are preserved with browser redirects and unchanged static assets on finmath.net.

## Components

- `solidity/framework/contracts/` contains the maintained core framework, ERC-8100 resources
  and settlement helpers; `solidity/framework/test/` tests these components.
- `solidity/framework/contracts/examples/fixedRateBond/` adds the maintained bond, its library
  and factory with an existing ERC-20 asset and a local payment adapter. It exercises
  delivery, coupon payments and redemption between participant wallets. Its guide
  describes operator trust and the single-attempt coupon limit.
- `solidity/examples/erc8100-products/` runs the original bond and interest-rate-swap
  demos with their original framework and isolated dependencies.
- `solidity/examples/fx-atomic-swap/` contains the standalone FX demo and walkthrough.
- `solidity/origins/` preserves original framework history and license notices.
- `solidity/derivatives/` contains the derivative contracts and their Hardhat build.
- `solidity/ercs/` contains public ERC reference snapshots.
- The root Maven project, Java packages and frontend retain their paths and
  published artifact identities.
- The general ERC-8100 renderer remains a separate project and dependency. The demo
  copies in `representable-contract-state` have not been removed.

The Maven coordinates remain `net.finmath:finmath-smart-derivative-contract`.
Existing Docker image names and service endpoints are unchanged. Legacy snapshot
publishing is manual until its repository configuration is updated.

## Development history

The original derivative history remains unchanged. The migration retains 98
commits from the original ERC-8100 framework development, including the framework
branch, by Christian Fries (`cfries`) and Raphael Prandtl (`RKP1101`). Those commits
retain their contents, messages, author dates and relationships, with canonical
contributor identities. Later integration changes are consolidated into one commit.
The merged history remains unchanged by the subsequent package moves.

License texts, SPDX identifiers and license notices remain intact.

## Build and validation

Use Java 17 for the root Maven project, Node.js 22.13 or newer for the framework
and frontend, Node.js 16 for the legacy Solidity package, and Foundry 1.5.0 for
the standalone demos.

```sh
mvn clean verify
(cd solidity/framework && npm ci && npm test)
(cd solidity/examples/erc8100-products && npm ci && forge test)
(cd solidity/examples/fx-atomic-swap && forge test)
(cd frontend && npm ci && npm run build)
(cd solidity/derivatives && npm ci --ignore-scripts && npm test)
```

Validation of the integrated code:

- Core framework and local fixed-rate bond example: 36 Solidity files compiled and
  74 tests passed with normal deployment-size limits enabled. All generated contracts
  fit runtime and initcode limits; the bond factory runtime is 20,181 bytes.
- Original product demos: 11 factory, registry, representation and lifecycle tests
  passed in their isolated Foundry project.
- FX atomic swap: 26 Foundry tests passed, including fuzz coverage.
- Java: 86 tests, no failures or errors, four existing skips.
- Legacy Solidity: 19 files compiled and all five active tests passed.
- Frontend: production build and three ChromeHeadless compatibility tests passed
  in `Europe/Berlin`, including saved counterparties and date round trips.
- Docker: executable JAR packaging verified; a Docker daemon was unavailable for
  an image build or container execution.
