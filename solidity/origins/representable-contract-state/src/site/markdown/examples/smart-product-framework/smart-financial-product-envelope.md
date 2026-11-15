# Smart Financial Product XML envelope

Status: proposed envelope version 1.0.0

The Smart Financial Product envelope gives Smart Product Framework products a
stable ERC-8100 root instead of encoding the product kind in the root element:

```xml
<SmartFinancialProduct
    xmlns="urn:smart-product-framework:financial-product:1.0"
    schemaVersion="1.0.0"
    type="ExampleProduct"
    typeVersion="1.0.0">
```

Product-specific state and business-document vocabularies remain separate,
versioned profiles. The generic schema is packaged by
`representable-contract-state-core` at:

```text
xsd/smart-product-framework/smart-financial-product-envelope.xsd
```

The restricted XInclude profile is packaged beside it as
`xinclude-smart-product-profile.xsd`. The canonical `evmstate` vocabulary is
available at `xsd/evmstate-bindings.xsd` in the same artifact.

## Envelope structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<SmartFinancialProduct
        xmlns="urn:smart-product-framework:financial-product:1.0"
        xmlns:xi="http://www.w3.org/2001/XInclude"
        xmlns:evmstate="urn:evm:state:1.0"
        schemaVersion="1.0.0"
        type="ExampleProduct"
        typeVersion="1.0.0">
    <DeploymentState>
        <ProductRegistry evmstate:call="productRegistry()(address)"/>
    </DeploymentState>
    <ProductResources>
        <ProductTermsTemplate
                type="ExampleTermsVocabulary"
                version="1.0.0"
                namespace="urn:example:product-terms:1.0"
                mediaType="application/xml">
            <xi:include
                    href="web3://0x0000000000000000000000000000000000000001:1/content"
                    parse="xml"
                    evmstate:integrity="keccak256-0x0000000000000000000000000000000000000000000000000000000000000000"/>
        </ProductTermsTemplate>
        <ProductDocumentationTemplate
                type="XSLT"
                formatVersion="1.0"
                mediaType="application/xslt+xml"
                href="web3://0x0000000000000000000000000000000000000002:1/content"
                integrity="keccak256-0x1111111111111111111111111111111111111111111111111111111111111111"/>
    </ProductResources>
