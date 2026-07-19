# Smart Product Framework: End-to-End Workflow

[`DemoEndToEndWorkflow`](../representable-contract-state-web/src/main/java/net/finmath/smartcontracts/representablestate/demo/SmartProductFramework/DemoEndToEndWorkflow.java)
runs the complete Simple Bond workflow on a local development chain. It deploys
the framework, publishes the product resources and definition, creates a trade,
and renders the registry, curve indication, and product at their state-change
checkpoints.

## Before Running

The demo expects:

- Java 21, Maven, `solc`, Docker, and the Solidity dependencies installed with
  `npm ci` at the repository root;
- a Cancun-capable JSON-RPC node at `http://127.0.0.1:8545`; and
- the renderer web application at `http://localhost:8080` when opening the
  printed XML URLs.

Start the development chain with the public demo account funded:

```bash
export DEPLOYMENT_ACCOUNT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
docker run --rm -it --name besu \
  -p 8545:8545 -p 8546:8546 \
  hyperledger/besu:latest \
  --network=dev \
  --miner-enabled=true \
  --miner-coinbase="$DEPLOYMENT_ACCOUNT" \
  --rpc-http-enabled=true \
  --rpc-http-host=0.0.0.0 \
  --rpc-http-port=8545 \
  --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG \
  --host-allowlist="*"
```

The embedded accounts are public development accounts and must never be used
on a chain carrying real assets.

Build the project and start the renderer in a second terminal:

```bash
npm ci
mvn -pl representable-contract-state-web -am -DskipTests package
java -jar representable-contract-state-web/target/representable-contract-state-web-2.3.1-SNAPSHOT.jar
```

Alternatively, run `EvmXmlRendererApplication` from the IDE. Then run
`DemoEndToEndWorkflow`, setting its working directory to
`representable-contract-state-web`; the Solidity source and compiler output
paths are relative to that module. Restart the renderer application after
recompiling it because the project does not use automatic class reloading.

## Workflow

The demo performs these steps:

1. Funds the client development account.
2. Deploys the client registry, product registry, generic factory, and
   Simple Bond factory, then wires their references.
3. Publishes and finalizes the XML product terms template and XSLT product
   documentation template as on-chain `TextResource` contracts.
4. Publishes the Simple Bond product definition and captures registry view
   `R0`.
5. Publishes the curve indication and captures curve view `C0`.
6. Assigns the curve to the product definition and captures registry view
   `R1`.
7. Updates the EUR-2Y yield from 2.75 to 2.85 and captures curve view `C1`.
8. Registers the client and verifies eligibility.
9. Discovers the product type, factory, payload schema, and schema hash.
10. Creates and amends the trade request, then incepts and confirms it.
11. Verifies product provenance and captures product views `P0` through `P3`.
12. Prints every renderer URL, grouped by contract.

## Historical Contract Views

Every checkpoint uses the block from the transaction receipt that caused its
state change. The labels below are relative to one demo run; actual block
numbers can have gaps and are printed by the demo.

Full-state and state-part views use different endpoints:

```text
http://localhost:8080/xml?contract=<product-address>&block=<receipt-block>
http://localhost:8080/xml/part?contract=<address>&partid=<part-id>&block=<receipt-block>
```

### Product-Definition Registry

| Checkpoint | Block label | Status | Version | Visible change |
|---|---|---|---:|---|
| Definition published | `R0` | `1` — Active | 1 | Resources appear; `ProductIndicationAssignment` has `assigned="false"` |
| Curve assigned | `R1` | `1` — Active | 2 | Assignment changes to `assigned="true"` and exposes its contract, indication ID, and part ID |

The `<ProductDefinition>` view groups both inert source previews under
`<ProductResources>`. Its `<ProductTermsTemplate>` and
`<ProductDocumentationTemplate>` children identify the role of each included
resource explicitly.

`<ProductIndicationAssignment>` represents the registry's own reference state.
It is explicitly unassigned at `R0`; at `R1` it contains `contractAddress`,
`indicationId`, and `partId`. The live indication state remains a separate
partial view on the indication contract and is rendered at the same block when
needed.

### Curve Indication

| Checkpoint | Block label | Status | Active quotes | EUR-2Y yield | EUR-5Y yield |
|---|---|---|---:|---:|---:|
| Initial publication | `C0` | `1` — Active | 2 | 2.75 | 3.10 |
| EUR-2Y update | `C1` | `1` — Active | 2 | 2.85 | 3.10 |

All other rendered EUR-2Y fields remain unchanged. Rendering `C0` after the
update has been mined demonstrates that the renderer is reading historical
state rather than the latest quote.

### Product Lifecycle

| Checkpoint | Block label | Trade status | Notional | Maturity | Change |
|---|---|---|---:|---|---|
| Initial request | `P0` | `0` — Requested | `1000000.00` | Initial date (`now + 3 years`) | Product deployed |
| Amended request | `P1` | `0` — Requested | `1250000.00` | Amended date (`now + 4 years`) | Economic terms changed |
| Inception | `P2` | `1` — Incepted | `1250000.00` | Amended date | Status changed |
| Confirmation | `P3` | `2` — Active | `1250000.00` | Amended date | Status changed |

Most product XML fields remain unchanged because the product identity and
deployment data are immutable. Inception also stores `agreedTermsHash`, but
that value is currently not part of the product XML. Compare `TradeStatus`,
`Amount`, and `UnadjustedDate` when inspecting the product snapshots.

Every snapshot retains the `<SimpleBond>` root with sibling `<DeploymentState>`
and `<ProductResources>` sections. The latter contains the named product terms
and product documentation template slots.

For a compact comparison, substitute the addresses, part IDs, and receipt
blocks printed by the demo:

```bash
REGISTRY_ADDRESS=0x...
DEFINITION_PART_ID=...
R0=...
R1=...
for block in "$R0" "$R1"; do
  curl -s "http://localhost:8080/xml/part?contract=$REGISTRY_ADDRESS&partid=$DEFINITION_PART_ID&block=$block" |
    grep -Eo 'evmstate:block-number="[0-9]+"|status="[0-9]+"|productDefinitionVersion="[0-9]+"|<ProductResources>|<ProductTermsTemplate>|<ProductDocumentationTemplate>|<ProductIndicationAssignment[^>]*/>'
done

CURVE_ADDRESS=0x...
INDICATION_PART_ID=...
C0=...
C1=...
for block in "$C0" "$C1"; do
  curl -s "http://localhost:8080/xml/part?contract=$CURVE_ADDRESS&partid=$INDICATION_PART_ID&block=$block" |
    grep -Eo 'evmstate:block-number="[0-9]+"|<Status>[^<]+|<ActiveQuoteCount>[^<]+|<Symbol>[^<]+|<Yield>[^<]+'
done

PRODUCT_ADDRESS=0x...
P0=...
P1=...
P2=...
P3=...
for block in "$P0" "$P1" "$P2" "$P3"; do
  curl -s "http://localhost:8080/xml?contract=$PRODUCT_ADDRESS&block=$block" |
    grep -Eo 'evmstate:block-number="[0-9]+"|<TradeStatus>[^<]+|<Amount>[^<]+|<UnadjustedDate>[^<]+'
done
```

Quote URLs containing `&` when using them directly in a shell. The demo also
checks the expected block metadata and state values programmatically. The
`TextResource`, client registry, and factory contracts do not currently expose
renderer-compatible XML state; the finalized text resources remain available
through their immutable `web3Url()` values.
