package net.finmath.smartcontracts.representablestate.util;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Bool;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.crypto.Credentials;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.admin.Admin;
import org.web3j.protocol.core.DefaultBlockParameterName;
import org.web3j.protocol.core.methods.response.EthGetCode;
import org.web3j.protocol.exceptions.TransactionException;
import org.web3j.protocol.http.HttpService;
import org.web3j.tx.RawTransactionManager;
import org.web3j.tx.response.PollingTransactionReceiptProcessor;
import org.web3j.tx.response.TransactionReceiptProcessor;

import java.io.IOException;
import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;

/**
 * <p>Deployer</p>
 *
 * @author Christian Fries
 */
public class SmartContractDeployer {

	private static final Logger logger = LoggerFactory.getLogger(SmartContractDeployer.class);

	// ==== Configuration ====
	static final String RPC_URL   = "http://127.0.0.1:8545";                 // Besu dev
	static final BigInteger GAS_PRICE = BigInteger.valueOf(1_000_000_000L);  // dev
	static final BigInteger GAS_LIMIT = BigInteger.valueOf(6_000_000L);

	// **** DEV KEY ONLY — make sure this is funded on your dev chain ****
	static final String PRIVATE_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

	// Solidity sources and output locations
	static final Path SOL_SRC_DIR = Paths.get("src/main/solidity");
	static final Path SOL_OUT_DIR = Paths.get("target/solc"); // will be created

	/**
	 * Deploy a contract
	 *
	 * @param contractSolFile Name of the solidity file.
	 * @return
	 */
	public static String deploy(String contractSolFile) throws IOException, TransactionException, InterruptedException {
		System.out.println("Compiling contract" + contractSolFile);
		// 1) Compile with solc if needed
		Files.createDirectories(SOL_OUT_DIR);
		compileWithSolc(contractSolFile);

		// 2) Connect Web3j
		Web3j web3  = Web3j.build(new HttpService(RPC_URL));
		Admin admin = Admin.build(new HttpService(RPC_URL));
		String clientVer = web3.web3ClientVersion().send().getWeb3ClientVersion();
		long chainId = admin.ethChainId().send().getChainId().longValue();
		System.out.println("Connected to: " + clientVer + " chainId=" + chainId);

		Credentials creds = Credentials.create(PRIVATE_KEY);
		RawTransactionManager txMgr = new RawTransactionManager(web3, creds, chainId);
		TransactionReceiptProcessor rp = new PollingTransactionReceiptProcessor(web3, 2_000, 120);

		// Operator address (oracle) and treasury (here: same as operator for dev)
		String ownerAddress = creds.getAddress();

		System.out.println("Oracle operator (constructor arg): " + ownerAddress);

		// 3) Deploy DecryptionOracle WITH constructor(address _oracle, address _treasury)
		String oracleBinRaw = Files.readString(SOL_OUT_DIR.resolve("XmlRepresentableInstrument.bin")).trim();

		// ABI-encode constructor args and append to bytecode
		String ctorArgs = FunctionEncoder.encodeConstructor(
				Arrays.asList(new Address(ownerAddress), new Uint256(100), new Bool(true))
		);
		String oracleCreateData = hexConcat(oracleBinRaw, ctorArgs); // "0x..."

		String txHashContractDeployment = txMgr
				.sendTransaction(GAS_PRICE, GAS_LIMIT, null, oracleCreateData, BigInteger.ZERO)
				.getTransactionHash();
		var oracleRcpt = rp.waitForTransactionReceipt(txHashContractDeployment);
		String contractAddress = oracleRcpt.getContractAddress();
		System.out.println("Contract deployed @ " + contractAddress);

		logger.info("Contract deployed at {}", contractAddress);

		// Ensure code present
		EthGetCode code = web3.ethGetCode(contractAddress, DefaultBlockParameterName.LATEST).send();
		if ("0x".equalsIgnoreCase(code.getCode())) {
			throw new IllegalStateException(
					"No code at oracle address (check solc --evm-version=paris and Besu config).");
		}

		// 5) Persist addresses to JSON
		Path deployJson = Paths.get("deployments", "besu-" + chainId + ".json");
		Files.createDirectories(deployJson.getParent());

		ObjectMapper om = new ObjectMapper();
		ObjectNode root = om.createObjectNode();
		root.put("chainId", chainId);
		root.put("ethereum.xmlrenderer.contract", contractAddress);
		root.put("contactTx", txHashContractDeployment);
		root.put("owner", ownerAddress);

		om.writerWithDefaultPrettyPrinter().writeValue(deployJson.toFile(), root);

		System.out.println("Saved deployment to " + deployJson.toAbsolutePath());
		System.out.println("_".repeat(79));
		System.out.println("\nSet these properties in application.properties for local test - then (re-)start the event listener:\n");
		System.out.println("ethereum.rpcUrl=" + RPC_URL);
		System.out.println("ethereum.chainId=" + chainId);
		System.out.println("ethereum.sender.privateKey=" + PRIVATE_KEY);
		System.out.println();
		System.out.println("ethereum.tx.enabled=true");
		System.out.println("ethereum.xmlrenderer.contract=" + contractAddress);
		System.out.println("ethereum.keydecryptionoracle.fromBlock=1");
		System.out.println();
		System.out.println("ethereum.listener.enabled=true");
		System.out.println();

		return contractAddress;
	}

	private static void compileWithSolc(String solFile) throws IOException, InterruptedException {
		ProcessBuilder pb = new ProcessBuilder(
				"solc", "--optimize", "--evm-version", "paris",
				"--abi", "--bin", "-o", SOL_OUT_DIR.toString(), "--overwrite",
				SOL_SRC_DIR.resolve(solFile).toString()
		);
		pb.inheritIO();
		Process p = pb.start();
		if (!p.waitFor(60, java.util.concurrent.TimeUnit.SECONDS)) {
			p.destroyForcibly();
			throw new RuntimeException("solc timed out");
		}
		if (p.exitValue() != 0) {
			throw new RuntimeException("solc failed for " + solFile + " (see logs above)");
		}
	}

	/* ---------- helpers ---------- */
	private static String ensure0x(String hex) { return hex.startsWith("0x") ? hex : "0x" + hex; }
	private static String strip0x(String hex)  { return hex.startsWith("0x") ? hex.substring(2) : hex; }

	/** Concatenate bin and encodedConstructor into a single 0x-prefixed data string. */
	private static String hexConcat(String bin, String encodedConstructor) {
		String b = strip0x(bin);
		String a = encodedConstructor == null ? "" : strip0x(encodedConstructor);
		return "0x" + b + a;
	}
}
