// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonDeploymentParams} from "../../smartProductFramework/productFactories/ProductDeploymentTypes.sol";
import {BondSettlementModules} from "./BondSettlementModules.sol";
import {IProductDefinitionRegistry} from "../../smartProductFramework/productDefinitionRegistry/IProductDefinitionRegistry.sol";
import {ITextResource} from "../../erc8100/ITextResource.sol";
import {IDecryptionContractWithKeyGeneration} from "@finmath.net/dvp/contracts/IDecryptionContractWithKeyGeneration.sol";
import {IDecryptionContractInceptionCallback} from "@finmath.net/dvp/contracts/IDecryptionContractInceptionCallback.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DateTimeLib} from "solady/src/utils/DateTimeLib.sol";

/**
 * @notice A single coupon period.
 * @dev Unadjusted accrual/reference dates and Following payment date, all at UTC midnight.
 *      All four values pack into one storage slot. Only the first period may be short.
 */
struct CouponPeriod {
    uint64 startDate;
    uint64 endDate;
    uint64 paymentDate;
    uint64 referenceStartDate;
}

/// @notice One scheduled payment per specified denomination, in minor currency units.
struct CouponPayment {
    uint64 paymentDate;
    uint256 amount;
}

/// @notice Settlement state of one contractual coupon claim.
enum CouponPaymentStatus {
    None,
    Pending,
    Paid,
    Failed
}

/// @dev Bond-side evidence for one coupon-payment attempt.
struct CouponSettlement {
    CouponPaymentStatus status;
    uint256 amount;
    bytes32 contextHash;
    bytes32 executionHash;
    bytes32 cancellationHash;
}

/// @dev Static terms and routing data for one coupon-payment inception.
struct CouponPaymentInception {
    /// @dev Nominal basis for calculating and rounding one unit's coupon.
    uint256 calculationAmount;
    /// @dev Units entitled to this payment; kept separate for future allocation across payees.
    uint256 unitCount;
    uint256 rate;
    uint8 frequency;
    uint8 scale;
    address expectedGenerationOracle;
    address paymentContract;
    address payer;
    address payee;
}

/// @dev Read-only participant infrastructure, implemented by the selected payment module.
interface IPaymentOracleConfiguration {
    function oracleOf(address participant) external view returns (address);
}

/// @dev Optional extension; older payment modules remain usable without reusable XML witnesses.
interface IVersionedPaymentOracleConfiguration {
    function oracleConfigurationVersion() external view returns (uint256);
}

/// @dev Read through the bond ABI to keep its factory-embedded wrapper small.
interface IVersionedBondRepresentation {
    function productTermsTemplate() external view returns (address);
    function productDocumentationTemplate() external view returns (address);
    function paymentContract() external view returns (address);
    function initialAggregateAmount() external view returns (uint256);
    function issuePrice() external view returns (uint256);
    function finalRedemptionPercentage() external view returns (uint256);
    function percentageScale() external view returns (uint8);
}

/// @notice The fixed-size terms of the deployment payload, encoded inline in the ABI.
struct FixedRateBondTerms {
    address buyer;
    uint256 initialAggregateAmount;
    uint256 specifiedDenomination;
    uint64 maturityDate;
    uint256 issuePrice;
    uint256 finalRedemptionPercentage;
    uint256 interestRate;
    uint8 couponsPerYear;
    uint64 pricingDate;
    uint64 issueDate;
    uint64 settlementDate;
}

/// @notice Same flat v6 wire encoding: eleven static terms followed by the coupon-array offset.
struct FixedRateBondDeploymentPayload {
    FixedRateBondTerms terms;
    CouponPeriod[] couponPeriods;
}

/**
 * @title FixedRateBondLib
 * @notice Payload validation, initialization and shared economics of the fixed rate bond.
 *
 * @dev The external entry point keeps the validation out of the bond's creation bytecode, which
 *      is embedded in FixedRateBondFactory and therefore competes for the factory's EIP-170
 *      budget. Validation runs exactly once, in the constructor, so moving it behind a
 *      delegatecall costs a single call at deployment. Pure/read-only helpers share the same library.
 *
 *      The payload is passed as raw bytes rather than as a decoded struct on purpose: encoding a
 *      struct with a dynamic array for the delegatecall would add an ABI encoder to the bond and
 *      give back most of what this saves. The library validates and stores the schedule once,
 *      returning only static terms for assignment by the constructor.
 *
 *      The errors are redeclared with the signatures used by the bond, so the data bubbling up
 *      through the delegatecall carries the selectors the bond's own ABI documents.
 */
