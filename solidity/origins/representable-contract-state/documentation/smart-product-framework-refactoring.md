# Smart Product Framework Refactoring Summary

## 1. Core architectural change

The framework was simplified from a product-type-based routing architecture to a factory-anchored product-definition model.

### Previous structure

```text
Product Definition
    → productTypeId
    → ProductFactoryRegistry
    → product-specific factory
    → product
```

A product definition stored:

```solidity
struct ProductDefinitionResources {
    address productTermsTemplate;
    address productDocumentationTemplate;
    bytes32 productTypeId;
}
```

The `ProductFactoryRegistry` resolved the `productTypeId` to the currently registered factory.

### New structure

```text
Product Definition
    → exact product factory
    → product
```

A product definition now stores:

```solidity
struct ProductDefinition {
    address productFactory;
    address productTermsTemplate;
    address productDocumentationTemplate;
}
```

The registry knows the exact factory belonging to the definition and calls it directly.

---

## 2. Removal of the factory registry

`ProductFactoryRegistry` was removed because its routing state became redundant.

The product definition already identifies:

- the exact factory;
- the exact product terms template;
- the exact documentation template.

The new deployment flow is:

```text
1. Load the active product definition.
2. Read its productFactory address.
3. Build ProductDeploymentParams.
4. Call deployProduct() directly on that factory.
5. Validate the returned product.
```

This prevents an existing product definition from being silently routed to a different factory through a later registry update.

A changed product implementation now requires:

1. deployment of a new factory;
2. an explicit product-definition update;
3. a product-definition version increment.

---

## 3. Unified product factory

The previous generic and product-specific factory concepts were merged.

### Removed or renamed

```text
IProductSpecificFactory          → IProductFactory
AbstractProductSpecificFactory   → AbstractProductFactory
genericFactory                   → productRegistryAddress
onlyGenericFactory               → onlyProductRegistry
productSpecificFactory           → productFactory
```

Each `IProductFactory` now represents one complete product specification and owns:

- the human-readable product payload schema;
- the required product terms resource type;
- the required documentation resource type;
- accepted indication categories;
- the concrete product deployment implementation;
- the record of products deployed by the factory.

The factory can only be called by its configured product registry.

---

## 4. Removal of shared constants

Product-specific `Constants.sol` files were removed.

Examples:

```text
BondConstants.sol
SwapConstants.sol
```

Identifiers are now defined by the contract that owns their meaning.

### Product factories own

- product payload schemas;
- product terms template resource types;
- product documentation template resource types.

### Indication contracts own

- indication category identifiers.

For example:

```solidity
SimpleBondFactory
    → Simple Bond payload schema
    → Simple Bond XML resource type
    → Simple Bond XSLT resource type

CurveIndications
    → keccak256("CURVE")
```

This creates a clear single source of truth and removes cross-contract constant dependencies.

---

## 5. Removed product type and schema hash

The following values were removed because they no longer added meaningful value:

```text
productTypeId
productPayloadSchemaHash
```

### Product type

The exact factory address now identifies the deployment implementation and specification. A separate product-type routing identifier is no longer needed.

### Payload schema hash

The factory still exposes:

```solidity
function productPayloadSchema()
    external
    view
    returns (string memory);
```

The schema is descriptive metadata for clients and integrations.

Runtime correctness is enforced by the concrete product or factory through:

```solidity
abi.decode(productPayload, (...))
```

A duplicated caller-supplied schema hash did not improve this validation.

---

## 6. Product-definition validation

When a product definition is published or updated, the registry validates:

1. the factory address is nonzero and contains code;
2. the factory supports `IProductFactory`;
3. the factory is configured for the current registry;
4. the payload schema is nonempty;
5. both required resource types are nonzero;
6. both resource contracts contain code;
7. both support `ITextResource`;
8. both resources are finalized;
9. both resource types match the requirements exposed by the factory.

The registry therefore remains generic while product-specific compatibility is defined by the factory.

Product-specific registry subclasses such as the following are no longer needed:

```text
BondProductRegistry
InterestRateSwapProductRegistry
```

---

## 7. Simplified deployment parameters

The deployment parameters now contain only the common deployment context and the encoded product payload.

