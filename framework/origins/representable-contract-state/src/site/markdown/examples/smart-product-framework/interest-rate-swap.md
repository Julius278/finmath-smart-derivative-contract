<script src="../../js/copy-code.js" defer="defer"></script>

# Smart Product Framework: Interest Rate Swap

`DemoInterestRateSwap` is a deliberately small second product example for the
Smart Product Framework. It deploys a fixed-versus-floating EUR interest-rate
swap, stores its product terms and documentation templates as immutable
`TextResource` contracts, and walks one trade through request, amendment,
inception, and confirmation.

The implementation uses FpML's confirmation vocabulary for the represented
economic terms. It is a focused example rather than a complete swap engine: it
does not generate cash flows, perform fixing or valuation, or settle payments.

## Product Specification

The product-specific factory accepts one ABI tuple:

```text
v1:InterestRateSwapDeploymentPayload(
  uint256 notional,
  string currency,
  uint256 maturity,
  int256 swapRate,
  uint8 clientFixedRateRole,
  string forwardCurveSymbol,
  string discountCurveSymbol
)
```

| Payload field | Encoding convention | Rendered meaning |
|---|---|---|
| `notional` | Unsigned integer, scale 2 | The same `notionalStepSchedule/initialValue` on both FpML swap streams |
| `currency` | Three uppercase ASCII letters | The FpML notional currency; the demo uses `EUR` |
| `maturity` | Unix timestamp in seconds | The unadjusted termination date on both legs |
| `swapRate` | Signed integer, scale 4 | FpML decimal fixed rate: `250` renders as `0.0250`, or 2.50% |
| `clientFixedRateRole` | `0` = Payer, `1` = Receiver | Selects the payer and receiver party references on both legs, from the client's perspective |
| `forwardCurveSymbol` | Non-empty string | Symbolic projection-curve assignment |
| `discountCurveSymbol` | Non-empty string | Symbolic discount-curve assignment |

The trade date and effective date are fixed to the product-deployment time to
avoid adding two more payload fields. The immutable terms template supplies the
remaining conventions for this example: annual fixed payments with `30E/360`,
quarterly EUR-EURIBOR floating periods with `ACT/360`, and EUTA business-day
adjustments.

## FpML Representation

The included XML template uses the FpML confirmation namespace and its normal
`dataDocument / trade / swap / swapStream` structure. It represents two
streams, opposite payer/receiver references, calculation and payment dates,
notional schedules, a fixed-rate schedule, and a floating-rate calculation.
The client and product provider appear as FpML parties whose identifiers are
their EVM addresses.

The two curve symbols are valuation/model inputs rather than contractual FpML
economics. They therefore remain explicit siblings in the Smart Product
Framework extension namespace instead of being presented as standard FpML
elements. This keeps the distinction visible while allowing the renderer to
resolve all seven requested fields from contract state.

