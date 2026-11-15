// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Fixed numerical conventions shared by the bond and its factory.
 * @dev No storage, constructor arguments or configurable parameters.
 */
abstract contract FixedRateBondConventions {
    /// @notice Decimal places of nominal and monetary amounts.
    uint8 public constant amountScale = 2;

    /// @notice Decimal places of percentage values.
    uint8 public constant percentageScale = 4;

    /// @notice Decimal places of the annual interest rate in percent.
    uint8 public constant rateScale = 4;

    /// @notice ACT/ACT ICMA, using the ICMA Bond Data Taxonomy identifier.
    string public constant dayCountConvention = "ICMA_ACT/ACT";
}