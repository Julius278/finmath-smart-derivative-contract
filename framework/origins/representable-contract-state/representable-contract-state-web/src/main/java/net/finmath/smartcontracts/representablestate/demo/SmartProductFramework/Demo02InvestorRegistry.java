package net.finmath.smartcontracts.representablestate.demo.SmartProductFramework;

import net.finmath.smartcontracts.representablestate.util.SmartContractDeployer;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Bool;
import org.web3j.abi.datatypes.DynamicStruct;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.Type;
import org.web3j.abi.datatypes.Utf8String;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.abi.datatypes.generated.Uint8;
import org.web3j.abi.datatypes.generated.Uint64;
import org.web3j.crypto.Hash;
import org.web3j.utils.Numeric;

import java.math.BigInteger;
import java.nio.file.Path;
import java.util.List;

public class Demo02InvestorRegistry {

    static final Path INVESTOR_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "InvestorRegistry", "InvestorRegistry.sol");

    /*
     * InvestorStatus enum in Solidity:
     *
     * enum InvestorStatus {
     *     Unknown,   // 0
     *     Active,    // 1
     *     Suspended, // 2
     *     Revoked    // 3
     * }
     */
    private static final BigInteger STATUS_UNKNOWN = BigInteger.ZERO;
    private static final BigInteger STATUS_ACTIVE = BigInteger.ONE;
    private static final BigInteger STATUS_SUSPENDED = BigInteger.valueOf(2);
    private static final BigInteger STATUS_REVOKED = BigInteger.valueOf(3);

    private static final String INVESTOR_ADDRESS = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";

    private static final String INVESTOR_LEI = "529900T8BM49AURSDO55";

    private static final String DEMO_PRODUCT_DEFINITION_NAME = "Simple Bond Product Definition";

    public static void main(String[] args) throws Exception {

        System.out.println("This demo requires a locally running chain. If not already running, start one with:");
        System.out.println("DEPLOYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYER --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
        System.out.println("-".repeat(79));

        String owner = SmartContractDeployer.defaultSenderAddress();
        byte[] productDefinitionId = Hash.sha3(DEMO_PRODUCT_DEFINITION_NAME.getBytes());

        System.out.println("Demo 02 - InvestorRegistry");
        System.out.println("Owner:                  " + owner);
        System.out.println("Investor:               " + INVESTOR_ADDRESS);
        System.out.println("Investor LEI:           " + INVESTOR_LEI);
        System.out.println("ProductDefinitionId:    " + Numeric.toHexString(productDefinitionId));
        System.out.println("-".repeat(79));

        System.out.println("Deploying InvestorRegistry.");
        String investorRegistry = SmartContractDeployer.deploy(
                INVESTOR_REGISTRY_CONTRACT,
                SmartContractDeployer.PARIS,
                new Address(owner)
        );

        System.out.println("InvestorRegistry deployed at " + investorRegistry);
        System.out.println("-".repeat(79));

        System.out.println("Registering investor.");

        SmartContractDeployer.transact(investorRegistry, new Function("registerInvestor", List.of(new InvestorRegistrationParams(new Address(INVESTOR_ADDRESS), new Utf8String(INVESTOR_LEI))), List.of()));

        System.out.println("Investor registered.");
        System.out.println("-".repeat(79));

        printInvestorState(investorRegistry, INVESTOR_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Suspending investor.");
        setInvestorStatus(investorRegistry, INVESTOR_ADDRESS, STATUS_SUSPENDED);
        printInvestorState(investorRegistry, INVESTOR_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Re-activating investor.");
        setInvestorStatus(investorRegistry, INVESTOR_ADDRESS, STATUS_ACTIVE);
        printInvestorState(investorRegistry, INVESTOR_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Revoking investor.");
        setInvestorStatus(investorRegistry, INVESTOR_ADDRESS, STATUS_REVOKED);
        printInvestorState(investorRegistry, INVESTOR_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Trying to re-activate revoked investor. This should fail.");

        try {
            setInvestorStatus(investorRegistry, INVESTOR_ADDRESS, STATUS_ACTIVE);
            throw new AssertionError("Expected revoked investor re-activation to fail.");
        }
        catch (Exception expected) {
            System.out.println("Expected failure received.");
            System.out.println("Reason: " + expected.getMessage());
        }

        System.out.println();
        System.out.println("=".repeat(79));
        System.out.println("Demo 02 completed.");
        System.out.println("InvestorRegistry: " + investorRegistry);
    }

    private static void setInvestorStatus(String investorRegistry, String investor, BigInteger status) throws Exception {

        SmartContractDeployer.transact(investorRegistry, new Function("setInvestorStatus", List.of(new Address(investor), new Uint8(status)), List.of()));
    }

    private static void printInvestorState(String investorRegistry, String investor, byte[] productDefinitionId) throws Exception {

        InvestorView investorView = getInvestor(investorRegistry, investor);

        boolean registered = callBool(investorRegistry, new Function("isRegisteredInvestor", List.of(new Address(investor)), List.of(new TypeReference<Bool>() {})));

        boolean eligible = callBool(investorRegistry, new Function("isEligibleInvestor", List.of(new Address(investor), new Bytes32(productDefinitionId)), List.of(new TypeReference<Bool>() {})));

        System.out.println("Investor state:");
        System.out.println("  registered:           " + registered);
        System.out.println("  status:               " + statusName(investorView.status.getValue()));
        System.out.println("  eligible:             " + eligible);
        System.out.println("  lei:                  " + investorView.lei.getValue());
        System.out.println("  registeredAt:         " + investorView.registeredAt.getValue());
        System.out.println("  updatedAt:            " + investorView.updatedAt.getValue());
    }

    private static InvestorView getInvestor(String investorRegistry, String investor) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(investorRegistry, new Function("getInvestor", List.of(new Address(investor)), List.of(new TypeReference<InvestorView>() {})));
        return (InvestorView) decoded.get(0);
    }

    private static boolean callBool(String contractAddress, Function function) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(contractAddress, function);
        return ((Bool) decoded.get(0)).getValue();
    }

    private static String statusName(BigInteger status) {
        if (STATUS_UNKNOWN.equals(status)) {
            return "Unknown";
        }
        if (STATUS_ACTIVE.equals(status)) {
            return "Active";
        }
        if (STATUS_SUSPENDED.equals(status)) {
            return "Suspended";
        }
        if (STATUS_REVOKED.equals(status)) {
            return "Revoked";
        }
        return "Unknown enum value: " + status;
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

    public static class InvestorView extends DynamicStruct {

        public final Uint8 status;
        public final Utf8String lei;
        public final Uint64 registeredAt;
        public final Uint64 updatedAt;

        public InvestorView(Uint8 status, Utf8String lei, Uint64 registeredAt, Uint64 updatedAt) {
            super(status, lei, registeredAt, updatedAt);
            this.status = status;
            this.lei = lei;
            this.registeredAt = registeredAt;
            this.updatedAt = updatedAt;
        }
    }
}