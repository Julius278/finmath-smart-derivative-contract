import { expect } from "chai";
import { AbiCoder, keccak256 } from "ethers";

/** Confirms the fixture's reviewed literals, never bank details copied blindly from a proposal. */
export async function confirmReviewedClientData(registry, client, expectedLei, expectedBic) {
    const pending = await registry.getPendingClientData(client.address);
    expect(pending.lei).to.equal(expectedLei);
    expect(pending.bic).to.equal(expectedBic);
    const { chainId } = await registry.runner.provider.getNetwork();
    const expectedHash = keccak256(AbiCoder.defaultAbiCoder().encode(
        ["uint256", "address", "address", "uint256", "uint256", "string", "string"],
        [chainId, registry.target, client.address, pending.revision, pending.ownershipEpoch, expectedLei, expectedBic]
    ));
    expect(pending.dataHash).to.equal(expectedHash);
    await (await registry.connect(client).confirmClientData(pending.revision, expectedHash)).wait();
}
