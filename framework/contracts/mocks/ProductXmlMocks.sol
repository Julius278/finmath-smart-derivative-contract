// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "../smartProductFramework/products/AbstractProduct.sol";
import {CommonDeploymentParams} from "../smartProductFramework/productFactories/ProductDeploymentTypes.sol";

/// @dev Test products intentionally supply no XML implementation of their own.
contract ProductXmlNoteMock is AbstractProduct {
    constructor(CommonDeploymentParams memory common) AbstractProduct(common) {}

    function _productType() internal pure override returns (string memory name, string memory version) {
        return ("CouponNote", "7.3.0");
    }
}

contract ProductXmlFundMock is AbstractProduct {
    constructor(CommonDeploymentParams memory common) AbstractProduct(common) {}

    function _productType() internal pure override returns (string memory name, string memory version) {
        return ("Equity & \"Income\" <Fund>", "2.4&\"beta\"<1>");
    }
}
