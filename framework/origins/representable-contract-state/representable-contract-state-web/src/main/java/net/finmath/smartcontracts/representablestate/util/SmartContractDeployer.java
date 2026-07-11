package net.finmath.smartcontracts.representablestate.util;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.FunctionReturnDecoder;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.Type;
import org.web3j.crypto.Credentials;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.admin.Admin;
import org.web3j.protocol.core.DefaultBlockParameterName;
import org.web3j.protocol.core.methods.request.Transaction;
import org.web3j.protocol.core.methods.response.EthGetCode;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.protocol.exceptions.TransactionException;
import org.web3j.protocol.http.HttpService;
import org.web3j.tx.RawTransactionManager;
import org.web3j.tx.response.PollingTransactionReceiptProcessor;
import org.web3j.tx.response.TransactionReceiptProcessor;

import java.io.IOException;
import java.math.BigInteger;
import java.net.ConnectException;
import java.net.URISyntaxException;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

/**
 * Deployer - deploys a smart contract.
 *
 * Useful for demos and testing.
 *
 * @author Christian Fries
 * @author Raphael Prandtl
 */
public class SmartContractDeployer {

	private static final Logger logger = LoggerFactory.getLogger(SmartContractDeployer.class);

	// ==== Chain configuration ====
	static final String RPC_URL = "http://127.0.0.1:8545";
	static final BigInteger GAS_PRICE = BigInteger.valueOf(1_000_000_000L);
	static final BigInteger GAS_LIMIT = BigInteger.valueOf(20_000_000L);

	// **** DEV KEY ONLY — make sure this is funded on your dev chain ****
	static final String PRIVATE_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";

	// Solidity sources and output locations
	static final Path SOL_SRC_DIR = Paths.get("src/main/solidity");
	static final Path SOL_OUT_DIR = Paths.get("target/solc");

	// ==== Compiler presets ====
	public static final CompilerConfig PARIS = new CompilerConfig("paris", true, true);
	public static final CompilerConfig CANCUN = new CompilerConfig("cancun", true, true);

	/**
	 * Compiler settings for solc.
	 *
	 * @param evmVersion EVM target, e.g. paris, shanghai, cancun.
	 * @param viaIr      Whether to compile via IR.
	 * @param optimize   Whether to enable optimizer.
	 */
	public record CompilerConfig(
			String evmVersion,
			boolean viaIr,
			boolean optimize
	) {}

	/**
	 * Deploy with default compiler settings.
	 *
	 * Default is PARIS because most existing demos do not need Cancun opcodes.
	 */
	public static String deploy(Path contract) throws IOException, InterruptedException, TransactionException {
		return deploy(contract, PARIS, List.of());
	}

	/**
	 * Deploy with default compiler settings and constructor arguments.
	 */
	public static String deploy(Path contract, Type... constructorArgs) throws IOException, InterruptedException, TransactionException {
		return deploy(contract, PARIS, Arrays.asList(constructorArgs));
	}

	/**
	 * Deploy with explicit EVM/compiler settings and constructor arguments.
	 */
	public static String deploy(Path contract, CompilerConfig compilerConfig, Type... constructorArgs) throws IOException, InterruptedException, TransactionException {
		return deploy(contract, compilerConfig, Arrays.asList(constructorArgs));
	}

	/**
	 * Convenience method for contracts requiring Cancun opcodes, e.g. MCOPY.
	 */
	public static String deployCancun(Path contract, Type... constructorArgs) throws IOException, InterruptedException, TransactionException {
		return deploy(contract, CANCUN, Arrays.asList(constructorArgs));
	}

