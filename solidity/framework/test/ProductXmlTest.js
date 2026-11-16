import hre from "hardhat";
import { expect } from "chai";
import { ZeroHash, keccak256, toUtf8Bytes } from "ethers";

describe("AbstractProduct common XML envelope", function () {
    let ethers, deployer, registry, provider;
    let library, terms, documentation, note, fund;

    const TERMS_TYPE = keccak256(toUtf8Bytes("example:custom-product-terms:7.3"));
    const DOCUMENTATION_TYPE = keccak256(toUtf8Bytes("example:custom-product-documentation:2.4"));
    const TERMS = '<Document xmlns="urn:icma:xsd:ICMABondDataTaxonomy"><ICMABondDataTaxonomy>'
        + '<DocumentInformation><BDTVersion>2.1.0</BDTVersion></DocumentInformation>'
        + '</ICMABondDataTaxonomy></Document>';
    const DOCUMENTATION = '<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"/>';
    const TERMS_MEDIA_TYPE = 'application/xml; profile="urn:example:terms&7.3"';
    const DOCUMENTATION_MEDIA_TYPE = 'application/xslt+xml; profile="urn:example:docs&2.4"';
    const TYPE_ATTRIBUTES_NOTE = 'type="CouponNote" typeVersion="7.3.0"';
    const TYPE_ATTRIBUTES_FUND = 'type="Equity &amp; &quot;Income&quot; &lt;Fund&gt;" typeVersion="2.4&amp;&quot;beta&quot;&lt;1&gt;"';
    const TERMS_PROFILE = 'type="ICMABondDataTaxonomy" version="2.1.0" namespace="urn:icma:xsd:ICMABondDataTaxonomy"';
    const DOCUMENTATION_PROFILE = 'type="XSLT" formatVersion="1.0"';

    async function deployResource(type, mediaType, content) {
        const bytes = toUtf8Bytes(content);
        const resource = await (await ethers.getContractFactory("TextResource")).deploy(
            deployer.address, type, mediaType, bytes, bytes.length ? keccak256(bytes) : ZeroHash
        );
        await resource.waitForDeployment();
        return resource;
    }

    async function deployProduct(name, termsAddress = terms.target) {
        const Product = await ethers.getContractFactory(name, {
            libraries: { ProductLib: library.target }
        });
        const product = await Product.deploy({
            productRegistry: registry.address,
            productProvider: provider.address,
            productDefinitionId: keccak256(toUtf8Bytes("example:definition")),
            productDefinitionVersion: 42,
            productTermsTemplate: termsAddress,
            productDocumentationTemplate: documentation.target
        });
        await product.waitForDeployment();
        return product;
    }

    beforeEach(async function () {
        ({ ethers } = await hre.network.create());
        [deployer, registry, provider] = await ethers.getSigners();
        library = await (await ethers.getContractFactory("ProductLib")).deploy();
        await library.waitForDeployment();
        terms = await deployResource(TERMS_TYPE, TERMS_MEDIA_TYPE, TERMS);
        documentation = await deployResource(DOCUMENTATION_TYPE, DOCUMENTATION_MEDIA_TYPE, DOCUMENTATION);
        note = await deployProduct("ProductXmlNoteMock");
        fund = await deployProduct("ProductXmlFundMock");
    });

    it("uses the same inherited envelope for two product types without conflating schema and definition versions", async function () {
        const noteXml = await note.stateXmlTemplate();
        const fundXml = await fund.stateXmlTemplate();
        const prefix = '<?xml version="1.0" encoding="UTF-8"?><SmartFinancialProduct '
            + 'xmlns="urn:smart-product-framework:financial-product:1.0" '
            + 'xmlns:xi="http://www.w3.org/2001/XInclude" xmlns:evmstate="urn:evm:state:1.0" schemaVersion="1.0.0" ';

        expect(noteXml).to.contain(prefix + TYPE_ATTRIBUTES_NOTE + ">");
        expect(fundXml).to.contain(prefix + TYPE_ATTRIBUTES_FUND + ">");
        expect(noteXml.replace(TYPE_ATTRIBUTES_NOTE, "TYPE")).to.equal(fundXml.replace(TYPE_ATTRIBUTES_FUND, "TYPE"));
        expect(noteXml).to.match(/<\/ProductResources><\/SmartFinancialProduct>$/);
        for (const product of [note, fund]) {
            expect(await product.productFactory()).to.equal(deployer.address);
            expect(await product.productRegistry()).to.equal(registry.address);
            expect(await product.productProvider()).to.equal(provider.address);
            expect(await product.productDefinitionVersion()).to.equal(42n);
        }
        for (const getter of ["productRegistry()(address)", "productFactory()(address)",
            "productProvider()(address)", "productDefinitionId()(bytes32)", "productDefinitionVersion()(uint256)"]) {
            expect(noteXml).to.contain(`evmstate:call="${getter}"`);
        }
        expect(noteXml).not.to.contain('typeVersion="42"');
        for (const xml of [noteXml, fundXml]) {
            expect(xml).to.contain(`<ProductTermsTemplate ${TERMS_PROFILE} `);
            expect(xml).to.contain(`<ProductDocumentationTemplate ${DOCUMENTATION_PROFILE} `);
        }
    });

    it("combines fixed profile metadata with actual media types, URLs and integrity hashes", async function () {
        const xml = await note.stateXmlTemplate();
        expect(await terms.resourceType()).to.equal(TERMS_TYPE);
        expect(await documentation.resourceType()).to.equal(DOCUMENTATION_TYPE);
        expect(await terms.mediaType()).to.equal(TERMS_MEDIA_TYPE);
        expect(await documentation.mediaType()).to.equal(DOCUMENTATION_MEDIA_TYPE);
        expect(xml).to.contain(`<ProductTermsTemplate ${TERMS_PROFILE} `
            + 'mediaType="application/xml; profile=&quot;urn:example:terms&amp;7.3&quot;">');
        expect(xml).to.contain(`<xi:include href="${await terms.web3Url()}" parse="xml" `
            + `evmstate:integrity="keccak256-${keccak256(toUtf8Bytes(TERMS))}"/>`);
        expect(xml).to.contain(`<ProductDocumentationTemplate ${DOCUMENTATION_PROFILE} `
            + 'mediaType="application/xslt+xml; profile=&quot;urn:example:docs&amp;2.4&quot;" '
            + `href="${await documentation.web3Url()}" integrity="keccak256-${keccak256(toUtf8Bytes(DOCUMENTATION))}"/>`);
        expect(xml).not.to.contain("<Document xmlns=");
        expect(xml).not.to.contain("<xsl:stylesheet");
        // The opaque on-chain resource type remains queryable, but is not an XML profile attribute.
        expect(xml).not.to.match(/resourceType=|resourceVersion=|resourceSchemaVersion=/);
    });

    it("escapes quotes, ampersands and angle brackets in product type and version attributes", async function () {
        const xml = await fund.stateXmlTemplate();
        expect(xml).to.contain(TYPE_ATTRIBUTES_FUND);
        expect(xml).not.to.contain('type="Equity & "Income" <Fund>"');
        expect(xml).not.to.contain('typeVersion="2.4&"beta"<1>"');
        expect(xml).not.to.contain('profile="urn:example:terms&7.3"');
    });

    it("does not emit an apparently usable include before its text resource is finalized", async function () {
        const termsBytes = toUtf8Bytes(TERMS);
        const pending = await (await ethers.getContractFactory("TextResource")).deploy(
            deployer.address, TERMS_TYPE, "application/xml", "0x", keccak256(termsBytes)
        );
        await pending.waitForDeployment();
        const product = await deployProduct("ProductXmlNoteMock", pending.target);
        expect(await pending.isFinalized()).to.equal(false);
        expect(await pending.committedContentHash()).to.equal(keccak256(termsBytes));
        expect(await pending.currentContentHash()).to.equal(keccak256("0x"));
        await expect(product.stateXmlTemplate()).to.be.revertedWithCustomError(pending, "NotFinalized");

        const first = toUtf8Bytes(TERMS.slice(0, 40));
        const rest = toUtf8Bytes(TERMS.slice(40));
        await pending.appendChunkAt(0, first);
        expect(await pending.currentContentHash()).to.equal(keccak256(first));
        await expect(pending.appendChunkAt(0, first))
            .to.be.revertedWithCustomError(pending, "UnexpectedContentLength")
            .withArgs(0, first.length);
        await pending.appendChunkAt(first.length, rest);
        await expect(pending.finalize(keccak256(toUtf8Bytes("different"))))
            .to.be.revertedWithCustomError(pending, "ContentHashCommitmentMismatch");
        await pending.finalize(keccak256(termsBytes));
        expect(await pending.currentContentHash()).to.equal(await pending.contentHash());
        expect(await product.stateXmlTemplate()).to.contain(`evmstate:integrity="keccak256-${await pending.contentHash()}"`);
    });
});
