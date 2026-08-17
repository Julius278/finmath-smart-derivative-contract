// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BondTypes
 * @notice Shared enumerations for bond products.
 *
 * @dev All enumerations use a `Unknown`-free layout: slot 0 always carries a
 *      meaningful default so that an unset storage value is never silently
 *      interpreted as valid. Where no sensible default exists, validation in
 *      the implementing contract must reject slot 0 explicitly.
 *
 * @dev Values originate from closed code lists used in bond term sheets. They
 *      are modelled as enums rather than strings to keep them type safe,
 *      comparable on-chain and cheap to store. Human readable labels are
 *      resolved during XML/XSLT rendering, not in the contract.
 *
 * @author Raphael Prandtl
 */

// ------------------------------ Issuance ------------------------------ */

/// @notice Whether the bond is issued standalone or under a debt issuance programme.
    enum IssuanceType {
        Standalone,
        Programme
    }

/// @notice Settlement mechanism applied at issuance.
    enum DeliveryType {
        /// @dev Delivery versus payment.
        DVP,
        /// @dev Free of payment.
        FOP
    }

/// @notice Distribution channel used to place the issue.
    enum DistributionMethod {
        Syndicated,
        NonSyndicated
    }

// ------------------------------ Interest ------------------------------ */

/// @notice Interest mechanism of the bond; acts as discriminator for extension interfaces.
    enum InterestType {
        /// @dev No periodic interest; typically issued at a discount.
        ZeroCoupon,
        /// @dev Constant rate over the life of the bond.
        Fixed,
        /// @dev Rate derived from a reference rate plus spread.
        Floating,
        /// @dev Any payoff not covered by the above.
        Structured
    }

/// @notice Frequency of periodic interest payments.
    enum PaymentFrequency {
        /// @dev No periodic payment; used for zero coupon instruments.
        None,
        Annually,
        SemiAnnually,
        Quarterly,
        Monthly
    }

/// @notice Convention used to compute the accrual factor of an interest period.
    enum DayCountFraction {
        ACT_360,
        ACT_365_FIXED,
        ACT_ACT_ICMA,
        ACT_ACT_ISDA,
        THIRTY_360,
        THIRTY_E_360
    }

/// @notice Settlement system calendar used for business day adjustment.
    enum BusinessDayCenter {
        TARGET2,
        LONDON,
        NEW_YORK,
        FRANKFURT
    }

/// @notice Convention used to shift a payment date falling on a non-business day.
    enum BusinessDayConvention {
        Unadjusted,
        Following,
        ModifiedFollowing,
        Preceding,
        ModifiedPreceding
    }

/// @notice Length of an irregular first or last interest period.
    enum StubType {
        /// @dev Regular period, no stub.
        None,
        /// @dev Period shorter than a regular interest period.
        Short,
        /// @dev Period longer than a regular interest period.
        Long
    }

// ------------------------------ Redemption ------------------------------ */

/// @notice Redemption mechanism of the bond.
    enum RedemptionType {
        /// @dev Single redemption at maturity.
        Maturity,
        /// @dev Redeemable early at the issuer's option.
        Callable,
        /// @dev Redeemable early at the holder's option.
        Puttable,
        /// @dev Redeemed in instalments over the life of the bond.
        Amortising
    }

/// @notice Basis on which the redemption amount is determined.
    enum RedemptionBasis {
        /// @dev Redemption at nominal value.
        Par,
        /// @dev Redemption above nominal value.
        Premium,
        /// @dev Redemption below nominal value.
        Discount
    }

// ------------------------------ Security ------------------------------ */

/// @notice Physical or dematerialised form in which the notes are issued.
    enum FormOfNote {
        DematerialisedBearer,
        DematerialisedRegistered,
        GlobalBearer,
        GlobalRegistered
    }

/// @notice Safekeeping arrangement applied to the notes.
    enum SafekeepingStructure {
        /// @dev New safekeeping structure, electronic form.
        NewSafekeepingStructureElectronic,
        /// @dev New safekeeping structure, physical global note.
        NewSafekeepingStructure,
        /// @dev Classical global note.
        ClassicalGlobalNote,
        /// @dev New global note.
        NewGlobalNote
    }

/// @notice Ranking of the notes in the issuer's capital structure.
    enum Seniority {
        Senior,
        SeniorPreferred,
        SeniorNonPreferred,
        Junior
    }

/// @notice Subordination status of the notes.
    enum Subordination {
        Unsubordinated,
        Subordinated
    }

/// @notice Collateralization status of the notes.
    enum Collateralization {
        Unsecured,
        Secured
    }

// ------------------------------ DLT ------------------------------ */

/// @notice Distributed ledger the security token is issued on.
    enum DLTPlatform {
        Ethereum,
        Polygon,
        Other
    }

/// @notice Token standard implemented by the security token.
    enum TokenStandard {
        ERC20,
        ERC1400,
        ERC3643,
        Other
    }
