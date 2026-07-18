package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Bool;
import org.web3j.abi.datatypes.DynamicBytes;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.Type;
import org.web3j.abi.datatypes.Utf8String;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.crypto.Hash;
import org.web3j.utils.Numeric;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;

public class Demo01TextResources {

    static final Path TEXT_RESOURCE_CONTRACT = Path.of("resources", "TextResource.sol");

    private static final String PRODUCT_TERMS_TEMPLATE_PATH = "text-resources/simple-bond-product-terms-template.xml";

    private static final String PRODUCT_DOCUMENTATION_TEMPLATE_PATH = "text-resources/simple-bond-product-documentation-template.xslt";

    private static final int DEMO_CHUNK_SIZE = 16_000;

    public static void main(String[] args) throws Exception {

        System.out.println("This demo requires a locally running chain. If not already running, start one with:");
        System.out.println("DEPLOYMENT_ACCOUNT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYMENT_ACCOUNT --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
        System.out.println("-".repeat(79));

        PublishedTextResource productTermsTemplate = publishStagedTextResource(
                "BOND_PRODUCT_TERMS_TEMPLATE", "application/xml", PRODUCT_TERMS_TEMPLATE_PATH);

        PublishedTextResource productDocumentationTemplate = publishStagedTextResource(
                "BOND_PRODUCT_DOCUMENTATION_TEMPLATE", "application/xslt+xml", PRODUCT_DOCUMENTATION_TEMPLATE_PATH);

        System.out.println();
        System.out.println("=".repeat(79));
        System.out.println("Demo 01 completed.");
        System.out.println();

        System.out.println("Product terms template:");
        System.out.println("  address:      " + productTermsTemplate.contractAddress());
        System.out.println("  resourceType: " + productTermsTemplate.resourceTypeHashHex());
        System.out.println("  contentHash:  " + productTermsTemplate.contentHashHex());
        System.out.println("  web3Url:      " + productTermsTemplate.web3Url());
        System.out.println();

        System.out.println("Product documentation template:");
        System.out.println("  address:      " + productDocumentationTemplate.contractAddress());
        System.out.println("  resourceType: " + productDocumentationTemplate.resourceTypeHashHex());
        System.out.println("  contentHash:  " + productDocumentationTemplate.contentHashHex());
        System.out.println("  web3Url:      " + productDocumentationTemplate.web3Url());
        System.out.println();

        System.out.println("Use these addresses in Demo 03 when publishing the ProductDefinition.");
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

        /*
         * Staged mode:
         * content_ is empty, expectedContentHash_ is zero.
         */
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

        boolean finalized = callBool(contractAddress, "isFinalized");
        String onChainHash = callBytes32(contractAddress, "contentHash");
        String text = callString(contractAddress, "text");
        String web3Url = callString(contractAddress, "web3Url");

        System.out.println();
        System.out.println("Read-back:");
        System.out.println("isFinalized():         " + finalized);
        System.out.println("contentHash():         " + onChainHash);
        System.out.println("hash matches:          " + onChainHash.equalsIgnoreCase(Numeric.toHexString(expectedContentHash)));
        System.out.println("text length:           " + text.getBytes(StandardCharsets.UTF_8).length + " bytes");
        System.out.println("web3Url():             " + web3Url);

        assertTextEqualsResource(content, text);
        printTextPreview(text, 200);

        return new PublishedTextResource(contractAddress, Numeric.toHexString(resourceType), Numeric.toHexString(expectedContentHash), web3Url);
    }

    private static byte[] loadResourceBytes(String resourceName) throws Exception {
        try (InputStream inputStream = Demo01TextResources.class.getClassLoader().getResourceAsStream(resourceName)) {

            if (inputStream == null) {
                throw new IllegalArgumentException("Could not find resource on classpath: " + resourceName);
            }

            return inputStream.readAllBytes();
        }
    }

    private static byte[] bytes32FromKeccak256String(String value) {
        return Numeric.hexStringToByteArray(Hash.sha3String(value));
    }

    private static boolean callBool(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, new Function(functionName, List.of(), List.of(new TypeReference<Bool>() {})));
        return ((Bool) decoded.get(0)).getValue();
    }

    private static String callBytes32(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, new Function(functionName, List.of(), List.of(new TypeReference<Bytes32>() {})));
        return Numeric.toHexString(((Bytes32) decoded.get(0)).getValue());
    }

    private static String callString(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, new Function(functionName, List.of(), List.of(new TypeReference<Utf8String>() {})));
        return ((Utf8String) decoded.get(0)).getValue();
    }

    private static void assertTextEqualsResource(byte[] expectedContent, String actualText) {
        byte[] actualContent = actualText.getBytes(StandardCharsets.UTF_8);

        if (!Arrays.equals(expectedContent, actualContent)) {
            throw new AssertionError("text() does not match the original resource file. Expected " + expectedContent.length + " bytes, got " + actualContent.length + " bytes.");
        }
        System.out.println("text() equals resource: true");
    }

    private static void printTextPreview(String text, int edgeLength) {
        System.out.println();
        System.out.println("text() preview:");

        if (text.length() <= edgeLength * 2) {
            System.out.println(text);
            return;
        }

        String start = text.substring(0, edgeLength);
        String end = text.substring(text.length() - edgeLength);

        System.out.println(start);
        System.out.println();
        System.out.println("...(" + (text.length()-2*edgeLength) + " bytes omitted from preview)...");
        System.out.println();
        System.out.println(end);
    }

    private record PublishedTextResource(
            String contractAddress,
            String resourceTypeHashHex,
            String contentHashHex,
            String web3Url
    ) {}
}
