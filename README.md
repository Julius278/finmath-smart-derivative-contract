# Smart Financial Contracts

Reference implementations and reusable infrastructure for smart financial products.
This project continues the history of `finmath-smart-derivative-contract` and brings
together the Smart Product Framework, smart derivative contracts, and valuation tools.

## Components

| Component | Location | Build |
| --- | --- | --- |
| Smart Product Framework and demo implementations | [`framework/`](framework/README.md) | `cd framework && npm ci && npm test` |
| Fixed-rate bond with local demo adapters | [`framework/contracts/examples/fixedRateBond/`](framework/contracts/examples/fixedRateBond/README.md) | Included in the framework tests |
| Original ERC-8100 bond and interest-rate-swap demos | [`framework/examples/erc8100-products/`](framework/examples/erc8100-products/README.md) | `cd framework/examples/erc8100-products && npm ci && forge test` |
| FX atomic swap demo | [`framework/examples/fx-atomic-swap/`](framework/examples/fx-atomic-swap/README.md) | `cd framework/examples/fx-atomic-swap && forge test` |
| Java valuation oracle, derivative models, XML schemas and demos | [`src/`](src/), [`pom.xml`](pom.xml) | Java 17: `mvn clean verify` |
| Derivative service frontend | [`frontend/`](frontend/) | `cd frontend && npm ci && npm run build` |
| Existing Solidity contracts and ERC reference implementations | [`solidity/`](solidity/) | `cd solidity && npm ci && npm test` |
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
product indications, XML-representable product state and settlement helpers. See the [framework guide](framework/README.md) and
[migration record](docs/migration/smart-financial-contracts.md) for repository layout,
compatibility and validation.

The [original ERC-8100 product demos](framework/examples/erc8100-products/README.md)
provide runnable bond and interest-rate-swap examples with their original framework.

The maintained [fixed-rate bond example](framework/contracts/examples/fixedRateBond/README.md)
uses `FixedRateBond` and `FixedRateBondLib` with an existing ERC-20 asset and a
local cash-settlement adapter. Its tests run agreement, asset delivery, coupons
and redemption with real transfers between participant wallets on an isolated chain.

The [FX atomic swap demo](framework/examples/fx-atomic-swap/README.md) includes
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
commit. Use a merge commit to retain the original framework history when
integrating this migration.

See [LICENSE.txt](LICENSE.txt), the framework's source notices and individual SPDX
headers. Components retain their original licenses and license notices.
