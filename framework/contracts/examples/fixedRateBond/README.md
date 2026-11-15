# Fixed-rate bond with an existing ERC-20 asset

This example runs `FixedRateBond`, `FixedRateBondLib` and `FixedRateBondFactory`
against the maintained Smart Product Framework. The factory selects an existing
ERC-20 asset and a local payment adapter. Asset units and cash move between the
issuer's and buyer's wallets on the local test chain.

From `framework/`, run:

```sh
npm ci
npm run build
npm test
```

The executable walkthrough is
[`FixedRateBondDemoTest.js`](../../../test/FixedRateBondDemoTest.js), with deployment
and term construction in
[`fixedRateBondDemo.js`](../../../test/helpers/fixedRateBondDemo.js).
It needs no RPC endpoint, wallet, external service or real money. Normal Ethereum
contract-size limits remain enabled, including for factory deployment.

## Lifecycle

1. Deploy the existing asset, cash token, client and product registries, resources,
   indications, payment adapter and linked libraries. Publish a definition whose
   factory fixes the asset and payment addresses. Request the trade and issue the
   bond through the registry. Authorize the bond in the payment adapter.
2. The issuer incepts the trade and the buyer confirms the same terms hash. That
   hash binds the economics, finalized resource hashes, asset and payment contracts.
   Confirmation enables delivery of the already-existing asset.
3. The issuer approves the asset escrow. The buyer incepts delivery and a matching
   payment. The operator commits two outcome hashes; the bond checks the payment
   context and locks the asset. Success moves cash and asset units atomically.
   Failure returns the units without paying cash. Missing balances or allowances
   leave the attempt recoverable once the participant supplies them.
4. On a coupon payment date, the buyer calls `payCoupon`. The issuer approves that
   payment and the operator completes and settles it. Amounts use ACT/ACT ICMA,
   including a short first period, with rounding down per denomination before
   multiplication by the number of units.
5. At maturity, the issuer requests redemption through `requestTradeTermination`,
   offering the negative redemption amount from the issuer's perspective. The buyer
   accepts through `confirmTradeTermination`, with the corresponding positive
   amount and identical terms. Settlement then returns the asset units to the
   issuer against the redemption payment. The existing token supply remains unchanged.

The four agreement states remain separate from `positionState`, which tracks
delivery, the redemption proposal, authorization to return the units, and repayment.
Either participant can cancel an unmatched redemption proposal or an accepted
proposal before an asset attempt is active; a later request starts a new proposal.

## Components and scope

| Component | Local behavior |
| --- | --- |
| `ClientRegistry` | Shared participant onboarding and eligibility |
| `BondSettlementModules` | Immutable factory-selected asset and payment configuration |
| `DemoToken` | Ordinary integer ERC-20 test balances, allocated once at construction |
| `DemoPayment` | Explicit payer approval, operator-supplied outcome commitments and local cash transfers |
| `DemoAssetLocking` | Generated-key escrow, payment-context checks, delivery, cancellation and retry |
| `DemoInterfaces` | Narrow payment callback and context declarations |

The example has no token-creation or retirement service, securities-identifier
allocation, account-resolution or delegated-account integration. Participants
use their own wallets. It models one bilateral position, not a transferable
holder register or a securities administration service.

The payment adapter is a local demonstration. Its operator controls product
authorization and payment outcomes and must keep outcome preimages private.
It provides no encrypted oracle service, bank settlement or cross-chain finality.
Use ordinary ERC-20 tokens with the documented integer-unit convention;
transfer-tax or rebasing assets are outside this example's scope.

Only the configured payment adapter can submit outcome keys to the bond. This
ensures a visible key cannot release an asset or discharge a coupon before the
local cash transfer. Each coupon retains the single-attempt behavior: cancellation
marks it `Failed` and does not permit another request. Asset settlement supports
fresh attempts after cancellation or failure.

Existing SPDX identifiers and source notices on the retained bond, library and
factory remain applicable. The `demo/` adapters and walkthrough tests are local
integration code.
