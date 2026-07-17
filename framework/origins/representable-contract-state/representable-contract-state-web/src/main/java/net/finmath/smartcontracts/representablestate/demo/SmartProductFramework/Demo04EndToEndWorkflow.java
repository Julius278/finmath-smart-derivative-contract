package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import net.finmath.smartcontracts.representablestate.xml.EvmXmlRenderer;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.FunctionReturnDecoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Bool;
import org.web3j.abi.datatypes.DynamicArray;
import org.web3j.abi.datatypes.DynamicBytes;
import org.web3j.abi.datatypes.DynamicStruct;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.StaticStruct;
import org.web3j.abi.datatypes.Type;
import org.web3j.abi.datatypes.Utf8String;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.abi.datatypes.generated.Int256;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.abi.datatypes.generated.Uint8;
import org.web3j.crypto.Credentials;
import org.web3j.crypto.Hash;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterName;
import org.web3j.protocol.core.methods.response.EthSendTransaction;
import org.web3j.protocol.core.methods.response.Log;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.protocol.http.HttpService;
import org.web3j.tx.RawTransactionManager;
import org.web3j.tx.response.PollingTransactionReceiptProcessor;
import org.web3j.tx.response.TransactionReceiptProcessor;
import org.web3j.utils.Convert;
import org.web3j.utils.Numeric;

import javax.xml.XMLConstants;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.stream.StreamResult;
import javax.xml.transform.stream.StreamSource;
import java.io.InputStream;
import java.io.StringReader;
import java.io.StringWriter;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;

/**
 * End-to-end demo for the Smart Product Framework sequence documented in
 * {@code documentation/smart-product-framework.puml}.
 *
 * <p>The demo is deliberately standalone. It repeats the setup and product
 * definition publication from Demo 03, then covers the remaining workflow:</p>
 *
 * <ol>
 *     <li>wire and register the generic and product-specific factories,</li>
 *     <li>publish and assign a curve indication,</li>
 *     <li>register and fund an investor dev account,</li>
 *     <li>perform the frontend discovery steps and ABI-encode a payload,</li>
 *     <li>create and optionally amend a trade request as the investor,</li>
 *     <li>incept as product provider and confirm as investor, and</li>
 *     <li>verify provenance and render the live product state.</li>
 * </ol>
 *
 * <p>The embedded private keys are public development keys. Never use them on
 * a chain carrying real assets.</p>
 *
 * @author Christian Fries
 */
public class Demo04EndToEndWorkflow {