	/**
	 * Generic deploy method.
	 */
	public static String deploy(Path contract, CompilerConfig compilerConfig, List<Type> constructorArgs) throws IOException, InterruptedException, TransactionException {

		contract = resolveSolidityPath(contract.toString());

		String contractFile = contract.getFileName().toString();
		String contractName = contractFile.substring(0, contractFile.length() - ".sol".length());

		System.out.println("Compiling contract " + contractName);
		System.out.println("EVM version: " + compilerConfig.evmVersion());
		System.out.println("via-ir: " + compilerConfig.viaIr());
		System.out.println("optimize: " + compilerConfig.optimize());

		Files.createDirectories(SOL_OUT_DIR);
		compileWithSolc(contract, compilerConfig);

		Web3j web3;
		long chainId;

		try {
			web3 = Web3j.build(new HttpService(RPC_URL));

			Admin admin = Admin.build(new HttpService(RPC_URL));

			String clientVer = web3.web3ClientVersion().send().getWeb3ClientVersion();
			chainId = admin.ethChainId().send().getChainId().longValue();

			System.out.println("Connected to: " + clientVer + " chainId=" + chainId);
		} catch (ConnectException e) {
			logger.error("Unable to connect to chain.");
			throw new RuntimeException("Unable to connect to chain.", e);
		}

		Credentials creds = Credentials.create(PRIVATE_KEY);
		RawTransactionManager txMgr = new RawTransactionManager(web3, creds, chainId);
		TransactionReceiptProcessor receiptProcessor = new PollingTransactionReceiptProcessor(web3, 2_000, 120);

		String deployerAddress = creds.getAddress();

		System.out.println("Deployer address: " + deployerAddress);
		System.out.println("Constructor args: " + constructorArgs.size());

		String contractBinRaw = Files.readString(SOL_OUT_DIR.resolve(contractName + ".bin")).trim();

		String strippedBin = strip0x(contractBinRaw);

		if (strippedBin.isBlank()) {
			throw new IllegalStateException("No deployable bytecode found in " + SOL_OUT_DIR.resolve(contractName + ".bin") + ". Is " + contractName + " abstract, an interface, or not the deployable contract?");
		}

		System.out.println("Bytecode length: " + strippedBin.length() / 2 + " bytes");

		String encodedConstructorArgs = constructorArgs.isEmpty() ? "" : FunctionEncoder.encodeConstructor(constructorArgs);

		String createData = hexConcat(contractBinRaw, encodedConstructorArgs);

		String txHashContractDeployment = txMgr.sendTransaction(GAS_PRICE, GAS_LIMIT, null, createData, BigInteger.ZERO).getTransactionHash();

		var receipt = receiptProcessor.waitForTransactionReceipt(txHashContractDeployment);

		System.out.println("Deployment tx status: " + receipt.getStatus());
		System.out.println("Gas used: " + receipt.getGasUsed());

		if (!receipt.isStatusOK()) {
			throw new IllegalStateException("Deployment transaction failed. Tx hash: " + txHashContractDeployment + ", status: " + receipt.getStatus() + ", gasUsed: " + receipt.getGasUsed());
		}

		String contractAddress = receipt.getContractAddress();

		if (contractAddress == null || contractAddress.isBlank()) {
			throw new IllegalStateException("No contract address in deployment receipt. Tx hash: " + txHashContractDeployment);
		}

		System.out.println("Contract deployed @ " + contractAddress);

		logger.info("Contract {} deployed at {}", contractName, contractAddress);

		EthGetCode code = web3.ethGetCode(contractAddress, DefaultBlockParameterName.LATEST).send();

		if ("0x".equalsIgnoreCase(code.getCode())) {
			throw new IllegalStateException("No code at deployed contract address. Check deployment status, solc EVM version and Besu config.");
		}

		writeDeploymentJson(chainId, contractName, contractAddress, txHashContractDeployment, deployerAddress, compilerConfig);

		printLocalApplicationProperties(chainId, contractName, contractAddress);

		return contractAddress;
	}

