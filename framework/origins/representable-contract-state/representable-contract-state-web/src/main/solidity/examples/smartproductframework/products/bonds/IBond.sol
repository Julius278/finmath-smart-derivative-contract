// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IssuanceType, DeliveryType, DistributionMethod,
InterestType, RedemptionType, RedemptionBasis, FormOfNote, SafekeepingStructure,
Seniority, Subordination, Collateralization, DLTPlatform, TokenStandard} from "./BondTypes.sol";

/**
 * @title IBond
 * @notice Common interface for all bond products, independent of the interest
 *         mechanism. Type specific terms are exposed through extension
 *         interfaces.
 *
 * @dev VALUE SOURCES
 *      The values behind these getters originate from four distinct sources:
 *
 *      1. Implementation constants  - fixed per contract version, e.g. the DLT
 *                                     platform and token standard.
 *      2. Product definition        - identical for every issue of a product
 *                                     family, e.g. issuer, registrar, governing
 *                                     law, form of note.
 *      3. Deployment payload        - specific to a single issue, e.g. amounts,
 *                                     dates, issue price.
 *      4. Late binding              - assigned after deployment during the
 *                                     issuance process, e.g. ISIN, WKN or the
 *                                     asset token address.
 *
 *      Getters of category 4 return a zero value until the corresponding
 *      process phase has completed. This is documented per function.
 *
 * @dev SCALING
 *      Amounts and percentages are integers. The applicable number of decimal
 *      places is exposed through amountScale() and percentageScale(); consumers
 *      must not assume a fixed scale.
 *
 * @dev ENUM RENDERING
 *      Enum getters return the underlying uint8 when read through generic
 *      tooling. Human readable labels are resolved during term sheet rendering.
 *
 * @author Raphael Prandtl
 */
interface IBond {
    // ------------------------------ Scales ------------------------------ */

    /**
     * @notice Returns the number of decimal places of all nominal and money amounts.
     * @dev A scale of 2 means that 10000000 represents 100,000.00 currency units.
     *      Applies to aggregate amounts, denominations and calculation amount.
     */
    function amountScale() external view returns (uint8);

    /**
     * @notice Returns the number of decimal places of all percentage values.
     * @dev A scale of 4 means that 1000000 represents 100.0000 per cent.
     *      Applies to issue price and final redemption percentage.
     */
    function percentageScale() external view returns (uint8);

    // ------------------------------ Parties ------------------------------ */

    /// @notice Returns the legal name of the issuer.
    function issuerName() external view returns (string memory);

    /// @notice Returns the Legal Entity Identifier of the issuer.
    function issuerLei() external view returns (string memory);

    /**
     * @notice Returns the issuer ratings as published on the term sheet.
     * @dev Free form, semicolon separated, e.g. "MOODYS Aa1; SNPG AA; FITCH AAA".
     *      Not intended for on-chain evaluation.
     */
    function issuerRatings() external view returns (string memory);

    /// @notice Returns the legal name of the registrar maintaining the security register.
    function registrar() external view returns (string memory);

    /// @notice Returns the legal name of the settlement agent.
    function settlementAgent() external view returns (string memory);

    // ------------------------------ Issuance ------------------------------ */

    /// @notice Returns whether the bond is issued standalone or under a programme.
    function issuanceType() external view returns (IssuanceType);

    /// @notice Returns whether the bond is placed as a private placement.
    function privatePlacement() external view returns (bool);

    /**
     * @notice Returns the aggregate nominal amount at issuance.
     * @dev Scaled by amountScale(). Immutable over the life of the bond.
     */
    function initialAggregateAmount() external view returns (uint256);

    /**
     * @notice Returns the aggregate nominal amount currently outstanding.
     * @dev Scaled by amountScale(). Equals initialAggregateAmount() until a
     *      partial redemption or buyback occurs.
     */
    function outstandingAggregateAmount() external view returns (uint256);

    /**
     * @notice Returns the specified denomination in nominal terms.
     * @dev Scaled by amountScale(). Returns 0 if the issue instead uses a
     *      minimum denomination combined with integral multiples.
     */
    function specifiedDenomination() external view returns (uint256);

    /**
     * @notice Returns the smallest tradeable nominal amount.
     * @dev Scaled by amountScale(). Equals specifiedDenomination() where no
     *      integral multiples apply.
     */
    function minimumDenomination() external view returns (uint256);

    /**
     * @notice Returns the nominal increment above the minimum denomination.
     * @dev Scaled by amountScale(). Returns 0 where no integral multiples apply.
     */
    function integralMultiples() external view returns (uint256);

    /**
     * @notice Returns the nominal amount all interest and redemption figures relate to.
     * @dev Scaled by amountScale().
     */
    function calculationAmount() external view returns (uint256);

    /// @notice Returns the ISO 4217 currency code of the bond, e.g. "EUR".
    function specifiedCurrency() external view returns (bytes3);

