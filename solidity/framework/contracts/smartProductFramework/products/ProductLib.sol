// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {CommonDeploymentParams} from "../productFactories/ProductDeploymentTypes.sol";
import {ITextResource} from "../../erc8100/ITextResource.sol";

/**
 * @title ProductLib
 * @notice Shared XML and trade-data string helpers for deployed products.
 * @dev The external entry points keep string processing out of product creation
 *      bytecode, which is also embedded in its factory. AbstractProduct fixes the
 *      envelope; products provide only their type name and type schema version.
 */
library ProductLib {
    using Strings for uint256;

    /// @dev Same selector as the product's InvalidTradeData error.
    error InvalidTradeData();

    /// @dev Same selectors as AbstractProduct; validation stays in the constructor's delegatecall.
    error ZeroAddress(string field);
    error ZeroHash(string field);

    function validateDeploymentContext(CommonDeploymentParams memory common) external pure {
        if (common.productRegistry == address(0)) {
            revert ZeroAddress("productRegistry");
        }
        if (common.productProvider == address(0)) {
            revert ZeroAddress("productProvider");
        }
        if (common.productDefinitionId == bytes32(0)) {
            revert ZeroHash("productDefinitionId");
        }
        if (common.productTermsTemplate == address(0)) {
            revert ZeroAddress("productTermsTemplate");
        }
        if (common.productDocumentationTemplate == address(0)) {
            revert ZeroAddress("productDocumentationTemplate");
        }

    }

    /**
     * @notice Builds the common SmartFinancialProduct XML envelope.
     * @dev ICMA BDT 2.1.0 and XSLT 1.0 are the current shared resource profile.
     *      These schema constants are not exposed by ITextResource. Media types,
     *      URLs and integrity hashes are read from the immutable resources.
     */
    function productStateXml(
        address termsTemplate,
        address documentationTemplate,
        string memory productType,
        string memory typeVersion
    ) external view returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<SmartFinancialProduct xmlns=\"urn:smart-product-framework:financial-product:1.0\"",
            " xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\"",
            " schemaVersion=\"1.0.0\"",
            " type=\"", LibString.escapeHTML(productType),
            "\" typeVersion=\"", LibString.escapeHTML(typeVersion), "\">",
            _deploymentStateXml(),
            "<ProductResources>",
            "<ProductTermsTemplate type=\"ICMABondDataTaxonomy\"",
            " version=\"2.1.0\"",
            " namespace=\"urn:icma:xsd:ICMABondDataTaxonomy\"",
            _mediaTypeAttribute(ITextResource(termsTemplate)), ">",
            _include(ITextResource(termsTemplate)),
            "</ProductTermsTemplate>",
            "<ProductDocumentationTemplate type=\"XSLT\"",
            " formatVersion=\"1.0\"",
            _mediaTypeAttribute(ITextResource(documentationTemplate)),
            _resourceReference(ITextResource(documentationTemplate)),
            "/></ProductResources>",
            "</SmartFinancialProduct>"
        );
    }

    /// @notice Renders the trade identifier as a checksum-free hex product address.
    function tradeId(address product) external pure returns (string memory) {
        return uint256(uint160(product)).toHexString(20);
    }

    /// @notice Identifies an ICMA BDT 2.1.0 document by chain, product and represented-state revision.
    /// @dev Runs in the product's context. Decimal integers and a lowercase,
    ///      zero-padded address make the identifier canonical; the full revision must be available.
    function documentId(uint256 version) external view returns (string memory) {
        return string.concat(
            "sbc:icma-bdt:2.1.0:", block.chainid.toString(), ":",
            uint256(uint160(address(this))).toHexString(20), ":", version.toString()
        );
    }

    /// @notice Parses a 0x-prefixed 32-byte trade-data hash.
    function parseHash(string memory s) external pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length != 66 || b[0] != "0" || b[1] != "x") revert InvalidTradeData();
        for (uint256 i = 0; i < 32; ) {
            result |= bytes32(
                uint256(_hexVal(b[2 + i * 2]) * 16 + _hexVal(b[3 + i * 2]))
                << (8 * (31 - i))
            );
            unchecked { ++i; }
        }
    }

    function _deploymentStateXml() private pure returns (string memory) {
        return string.concat(
            "<DeploymentState>",
            "<ProductRegistry evmstate:call=\"productRegistry()(address)\"/>",
            "<ProductFactory evmstate:call=\"productFactory()(address)\"/>",
            "<ProductProvider evmstate:call=\"productProvider()(address)\"/>",
            "<ProductDefinitionId evmstate:call=\"productDefinitionId()(bytes32)\"/>",
            "<ProductDefinitionVersion evmstate:call=\"productDefinitionVersion()(uint256)\"/>",
            "</DeploymentState>"
        );
    }

    function _mediaTypeAttribute(ITextResource resource) private view returns (string memory) {
        return string.concat(
            " mediaType=\"", LibString.escapeHTML(resource.mediaType()), "\""
        );
    }

    function _include(ITextResource resource) private view returns (string memory) {
        return string.concat(
            "<xi:include href=\"", LibString.escapeHTML(resource.web3Url()),
            "\" parse=\"xml\" evmstate:integrity=\"", _integrity(resource), "\"/>"
        );
    }

    function _resourceReference(ITextResource resource) private view returns (string memory) {
        return string.concat(
            " href=\"", LibString.escapeHTML(resource.web3Url()),
            "\" integrity=\"", _integrity(resource), "\""
        );
    }

    function _integrity(ITextResource resource) private view returns (string memory) {
        return string.concat("keccak256-", uint256(resource.contentHash()).toHexString(32));
    }

    function _hexVal(bytes1 c) private pure returns (uint8) {
        uint8 v = uint8(c);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 97 && v <= 102) return v - 87;
        if (v >= 65 && v <= 70) return v - 55;
        revert InvalidTradeData();
    }
}
