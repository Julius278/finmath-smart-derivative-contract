// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductIndication} from "../ProductIndication/AbstractProductIndication.sol";

/**
 * @title CurveIndications
 * @notice Concrete indication registry for curve indications (a set of quotes
 *         forming an indicative curve for bond-like products).
 * @dev Lifecycle (status, id/partId, versioning, rendering dispatch) is
 *      inherited from AbstractProductIndication.sol. This contract only adds the
 *      curve data model, typed publish/quote mutators, the category constant,
 *      and the XML rendering hook.
 *
 *      PUBLISH-OVERWRITES: publishCurveIndications sets the active board to
 *      exactly the provided quote set; previously-active symbols not in the
 *      new set are withdrawn.
 *
 * @author Raphael Prandtl
 */
contract CurveIndications is AbstractProductIndication {

    // ------------------------------ Constants ------------------------------ */

    /// @dev Canonical indication category owned and exposed by this contract.
    bytes32 private constant INDICATION_CATEGORY = keccak256("CURVE");

    /// @notice Max number of simultaneously active quotes per curve.
    uint256 public constant MAX_ACTIVE_QUOTES = 20;

    // ------------------------------ Enums ------------------------------ */

    /**
     * @notice Lifecycle status of an individual quote within a curve.
     * @dev `Unknown` = never created; `Withdrawn` quotes retain their last data
     *      but are excluded from the active board and rendering.
     */
    enum QuoteStatus {
        Unknown,
        Active,
        Withdrawn
    }

    // ------------------------------ Structs ------------------------------ */

    /// @notice Raw quote data submitted by the owner.
    struct QuoteParams {
        string symbol;
        int256 durationInDays;
        uint256 settlementDate;
        uint256 maturityDate;
        string dayCountConvention;
        uint256 couponRateBps;
        string currency;
        int256 yieldBps;
        uint256 issuePriceE8;
        uint256 redemptionValueE8;
        uint256 minNotionalE8;
        uint256 maxNotionalE8;
    }

    struct QuoteStorage {
        QuoteStatus status;
        uint64 updatedAt;
        uint256 quoteVersion;
        string symbol;
        int256 durationInDays;
        uint256 settlementDate;
        uint256 maturityDate;
        string dayCountConvention;
        uint256 couponRateBps;
        string currency;
        int256 yieldBps;
        uint256 issuePriceE8;
        uint256 redemptionValueE8;
        uint256 minNotionalE8;
        uint256 maxNotionalE8;
    }

    /**
     * @notice Flattened, render-friendly view of an active quote.
     * @dev ABI: tuple(string,int256,uint256,uint256,string,uint256,string,int256,uint256,uint256,uint256,uint256)
     */
    struct QuoteView {
        string  symbol;              // field 0
        int256  durationInDays;      // field 1
        uint256 settlementDate;      // field 2
        uint256 maturityDate;        // field 3
        string  dayCountConvention;  // field 4
        uint256 couponRateBps;       // field 5
        string  currency;            // field 6
        int256  yieldBps;            // field 7
        uint256 issuePriceE8;        // field 8
        uint256 redemptionValueE8;   // field 9
        uint256 minNotionalE8;       // field 10
        uint256 maxNotionalE8;       // field 11
    }

    /**
     * @dev Curve payload keyed by the same indicationId (curveId).
     *      Withdrawn quotes stay in quotesBySymbol so they can be
     *      reactivated with their history.
     */
    struct CurvePayload {
        string[] activeSymbols;
        mapping(bytes32 => uint256) activeIndexPlusOne; // symbolId -> index+1 in activeSymbols
        mapping(bytes32 => QuoteStorage) quotesBySymbol; // symbolId -> quote
    }

    mapping(bytes32 => CurvePayload) private _payloads;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required string argument is empty.
    error EmptyString(string field);

    /**
     * @notice Thrown when a string contains a character outside the allowed
     *         XML-safe whitelist (A-Z a-z 0-9 . _ - / and space).
     */
    error InvalidCharacter(string field);

    /// @notice Thrown when a curve is published with an empty quote set.
    error EmptyQuotes();

    /// @notice Thrown when the number of quotes exceeds MAX_ACTIVE_QUOTES.
    error TooManyQuotes(uint256 count);

    /**
     * @notice Thrown when the same symbol appears more than once in a
     *         single publish input.
     */
    error DuplicateQuoteSymbol(string symbol);

    /// @notice Thrown when referencing a quote that does not exist on the curve.
    error UnknownQuote(bytes32 curveId, string symbol);

    /// @notice Thrown when adding a quote whose symbol is already active.
    error QuoteAlreadyActive(bytes32 curveId, string symbol);

    /**
     * @notice Thrown when an operation requires an active quote but the quote
     *         is not active (unknown or withdrawn).
     */
    error QuoteNotActive(bytes32 curveId, string symbol);

    // ------------------------------ Events ------------------------------ */

    /**
     * @notice Emitted when a new quote is added to an existing curve
     *         (including reactivation of a previously withdrawn quote).
     */
    event CurveQuoteAdded(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /// @notice Emitted when an existing active quote's data is updated.
    event CurveQuoteUpdated(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /// @notice Emitted when an active quote is withdrawn from a curve.
    event CurveQuoteWithdrawn(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to publish and manage curves.
    constructor(address owner_) AbstractProductIndication(owner_) {}

    // ------------------------------ Publishing / Quotes ------------------------------ */

    /**
     * @notice Publishes (or fully re-publishes) a curve's active quote board.
     * @dev Creates the curve on first use; on re-publish the curve must be
     *      writable (Active or Suspended). The active board becomes exactly
     *      `quotes`; previously-active symbols absent from `quotes` are
     *      withdrawn.
     * @return curveId The derived indication id.
     */
    function publishCurveIndications(string calldata curveName, QuoteParams[] calldata quotes) external onlyOwner returns (bytes32 curveId) {
        _validateCurveName(curveName);
        _validateQuoteInputs(quotes);
        _validateNoDuplicateSymbols(quotes);

        curveId = _indicationIdFromName(curveName);
        IndicationCore storage core = _openForPublish(curveId);
        CurvePayload storage payload = _payloads[curveId];

        // Withdraw currently-active symbols that are not in the new input.
        // Snapshot to memory so we can mutate the storage list while iterating.
        string[] memory current = payload.activeSymbols;
        for (uint256 i; i < current.length; ++i) {
            if (!_inputContainsSymbol(quotes, current[i])) {
                _withdrawQuote(curveId, payload, current[i]);
            }
        }

        // Upsert all new quotes (retained symbols stay active and are updated).
        for (uint256 i; i < quotes.length; ++i) {
            _upsertQuote(payload, quotes[i]);
        }

        _touchIndication(curveId, core);
    }

    /**
     * @notice Adds a quote to an existing curve (may reactivate a withdrawn one).
     * @dev Reverts if the symbol is already active.
     */
    function addCurveQuote(bytes32 curveId, QuoteParams calldata params) external onlyOwner {
        IndicationCore storage core = _existingCore(curveId);
        _ensureWritable(curveId, core.status);

        CurvePayload storage payload = _payloads[curveId];
        bytes32 symbolId = _symbolId(params.symbol);
        if (payload.quotesBySymbol[symbolId].status == QuoteStatus.Active) {
            revert QuoteAlreadyActive(curveId, params.symbol);
        }

        uint256 quoteVersion = _upsertQuote(payload, params);
        _touchIndication(curveId, core);

        emit CurveQuoteAdded(curveId, symbolId, params.symbol, quoteVersion);
    }

    /// @notice Updates an already-active quote.
    function updateCurveQuote(bytes32 curveId, QuoteParams calldata params) external onlyOwner {
        IndicationCore storage core = _existingCore(curveId);
        _ensureWritable(curveId, core.status);

        CurvePayload storage payload = _payloads[curveId];
        bytes32 symbolId = _symbolId(params.symbol);
        QuoteStatus status = payload.quotesBySymbol[symbolId].status;
        if (status == QuoteStatus.Unknown) revert UnknownQuote(curveId, params.symbol);
        if (status != QuoteStatus.Active) revert QuoteNotActive(curveId, params.symbol);

        uint256 quoteVersion = _upsertQuote(payload, params);
        _touchIndication(curveId, core);

        emit CurveQuoteUpdated(curveId, symbolId, params.symbol, quoteVersion);
    }

    /// @notice Withdraws an active quote from a curve.
    function withdrawCurveQuote(bytes32 curveId, string calldata symbol) external onlyOwner {
        IndicationCore storage core = _existingCore(curveId);
        _ensureWritable(curveId, core.status);

        CurvePayload storage payload = _payloads[curveId];
        uint256 quoteVersion = _withdrawQuote(curveId, payload, symbol);
        _touchIndication(curveId, core);

        emit CurveQuoteWithdrawn(curveId, _symbolId(symbol), symbol, quoteVersion);
    }

    // ------------------------------ Hooks ------------------------------ */

    /// @inheritdoc AbstractProductIndication
    function indicationCategory() external pure override returns (bytes32) {
        return INDICATION_CATEGORY;
    }

    // ------------------------------ XML View ------------------------------ */

    /**
     * @dev Thin template: curve-level metadata bindings + an array-of-struct
     *      binding over activeQuotesByPartId(partId). The renderer supplies the
     *      partId from its render context, clones the <Quote> row per element,
     *      and maps tuple fields via item-field. No per-quote XML is built
     *      on-chain.
     */
    function _indicationStateXml(bytes32) internal pure override returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<CurveIndications xmlns:evmstate=\"urn:evm:state:1.0\">",
            "<Status evmstate:call=\"indicationStatusByPartId(uint256)(uint8)\" evmstate:args=\"$partId\"/>",
            "<ActiveQuoteCount evmstate:call=\"activeQuoteCountByPartId(uint256)(uint256)\"",
            " evmstate:args=\"$partId\" evmstate:format=\"integer\"/>",
            "<Quotes evmstate:call=\"activeQuotesByPartId(uint256)(tuple(string,int256,uint256,uint256,string,uint256,string,int256,uint256,uint256,uint256,uint256)[])\"",
            " evmstate:args=\"$partId\"",
            " evmstate:item-element=\"Quote\">",
            "<Quote>",
            "<Symbol evmstate:item-field=\"0\"/>",
            "<DurationInDays evmstate:item-field=\"1\"/>",
            "<Settlement evmstate:item-field=\"2\" evmstate:format=\"iso8601-datetime\"/>",
            "<Maturity evmstate:item-field=\"3\" evmstate:format=\"iso8601-datetime\"/>",
            "<Convention evmstate:item-field=\"4\"/>",
            "<Coupon evmstate:item-field=\"5\" evmstate:format=\"decimal\" evmstate:scale=\"2\"/>",
            "<Currency evmstate:item-field=\"6\"/>",
            "<Yield evmstate:item-field=\"7\" evmstate:format=\"decimal\" evmstate:scale=\"2\"/>",
            "<IssuePrice evmstate:item-field=\"8\" evmstate:format=\"decimal\" evmstate:scale=\"8\"/>",
            "<RedemptionValue evmstate:item-field=\"9\" evmstate:format=\"decimal\" evmstate:scale=\"8\"/>",
            "<MinNotional evmstate:item-field=\"10\" evmstate:format=\"decimal\" evmstate:scale=\"8\"/>",
            "<MaxNotional evmstate:item-field=\"11\" evmstate:format=\"decimal\" evmstate:scale=\"8\"/>",
            "</Quote>",
            "</Quotes>",
            "</CurveIndications>"
        );
    }

    // ------------------------------ Read API ------------------------------ */

    /// @notice Number of currently active quotes on a curve.
    function activeQuoteCount(bytes32 curveId) external view returns (uint256) {
        return _payloads[curveId].activeSymbols.length;
    }

    /// @notice Number of currently active quotes for a renderer part id.
    function activeQuoteCountByPartId(uint256 partId) external view returns (uint256) {
        bytes32 curveId = _indicationIdFromPartId(partId);
        _existingCore(curveId);
        return _payloads[curveId].activeSymbols.length;
    }

    /// @notice Lifecycle status for a renderer part id.
    function indicationStatusByPartId(uint256 partId) external view returns (IndicationStatus) {
        return _existingCore(_indicationIdFromPartId(partId)).status;
    }

    /// @notice Returns all currently active quotes of a curve as a struct array.
    function activeQuotes(bytes32 curveId) external view returns (QuoteView[] memory) {
        return _activeQuotes(curveId);
    }

    /**
     * @notice Returns active quotes for the renderer-supplied part id.
     * @dev Consumed by the array binding in _indicationStateXml.
     */
    function activeQuotesByPartId(uint256 partId) external view returns (QuoteView[] memory) {
        bytes32 curveId = _indicationIdFromPartId(partId);
        _existingCore(curveId);
        return _activeQuotes(curveId);
    }

    function _activeQuotes(bytes32 curveId) internal view returns (QuoteView[] memory quotes) {
        CurvePayload storage payload = _payloads[curveId];
        uint256 n = payload.activeSymbols.length;
        quotes = new QuoteView[](n);
        for (uint256 i; i < n; ++i) {
            QuoteStorage storage q = payload.quotesBySymbol[_symbolId(payload.activeSymbols[i])];
            quotes[i] = QuoteView({
                symbol: q.symbol,
                durationInDays: q.durationInDays,
                settlementDate: q.settlementDate,
                maturityDate: q.maturityDate,
                dayCountConvention: q.dayCountConvention,
                couponRateBps: q.couponRateBps,
                currency: q.currency,
                yieldBps: q.yieldBps,
                issuePriceE8: q.issuePriceE8,
                redemptionValueE8: q.redemptionValueE8,
                minNotionalE8: q.minNotionalE8,
                maxNotionalE8: q.maxNotionalE8
            });
        }
    }

    // ------------------------------ Internal Mutation Helpers ------------------------------ */

    /// @dev Creates or updates a quote and ensures it is on the active board.
    function _upsertQuote(CurvePayload storage payload, QuoteParams calldata params) internal returns (uint256 quoteVersion) {
        _validateQuoteStrings(params);

        bytes32 symbolId = _symbolId(params.symbol);
        QuoteStorage storage quote = payload.quotesBySymbol[symbolId];

        if (bytes(quote.symbol).length == 0) {
            quote.symbol = params.symbol; // first creation
        }

        quote.status = QuoteStatus.Active;
        quote.updatedAt = uint64(block.timestamp);
        unchecked { quote.quoteVersion += 1; }

        quote.durationInDays = params.durationInDays;
        quote.settlementDate = params.settlementDate;
        quote.maturityDate = params.maturityDate;
        quote.dayCountConvention = params.dayCountConvention;
        quote.couponRateBps = params.couponRateBps;
        quote.currency = params.currency;
        quote.yieldBps = params.yieldBps;
        quote.issuePriceE8 = params.issuePriceE8;
        quote.redemptionValueE8 = params.redemptionValueE8;
        quote.minNotionalE8 = params.minNotionalE8;
        quote.maxNotionalE8 = params.maxNotionalE8;

        _addActiveSymbol(payload, params.symbol, symbolId);

        return quote.quoteVersion;
    }

    /// @dev Withdraws an active quote and removes it from the active board.
    function _withdrawQuote(bytes32 curveId, CurvePayload storage payload, string memory symbol) internal returns (uint256 quoteVersion) {
        bytes32 symbolId = _symbolId(symbol);
        QuoteStorage storage quote = payload.quotesBySymbol[symbolId];

        if (quote.status == QuoteStatus.Unknown) {
            revert UnknownQuote(curveId, symbol);
        }
        if (quote.status != QuoteStatus.Active) {
            revert QuoteNotActive(curveId, symbol);
        }
        quote.status = QuoteStatus.Withdrawn;
        quote.updatedAt = uint64(block.timestamp);
        unchecked { quote.quoteVersion += 1; }

        _removeActiveSymbol(payload, symbolId);

        return quote.quoteVersion;
    }

    function _addActiveSymbol(CurvePayload storage payload, string memory symbol, bytes32 symbolId) internal {
        if (payload.activeIndexPlusOne[symbolId] != 0) {
            return; // already active
        }
        if (payload.activeSymbols.length >= MAX_ACTIVE_QUOTES) {
            revert TooManyQuotes(payload.activeSymbols.length + 1);
        }
        payload.activeSymbols.push(symbol);
        payload.activeIndexPlusOne[symbolId] = payload.activeSymbols.length;
    }

    function _removeActiveSymbol(CurvePayload storage payload, bytes32 symbolId) internal {
        uint256 indexPlusOne = payload.activeIndexPlusOne[symbolId];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = payload.activeSymbols.length - 1;

        if (index != lastIndex) {
            string memory lastSymbol = payload.activeSymbols[lastIndex];
            payload.activeSymbols[index] = lastSymbol;
            payload.activeIndexPlusOne[_symbolId(lastSymbol)] = index + 1;
        }

        payload.activeSymbols.pop();
        delete payload.activeIndexPlusOne[symbolId];
    }

    // ------------------------------ Internal Key / Hash Logic ------------------------------ */

    /// @dev Curve-scoped symbol key
    function _symbolId(string memory symbol) internal pure returns (bytes32) {
        return keccak256(bytes(symbol));
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    function _validateCurveName(string calldata curveName) internal pure {
        if (bytes(curveName).length == 0) revert EmptyString("curveName");
    }

    function _validateQuoteInputs(QuoteParams[] calldata quotes) internal pure {
        if (quotes.length == 0) revert EmptyQuotes();
        if (quotes.length > MAX_ACTIVE_QUOTES) revert TooManyQuotes(quotes.length);
    }

    function _validateQuoteStrings(QuoteParams calldata params) internal pure {
        if (bytes(params.symbol).length == 0) revert EmptyString("symbol");
        _requireXmlSafe(params.symbol, "symbol");
        _requireXmlSafe(params.currency, "currency");
        _requireXmlSafe(params.dayCountConvention, "dayCountConvention");
    }

    function _validateNoDuplicateSymbols(QuoteParams[] calldata quotes) internal pure {
        for (uint256 i; i < quotes.length; ++i) {
            bytes32 left = keccak256(bytes(quotes[i].symbol));
            for (uint256 j = i + 1; j < quotes.length; ++j) {
                if (left == keccak256(bytes(quotes[j].symbol))) {
                    revert DuplicateQuoteSymbol(quotes[i].symbol);
                }
            }
        }
    }

    function _inputContainsSymbol(QuoteParams[] calldata quotes, string memory symbol) internal pure returns (bool) {
        bytes32 key = keccak256(bytes(symbol));
        for (uint256 i; i < quotes.length; ++i) {
            if (key == keccak256(bytes(quotes[i].symbol))) return true;
        }
        return false;
    }

    /**
     * @dev Strict write-time charset guard so rendered XML stays well-formed.
     *      Allowed: A-Z a-z 0-9 . _ - / and space. Rejects XML-significant
     *      characters (< > & " ') and anything else outside the whitelist.
     */
    function _requireXmlSafe(string memory value, string memory field) internal pure {
        bytes memory b = bytes(value);
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            bool ok =
                (c >= 0x30 && c <= 0x39) || // 0-9
                (c >= 0x41 && c <= 0x5A) || // A-Z
                (c >= 0x61 && c <= 0x7A) || // a-z
                c == 0x2E ||                 // .
                c == 0x5F ||                 // _
                c == 0x2D ||                 // -
                c == 0x2F ||                 // /
                c == 0x20;                   // space
            if (!ok) revert InvalidCharacter(field);
        }
    }

}