    /**
     * @notice Returns the nominal amount represented by a single token unit.
     * @dev Scaled by amountScale(). Conversion factor between the nominal
     *      denomination of the bond and the security token supply.
     */
    function nominalPerToken() external view returns (uint256);

    // ------------------------------ Dates ------------------------------ */

    /// @notice Returns the date on which the terms were priced, as a Unix timestamp.
    function pricingDate() external view returns (uint64);

    /// @notice Returns the issue date of the bond, as a Unix timestamp.
    function issueDate() external view returns (uint64);

    /**
     * @notice Returns the exact execution time of the issue, as a Unix timestamp.
     * @dev Returns 0 until the trade has been executed.
     */
    function executionTime() external view returns (uint64);

    /// @notice Returns the settlement date of the issue, as a Unix timestamp.
    function settlementDate() external view returns (uint64);

    /**
     * @notice Returns the scheduled maturity date, as a Unix timestamp.
     * @dev Contractual end of the term. The date on which the redemption amount
     *      is actually paid is exposed through finalRedemptionDate().
     */
    function maturityDate() external view returns (uint64);

    // ------------------------------ Pricing and Distribution ------------------------------ */

    /**
     * @notice Returns the issue price as a percentage of the nominal amount.
     * @dev Scaled by percentageScale().
     */
    function issuePrice() external view returns (uint256);

    /// @notice Returns the delivery mechanism applied at settlement.
    function delivery() external view returns (DeliveryType);

    /// @notice Returns whether the bond is admitted to trading on a regulated market.
    function listed() external view returns (bool);

    /// @notice Returns the distribution channel used to place the issue.
    function methodOfDistribution() external view returns (DistributionMethod);

    // ------------------------------ Redemption ------------------------------ */

    /// @notice Returns the redemption mechanism of the bond.
    function redemptionType() external view returns (RedemptionType);

    /**
     * @notice Returns the final redemption amount as a percentage of the nominal amount.
     * @dev Scaled by percentageScale(). Equals 100 per cent for par redemption.
     */
    function finalRedemptionPercentage() external view returns (uint256);

    /**
     * @notice Returns the date on which the redemption amount is paid, as a Unix timestamp.
     * @dev May differ from maturityDate() where a business day convention applies.
     */
    function finalRedemptionDate() external view returns (uint64);

    /// @notice Returns the basis on which the redemption amount is determined.
    function redemptionPaymentBasis() external view returns (RedemptionBasis);

    // ------------------------------ Security Identifiers ------------------------------ */

    /// @notice Returns the ISIN of the bond.
    function isin() external view returns (string memory);

    /// @notice Returns the WKN of the bond.
    function wkn() external view returns (string memory);

    // ------------------------------ Legal and Structural ------------------------------ */

    /// @notice Returns the form in which the notes are issued.
    function formOfNote() external view returns (FormOfNote);

    /// @notice Returns the safekeeping arrangement applied to the notes.
    function safekeepingStructure() external view returns (SafekeepingStructure);

    /// @notice Returns the ranking of the notes in the issuer's capital structure.
    function seniority() external view returns (Seniority);

    /// @notice Returns the subordination status of the notes.
    function subordination() external view returns (Subordination);

    /// @notice Returns the collateralization status of the notes.
    function collateralization() external view returns (Collateralization);

    /// @notice Returns the ISO 3166-1 alpha-2 country code of the governing law, e.g. "DE".
    function governingLaw() external view returns (bytes2);

    /**
     * @notice Returns the settlement system calendar used for business day adjustment.
     * @dev Free form calendar code, e.g. "TARGET2". Applies to interest and
     *      redemption payments alike and is therefore not interest type specific.
     */
    function businessDayCenter() external view returns (string memory);

    /// @notice Returns whether the bond is eligible as central bank collateral.
    function centralBankEligible() external view returns (bool);

    /// @notice Returns whether the instrument itself is unrated.
    function unrated() external view returns (bool);

    // ------------------------------ DLT ------------------------------ */

    /// @notice Returns the distributed ledger the security token is issued on.
    function dltPlatform() external view returns (DLTPlatform);

    /// @notice Returns the token standard implemented by the security token.
    function tokenStandard() external view returns (TokenStandard);

    /// @notice Returns the address of the security token representing the bond.
    function assetToken() external view returns (address);

    /// @notice Returns whether the bond is issued as a DLT based security.
    function dltBondIndicator() external view returns (bool);

    /// @notice Block at which the issuance terms became final.
    uint64 public issuanceBlock;


    // ------------------------------ Interest Discriminator ------------------------------ */

    /**
     * @notice Returns the interest mechanism of the bond.
     * @dev Determines which extension interface, if any, the contract implements.
     *      Consumers should confirm support via ERC-165 rather than relying on
     *      this value alone.
     */
    function interestType() external view returns (InterestType);
}
