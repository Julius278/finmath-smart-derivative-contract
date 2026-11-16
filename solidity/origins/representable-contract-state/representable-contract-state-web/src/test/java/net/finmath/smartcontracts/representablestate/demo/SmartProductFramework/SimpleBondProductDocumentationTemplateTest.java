package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import org.junit.jupiter.api.Test;

import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.stream.StreamResult;
import javax.xml.transform.stream.StreamSource;
import java.io.InputStream;
import java.io.StringReader;
import java.io.StringWriter;

import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SimpleBondProductDocumentationTemplateTest {

	private static final String DOCUMENTATION_TEMPLATE =
			"text-resources/simple-bond-product-documentation-template.xslt";

	@Test
	void rendersProductDocumentationFromWrappedState() throws Exception {
		String renderedDocumentation = renderProductDocumentation(wrappedProductState());

		assertRenderedValues(renderedDocumentation);
		assertFalse(renderedDocumentation.contains("decoy-product-name"));
		assertFalse(renderedDocumentation.contains("xmlns:s"));
	}

	@Test
	void retainsCompatibilityWithLegacyUnwrappedTerms() throws Exception {
		String renderedDocumentation = renderProductDocumentation(legacyProductState());

		assertRenderedValues(renderedDocumentation);
	}

	private static void assertRenderedValues(String renderedDocumentation) {
		assertAll(
				() -> assertTrue(renderedDocumentation.contains("Simple Demo Bond")),
				() -> assertTrue(renderedDocumentation.contains("Bond")),
				() -> assertTrue(renderedDocumentation.contains("1250000.00")),
				() -> assertTrue(renderedDocumentation.contains("EUR")),
				() -> assertTrue(renderedDocumentation.contains("2030-01-02")),
				() -> assertTrue(renderedDocumentation.contains("trade-17")),
				() -> assertTrue(renderedDocumentation.contains("provider-23")),
				() -> assertTrue(renderedDocumentation.contains("client-42")),
				() -> assertTrue(renderedDocumentation.contains("definition-5")),
				() -> assertTrue(renderedDocumentation.contains("deployment-hash-9")),
				() -> assertTrue(renderedDocumentation.contains("Requested lifecycle text")),
				() -> assertTrue(renderedDocumentation.contains("Incepted lifecycle text")),
				() -> assertTrue(renderedDocumentation.contains("Active lifecycle text"))
		);
	}

	private static String renderProductDocumentation(String productState) throws Exception {
		TransformerFactory factory = TransformerFactory.newInstance();
		try (InputStream template = SimpleBondProductDocumentationTemplateTest.class
				.getClassLoader()
				.getResourceAsStream(DOCUMENTATION_TEMPLATE)) {
			if (template == null) {
				throw new IllegalStateException("Missing documentation template: " + DOCUMENTATION_TEMPLATE);
			}
			Transformer transformer = factory.newTransformer(new StreamSource(template));
			StringWriter renderedDocumentation = new StringWriter();
			transformer.transform(
					new StreamSource(new StringReader(productState)),
					new StreamResult(renderedDocumentation)
			);
			return renderedDocumentation.toString();
		}
	}

	private static String wrappedProductState() {
		return """
				<SimpleBond xmlns="urn:smart-product-framework:simple-bond:1.0">
				  <ProductName>decoy-product-name</ProductName>
				  %s
				  <ProductResources>
				    <ProductTermsTemplate>
				      %s
				    </ProductTermsTemplate>
				    <ProductDocumentationTemplate/>
				  </ProductResources>
				</SimpleBond>
				""".formatted(deploymentState(), productTerms());
	}

	private static String legacyProductState() {
		return """
				<SimpleBond xmlns="urn:smart-product-framework:simple-bond:1.0">
				  %s
				  %s
				</SimpleBond>
				""".formatted(deploymentState(), productTerms());
	}

	private static String deploymentState() {
		return """
				<DeploymentState>
				  <TradeId>trade-17</TradeId>
				  <ProductProvider>provider-23</ProductProvider>
				  <Client>client-42</Client>
				  <ProductDefinitionId>definition-5</ProductDefinitionId>
				  <ProductDefinitionVersion>3</ProductDefinitionVersion>
				  <ProductTypeId>simple-bond</ProductTypeId>
				  <DeploymentStateHash>deployment-hash-9</DeploymentStateHash>
				  <TradeStatus>2</TradeStatus>
				</DeploymentState>
				""";
	}

	private static String productTerms() {
		return """
				<SimpleBondTerms>
				  <Header>
				    <ProductName>Simple Demo Bond</ProductName>
				  </Header>
				  <EconomicTerms>
				    <InstrumentType>Bond</InstrumentType>
				    <Currency>EUR</Currency>
				    <Notional><Amount>1250000.00</Amount><Currency>EUR</Currency></Notional>
				    <MaturityDate><UnadjustedDate>2030-01-02</UnadjustedDate></MaturityDate>
				  </EconomicTerms>
				  <Lifecycle>
				    <Requested>Requested lifecycle text</Requested>
				    <Incepted>Incepted lifecycle text</Incepted>
				    <Active>Active lifecycle text</Active>
				  </Lifecycle>
				</SimpleBondTerms>
				""";
	}
}
