package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import org.junit.jupiter.api.Test;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.stream.StreamResult;
import javax.xml.transform.stream.StreamSource;
import java.io.InputStream;
import java.io.StringReader;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InterestRateSwapProductDocumentationTemplateTest {

	private static final String DOCUMENTATION_TEMPLATE =
			"text-resources/interest-rate-swap-product-documentation-template.xslt";
	private static final String TERMS_TEMPLATE =
			"text-resources/interest-rate-swap-product-terms-template.xml";
	private static final String FPML_NAMESPACE = "http://www.fpml.org/FpML-5/confirmation";
	private static final String SPF_NAMESPACE = "urn:smart-product-framework:interest-rate-swap:1.0";

	@Test
	void rendersFpmlAlignedSwapTermsAndFrameworkState() throws Exception {
		String renderedDocumentation = renderProductDocumentation(wrappedProductState());

		assertAll(
				() -> assertTrue(renderedDocumentation.contains("Fixed-Floating Interest Rate Swap")),
				() -> assertTrue(renderedDocumentation.contains("Active")),
				() -> assertTrue(renderedDocumentation.contains("trade-swap-17")),
				() -> assertTrue(renderedDocumentation.contains("2026-07-20")),
				() -> assertTrue(renderedDocumentation.contains("2026-07-22")),
				() -> assertTrue(renderedDocumentation.contains("2031-07-22")),
				() -> assertTrue(renderedDocumentation.contains("10000000.00")),
				() -> assertTrue(renderedDocumentation.contains("EUR")),
				() -> assertTrue(renderedDocumentation.contains("0.0250")),
				() -> assertTrue(renderedDocumentation.contains("2.5%")),
				() -> assertTrue(renderedDocumentation.contains("30E/360")),
				() -> assertTrue(renderedDocumentation.contains("EUR-EURIBOR-Reuters")),
				() -> assertTrue(renderedDocumentation.contains("ACT/360")),
				() -> assertTrue(renderedDocumentation.contains("Fixed-rate payer")),
				() -> assertTrue(renderedDocumentation.contains("<td>Payer</td>")),
				() -> assertTrue(renderedDocumentation.contains("client-address-42")),
				() -> assertTrue(renderedDocumentation.contains("provider-address-23")),
				() -> assertTrue(renderedDocumentation.contains("EUR-EURIBOR-3M")),
				() -> assertTrue(renderedDocumentation.contains("EUR-ESTR-OIS")),
				() -> assertFalse(renderedDocumentation.contains("decoy-forward-curve")),
				() -> assertFalse(renderedDocumentation.contains("xmlns:spf")),
				() -> assertFalse(renderedDocumentation.contains("xmlns:fpml"))
		);
	}

	@Test
	void termsTemplateContainsBothFpmlLegsAndEveryDynamicTermBinding() throws Exception {
		String template;
		try (InputStream stream = InterestRateSwapProductDocumentationTemplateTest.class
				.getClassLoader()
				.getResourceAsStream(TERMS_TEMPLATE)) {
			if (stream == null) {
				throw new IllegalStateException("Missing terms template: " + TERMS_TEMPLATE);
			}
			template = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
		}

		DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
		factory.setNamespaceAware(true);
		var document = factory.newDocumentBuilder().parse(
				new org.xml.sax.InputSource(new StringReader(template))
		);

		assertAll(
				() -> assertTrue(SPF_NAMESPACE.equals(document.getDocumentElement().getNamespaceURI())),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "dataDocument").getLength() == 1),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "swapStream").getLength() == 2),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "calculationPeriodDates").getLength() == 2),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "paymentDates").getLength() == 2),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "resetDates").getLength() == 1),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "notionalSchedule").getLength() == 2),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "fixedRateSchedule").getLength() == 1),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "floatingRateCalculation").getLength() == 1),
				() -> assertTrue(document.getElementsByTagNameNS(FPML_NAMESPACE, "party").getLength() == 2),
				() -> assertTrue(document.getElementsByTagNameNS(SPF_NAMESPACE, "valuationInputs").getLength() == 1),
				() -> assertTrue(template.contains("notional()(uint256)")),
				() -> assertTrue(template.contains("currency()(string)")),
				() -> assertTrue(template.contains("maturity()(uint256)")),
				() -> assertTrue(template.contains("swapRate()(int256)")),
				() -> assertTrue(template.contains("clientFixedRateRoleName()(string)")),
				() -> assertTrue(template.contains("forwardCurveSymbol()(string)")),
				() -> assertTrue(template.contains("discountCurveSymbol()(string)")),
				() -> assertTrue(template.contains("fixedLegPayerPartyReference()(string)")),
				() -> assertTrue(template.contains("floatingLegReceiverPartyReference()(string)"))
		);
	}

	private static String renderProductDocumentation(String productState) throws Exception {
		TransformerFactory factory = TransformerFactory.newInstance();
		try (InputStream template = InterestRateSwapProductDocumentationTemplateTest.class
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
				<InterestRateSwap xmlns="urn:smart-product-framework:interest-rate-swap:1.0">
				  <forwardCurveSymbol>decoy-forward-curve</forwardCurveSymbol>
				  <DeploymentState>
				    <TradeId>deployment-trade-id</TradeId>
				    <ProductProvider>provider-address-23</ProductProvider>
				    <Client>client-address-42</Client>
				    <TradeStatus>2</TradeStatus>
				  </DeploymentState>
				  <ProductResources>
				    <ProductTermsTemplate>
				      <spf:InterestRateSwapTerms
				          xmlns:spf="urn:smart-product-framework:interest-rate-swap:1.0"
				          xmlns:fpml="http://www.fpml.org/FpML-5/confirmation">
				        <fpml:dataDocument fpmlVersion="5-6">
				          <fpml:trade>
				            <fpml:tradeHeader>
				              <fpml:partyTradeIdentifier>
				                <fpml:partyReference href="client"/>
				                <fpml:tradeId>trade-swap-17</fpml:tradeId>
				              </fpml:partyTradeIdentifier>
				              <fpml:partyTradeIdentifier>
				                <fpml:partyReference href="productProvider"/>
				                <fpml:tradeId>trade-swap-17</fpml:tradeId>
				              </fpml:partyTradeIdentifier>
				              <fpml:tradeDate>2026-07-20</fpml:tradeDate>
				            </fpml:tradeHeader>
				            <fpml:swap>
				              %s
				              %s
				            </fpml:swap>
				          </fpml:trade>
				          <fpml:party id="client"><fpml:partyId>client-address-42</fpml:partyId></fpml:party>
				          <fpml:party id="productProvider"><fpml:partyId>provider-address-23</fpml:partyId></fpml:party>
				        </fpml:dataDocument>
				        <spf:valuationInputs>
					          <spf:clientFixedRateRole>Payer</spf:clientFixedRateRole>
				          <spf:forwardCurveSymbol>EUR-EURIBOR-3M</spf:forwardCurveSymbol>
				          <spf:discountCurveSymbol>EUR-ESTR-OIS</spf:discountCurveSymbol>
				        </spf:valuationInputs>
				      </spf:InterestRateSwapTerms>
				    </ProductTermsTemplate>
				    <ProductDocumentationTemplate/>
				  </ProductResources>
				</InterestRateSwap>
				""".formatted(fixedLeg(), floatingLeg());
	}

	private static String fixedLeg() {
		return """
				<fpml:swapStream id="fixedLeg">
				  <fpml:payerPartyReference href="client"/>
				  <fpml:receiverPartyReference href="productProvider"/>
				  <fpml:calculationPeriodDates>
				    <fpml:effectiveDate><fpml:unadjustedDate>2026-07-22</fpml:unadjustedDate></fpml:effectiveDate>
				    <fpml:terminationDate><fpml:unadjustedDate>2031-07-22</fpml:unadjustedDate></fpml:terminationDate>
				    <fpml:calculationPeriodFrequency><fpml:periodMultiplier>12</fpml:periodMultiplier><fpml:period>M</fpml:period></fpml:calculationPeriodFrequency>
				  </fpml:calculationPeriodDates>
				  <fpml:calculationPeriodAmount>
				    <fpml:calculation>
				      <fpml:notionalSchedule><fpml:notionalStepSchedule><fpml:initialValue>10000000.00</fpml:initialValue><fpml:currency>EUR</fpml:currency></fpml:notionalStepSchedule></fpml:notionalSchedule>
				      <fpml:fixedRateSchedule><fpml:initialValue>0.0250</fpml:initialValue></fpml:fixedRateSchedule>
				      <fpml:dayCountFraction>30E/360</fpml:dayCountFraction>
				    </fpml:calculation>
				  </fpml:calculationPeriodAmount>
				</fpml:swapStream>
				""";
	}

	private static String floatingLeg() {
		return """
				<fpml:swapStream id="floatingLeg">
				  <fpml:payerPartyReference href="productProvider"/>
				  <fpml:receiverPartyReference href="client"/>
				  <fpml:calculationPeriodAmount>
				    <fpml:calculation>
				      <fpml:floatingRateCalculation>
				        <fpml:floatingRateIndex>EUR-EURIBOR-Reuters</fpml:floatingRateIndex>
				        <fpml:indexTenor><fpml:periodMultiplier>3</fpml:periodMultiplier><fpml:period>M</fpml:period></fpml:indexTenor>
				      </fpml:floatingRateCalculation>
				      <fpml:dayCountFraction>ACT/360</fpml:dayCountFraction>
				    </fpml:calculation>
				  </fpml:calculationPeriodAmount>
				</fpml:swapStream>
				""";
	}
}
