// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProduct} from "../products/AbstractProduct.sol";
import {CommonDeploymentParams} from "../productfactories/ProductDeploymentTypes.sol";
import {IFixedRateBond} from "./IFixedRateBond.sol";
import {ISDCTrade} from "./ISDC/ISDCTrade.sol";
import {IClientRegistry} from "../../clientRegistry/IClientRegistry.sol";
import {IProductDefinitionRegistry} from "../../productdefinitionregistry/IProductDefinitionRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IssuanceType, DeliveryType, DistributionMethod, InterestType, RedemptionType, RedemptionBasis, FormOfNote, SafekeepingStructure, Seniority,
    Subordination, Collateralization, DLTPlatform, TokenStandard, PaymentFrequency, DayCountFraction, BusinessDayConvention, BusinessDayCenter, StubType} from "./BondTypes.sol";

/**
 * @title FixedRateBond
 * @notice Bond paying a constant interest rate, issued through the product
 *         framework and traded via ERC-6123 inception and confirmation.
 *
 * @dev TWO INDEPENDENT STATE MACHINES
 *      IssuancePhase tracks the technical issuance (identifiers, token minting)
 *      and drives the actions offered by the frontend. AllocationStatus tracks
 *      each client's trade separately. Identifier assignment and minting proceed
 *      regardless of whether clients have confirmed.
 *
 * @dev TERMS AGREEMENT
 *      The tradeData exchanged during inception and confirmation is the hex
 *      encoded currentTermsHash(). Both parties therefore commit to the exact
 *      same contract state; the term sheet itself is rendered off-chain from
 *      that state and is not stored on-chain.
 *
 * @author Raphael Prandtl
 */
