package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import net.finmath.smartcontracts.representablestate.xml.EvmXmlRenderer;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.FunctionReturnDecoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Bool;
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
import org.web3j.utils.Convert;
import org.web3j.utils.Numeric;

import java.io.InputStream;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;

/**
 * Focused Smart Product Framework demo for a fixed-versus-floating interest
 * rate swap. It deploys the minimum complete framework stack, publishes the
 * FpML-shaped product resources, creates a request, and performs the
 * ERC-6123-inspired incept/confirm handshake.
 *
 * <p>The embedded private keys are public development keys. Never use them on
 * a chain carrying real assets.</p>
 *
 * @author Christian Fries
 */
public class DemoInterestRateSwap {

	private static final Path TEXT_RESOURCE_CONTRACT = Path.of("resources", "TextResource.sol");
	private static final Path CLIENT_REGISTRY_CONTRACT = Path.of(
			"examples", "SmartProductFramework", "ClientRegistry", "ClientRegistry.sol"
	);
	private static final Path SWAP_PRODUCT_REGISTRY_CONTRACT = Path.of(
			"examples", "SmartProductFramework", "InterestRateSwapDemo", "InterestRateSwapProductRegistry.sol"
	);
	private static final Path PRODUCT_FACTORY_REGISTRY_CONTRACT = Path.of(
			"examples", "SmartProductFramework", "ProductFactory", "ProductFactoryRegistry.sol"
	);
	private static final Path SWAP_FACTORY_CONTRACT = Path.of(
			"examples", "SmartProductFramework", "InterestRateSwapDemo", "InterestRateSwapFactory.sol"
	);

	private static final String RPC_URL = "http://127.0.0.1:8545";
	private static final String RENDERER_XML_URL = "http://localhost:8080/xml";
	private static final BigInteger GAS_PRICE = BigInteger.valueOf(1_000_000_000L);
	private static final BigInteger GAS_LIMIT = BigInteger.valueOf(20_000_000L);
	private static final BigInteger CLIENT_TARGET_BALANCE = Convert.toWei("1", Convert.Unit.ETHER)
			.toBigIntegerExact();

	// Public Anvil/Hardhat development accounts used elsewhere in this project.
	private static final String PRODUCT_PROVIDER_PRIVATE_KEY =
			"0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
	private static final String CLIENT_PRIVATE_KEY =
			"0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a";

	private static final String CLIENT_LEI = "529900T8BM49AURSDO55";
	private static final String PRODUCT_DEFINITION_NAME = "EUR Fixed-Floating Interest Rate Swap";
	private static final String PRODUCT_TYPE = "INTEREST_RATE_SWAP";
	private static final String PRODUCT_SPECIFIC_PAYLOAD_SCHEMA =
			"v1:InterestRateSwapDeploymentPayload(uint256 notional,string currency,uint256 maturity,"
					+ "int256 swapRate,uint8 clientFixedRateRole,string forwardCurveSymbol,"
					+ "string discountCurveSymbol)";
	private static final String PRODUCT_TERMS_TEMPLATE_PATH =
			"text-resources/interest-rate-swap-product-terms-template.xml";
	private static final String PRODUCT_DOCUMENTATION_TEMPLATE_PATH =
			"text-resources/interest-rate-swap-product-documentation-template.xslt";
	private static final String PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE =
			"INTEREST_RATE_SWAP_PRODUCT_TERMS_TEMPLATE";
	private static final String PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE =
			"INTEREST_RATE_SWAP_PRODUCT_DOCUMENTATION_TEMPLATE";
	private static final int RESOURCE_CHUNK_SIZE = 10_000;

	private static final BigInteger STATUS_REQUESTED = BigInteger.ZERO;
	private static final BigInteger STATUS_INCEPTED = BigInteger.ONE;
	private static final BigInteger STATUS_ACTIVE = BigInteger.TWO;
	private static final BigInteger CLIENT_FIXED_RATE_PAYER = BigInteger.ZERO;
	private static final BigInteger CLIENT_FIXED_RATE_RECEIVER = BigInteger.ONE;

	private static final String TRADE_REQUEST_CREATED_EVENT_SIGNATURE =
			Hash.sha3String("TradeRequestCreated(bytes32,address,address,bytes32,bytes32,address)");

	private DemoInterestRateSwap() {
	}

