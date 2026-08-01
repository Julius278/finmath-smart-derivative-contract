// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductFactory} from "../ProductFactory/AbstractProductFactory.sol";
import {ProductDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";
import {IProductIndication} from "../ProductIndication/IProductIndication.sol";
import {SimpleBond} from "./SimpleBond.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title SimpleBondFactory
 * @notice Product-specific factory that deploys SimpleBond products.
 * @dev Caller restriction (onlyGenericFactory) and schema validation are
 *      handled by AbstractProductFactory.sol.sol; this contract only decodes
 *      the payload, validates the economics, and constructs the bond.
 *
 * @author Raphael Prandtl
 */
contract SimpleBondFactory is AbstractProductFactory {
    using ERC165Checker for address;

    // ------------------------------ Constants ------------------------------ */

    /// @notice Human-readable schema of the expected productSpecificPayload.
    string internal constant PRODUCT_SPECIFIC_PAYLOAD_SCHEMA = "v1:SimpleBondDeploymentPayload(uint256 notional,uint256 maturity)";

    /// @dev resourceType() a text resource must declare to back the product terms template slot of a bond product.
    bytes32 internal constant PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE = keccak256("SPF:SIMPLE_BOND:PRODUCT_TERMS_TEMPLATE:V1");

    /// @dev resourceType() a text resource must declare to back the product documentation template slot of a bond product.
    bytes32 internal constant PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE = keccak256("SPF:SIMPLE_BOND:PRODUCT_DOCUMENTATION_TEMPLATE:V1");


    bytes32 public immutable acceptedIndicationCategory;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Address has no contract code.
    error InvalidIndicationContract(address indicationContract);

    /// @notice Resource does not implement the expected interface.
    error InvalidInterface(address contractAddress);

    /// @notice Call to a contract failed
    error ContractCallFailed(address contractAddress, string functionName);

    error InvalidIndicationCategory(address indicationContract);

    // ------------------------------ Constructor ------------------------------ */

    /// @param productRegistry_ The product registry that will invoke this factory.
    constructor(address productRegistry_, address curveIndications_) AbstractProductFactory(productRegistry_) {
        if (curveIndications_ == address(0) || curveIndications_.code.length == 0) {
            revert InvalidIndicationContract(curveIndications_);
        }
        // Must advertise IProductIndication via ERC-165
        if (!curveIndications_.supportsInterface(type(IProductIndication).interfaceId)) {
            revert InvalidIndicationContract(curveIndications_);
        }
        IProductIndication indication = IProductIndication(curveIndications_);
        try indication.indicationCategory() returns (bytes32 indicationCategory) {
            if (indicationCategory == bytes32(0)) revert InvalidIndicationCategory(curveIndications_);
            acceptedIndicationCategory = indicationCategory;
        } catch {
            revert ContractCallFailed(curveIndications_, "indicationCategory()");
        }
    }

    // ------------------------------ Product Specification ------------------------------ */

    function productPayloadSchema() external pure override returns (string memory) {
        return PRODUCT_SPECIFIC_PAYLOAD_SCHEMA;
    }

    function productTermsTemplateResourceType() external pure override returns (bytes32) {
        return PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE;
    }

    function productDocumentationTemplateResourceType() external pure override returns (bytes32) {
        return PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE;
    }

    // ------------------------------ Product Indication ------------------------------ */

    function isAcceptedIndicationCategory(bytes32 indicationCategory) external view override returns (bool) {
        return acceptedIndicationCategory == indicationCategory;
    }

    // ------------------------------ Product-Specific Deploy ------------------------------ */

    function _deployProduct(ProductDeploymentParams calldata params) internal override returns (address product) {
        product = address(new SimpleBond(params.common, params.productPayload));
    }

}
