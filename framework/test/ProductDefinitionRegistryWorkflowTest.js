import hre from "hardhat";
import { expect } from "chai";
import { keccak256, toUtf8Bytes, MaxUint256, ZeroAddress, ZeroHash } from "ethers";
import { confirmReviewedClientData } from "./helpers/clientRegistry.js";

describe("ProductDefinitionRegistry retained workflows", function () {
    let ethers, owner, alice, bob, clients, registry, factory, terms, documentation;
    const LEI = "00000000000000000098";
    const BIC = "DEMOXXXX";
    const ACTIVE = 1n, SUSPENDED = 2n, RETIRED = 3n;

    async function resource(type, mediaType, text) {
        const content = toUtf8Bytes(text);
        const result = await (await ethers.getContractFactory("TextResource")).deploy(
            owner.address, type, mediaType, content, keccak256(content)
        );
        await result.waitForDeployment();
        return result;
    }

    beforeEach(async function () {
        ({ ethers } = await hre.network.create());
        [owner, alice, bob] = await ethers.getSigners();
        clients = await (await ethers.getContractFactory("ClientRegistry")).deploy(owner.address);
        await clients.waitForDeployment();
        registry = await (await ethers.getContractFactory("ProductDefinitionRegistry"))
            .deploy(owner.address, clients.target);
        await registry.waitForDeployment();
        const library = await (await ethers.getContractFactory("ProductLib")).deploy();
        await library.waitForDeployment();
        factory = await (await ethers.getContractFactory("RegistryWorkflowFactoryMock", {
            libraries: { ProductLib: library.target }
        })).deploy(registry.target);
        await factory.waitForDeployment();
        terms = await resource(await factory.productTermsTemplateResourceType(), "application/xml", "<Terms/>");
        documentation = await resource(await factory.productDocumentationTemplateResourceType(),
            "application/xslt+xml", '<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"/>');
        for (const client of [alice, bob]) {
            await clients.registerClient({ client: client.address, lei: LEI, bic: BIC });
            await confirmReviewedClientData(clients, client, LEI, BIC);
        }
    });

    async function publish(name) {
        const definition = await registry.computeProductDefinitionId(name);
        await registry.publishProductDefinition({
            name,
            productDefinition: {
                productFactory: factory.target,
                productTermsTemplate: terms.target,
                productDocumentationTemplate: documentation.target
            }
        });
        return definition;
    }

    async function eventArgs(transaction, eventName) {
        const receipt = await transaction.wait();
        for (const log of receipt.logs) {
            if (log.address.toLowerCase() !== registry.target.toLowerCase()) continue;
            const event = registry.interface.parseLog(log);
            if (event?.name === eventName) return event.args;
        }
        throw new Error(`Missing registry event ${eventName}`);
    }

    async function request(client, definition) {
        const transaction = await registry.connect(client).createTradeRequest({
            productDefinitionId: definition, productPayload: "0x"
        });
        return (await eventArgs(transaction, "TradeRequested")).tradeRequestId;
    }

    async function activeDefinitionIds() {
        return (await registry.getProductDefinitionStates(0, 100))
            .filter(item => item.status === ACTIVE).map(item => item.productDefinitionId);
    }

    async function activeRequestIds(definition) {
        return (await registry.getActiveTradeRequests(definition)).map(item => item.tradeRequestId);
    }

    it("tracks active definitions through publication, suspension, reactivation and retirement", async function () {
        expect(await registry.productDefinitionCount()).to.equal(0n);
        expect(await registry.getProductDefinitionStates(0, 100)).to.deep.equal([]);
        const first = await publish("First demo");
        const second = await publish("Second demo");
        const firstPage = await registry.getProductDefinitionStates(0, 1);
        const secondPage = await registry.getProductDefinitionStates(1, 1);
        expect([...firstPage, ...secondPage].map(item => item.productDefinitionId))
            .to.deep.equal([first, second]);
        expect(await registry.getProductDefinitionStates(0, 0)).to.deep.equal([]);
        expect(await registry.getProductDefinitionStates(2, 100)).to.deep.equal([]);
        expect(await registry.getProductDefinitionStates(MaxUint256, MaxUint256)).to.deep.equal([]);
        expect((await registry.getProductDefinitionStates(1, MaxUint256))
            .map(item => item.productDefinitionId)).to.deep.equal([second]);
        expect(await registry.productDefinitionCount()).to.equal(2n);
        expect(await activeDefinitionIds()).to.have.members([first, second]);
        expect((await registry.getProductDefinition(first)).name).to.equal("First demo");
        expect((await registry.getProductDefinition(second)).name).to.equal("Second demo");

        await registry.setProductDefinitionStatus(first, SUSPENDED);
        expect(await activeDefinitionIds()).to.deep.equal([second]);
        await registry.setProductDefinitionStatus(first, ACTIVE);
        expect(await activeDefinitionIds()).to.have.members([first, second]);
        await registry.setProductDefinitionStatus(second, RETIRED);
        expect(await activeDefinitionIds()).to.deep.equal([first]);
        expect(await registry.getProductDefinitionStatus(second)).to.equal(RETIRED);
        expect((await registry.getProductDefinitionStates(0, 100)).map(item => item.status))
            .to.deep.equal([ACTIVE, RETIRED]);
    });

    it("retains known request states while withdrawn, rejected and expired requests cease to be active", async function () {
        const definition = await publish("Client requests");
        const aliceRequest = await request(alice, definition);
        const bobRequest = await request(bob, definition);
        expect(await activeRequestIds(definition)).to.have.members([aliceRequest, bobRequest]);
        const requests = await registry.getActiveTradeRequests(definition);
        expect(requests.map(item => item.request.client)).to.have.members([alice.address, bob.address]);
        expect(requests.every(item => item.request.status === ACTIVE)).to.equal(true);

        await expect(registry.connect(bob).withdrawTradeRequest(aliceRequest))
            .to.be.revertedWithCustomError(registry, "InvalidTradeRequestOwner");
        await registry.connect(alice).withdrawTradeRequest(aliceRequest);
        expect(await activeRequestIds(definition)).to.deep.equal([bobRequest]);
        await registry.rejectTradeRequest(bobRequest);
        expect(await activeRequestIds(definition)).to.deep.equal([]);
        expect((await registry.tradeRequestState(aliceRequest)).status).to.equal(3n);
        expect((await registry.tradeRequestState(bobRequest)).status).to.equal(4n);
        expect(await registry.productOf(aliceRequest)).to.equal(ZeroAddress);

        const expiring = await request(alice, definition);
        await registry.setProductDefinitionStatus(definition, RETIRED);
        expect(await activeRequestIds(definition)).to.deep.equal([]);
        expect((await registry.tradeRequestState(expiring)).status).to.equal(5n);
        await expect(registry.connect(alice).withdrawTradeRequest(expiring))
            .to.be.revertedWithCustomError(registry, "InvalidTradeRequestStatus").withArgs(expiring, 5n);
        await expect(registry.tradeRequestState(ZeroHash))
            .to.be.revertedWithCustomError(registry, "UnknownTradeRequest").withArgs(ZeroHash);
    });

    it("issues a real factory product, consumes matched requests and records its registration", async function () {
        const definition = await publish("Issued demo");
        const first = await request(alice, definition);
        const second = await request(bob, definition);
        expect(await registry.isRegisteredProduct(factory.target)).to.equal(false);
        expect(await registry.isRegisteredProduct(alice.address)).to.equal(false);
        expect(await registry.isRegisteredProduct(ZeroAddress)).to.equal(false);
        const params = { productDefinitionId: definition, productPayload: "0x" };
        const issued = await eventArgs(await registry.issueProductForRequests([first, second], params), "ProductIssued");
        const product = await ethers.getContractAt("ProductXmlNoteMock", issued.product);

        expect(await registry.productOf(first)).to.equal(product.target);
        expect(await registry.productOf(second)).to.equal(product.target);
        expect(await registry.isRegisteredProduct(product.target)).to.equal(true);
        expect(await factory.isFactoryDeployedProduct(product.target)).to.equal(true);
        expect(await product.productRegistry()).to.equal(registry.target);
        expect(await product.productFactory()).to.equal(factory.target);
        expect(await product.productProvider()).to.equal(owner.address);
        expect(await product.productDefinitionId()).to.equal(definition);
        expect(await product.productTermsTemplate()).to.equal(terms.target);
        expect(await product.stateXmlTemplate()).to.contain(await terms.web3Url());
        expect(await activeRequestIds(definition)).to.deep.equal([]);
        expect((await registry.tradeRequestState(first)).status).to.equal(2n);
        expect((await registry.tradeRequestState(second)).status).to.equal(2n);
        await expect(registry.issueProductForRequests([first], params))
            .to.be.revertedWithCustomError(registry, "InvalidTradeRequestStatus").withArgs(first, 2n);

        const directIssue = await eventArgs(await registry.issueProductWithoutRequests(params), "ProductIssued");
        expect(directIssue.product).not.to.equal(product.target);
        expect(await registry.isRegisteredProduct(directIssue.product)).to.equal(true);
        expect(await registry.isRegisteredProduct(product.target)).to.equal(true);
        expect(await registry.productOf(first)).to.equal(product.target);
    });

    it("caps definition discovery without truncating the final page", async function () {
        const pageSize = Number(await registry.MAX_DISCOVERY_PAGE_SIZE());
        const ids = [];
        for (let i = 0; i <= pageSize; i++) ids.push(await publish(`Paged definition ${i}`));
        expect((await registry.getProductDefinitionStates(0, MaxUint256))
            .map(item => item.productDefinitionId)).to.deep.equal(ids.slice(0, pageSize));
        expect((await registry.getProductDefinitionStates(pageSize, MaxUint256))
            .map(item => item.productDefinitionId)).to.deep.equal(ids.slice(pageSize));
    });
});