	/**
	 * Runs the complete local swap example.
	 *
	 * @param args ignored
	 * @throws Exception if compilation, deployment, a transaction, or rendering fails
	 */
	public static void main(String[] args) throws Exception {

		printChainInstructions();

		String productProvider = Credentials.create(PRODUCT_PROVIDER_PRIVATE_KEY).getAddress();
		String client = Credentials.create(CLIENT_PRIVATE_KEY).getAddress();
		assertAddressEquals(
				SmartContractDeployer.defaultSenderAddress(),
				productProvider,
				"Product-provider signer mismatch."
		);
		ensureClientFunded(productProvider, client);

		System.out.println("Smart Product Framework interest-rate-swap demo");
		System.out.println("Product provider:         " + productProvider);
		System.out.println("Client:                   " + client);
		System.out.println("-".repeat(79));

		String clientRegistry = SmartContractDeployer.deploy(
				CLIENT_REGISTRY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider)
		);
		String productRegistry = SmartContractDeployer.deploy(
				SWAP_PRODUCT_REGISTRY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider),
				new Address(clientRegistry)
		);
		String genericFactory = SmartContractDeployer.deploy(
				PRODUCT_FACTORY_REGISTRY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(productProvider),
				new Address(productRegistry)
		);
		SmartContractDeployer.transact(
				productRegistry,
				function("setProductFactory", new Address(genericFactory))
		);

		String swapFactory = SmartContractDeployer.deploy(
				SWAP_FACTORY_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(genericFactory)
		);
		byte[] productTypeId = callBytes32(swapFactory, "productTypeId");
		assertBytesEqual(
				bytes32FromKeccak256String(PRODUCT_TYPE),
				productTypeId,
				"Unexpected swap product type."
		);
		SmartContractDeployer.transact(
				genericFactory,
				function("registerProductFactory", new Bytes32(productTypeId), new Address(swapFactory))
		);
		assertTrue(
				callBool(genericFactory, function("canDeployProduct", new Bytes32(productTypeId))),
				"The registered swap type is not deployable."
		);

		PublishedTextResource productTermsTemplate = publishTextResource(
				PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE,
				"application/xml",
				PRODUCT_TERMS_TEMPLATE_PATH
		);
		PublishedTextResource productDocumentationTemplate = publishTextResource(
				PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE,
				"application/xslt+xml",
				PRODUCT_DOCUMENTATION_TEMPLATE_PATH
		);

		TransactionReceipt productDefinitionPublicationReceipt = SmartContractDeployer.transact(
				productRegistry,
				function(
						"publishProductDefinition",
						new ProductDefinitionPublicationParams(
								new Utf8String(PRODUCT_DEFINITION_NAME),
								new ProductDefinitionResources(
										new Address(productTermsTemplate.contractAddress()),
										new Address(productDocumentationTemplate.contractAddress()),
										new Bytes32(productTypeId)
								)
						)
				)
		);
		byte[] productDefinitionId = callBytes32(
				productRegistry,
				function("computeProductDefinitionId", new Utf8String(PRODUCT_DEFINITION_NAME))
		);
		BigInteger productDefinitionPartId = new BigInteger(1, productDefinitionId);

		SmartContractDeployer.transact(
				clientRegistry,
				function(
						"registerClient",
						new ClientRegistrationParams(new Address(client), new Utf8String(CLIENT_LEI))
				)
		);

		String payloadSchema = callString(swapFactory, "productSpecificPayloadSchema");
		byte[] payloadSchemaHash = callBytes32(swapFactory, "productSpecificSchemaHash");
		assertEquals(
				PRODUCT_SPECIFIC_PAYLOAD_SCHEMA,
				payloadSchema,
				"Unexpected swap payload schema."
		);
		assertBytesEqual(
				Hash.sha3(payloadSchema.getBytes(StandardCharsets.UTF_8)),
				payloadSchemaHash,
				"Factory schema string and hash differ."
		);

		long now = Instant.now().getEpochSecond();
		BigInteger notional = BigInteger.valueOf(100_000_000L); // EUR 1,000,000.00, scale 2
		String currency = "EUR";
		BigInteger maturity = BigInteger.valueOf(now + 5L * 365 * 24 * 60 * 60);
		BigInteger swapRate = BigInteger.valueOf(250); // 0.0250, scale 4 = 2.50%
		String forwardCurveSymbol = "EUR-EURIBOR-3M";
		String discountCurveSymbol = "EUR-ESTR-OIS";

		byte[] payload = encodeSwapPayload(
				notional,
				currency,
				maturity,
				swapRate,
				CLIENT_FIXED_RATE_PAYER,
				forwardCurveSymbol,
				discountCurveSymbol
		);

		System.out.println("Product definition:       " + Numeric.toHexString(productDefinitionId));
		System.out.println("Payload schema:           " + payloadSchema);
		System.out.println("Notional:                 1000000.00 " + currency);
		System.out.println("Fixed rate:               0.0250 (2.50%)");
		System.out.println("Client fixed-leg role:    Payer");
		System.out.println("Forward curve:            " + forwardCurveSymbol);
		System.out.println("Discount curve:           " + discountCurveSymbol);
		System.out.println("-".repeat(79));

		TransactionReceipt requestReceipt = transactAs(
				CLIENT_PRIVATE_KEY,
				productRegistry,
				function(
						"createTradeRequest",
						new TradeRequestParams(
								new Bytes32(productDefinitionId),
								new Bytes32(payloadSchemaHash),
								new DynamicBytes(payload)
						)
				)
		);
		DeployedTrade deployedTrade = decodeTradeRequestCreated(productRegistry, requestReceipt);
		String product = deployedTrade.productAddress();
		System.out.println("Client requested the swap at block " + requestReceipt.getBlockNumber() + ".");
		System.out.println("Swap product:             " + product);
		System.out.println("-".repeat(79));

		assertTradeStatus(product, STATUS_REQUESTED, "Requested");
		assertEquals(notional, callUint256(product, "notional"), "Notional mismatch.");
		assertEquals(currency, callString(product, "currency"), "Currency mismatch.");
		assertEquals(maturity, callUint256(product, "maturity"), "Maturity mismatch.");
		assertEquals(swapRate, callInt256(product, "swapRate"), "Swap rate mismatch.");
		assertEquals(
				CLIENT_FIXED_RATE_PAYER,
				callUint8(product, "clientFixedRateRole"),
				"Client fixed-rate role mismatch."
		);
		assertEquals(
				forwardCurveSymbol,
				callString(product, "forwardCurveSymbol"),
				"Forward curve mismatch."
		);
		assertEquals(
				discountCurveSymbol,
				callString(product, "discountCurveSymbol"),
				"Discount curve mismatch."
		);

		byte[] initialTermsHash = callBytes32(product, "currentTermsHash");
		BigInteger amendedNotional = BigInteger.valueOf(125_000_000L); // EUR 1,250,000.00, scale 2
		BigInteger amendedMaturity = BigInteger.valueOf(now + 6L * 365 * 24 * 60 * 60);
		BigInteger amendedSwapRate = BigInteger.valueOf(275); // 0.0275, scale 4 = 2.75%
		byte[] amendedPayload = encodeSwapPayload(
				amendedNotional,
				currency,
				amendedMaturity,
				amendedSwapRate,
				CLIENT_FIXED_RATE_RECEIVER,
				forwardCurveSymbol,
				discountCurveSymbol
		);

		TransactionReceipt amendmentReceipt = transactAs(
				CLIENT_PRIVATE_KEY,
				product,
				function("updateTerms", new DynamicBytes(amendedPayload))
		);
		assertTradeStatus(product, STATUS_REQUESTED, "Requested after amendment");
		assertEquals(amendedNotional, callUint256(product, "notional"), "Amended notional mismatch.");
		assertEquals(amendedMaturity, callUint256(product, "maturity"), "Amended maturity mismatch.");
		assertEquals(amendedSwapRate, callInt256(product, "swapRate"), "Amended swap rate mismatch.");
		assertEquals(
				CLIENT_FIXED_RATE_RECEIVER,
				callUint8(product, "clientFixedRateRole"),
				"Amended client fixed-rate role mismatch."
		);
		assertEquals(currency, callString(product, "currency"), "Currency changed during amendment.");
		assertEquals(
				forwardCurveSymbol,
				callString(product, "forwardCurveSymbol"),
				"Forward curve changed during amendment."
		);
		assertEquals(
				discountCurveSymbol,
				callString(product, "discountCurveSymbol"),
				"Discount curve changed during amendment."
		);

		byte[] agreedTermsHash = callBytes32(product, "currentTermsHash");
		assertTrue(!Arrays.equals(initialTermsHash, agreedTermsHash), "Terms hash did not change after amendment.");
		System.out.println("Client amended the requested swap at block " + amendmentReceipt.getBlockNumber() + ".");
		System.out.println("Amended notional:         1250000.00 " + currency);
		System.out.println("Amended fixed rate:       0.0275 (2.75%)");
		System.out.println("Amended fixed-leg role:   Receiver");
		System.out.println("-".repeat(79));

		TransactionReceipt inceptionReceipt = SmartContractDeployer.transact(
				product,
				function("inceptTrade", new Bytes32(agreedTermsHash))
		);
		assertTradeStatus(product, STATUS_INCEPTED, "Incepted");
		assertBytesEqual(
				agreedTermsHash,
				callBytes32(product, "agreedTermsHash"),
				"Stored agreed terms hash mismatch."
		);
		System.out.println("Product provider incepted the agreed terms at block "
				+ inceptionReceipt.getBlockNumber() + ".");

		TransactionReceipt confirmationReceipt = transactAs(
				CLIENT_PRIVATE_KEY,
				product,
				function("confirmTrade", new Bytes32(agreedTermsHash))
		);
		assertTradeStatus(product, STATUS_ACTIVE, "Active");
		System.out.println("Client confirmed the agreed terms at block "
				+ confirmationReceipt.getBlockNumber() + ".");
		System.out.println("-".repeat(79));

		EvmXmlRenderer renderer = new EvmXmlRenderer(RPC_URL);
		String productDefinitionIdHex = Numeric.toHexString(productDefinitionId);
		StatePartCheckpoint definitionPublishedCheckpoint = renderStatePartCheckpoint(
				renderer,
				productRegistry,
				productDefinitionPartId,
				"Definition published",
				productDefinitionPublicationReceipt,
				"<ProductDefinition",
				"<ProductResources>",
				"<ProductTermsTemplate>",
				"<ProductDocumentationTemplate>",
				"<ProductIndicationAssignment assigned=\"false\"/>",
				"productDefinitionId=\"" + productDefinitionIdHex + "\"",
				"status=\"1\"",
				"productDefinitionVersion=\"1\""
		);
		List<StatePartCheckpoint> productDefinitionCheckpoints = List.of(definitionPublishedCheckpoint);

		SwapTerms initialTerms = new SwapTerms(
				notional,
				currency,
				maturity,
				swapRate,
				CLIENT_FIXED_RATE_PAYER,
				forwardCurveSymbol,
				discountCurveSymbol
		);
		SwapTerms amendedTerms = new SwapTerms(
				amendedNotional,
				currency,
				amendedMaturity,
				amendedSwapRate,
				CLIENT_FIXED_RATE_RECEIVER,
				forwardCurveSymbol,
				discountCurveSymbol
		);

		ProductStateCheckpoint requestedInitialCheckpoint = renderProductCheckpoint(
				renderer,
				product,
				"Requested / initial terms",
				requestReceipt,
				STATUS_REQUESTED,
				initialTerms
		);
		ProductStateCheckpoint requestedAmendedCheckpoint = renderProductCheckpoint(
				renderer,
				product,
				"Requested / amended terms",
				amendmentReceipt,
				STATUS_REQUESTED,
				amendedTerms
		);
		ProductStateCheckpoint inceptedCheckpoint = renderProductCheckpoint(
				renderer,
				product,
				"Incepted / agreed terms",
				inceptionReceipt,
				STATUS_INCEPTED,
				amendedTerms
		);
		ProductStateCheckpoint activeCheckpoint = renderProductCheckpoint(
				renderer,
				product,
				"Active / confirmed terms",
				confirmationReceipt,
				STATUS_ACTIVE,
				amendedTerms
		);
		List<ProductStateCheckpoint> productStateCheckpoints = List.of(
				requestedInitialCheckpoint,
				requestedAmendedCheckpoint,
				inceptedCheckpoint,
				activeCheckpoint
		);

		assertNotContains(requestedInitialCheckpoint.renderedState(), "1250000.00");
		assertNotContains(
				requestedInitialCheckpoint.renderedState(),
				"<fpml:initialValue>0.0275</fpml:initialValue>"
		);
		assertNotContains(
				requestedInitialCheckpoint.renderedState(),
				"<spf:clientFixedRateRole>Receiver</spf:clientFixedRateRole>"
		);
		assertNotContains(requestedAmendedCheckpoint.renderedState(), "1000000.00");
		assertNotContains(
				requestedAmendedCheckpoint.renderedState(),
				"<fpml:initialValue>0.0250</fpml:initialValue>"
		);
		assertNotContains(
				requestedAmendedCheckpoint.renderedState(),
				"<spf:clientFixedRateRole>Payer</spf:clientFixedRateRole>"
		);
		assertCheckpointOrder("Product lifecycle", productStateCheckpoints);

		System.out.println("=".repeat(79));
		System.out.println("Interest-rate-swap demo completed.");
		System.out.println("Product registry:         " + productRegistry);
		System.out.println("Generic factory:          " + genericFactory);
		System.out.println("Swap factory:             " + swapFactory);
		System.out.println("Trade id:                 " + Numeric.toHexString(deployedTrade.tradeId()));
		System.out.println("Swap product:             " + product);
		System.out.println("Latest product XML:       " + rendererUrl(product, null));
		System.out.println("-".repeat(79));
		System.out.println("Contract state checkpoint renderings grouped by contract:");
		printCheckpointGroup("Product-definition registry", productRegistry, productDefinitionCheckpoints);
		printCheckpointGroup("Product lifecycle", product, productStateCheckpoints);
	}

	private static StatePartCheckpoint renderStatePartCheckpoint(
			EvmXmlRenderer renderer,
			String contractAddress,
			BigInteger partId,
			String name,
			TransactionReceipt receipt,
			String... expectedSubstrings
	) throws Exception {
		BigInteger blockNumber = checkpointBlock(receipt, name);
		String renderedState = renderer.renderPart(contractAddress, blockNumber, partId);

		assertContains(renderedState, "evmstate:block-number=\"" + blockNumber + "\"");
		for (String expectedSubstring : expectedSubstrings) {
			assertContains(renderedState, expectedSubstring);
		}

		String rendererUrl = rendererPartUrl(contractAddress, partId, blockNumber);
		System.out.println("Rendered state part:       " + name);
		System.out.println("Checkpoint block:          " + blockNumber);
		System.out.println("Checkpoint XML endpoint:   " + rendererUrl);
		System.out.println("-".repeat(79));

		return new StatePartCheckpoint(name, blockNumber, renderedState, rendererUrl);
	}

	private static ProductStateCheckpoint renderProductCheckpoint(
			EvmXmlRenderer renderer,
			String product,
			String name,
			TransactionReceipt receipt,
			BigInteger expectedStatus,
			SwapTerms expectedTerms
	) throws Exception {
		BigInteger blockNumber = checkpointBlock(receipt, name);

		String xml = renderer.render(product, blockNumber);
		assertNotContains(xml, "evmstate:call=");
		assertNotContains(xml, "evmstate:args=");
		assertContains(xml, "evmstate:block-number=\"" + blockNumber + "\"");
		assertContains(xml, "<InterestRateSwap");
		assertContains(xml, "<ProductResources>");
		assertContains(xml, "<ProductTermsTemplate>");
		assertContains(xml, "<spf:InterestRateSwapTerms");
		assertContains(xml, "<ProductDocumentationTemplate>");
		assertContains(xml, "<xsl:stylesheet");
		assertContains(xml, "<TradeStatus>" + expectedStatus + "</TradeStatus>");
		assertContains(xml, "<fpml:dataDocument");
		assertContains(xml, "<fpml:swapStream id=\"fixedLeg\"");
		assertContains(
				xml,
				"<spf:clientFixedRateRole>" + fixedRateRoleName(expectedTerms.clientFixedRateRole())
						+ "</spf:clientFixedRateRole>"
		);
		assertContains(xml, new BigDecimal(expectedTerms.notional(), 2).toPlainString());
		assertContains(xml, expectedTerms.currency());
		assertContains(xml, isoDate(expectedTerms.maturity()));
		assertContains(xml, new BigDecimal(expectedTerms.swapRate(), 4).toPlainString());
		assertContains(xml, expectedTerms.forwardCurveSymbol());
		assertContains(xml, expectedTerms.discountCurveSymbol());

		String rendererUrl = rendererUrl(product, blockNumber);
		System.out.println("Rendered checkpoint:       " + name);
		System.out.println("Checkpoint block:          " + blockNumber);
		System.out.println("Checkpoint XML endpoint:   " + rendererUrl);
		System.out.println("-".repeat(79));

		return new ProductStateCheckpoint(name, blockNumber, xml, rendererUrl);
	}

	private static PublishedTextResource publishTextResource(
			String resourceTypeName,
			String mediaType,
			String classpathResource
	) throws Exception {
		byte[] content = loadResourceBytes(classpathResource);
		byte[] expectedContentHash = Hash.sha3(content);
		String contractAddress = SmartContractDeployer.deploy(
				TEXT_RESOURCE_CONTRACT,
				SmartContractDeployer.CANCUN,
				new Address(SmartContractDeployer.defaultSenderAddress()),
				new Bytes32(bytes32FromKeccak256String(resourceTypeName)),
				new Utf8String(mediaType),
				new DynamicBytes(new byte[0]),
				new Bytes32(new byte[32])
		);

		for (int offset = 0; offset < content.length; offset += RESOURCE_CHUNK_SIZE) {
			byte[] chunk = Arrays.copyOfRange(
					content,
					offset,
					Math.min(offset + RESOURCE_CHUNK_SIZE, content.length)
			);
			SmartContractDeployer.transact(
					contractAddress,
					function("appendChunk", new DynamicBytes(chunk))
			);
		}
		SmartContractDeployer.transact(
				contractAddress,
				function("finalize", new Bytes32(expectedContentHash))
		);

		assertTrue(callBool(contractAddress, "isFinalized"), "Text resource was not finalized.");
		assertBytesEqual(
				expectedContentHash,
				callBytes32(contractAddress, "contentHash"),
				"Text resource content hash mismatch."
		);
		String web3Url = callString(contractAddress, "web3Url");
		System.out.println("Published resource:       " + resourceTypeName);
		System.out.println("Resource address:         " + contractAddress);
		System.out.println("Resource Web3 URL:        " + web3Url);
		System.out.println("-".repeat(79));

		return new PublishedTextResource(contractAddress);
	}

	private static byte[] encodeSwapPayload(
			BigInteger notional,
			String currency,
			BigInteger maturity,
			BigInteger swapRate,
			BigInteger clientFixedRateRole,
			String forwardCurveSymbol,
			String discountCurveSymbol
	) {
		String encoded = FunctionEncoder.encodeConstructor(List.of(
				new SwapProductSpecificPayload(
						new Uint256(notional),
						new Utf8String(currency),
						new Uint256(maturity),
						new Int256(swapRate),
						new Uint8(clientFixedRateRole),
						new Utf8String(forwardCurveSymbol),
						new Utf8String(discountCurveSymbol)
				)
		));
		return Numeric.hexStringToByteArray(encoded);
	}

	private static DeployedTrade decodeTradeRequestCreated(
			String registry,
			TransactionReceipt receipt
	) {
		for (Log log : receipt.getLogs()) {
			if (!registry.equalsIgnoreCase(log.getAddress()) || log.getTopics().size() < 4) {
				continue;
			}
			if (!TRADE_REQUEST_CREATED_EVENT_SIGNATURE.equalsIgnoreCase(log.getTopics().getFirst())) {
				continue;
			}

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

			return new DeployedTrade(
					Numeric.hexStringToByteArray(log.getTopics().get(1)),
					((Address) decoded.get(2)).getValue()
			);
		}
		throw new IllegalStateException("TradeRequestCreated event not found.");
	}

	private static void ensureClientFunded(String productProvider, String client) throws Exception {
		Web3j web3 = Web3j.build(new HttpService(RPC_URL));
		try {
			BigInteger balance = web3.ethGetBalance(client, DefaultBlockParameterName.LATEST).send().getBalance();
			if (balance.compareTo(CLIENT_TARGET_BALANCE) >= 0) {
				return;
			}

			BigInteger topUp = CLIENT_TARGET_BALANCE.subtract(balance);
			long chainId = web3.ethChainId().send().getChainId().longValueExact();
			RawTransactionManager transactionManager = new RawTransactionManager(
					web3,
					Credentials.create(PRODUCT_PROVIDER_PRIVATE_KEY),
					chainId
			);
			assertAddressEquals(productProvider, transactionManager.getFromAddress(), "Funding signer mismatch.");
			EthSendTransaction response = transactionManager.sendTransaction(
					GAS_PRICE,
					BigInteger.valueOf(21_000),
					client,
					"0x",
					topUp
			);
			checkSendResponse(response, "fund client");
			TransactionReceipt receipt = receiptProcessor(web3)
					.waitForTransactionReceipt(response.getTransactionHash());
			checkReceipt(receipt, "fund client");
			System.out.println("Funded client with "
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
			RawTransactionManager transactionManager = new RawTransactionManager(
					web3,
					Credentials.create(privateKey),
					chainId
			);
			EthSendTransaction response = transactionManager.sendTransaction(
					GAS_PRICE,
					GAS_LIMIT,
					contractAddress,
					FunctionEncoder.encode(function),
					BigInteger.ZERO
			);
			checkSendResponse(response, function.getName());
			TransactionReceipt receipt = receiptProcessor(web3)
					.waitForTransactionReceipt(response.getTransactionHash());
			checkReceipt(receipt, function.getName());
			return receipt;
		}
		finally {
			web3.shutdown();
		}
	}

	private static PollingTransactionReceiptProcessor receiptProcessor(Web3j web3) {
		return new PollingTransactionReceiptProcessor(web3, 2_000, 120);
	}

	private static void checkSendResponse(EthSendTransaction response, String operation) {
		if (response.hasError()) {
			throw new IllegalStateException(
					"Could not send " + operation + ": " + response.getError().getMessage()
			);
		}
	}

	private static void checkReceipt(TransactionReceipt receipt, String operation) {
		if (!receipt.isStatusOK()) {
			throw new IllegalStateException(
					"Transaction failed for " + operation + ": " + receipt.getTransactionHash()
			);
		}
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

	private static String callString(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Utf8String>() {})
		);
		return ((Utf8String) SmartContractDeployer.call(contractAddress, function).getFirst()).getValue();
	}

	private static byte[] callBytes32(String contractAddress, String functionName) throws Exception {
		return callBytes32(contractAddress, function(functionName));
	}

	private static byte[] callBytes32(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Bytes32>() {})
		);
		return ((Bytes32) SmartContractDeployer.call(contractAddress, function).getFirst()).getValue();
	}

	private static boolean callBool(String contractAddress, String functionName) throws Exception {
		return callBool(contractAddress, function(functionName));
	}

	private static boolean callBool(String contractAddress, Function inputOnlyFunction) throws Exception {
		Function function = new Function(
				inputOnlyFunction.getName(),
				inputOnlyFunction.getInputParameters(),
				List.of(new TypeReference<Bool>() {})
		);
		return ((Bool) SmartContractDeployer.call(contractAddress, function).getFirst()).getValue();
	}

	private static BigInteger callUint256(String contractAddress, String functionName) throws Exception {
		List<Type> decoded = SmartContractDeployer.call(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Uint256>() {}))
		);
		return ((Uint256) decoded.getFirst()).getValue();
	}

	private static BigInteger callInt256(String contractAddress, String functionName) throws Exception {
		List<Type> decoded = SmartContractDeployer.call(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Int256>() {}))
		);
		return ((Int256) decoded.getFirst()).getValue();
	}

	private static BigInteger callUint8(String contractAddress, String functionName) throws Exception {
		List<Type> decoded = SmartContractDeployer.call(
				contractAddress,
				new Function(functionName, List.of(), List.of(new TypeReference<Uint8>() {}))
		);
		return ((Uint8) decoded.getFirst()).getValue();
	}

	private static void assertTradeStatus(
			String product,
			BigInteger expectedStatus,
			String statusName
	) throws Exception {
		assertEquals(
				expectedStatus,
				callUint8(product, "tradeStatus"),
				"Expected " + statusName + " trade status."
		);
	}

	private static byte[] loadResourceBytes(String resourceName) throws Exception {
		try (InputStream stream = DemoInterestRateSwap.class.getClassLoader().getResourceAsStream(resourceName)) {
			if (stream == null) {
				throw new IllegalArgumentException("Could not find classpath resource: " + resourceName);
			}
			return stream.readAllBytes();
		}
	}

	private static byte[] bytes32FromKeccak256String(String value) {
		return Numeric.hexStringToByteArray(Hash.sha3String(value));
	}

	private static String rendererUrl(String contractAddress, BigInteger blockNumber) {
		String url = RENDERER_XML_URL + "?contract=" + contractAddress;
		return blockNumber == null ? url : url + "&block=" + blockNumber;
	}

	private static String rendererPartUrl(String contractAddress, BigInteger partId, BigInteger blockNumber) {
		return RENDERER_XML_URL + "/part?contract=" + contractAddress
				+ "&partid=" + partId
				+ "&block=" + blockNumber;
	}

	private static BigInteger checkpointBlock(TransactionReceipt receipt, String checkpointName) {
		BigInteger blockNumber = receipt.getBlockNumber();
		if (blockNumber == null) {
			throw new IllegalStateException("Checkpoint transaction has no block number: " + checkpointName);
		}
		return blockNumber;
	}

	private static void assertCheckpointOrder(
			String groupName,
			List<? extends StateCheckpoint> checkpoints
	) {
		for (int index = 1; index < checkpoints.size(); index++) {
			StateCheckpoint previous = checkpoints.get(index - 1);
			StateCheckpoint current = checkpoints.get(index);
			assertTrue(
					previous.blockNumber().compareTo(current.blockNumber()) < 0,
					"Checkpoint block for " + current.name() + " in " + groupName
							+ " must be later than " + previous.name() + "."
			);
		}
	}

	private static void printCheckpointGroup(
			String groupName,
			String contractAddress,
			List<? extends StateCheckpoint> checkpoints
	) {
		System.out.println(groupName + " (" + contractAddress + "):");
		for (StateCheckpoint checkpoint : checkpoints) {
			System.out.println("- " + checkpoint.name() + " (block " + checkpoint.blockNumber() + "):");
			System.out.println("  " + checkpoint.rendererUrl());
		}
	}

	private static String isoDate(BigInteger epochSeconds) {
		return Instant.ofEpochSecond(epochSeconds.longValueExact())
				.atZone(ZoneOffset.UTC)
				.toLocalDate()
				.toString();
	}

	private static String fixedRateRoleName(BigInteger role) {
		if (CLIENT_FIXED_RATE_PAYER.equals(role)) {
			return "Payer";
		}
		if (CLIENT_FIXED_RATE_RECEIVER.equals(role)) {
			return "Receiver";
		}
		throw new IllegalArgumentException("Unsupported client fixed-rate role: " + role);
	}

	private static void printChainInstructions() {
		System.out.println("This demo requires a locally running Cancun-capable chain. For example:");
		System.out.println("anvil --chain-id 1337 --hardfork cancun");
		System.out.println("-".repeat(79));
	}

	private static void assertAddressEquals(String expected, String actual, String message) {
		if (!expected.equalsIgnoreCase(actual)) {
			throw new AssertionError(message + " Expected " + expected + ", got " + actual + ".");
		}
	}

	private static void assertBytesEqual(byte[] expected, byte[] actual, String message) {
		if (!Arrays.equals(expected, actual)) {
			throw new AssertionError(message);
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

	private static void assertContains(String value, String expectedSubstring) {
		if (!value.toLowerCase().contains(expectedSubstring.toLowerCase())) {
			throw new AssertionError("Expected XML to contain: " + expectedSubstring);
		}
	}

	private static void assertNotContains(String value, String unexpectedSubstring) {
		if (value.toLowerCase().contains(unexpectedSubstring.toLowerCase())) {
			throw new AssertionError("Expected XML not to contain: " + unexpectedSubstring);
		}
	}

	private static class ProductDefinitionPublicationParams extends DynamicStruct {

		public ProductDefinitionPublicationParams(Utf8String name, ProductDefinitionResources resources) {
			super(name, resources);
		}
	}

	private static class ProductDefinitionResources extends StaticStruct {

		public ProductDefinitionResources(
				Address productTermsTemplate,
				Address productDocumentationTemplate,
				Bytes32 productTypeId
		) {
			super(productTermsTemplate, productDocumentationTemplate, productTypeId);
		}
	}

	private static class ClientRegistrationParams extends DynamicStruct {

		public ClientRegistrationParams(Address client, Utf8String lei) {
			super(client, lei);
		}
	}

	private static class TradeRequestParams extends DynamicStruct {

		public TradeRequestParams(
				Bytes32 productDefinitionId,
				Bytes32 productSpecificSchemaHash,
				DynamicBytes productSpecificPayload
		) {
			super(productDefinitionId, productSpecificSchemaHash, productSpecificPayload);
		}
	}

	/** ABI representation of the factory's dynamic product-specific tuple. */
	private static class SwapProductSpecificPayload extends DynamicStruct {

		public SwapProductSpecificPayload(
				Uint256 notional,
				Utf8String currency,
				Uint256 maturity,
				Int256 swapRate,
				Uint8 clientFixedRateRole,
				Utf8String forwardCurveSymbol,
				Utf8String discountCurveSymbol
		) {
			super(
					notional,
					currency,
					maturity,
					swapRate,
					clientFixedRateRole,
					forwardCurveSymbol,
					discountCurveSymbol
			);
		}
	}

	private record PublishedTextResource(String contractAddress) {}

	private record DeployedTrade(byte[] tradeId, String productAddress) {}

	private record SwapTerms(
			BigInteger notional,
			String currency,
			BigInteger maturity,
			BigInteger swapRate,
			BigInteger clientFixedRateRole,
			String forwardCurveSymbol,
			String discountCurveSymbol
	) {}

	private interface StateCheckpoint {

		String name();

		BigInteger blockNumber();

		String rendererUrl();
	}

	private record StatePartCheckpoint(
			String name,
			BigInteger blockNumber,
			String renderedState,
			String rendererUrl
	) implements StateCheckpoint {}

	private record ProductStateCheckpoint(
			String name,
			BigInteger blockNumber,
			String renderedState,
			String rendererUrl
	) implements StateCheckpoint {}
}
