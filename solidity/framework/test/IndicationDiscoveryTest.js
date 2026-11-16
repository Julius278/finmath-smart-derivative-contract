import hre from "hardhat";
import { expect } from "chai";

describe("Indication discovery", function () {
    let ethers, owner, outsider, curves;
    const ACTIVE = 1n, SUSPENDED = 2n, CLOSED = 3n, ARCHIVED = 4n;
    const WITHDRAWN = 2n;

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

    function symbolId(symbol) {
        return ethers.keccak256(ethers.toUtf8Bytes(symbol));
    }

    async function publish(name, quotes = [quote("A")]) {
        await curves.publishCurveIndications(name, quotes);
        return curveId(name);
    }

    async function advanceTimestamp() {
        const latest = await ethers.provider.getBlock("latest");
        const timestamp = latest.timestamp + 10;
        await ethers.provider.send("evm_setNextBlockTimestamp", [timestamp]);
        return BigInt(timestamp);
    }

    function interfaceId(signatures) {
        const value = signatures.reduce((result, signature) =>
            result ^ BigInt(ethers.id(signature).slice(0, 10)), 0n);
        return ethers.toBeHex(value, 4);
    }

    it("preserves the legacy indication, XML and ERC165 interfaces", async function () {
        const legacy = interfaceId([
            "setIndicationStatus(bytes32,uint8)", "indicationCategory()",
            "indicationStatus(bytes32)", "isIndication(bytes32)",
            "partIdForIndication(bytes32)", "indicationForPartId(uint256)"
        ]);
        expect(await curves.supportsInterface(legacy)).to.equal(true);
        expect(await curves.supportsInterface(interfaceId(["statePartXmlTemplate(uint256)"]))).to.equal(true);
        expect(await curves.supportsInterface("0x01ffc9a7")).to.equal(true);
        expect(await curves.supportsInterface("0xffffffff")).to.equal(false);
    });

    it("handles empty pages and unknown ids explicitly, including maximum uint256 offsets", async function () {
        expect(await curves.indicationCount()).to.equal(0n);
        expect(await curves.getIndications(0n, ethers.MaxUint256)).to.deep.equal([]);
        expect(await curves.getIndications(ethers.MaxUint256, ethers.MaxUint256)).to.deep.equal([]);
        await expect(curves.indicationState(ethers.ZeroHash))
            .to.be.revertedWithCustomError(curves, "UnknownIndication").withArgs(ethers.ZeroHash);
        await expect(curves.curveName(ethers.ZeroHash))
            .to.be.revertedWithCustomError(curves, "UnknownIndication").withArgs(ethers.ZeroHash);
        await expect(curves.quoteCount(ethers.ZeroHash))
            .to.be.revertedWithCustomError(curves, "UnknownIndication").withArgs(ethers.ZeroHash);
        await expect(curves.getQuoteStates(ethers.ZeroHash, 0n, 0n))
            .to.be.revertedWithCustomError(curves, "UnknownIndication").withArgs(ethers.ZeroHash);
        await expect(curves.quoteById(ethers.ZeroHash, symbolId("A")))
            .to.be.revertedWithCustomError(curves, "UnknownIndication").withArgs(ethers.ZeroHash);
        expect(await curves.indicationStatus(ethers.ZeroHash)).to.equal(0n);
        expect(await curves.isIndication(ethers.ZeroHash)).to.equal(false);
    });

    it("returns the exact readable curve name across republication and lifecycle changes", async function () {
        const name = "EUR – Zinskurve für Käufer / 日本語";
        const id = await publish(name);
        expect(await curves.curveName(id)).to.equal(name);
        await curves.setIndicationStatus(id, SUSPENDED);
        await publish(name, [quote("B")]);
        expect(await curves.curveName(id)).to.equal(name);
        expect(await curves.indicationCount()).to.equal(1n);
        await curves.setIndicationStatus(id, CLOSED);
        await curves.setIndicationStatus(id, ARCHIVED);
        expect(await curves.curveName(id)).to.equal(name);
        expect((await curves.getIndications(0n, 1n))[0].indicationId).to.equal(id);
    });

    it("retains first-publication order and lifecycle metadata through updates and archival", async function () {
        const first = await publish("First");
        const original = await curves.indicationState(first);
        const second = await publish("Second");
        expect(original.indicationId).to.equal(first);
        expect(original.status).to.equal(ACTIVE);
        expect(original.version).to.equal(1n);
        expect(original.publishedAt).to.be.greaterThan(0n);
        expect(original.updatedAt).to.equal(original.publishedAt);

        await publish("First", [quote("A", { yieldBps: -25n })]);
        await curves.setIndicationStatus(first, SUSPENDED);
        await publish("First", [quote("B")]);
        const suspended = await curves.indicationState(first);
        expect(suspended.status).to.equal(SUSPENDED);
        expect(suspended.version).to.equal(3n);
        expect(suspended.publishedAt).to.equal(original.publishedAt);
        expect(suspended.updatedAt).to.be.at.least(original.updatedAt);
        await curves.setIndicationStatus(first, SUSPENDED);
        expect(await curves.indicationState(first)).to.deep.equal(suspended);

        await curves.setIndicationStatus(first, CLOSED);
        await curves.setIndicationStatus(first, ARCHIVED);
        const states = await curves.getIndications(0n, 10n);
        expect(states.map(s => s.indicationId)).to.deep.equal([first, second]);
        expect(states.map(s => s.status)).to.deep.equal([ARCHIVED, ACTIVE]);
        expect(states[0].version).to.equal(3n);
        expect(await curves.indicationCount()).to.equal(2n);
        expect(await curves.isIndication(first)).to.equal(true);
        const partId = await curves.partIdForIndication(first);
        expect(await curves.indicationForPartId(partId)).to.equal(first);
        await expect(publish("First"))
            .to.be.revertedWithCustomError(curves, "IndicationNotWritable").withArgs(first, ARCHIVED);
        await expect(curves.setIndicationStatus(first, ACTIVE))
            .to.be.revertedWithCustomError(curves, "InvalidStatusTransition").withArgs(ARCHIVED, ACTIVE);
        expect(await curves.indicationState(first)).to.deep.equal(states[0]);
    });

    it("touches lifecycle timestamps without revising content and ignores repeated status assignments", async function () {
        const id = await publish("Lifecycle");
        const original = await curves.indicationState(id);
        const quotes = await curves.getQuoteStates(id, 0n, 100n);
        const partId = await curves.partIdForIndication(id);
        let previousStatus = ACTIVE;
        for (const status of [ACTIVE, SUSPENDED, ACTIVE, CLOSED, ARCHIVED]) {
            const timestamp = await advanceTimestamp();
            const tx = curves.setIndicationStatus(id, status);
            if (status !== previousStatus) {
                await expect(tx).to.emit(curves, "IndicationStatusChanged").withArgs(id, previousStatus, status)
                    .and.to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 1n);
            } else {
                await expect(tx).to.not.emit(curves, "IndicationStatusChanged")
                    .and.to.not.emit(curves, "StatePartUpdated");
            }
            const current = await curves.indicationState(id);
            expect(current.status).to.equal(status);
            expect(current.version).to.equal(original.version);
            expect(current.publishedAt).to.equal(original.publishedAt);
            expect(current.updatedAt).to.equal(status === previousStatus ? original.updatedAt : timestamp);
            expect(await curves.getQuoteStates(id, 0n, 100n)).to.deep.equal(quotes);

            await advanceTimestamp();
            await expect(curves.setIndicationStatus(id, status)).to.not.emit(curves, "IndicationStatusChanged")
                .and.to.not.emit(curves, "StatePartUpdated");
            expect(await curves.indicationState(id)).to.deep.equal(current);
            previousStatus = status;
        }

        const suspendedId = await publish("Suspended to closed");
        await curves.setIndicationStatus(suspendedId, SUSPENDED);
        const timestamp = await advanceTimestamp();
        await curves.setIndicationStatus(suspendedId, CLOSED);
        const closed = await curves.indicationState(suspendedId);
        expect(closed.version).to.equal(1n);
        expect(closed.updatedAt).to.equal(timestamp);
    });

    it("clamps indication pages to 100 and supports exact, partial and past-end pages", async function () {
        this.timeout(120_000);
        const ids = [];
        for (let i = 0; i < 102; i++) ids.push(await publish(`Curve-${i}`));
        const first = await curves.getIndications(0n, ethers.MaxUint256);
        const last = await curves.getIndications(100n, ethers.MaxUint256);
        expect(first).to.have.length(100);
        expect(last.map(s => s.indicationId)).to.deep.equal(ids.slice(100));
        expect([...first, ...last].map(s => s.indicationId)).to.deep.equal(ids);
        expect((await curves.getIndications(1n, 1n))[0].indicationId).to.equal(ids[1]);
        expect(await curves.getIndications(0n, 0n)).to.deep.equal([]);
        expect(await curves.getIndications(102n, 1n)).to.deep.equal([]);
        expect(await curves.getIndications(ethers.MaxUint256, ethers.MaxUint256)).to.deep.equal([]);
        expect(await curves.indicationCount()).to.equal(102n);
    });

    it("keeps historical quote ids and last data through withdrawal, reactivation and replacement", async function () {
        const publishedAt = await advanceTimestamp();
        const id = await publish("Curve", [quote("A"), quote("B"), quote("C")]);
        const partId = await curves.partIdForIndication(id);
        async function expectRevision(version, timestamp) {
            const state = await curves.indicationState(id);
            expect(state.version).to.equal(version);
            expect(state.updatedAt).to.equal(timestamp);
            expect(state.publishedAt).to.equal(publishedAt);
        }
        await expectRevision(1n, publishedAt);
        const updatedAt = await advanceTimestamp();
        await expect(curves.updateCurveQuote(id, quote("A", { yieldBps: -50n })))
            .to.emit(curves, "CurveQuoteUpdated").withArgs(id, symbolId("A"), "A", 2n)
            .and.to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 2n);
        await expectRevision(2n, updatedAt);
        const withdrawnAt = await advanceTimestamp();
        await expect(curves.withdrawCurveQuote(id, "B"))
            .to.emit(curves, "CurveQuoteWithdrawn").withArgs(id, symbolId("B"), "B", 1n)
            .and.to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 3n);
        await expectRevision(3n, withdrawnAt);
        let states = await curves.getQuoteStates(id, 0n, 100n);
        expect(states.map(s => s.symbolId)).to.deep.equal(["A", "B", "C"].map(symbolId));
        expect(states.map(s => s.quoteVersion)).to.deep.equal([2n, 1n, 1n]);
        expect(states.map(s => s.updatedAt)).to.deep.equal([updatedAt, withdrawnAt, publishedAt]);
        expect(states.map(s => s.status)).to.deep.equal([ACTIVE, WITHDRAWN, ACTIVE]);
        expect((await curves.quoteById(id, symbolId("B"))).symbol).to.equal("B");
        expect((await curves.activeQuotes(id)).map(q => q.symbol)).to.deep.equal(["A", "C"]);
        await expect(curves.withdrawCurveQuote(id, "B"))
            .to.be.revertedWithCustomError(curves, "QuoteNotActive").withArgs(id, "B");
        await expectRevision(3n, withdrawnAt);
        expect(await curves.getQuoteStates(id, 0n, 100n)).to.deep.equal(states);
        const reactivatedAt = await advanceTimestamp();
        await expect(curves.addCurveQuote(id, quote("B", { yieldBps: 400n })))
            .to.emit(curves, "CurveQuoteAdded").withArgs(id, symbolId("B"), "B", 2n)
            .and.to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 4n);
        await expectRevision(4n, reactivatedAt);
        const republishedAt = await advanceTimestamp();
        await expect(curves.publishCurveIndications("Curve", [quote("C"), quote("A", { yieldBps: -75n }), quote("D")]))
            .to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 5n);
        await expectRevision(5n, republishedAt);
        states = await curves.getQuoteStates(id, 0n, 100n);
        expect(states.map(s => s.symbolId)).to.deep.equal(["A", "B", "C", "D"].map(symbolId));
        expect(states.map(s => s.status)).to.deep.equal([ACTIVE, WITHDRAWN, ACTIVE, ACTIVE]);
        expect(states.map(s => s.quoteVersion)).to.deep.equal([3n, 2n, 2n, 1n]);
        expect(states.every(s => s.updatedAt === republishedAt)).to.equal(true);
        expect((await curves.quoteById(id, symbolId("A"))).yieldBps).to.equal(-75n);
        expect((await curves.quoteById(id, symbolId("B"))).yieldBps).to.equal(400n);
        expect(await curves.quoteCount(id)).to.equal(4n);
        expect(await curves.activeQuoteCount(id)).to.equal(3n);
        await expect(curves.quoteById(id, symbolId("Unknown")))
            .to.be.revertedWithCustomError(curves, "UnknownQuoteId").withArgs(id, symbolId("Unknown"));
    });

    it("treats explicit publication and quote updates as revisions even with identical terms", async function () {
        const id = await publish("Same terms");
        const original = await curves.indicationState(id);
        const partId = await curves.partIdForIndication(id);
        const republishedAt = await advanceTimestamp();
        await expect(curves.publishCurveIndications("Same terms", [quote("A")]))
            .to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 2n);
        const republished = await curves.indicationState(id);
        expect(republished.version).to.equal(2n);
        expect(republished.updatedAt).to.equal(republishedAt);
        expect(republished.publishedAt).to.equal(original.publishedAt);
        expect((await curves.getQuoteStates(id, 0n, 1n))[0].quoteVersion).to.equal(2n);

        const updatedAt = await advanceTimestamp();
        await expect(curves.updateCurveQuote(id, quote("A")))
            .to.emit(curves, "CurveQuoteUpdated").withArgs(id, symbolId("A"), "A", 3n)
            .and.to.emit(curves, "StatePartUpdated").withArgs(owner.address, curves.target, partId, 3n);
        const updated = await curves.indicationState(id);
        expect(updated.version).to.equal(3n);
        expect(updated.updatedAt).to.equal(updatedAt);
        expect(updated.publishedAt).to.equal(original.publishedAt);
        const quoteState = (await curves.getQuoteStates(id, 0n, 1n))[0];
        expect(quoteState.quoteVersion).to.equal(3n);
        expect(quoteState.updatedAt).to.equal(updatedAt);
    });

    it("pages quote history independently of the bounded active board", async function () {
        const id = curveId("History");
        for (let batch = 0; batch < 6; batch++) {
            await publish("History", Array.from({ length: 20 }, (_, i) => quote(`Q${batch * 20 + i}`)));
        }
        const first = await curves.getQuoteStates(id, 0n, ethers.MaxUint256);
        const last = await curves.getQuoteStates(id, 100n, ethers.MaxUint256);
        expect(first).to.have.length(100);
        expect(last).to.have.length(20);
        expect(first.every(s => s.status === WITHDRAWN)).to.equal(true);
        expect(last.every(s => s.status === ACTIVE)).to.equal(true);
        expect([...first, ...last].map(s => s.symbolId)).to.deep.equal(
            Array.from({ length: 120 }, (_, i) => symbolId(`Q${i}`))
        );
        expect(await curves.quoteCount(id)).to.equal(120n);
        expect(await curves.activeQuoteCount(id)).to.equal(20n);
        expect((await curves.getQuoteStates(id, 119n, 20n))[0].symbolId).to.equal(symbolId("Q119"));
        expect(await curves.getQuoteStates(id, 0n, 0n)).to.deep.equal([]);
        expect(await curves.getQuoteStates(id, 120n, 1n)).to.deep.equal([]);
        expect(await curves.getQuoteStates(id, ethers.MaxUint256, ethers.MaxUint256)).to.deep.equal([]);
    });

    it("does not confuse a curve lifecycle with its quotes or change existing rendering getters", async function () {
        const id = await publish("Curve", [quote("A")]);
        const part = await curves.partIdForIndication(id);
        const active = await curves.activeQuotes(id);
        await curves.setIndicationStatus(id, SUSPENDED);
        expect((await curves.getIndications(0n, 1n))[0].status).to.equal(SUSPENDED);
        expect((await curves.getQuoteStates(id, 0n, 1n))[0].status).to.equal(ACTIVE);
        expect(await curves.activeQuotesByPartId(part)).to.deep.equal(active);
        expect(await curves.activeQuoteCountByPartId(part)).to.equal(1n);
        expect(await curves.indicationStatusByPartId(part)).to.equal(SUSPENDED);
        expect(await curves.statePartXmlTemplate(part)).to.contain("activeQuotesByPartId");
        await curves.withdrawCurveQuote(id, "A");
        expect(await curves.activeQuotes(id)).to.deep.equal([]);
        expect(await curves.quoteCount(id)).to.equal(1n);
        expect((await curves.getQuoteStates(id, 0n, 1n))[0].status).to.equal(WITHDRAWN);
        expect(await curves.quoteById(id, symbolId("A"))).to.deep.equal(active[0]);
    });

    it("keeps summary return sizes fixed even for large names and quote strings", async function () {
        const short = await publish("Short", [quote("A")]);
        const longSymbol = "Z".repeat(1024);
        const long = await publish("Long".repeat(256), [quote(longSymbol)]);
        for (const id of [short, long]) {
            const quoteData = await ethers.provider.call({
                to: curves.target, data: curves.interface.encodeFunctionData("getQuoteStates", [id, 0n, 1n])
            });
            expect(ethers.getBytes(quoteData)).to.have.length(64 + 4 * 32);
        }
        const indicationData = await ethers.provider.call({
            to: curves.target, data: curves.interface.encodeFunctionData("getIndications", [0n, 2n])
        });
        expect(ethers.getBytes(indicationData)).to.have.length(64 + 2 * 5 * 32);
        expect((await curves.quoteById(long, symbolId(longSymbol))).symbol).to.equal(longSymbol);
    });

    it("can read all pages and quote details against the same historical block", async function () {
        const id = await publish("Curve");
        const snapshot = await ethers.provider.getBlock("latest");
        await publish("Curve", [quote("B")]);
        await publish("Later");
        const block = { blockTag: snapshot.number };
        expect(await curves.indicationCount(block)).to.equal(1n);
        expect(await curves.quoteCount(id, block)).to.equal(1n);
        expect((await curves.getIndications(0n, 10n, block))[0].version).to.equal(1n);
        expect((await curves.getQuoteStates(id, 0n, 10n, block))[0].status).to.equal(ACTIVE);
        expect((await curves.quoteById(id, symbolId("A"), block)).symbol).to.equal("A");
        expect(await curves.indicationCount()).to.equal(2n);
        expect((await curves.getQuoteStates(id, 0n, 10n))[0].status).to.equal(WITHDRAWN);
    });

    it("rolls back all discovery entries after unauthorized or partially processed publications", async function () {
        await expect(curves.connect(outsider).publishCurveIndications("Denied", [quote("A")]))
            .to.be.revertedWith("Ownable: caller is not the owner");
        await expect(publish("Invalid", [quote("A"), quote("Bad<symbol")]))
            .to.be.revertedWithCustomError(curves, "InvalidCharacter").withArgs("symbol");
        expect(await curves.indicationCount()).to.equal(0n);
        expect(await curves.getIndications(0n, 100n)).to.deep.equal([]);
        const id = await publish("Invalid", [quote("Original")]);
        const original = await curves.indicationState(id);
        const originalQuotes = await curves.getQuoteStates(id, 0n, 100n);
        await advanceTimestamp();
        await expect(publish("Invalid", [quote("New"), quote("Bad<symbol")]))
            .to.be.revertedWithCustomError(curves, "InvalidCharacter");
        expect(await curves.indicationState(id)).to.deep.equal(original);
        expect(await curves.getQuoteStates(id, 0n, 100n)).to.deep.equal(originalQuotes);
        expect(await curves.quoteCount(id)).to.equal(1n);
        expect((await curves.getQuoteStates(id, 0n, 100n)).map(s => s.symbolId)).to.deep.equal([symbolId("Original")]);
        expect((await curves.activeQuotes(id))[0].symbol).to.equal("Original");
        await expect(curves.connect(outsider).addCurveQuote(id, quote("Denied")))
            .to.be.revertedWith("Ownable: caller is not the owner");
        await expect(curves.connect(outsider).setIndicationStatus(id, SUSPENDED))
            .to.be.revertedWith("Ownable: caller is not the owner");
        await expect(curves.setIndicationStatus(id, ARCHIVED))
            .to.be.revertedWithCustomError(curves, "InvalidStatusTransition").withArgs(ACTIVE, ARCHIVED);
        await expect(curves.updateCurveQuote(id, quote("Original", { currency: "EUR<" })))
            .to.be.revertedWithCustomError(curves, "InvalidCharacter").withArgs("currency");
        await expect(curves.withdrawCurveQuote(id, "Unknown"))
            .to.be.revertedWithCustomError(curves, "UnknownQuote").withArgs(id, "Unknown");
        expect(await curves.quoteCount(id)).to.equal(1n);
        expect(await curves.indicationState(id)).to.deep.equal(original);
        expect(await curves.getQuoteStates(id, 0n, 100n)).to.deep.equal(originalQuotes);
    });

    it("does not append a quote when the active board limit rejects its addition", async function () {
        const id = await publish("Full", Array.from({ length: 20 }, (_, i) => quote(`Q${i}`)));
        const original = await curves.indicationState(id);
        await expect(curves.addCurveQuote(id, quote("Overflow")))
            .to.be.revertedWithCustomError(curves, "TooManyQuotes").withArgs(21n);
        expect(await curves.quoteCount(id)).to.equal(20n);
        expect(await curves.indicationState(id)).to.deep.equal(original);
        await expect(curves.quoteById(id, symbolId("Overflow")))
            .to.be.revertedWithCustomError(curves, "UnknownQuoteId");
    });
});