	public static TransactionReceipt transact(String contractAddress, Function function) throws IOException, TransactionException {

		Web3j web3 = Web3j.build(new HttpService(RPC_URL));
		Admin admin = Admin.build(new HttpService(RPC_URL));

		long chainId = admin.ethChainId().send().getChainId().longValue();

		Credentials creds = Credentials.create(PRIVATE_KEY);
		RawTransactionManager txMgr = new RawTransactionManager(web3, creds, chainId);
		TransactionReceiptProcessor receiptProcessor = new PollingTransactionReceiptProcessor(web3, 2_000, 120);

		String encodedFunction = FunctionEncoder.encode(function);

		String txHash = txMgr.sendTransaction(GAS_PRICE, GAS_LIMIT, contractAddress, encodedFunction, BigInteger.ZERO).getTransactionHash();

		TransactionReceipt receipt = receiptProcessor.waitForTransactionReceipt(txHash);

		System.out.println("Tx " + function.getName() + " status: " + receipt.getStatus());
		System.out.println("Tx " + function.getName() + " gas used: " + receipt.getGasUsed());

		if (!receipt.isStatusOK()) {
			throw new IllegalStateException("Transaction failed. Function: " + function.getName() + ", txHash: " + txHash + ", status: " + receipt.getStatus() + ", gasUsed: " + receipt.getGasUsed());
		}

		return receipt;
	}

	public static List<Type> call(String contractAddress, Function function) throws IOException {

		Web3j web3 = Web3j.build(new HttpService(RPC_URL));

		String encodedFunction = FunctionEncoder.encode(function);

		var response = web3.ethCall(Transaction.createEthCallTransaction(defaultSenderAddress(), contractAddress, encodedFunction), DefaultBlockParameterName.LATEST).send();

		if (response.hasError()) {
			throw new RuntimeException("eth_call failed: " + response.getError().getMessage());
		}

		return FunctionReturnDecoder.decode(response.getValue(), function.getOutputParameters());
	}

	public static String defaultSenderAddress() {
		return Credentials.create(PRIVATE_KEY).getAddress();
	}


