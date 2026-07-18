# Smart Product Framework: End-to-End Workflow

[`DemoEndToEndWorkflow`](../representable-contract-state-web/src/main/java/net/finmath/smartcontracts/representablestate/demo/SmartProductFramework/DemoEndToEndWorkflow.java)
runs the complete Simple Bond workflow on a local development chain. It deploys
the framework, publishes the product resources and definition, creates a trade,
and renders the product at each lifecycle checkpoint.

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
4. Publishes the Simple Bond product definition.
5. Publishes a curve indication and assigns it to the product definition.
6. Registers the client and verifies eligibility.
7. Discovers the product type, factory, payload schema, and schema hash.
8. Creates the trade request, which deploys the `SimpleBond` in `Requested`.
9. Amends the requested notional and maturity.
10. Incepts the agreed terms as product provider and confirms them as client.
11. Verifies product provenance and renders every lifecycle checkpoint.

## Historical Product Views

Each lifecycle transaction receipt supplies the exact block used by the
renderer. If the request, amendment, inception, and confirmation are mined in
blocks `B0` through `B3`, the expected differences are:

| Checkpoint | Example block | Trade status | Notional | Maturity | Change |
|---|---:|---|---:|---|---|
| Initial request | 550 (`B0`) | `0` — Requested | `1000000.00` | Initial date (`now + 3 years`) | Product deployed |
| Amended request | 551 (`B1`) | `0` — Requested | `1250000.00` | Amended date (`now + 4 years`) | Economic terms changed |
| Inception | 552 (`B2`) | `1` — Incepted | `1250000.00` | Amended date | Status changed |
| Confirmation | 553 (`B3`) | `2` — Active | `1250000.00` | Amended date | Status changed |

Actual block numbers depend on the chain. The demo prints URLs of this form:

```text
http://localhost:8080/xml?contract=<product-address>&block=<receipt-block>
```

Most XML fields remain unchanged because the product identity and deployment
data are immutable. Inception also stores `agreedTermsHash`, but that value is
currently not part of the product XML. The documentation template always lists
all lifecycle notes and does not display the block number, so compare
`TradeStatus`, `Amount`, and `UnadjustedDate` when inspecting snapshots.

For a compact comparison, substitute the product address and receipt blocks
printed by the demo:

```bash
PRODUCT_ADDRESS=0x...
for block in 550 551 552 553; do
  echo "BLOCK $block"
  curl -s "http://localhost:8080/xml?contract=$PRODUCT_ADDRESS&block=$block" |
    grep -Eo 'evmstate:block-number="[0-9]+"|<TradeStatus>[^<]+|<Amount>[^<]+|<UnadjustedDate>[^<]+'
done
```

Quote URLs containing `&` when using them directly in a shell. The demo also
checks the expected status and economic values programmatically and fails if a
checkpoint resolves against the wrong state.
