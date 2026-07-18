# Smart Product Framework Template Renamings

This document records the terminology migration applied to the Smart Product
Framework. Domain-facing names describe the role of each template; XML and
XSLT remain in use only where they identify a concrete format or protocol.

## Canonical terminology

| Previous name | New name |
|---|---|
| `termsResource` | `productTermsTemplate` |
| `stylesheetResource` | `productDocumentationTemplate` |
| `termsContentHash` | `productTermsTemplateContentHash` |
| `stylesheetContentHash` | `productDocumentationTemplateContentHash` |
| `ResourceSlot.ProductTerms` | `ResourceSlot.ProductTermsTemplate` |
| `ResourceSlot.StyleSheet` | `ResourceSlot.ProductDocumentationTemplate` |
| `BOND_TERMS_RESOURCE_TYPE` | `BOND_PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE` |
| `BOND_STYLESHEET_RESOURCE_TYPE` | `BOND_PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE` |
| `keccak256("BOND_TERMS")` | `keccak256("BOND_PRODUCT_TERMS_TEMPLATE")` |
| `keccak256("BOND_STYLESHEET")` | `keccak256("BOND_PRODUCT_DOCUMENTATION_TEMPLATE")` |

The same stems are qualified according to the represented value:

- `productTermsTemplatePath`
- `productTermsTemplateContentHash`
- `productTermsTemplateText`
- `productDocumentationTemplatePath`
- `productDocumentationTemplateContentHash`
- `productDocumentationTemplateText`

## Solidity API and data model

The field order and types remain unchanged:

```solidity
struct ProductDefinitionResources {
    address productTermsTemplate;
    address productDocumentationTemplate;
    bytes32 productTypeId;
}
```

`CommonDeploymentParams` uses the same two field names. Deployed products now
expose:

```solidity
function productTermsTemplate() external view returns (address);
function productDocumentationTemplate() external view returns (address);
```

The renamed fields flow through product-definition events, validation,
deployment parameter construction, template inclusion and
`deploymentStateHash` calculation. The hash's encoded field order and types did
not change.

Generic infrastructure names remain unchanged because they describe reusable
infrastructure rather than a domain role:

- `ITextResource`, `TextResource`, `resourceType`, `mediaType`, `contentHash`
- `ProductDefinitionResources`, `resources`, `updateProductDefinitionResources`
- `IXMLRepresentableState`, `stateXmlTemplate`, `statePartXmlTemplate`

Economic agreement names also remain unchanged: `updateTerms`, `TermsUpdated`,
`currentTermsHash`, `agreedTermsHash` and `_economicTermsHash` refer to live
negotiated terms, not to a stored template.

## Java demos

| Previous name | New name |
|---|---|
| `TERMS_RESOURCE` | `PRODUCT_TERMS_TEMPLATE_PATH` |
| `STYLESHEET_RESOURCE` | `PRODUCT_DOCUMENTATION_TEMPLATE_PATH` |
| `TEMPLATE_RESOURCE` | `PRODUCT_TERMS_TEMPLATE_PATH` |
| `TERMS_RESOURCE_TYPE` | `PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE` |
| `STYLESHEET_RESOURCE_TYPE` | `PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE` |
| `"PRODUCT_TERMS_XML"` | `"PRODUCT_TERMS_TEMPLATE"` |
| `terms`, `termsResource` | `productTermsTemplate` |
| `stylesheet`, `stylesheetResource` | `productDocumentationTemplate` |
| `productTemplate` | `productStateTemplate` |
| `renderedXml` | `renderedProductState` |
| `renderedHtml` | `renderedProductDocumentation` |
| `applyXslt(...)` | `renderProductDocumentation(...)` |

Raw Solidity getter calls in the end-to-end demo now use
`productTermsTemplate` and `productDocumentationTemplate`.

## PlantUML and documentation

| Previous participant alias | New participant alias |
|---|---|
| `XmlResource` | `ProductTermsTemplate` |
| `XsltResource` | `ProductDocumentationTemplate` |

Product-definition examples now use:

```text
{productTermsTemplate, productDocumentationTemplate, productTypeId}
```

The rendering flow is described as resolving the product terms template
against the live product state and applying the product documentation template
to the resolved state.

## Resource files

| Previous path | New path |
|---|---|
| `text-resources/simple-bond-terms.xml` | `text-resources/simple-bond-product-terms-template.xml` |
| `text-resources/simple-bond-stylesheet.xslt` | `text-resources/simple-bond-product-documentation-template.xslt` |
| `text-resources/product-terms-staged-resource.xml` | `text-resources/product-terms-template-staged-resource.xml` |

The `.xml` and `.xslt` extensions remain because they correctly identify the
file formats.

## Technical names retained

The following terms remain intentionally unchanged:

- MIME types `application/xml` and `application/xslt+xml`
- XML declarations, namespaces, `parse="xml"`, `<xi:include>` and
  `<xsl:stylesheet>`
- `EvmXmlRenderer`, XML endpoints and Java `javax.xml.*` APIs
- ERC-8100 methods `stateXmlTemplate` and `statePartXmlTemplate`

## Compatibility impact

This is a clean breaking migration:

- The two renamed public Solidity getters have new function selectors. Existing
  deployed products retain the previous getter API.
- The new resource-type hash preimages produce new identifiers. Previously
  published resources tagged with `BOND_TERMS` or `BOND_STYLESHEET` are not
  accepted by the renamed bond registry rules.
- Struct component and event parameter names changed in ABI metadata, while
  their binary field order, storage layout and event signatures remain
  unchanged.
- Product templates, product definitions, generated bindings and deployments
  must be republished or redeployed together.
