package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework.TextResource;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
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

public class DemoTextResourceStaged {

    static final Path TEXT_RESOURCE_CONTRACT = Path.of(
            "examples",
            "SmartProductFramework",
            "TextResource",
            "TextResource.sol"
    );

    private static final String TEMPLATE_RESOURCE =
            "product-terms/demo-product-terms-template.xml";

    private static final String RESOURCE_TYPE_NAME = "PRODUCT_TERMS_XML";
    private static final String MEDIA_TYPE = "application/xml";

    private static final int DEMO_CHUNK_SIZE = 16_000;

    public static void main(String[] args) throws Exception {

        System.out.println("This demo requires a locally running chain. If not already running, start one with:");
        System.out.println("DEPLOYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYER --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
        System.out.println("-".repeat(79));

        String owner = SmartContractDeployer.defaultSenderAddress();

        byte[] content = loadResourceBytes(TEMPLATE_RESOURCE);
        byte[] resourceType = bytes32FromKeccak256String(RESOURCE_TYPE_NAME);
        byte[] expectedContentHash = Hash.sha3(content);

        System.out.println("Loaded XML template from resources:");
        System.out.println("Resource:              " + TEMPLATE_RESOURCE);
        System.out.println("Content length:        " + content.length + " bytes");
        System.out.println("Expected contentHash:  " + Numeric.toHexString(expectedContentHash));
        System.out.println("Resource type hash:    " + Numeric.toHexString(resourceType));
        System.out.println("-".repeat(79));

        /*
         * Staged mode:
         * content_ is empty, expectedContentHash_ is zero.
         * The constructor does NOT finalize. We append chunks afterwards.
         */
        String contractAddress = SmartContractDeployer.deploy(
                TEXT_RESOURCE_CONTRACT,
                SmartContractDeployer.PARIS,
                new Address(owner),
                new Bytes32(resourceType),
                new Utf8String(MEDIA_TYPE),
                new DynamicBytes(new byte[0]),
                new Bytes32(new byte[32])
        );

        System.out.println("TextResource deployed at " + contractAddress);
        System.out.println("-".repeat(79));

        int chunkCount = 0;

        for (int offset = 0; offset < content.length; offset += DEMO_CHUNK_SIZE) {
            int chunkLength = Math.min(DEMO_CHUNK_SIZE, content.length - offset);
            byte[] chunk = Arrays.copyOfRange(content, offset, offset + chunkLength);

            Function appendChunk = new Function(
                    "appendChunk",
                    List.of(new DynamicBytes(chunk)),
                    List.of()
            );

            System.out.println("Appending chunk " + chunkCount + " with " + chunk.length + " bytes.");
            SmartContractDeployer.transact(contractAddress, appendChunk);

            chunkCount++;
        }

        System.out.println("Appended chunks: " + chunkCount);
        System.out.println("-".repeat(79));

        Function finalize = new Function(
                "finalize",
                List.of(new Bytes32(expectedContentHash)),
                List.of()
        );

        System.out.println("Finalizing resource.");
        SmartContractDeployer.transact(contractAddress, finalize);

        System.out.println("-".repeat(79));

        boolean finalized = callBool(contractAddress, "isFinalized");
        String onChainContentHash = callBytes32(contractAddress, "contentHash");
        String text = callString(contractAddress, "text");

        System.out.println("Read-back via ITextResource:");
        System.out.println("isFinalized():         " + finalized);
        System.out.println("contentHash():         " + onChainContentHash);
        System.out.println("hash matches:          " + onChainContentHash.equalsIgnoreCase(Numeric.toHexString(expectedContentHash)));
        System.out.println("text length:           " + text.getBytes(StandardCharsets.UTF_8).length + " bytes");
        System.out.println();

        assertTextEqualsResource(content, text);
        printTextPreview(text, 200);

        System.out.println();
        System.out.println("web3 resource URI:");
        System.out.println("web3://" + contractAddress + ":1337/text");
    }

    private static byte[] loadResourceBytes(String resourceName) throws Exception {
        try (InputStream inputStream = DemoTextResourceStaged.class
                .getClassLoader()
                .getResourceAsStream(resourceName)) {

            if (inputStream == null) {
                throw new IllegalArgumentException(
                        "Could not find resource on classpath: " + resourceName
                );
            }

            return inputStream.readAllBytes();
        }
    }

    private static byte[] bytes32FromKeccak256String(String value) {
        return Numeric.hexStringToByteArray(Hash.sha3String(value));
    }

    private static boolean callBool(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(
                contractAddress,
                new Function(
                        functionName,
                        List.of(),
                        List.of(new TypeReference<org.web3j.abi.datatypes.Bool>() {})
                )
        );

        return ((org.web3j.abi.datatypes.Bool) decoded.get(0)).getValue();
    }

    private static String callBytes32(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(
                contractAddress,
                new Function(
                        functionName,
                        List.of(),
                        List.of(new TypeReference<Bytes32>() {})
                )
        );

        return Numeric.toHexString(((Bytes32) decoded.get(0)).getValue());
    }

    private static String callString(String contractAddress, String functionName) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(
                contractAddress,
                new Function(
                        functionName,
                        List.of(),
                        List.of(new TypeReference<Utf8String>() {})
                )
        );

        return ((Utf8String) decoded.get(0)).getValue();
    }

    private static void assertTextEqualsResource(
            byte[] expectedContent,
            String actualText
    ) {
        byte[] actualContent = actualText.getBytes(StandardCharsets.UTF_8);

        if (!Arrays.equals(expectedContent, actualContent)) {
            throw new AssertionError(
                    "text() does not match the original resource file. "
                            + "Expected "
                            + expectedContent.length
                            + " bytes, got "
                            + actualContent.length
                            + " bytes."
            );
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
        System.out.println("...");
        System.out.println();
        System.out.println(end);
    }
}