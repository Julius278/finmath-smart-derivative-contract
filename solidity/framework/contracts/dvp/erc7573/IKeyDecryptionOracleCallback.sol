// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

import {
    IKeyDecryptionOracleCallback as PublishedIKeyDecryptionOracleCallback
} from "@finmath.net/dvp/contracts/IKeyDecryptionOracleCallback.sol";

/**
 * @dev Compatibility artifact for the existing Maven/Web3j generation path.
 * The callback ABI is inherited entirely from the published ERC-7573 package.
 */
interface IKeyDecryptionOracleCallback is PublishedIKeyDecryptionOracleCallback {}