</SmartFinancialProduct>
```

`DeploymentState` is deliberately open in the generic schema. A product
profile defines its required fields, order, lexical value types, and exact
ERC-8100 getter bindings.

## Identifiers and versions

The metadata fields describe independent compatibility domains:

| Location | Meaning |
| --- | --- |
| Envelope namespace ending in `:1.0` | Major-compatible envelope family. |
| `schemaVersion` | Exact envelope grammar version. Version 1.0 fixes it to `1.0.0`. |
| `type` | Product-profile dispatch key, such as `FixedRateBond`. |
| `typeVersion` | Version of that product's XML state projection and bindings. |
| `ProductTermsTemplate/@type` | Business-document vocabulary identifier. |
| `ProductTermsTemplate/@version` | Version of that vocabulary. |
| `ProductTermsTemplate/@namespace` | Expected namespace of the included document root. |
| `ProductDocumentationTemplate/@formatVersion` | Transformation-language version, not a content revision. |
| Resource `integrity` | Digest that pins the exact external resource bytes. |

`type` is an ordinary framework attribute, not `xsi:type`. It is also not a
replacement for an on-chain routing identifier or factory address. The current
Smart Product Framework uses the selected factory to identify deployment
behavior; the XML `type` pair only selects the validation and interpretation
profile.

A consumer selects a concrete profile from both pairs:

```text
(SmartFinancialProduct/@type, @typeVersion)
(ProductTermsTemplate/@type, @version)
```

Unknown pairs must be rejected. Upgrading a terms vocabulary does not
automatically change the product-state profile, and changing state fields or
getter signatures requires a new `typeVersion`.

## Namespaces

The proposed envelope namespace is:

```text
urn:smart-product-framework:financial-product:1.0
```

This is a provisional project namespace. Before independent implementations
treat the format as a public standard, its governing organization should use a
controlled HTTPS namespace or register an appropriate URN namespace identifier
and publish the profile-registry policy.

An included business document retains its vocabulary owner's namespace. A
profile must not invent a versioned replacement for an external vocabulary's
official namespace merely because the envelope records its version separately.

`xsi:schemaLocation` supplied by an instance is advisory and must not trigger
network schema loading. Validators select schemas from a trusted local registry
using the envelope metadata.

## Validation profiles

Validation is intentionally layered:

1. The generic envelope schema checks the stable root, required metadata,
   resource slots, URI syntax, and integrity syntax.
2. A product-and-terms profile checks the exact deployment fields, ERC-8100
   bindings, business-document root, and fixed metadata values.
3. After rendering, a rendered-state profile checks concrete values, required
   renderer context, and the absence of residual bindings where appropriate.
4. The extracted business document is validated against its authoritative
   vocabulary schema.

The generic and concrete schemas are separate validation passes. Concrete
profiles share the envelope target namespace and may declare the same global
root, so all profiles must not be compiled into one undifferentiated XSD set.

The schema uses XSD 1.0. Rules requiring comparisons between metadata and a
deep business-document value remain semantic profile checks unless a separate
assertion technology is adopted.

## Raw and rendered documents

The raw `stateXmlTemplate()` and its rendered representation are different
artifacts:

- the raw template contains `evmstate` bindings and normally has no renderer
  context values;
- the renderer expands integrity-protected resources and evaluates every
  binding at one fixed block;
- the rendered root carries `evmstate:chain-id`, `contract-address`,
  `block-number`, `renderer-id`, `renderer-version`, and `renderer-url`;
- a concrete rendered-state profile may require all six attributes even though
  they remain optional in the generic envelope, which also validates raw
  templates.

The core `evmstate` schema keeps the original three context attributes typed as
strings for compatibility. Profiles or application checks can impose stricter
chain-ID, address, and block-number lexical rules.

## XInclude and resource security

An unresolved product terms resource contains one `xi:include` whose profile
requires:

- an absolute hierarchical `http`, `https`, `ipfs`, `web3`, or `w3` URI;
- explicit `parse="xml"`;
- no fragment-selection mechanism; and
- `evmstate:integrity="keccak256-0x{64 hexadecimal digits}"`.

The renderer must hash the fetched raw bytes before parsing them and reject a
mismatch. It must also enforce configured URI/host allow-lists, response-size
and nesting limits, cycle detection, request timeouts, and secure XML parsing
without DTDs or external entities.

`ProductDocumentationTemplate` remains a reference because ERC-8100 rendering
produces product XML and documentation generation is a distinct processing
step. A consumer must verify its unqualified `integrity` attribute before
compiling the resource. XSLT execution requires secure processing, disabled
unapproved external access and extension functions, and resource and execution
limits. An integrity digest authenticates bytes; it does not make executable
transformation code safe.

## Compatibility and adoption

Replacing product-specific roots with `SmartFinancialProduct` is a breaking
writer-format change. Existing on-chain templates and their hashes remain valid
under their old profiles and must never be silently reinterpreted. During a
transition, readers may register both formats while new writers emit the new
one only after their concrete profile is available.

This proposal does not migrate the current Simple Bond or Interest Rate Swap
demo emitters. Their deployment-state shape and resource metadata must first be
assigned explicit profile versions. Implementations also need governed hooks
for product type, terms vocabulary/version/namespace, and documentation format
metadata rather than guessing those values from an opaque resource identifier.

The framework repository owns this generic envelope and the canonical
`evmstate`/XInclude schema vocabulary. Product repositories own concrete
product and business-vocabulary profiles, fixtures, and exact getter rules.