	private static void compileWithSolc(Path solFile, CompilerConfig compilerConfig) throws IOException, InterruptedException {

		Path nodeModules = findNodeModules(solFile);
		Path projectRoot = nodeModules.getParent();

		Path openZeppelinContracts = nodeModules
				.resolve("@openzeppelin")
				.resolve("contracts");

		Path soladySrc = nodeModules
				.resolve("solady")
				.resolve("src");

		if (!Files.isDirectory(openZeppelinContracts)) {
			throw new IllegalStateException("Missing OpenZeppelin contracts dependency at " + openZeppelinContracts);
		}

		if (!Files.isDirectory(soladySrc)) {
			throw new IllegalStateException("Missing Solady src dependency at " + soladySrc);
		}

		String solFileArg = projectRoot
				.relativize(solFile.toAbsolutePath().normalize())
				.toString()
				.replace("\\", "/");

		var command = new java.util.ArrayList<String>();

		command.add("solc");

		if (compilerConfig.viaIr()) {
			command.add("--via-ir");
		}

		if (compilerConfig.optimize()) {
			command.add("--optimize");
		}

		command.add("--evm-version");
		command.add(compilerConfig.evmVersion());

		command.add("--base-path");
		command.add(solcPath(projectRoot));

		command.add("--include-path");
		command.add(solcPath(nodeModules));

		command.add("--allow-paths");
		command.add(solcPath(projectRoot) + "," + solcPath(nodeModules));

		/*
		 * Important:
		 * Use relative remappings from --base-path.
		 *
		 * @openzeppelin/contracts/... -> node_modules/@openzeppelin/contracts/...
		 * solady/utils/...            -> node_modules/solady/src/utils/...
		 */
		command.add("@openzeppelin/=node_modules/@openzeppelin/");
		command.add("solady/=node_modules/solady/src/");

		command.add("--abi");
		command.add("--bin");
		command.add("-o");
		command.add(SOL_OUT_DIR.toString());
		command.add("--overwrite");
		command.add(solFileArg);

		System.out.println("solc command:");
		System.out.println(String.join(" ", command));

		ProcessBuilder pb = new ProcessBuilder(command);
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

	private static void writeDeploymentJson(long chainId, String contractName, String contractAddress, String txHash, String deployerAddress, CompilerConfig compilerConfig) throws IOException {

		Path deployJson = Paths.get("deployments", "besu-" + chainId + ".json");

		Files.createDirectories(deployJson.getParent());

		ObjectMapper om = new ObjectMapper();
		ObjectNode root = om.createObjectNode();

		root.put("chainId", chainId);
		root.put("contractName", contractName);
		root.put("contractAddress", contractAddress);
		root.put("contractTx", txHash);
		root.put("deployer", deployerAddress);
		root.put("evmVersion", compilerConfig.evmVersion());
		root.put("viaIr", compilerConfig.viaIr());
		root.put("optimize", compilerConfig.optimize());

		om.writerWithDefaultPrettyPrinter().writeValue(deployJson.toFile(), root);

		System.out.println("Saved deployment to " + deployJson.toAbsolutePath());
	}

	private static void printLocalApplicationProperties(long chainId, String contractName, String contractAddress) {
		System.out.println("_".repeat(79));
		System.out.println("Set these properties in application.properties for local test:");
		System.out.println("ethereum.rpcUrl=" + RPC_URL);
		System.out.println("ethereum.chainId=" + chainId);
		System.out.println("ethereum.sender.privateKey=" + PRIVATE_KEY);
		System.out.println();

		System.out.println("# Last deployed contract");
		System.out.println("ethereum.contract." + contractName + "=" + contractAddress);
		System.out.println();

		System.out.println("ethereum.tx.enabled=true");
		System.out.println("ethereum.listener.enabled=true");
		System.out.println();
	}

	/* ---------- helpers ---------- */

	private static String strip0x(String hex) {
		return hex != null && hex.startsWith("0x") ? hex.substring(2) : hex;
	}

	private static String hexConcat(String bin, String encodedConstructor) {
		String b = strip0x(bin);
		String a = encodedConstructor == null ? "" : strip0x(encodedConstructor);

		return "0x" + b + a;
	}

	private static Path resolveSolidityPath(String pathLike) {
		try {
			Path provided = Paths.get(pathLike);

			if (provided.isAbsolute() && Files.exists(provided)) {
				return provided.normalize();
			}

			if (Files.exists(provided)) {
				return provided.toAbsolutePath().normalize();
			}

			URL location = SmartContractDeployer.class
					.getProtectionDomain()
					.getCodeSource()
					.getLocation();

            Path moduleRoot = Paths.get(location.toURI());

			if ("classes".equals(moduleRoot.getFileName().toString())) {
				moduleRoot = moduleRoot.getParent();
			}

			if ("target".equals(moduleRoot.getFileName().toString())) {
				moduleRoot = moduleRoot.getParent();
			}

			Path candidate = moduleRoot.resolve(SOL_SRC_DIR).resolve(pathLike).normalize();

			if (Files.exists(candidate)) {
				return candidate;
			}

			throw new IllegalArgumentException("Cannot find Solidity file " + candidate + " (derived from " + pathLike + ")");
		} catch (URISyntaxException e) {
			throw new RuntimeException("Failed to resolve Solidity path from class location", e);
		}
	}

	private static Path findNodeModules(Path start) {
		Path current = start.toAbsolutePath().normalize();

		if (Files.isRegularFile(current)) {
			current = current.getParent();
		}

		while (current != null) {
			Path candidate = current.resolve("node_modules");

			if (Files.isDirectory(candidate)) {
				return candidate.normalize();
			}

			current = current.getParent();
		}

		throw new IllegalStateException("Could not find node_modules in " + start.toAbsolutePath() + " or any parent directory. Did you run npm install?");
	}

	private static String solcPath(Path path) {
		return path.toAbsolutePath().normalize().toString().replace("\\", "/");
	}
}