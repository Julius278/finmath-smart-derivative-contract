// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductFactory} from "../ProductFactory/AbstractProductFactory.sol";
import {ProductDeploymentParams} from "../ProductFactory/ProductDeploymentTypes.sol";
import {IProductIndication} from "../ProductIndication/IProductIndication.sol";
import {SimpleBond} from "./SimpleBond.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title SimpleBondFactory
 * @notice Factory defining and deploying the SimpleBond product specification.
 *
 * @dev Defines the product payload schema, required resource types, and
 *      accepted indication category. Product deployment is restricted by
 *      AbstractProductFactory.
 *
 * @author Raphael Prandtl
 */
contract SimpleBondFactory is AbstractProductFactory {
    using ERC165Checker for address;

    // ------------------------------ Constants ------------------------------ */

    /// @notice Human-readable schema of the expected product payload.
    string internal constant PRODUCT_PAYLOAD_SCHEMA = "v1:SimpleBondDeploymentPayload(uint256 notional,uint256 maturity)";

    /// @notice Required resource type of the product terms template.
    bytes32 internal constant PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE = keccak256("SPF:SIMPLE_BOND:PRODUCT_TERMS_TEMPLATE:V1");

    /// @notice Required resource type of the product documentation template.
    bytes32 internal constant PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE = keccak256("SPF:SIMPLE_BOND:PRODUCT_DOCUMENTATION_TEMPLATE:V1");

    // ------------------------------ Immutable State ------------------------------ */

    /// @notice Indication category accepted by this factory.
    bytes32 public immutable acceptedIndicationCategory;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when the supplied indication contract is invalid.
    error InvalidIndicationContract(address indicationContract);

    /// @notice Thrown when a call to the indication contract fails.
    error ContractCallFailed(address contractAddress, string functionName);

    /// @notice Thrown when the indication contract exposes a zero category.
    error InvalidIndicationCategory(address indicationContract);

    // ------------------------------ Constructor ------------------------------ */

    /**
     * @param productRegistry_  Product registry authorized to use this factory.
     * @param curveIndications_ Curve indication contract defining the accepted category.
     */
    constructor(address productRegistry_, address curveIndications_) AbstractProductFactory(productRegistry_) {
        if (curveIndications_ == address(0) || curveIndications_.code.length == 0 || !curveIndications_.supportsInterface(type(IProductIndication).interfaceId)) {
            revert InvalidIndicationContract(curveIndications_);
        }

        try IProductIndication(curveIndications_).indicationCategory() returns (bytes32 indicationCategory) {
            if (indicationCategory == bytes32(0)) {
                revert InvalidIndicationCategory(curveIndications_);
            }
            acceptedIndicationCategory = indicationCategory;
        } catch {
            revert ContractCallFailed(curveIndications_, "indicationCategory()");
        }
    }

    // ------------------------------ Product Specification ------------------------------ */

    /// @inheritdoc AbstractProductFactory
    function productPayloadSchema() external pure override returns (string memory) {
        return PRODUCT_PAYLOAD_SCHEMA;
    }

    /// @inheritdoc AbstractProductFactory
    function productTermsTemplateResourceType() external pure override returns (bytes32) {
        return PRODUCT_TERMS_TEMPLATE_RESOURCE_TYPE;
    }

    /// @inheritdoc AbstractProductFactory
    function productDocumentationTemplateResourceType() external pure override returns (bytes32) {
        return PRODUCT_DOCUMENTATION_TEMPLATE_RESOURCE_TYPE;
    }

    // ------------------------------ Product Indication ------------------------------ */

    /// @inheritdoc AbstractProductFactory
    function isAcceptedIndicationCategory(bytes32 indicationCategory) external view override returns (bool) {
        return indicationCategory == acceptedIndicationCategory;
    }

    // ------------------------------ Product Deployment ------------------------------ */

    /// @inheritdoc AbstractProductFactory
    function _deployProduct(ProductDeploymentParams calldata params) internal override returns (address product) {
        product = address(new SimpleBond(params.common, params.productPayload));
    }
}
