# Original ERC-8100 product demos

This standalone Foundry project runs the original Smart Product Framework
`SimpleBond` and `InterestRateSwap` examples from `representable-contract-state`.
The 20 Solidity source files and four XML/XSLT resources are copied unchanged
from the retained original framework sources, with their licenses and notices.

`SimpleBond` demonstrates negotiated notional and maturity. `InterestRateSwap`
adds currency, fixed-rate payer/receiver roles and forward/discount curve symbols.
Both use a product definition registry, product factories, client eligibility,
immutable text resources, and a request/inception/confirmation lifecycle. They
expose ERC-8100 XML templates for product and registry state.

These demos cover product state and agreement. Cash/asset settlement and swap
valuation are outside their workflow.

## Build and run

Use Node.js 22 or newer and Foundry. CI uses Foundry 1.5.0. From this directory:

```sh
npm ci
forge test -vv
forge build --sizes
```

The package pins OpenZeppelin Contracts 5.1.0 and Solady 0.1.26 in its own
`node_modules`; the main framework package's dependencies are independent.
Compilation uses Solidity 0.8.24, the Paris EVM target, IR compilation and 200
optimizer runs, matching the original Java demo's deployment settings.

The tests run on Foundry's local simulated EVM. They require no external chain,
wallet, Java service or renderer. Solidity dependencies and the compiler are
downloaded on the first build.

For a full call trace of either example:

```sh
forge test --match-test testSimpleBondRegistryFactoryAndLifecycle -vvvv
forge test --match-test testInterestRateSwapRegistryFactoryAndLifecycle -vvvv
```

## Demo workflow

The test setup publishes the original terms and documentation resources, creates
the factories and product definitions, registers an example client, and assigns
a curve indication to the bond definition. The bond resources are published in
stages; the swap resources use one-shot publication. Both approaches verify the
resource content hashes before finalization.

The client requests a product through the registry, which deploys it through the
corresponding factory. The client may amend terms while the product is requested.
The provider incepts the current terms hash, and the client confirms that exact
hash to activate the trade. Either party can cancel before activation.

The 11 tests cover both workflows, deployment provenance, eligibility, factory
access, terms validation and agreement, cancellation, distinct trade identities,
XML resource references, resource integrity and runtime size limits. XML tests
check the contracts' templates and bindings; they do not run the external Java
renderer.

## Layout and notices

- `contracts/` preserves the original Solidity directory structure and imports.
- `resources/` contains the original SimpleBond and InterestRateSwap XML/XSLT
  templates used by the tests.
- `test/OriginalProducts.t.sol` exercises the original contracts end to end.
- `LICENSE` and `NOTICE` preserve the original repository notices. Individual
  Solidity files retain their SPDX license identifiers and author comments.

The original Java demos and development history remain under
[`../../origins/representable-contract-state/`](../../origins/representable-contract-state/).
