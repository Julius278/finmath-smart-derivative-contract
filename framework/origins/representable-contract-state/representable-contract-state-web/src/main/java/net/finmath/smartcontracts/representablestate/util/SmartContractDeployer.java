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
 * Deployer - deploys a smart contract. Useful for demos and testing.
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
	static final Path FORGE_OUT_DIR = Paths.get("target/forge");
	static final Path FORGE_CACHE_DIR = Paths.get("target/forge-cache");

	private static final String FORGE_SOLC_VERSION = "0.8.24";
	private static final long FORGE_TIMEOUT_SECONDS = 300;

	// ==== Compiler presets ====
	public static final CompilerConfig PARIS = new CompilerConfig("paris", true, true);
	public static final CompilerConfig CANCUN = new CompilerConfig("cancun", true, true);

	/**
	 * Solidity compiler settings.
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

	private enum CompilerBackend {
		SOLC("solc"),
		FORGE("forge");

		private final String command;

		CompilerBackend(String command) {
			this.command = command;
		}
	}

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
	 * Deploy with default compiler settings, using Forge to compile the
	 * Solidity contract.
	 *
	 * <p>Forge manages the pinned Solidity compiler internally, so callers do
	 * not need a standalone {@code solc} executable on {@code PATH}.</p>
	 */
	public static String deployWithForge(Path contract, Type... constructorArgs) throws IOException, InterruptedException, TransactionException {
		return deploy(contract, PARIS, Arrays.asList(constructorArgs), CompilerBackend.FORGE);
	}

	/**
	 * Deploy with explicit EVM/compiler settings, using Forge to compile the
	 * Solidity contract.
	 */
	public static String deployWithForge(Path contract, CompilerConfig compilerConfig, Type... constructorArgs) throws IOException, InterruptedException, TransactionException {
		return deploy(contract, compilerConfig, Arrays.asList(constructorArgs), CompilerBackend.FORGE);
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
		return deploy(contract, compilerConfig, constructorArgs, CompilerBackend.SOLC);
	}

	private static String deploy(
			Path contract,
			CompilerConfig compilerConfig,
			List<Type> constructorArgs,
			CompilerBackend compilerBackend
	) throws IOException, InterruptedException, TransactionException {

		contract = resolveSolidityPath(contract.toString());

		String contractFile = contract.getFileName().toString();
		String contractName = contractFile.substring(0, contractFile.length() - ".sol".length());

		System.out.println("Compiling contract " + contractName);
		System.out.println("Compiler backend: " + compilerBackend.command);
		System.out.println("EVM version: " + compilerConfig.evmVersion());
		System.out.println("via-ir: " + compilerConfig.viaIr());
		System.out.println("optimize: " + compilerConfig.optimize());

		// 1) Compile the Solidity contract.
		Files.createDirectories(SOL_OUT_DIR);
		switch (compilerBackend) {
			case SOLC -> compileWithSolc(contract, compilerConfig);
			case FORGE -> compileWithForge(contract, compilerConfig);
		}

		// 2) Connect Web3j
		Web3j web3;
		long chainId;

		try {
			web3 = Web3j.build(new HttpService(RPC_URL));

			Admin admin = Admin.build(new HttpService(RPC_URL));

			String clientVer = web3.web3ClientVersion().send().getWeb3ClientVersion();
			chainId = admin.ethChainId().send().getChainId().longValue();

			System.out.println("Connected to: " + clientVer + " chainId=" + chainId);
		} catch (ConnectException e) {
			logger.error("Unable to connect to chain. Ensure that you have set the correct RPC_URL and in case of a local chain, that it runs.");
			throw new RuntimeException("Unable to connect to chain.", e);
		}

		Credentials creds = Credentials.create(PRIVATE_KEY);
		RawTransactionManager txMgr = new RawTransactionManager(web3, creds, chainId);
		TransactionReceiptProcessor receiptProcessor = new PollingTransactionReceiptProcessor(web3, 2_000, 120);

		String deploymentAccountAddress = creds.getAddress();

		System.out.println("Deployment account address: " + deploymentAccountAddress);
		System.out.println("Constructor args: " + constructorArgs.size());

		// 3) Deploy contract with constructor(...)
		String contractBinRaw = Files.readString(SOL_OUT_DIR.resolve(contractName + ".bin")).trim();

		String strippedBin = strip0x(contractBinRaw);

		if (strippedBin.isBlank()) {
			throw new IllegalStateException("No deployable bytecode found in " + SOL_OUT_DIR.resolve(contractName + ".bin") + ". Is " + contractName + " abstract, an interface, or not the deployable contract?");
		}

		System.out.println("Bytecode length: " + strippedBin.length() / 2 + " bytes");

		// ABI-encode constructor args and append to bytecode
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

		// 4) Ensure code present
		EthGetCode code = web3.ethGetCode(contractAddress, DefaultBlockParameterName.LATEST).send();

		if ("0x".equalsIgnoreCase(code.getCode())) {
			throw new IllegalStateException("No code at deployed contract address. Check deployment status, compiler EVM version and Besu config.");
		}

		// 5) Persist addresses to JSON
		writeDeploymentJson(chainId, contractName, contractAddress, txHashContractDeployment, deploymentAccountAddress, compilerConfig, compilerBackend);

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

		String solFileArg = solcPath(solFile);

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

	private static void compileWithForge(Path solFile, CompilerConfig compilerConfig) throws IOException, InterruptedException {

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

		if (!solFile.startsWith(projectRoot)) {
			throw new IllegalArgumentException("Solidity file must be inside the Forge project root " + projectRoot + ": " + solFile);
		}

		String contractFile = solFile.getFileName().toString();
		String contractName = contractFile.substring(0, contractFile.length() - ".sol".length());
		String sourceFile = projectRoot
				.relativize(solFile)
				.toString()
				.replace("\\", "/");

		Path forgeOut = FORGE_OUT_DIR.toAbsolutePath().normalize();
		Path forgeCache = FORGE_CACHE_DIR.toAbsolutePath().normalize();

		var command = new java.util.ArrayList<String>();

		command.add("forge");
		command.add("build");
		command.add("--root");
		command.add(solcPath(projectRoot));
		command.add("--contracts");
		command.add(".");
		command.add("--lib-paths");
		command.add("node_modules");
		command.add("--out");
		command.add(solcPath(forgeOut));
		command.add("--cache-path");
		command.add(solcPath(forgeCache));
		command.add("--use");
		command.add(FORGE_SOLC_VERSION);

		if (compilerConfig.viaIr()) {
			command.add("--via-ir");
		}

		command.add("--optimize");
		command.add(Boolean.toString(compilerConfig.optimize()));

		if (compilerConfig.optimize()) {
			command.add("--optimizer-runs");
			command.add("200");
		}

		command.add("--evm-version");
		command.add(compilerConfig.evmVersion());
		command.add("--remappings");
		command.add("@openzeppelin/=node_modules/@openzeppelin/");
		command.add("--remappings");
		command.add("solady/=node_modules/solady/src/");
		command.add("--color");
		command.add("never");
		command.add(sourceFile);

		System.out.println("forge command:");
		System.out.println(String.join(" ", command));

		ProcessBuilder pb = new ProcessBuilder(command);
		pb.directory(projectRoot.toFile());
		pb.environment().put(
				"FOUNDRY_VIA_IR",
				Boolean.toString(compilerConfig.viaIr())
		);
		pb.environment().put(
				"FOUNDRY_OPTIMIZER",
				Boolean.toString(compilerConfig.optimize())
		);
		pb.environment().put(
				"FOUNDRY_LINT__LINT_ON_BUILD",
				"false"
		);
		pb.inheritIO();

		Process p;

		try {
			p = pb.start();
		} catch (IOException exception) {
			throw new IOException(
					"Unable to start Forge. Install Foundry and ensure that forge is available on PATH.",
					exception
			);
		}

		if (!p.waitFor(FORGE_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)) {
			p.destroyForcibly();
			throw new RuntimeException("forge timed out");
		}

		if (p.exitValue() != 0) {
			throw new RuntimeException("forge failed for " + solFile + " (see logs above)");
		}

		Path artifact = forgeOut
				.resolve(contractFile)
				.resolve(contractName + ".json");

		if (!Files.isRegularFile(artifact)) {
			throw new IllegalStateException("Forge did not produce the expected artifact " + artifact);
		}

		String bytecode = new ObjectMapper()
				.readTree(artifact.toFile())
				.path("bytecode")
				.path("object")
				.asText()
				.trim();

		if (!bytecode.matches("0x[0-9a-fA-F]+")) {
			throw new IllegalStateException("Forge artifact contains no deployable bytecode: " + artifact);
		}

		Files.writeString(
				SOL_OUT_DIR.resolve(contractName + ".bin"),
				bytecode
		);
	}

	private static void writeDeploymentJson(
			long chainId,
			String contractName,
			String contractAddress,
			String txHash,
			String deploymentAccountAddress,
			CompilerConfig compilerConfig,
			CompilerBackend compilerBackend
	) throws IOException {

		Path deployJson = Paths.get("deployments", "besu-" + chainId + ".json");

		Files.createDirectories(deployJson.getParent());

		ObjectMapper om = new ObjectMapper();
		ObjectNode root = om.createObjectNode();

		root.put("chainId", chainId);
		root.put("contractName", contractName);
		root.put("contractAddress", contractAddress);
		root.put("contractTx", txHash);
		root.put("deploymentAccount", deploymentAccountAddress);
		root.put("compilerBackend", compilerBackend.command);
		if (compilerBackend == CompilerBackend.FORGE) {
			root.put("solcVersion", FORGE_SOLC_VERSION);
		}
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

			Path workingDirectory = Paths.get("").toAbsolutePath().normalize();
			List<Path> sourceRoots = List.of(
					workingDirectory.resolve(SOL_SRC_DIR),
					workingDirectory.resolve("representable-contract-state-web").resolve(SOL_SRC_DIR)
			);

			for (Path sourceRoot : sourceRoots) {
				Path candidate = sourceRoot.resolve(provided).normalize();

				if (Files.exists(candidate)) {
					return candidate;
				}
			}

			URL location = SmartContractDeployer.class
					.getProtectionDomain()
					.getCodeSource()
					.getLocation();

			Path moduleRoot = Paths.get(location.toURI());
			Path moduleRootName = moduleRoot.getFileName();

			if (moduleRootName != null && "classes".equals(moduleRootName.toString())) {
				moduleRoot = moduleRoot.getParent();
				moduleRootName = moduleRoot != null ? moduleRoot.getFileName() : null;
			}

			if (moduleRootName != null && "target".equals(moduleRootName.toString())) {
				moduleRoot = moduleRoot.getParent();
			}

			if (moduleRoot == null) {
				throw new IllegalArgumentException("Cannot derive a Solidity source directory from " + location);
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

		throw new IllegalStateException(
				"Could not find Solidity dependencies in a node_modules directory at "
						+ start.toAbsolutePath()
						+ " or any parent directory."
		);
	}

	private static String solcPath(Path path) {
		return path.toAbsolutePath().normalize().toString().replace("\\", "/");
	}
}
