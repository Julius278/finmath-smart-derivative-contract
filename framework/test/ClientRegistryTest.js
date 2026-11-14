import hre from "hardhat";
import { expect } from "chai";

describe("ClientRegistry identity approval", function () {
    let ethers, registry, owner, client, other, nextOwner;
    const LEI = "529900T8BM49AURSDO55";
    const BIC = "MARKDEFFXXX";
    const NEXT_BIC = "DEUTDEFFXXX";
    const UNKNOWN = 0n, PENDING = 1n, ACTIVE = 2n, SUSPENDED = 3n, REVOKED = 4n;

    beforeEach(async function () {
        ({ ethers } = await hre.network.create());
        [owner, client, other, nextOwner] = await ethers.getSigners();
        registry = await (await ethers.getContractFactory("ClientRegistry")).deploy(owner.address);
        await registry.waitForDeployment();
    });

    async function propose(signer = client, bic = BIC) {
        await registry.registerClient({ client: signer.address, lei: LEI, bic });
        return registry.getPendingClientData(signer.address);
    }

    async function hash(proposal, signer = client, bic = BIC, domain = {}) {
        const { chainId } = await ethers.provider.getNetwork();
        return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
            ["uint256", "address", "address", "uint256", "uint256", "string", "string"],
            [domain.chainId ?? chainId, domain.registry ?? registry.target,
                domain.client ?? signer.address, proposal.revision, proposal.ownershipEpoch, LEI, bic]
        ));
    }

    async function confirm(proposal, signer = client, bic = BIC) {
        return registry.connect(signer).confirmClientData(proposal.revision, await hash(proposal, signer, bic));
    }

    async function activate() {
        await confirm(await propose());
    }

    it("keeps the public status ordinals ordered Unknown, Pending, Active, Suspended, Revoked", async function () {
        const statuses = [await registry.clientStatus(client.address)];
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
        const proposal = await propose();
        statuses.push(await registry.clientStatus(client.address));
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
        await confirm(proposal);
        statuses.push(await registry.clientStatus(client.address));
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(true);
        await registry.setClientStatus(client.address, SUSPENDED);
        statuses.push(await registry.clientStatus(client.address));
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
        await registry.setClientStatus(client.address, REVOKED);
        statuses.push(await registry.clientStatus(client.address));
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
        expect(statuses).to.deep.equal([0n, 1n, 2n, 3n, 4n]);
    });

    it("registers pending without publishing unapproved identity or granting eligibility", async function () {
        await expect(registry.registerClient({ client: client.address, lei: LEI, bic: BIC }))
            .to.emit(registry, "ClientStatusChanged").withArgs(client.address, UNKNOWN, PENDING);
        const stored = await registry.getClient(client.address);
        expect(stored.status).to.equal(PENDING);
        expect(stored.lei).to.equal("");
        expect(stored.bic).to.equal("");
        expect(stored.registeredAt).to.be.greaterThan(0n);
        expect(await registry.isRegisteredClient(client.address)).to.equal(true);
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
        const proposal = await registry.getPendingClientData(client.address);
        expect(proposal.lei).to.equal(LEI);
        expect(proposal.bic).to.equal(BIC);
        expect(proposal.dataHash).to.equal(await hash(proposal));
        await expect(registry.setClientStatus(client.address, ACTIVE))
            .to.be.revertedWithCustomError(registry, "ClientDataNotConfirmed");
    });

    it("only the owner can register or propose changes; clients cannot submit a chosen BIC", async function () {
        const params = { client: client.address, lei: LEI, bic: NEXT_BIC };
        await expect(registry.connect(client).registerClient(params)).to.be.revertedWith("Ownable: caller is not the owner");
        await activate();
        await expect(registry.connect(client).updateClient(params)).to.be.revertedWith("Ownable: caller is not the owner");
        await expect(registry.connect(other).updateClient(params)).to.be.revertedWith("Ownable: caller is not the owner");
        expect((await registry.getClient(client.address)).bic).to.equal(BIC);
    });

    it("requires the exact client and reviewed data, then activates once", async function () {
        const proposal = await propose();
        await expect(registry.confirmClientData(proposal.revision, proposal.dataHash))
            .to.be.revertedWithCustomError(registry, "UnknownClient").withArgs(owner.address);
        await propose(other);
        await expect(registry.connect(other).confirmClientData(proposal.revision, proposal.dataHash))
            .to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        await expect(registry.connect(client).confirmClientData(proposal.revision, await hash(proposal, client, NEXT_BIC)))
            .to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        await expect(confirm(proposal)).to.emit(registry, "ClientDataConfirmed")
            .withArgs(client.address, proposal.revision, proposal.dataHash);
        const stored = await registry.getClient(client.address);
        expect(stored.status).to.equal(ACTIVE);
        expect(stored.lei).to.equal(LEI);
        expect(stored.bic).to.equal(BIC);
        expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(true);
        await expect(confirm(proposal)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
        await expect(registry.getPendingClientData(client.address)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
    });

    it("binds the digest to chain, registry and client", async function () {
        const proposal = await propose();
        const { chainId } = await ethers.provider.getNetwork();
        for (const domain of [{ chainId: chainId + 1n }, { registry: other.address }, { client: other.address }]) {
            await expect(registry.connect(client).confirmClientData(proposal.revision, await hash(proposal, client, BIC, domain)))
                .to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        }
    });

    it("retains the complete confirmed record until an update is approved", async function () {
        await activate();
        const original = await registry.getClient(client.address);
        await expect(registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC }))
            .not.to.emit(registry, "ClientUpdated");
        expect(await registry.getClient(client.address)).to.deep.equal(original);
        const proposal = await registry.getPendingClientData(client.address);
        expect(proposal.revision).to.equal(2n);
        await expect(confirm(proposal, client, NEXT_BIC)).to.emit(registry, "ClientUpdated").withArgs(client.address);
        const updated = await registry.getClient(client.address);
        expect(updated.bic).to.equal(NEXT_BIC);
        expect(updated.registeredAt).to.equal(original.registeredAt);
        expect(updated.updatedAt).to.be.greaterThan(original.updatedAt);
        expect(updated.status).to.equal(ACTIVE);
    });

    it("rejects an approval raced by proposal replacement, even if the values are the same", async function () {
        const original = await propose();
        await registry.updateClient({ client: client.address, lei: LEI, bic: BIC });
        const replacement = await registry.getPendingClientData(client.address);
        expect(replacement.revision).to.equal(original.revision + 1n);
        expect(replacement.dataHash).not.to.equal(original.dataHash);
        await expect(confirm(original)).to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        await expect(registry.connect(client).confirmClientData(replacement.revision, original.dataHash))
            .to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        await confirm(replacement);
    });

    for (const who of ["owner", "client"]) {
        it(`allows ${who} to cancel, preserves the record and never reuses a cancelled revision`, async function () {
            await activate();
            const original = await registry.getClient(client.address);
            await registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC });
            const proposal = await registry.getPendingClientData(client.address);
            await expect(registry.connect(who === "owner" ? owner : client).cancelClientDataProposal(client.address, proposal.revision))
                .to.emit(registry, "ClientDataProposalCancelled").withArgs(client.address, proposal.revision);
            expect(await registry.getClient(client.address)).to.deep.equal(original);
            await expect(confirm(proposal, client, NEXT_BIC)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
            await registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC });
            const replacement = await registry.getPendingClientData(client.address);
            expect(replacement.revision).to.equal(proposal.revision + 1n);
            await expect(confirm(proposal, client, NEXT_BIC)).to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        });
    }

    it("rejects cancellation by a third party or using an obsolete revision", async function () {
        const proposal = await propose();
        await expect(registry.connect(other).cancelClientDataProposal(client.address, proposal.revision))
            .to.be.revertedWithCustomError(registry, "UnauthorizedClientDataAction");
        await expect(registry.cancelClientDataProposal(client.address, proposal.revision + 1n))
            .to.be.revertedWithCustomError(registry, "InvalidClientDataConfirmation");
        await confirm(proposal);
    });

    it("can repropose a cancelled initial registration without releasing the client address", async function () {
        const proposal = await propose();
        await registry.connect(client).cancelClientDataProposal(client.address, proposal.revision);
        expect(await registry.clientStatus(client.address)).to.equal(PENDING);
        await expect(propose()).to.be.revertedWithCustomError(registry, "ClientAlreadyRegistered");
        await registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC });
        await confirm(await registry.getPendingClientData(client.address), client, NEXT_BIC);
        expect(await registry.clientStatus(client.address)).to.equal(ACTIVE);
    });

    for (const alreadyConfirmed of [false, true]) {
        it(`keeps an owner suspension effective when confirming ${alreadyConfirmed ? "updated" : "initial"} identity`, async function () {
            if (alreadyConfirmed) {
                await activate();
                await registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC });
            } else {
                await propose(client, NEXT_BIC);
            }
            const proposal = await registry.getPendingClientData(client.address);
            await registry.setClientStatus(client.address, SUSPENDED);
            if (!alreadyConfirmed) {
                await expect(registry.setClientStatus(client.address, ACTIVE))
                    .to.be.revertedWithCustomError(registry, "ClientDataNotConfirmed");
            }
            await confirm(proposal, client, NEXT_BIC);
            expect(await registry.clientStatus(client.address)).to.equal(SUSPENDED);
            expect((await registry.getClient(client.address)).bic).to.equal(NEXT_BIC);
            expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
            await expect(registry.connect(client).setClientStatus(client.address, ACTIVE))
                .to.be.revertedWith("Ownable: caller is not the owner");
            await registry.setClientStatus(client.address, ACTIVE);
            expect(await registry.clientStatus(client.address)).to.equal(ACTIVE);
        });
    }

    for (const alreadyConfirmed of [false, true]) {
        it(`makes revocation terminal for ${alreadyConfirmed ? "confirmed" : "pending"} clients`, async function () {
            if (alreadyConfirmed) {
                await activate();
                await registry.updateClient({ client: client.address, lei: LEI, bic: BIC });
            } else {
                await propose();
            }
            const proposal = await registry.getPendingClientData(client.address);
            await registry.setClientStatus(client.address, REVOKED);
            await expect(confirm(proposal)).to.be.revertedWithCustomError(registry, "RevokedClient");
            await expect(registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC }))
                .to.be.revertedWithCustomError(registry, "RevokedClient");
            await expect(registry.getPendingClientData(client.address)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
            for (const status of [ACTIVE, SUSPENDED, PENDING, UNKNOWN]) {
                await expect(registry.setClientStatus(client.address, status))
                    .to.be.revertedWithCustomError(registry, "InvalidStatusTransition");
            }
            expect(await registry.isRegisteredClient(client.address)).to.equal(true);
            expect(await registry.isEligibleClient(client.address, ethers.ZeroHash)).to.equal(false);
        });
    }

    it("prevents owner resets to Unknown or Pending", async function () {
        await activate();
        for (const status of [UNKNOWN, PENDING]) {
            await expect(registry.setClientStatus(client.address, status))
                .to.be.revertedWithCustomError(registry, "InvalidStatusTransition");
        }
    });

    it("keeps proposals valid while ownership transfer is only pending", async function () {
        const proposal = await propose();
        await registry.transferOwnership(nextOwner.address);
        expect(await registry.ownershipEpoch()).to.equal(proposal.ownershipEpoch);
        await confirm(proposal);
        expect(await registry.clientStatus(client.address)).to.equal(ACTIVE);
    });

    it("invalidates proposals across completed ownership transfers, even A -> B -> A", async function () {
        const proposal = await propose();
        await registry.transferOwnership(nextOwner.address);
        await registry.connect(nextOwner).acceptOwnership();
        expect(await registry.ownershipEpoch()).to.equal(proposal.ownershipEpoch + 1n);
        await expect(confirm(proposal)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
        await registry.connect(nextOwner).transferOwnership(owner.address);
        await registry.acceptOwnership();
        expect(await registry.ownershipEpoch()).to.equal(proposal.ownershipEpoch + 2n);
        await expect(registry.getPendingClientData(client.address)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
        await expect(confirm(proposal)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
        await registry.updateClient({ client: client.address, lei: LEI, bic: BIC });
        const replacement = await registry.getPendingClientData(client.address);
        expect(replacement.revision).to.equal(proposal.revision + 1n);
        await confirm(replacement);
    });

    it("preserves confirmed identity across ownership handover while requiring the new owner's proposal", async function () {
        await activate();
        const original = await registry.getClient(client.address);
        await registry.updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC });
        await registry.transferOwnership(nextOwner.address);
        await registry.connect(nextOwner).acceptOwnership();
        expect(await registry.getClient(client.address)).to.deep.equal(original);
        await registry.connect(nextOwner).updateClient({ client: client.address, lei: LEI, bic: NEXT_BIC });
        await confirm(await registry.getPendingClientData(client.address), client, NEXT_BIC);
        expect((await registry.getClient(client.address)).bic).to.equal(NEXT_BIC);
    });

    it("invalidates pending proposals on ownership renunciation", async function () {
        const proposal = await propose();
        await registry.renounceOwnership();
        expect(await registry.ownershipEpoch()).to.equal(proposal.ownershipEpoch + 1n);
        await expect(confirm(proposal)).to.be.revertedWithCustomError(registry, "NoPendingClientData");
    });

    it("retains basic registration validation and unknown-client behavior", async function () {
        await expect(registry.registerClient({ client: ethers.ZeroAddress, lei: LEI, bic: BIC }))
            .to.be.revertedWithCustomError(registry, "ZeroAddress");
        for (const field of ["lei", "bic"]) {
            await expect(registry.registerClient({ client: client.address, lei: LEI, bic: BIC, [field]: "" }))
                .to.be.revertedWithCustomError(registry, "EmptyString").withArgs(field);
        }
        await expect(registry.updateClient({ client: client.address, lei: LEI, bic: BIC }))
            .to.be.revertedWithCustomError(registry, "UnknownClient");
        await expect(registry.getClient(client.address)).to.be.revertedWithCustomError(registry, "UnknownClient");
        expect(await registry.clientStatus(client.address)).to.equal(UNKNOWN);
        expect(await registry.isRegisteredClient(client.address)).to.equal(false);
    });
});
