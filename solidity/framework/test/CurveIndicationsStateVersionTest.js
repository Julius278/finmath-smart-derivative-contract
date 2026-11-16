import hre from "hardhat";
import { expect } from "chai";

describe("CurveIndications representation version", function () {
    let ethers, owner, outsider, curves;
    const ACTIVE = 1n, SUSPENDED = 2n, CLOSED = 3n, ARCHIVED = 4n;

    beforeEach(async function () {
        ({ ethers } = await hre.network.create());
        [owner, outsider] = await ethers.getSigners();
        curves = await (await ethers.getContractFactory("CurveIndications")).deploy(owner.address);
        await curves.waitForDeployment();
    });

    function quote(symbol, overrides = {}) {
        return {
            symbol, durationInDays: 365n, settlementDate: 1_900_000_000n,
            maturityDate: 1_931_536_000n, dayCountConvention: "ACT/365",
            couponRateBps: 350n, currency: "EUR", yieldBps: 375n,
            issuePriceE8: 10_000_000_000n, redemptionValueE8: 10_000_000_000n,
            minNotionalE8: 100_000_000n, maxNotionalE8: 1_000_000_000_000n,
            ...overrides
        };
    }

    function curveId(name) {
        return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
            ["string", "address"], [name, curves.target]
        ));
    }

    it("invalidates globally for publication, updates, withdrawals and reactivation across parts", async function () {
        expect(await curves.stateVersion()).to.equal(0n);
        const first = curveId("First");
        await curves.publishCurveIndications("First", [quote("A"), quote("B")]);
        const snapshot = await ethers.provider.getBlock("latest");
        expect(await curves.stateVersion()).to.equal(1n);

        await curves.publishCurveIndications("Second", [quote("Other")]);
        expect(await curves.stateVersion()).to.equal(2n);
        expect((await curves.indicationState(first)).version).to.equal(1n);
        await curves.updateCurveQuote(first, quote("A", { yieldBps: -50n }));
        expect(await curves.stateVersion()).to.equal(3n);
        expect((await curves.activeQuotes(first))[0].yieldBps).to.equal(-50n);
        await curves.withdrawCurveQuote(first, "B");
        expect(await curves.stateVersion()).to.equal(4n);
        expect(await curves.activeQuoteCount(first)).to.equal(1n);
        await curves.addCurveQuote(first, quote("B"));
        expect(await curves.stateVersion()).to.equal(5n);
        expect(await curves.activeQuoteCount(first)).to.equal(2n);
        await curves.publishCurveIndications("First", [quote("C")]);
        expect(await curves.stateVersion()).to.equal(6n);
        expect((await curves.activeQuotes(first)).map(q => q.symbol)).to.deep.equal(["C"]);

        const historic = { blockTag: snapshot.number };
        expect(await curves.stateVersion(historic)).to.equal(1n);
        expect((await curves.activeQuotes(first, historic)).map(q => q.symbol)).to.deep.equal(["A", "B"]);
    });

    it("includes all lifecycle transitions without changing content versions, and ignores status no-ops", async function () {
        const id = curveId("Lifecycle");
        await curves.publishCurveIndications("Lifecycle", [quote("A")]);
        let version = 1n;
        for (const status of [SUSPENDED, ACTIVE, SUSPENDED, CLOSED, ARCHIVED]) {
            await curves.setIndicationStatus(id, status);
            expect(await curves.stateVersion()).to.equal(++version);
            expect(await curves.indicationStatusByPartId(BigInt(id))).to.equal(status);
            expect((await curves.indicationState(id)).version).to.equal(1n);
            await curves.setIndicationStatus(id, status);
            expect(await curves.stateVersion()).to.equal(version);
        }
    });

    it("retains the version and represented state after reverted or unauthorized changes", async function () {
        const id = curveId("Rollback");
        await curves.publishCurveIndications("Rollback", [quote("Original")]);
        const before = await curves.activeQuotes(id);
        await expect(curves.publishCurveIndications("Rollback", [quote("New"), quote("Bad<symbol")]))
            .to.be.revertedWithCustomError(curves, "InvalidCharacter");
        await expect(curves.connect(outsider).updateCurveQuote(id, quote("Original")))
            .to.be.revertedWith("Ownable: caller is not the owner");
        await expect(curves.setIndicationStatus(id, ARCHIVED))
            .to.be.revertedWithCustomError(curves, "InvalidStatusTransition");
        expect(await curves.stateVersion()).to.equal(1n);
        expect(await curves.activeQuotes(id)).to.deep.equal(before);
    });

    it("advertises versioned partial XML and remains stable when only time or ownership changes", async function () {
        const selector = signature => ethers.id(signature).slice(0, 10);
        expect(await curves.supportsInterface(selector("stateVersion()"))).to.equal(true);
        expect(await curves.supportsInterface(selector("statePartXmlTemplate(uint256)"))).to.equal(true);
        expect(await curves.supportsInterface(selector("stateXmlTemplate()"))).to.equal(false);
        expect(await curves.supportsInterface("0x01ffc9a7")).to.equal(true);
        expect(await curves.supportsInterface("0xffffffff")).to.equal(false);

        const id = curveId("Stable");
        await curves.publishCurveIndications("Stable", [quote("A")]);
        const quotes = await curves.activeQuotes(id);
        await ethers.provider.send("evm_increaseTime", [86_400]);
        await ethers.provider.send("evm_mine", []);
        await curves.transferOwnership(outsider.address);
        await curves.connect(outsider).acceptOwnership();
        expect(await curves.stateVersion()).to.equal(1n);
        expect(await curves.activeQuotes(id)).to.deep.equal(quotes);
        expect(await curves.indicationStatusByPartId(BigInt(id))).to.equal(ACTIVE);
    });
});