contract FixedRateBond is AbstractProduct, IFixedRateBond, ISDCTrade {
    using Strings for uint256;
    // ------------------------------ Enums ------------------------------ */

    /**
     * @notice Issuance phases of the bond.
     * @dev Drives the actions offered by the frontend. Allocation, inception and
     *      confirmation are possible in every phase except BooksClosed; the phase
     *      chain only tracks the technical issuance steps.
     */
    enum IssuancePhase {
        /// @dev Terms amendable, allocation and confirmation open.
        Offering,
        /// @dev Identifier request sent, response pending.
        IsinRequested,
        /// @dev ISIN and WKN assigned.
        IsinAssigned,
        /// @dev Token minting requested, callback pending.
        MintRequested,
        /// @dev Asset token address reported back.
        Minted,
        /// @dev Books closed, no further trades; unconfirmed allocations rejected.
        BooksClosed
    }

    /// @notice Status of a single client allocation.
    enum AllocationStatus {
        /// @dev No allocation exists.
        None,
        /// @dev Allocated by the seller, awaiting client confirmation.
        Incepted,
        /// @dev Confirmed by the client.
        Confirmed,
        /// @dev Withdrawn by either party, or lapsed when the books were closed.
        Rejected
    }

    // ------------------------------ Constants ------------------------------ */

    uint8 public constant override amountScale = 2;
    uint8 public constant override percentageScale = 4;
    uint8 public constant override rateScale = 4;

    IssuanceType public constant override issuanceType = IssuanceType.Standalone;
    InterestType public constant override interestType = InterestType.Fixed;
    FormOfNote public constant override formOfNote = FormOfNote.DematerialisedBearer;
    SafekeepingStructure public constant override safekeepingStructure = SafekeepingStructure.NewSafekeepingStructureElectronic;
    Seniority public constant override seniority = Seniority.Senior;
    Subordination public constant override subordination = Subordination.Unsubordinated;
    Collateralization public constant override collateralization = Collateralization.Unsecured;
    DLTPlatform public constant override dltPlatform = DLTPlatform.Ethereum;
    TokenStandard public constant override tokenStandard = TokenStandard.ERC20;
    bool public constant override dltBondIndicator = true;
    bool public constant override centralBankEligible = false;
    bool public constant override unrated = true;
    bytes2 public constant override governingLaw = "DE";

    /// @dev Flags marking which late-bound term sheet values have been assigned.
    uint8 private constant FLAG_IDENTIFIERS = 1;
    uint8 private constant FLAG_ASSET_TOKEN = 2;
    uint8 private constant FLAG_ALL = FLAG_IDENTIFIERS | FLAG_ASSET_TOKEN;

    // ------------------------------ Structs ------------------------------ */

    /// @notice A single client allocation and its associated trade.
    struct Allocation {
        AllocationStatus status;
        uint64 inceptedAt;
        address client;
        uint256 nominal;
        uint256 paymentAmount;
        bytes32 agreedTermsHash;
    }

    /**
     * @notice ABI-decoded deployment payload of the fixed rate bond.
     * @dev Canonical ABI type, kept in sync with FixedRateBondFactory:
     *      tuple(address,address,uint256,uint256,uint256,uint256,uint256,bytes3,
     *            uint256,uint64,uint64,uint64,uint64,uint64,uint256,uint256,
     *            uint8,uint8,uint8,uint8,bool,bool,uint256,uint64,uint8,uint8,
     *            uint8,uint8,uint8,uint64,uint8,uint256,uint64,uint256)
     */
    struct FixedRateBondDeploymentPayload {
        // --- Roles and infrastructure ---
        address seller;                     // zero address falls back to productProvider
        address cashlinkOracleProxy;

        // --- Issuance ---
        uint256 initialAggregateAmount;
        uint256 specifiedDenomination;
        uint256 minimumDenomination;
        uint256 integralMultiples;
        uint256 calculationAmount;
        bytes3  specifiedCurrency;
        uint256 nominalPerToken;

        // --- Dates ---
        uint64 pricingDate;
        uint64 issueDate;
        uint64 settlementDate;
        uint64 maturityDate;
        uint64 finalRedemptionDate;

        // --- Pricing and redemption ---
        uint256 issuePrice;
        uint256 finalRedemptionPercentage;
        uint8   redemptionType;
        uint8   redemptionPaymentBasis;
        uint8   delivery;
        uint8   methodOfDistribution;
        bool    privatePlacement;
        bool    listed;

        // --- Interest ---
        uint256 interestRate;
        uint64  interestCommencementDate;
        uint8   interestPaymentFrequency;
        uint8   dayCountFraction;
        uint8   businessDayConvention;
        uint8   businessDayCenter;
        uint8   payableDay;
        uint8   payableMonth;
        uint64  firstPaymentDate;
        uint8   firstPaymentStub;
        uint256 firstPaymentAmount;
        uint64  lastPaymentDate;
        uint256 lastPaymentAmount;
    }


    // ------------------------------ Immutable State ------------------------------ */

    /// @notice Party placing the bond; defaults to the product provider.
    address public immutable seller;
    /// @notice Oracle proxy authorised to report the minted asset token.
    address public immutable cashlinkOracleProxy;
    /// @notice Registry used for client eligibility and identifier requests.
    address public immutable clientRegistry;

    uint256 public immutable override initialAggregateAmount;
    uint256 public immutable override specifiedDenomination;
    uint256 public immutable override minimumDenomination;
    uint256 public immutable override integralMultiples;
    uint256 public immutable override calculationAmount;
    bytes3  public immutable override specifiedCurrency;
    uint256 public immutable override nominalPerToken;

    uint64 public immutable override pricingDate;
    uint64 public immutable override issueDate;
    uint64 public immutable override settlementDate;
    uint64 public immutable override maturityDate;
    uint64 public immutable override finalRedemptionDate;

    uint256 public immutable override issuePrice;
    uint256 public immutable override finalRedemptionPercentage;
    RedemptionType public immutable override redemptionType;
    RedemptionBasis public immutable override redemptionPaymentBasis;
    DeliveryType public immutable override delivery;
    DistributionMethod public immutable override methodOfDistribution;
    bool public immutable override privatePlacement;
    bool public immutable override listed;

    uint256 public immutable override interestRate;
    uint64 public immutable override interestCommencementDate;
    PaymentFrequency public immutable override interestPaymentFrequency;
    DayCountFraction public immutable override dayCountFraction;
    BusinessDayConvention public immutable override businessDayConvention;
    BusinessDayCenter public immutable businessDayCenterCode;
    uint8 public immutable override payableDay;
    uint8 public immutable override payableMonth;
    uint64 public immutable override firstPaymentDate;
    StubType public immutable override firstPaymentStub;
    uint256 public immutable override firstPaymentAmount;
    uint64 public immutable override lastPaymentDate;
    uint256 public immutable override lastPaymentAmount;

    // ------------------------------ Mutable State ------------------------------ */

    /// @notice Current issuance phase.
    IssuancePhase public phase;

    /// @inheritdoc IBond
    string public override isin;
    /// @inheritdoc IBond
    string public override wkn;
    /// @inheritdoc IBond
    address public override assetToken;

    /// @notice Block the term sheet was finalized; 0 until final.
    uint64 public termsFinalizationBlock;

    /// @dev Bitmask of assigned late-bound values.
    uint8 private _finalisedFlags;

    /// @notice Aggregate nominal currently allocated and not rejected.
    uint256 public allocatedNominal;

    mapping(bytes32 => Allocation) private _allocations;
    mapping(address => bytes32) private _tradeIdOf;
    bytes32[] private _tradeIds;
    uint256 private _tradeNonce;

    // ------------------------------ Custom Errors ------------------------------ */

    error NotSeller(address caller);
    error NotClientRegistry(address caller);
    error NotOracleProxy(address caller);
    error InvalidPhase(IssuancePhase current);
    error BooksAreClosed();
    error InvalidCounterparty(address party);
    error AllocationExists(address client);
    error NoAllocation(address client);
    error ClientNotEligible(address client);
    error TermsMismatch(bytes32 expected, bytes32 actual);
    error ExceedsIssueSize(uint256 requested, uint256 available);
    error LengthMismatch();
    error InvalidAmount();
    error AlreadyAssigned();
    error TermsLocked();
    error NotImplementedYet();

    // ------------------------------ Events ------------------------------ */

    event IsinRequestSent(address indexed clientRegistry);
    event IdentifiersAssigned(string isin, string wkn);
    event MintingRequested(uint256 amount);
    event AssetTokenAssigned(address indexed assetToken);
    event TermsFinalized(uint64 referenceBlock);
    event BooksClosedEvent(uint256 confirmedNominal, uint256 rejectedNominal);
    event AllocationRejected(address indexed client, bytes32 tradeId);
    event PhaseChanged(IssuancePhase previousPhase, IssuancePhase newPhase);

    // ------------------------------ Constructor ------------------------------ */

    constructor(CommonDeploymentParams memory common, bytes memory productPayload)
    AbstractProduct(common)
    {
        FixedRateBondDeploymentPayload memory p = abi.decode(productPayload, (FixedRateBondDeploymentPayload));

        seller = p.seller == address(0) ? common.productProvider : p.seller;

        if (p.cashlinkOracleProxy == address(0)) revert ZeroAddress("cashlinkOracleProxy");
        cashlinkOracleProxy = p.cashlinkOracleProxy;

        clientRegistry = IProductDefinitionRegistry(common.productRegistry).clientRegistryAddress();
        if (clientRegistry == address(0)) revert ZeroAddress("clientRegistry");

        _validate(p);

        initialAggregateAmount = p.initialAggregateAmount;
        specifiedDenomination = p.specifiedDenomination;
        minimumDenomination = p.minimumDenomination;
        integralMultiples = p.integralMultiples;
        calculationAmount = p.calculationAmount;
        specifiedCurrency = p.specifiedCurrency;
        nominalPerToken = p.nominalPerToken;

        pricingDate = p.pricingDate;
        issueDate = p.issueDate;
        settlementDate = p.settlementDate;
        maturityDate = p.maturityDate;
        finalRedemptionDate = p.finalRedemptionDate;

        issuePrice = p.issuePrice;
        finalRedemptionPercentage = p.finalRedemptionPercentage;
        redemptionType = RedemptionType(p.redemptionType);
        redemptionPaymentBasis = RedemptionBasis(p.redemptionPaymentBasis);
        delivery = DeliveryType(p.delivery);
        methodOfDistribution = DistributionMethod(p.methodOfDistribution);
        privatePlacement = p.privatePlacement;
        listed = p.listed;

        interestRate = p.interestRate;
        interestCommencementDate = p.interestCommencementDate;
        interestPaymentFrequency = PaymentFrequency(p.interestPaymentFrequency);
        dayCountFraction = DayCountFraction(p.dayCountFraction);
        businessDayConvention = BusinessDayConvention(p.businessDayConvention);
        businessDayCenterCode = BusinessDayCenter(p.businessDayCenter);
        payableDay = p.payableDay;
        payableMonth = p.payableMonth;
        firstPaymentDate = p.firstPaymentDate;
        firstPaymentStub = StubType(p.firstPaymentStub);
        firstPaymentAmount = p.firstPaymentAmount;
        lastPaymentDate = p.lastPaymentDate;
        lastPaymentAmount = p.lastPaymentAmount;

        phase = IssuancePhase.Offering;
    }

    /// @dev Validates the decoded payload; reverts on any inconsistency.
    function _validate(FixedRateBondDeploymentPayload memory p) private view {
        if (p.initialAggregateAmount == 0) revert InvalidAmount();
        if (p.calculationAmount == 0) revert InvalidAmount();
        if (p.minimumDenomination == 0) revert InvalidAmount();
        if (p.nominalPerToken == 0) revert InvalidAmount();
        if (p.issuePrice == 0) revert InvalidAmount();
        if (p.maturityDate <= block.timestamp) revert InvalidAmount();
        if (p.settlementDate < p.issueDate) revert InvalidAmount();
        if (p.finalRedemptionDate < p.maturityDate) revert InvalidAmount();
        if (p.payableDay == 0 || p.payableDay > 31) revert InvalidAmount();
        if (p.payableMonth == 0 || p.payableMonth > 12) revert InvalidAmount();
    }

    // ------------------------------ Modifiers ------------------------------ */

    modifier onlySeller() {
        if (msg.sender != seller) revert NotSeller(msg.sender);
        _;
    }

    modifier booksOpen() {
        if (phase == IssuancePhase.BooksClosed) revert BooksAreClosed();
        _;
    }

    modifier inPhase(IssuancePhase expected) {
        if (phase != expected) revert InvalidPhase(phase);
        _;
    }

    // ------------------------------ Trade Lifecycle (ERC-6123) ------------------------------ */

    /**
     * @inheritdoc ISDCTrade
     * @dev Seller-driven: the seller allocates nominal to a client and incepts
     *      the trade on its behalf. tradeData must be the hex encoded
     *      currentTermsHash(). position carries the allocated nominal; the
     *      payment amount is derived from the issue price and the supplied value
     *      is ignored to avoid inconsistencies with the term sheet.
     */
    function inceptTrade(address withParty, string memory tradeData, int position, int256 /* paymentAmount */, string memory initialSettlementData) external override onlySeller booksOpen returns (string memory) {
        if (withParty == address(0) || withParty == seller) revert InvalidCounterparty(withParty);
        if (position <= 0) revert InvalidAmount();
        if (_tradeIdOf[withParty] != bytes32(0)) revert AllocationExists(withParty);
        if (!IClientRegistry(clientRegistry).isEligibleClient(withParty, productDefinitionId)) {
            revert ClientNotEligible(withParty);
        }

        bytes32 termsHash = _requireTermsHash(tradeData);

        uint256 nominal = uint256(position);
        uint256 available = initialAggregateAmount - allocatedNominal;
        if (nominal > available) revert ExceedsIssueSize(nominal, available);

        bytes32 tradeId = keccak256(abi.encode(address(this), withParty, _tradeNonce++));

        _allocations[tradeId] = Allocation({
            status: AllocationStatus.Incepted,
            inceptedAt: uint64(block.timestamp),
            client: withParty,
            nominal: nominal,
            paymentAmount: _paymentAmountFor(nominal),
            agreedTermsHash: termsHash
        });
        _tradeIdOf[withParty] = tradeId;
        _tradeIds.push(tradeId);
        allocatedNominal += nominal;

        string memory tradeIdString = _toTradeIdString(tradeId);
        emit TradeIncepted(msg.sender, withParty, tradeIdString, tradeData, position, 0, initialSettlementData);
        return tradeIdString;
    }

    /**
     * @inheritdoc ISDCTrade
     * @dev Callable by the allocated client only, in any phase before the books
     *      are closed. tradeData must match the hash frozen at inception.
     */
    function confirmTrade(address withParty, string memory tradeData, int position, int256 /* paymentAmount */, string memory initialSettlementData) external override booksOpen {
        bytes32 tradeId = _tradeIdOf[msg.sender];
        Allocation storage a = _allocations[tradeId];
        if (a.status != AllocationStatus.Incepted) revert NoAllocation(msg.sender);
        if (withParty != seller) revert InvalidCounterparty(withParty);
        if (uint256(position) != a.nominal) revert InvalidAmount();

        bytes32 supplied = _parseTermsHash(tradeData);
        if (supplied != a.agreedTermsHash) revert TermsMismatch(a.agreedTermsHash, supplied);

        a.status = AllocationStatus.Confirmed;

        emit TradeConfirmed(msg.sender, _toTradeIdString(tradeId), tradeData, position, 0, initialSettlementData);
    }

    /**
     * @inheritdoc ISDCTrade
     * @dev Callable by the seller or the allocated client while the allocation
     *      has not been confirmed.
     */
    function cancelTrade(address /* withParty */, string memory /* tradeData */, int /* position */, int256 /* paymentAmount */, string memory /* initialSettlementData */) external override booksOpen {
        address client = msg.sender == seller ? address(0) : msg.sender;
        bytes32 tradeId = _tradeIdOf[client == address(0) ? msg.sender : client];
        Allocation storage a = _allocations[tradeId];

        if (a.status != AllocationStatus.Incepted) revert NoAllocation(msg.sender);
        if (msg.sender != seller && msg.sender != a.client) revert NotSeller(msg.sender);

        _rejectAllocation(tradeId, a);
    }

    /// @notice Rejects a single unconfirmed allocation.
    function rejectAllocation(address client) external onlySeller booksOpen {
        bytes32 tradeId = _tradeIdOf[client];
        Allocation storage a = _allocations[tradeId];
        if (a.status != AllocationStatus.Incepted) revert NoAllocation(client);
        _rejectAllocation(tradeId, a);
    }

    /**
     * @notice Allocates nominal to several clients and incepts each trade.
     * @dev Convenience wrapper around inceptTrade for the common case.
     */
    function setAmounts(address[] calldata clients, uint256[] calldata nominals) external onlySeller booksOpen {
        if (clients.length != nominals.length) revert LengthMismatch();

        bytes32 termsHash = currentTermsHash();
        string memory tradeData = _toTermsHashString(termsHash);

        for (uint256 i = 0; i < clients.length; ) {
            this.inceptTrade(clients[i], tradeData, int(nominals[i]), 0, "");
            unchecked { ++i; }
        }
    }

    // ------------------------------ Issuance Process ------------------------------ */

    /// @notice Requests ISIN and WKN from the client registry.
    function requestIsin() external onlySeller inPhase(IssuancePhase.Offering) {
        _setPhase(IssuancePhase.IsinRequested);
        emit IsinRequestSent(clientRegistry);
        IClientRegistry(clientRegistry).requestISINAndWKN(productRegistry, productDefinitionId, productProvider);
    }

    /// @notice Callback assigning the security identifiers.
    function setISINandWKN(string calldata isin_, string calldata wkn_) external {
        if (msg.sender != clientRegistry) revert NotClientRegistry(msg.sender);
        if (bytes(isin).length != 0) return; // idempotent

        isin = isin_;
        wkn = wkn_;
        _setPhase(IssuancePhase.IsinAssigned);
        emit IdentifiersAssigned(isin_, wkn_);
        _markFinalised(FLAG_IDENTIFIERS);
    }

    /// @notice Requests minting of the security token.
    function requestMinting() external onlySeller inPhase(IssuancePhase.IsinAssigned) {
        uint256 tokenSupply = initialAggregateAmount / nominalPerToken;
        _setPhase(IssuancePhase.MintRequested);
        emit MintingRequested(tokenSupply);
        // Oracle proxy picks up the event and calls back setAssetTokenAddress.
    }

    /// @notice Callback reporting the deployed security token.
    function setAssetTokenAddress(address assetToken_) external {
        if (msg.sender != cashlinkOracleProxy) revert NotOracleProxy(msg.sender);
        if (assetToken != address(0)) return; // idempotent
        if (assetToken_ == address(0)) revert ZeroAddress("assetToken");

        assetToken = assetToken_;
        _setPhase(IssuancePhase.Minted);
        emit AssetTokenAssigned(assetToken_);
        _markFinalised(FLAG_ASSET_TOKEN);
    }

    /// @notice Closes the books; unconfirmed allocations lapse.
    function closeBooks() external onlySeller inPhase(IssuancePhase.Minted) {
        uint256 rejected;
        uint256 confirmed;
        uint256 len = _tradeIds.length;

        for (uint256 i = 0; i < len; ) {
            Allocation storage a = _allocations[_tradeIds[i]];
            if (a.status == AllocationStatus.Incepted) {
                rejected += a.nominal;
                a.status = AllocationStatus.Rejected;
                emit AllocationRejected(a.client, _tradeIds[i]);
            } else if (a.status == AllocationStatus.Confirmed) {
                confirmed += a.nominal;
            }
            unchecked { ++i; }
        }

        allocatedNominal = confirmed;
        _setPhase(IssuancePhase.BooksClosed);
        emit BooksClosedEvent(confirmed, rejected);
    }

    // ------------------------------ Manual Recovery ------------------------------ */

    /// @notice Retries the identifier request after a failed attempt.
    function retryIsinRequest() external onlySeller inPhase(IssuancePhase.IsinRequested) {
        emit IsinRequestSent(clientRegistry);
        IClientRegistry(clientRegistry).requestISINAndWKN(productRegistry, productDefinitionId, productProvider);
    }

    /// @notice Retries the minting request after a failed attempt.
    function retryMinting() external onlySeller inPhase(IssuancePhase.MintRequested) {
        emit MintingRequested(initialAggregateAmount / nominalPerToken);
    }

    /// @notice Assigns identifiers manually if the automated path fails permanently.
    function forceSetISINandWKN(string calldata isin_, string calldata wkn_) external onlyProductProvider {
        if (bytes(isin).length != 0) revert AlreadyAssigned();
        isin = isin_;
        wkn = wkn_;
        _setPhase(IssuancePhase.IsinAssigned);
        emit IdentifiersAssigned(isin_, wkn_);
        _markFinalised(FLAG_IDENTIFIERS);
    }

    // ------------------------------ Views ------------------------------ */

    /// @inheritdoc IBond
    function outstandingAggregateAmount() external view override returns (uint256) {
        return initialAggregateAmount;
    }

    /// @inheritdoc IBond
    function issuerName() external view override returns (string memory) {
        return IClientRegistry(clientRegistry).nameOf(productProvider);
    }

    /// @inheritdoc IBond
    function issuerLei() external view override returns (string memory) {
        return IClientRegistry(clientRegistry).leiOf(productProvider);
    }

    /// @inheritdoc IBond
    function issuerRatings() external view override returns (string memory) {
        return IClientRegistry(clientRegistry).ratingsOf(productProvider);
    }

    /// @notice Returns the allocation of a client.
    function allocationOf(address client) external view returns (Allocation memory) {
        return _allocations[_tradeIdOf[client]];
    }

    /// @notice Returns all trade ids created on this bond.
    function tradeIds() external view returns (bytes32[] memory) {
        return _tradeIds;
    }

    /// @notice Returns the number of allocations.
    function allocationCount() external view returns (uint256) {
        return _tradeIds.length;
    }

    // ------------------------------ Internal ------------------------------ */

    function _setPhase(IssuancePhase newPhase) private {
        IssuancePhase previous = phase;
        phase = newPhase;
        emit PhaseChanged(previous, newPhase);
    }

    function _markFinalised(uint8 flag) private {
        _finalisedFlags |= flag;
        if (_finalisedFlags == FLAG_ALL && termsFinalizationBlock == 0) {
            termsFinalizationBlock = uint64(block.number);
            emit TermsFinalized(termsFinalizationBlock);
        }
    }

    function _rejectAllocation(bytes32 tradeId, Allocation storage a) private {
        a.status = AllocationStatus.Rejected;
        allocatedNominal -= a.nominal;
        delete _tradeIdOf[a.client];
        emit AllocationRejected(a.client, tradeId);
    }

    /// @dev Payment amount derived from nominal and issue price.
    function _paymentAmountFor(uint256 nominal) private view returns (uint256) {
        return (nominal * issuePrice) / (100 * 10 ** percentageScale);
    }

    function _requireTermsHash(string memory tradeData) private view returns (bytes32) {
        bytes32 current = currentTermsHash();
        bytes32 supplied = _parseTermsHash(tradeData);
        if (supplied != current) revert TermsMismatch(current, supplied);
        return current;
    }

    function _toTermsHashString(bytes32 h) private pure returns (string memory) {
        return uint256(h).toHexString(32);
    }

    function _toTradeIdString(bytes32 id) private pure returns (string memory) {
        return uint256(id).toHexString(32);
    }

    /// @dev Parses a 0x-prefixed 32 byte hex string back into bytes32.
    function _parseTermsHash(string memory s) private pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length != 66) revert TermsMismatch(bytes32(0), bytes32(0));
        for (uint256 i = 0; i < 32; i++) {
            result |= bytes32(uint256(_hexPair(b[2 + i * 2], b[3 + i * 2])) << (8 * (31 - i)));
        }
    }

    function _hexPair(bytes1 hi, bytes1 lo) private pure returns (uint8) {
        return uint8(_hexVal(hi) * 16 + _hexVal(lo));
    }

    function _hexVal(bytes1 c) private pure returns (uint8) {
        uint8 v = uint8(c);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 97 && v <= 102) return v - 87;
        if (v >= 65 && v <= 70) return v - 55;
        revert TermsMismatch(bytes32(0), bytes32(0));
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc AbstractProduct
    function _productSpecificStateXml() internal view override returns (string memory) {
        return ITextResource(productTermsTemplate).content();
    }
}
