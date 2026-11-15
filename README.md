# Smart Financial Contracts

Reference implementations and reusable infrastructure for smart financial products.
This project continues the history of `finmath-smart-derivative-contract` and brings
together the Smart Product Framework, smart derivative contracts, and valuation tools.
All Solidity packages live under [`solidity/`](solidity/README.md), with separate
compiler and dependency configurations for each package.

## Components

| Component | Location | Build |
| --- | --- | --- |
| Smart Product Framework and demo implementations | [`solidity/framework/`](solidity/framework/README.md) | `cd solidity/framework && npm ci && npm test` |
| Fixed-rate bond with local demo adapters | [`solidity/framework/contracts/examples/fixedRateBond/`](solidity/framework/contracts/examples/fixedRateBond/README.md) | Included in the framework tests |
| Original ERC-8100 bond and interest-rate-swap demos | [`solidity/examples/erc8100-products/`](solidity/examples/erc8100-products/README.md) | `cd solidity/examples/erc8100-products && npm ci && forge test` |
| FX atomic swap demo | [`solidity/examples/fx-atomic-swap/`](solidity/examples/fx-atomic-swap/README.md) | `cd solidity/examples/fx-atomic-swap && forge test` |
| Java valuation oracle, derivative models, XML schemas and demos | [`src/`](src/), [`pom.xml`](pom.xml) | Java 17: `mvn clean verify` |
| Derivative service frontend | [`frontend/`](frontend/) | `cd frontend && npm ci && npm run build` |
| Derivative contracts | [`solidity/derivatives/`](solidity/derivatives/doc/README.md) | `cd solidity/derivatives && npm ci --ignore-scripts && npm test` |
| Public ERC reference snapshots | [`solidity/ercs/`](solidity/ercs/) | Reference material |
| Existing project documentation | [`src/site/markdown/`](src/site/markdown/index.md) | `mvn site` |

The framework is an independent Node package. It does not change the existing Maven
project, Java package names, service endpoints, frontend paths or published Maven
coordinates (`net.finmath:finmath-smart-derivative-contract`). Existing Docker image
names and the [published documentation](https://www.finmath.net/smart-financial-contracts/)
remain separate from the GitHub repository name.

## Smart Product Framework

The Smart Product Framework and its demo implementations were originally
distributed through the ERC-8100 repository (`representable-contract-state`).
The framework provides product factories and definitions, a client registry,
product indications, XML-representable product state and settlement helpers. See the [framework guide](solidity/framework/README.md) and
[migration record](docs/migration/smart-financial-contracts.md) for repository layout,
compatibility and validation.

The [original ERC-8100 product demos](solidity/examples/erc8100-products/README.md)
provide runnable bond and interest-rate-swap examples with their original framework.

The maintained [fixed-rate bond example](solidity/framework/contracts/examples/fixedRateBond/README.md)
uses `FixedRateBond` and `FixedRateBondLib` with an existing ERC-20 asset and a
local cash-settlement adapter. Its tests run agreement, asset delivery, coupons
and redemption with real transfers between participant wallets on an isolated chain.

The [FX atomic swap demo](solidity/examples/fx-atomic-swap/README.md) includes
ERC-20 settlement contracts, a factory, local tests and an ERC-8100 lifecycle
walkthrough. Its existing copy in `representable-contract-state` remains available.

The general ERC-8100 renderer remains available from
[Representable Contract State](https://gitlab.com/finmath/representable-contract-state).
The new package contains the Solidity interfaces and resources needed by the
framework; it does not replace the renderer service.

## Valuation service

With Java 17 and Maven installed, run `mvn spring-boot:run` from the repository root.
See the [valuation service documentation](src/site/markdown/valuationservice.md) and
[Docker instructions](src/site/markdown/dockerbuild.md) for configuration and usage.

## History and licensing

The original derivative repository history remains intact. The framework retains
98 commits from its original ERC-8100 development, including the framework branch,
by Christian Fries (`cfries`) and Raphael Prandtl (`RKP1101`). Later framework
updates and the repository migration are consolidated into one integration
commit. The merged history remains available across the package moves.

See [LICENSE.txt](LICENSE.txt), the framework's source notices and individual SPDX
headers. Components retain their original licenses and license notices.
