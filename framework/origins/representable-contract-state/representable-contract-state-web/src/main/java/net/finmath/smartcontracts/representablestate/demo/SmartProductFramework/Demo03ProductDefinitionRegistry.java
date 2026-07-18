package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.*;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.crypto.Hash;
import org.web3j.utils.Numeric;

import java.io.InputStream;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;

public class Demo03ProductDefinitionRegistry {

    static final Path TEXT_RESOURCE_CONTRACT = Path.of("examples", "SmartProductFramework", "TextResource", "TextResource.sol");

    static final Path CLIENT_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "ClientRegistry", "ClientRegistry.sol");

    static final Path TRADABLE_BOND_DATA_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "SimpleBondDemo", "TradableBondDataRegistry.sol");

    private static final String PRODUCT_TERMS_TEMPLATE_PATH = "text-resources/simple-bond-product-terms-template.xml";

    private static final String PRODUCT_DOCUMENTATION_TEMPLATE_PATH = "text-resources/simple-bond-product-documentation-template.xslt";

    private static final String PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE = "BOND_PRODUCT_TERMS_TEMPLATE";
    private static final String PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE = "BOND_PRODUCT_DOCUMENTATION_TEMPLATE";

    private static final String PRODUCT_DEFINITION_NAME = "Simple Bond Demo Product Definition";

    private static final String PRODUCT_TYPE_NAME = "SIMPLE_BOND";

    private static final int DEMO_CHUNK_SIZE = 10_000;

    public static void main(String[] args) throws Exception {

        System.out.println("This demo requires a locally running chain. If not already running, start one with:");
        System.out.println("DEPLOYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYER --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
        System.out.println("-".repeat(79));

        String owner = SmartContractDeployer.defaultSenderAddress();

        System.out.println("Demo 03 - ProductDefinitionRegistry");
        System.out.println("Owner:                   " + owner);
        System.out.println("Product definition name: " + PRODUCT_DEFINITION_NAME);
        System.out.println("Product type name:       " + PRODUCT_TYPE_NAME);
        System.out.println("-".repeat(79));

        System.out.println("Deploying ClientRegistry.");
        String clientRegistry = SmartContractDeployer.deploy(CLIENT_REGISTRY_CONTRACT, SmartContractDeployer.PARIS, new Address(owner));
        System.out.println("ClientRegistry deployed at " + clientRegistry);
        System.out.println("-".repeat(79));

        System.out.println("Deploying TradableBondDataRegistry.");
        String registry = SmartContractDeployer.deploy(TRADABLE_BOND_DATA_REGISTRY_CONTRACT, SmartContractDeployer.PARIS, new Address(owner), new Address(clientRegistry));
        System.out.println("TradableBondDataRegistry deployed at " + registry);
        System.out.println("-".repeat(79));

        PublishedTextResource productTermsTemplate = publishStagedTextResource(
                PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE, "application/xml", PRODUCT_TERMS_TEMPLATE_PATH);

        PublishedTextResource productDocumentationTemplate = publishStagedTextResource(
                PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE, "application/xslt+xml", PRODUCT_DOCUMENTATION_TEMPLATE_PATH);

        byte[] productTypeId = bytes32FromKeccak256String(PRODUCT_TYPE_NAME);

        System.out.println();
        System.out.println("=".repeat(79));
        System.out.println("Publishing ProductDefinition.");
        System.out.println("Registry:                " + registry);
        System.out.println("Product terms template:         " + productTermsTemplate.contractAddress());
        System.out.println("Product documentation template: " + productDocumentationTemplate.contractAddress());
        System.out.println("Product type id:         " + Numeric.toHexString(productTypeId));
        System.out.println("-".repeat(79));

        SmartContractDeployer.transact(registry, new Function("publishProductDefinition",
                        List.of(new ProductDefinitionPublicationParams(
                                new Utf8String(PRODUCT_DEFINITION_NAME),
                                new ProductDefinitionResources(new Address(productTermsTemplate.contractAddress()), new Address(productDocumentationTemplate.contractAddress()), new Bytes32(productTypeId)))),
                        List.of())
        );

        byte[] productDefinitionId = computeProductDefinitionId(registry, PRODUCT_DEFINITION_NAME);

        BigInteger partId = new BigInteger(1, productDefinitionId);

        System.out.println("ProductDefinition published.");
        System.out.println("ProductDefinitionId:     " + Numeric.toHexString(productDefinitionId));
        System.out.println("PartId:                  " + partId);
        System.out.println("-".repeat(79));

        String statePartXmlTemplate = callString(registry, new Function("statePartXmlTemplate", List.of(new Uint256(partId)), List.of(new TypeReference<Utf8String>() {})));

        System.out.println("statePartXmlTemplate(partId):");
        System.out.println();
        System.out.println(statePartXmlTemplate);
        System.out.println();

        assertContains(statePartXmlTemplate, "<ProductDefinition");
        assertContains(statePartXmlTemplate, "productDefinitionId=\"" + Numeric.toHexString(productDefinitionId) + "\"");
        assertContains(statePartXmlTemplate, "xi:include");
        assertContains(statePartXmlTemplate, "parse=\"text\"");
        assertContains(statePartXmlTemplate, productTermsTemplate.contractAddress().toLowerCase());
        assertContains(statePartXmlTemplate, productDocumentationTemplate.contractAddress().toLowerCase());

        System.out.println("ProductDefinition XML wrapper checks passed.");
        System.out.println();

        System.out.println("If the XmlRenderer is running, request the ProductDefinition preview with:");
        System.out.println("http://localhost:8080/xml/part?contract=" + registry + "&partid=" + partId);
        System.out.println();

        System.out.println("Expected rendering behavior:");
        System.out.println("- The renderer calls statePartXmlTemplate(partId) on the registry.");
        System.out.println("- The registry returns a ProductDefinition XML wrapper.");
        System.out.println("- The wrapper includes the product terms template and product documentation template via xi:include.");
        System.out.println("- Because the includes use parse=\"text\", product-specific evmstate:call bindings are not resolved here.");
        System.out.println("- Those bindings resolve later against the deployed SimpleBond product.");
        System.out.println();

        System.out.println("=".repeat(79));
        System.out.println("Demo 03 completed.");
        System.out.println("Registry:                " + registry);
        System.out.println("ProductDefinitionId:     " + Numeric.toHexString(productDefinitionId));
        System.out.println("PartId:                  " + partId);
        System.out.println("Product terms template:         " + productTermsTemplate.contractAddress());
        System.out.println("Product documentation template: " + productDocumentationTemplate.contractAddress());
    }

    private static PublishedTextResource publishStagedTextResource(String resourceTypeName, String mediaType, String classpathResource) throws Exception {

        String owner = SmartContractDeployer.defaultSenderAddress();

        byte[] content = loadResourceBytes(classpathResource);
        byte[] resourceType = bytes32FromKeccak256String(resourceTypeName);
        byte[] expectedContentHash = Hash.sha3(content);

        System.out.println();
        System.out.println("=".repeat(79));
        System.out.println("Publishing TextResource: " + resourceTypeName);
        System.out.println("Classpath resource:      " + classpathResource);
        System.out.println("Media type:              " + mediaType);
        System.out.println("Content length:          " + content.length + " bytes");
        System.out.println("Resource type hash:      " + Numeric.toHexString(resourceType));
        System.out.println("Expected contentHash:    " + Numeric.toHexString(expectedContentHash));
        System.out.println("-".repeat(79));

        String contractAddress = SmartContractDeployer.deploy(
                TEXT_RESOURCE_CONTRACT,
                SmartContractDeployer.PARIS,
                new Address(owner),
                new Bytes32(resourceType),
                new Utf8String(mediaType),
                new DynamicBytes(new byte[0]),
                new Bytes32(new byte[32])
        );

        int chunkCount = 0;

        for (int offset = 0; offset < content.length; offset += DEMO_CHUNK_SIZE) {
            int chunkLength = Math.min(DEMO_CHUNK_SIZE, content.length - offset);
            byte[] chunk = Arrays.copyOfRange(content, offset, offset + chunkLength);

            System.out.println("Appending chunk " + chunkCount + " (" + chunk.length + " bytes)");
            SmartContractDeployer.transact(contractAddress, new Function("appendChunk", List.of(new DynamicBytes(chunk)), List.of()));
            chunkCount++;
        }

        System.out.println("Finalizing resource with " + chunkCount + " chunks.");

        SmartContractDeployer.transact(contractAddress, new Function("finalize", List.of(new Bytes32(expectedContentHash)), List.of()));

        String onChainHash = callStringOrBytes32Hash(contractAddress, "contentHash");
        String text = callString(contractAddress, new Function("text", List.of(), List.of(new TypeReference<Utf8String>() {})));

        assertBytesEqual(content, text.getBytes(StandardCharsets.UTF_8));

        System.out.println("TextResource published.");
        System.out.println("Address:                 " + contractAddress);
        System.out.println("contentHash():           " + onChainHash);
        System.out.println("text() equals resource:  true");

        return new PublishedTextResource(contractAddress, Numeric.toHexString(resourceType), Numeric.toHexString(expectedContentHash));
    }

    private static byte[] computeProductDefinitionId(String registry, String productDefinitionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(registry, new Function("computeProductDefinitionId", List.of(new Utf8String(productDefinitionName)), List.of(new TypeReference<Bytes32>() {})));
        return ((Bytes32) decoded.get(0)).getValue();
    }

    private static String callString(String contractAddress, Function function) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
        return ((Utf8String) decoded.get(0)).getValue();
    }

    private static String callStringOrBytes32Hash(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, new Function(functionName, List.of(), List.of(new TypeReference<Bytes32>() {})));
        return Numeric.toHexString(((Bytes32) decoded.get(0)).getValue());
    }

    private static byte[] loadResourceBytes(String resourceName) throws Exception {
        try (InputStream inputStream = Demo03ProductDefinitionRegistry.class.getClassLoader().getResourceAsStream(resourceName)) {
            if (inputStream == null) {
                throw new IllegalArgumentException("Could not find resource on classpath: " + resourceName);
            }
            return inputStream.readAllBytes();
        }
    }

    private static byte[] bytes32FromKeccak256String(String value) {
        return Numeric.hexStringToByteArray(Hash.sha3String(value));
    }

    private static void assertBytesEqual(byte[] expected, byte[] actual) {
        if (!Arrays.equals(expected, actual)) {
            throw new AssertionError("Byte arrays differ. Expected " + expected.length + " bytes, got " + actual.length + " bytes.");
        }
    }

    private static void assertContains(String value, String expectedSubstring) {
        if (!value.toLowerCase().contains(expectedSubstring.toLowerCase())) {
            throw new AssertionError("Expected XML to contain substring: " + expectedSubstring);
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

        public final Address productTermsTemplate;
        public final Address productDocumentationTemplate;
        public final Bytes32 productTypeId;

        public ProductDefinitionResources(Address productTermsTemplate, Address productDocumentationTemplate, Bytes32 productTypeId) {
            super(productTermsTemplate, productDocumentationTemplate, productTypeId);
            this.productTermsTemplate = productTermsTemplate;
            this.productDocumentationTemplate = productDocumentationTemplate;
            this.productTypeId = productTypeId;
        }
    }

    private static String callBytes32(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, new Function(functionName, List.of(), List.of(new TypeReference<Bytes32>() {})));
        return Numeric.toHexString(((Bytes32) decoded.get(0)).getValue());
    }

    private record PublishedTextResource(
            String contractAddress,
            String resourceTypeHashHex,
            String contentHashHex
    ) {}
}
