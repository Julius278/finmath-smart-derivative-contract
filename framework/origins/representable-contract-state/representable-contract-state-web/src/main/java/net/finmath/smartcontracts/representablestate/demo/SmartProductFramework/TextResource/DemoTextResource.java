package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework.TextResource;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.FunctionReturnDecoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Bool;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.Utf8String;
import org.web3j.abi.datatypes.DynamicBytes;
import org.web3j.abi.datatypes.Type;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.crypto.Hash;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.admin.Admin;
import org.web3j.protocol.core.DefaultBlockParameterName;
import org.web3j.protocol.core.methods.request.Transaction;
import org.web3j.protocol.http.HttpService;
import org.web3j.utils.Numeric;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.List;

/**
 * Demo deploying a TextResource contract in one-shot mode.
 *
 * <p>The contract implements ITextResource. The demo publishes a small XML
 * resource through the constructor, verifies the expected content hash on-chain,
 * and reads back selected ITextResource views via eth_call.</p>
 *
 * @author Raphael Prandtl
 */
public class DemoTextResource {

    private static final Logger logger = LoggerFactory.getLogger(DemoTextResource.class);

    static final Path TEXT_RESOURCE_CONTRACT = Path.of("examples","SmartProductFramework", "TextResource", "TextResource.sol");

    private static final String RPC_URL = "http://127.0.0.1:8545";

    private static final String RESOURCE_TYPE_NAME = "PRODUCT_TERMS_XML";

    private static final String MEDIA_TYPE = "application/xml";

    private static final String SAMPLE_XML = """
			<?xml version="1.0" encoding="UTF-8"?>
			<ProductTerms>
			    <Name>Demo Product Terms</Name>
			    <Currency>EUR</Currency>
			    <Notional>1000000</Notional>
			</ProductTerms>
			""";

    public static void main(String[] args) throws Exception {

        System.out.println("This demo requires a locally running chain. If not already running, start one with:");
        System.out.println("DEPLOYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYER --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
        System.out.println("-".repeat(79));

        String owner = SmartContractDeployer.defaultSenderAddress();

        byte[] content = SAMPLE_XML.getBytes(StandardCharsets.UTF_8);
        byte[] resourceType = bytes32FromKeccak256String(RESOURCE_TYPE_NAME);
        byte[] expectedContentHash = Hash.sha3(content);

        System.out.println("Deploying TextResource in one-shot mode.");
        System.out.println("Owner:                 " + owner);
        System.out.println("Resource type name:    " + RESOURCE_TYPE_NAME);
        System.out.println("Resource type hash:    " + Numeric.toHexString(resourceType));
        System.out.println("Media type:            " + MEDIA_TYPE);
        System.out.println("Content length:        " + content.length + " bytes");
        System.out.println("Expected contentHash:  " + Numeric.toHexString(expectedContentHash));
        System.out.println("-".repeat(79));

        String contractAddress = SmartContractDeployer.deploy(
                TEXT_RESOURCE_CONTRACT,
                SmartContractDeployer.PARIS,
                new Address(owner),
                new Bytes32(resourceType),
                new Utf8String(MEDIA_TYPE),
                new DynamicBytes(content),
                new Bytes32(expectedContentHash)
        );

        System.out.println("TextResource deployed at " + contractAddress);
        System.out.println("-".repeat(79));

        try (Web3j web3 = Web3j.build(new HttpService(RPC_URL))) {
            Admin admin = Admin.build(new HttpService(RPC_URL));
            long chainId = admin.ethChainId().send().getChainId().longValue();

            boolean finalized = callBool(web3, contractAddress, "isFinalized");
            String onChainContentHash = callBytes32(web3, contractAddress, "contentHash");
            String text = callString(web3, contractAddress, "text");

            System.out.println("Read-back via ITextResource:");
            System.out.println("isFinalized():         " + finalized);
            System.out.println("contentHash():         " + onChainContentHash);
            System.out.println("hash matches:          " + onChainContentHash.equalsIgnoreCase(Numeric.toHexString(expectedContentHash)));
            System.out.println();
            System.out.println("text():");
            System.out.println(text);
            System.out.println();

            System.out.println("web3 resource URI:");
            System.out.println("web3://" + contractAddress + ":" + chainId + "/text");
            System.out.println();

            System.out.println("Note: TextResource itself is not an IXMLRepresentableState contract.");
            System.out.println("It is meant to be included by a ProductDefinition/Product via xi:include.");
        }
    }

    private static byte[] bytes32FromKeccak256String(String value) {
        return Numeric.hexStringToByteArray(Hash.sha3String(value));
    }

    private static boolean callBool(Web3j web3, String contractAddress, String functionName) throws Exception {
        List<Type> decoded = call(web3, contractAddress, new Function(
                functionName,
                List.of(),
                List.of(new TypeReference<Bool>() {})
        ));

        return ((Bool) decoded.get(0)).getValue();
    }

    private static String callBytes32(Web3j web3, String contractAddress, String functionName) throws Exception {
        List<Type> decoded = call(web3, contractAddress, new Function(
                functionName,
                List.of(),
                List.of(new TypeReference<Bytes32>() {})
        ));

        return Numeric.toHexString(((Bytes32) decoded.get(0)).getValue());
    }

    private static String callString(Web3j web3, String contractAddress, String functionName) throws Exception {
        List<Type> decoded = call(web3, contractAddress, new Function(
                functionName,
                List.of(),
                List.of(new TypeReference<Utf8String>() {})
        ));

        return ((Utf8String) decoded.get(0)).getValue();
    }

    private static List<Type> call(Web3j web3, String contractAddress, Function function) throws Exception {
        String encodedFunction = FunctionEncoder.encode(function);

        var response = web3.ethCall(
                Transaction.createEthCallTransaction(
                        SmartContractDeployer.defaultSenderAddress(),
                        contractAddress,
                        encodedFunction
                ),
                DefaultBlockParameterName.LATEST
        ).send();

        if (response.hasError()) {
            throw new RuntimeException("eth_call failed: " + response.getError().getMessage());
        }

        return FunctionReturnDecoder.decode(
                response.getValue(),
                function.getOutputParameters()
        );
    }
}