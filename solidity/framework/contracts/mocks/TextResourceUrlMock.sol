// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TextResource} from "../erc8100/TextResource.sol";

/// @dev Finalized resource with a constructor-fixed URL for XML attribute-escaping tests.
contract TextResourceUrlMock is TextResource {
    string private _url;

    constructor(address owner_, bytes32 resourceType_, string memory url_)
        TextResource(owner_, resourceType_, "application/xml", bytes("<Terms/>"), keccak256(bytes("<Terms/>")))
    {
        _url = url_;
    }

    function web3Url() external view override returns (string memory) {
        return _url;
    }
}