```solidity
struct CommonDeploymentParams {
    address productRegistry;
    bytes32 tradeId;
    address productProvider;
    address client;
    bytes32 productDefinitionId;
    uint256 productDefinitionVersion;
    address productTermsTemplate;
    address productDocumentationTemplate;
    bytes32 deploymentStateHash;
}

struct ProductDeploymentParams {
    CommonDeploymentParams common;
    bytes productPayload;
}
```

Removed fields include:

```text
productTypeId
productSpecificSchemaHash
```

The payload name was standardized:

```text
productSpecificPayload → productPayload
```

---

## 8. Product deployment and verification

The factory deploys the concrete product and verifies that the returned address:

- is not zero;
- contains contract code.

The factory then records the product in:

```solidity
isFactoryDeployedProduct(product)
```

The product registry independently validates the returned product because the factory is an external contract.

The registry verifies the product’s immutable deployment context, including:

- product registry;
- product factory;
- trade ID;
- product provider;
- client;
- product definition ID;
- product definition version;
- terms template;
- documentation template;
- deployment-state hash.

This creates a bidirectional authenticity relationship:

```text
Product → identifies its factory
Factory → confirms it deployed the product
Registry → confirms the product matches the requested deployment
```

---

## 9. Deployment-state hash

The registry creates an integrity hash covering the exact deployment context:

```text
registry
chain ID
trade ID
product provider
client
product definition ID
product definition version
factory address
terms template address and content hash
documentation template address and content hash
product payload hash
```

The deployed product stores this hash immutably.

This anchors the exact factory, resources, payload, and definition revision used for deployment.

---

## 10. Indication model

Indications remain optional registry-level assignments.

The responsibilities are separated as follows:

### Indication contract

Owns the indication category and indication lifecycle.

### Product factory

Defines whether a category is compatible:

```solidity
function isAcceptedIndicationCategory(
    bytes32 indicationCategory
)
    external
    view
    returns (bool);
```

### Product registry

Stores the concrete assignment:

```text
product definition
    → indication contract
    → indication ID
```

When the factory of a product definition changes, an existing indication assignment is revalidated against the new factory.

There is currently:

- no `IndicationMode`;
- no requirement that every definition has an indication;
- no indication validation during trade creation;
- no indication snapshot in the deployed product.

Under the current design, indications are metadata and do not influence deployment or product economics.

---

## 11. Example modules

### Simple Bond

`SimpleBondFactory` owns:

- the Simple Bond payload schema;
- the terms resource type;
- the documentation resource type;
- the accepted curve indication category;
- deployment of `SimpleBond`.

`SimpleBond` decodes:

```solidity
struct SimpleBondDeploymentPayload {
    uint256 notional;
    uint256 maturity;
}
```

### Interest Rate Swap

`InterestRateSwapFactory` owns:

- the swap payload schema;
- the terms resource type;
- the documentation resource type;
- deployment of `InterestRateSwap`.

It currently rejects all indication categories.

The following files were removed:

```text
SwapConstants.sol
InterestRateSwapProductRegistry.sol
```

---

## 12. Final responsibility split

### ProductDefinitionRegistry

Owns:

- product-definition publication;
- lifecycle and versioning;
- factory and resource validation;
- optional indication assignment;
- client eligibility checks;
- trade creation;
- deployment-state hashing;
- direct factory invocation;
- returned-product verification.

### ProductDefinition

Anchors:

- exact product factory;
- exact product terms template;
- exact documentation template.

### ProductFactory

Owns:

- payload schema;
- resource-type requirements;
- indication compatibility;
- product implementation;
- deployment;
- deployed-product authenticity.

### Product

Stores:

- immutable deployment context;
- product-specific economic state;
- trade lifecycle;
- XML-representable state.

### ProductIndication

Owns:

- indication category;
- indication lifecycle;
- indication-specific state.

---

## 13. Result

The refactoring removes unnecessary routing and duplicated metadata.

The central relationship is now:

```text
Product Definition
    ├── exact Product Factory
    ├── exact Product Terms Template
    └── exact Documentation Template
```

The product definition is the canonical deployment record, while the factory is the single source of truth for all product-specific requirements and behavior.

This results in:

- fewer contracts;
- fewer deployment steps;
- no shared constants files;
- no factory-routing registry;
- no product-specific registry subclasses;
- clearer ownership boundaries;
- explicit factory replacement;
- stronger deployment traceability.