library FixedRateBondLib {
    error UnsupportedStateVersion();

    /// @notice Revision of stored bond state and its versioned payment-oracle configuration.
    /// @dev Both resource addresses are immutable. Finalized TextResources using the supported
    ///      versioned XML getter profile are configurable independently of this implementation.
    ///      No template bytes or content hash are embedded in the contract. External counters
    ///      remain included after confirmation so the aggregate can never decrease.
    ///      Live token diagnostics (assetLockStatus) are outside that profile; consumers must
    ///      not use this witness for such bindings. The backend rejects those tuple bindings.
    ///      Unversioned dependencies make the witness unavailable rather than risk stale reuse.
    function representedStateVersion(uint256 localVersion) external view returns (uint256) {
        IVersionedBondRepresentation bond = IVersionedBondRepresentation(address(this));
        if (!ITextResource(bond.productTermsTemplate()).isFinalized()
            || !ITextResource(bond.productDocumentationTemplate()).isFinalized()) {
            revert UnsupportedStateVersion();
        }
        return localVersion
            + IVersionedPaymentOracleConfiguration(bond.paymentContract()).oracleConfigurationVersion();
    }

    /// @dev Flips the top bit of the bond-derived ERC-7573 id, separating coupon claims from
    ///      issuance and redemption while retaining the coupon index in the low 96 bits.
    uint256 private constant COUPON_ID_DOMAIN = uint256(1) << 255;

    /// @notice Payload ABI identity shared by the factory and deploying integrations.
    function productPayloadSchema() external pure returns (string memory) {
        return "v6:FixedRateBondDeploymentPayload(address buyer,uint256 initialAggregateAmount,uint256 specifiedDenomination,uint64 maturityDate,uint256 issuePrice,uint256 finalRedemptionPercentage,uint256 interestRate,uint8 couponsPerYear,uint64 pricingDate,uint64 issueDate,uint64 settlementDate,(uint64,uint64,uint64,uint64)[] couponPeriods)";
    }

    error ZeroAddress(string field);
    error InvalidSettlementContract(address target);
    error InvalidCounterparty(address party);

    /// @dev Same selector as the bond's InvalidAmount error.
    error InvalidAmount();
    error InvalidIssuanceDates();
    error CouponNotDue(uint256 index, uint256 paymentDate);
    error CouponAlreadyRequested(uint256 index);
    error UnexpectedPaymentOracle(address expected, address actual);
    error InvalidTransferContext();
    error InvalidKeyMaterial();
    error InvalidKey();
    error InvalidCouponPaymentState(uint256 index, CouponPaymentStatus status);

    event TokenLocked(uint256 indexed id);
    event TokenClaimed(uint256 id, bytes key);
    event TokenReclaimed(uint256 id, bytes key);
    event CouponPaymentRequested(uint256 indexed index, bytes32 indexed requestId, uint256 amount, address indexed payee);
    event CouponPaid(uint256 indexed index, bytes32 indexed requestId);
    event CouponPaymentFailed(uint256 indexed index, bytes32 indexed requestId);

    /// @dev Same selector as the bond's InvalidCouponPeriod error.
    error InvalidCouponPeriod(uint256 index);

    /// @dev Same selector as the bond's InvalidCouponFrequency error.
    error InvalidCouponFrequency(uint8 couponsPerYear);

    /// @dev Same selector as the bond's CouponPaymentWindowClosed error.
    error CouponPaymentWindowClosed(uint256 index);

    /**
     * @notice Validates the encoded deployment payload of a fixed rate bond.
     * @dev ACT/ACT ICMA: validate the unadjusted calendar grid backwards from maturity,
     *      without end-of-month rolling. Only a short first period is supported.
     * @param productPayload ABI-encoded FixedRateBondDeploymentPayload.
     */
    function initializeBond(bytes memory productPayload, CommonDeploymentParams memory common, BondSettlementModules memory modules,
        CouponPeriod[] storage periods) external returns (FixedRateBondTerms memory terms, address clientRegistry, bytes32 economicTermsHash)
    {
        FixedRateBondDeploymentPayload memory p = abi.decode(productPayload, (FixedRateBondDeploymentPayload));
        terms = p.terms;
        if (terms.buyer == address(0)) revert ZeroAddress("buyer");
        if (terms.buyer == common.productProvider) revert InvalidCounterparty(terms.buyer);
        if (modules.assetToken.code.length == 0) revert InvalidSettlementContract(modules.assetToken);
        if (modules.paymentContract.code.length == 0) revert InvalidSettlementContract(modules.paymentContract);
        clientRegistry = IProductDefinitionRegistry(common.productRegistry).clientRegistryAddress();
        if (clientRegistry == address(0)) revert ZeroAddress("clientRegistry");
        _initializeCoupons(p, periods);
        economicTermsHash = _economicTermsHash(p, common.productProvider, common.productTermsTemplate, common.productDocumentationTemplate);
    }

    function _initializeCoupons(FixedRateBondDeploymentPayload memory p, CouponPeriod[] storage periods) private {

        if (p.terms.initialAggregateAmount == 0) revert InvalidAmount();
        // Both amounts use amountScale; require a whole number of denominations.
        if (p.terms.specifiedDenomination == 0 || p.terms.initialAggregateAmount % p.terms.specifiedDenomination != 0) {
            revert InvalidAmount();
        }
        if (p.terms.issuePrice == 0) revert InvalidAmount();
        if (p.terms.finalRedemptionPercentage == 0) revert InvalidAmount();
        if (p.terms.maturityDate <= block.timestamp) revert InvalidAmount();
        if (!DateTimeLib.isSupportedTimestamp(p.terms.maturityDate)) revert InvalidAmount();
        if (p.terms.couponsPerYear != 1 && p.terms.couponsPerYear != 2 && p.terms.couponsPerYear != 4 && p.terms.couponsPerYear != 12) {
            revert InvalidCouponFrequency(p.terms.couponsPerYear);
        }

        if (p.terms.pricingDate == 0 || p.terms.issueDate == 0 || p.terms.settlementDate == 0
            || p.terms.pricingDate % 1 days != 0 || p.terms.issueDate % 1 days != 0 || p.terms.settlementDate % 1 days != 0
            || p.terms.pricingDate > p.terms.issueDate || p.terms.issueDate > p.terms.settlementDate || p.terms.settlementDate > p.terms.maturityDate) {
            revert InvalidIssuanceDates();
        }

        uint256 n = p.couponPeriods.length;
        if (n == 0) revert InvalidCouponPeriod(0);
        uint256 monthsPerCoupon = 12 / p.terms.couponsPerYear;
        (uint256 year, uint256 month,) = DateTimeLib.timestampToDate(p.terms.maturityDate);
        // DateTimeLib and uint timestamps cannot represent a reference period before 1970.
        if (n > ((year - 1970) * 12 + month - 1) / monthsPerCoupon) revert InvalidCouponPeriod(0);

        for (uint256 i = 0; i < n; ) {
            CouponPeriod memory c = p.couponPeriods[i];
            // All dates must represent midnight UTC.
            if (uint256(c.startDate) % 1 days != 0 || uint256(c.endDate) % 1 days != 0 || uint256(c.paymentDate) % 1 days != 0 || uint256(c.referenceStartDate) % 1 days != 0) {
                revert InvalidCouponPeriod(i);
            }
            // Do not deploy a coupon whose request window has already expired.
            // Cast before adding to avoid uint64 arithmetic.
            if (block.timestamp >= uint256(c.paymentDate) + 1 days) {
                revert CouponPaymentWindowClosed(i);
            }
            if (c.endDate <= c.startDate) revert InvalidCouponPeriod(i);
            if (c.paymentDate < c.endDate) revert InvalidCouponPeriod(i);
            // Always subtract from maturity: repeated subtraction would drift after February.
            if (c.referenceStartDate != DateTimeLib.subMonths(p.terms.maturityDate, monthsPerCoupon * (n - i))
                || c.endDate != DateTimeLib.subMonths(p.terms.maturityDate, monthsPerCoupon * (n - i - 1))
                || c.startDate < c.referenceStartDate
                || (i > 0 && c.startDate != c.referenceStartDate)) {
                revert InvalidCouponPeriod(i);
            }
            if (i > 0 && c.startDate != p.couponPeriods[i - 1].endDate) {
                revert InvalidCouponPeriod(i);
            }
            periods.push(c);
            unchecked { ++i; }
        }

        if (p.couponPeriods[n - 1].endDate != p.terms.maturityDate) {
            revert InvalidCouponPeriod(n - 1);
        }
    }

    function _economicTermsHash(FixedRateBondDeploymentPayload memory p, address issuer, address termsTemplate, address documentationTemplate)
        private view returns (bytes32)
    {
        // A static tuple is encoded inline: identical to the flat v6 vector with all eleven
        // fields listed individually, without keeping every value live on the compiler stack.
        bytes32 payloadHash = keccak256(abi.encode(address(this), issuer, p.terms, p.couponPeriods));
        return keccak256(abi.encode(payloadHash, ITextResource(termsTemplate).contentHash(),
            ITextResource(documentationTemplate).contentHash()));
    }

    /// @notice ICMA document-status label for initial delivery completion.
    function documentStatus(bool issued) external pure returns (string memory) {
        return issued ? "ISSUED" : "PENDING";
    }

    /// @notice Actual payment frequency; one final coupon is independent of its reference frequency.
    function interestPaymentFrequency(uint256 count, uint8 frequency) external pure returns (string memory) {
        if (count == 1) return "ATMATURITY";
        if (frequency == 1) return "ANNUALLY";
        if (frequency == 2) return "SEMIANNUALLY";
        if (frequency == 4) return "QUARTERLY";
        if (frequency == 12) return "MONTHLY";
        revert InvalidCouponFrequency(frequency);
    }

    /**
     * @dev Validates and freezes a coupon claim before the bond asks Payment to generate keys.
     *      The upper request-window bound applies to the one supported attempt.
     */
    function inceptCouponPayment(
        CouponPeriod[] storage periods,
        CouponSettlement storage settlement,
        mapping(uint256 => uint256) storage couponIndexByPaymentId,
        uint256 index,
        bytes calldata transaction,
        CouponPaymentInception memory inception
    ) external {
        (bytes32 requestId, uint256 amount) = _prepareCouponPayment(
            periods,
            settlement,
            index,
            transaction,
            inception
        );
        couponIndexByPaymentId[uint256(requestId)] = index + 1;

        emit CouponPaymentRequested(index, requestId, amount, inception.payee);
        IDecryptionContractWithKeyGeneration(inception.paymentContract).inceptTransfer(
            uint256(requestId),
            int256(amount),
            inception.payer,
            inception.payee,
            transaction,
            IDecryptionContractInceptionCallback(address(this))
        );
    }

    function _prepareCouponPayment(
        CouponPeriod[] storage periods,
        CouponSettlement storage settlement,
        uint256 index,
        bytes calldata transaction,
        CouponPaymentInception memory inception
    ) private returns (bytes32 requestId, uint256 amount) {
        if (index >= periods.length) revert InvalidCouponPeriod(index);
        uint256 paymentDate = periods[index].paymentDate;
        if (block.timestamp < paymentDate) revert CouponNotDue(index, paymentDate);
        if (block.timestamp >= paymentDate + 1 days) revert CouponPaymentWindowClosed(index);
        if (settlement.status != CouponPaymentStatus.None) revert CouponAlreadyRequested(index);
        address generationOracle =
            IPaymentOracleConfiguration(inception.paymentContract).oracleOf(inception.payee);
        if (
            generationOracle != inception.expectedGenerationOracle
                || generationOracle == address(0)
        ) {
            revert UnexpectedPaymentOracle(inception.expectedGenerationOracle, generationOracle);
        }

        amount = _couponAmount(
            periods[index], inception.calculationAmount, inception.rate, inception.frequency, inception.scale
        ) * inception.unitCount;
        if (amount == 0) revert InvalidAmount();
        requestId = bytes32(
            ((uint256(uint160(address(this))) << 96) ^ COUPON_ID_DOMAIN) | uint96(index + 1)
        );
        settlement.status = CouponPaymentStatus.Pending;
        settlement.amount = amount;
        settlement.contextHash = keccak256(abi.encode(uint256(requestId), transaction));
    }

    /**
     * @dev The bond authenticates its payment adapter before dispatching this callback. This
     *      function freezes both outcome commitments. The delegatecall executes as the bond,
     *      so Payment scopes both getters to the exact callback address and cannot substitute
     *      a callback-free leg.
     */
    function completeCouponLock(
        CouponSettlement storage settlement,
        uint256 index,
        uint256 id,
        address paymentContract,
        address payer,
        address payee
    ) external {
        if (settlement.status != CouponPaymentStatus.Pending) {
            revert InvalidCouponPaymentState(index, settlement.status);
        }
        if (settlement.executionHash != bytes32(0)) return;

        IDecryptionContractWithKeyGeneration payment =
            IDecryptionContractWithKeyGeneration(paymentContract);
        {
            (
                bool exists,
                int256 amount,
                address from,
                address to,
                bytes memory transaction,
                IDecryptionContractInceptionCallback callback
            ) = payment.getInceptionContext(id);
            if (
                !exists || amount <= 0 || uint256(amount) != settlement.amount || from != payer
                    || to != payee || address(callback) != address(this)
                    || keccak256(abi.encode(id, transaction)) != settlement.contextHash
            ) revert InvalidTransferContext();
        }

        (bool available, , bytes memory hashedSuccess, , bytes memory hashedFailure) =
            payment.getInceptionKeyMaterial(id);
        if (!available || hashedSuccess.length != 32 || hashedFailure.length != 32) {
            revert InvalidKeyMaterial();
        }
        bytes32 executionHash = abi.decode(hashedSuccess, (bytes32));
        bytes32 cancellationHash = abi.decode(hashedFailure, (bytes32));
        if (
            executionHash == bytes32(0) || executionHash == cancellationHash
                || cancellationHash == bytes32(0)
        ) revert InvalidKeyMaterial();

        settlement.executionHash = executionHash;
        settlement.cancellationHash = cancellationHash;
        emit TokenLocked(id);
    }

    /** @dev Consumes the released key against evidence frozen in the bond, not Payment state. */
    function transferCouponWithKey(
        CouponSettlement storage settlement,
        uint256 index,
        uint256 id,
        bytes calldata key
    ) external {
        if (
            settlement.status != CouponPaymentStatus.Pending
                || settlement.executionHash == bytes32(0)
        ) revert InvalidCouponPaymentState(index, settlement.status);

        bytes32 keyHash = sha256(key);
        if (keyHash == settlement.executionHash) {
            settlement.status = CouponPaymentStatus.Paid;
            emit TokenClaimed(id, key);
            emit CouponPaid(index, bytes32(id));
            return;
        }
        if (keyHash == settlement.cancellationHash) {
            settlement.status = CouponPaymentStatus.Failed;
            emit TokenReclaimed(id, key);
            emit CouponPaymentFailed(index, bytes32(id));
            return;
        }
        revert InvalidKey();
    }

    /// @notice Coupon rounded down per calculation amount, before applying a claim's unit count.
    function couponAmount(CouponPeriod storage period, uint256 calculationAmount, uint256 rate, uint8 frequency, uint8 scale)
        external view returns (uint256)
    {
        return _couponAmount(period, calculationAmount, rate, frequency, scale);
    }


    /// @dev ACT/ACT ICMA, rounded down once per calculation amount to a minor currency unit.
    ///      Following affects only paymentDate. Position sizing is applied after this calculation.
    function _couponAmount(CouponPeriod storage period, uint256 calculationAmount, uint256 rate, uint8 frequency, uint8 scale)
        private view returns (uint256)
    {
        uint256 accrualDays = (period.endDate - period.startDate) / 1 days;
        uint256 referenceDays = (period.endDate - period.referenceStartDate) / 1 days;
        uint256 denominator = referenceDays * frequency * 100 * (uint256(10) ** uint256(scale));
        return Math.mulDiv(calculationAmount, rate * accrualDays, denominator);
    }

    /// @notice Existing settlement/redemption calculation using the bond's immutable terms.
    /// @dev Reading the public getters inside this delegatecall avoids embedding their argument
    ///      setup twice in the bond's creation code, which must fit inside its factory.
    function bondPercentageAmount(bool redemption) external view returns (uint256) {
        IVersionedBondRepresentation bond = IVersionedBondRepresentation(address(this));
        return percentageAmount(bond.initialAggregateAmount(),
            redemption ? bond.finalRedemptionPercentage() : bond.issuePrice(), bond.percentageScale());
    }

    function percentageAmount(uint256 principal, uint256 percentage, uint8 scale) public pure returns (uint256) {
        return Math.mulDiv(principal, percentage, 100 * (uint256(10) ** uint256(scale)));
    }

}
