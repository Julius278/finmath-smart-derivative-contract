// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBond} from "./IBond.sol";
import {PaymentFrequency, DayCountFraction, BusinessDayConvention, StubType} from "./BondTypes.sol";

/**
 * @title IFixedRateBond
 * @notice Extension of IBond for bonds paying a constant interest rate over
 *         their entire term.
 *
 * @dev Implementing contracts return InterestType.Fixed from interestType().
 *
 * @dev Interest payment dates are described by a recurring day and month rather
 *      than an explicit schedule, so that the schedule can be derived off-chain
 *      without storing an unbounded array. The first and last periods are
 *      exposed separately because they may be irregular.
 *
 * @author Raphael Prandtl
 */
interface IFixedRateBond is IBond {
    // ------------------------------ Scales ------------------------------ */

    /**
     * @notice Returns the number of decimal places of the interest rate.
     * @dev A scale of 4 means that 31000 represents an interest rate of 3.1000 per cent.
     */
    function rateScale() external view returns (uint8);

    // ------------------------------ Interest Terms ------------------------------ */

    /**
     * @notice Returns the fixed interest rate of the bond.
     * @dev Scaled by rateScale(), expressed as a percentage per annum.
     */
    function interestRate() external view returns (uint256);

    /// @notice Returns the date from which interest starts to accrue, as a Unix timestamp.
    function interestCommencementDate() external view returns (uint64);

    /// @notice Returns the frequency at which interest is paid.
    function interestPaymentFrequency() external view returns (PaymentFrequency);

    /// @notice Returns the convention used to compute the accrual factor of an interest period.
    function dayCountFraction() external view returns (DayCountFraction);

    /**
     * @notice Returns the convention applied when a payment date is not a business day.
     * @dev Evaluated against the calendar returned by businessDayCenter().
     */
    function businessDayConvention() external view returns (BusinessDayConvention);

    // ------------------------------ Payment Schedule ------------------------------ */

    /**
     * @notice Returns the recurring day of month on which interest is paid.
     * @dev Value between 1 and 31.
     */
    function payableDay() external view returns (uint8);

    /**
     * @notice Returns the recurring month in which interest is paid.
     * @dev Value between 1 and 12. For frequencies other than annual, this
     *      denotes the anchor month from which further payment dates are derived.
     */
    function payableMonth() external view returns (uint8);

    /// @notice Returns the date of the first interest payment, as a Unix timestamp.
    function firstPaymentDate() external view returns (uint64);

    /// @notice Returns whether the first interest period is regular, short or long.
    function firstPaymentStub() external view returns (StubType);

    /**
     * @notice Returns the amount of the first interest payment per calculation amount.
     * @dev Scaled by amountScale(). Returns 0 until the amount has been fixed.
     */
    function firstPaymentAmount() external view returns (uint256);

    /// @notice Returns the date of the final interest payment, as a Unix timestamp.
    function lastPaymentDate() external view returns (uint64);

    /**
     * @notice Returns the amount of the final interest payment per calculation amount.
     * @dev Scaled by amountScale(). Returns 0 until the amount has been fixed.
     */
    function lastPaymentAmount() external view returns (uint256);
}