The document is an intentionally small FpML-shaped confirmation subset. It
uses the corresponding FpML terms and nesting, but does not claim validation as
a complete standalone FpML message. See the
[FpML confirmation product architecture](https://www.fpml.org/spec/fpml-5-6-5-rec-1/html/confirmation/fpml-5-6-intro-6.html)
for the wider model.

## ERC-6123-Inspired Agreement

The shared Smart Product Framework lifecycle preserves the important
incept/confirm agreement pattern while adapting it to an already deployed,
self-rendering product. It is not ABI-compatible with `ISDCTrade` and does not
claim full ERC-6123 conformance.

| ERC-6123 concept | Lightweight adaptation in this example |
|---|---|
| `withParty` is supplied to inception and confirmation | `productProvider` and `client` are fixed in the product's authenticated deployment state |
| Both parties repeat matching `tradeData` | Canonical structured terms live on-chain; both calls submit the same instance-bound `currentTermsHash()` |
| Signed `position` expresses direction | `clientFixedRateRole` states whether the client pays or receives the fixed leg; the floating-leg roles are the opposite |
| `paymentAmount` and `initialSettlementData` accompany inception | Upfront payment and initial settlement are intentionally outside this terms-and-agreement example |

The provider calls `inceptTrade(currentTermsHash)` while the trade is
`Requested`; the client then calls `confirmTrade` with that same hash. A
mismatch reverts. Successful calls emit the lifecycle and status events and
move the product through `Requested -> Incepted -> Active`. This is the part of
the [ERC-6123 lifecycle](https://eips.ethereum.org/EIPS/eip-6123) the example is
intended to demonstrate.

## Run the Demo

You need Java 21, Maven, `solc`, Node.js/npm, and a local Cancun-capable JSON-RPC
node. The renderer is only required to open the XML URLs printed at the end.
From the repository root:

```bash
npm ci --prefix representable-contract-state-web/src/main/solidity
anvil --chain-id 1337 --hardfork cancun
```

Leave Anvil running. In another terminal, build the project:

```bash
mvn -pl representable-contract-state-web -am -DskipTests package
```

Then run
[`DemoInterestRateSwap`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/java/net/finmath/smartcontracts/representablestate/demo/SmartProductFramework/DemoInterestRateSwap.java)
from the IDE with `representable-contract-state-web` as its working directory.
The Solidity source and compiler output paths are relative to that module.
The equivalent command-line launch for the current snapshot is:

```bash
cd representable-contract-state-web
java \
  -Dloader.main=net.finmath.smartcontracts.representablestate.demo.SmartProductFramework.DemoInterestRateSwap \
  -cp target/representable-contract-state-web-2.4.0.jar \
  org.springframework.boot.loader.launch.PropertiesLauncher
```

The demo deploys the client registry, swap product registry, generic and
product-specific factories, and both template resources. It registers and
funds the client, publishes the product definition, ABI-encodes the seven
fields, creates a request, and performs inception and confirmation. Finally it
amends the requested economic terms before inception and prints block-pinned
renderer URLs grouped by contract.

## Historical Contract Views

Every checkpoint uses the block number from the transaction receipt that
caused the state change. The product-definition registry is rendered as a
state part, while the swap exposes its complete state:

```text
http://localhost:8080/xml/part?contract=<registry>&partid=<definition-id>&block=<receipt-block>
http://localhost:8080/xml?contract=<swap>&block=<receipt-block>
```

The registry group contains one checkpoint:

| Checkpoint | Block label | Status | Version | Visible state |
|---|---|---|---:|---|
| Definition published | `R0` | `1` — Active | 1 | Terms and documentation resources are present; `ProductIndicationAssignment` is `assigned="false"` |

There is deliberately no indication-assignment checkpoint. The forward and
discount curve symbols belong to the swap's requested terms in this minimal
example, rather than referencing a separate indication contract.

The product group contains four checkpoints:

| Checkpoint | Block label | Trade status | Notional | Maturity | Fixed rate | Client fixed-leg role |
|---|---|---|---:|---|---:|---|
| Initial request | `P0` | `0` — Requested | `1000000.00` | `now + 5 years` | `0.0250` | Payer |
| Amended request | `P1` | `0` — Requested | `1250000.00` | `now + 6 years` | `0.0275` | Receiver |
| Inception | `P2` | `1` — Incepted | `1250000.00` | Amended date | `0.0275` | Receiver |
| Confirmation | `P3` | `2` — Active | `1250000.00` | Amended date | `0.0275` | Receiver |

The demo checks both the expected values and strict checkpoint ordering. Open
the grouped URLs printed at the end to compare the historical XML directly.
The client registry and factories do not currently expose renderer-compatible
XML state; finalized template resources remain available through their
immutable `web3Url()` values.

## Source Files

- [`SwapConstants.sol`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/solidity/examples/SmartProductFramework/InterestRateSwapDemo/SwapConstants.sol)
- [`InterestRateSwap.sol`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/solidity/examples/SmartProductFramework/InterestRateSwapDemo/InterestRateSwap.sol)
- [`InterestRateSwapFactory.sol`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/solidity/examples/SmartProductFramework/InterestRateSwapDemo/InterestRateSwapFactory.sol)
- [`InterestRateSwapProductRegistry.sol`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/solidity/examples/SmartProductFramework/InterestRateSwapDemo/InterestRateSwapProductRegistry.sol)
- [`interest-rate-swap-product-terms-template.xml`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/resources/text-resources/interest-rate-swap-product-terms-template.xml)
- [`interest-rate-swap-product-documentation-template.xslt`](https://gitlab.com/finmath/representable-contract-state/-/blob/main/representable-contract-state-web/src/main/resources/text-resources/interest-rate-swap-product-documentation-template.xslt)
