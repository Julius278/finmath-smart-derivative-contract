// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductFactory} from "../smartProductFramework/productFactories/AbstractProductFactory.sol";
import {ProductDeploymentParams} from "../smartProductFramework/productFactories/ProductDeploymentTypes.sol";
import {ProductXmlNoteMock} from "./ProductXmlMocks.sol";

/// @dev Minimal factory for exercising the retained registry with a real deployed product.
contract RegistryWorkflowFactoryMock is AbstractProductFactory {
    constructor(address registry) AbstractProductFactory(registry) {}

    function productPayloadSchema() external pure override returns (string memory) {
        return "test:registry-workflow:no-product-parameters";
    }

    function productTermsTemplateResourceType() external pure override returns (bytes32) {
        return keccak256("TEST:REGISTRY:TERMS");
    }

    function productDocumentationTemplateResourceType() external pure override returns (bytes32) {
        return keccak256("TEST:REGISTRY:DOCUMENTATION");
    }

    function isAcceptedIndicationCategory(bytes32) external pure override returns (bool) {
        return false;
    }

    function _deployProduct(ProductDeploymentParams calldata params) internal override returns (address) {
        return address(new ProductXmlNoteMock(params.common));
    }
}
