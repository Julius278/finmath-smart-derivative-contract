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

public class DemoClientRegistry {

    static final Path CLIENT_REGISTRY_CONTRACT = Path.of("examples", "SmartProductFramework", "ClientRegistry", "ClientRegistry.sol");

    /*
     * ClientStatus enum in Solidity:
     *
     * enum ClientStatus {
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

    private static final String CLIENT_ADDRESS = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";

    private static final String CLIENT_LEI = "529900T8BM49AURSDO55";

    private static final String DEMO_PRODUCT_DEFINITION_NAME = "Simple Bond Product Definition";

    public static void main(String[] args) throws Exception {

        System.out.println("This demo requires a locally running chain. If not already running, start one with:");
        System.out.println("DEPLOYMENT_ACCOUNT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        System.out.println("docker run --rm -it --name besu -p 8545:8545 -p 8546:8546 hyperledger/besu:latest --network=dev --miner-enabled=true --miner-coinbase $DEPLOYMENT_ACCOUNT --rpc-http-enabled=true --rpc-http-host=0.0.0.0 --rpc-http-port=8545 --rpc-http-api=ETH,NET,WEB3,TXPOOL,TRACE,DEBUG --host-allowlist=\"*\" --logging=INFO");
        System.out.println("-".repeat(79));

        String owner = SmartContractDeployer.defaultSenderAddress();
        byte[] productDefinitionId = Hash.sha3(DEMO_PRODUCT_DEFINITION_NAME.getBytes());

        System.out.println("ClientRegistry demo");
        System.out.println("Owner:                  " + owner);
        System.out.println("Client:               " + CLIENT_ADDRESS);
        System.out.println("Client LEI:           " + CLIENT_LEI);
        System.out.println("ProductDefinitionId:    " + Numeric.toHexString(productDefinitionId));
        System.out.println("-".repeat(79));

        System.out.println("Deploying ClientRegistry.");
        String clientRegistry = SmartContractDeployer.deploy(
                CLIENT_REGISTRY_CONTRACT,
                SmartContractDeployer.PARIS,
                new Address(owner)
        );

        System.out.println("ClientRegistry deployed at " + clientRegistry);
        System.out.println("-".repeat(79));

        System.out.println("Registering client.");

        SmartContractDeployer.transact(clientRegistry, new Function("registerClient", List.of(new ClientRegistrationParams(new Address(CLIENT_ADDRESS), new Utf8String(CLIENT_LEI))), List.of()));

        System.out.println("Client registered.");
        System.out.println("-".repeat(79));

        printClientState(clientRegistry, CLIENT_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Suspending client.");
        setClientStatus(clientRegistry, CLIENT_ADDRESS, STATUS_SUSPENDED);
        printClientState(clientRegistry, CLIENT_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Re-activating client.");
        setClientStatus(clientRegistry, CLIENT_ADDRESS, STATUS_ACTIVE);
        printClientState(clientRegistry, CLIENT_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Revoking client.");
        setClientStatus(clientRegistry, CLIENT_ADDRESS, STATUS_REVOKED);
        printClientState(clientRegistry, CLIENT_ADDRESS, productDefinitionId);

        System.out.println();
        System.out.println("Trying to re-activate revoked client. This should fail.");

        try {
            setClientStatus(clientRegistry, CLIENT_ADDRESS, STATUS_ACTIVE);
            throw new AssertionError("Expected revoked client re-activation to fail.");
        }
        catch (Exception expected) {
            System.out.println("Expected failure received.");
            System.out.println("Reason: " + expected.getMessage());
        }

        System.out.println();
        System.out.println("=".repeat(79));
        System.out.println("ClientRegistry demo completed.");
        System.out.println("ClientRegistry: " + clientRegistry);
    }

    private static void setClientStatus(String clientRegistry, String client, BigInteger status) throws Exception {

        SmartContractDeployer.transact(clientRegistry, new Function("setClientStatus", List.of(new Address(client), new Uint8(status)), List.of()));
    }

    private static void printClientState(String clientRegistry, String client, byte[] productDefinitionId) throws Exception {

        ClientView clientView = getClient(clientRegistry, client);

        boolean registered = callBool(clientRegistry, new Function("isRegisteredClient", List.of(new Address(client)), List.of(new TypeReference<Bool>() {})));

        boolean eligible = callBool(clientRegistry, new Function("isEligibleClient", List.of(new Address(client), new Bytes32(productDefinitionId)), List.of(new TypeReference<Bool>() {})));

        System.out.println("Client state:");
        System.out.println("  registered:           " + registered);
        System.out.println("  status:               " + statusName(clientView.status.getValue()));
        System.out.println("  eligible:             " + eligible);
        System.out.println("  lei:                  " + clientView.lei.getValue());
        System.out.println("  registeredAt:         " + clientView.registeredAt.getValue());
        System.out.println("  updatedAt:            " + clientView.updatedAt.getValue());
    }

    private static ClientView getClient(String clientRegistry, String client) throws Exception {
        List<Type> decoded = SmartContractDeployer.call(clientRegistry, new Function("getClient", List.of(new Address(client)), List.of(new TypeReference<ClientView>() {})));
        return (ClientView) decoded.get(0);
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

    public static class ClientRegistrationParams extends DynamicStruct {

        public final Address client;
        public final Utf8String lei;

        public ClientRegistrationParams(Address client, Utf8String lei) {
            super(client, lei);
            this.client = client;
            this.lei = lei;
        }
    }

    public static class ClientView extends DynamicStruct {

        public final Uint8 status;
        public final Utf8String lei;
        public final Uint64 registeredAt;
        public final Uint64 updatedAt;

        public ClientView(Uint8 status, Utf8String lei, Uint64 registeredAt, Uint64 updatedAt) {
            super(status, lei, registeredAt, updatedAt);
            this.status = status;
            this.lei = lei;
            this.registeredAt = registeredAt;
            this.updatedAt = updatedAt;
        }
    }
}