	static final Path TEXT_RESOURCE_CONTRACT = Path.of("examples", "SmartProductFramework", "TextResource", "TextResource.sol");
	static final Path INVESTOR_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "InvestorRegistry", "InvestorRegistry.sol");
	static final Path TRADABLE_BOND_DATA_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "SimpleBondDemo", "TradableBondDataRegistry.sol");
	static final Path PRODUCT_FACTORY_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "ProductFactory", "ProductFactoryRegistry.sol");
	static final Path SIMPLE_BOND_FACTORY_CONTRACT = Path.of("examples", "SmartProductFramework", "SimpleBondDemo", "SimpleBondFactory.sol");
	static final Path CURVE_INDICATIONS_CONTRACT = Path.of("examples", "SmartProductFramework", "SimpleBondDemo", "CurveIndications.sol");

	private static final String RPC_URL = "http://127.0.0.1:8545";
	private static final BigInteger GAS_PRICE = BigInteger.valueOf(1_000_000_000L);
	private static final BigInteger GAS_LIMIT = BigInteger.valueOf(20_000_000L);
	private static final BigInteger INVESTOR_TARGET_BALANCE = Convert.toWei("1", Convert.Unit.ETHER).toBigIntegerExact();

	// Public Anvil/Hardhat development accounts used elsewhere in this project.
	private static final String PRODUCT_PROVIDER_PRIVATE_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
	private static final String INVESTOR_PRIVATE_KEY = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a";

	private static final String INVESTOR_LEI = "529900T8BM49AURSDO55";
	private static final String TERMS_RESOURCE = "text-resources/simple-bond-terms.xml";
	private static final String STYLESHEET_RESOURCE = "text-resources/simple-bond-stylesheet.xslt";
	private static final String TERMS_RESOURCE_TYPE = "BOND_TERMS";
	private static final String STYLESHEET_RESOURCE_TYPE = "BOND_STYLESHEET";
	private static final String PRODUCT_DEFINITION_NAME = "Simple Bond Demo Product Definition";
	private static final String CURVE_NAME = "EUR Demo Curve";
	private static final int DEMO_CHUNK_SIZE = 10_000;

	private static final BigInteger STATUS_REQUESTED = BigInteger.ZERO;
	private static final BigInteger STATUS_INCEPTED = BigInteger.ONE;
	private static final BigInteger STATUS_ACTIVE = BigInteger.valueOf(2);

	private static final String TRADE_REQUEST_CREATED_EVENT_SIGNATURE =
			Hash.sha3String("TradeRequestCreated(bytes32,address,address,bytes32,bytes32,address)");

	public static void main(String[] args) throws Exception {

		printChainInstructions();

		String productProvider = Credentials.create(PRODUCT_PROVIDER_PRIVATE_KEY).getAddress();
		String investor = Credentials.create(INVESTOR_PRIVATE_KEY).getAddress();

		assertAddressEquals(SmartContractDeployer.defaultSenderAddress(), productProvider,
				"The product-provider key must match SmartContractDeployer's deployment key.");

		System.out.println("Demo 04 - Smart Product Framework end-to-end workflow");
		System.out.println("Product provider:         " + productProvider);
		System.out.println("Investor:                 " + investor);
		System.out.println("Product definition:       " + PRODUCT_DEFINITION_NAME);
		System.out.println("Curve:                    " + CURVE_NAME);
		System.out.println("-".repeat(79));

		ensureInvestorFunded(productProvider, investor);

		/*
		 * Initial setup and factory registration.
		 */
		System.out.println("Deploying InvestorRegistry.");
		String investorRegistry = SmartContractDeployer.deploy(
				INVESTOR_REGISTRY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider)
		);

		System.out.println("Deploying TradableBondDataRegistry.");
		String registry = SmartContractDeployer.deploy(
				TRADABLE_BOND_DATA_REGISTRY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider),
				new Address(investorRegistry)
		);

		System.out.println("Deploying ProductFactoryRegistry.");
		String genericFactory = SmartContractDeployer.deploy(
				PRODUCT_FACTORY_REGISTRY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider),
				new Address(registry)
		);

		SmartContractDeployer.transact(
				registry,
				function("setProductFactory", new Address(genericFactory))
		);

		String factoryBackReference = callAddress(genericFactory, "productRegistryAddress");
		assertAddressEquals(registry, factoryBackReference, "Generic factory back-reference mismatch.");

		System.out.println("Deploying SimpleBondFactory.");
		String simpleBondFactory = SmartContractDeployer.deploy(
				SIMPLE_BOND_FACTORY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(genericFactory)
		);

		byte[] productTypeId = callBytes32(simpleBondFactory, "productTypeId");

		SmartContractDeployer.transact(
				genericFactory,
				function("registerProductFactory", new Bytes32(productTypeId), new Address(simpleBondFactory))
		);

		assertTrue(
				callBool(genericFactory, function("canDeployProduct", new Bytes32(productTypeId))),
				"Registered SimpleBond product type is not deployable."
		);
		assertAddressEquals(
				simpleBondFactory,
				callAddress(genericFactory, function("productFactoryOf", new Bytes32(productTypeId))),
				"The generic factory does not resolve the SimpleBond factory."
		);

		System.out.println("Factory setup complete.");
		System.out.println("Generic factory:          " + genericFactory);
		System.out.println("SimpleBond factory:       " + simpleBondFactory);
		System.out.println("Product type id:          " + Numeric.toHexString(productTypeId));
		System.out.println("-".repeat(79));

		/*
		 * Resource and product-definition publication (the Demo 03 portion).
		 */
		PublishedTextResource termsResource = publishStagedTextResource(
				TERMS_RESOURCE_TYPE,
				"application/xml",
				TERMS_RESOURCE
		);
		PublishedTextResource stylesheetResource = publishStagedTextResource(
				STYLESHEET_RESOURCE_TYPE,
				"application/xslt+xml",
				STYLESHEET_RESOURCE
		);

		SmartContractDeployer.transact(
				registry,
				function(
						"publishProductDefinition",
						new ProductDefinitionPublicationParams(
								new Utf8String(PRODUCT_DEFINITION_NAME),
								new ProductDefinitionResources(
										new Address(termsResource.contractAddress()),
										new Address(stylesheetResource.contractAddress()),
										new Bytes32(productTypeId)
								)
						)
				)
		);

		byte[] productDefinitionId = callBytes32(
				registry,
				function("computeProductDefinitionId", new Utf8String(PRODUCT_DEFINITION_NAME))
		);
		BigInteger productDefinitionPartId = new BigInteger(1, productDefinitionId);

		System.out.println("Product definition published.");
		System.out.println("Product definition id:    " + Numeric.toHexString(productDefinitionId));
		System.out.println("Product definition part:  " + productDefinitionPartId);
		System.out.println("-".repeat(79));

		/*
		 * Curve indication publication and assignment.
		 */
		System.out.println("Deploying and publishing CurveIndications.");
		String curveIndications = SmartContractDeployer.deploy(
				CURVE_INDICATIONS_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider)
		);

		long now = Instant.now().getEpochSecond();
		List<QuoteParams> quotes = createCurveQuotes(now);

		SmartContractDeployer.transact(
				curveIndications,
				function(
						"publishCurveIndications",
						new Utf8String(CURVE_NAME),
						new DynamicArray<>(QuoteParams.class, quotes)
				)
		);

		byte[] indicationId = computeScopedId(CURVE_NAME, curveIndications);
		BigInteger indicationPartId = callUint256(
				curveIndications,
				function("partIdForIndication", new Bytes32(indicationId))
		);

		assertEquals(BigInteger.valueOf(quotes.size()), callUint256(
				curveIndications,
				function("activeQuoteCount", new Bytes32(indicationId))
		), "Unexpected active curve quote count.");

		String indicationTemplate = callString(
				curveIndications,
				new Function(
						"statePartXmlTemplate",
						List.of(new Uint256(indicationPartId)),
						List.of(new TypeReference<Utf8String>() {})
				)
		);
		assertContains(indicationTemplate, "<CurveIndications");
		assertContains(indicationTemplate, "indicationStatusByPartId(uint256)(uint8)");
		assertContains(indicationTemplate, "activeQuotesByPartId(uint256)");
		assertContains(indicationTemplate, "evmstate:args=\"$partId\"");

		EvmXmlRenderer renderer = new EvmXmlRenderer(RPC_URL);
		String renderedIndication = renderer.renderPart(curveIndications, indicationPartId);
		assertNotContains(renderedIndication, "evmstate:call=");
		assertNotContains(renderedIndication, "evmstate:args=");
		assertContains(renderedIndication, "<Status>1</Status>");
		assertContains(renderedIndication, "<ActiveQuoteCount>2</ActiveQuoteCount>");
		assertContains(renderedIndication, "<Symbol>EUR-2Y</Symbol>");
		assertContains(renderedIndication, "<Coupon>2.50</Coupon>");
		assertContains(renderedIndication, "<Yield>2.75</Yield>");

		SmartContractDeployer.transact(
				registry,
				function(
						"assignProductIndication",
						new Bytes32(productDefinitionId),
						new Address(curveIndications),
						new Bytes32(indicationId)
				)
		);

		ProductIndicationAssignment assignment = getProductIndicationAssignment(registry, productDefinitionId);
		assertAddressEquals(curveIndications, assignment.contractAddress(), "Assigned indication contract mismatch.");
		assertBytesEqual(indicationId, assignment.indicationId(), "Assigned indication id mismatch.");
		assertEquals(indicationPartId, assignment.partId(), "Assigned indication part id mismatch.");

		System.out.println("Curve indication assigned.");
		System.out.println("Curve contract:           " + curveIndications);
		System.out.println("Indication id:            " + Numeric.toHexString(indicationId));
		System.out.println("Indication part id:       " + indicationPartId);
		System.out.println("Curve part endpoint*:     http://localhost:8080/xml/part?contract="
				+ curveIndications + "&partid=" + indicationPartId);
		System.out.println("* The renderer supplies $partId to the curve callbacks and expands the quote array.");
		System.out.println("-".repeat(79));

		/*
		 * Investor registration.
		 */
		SmartContractDeployer.transact(
				investorRegistry,
				function(
						"registerInvestor",
						new InvestorRegistrationParams(new Address(investor), new Utf8String(INVESTOR_LEI))
				)
		);

		assertTrue(
				callBool(
						investorRegistry,
						function("isEligibleInvestor", new Address(investor), new Bytes32(productDefinitionId))
				),
				"The registered investor is not eligible for the product definition."
		);

		System.out.println("Investor registered and eligible.");
		System.out.println("Investor LEI:             " + INVESTOR_LEI);
		System.out.println("-".repeat(79));

		/*
		 * Frontend discovery: resolve product type, factory, schema, and payload.
		 */
		byte[] discoveredProductTypeId = callBytes32(
				registry,
				function("productTypeByDefinitionId", new Bytes32(productDefinitionId))
		);
		assertBytesEqual(productTypeId, discoveredProductTypeId, "Product definition type mismatch.");

		String discoveredFactory = callAddress(
				genericFactory,
				function("productFactoryOf", new Bytes32(discoveredProductTypeId))
		);
		assertAddressEquals(simpleBondFactory, discoveredFactory, "Frontend resolved the wrong factory.");

		String payloadSchema = callString(simpleBondFactory, "productSpecificPayloadSchema");
		byte[] payloadSchemaHash = callBytes32(simpleBondFactory, "productSpecificSchemaHash");
		assertBytesEqual(
				Hash.sha3(payloadSchema.getBytes(StandardCharsets.UTF_8)),
				payloadSchemaHash,
				"Factory schema string and schema hash are inconsistent."
		);

		BigInteger initialNotional = BigInteger.valueOf(100_000_000L); // 1,000,000.00 with scale 2
		BigInteger initialMaturity = BigInteger.valueOf(now + 3L * 365 * 24 * 60 * 60);
		byte[] initialPayload = encodeSimpleBondPayload(initialNotional, initialMaturity);

		System.out.println("Frontend discovery complete.");
		System.out.println("Payload schema:           " + payloadSchema);
		System.out.println("Payload schema hash:      " + Numeric.toHexString(payloadSchemaHash));
		System.out.println("Initial notional:         " + initialNotional);
		System.out.println("Initial maturity:         " + initialMaturity);
		System.out.println("-".repeat(79));

		/*
		 * Investor trade request and deployment through both factory layers.
		 */
		TransactionReceipt tradeRequestReceipt = transactAs(
				INVESTOR_PRIVATE_KEY,
				registry,
				function(
						"createTradeRequest",
						new TradeRequestParams(
								new Bytes32(productDefinitionId),
								new Bytes32(payloadSchemaHash),
								new DynamicBytes(initialPayload)
						)
				)
		);

		DeployedTrade deployedTrade = decodeTradeRequestCreated(registry, tradeRequestReceipt);
		byte[] tradeId = deployedTrade.tradeId();
		String product = deployedTrade.productAddress();

		assertAddressEquals(
				product,
				callAddress(registry, function("productOf", new Bytes32(tradeId))),
				"Registry trade lookup mismatch."
		);
		assertAddressEquals(
				product,
				callAddress(genericFactory, function("productByTradeId", new Bytes32(tradeId))),
				"Generic factory trade lookup mismatch."
		);
		assertTradeStatus(product, STATUS_REQUESTED, "Requested");

		assertAddressEquals(registry, callAddress(product, "productRegistry"), "Product registry mismatch.");
		assertAddressEquals(productProvider, callAddress(product, "productProvider"), "Product provider mismatch.");
		assertAddressEquals(investor, callAddress(product, "investor"), "Product investor mismatch.");
		assertAddressEquals(termsResource.contractAddress(), callAddress(product, "termsResource"), "Terms resource mismatch.");
		assertAddressEquals(stylesheetResource.contractAddress(), callAddress(product, "stylesheetResource"), "Stylesheet resource mismatch.");
		assertBytesEqual(tradeId, callBytes32(product, "tradeId"), "Product trade id mismatch.");
		assertBytesEqual(productDefinitionId, callBytes32(product, "productDefinitionId"), "Product definition id mismatch.");
		assertBytesEqual(productTypeId, callBytes32(product, "productTypeId"), "Product type id mismatch.");

		System.out.println("Trade request created; SimpleBond deployed in Requested state.");
		System.out.println("Trade id:                 " + Numeric.toHexString(tradeId));
		System.out.println("Product:                  " + product);
		System.out.println("-".repeat(79));

		/*
		 * Optional amendment while Requested.
		 */
		byte[] initialTermsHash = callBytes32(product, "currentTermsHash");

		BigInteger amendedNotional = BigInteger.valueOf(125_000_000L); // 1,250,000.00 with scale 2
		BigInteger amendedMaturity = BigInteger.valueOf(now + 4L * 365 * 24 * 60 * 60);
		byte[] amendedPayload = encodeSimpleBondPayload(amendedNotional, amendedMaturity);

		transactAs(
				INVESTOR_PRIVATE_KEY,
				product,
				function("updateTerms", new DynamicBytes(amendedPayload))
		);

		assertEquals(amendedNotional, callUint256(product, "notional"), "Amended notional mismatch.");
		assertEquals(amendedMaturity, callUint256(product, "maturity"), "Amended maturity mismatch.");

		byte[] agreedTermsHash = callBytes32(product, "currentTermsHash");
		assertFalse(Arrays.equals(initialTermsHash, agreedTermsHash), "Terms hash did not change after amendment.");

		System.out.println("Investor amended the Requested terms.");
		System.out.println("Amended notional:         " + amendedNotional);
		System.out.println("Amended maturity:         " + amendedMaturity);
		System.out.println("Agreed terms hash:        " + Numeric.toHexString(agreedTermsHash));
		System.out.println("-".repeat(79));

		/*
		 * Product-provider inception and investor confirmation.
		 */
		SmartContractDeployer.transact(
				product,
				function("inceptTrade", new Bytes32(agreedTermsHash))
		);
		assertTradeStatus(product, STATUS_INCEPTED, "Incepted");
		assertBytesEqual(agreedTermsHash, callBytes32(product, "agreedTermsHash"), "Stored agreed terms hash mismatch.");

		transactAs(
				INVESTOR_PRIVATE_KEY,
				product,
				function("confirmTrade", new Bytes32(agreedTermsHash))
		);
		assertTradeStatus(product, STATUS_ACTIVE, "Active");

		System.out.println("Trade incepted by the product provider and confirmed by the investor.");
		System.out.println("Final trade status:       Active");
		System.out.println("-".repeat(79));

		/*
		 * Bidirectional authenticity proof.
		 */
		String productSpecificFactory = callAddress(product, "productSpecificFactory");
		assertAddressEquals(simpleBondFactory, productSpecificFactory, "Product points to the wrong specific factory.");
		assertTrue(
				callBool(
						simpleBondFactory,
						function("isFactoryDeployedProduct", new Address(product))
				),
				"Specific factory does not recognize its deployed product."
		);

		System.out.println("Product authenticity checks passed.");
		System.out.println("-".repeat(79));

		/*
		 * Live state rendering and final XSLT presentation.
		 */
		String productTemplate = callString(product, "stateXmlTemplate");
		assertContains(productTemplate, "<SimpleBond");
		assertContains(productTemplate, "parse=\"xml\"");
		assertContains(productTemplate, termsResource.contractAddress());
		assertContains(productTemplate, stylesheetResource.contractAddress());

		String renderedXml = renderer.render(product);

		assertNotContains(renderedXml, "evmstate:call=");
		assertContains(renderedXml, new BigDecimal(amendedNotional, 2).toPlainString());
		assertContains(
				renderedXml,
				Instant.ofEpochSecond(amendedMaturity.longValueExact())
						.atZone(ZoneOffset.UTC)
						.toLocalDate()
						.toString()
		);

		String stylesheet = callString(stylesheetResource.contractAddress(), "text");
		String renderedHtml = applyXslt(renderedXml, stylesheet);
		assertContains(renderedHtml, new BigDecimal(amendedNotional, 2).toPlainString());

		System.out.println("Rendered product XML:");
		System.out.println(renderedXml);
		System.out.println();
		System.out.println("XSLT result:");
		System.out.println(renderedHtml);
		System.out.println();

		System.out.println("=".repeat(79));
		System.out.println("Demo 04 completed.");
		System.out.println("InvestorRegistry:         " + investorRegistry);
		System.out.println("Product registry:         " + registry);
		System.out.println("Generic factory:          " + genericFactory);
		System.out.println("SimpleBond factory:       " + simpleBondFactory);
		System.out.println("Curve indications:        " + curveIndications);
		System.out.println("Product definition id:    " + Numeric.toHexString(productDefinitionId));
		System.out.println("Trade id:                 " + Numeric.toHexString(tradeId));
		System.out.println("Product:                  " + product);
		System.out.println("Rendered XML endpoint:    http://localhost:8080/xml?contract=" + product);
	}

	private static void printChainInstructions() {
		System.out.println("This demo requires a locally running Cancun-capable chain. If not already running, start one with:");
		System.out.println("DEPLOYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
		System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYER --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
		System.out.println("-".repeat(79));
	}

	private static List<QuoteParams> createCurveQuotes(long now) {
		BigInteger settlement = BigInteger.valueOf(now + 2L * 24 * 60 * 60);

		return List.of(
				new QuoteParams(
						new Utf8String("EUR-2Y"),
						new Int256(BigInteger.valueOf(730)),
						new Uint256(settlement),
						new Uint256(BigInteger.valueOf(now + 2L * 365 * 24 * 60 * 60)),
						new Utf8String("ACT/ACT"),
						new Uint256(BigInteger.valueOf(250)),
						new Utf8String("EUR"),
						new Int256(BigInteger.valueOf(275)),
						new Uint256(BigInteger.valueOf(99_500_000L)),
						new Uint256(BigInteger.valueOf(100_000_000L)),
						new Uint256(BigInteger.valueOf(100_000_000_000L)),
						new Uint256(BigInteger.valueOf(1_000_000_000_000_000L))
				),
				new QuoteParams(
						new Utf8String("EUR-5Y"),
						new Int256(BigInteger.valueOf(1_825)),
						new Uint256(settlement),
						new Uint256(BigInteger.valueOf(now + 5L * 365 * 24 * 60 * 60)),
						new Utf8String("ACT/ACT"),
						new Uint256(BigInteger.valueOf(300)),
						new Utf8String("EUR"),
						new Int256(BigInteger.valueOf(310)),
						new Uint256(BigInteger.valueOf(99_000_000L)),
						new Uint256(BigInteger.valueOf(100_000_000L)),
						new Uint256(BigInteger.valueOf(100_000_000_000L)),
						new Uint256(BigInteger.valueOf(1_000_000_000_000_000L))
				)
		);
	}

	private static PublishedTextResource publishStagedTextResource(
			String resourceTypeName,
			String mediaType,
			String classpathResource
	) throws Exception {

		String owner = SmartContractDeployer.defaultSenderAddress();
		byte[] content = loadResourceBytes(classpathResource);
		byte[] resourceType = bytes32FromKeccak256String(resourceTypeName);
		byte[] expectedContentHash = Hash.sha3(content);

		System.out.println("Publishing TextResource:  " + resourceTypeName);
		System.out.println("Classpath resource:       " + classpathResource);
		System.out.println("Content length:           " + content.length + " bytes");

		String contractAddress = SmartContractDeployer.deploy(
				TEXT_RESOURCE_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(owner),
				new Bytes32(resourceType),
				new Utf8String(mediaType),
				new DynamicBytes(new byte[0]),
				new Bytes32(new byte[32])
		);

		for (int offset = 0; offset < content.length; offset += DEMO_CHUNK_SIZE) {
			int chunkLength = Math.min(DEMO_CHUNK_SIZE, content.length - offset);
			byte[] chunk = Arrays.copyOfRange(content, offset, offset + chunkLength);
			SmartContractDeployer.transact(
					contractAddress,
					function("appendChunk", new DynamicBytes(chunk))
			);
		}

		SmartContractDeployer.transact(
				contractAddress,
				function("finalize", new Bytes32(expectedContentHash))
		);

		assertTrue(callBool(contractAddress, "isFinalized"), "TextResource was not finalized.");
		assertBytesEqual(expectedContentHash, callBytes32(contractAddress, "contentHash"), "TextResource content hash mismatch.");
		assertBytesEqual(
				content,
				callString(contractAddress, "text").getBytes(StandardCharsets.UTF_8),
				"TextResource read-back mismatch."
		);

		System.out.println("TextResource:             " + contractAddress);
		System.out.println("Content hash:             " + Numeric.toHexString(expectedContentHash));
		System.out.println("-".repeat(79));

		return new PublishedTextResource(contractAddress, expectedContentHash);
	}

	private static void ensureInvestorFunded(String productProvider, String investor) throws Exception {
		Web3j web3 = Web3j.build(new HttpService(RPC_URL));
		try {
			BigInteger balance = web3.ethGetBalance(investor, DefaultBlockParameterName.LATEST).send().getBalance();
			if (balance.compareTo(INVESTOR_TARGET_BALANCE) >= 0) {
				System.out.println("Investor dev account is already funded: "
						+ Convert.fromWei(new BigDecimal(balance), Convert.Unit.ETHER) + " ETH");
				return;
			}

			BigInteger topUp = INVESTOR_TARGET_BALANCE.subtract(balance);
			long chainId = web3.ethChainId().send().getChainId().longValueExact();
			RawTransactionManager txManager = new RawTransactionManager(
					web3,
					Credentials.create(PRODUCT_PROVIDER_PRIVATE_KEY),
					chainId
			);

			assertAddressEquals(productProvider, txManager.getFromAddress(), "Funding signer mismatch.");

			EthSendTransaction response = txManager.sendTransaction(
					GAS_PRICE,
					BigInteger.valueOf(21_000),
					investor,
					"0x",
					topUp
			);
			checkSendResponse(response, "fund investor");

			TransactionReceipt receipt = receiptProcessor(web3).waitForTransactionReceipt(response.getTransactionHash());
			checkReceipt(receipt, "fund investor");

			System.out.println("Funded investor dev account with "
					+ Convert.fromWei(new BigDecimal(topUp), Convert.Unit.ETHER) + " ETH.");
		}
		finally {
			web3.shutdown();
		}
	}

	private static TransactionReceipt transactAs(
			String privateKey,
			String contractAddress,
			Function function
	) throws Exception {

		Web3j web3 = Web3j.build(new HttpService(RPC_URL));
		try {
			long chainId = web3.ethChainId().send().getChainId().longValueExact();

			Credentials credentials = Credentials.create(privateKey);
			RawTransactionManager txManager = new RawTransactionManager(web3, credentials, chainId);

			EthSendTransaction response = txManager.sendTransaction(
					GAS_PRICE,
					GAS_LIMIT,
					contractAddress,
					FunctionEncoder.encode(function),
					BigInteger.ZERO
			);
			checkSendResponse(response, function.getName());

			TransactionReceipt receipt = receiptProcessor(web3).waitForTransactionReceipt(response.getTransactionHash());
			checkReceipt(receipt, function.getName());

			System.out.println("Tx " + function.getName() + " by " + credentials.getAddress()
					+ " gas used: " + receipt.getGasUsed());

			return receipt;
		}
		finally {
			web3.shutdown();
		}
	}

	private static TransactionReceiptProcessor receiptProcessor(Web3j web3) {
		return new PollingTransactionReceiptProcessor(web3, 2_000, 120);
	}

	private static void checkSendResponse(EthSendTransaction response, String operation) {
		if (response.hasError()) {
			throw new IllegalStateException(
					"Could not send transaction for " + operation + ": " + response.getError().getMessage()
			);
		}
	}

	private static void checkReceipt(TransactionReceipt receipt, String operation) {
		if (!receipt.isStatusOK()) {
			throw new IllegalStateException(
					"Transaction failed for " + operation + ". Tx hash: " + receipt.getTransactionHash()
							+ ", status: " + receipt.getStatus()
			);
		}
	}

	private static DeployedTrade decodeTradeRequestCreated(
			String registry,
			TransactionReceipt receipt
	) {
		for (Log log : receipt.getLogs()) {
			if (!registry.equalsIgnoreCase(log.getAddress()) || log.getTopics().size() < 4) {
				continue;
			}
			if (!TRADE_REQUEST_CREATED_EVENT_SIGNATURE.equalsIgnoreCase(log.getTopics().get(0))) {
				continue;
			}

			byte[] tradeId = Numeric.hexStringToByteArray(log.getTopics().get(1));
			Function eventDataDecoder = new Function(
					"TradeRequestCreatedData",
					List.of(),
					List.of(
							new TypeReference<Bytes32>() {},
							new TypeReference<Bytes32>() {},
							new TypeReference<Address>() {}
					)
			);
			List<Type> decoded = FunctionReturnDecoder.decode(
					log.getData(),
					eventDataDecoder.getOutputParameters()
			);

			if (decoded.size() != 3) {
				throw new IllegalStateException("Unexpected TradeRequestCreated event payload.");
			}

			String product = ((Address) decoded.get(2)).getValue();
			return new DeployedTrade(tradeId, product);
		}

		throw new IllegalStateException(
				"TradeRequestCreated event not found in transaction " + receipt.getTransactionHash()
		);
	}

	private static ProductIndicationAssignment getProductIndicationAssignment(
			String registry,
			byte[] productDefinitionId
	) throws Exception {
		List<Type> decoded = SmartContractDeployer.call(
				registry,
				new Function(
						"productIndicationOfDefinition",
						List.of(new Bytes32(productDefinitionId)),
						List.of(
								new TypeReference<Address>() {},
								new TypeReference<Bytes32>() {},
								new TypeReference<Uint256>() {}
						)
				)
		);

		return new ProductIndicationAssignment(
				((Address) decoded.get(0)).getValue(),
				((Bytes32) decoded.get(1)).getValue(),
				((Uint256) decoded.get(2)).getValue()
		);
	}

	private static byte[] encodeSimpleBondPayload(BigInteger notional, BigInteger maturity) {
		String encoded = FunctionEncoder.encodeConstructor(
				List.of(new Uint256(notional), new Uint256(maturity))
		);
		return Numeric.hexStringToByteArray(encoded);
	}

	private static byte[] computeScopedId(String name, String contractAddress) {
		String encoded = FunctionEncoder.encodeConstructor(
				List.of(new Utf8String(name), new Address(contractAddress))
		);
		return Hash.sha3(Numeric.hexStringToByteArray(encoded));
	}

	private static String applyXslt(String xml, String stylesheet) throws Exception {
		TransformerFactory factory = TransformerFactory.newInstance();
		factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
		factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_STYLESHEET, "");

		Transformer transformer = factory.newTransformer(
				new StreamSource(new StringReader(stylesheet))
		);
		StringWriter writer = new StringWriter();
		transformer.transform(
				new StreamSource(new StringReader(xml)),
				new StreamResult(writer)
		);
		return writer.toString();
	}

	private static Function function(String name, Type... inputParameters) {
		return new Function(name, Arrays.asList(inputParameters), List.of());
	}

	private static String callString(String contractAddress, String functionName) throws Exception {
		return callString(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Utf8String>() {}))
		);
	}

	private static String callString(String contractAddress, Function function) throws Exception {
		List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
		return ((Utf8String) decoded.get(0)).getValue();
	}

	private static String callAddress(String contractAddress, String functionName) throws Exception {
		return callAddress(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Address>() {}))
		);
	}

	private static String callAddress(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Address>() {})
		);
		List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
		return ((Address) decoded.get(0)).getValue();
	}

	private static byte[] callBytes32(String contractAddress, String functionName) throws Exception {
		return callBytes32(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Bytes32>() {}))
		);
	}

	private static byte[] callBytes32(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Bytes32>() {})
		);
		List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
		return ((Bytes32) decoded.get(0)).getValue();
	}

	private static boolean callBool(String contractAddress, String functionName) throws Exception {
		return callBool(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Bool>() {}))
		);
	}

	private static boolean callBool(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Bool>() {})
		);
		List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
		return ((Bool) decoded.get(0)).getValue();
	}

	private static BigInteger callUint256(String contractAddress, String functionName) throws Exception {
		return callUint256(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Uint256>() {}))
		);
	}

	private static BigInteger callUint256(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Uint256>() {})
		);
		List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
		return ((Uint256) decoded.get(0)).getValue();
	}

	private static void assertTradeStatus(String product, BigInteger expectedStatus, String expectedName) throws Exception {
		List<Type> decoded = SmartContractDeployer.call(
				product,
				new Function("tradeStatus", List.of(), List.of(new TypeReference<Uint8>() {}))
		);
		BigInteger actualStatus = ((Uint8) decoded.get(0)).getValue();
		assertEquals(expectedStatus, actualStatus, "Expected trade status " + expectedName + ".");
	}

	private static byte[] loadResourceBytes(String resourceName) throws Exception {
		try (InputStream inputStream = Demo04EndToEndWorkflow.class.getClassLoader().getResourceAsStream(resourceName)) {
			if (inputStream == null) {
				throw new IllegalArgumentException("Could not find resource on classpath: " + resourceName);
			}
			return inputStream.readAllBytes();
		}
	}

	private static byte[] bytes32FromKeccak256String(String value) {
		return Numeric.hexStringToByteArray(Hash.sha3String(value));
	}

	private static void assertAddressEquals(String expected, String actual, String message) {
		if (!expected.equalsIgnoreCase(actual)) {
			throw new AssertionError(message + " Expected " + expected + ", got " + actual + ".");
		}
	}

	private static void assertBytesEqual(byte[] expected, byte[] actual, String message) {
		if (!Arrays.equals(expected, actual)) {
			throw new AssertionError(
					message + " Expected " + Numeric.toHexString(expected) + ", got " + Numeric.toHexString(actual) + "."
			);
		}
	}

	private static void assertEquals(Object expected, Object actual, String message) {
		if (!expected.equals(actual)) {
			throw new AssertionError(message + " Expected " + expected + ", got " + actual + ".");
		}
	}

	private static void assertTrue(boolean condition, String message) {
		if (!condition) {
			throw new AssertionError(message);
		}
	}

	private static void assertFalse(boolean condition, String message) {
		if (condition) {
			throw new AssertionError(message);
		}
	}

	private static void assertContains(String value, String expectedSubstring) {
		if (!value.toLowerCase().contains(expectedSubstring.toLowerCase())) {
			throw new AssertionError("Expected value to contain: " + expectedSubstring);
		}
	}

	private static void assertNotContains(String value, String unexpectedSubstring) {
		if (value.toLowerCase().contains(unexpectedSubstring.toLowerCase())) {
			throw new AssertionError("Expected value not to contain: " + unexpectedSubstring);
		}
	}

	public static class ProductDefinitionPublicationParams extends DynamicStruct {

		public final Utf8String name;
		public final ProductDefinitionResources resources;

		public ProductDefinitionPublicationParams(Utf8String name, ProductDefinitionResources resources) {
			super(name, resources);
			this.name = name;
			this.resources = resources;
		}
	}

	public static class ProductDefinitionResources extends StaticStruct {

		public final Address termsResource;
		public final Address stylesheetResource;
		public final Bytes32 productTypeId;

		public ProductDefinitionResources(Address termsResource, Address stylesheetResource, Bytes32 productTypeId) {
			super(termsResource, stylesheetResource, productTypeId);
			this.termsResource = termsResource;
			this.stylesheetResource = stylesheetResource;
			this.productTypeId = productTypeId;
		}
	}

	public static class InvestorRegistrationParams extends DynamicStruct {

		public final Address investor;
		public final Utf8String lei;

		public InvestorRegistrationParams(Address investor, Utf8String lei) {
			super(investor, lei);
			this.investor = investor;
			this.lei = lei;
		}
	}

	public static class TradeRequestParams extends DynamicStruct {

		public final Bytes32 productDefinitionId;
		public final Bytes32 productSpecificSchemaHash;
		public final DynamicBytes productSpecificPayload;

		public TradeRequestParams(
				Bytes32 productDefinitionId,
				Bytes32 productSpecificSchemaHash,
				DynamicBytes productSpecificPayload
		) {
			super(productDefinitionId, productSpecificSchemaHash, productSpecificPayload);
			this.productDefinitionId = productDefinitionId;
			this.productSpecificSchemaHash = productSpecificSchemaHash;
			this.productSpecificPayload = productSpecificPayload;
		}
	}

	public static class QuoteParams extends DynamicStruct {

		public final Utf8String symbol;
		public final Int256 durationInDays;
		public final Uint256 settlementDate;
		public final Uint256 maturityDate;
		public final Utf8String dayCountConvention;
		public final Uint256 couponRateBps;
		public final Utf8String currency;
		public final Int256 yieldBps;
		public final Uint256 issuePriceE8;
		public final Uint256 redemptionValueE8;
		public final Uint256 minNotionalE8;
		public final Uint256 maxNotionalE8;

		public QuoteParams(
				Utf8String symbol,
				Int256 durationInDays,
				Uint256 settlementDate,
				Uint256 maturityDate,
				Utf8String dayCountConvention,
				Uint256 couponRateBps,
				Utf8String currency,
				Int256 yieldBps,
				Uint256 issuePriceE8,
				Uint256 redemptionValueE8,
				Uint256 minNotionalE8,
				Uint256 maxNotionalE8
		) {
			super(
					symbol,
					durationInDays,
					settlementDate,
					maturityDate,
					dayCountConvention,
					couponRateBps,
					currency,
					yieldBps,
					issuePriceE8,
					redemptionValueE8,
					minNotionalE8,
					maxNotionalE8
			);
			this.symbol = symbol;
			this.durationInDays = durationInDays;
			this.settlementDate = settlementDate;
			this.maturityDate = maturityDate;
			this.dayCountConvention = dayCountConvention;
			this.couponRateBps = couponRateBps;
			this.currency = currency;
			this.yieldBps = yieldBps;
			this.issuePriceE8 = issuePriceE8;
			this.redemptionValueE8 = redemptionValueE8;
			this.minNotionalE8 = minNotionalE8;
			this.maxNotionalE8 = maxNotionalE8;
		}
	}

	private record PublishedTextResource(String contractAddress, byte[] contentHash) {}

	private record ProductIndicationAssignment(
			String contractAddress,
			byte[] indicationId,
			BigInteger partId
	) {}

	private record DeployedTrade(byte[] tradeId, String productAddress) {}
}
