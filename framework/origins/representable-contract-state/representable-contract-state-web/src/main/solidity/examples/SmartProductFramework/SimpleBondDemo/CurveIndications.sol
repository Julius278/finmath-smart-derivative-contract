// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductIndication} from "../ProductIndication/AbstractProductIndication.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CURVE_INDICATION_CATEGORY} from "./BondConstants.sol";

/// @title CurveIndications
/// @notice Concrete indication registry for curve indications (a set of quotes
///         forming an indicative curve for bond-like products).
/// @dev Lifecycle (status, id/partId, versioning, rendering dispatch) is
///      inherited from AbstractProductIndication.sol. This contract only adds the
///      curve data model, typed publish/quote mutators, the category constant,
///      and the XML rendering hook.
///
///      PUBLISH-OVERWRITES: publishCurveIndications sets the active board to
///      exactly the provided quote set; previously-active symbols not in the
///      new set are withdrawn.
///
/// @author Raphael Prandtl
contract CurveIndications is AbstractProductIndication {

    using Strings for uint256;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         CONSTANTS                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Max number of simultaneously active quotes per curve.
    uint256 public constant MAX_ACTIVE_QUOTES = 20;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Lifecycle status of an individual quote within a curve.
    /// @dev `Unknown` = never created; `Withdrawn` quotes retain their last data
    ///      but are excluded from the active board and rendering.
    enum QuoteStatus {
        Unknown,
        Active,
        Withdrawn
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STRUCTS                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

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

    /// @notice Flattened, render-friendly view of an active quote.
    /// @dev ABI: tuple(string,int256,uint256,uint256,string,uint256,string,int256,uint256,uint256,uint256,uint256)
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

    /// @dev Curve payload keyed by the same indicationId (curveId).
    ///      Withdrawn quotes stay in quotesBySymbol so they can be
    ///      reactivated with their history.
    struct CurvePayload {
        string[] activeSymbols;
        mapping(bytes32 => uint256) activeIndexPlusOne; // symbolId -> index+1 in activeSymbols
        mapping(bytes32 => QuoteStorage) quotesBySymbol; // symbolId -> quote
    }

    mapping(bytes32 => CurvePayload) private _payloads;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when a required string argument is empty.
    error EmptyString(string field);

    /// @notice Thrown when a string contains a character outside the allowed
    ///         XML-safe whitelist (A-Z a-z 0-9 . _ - / and space).
    error InvalidCharacter(string field);

    /// @notice Thrown when a curve is published with an empty quote set.
    error EmptyQuotes();

    /// @notice Thrown when the number of quotes exceeds MAX_ACTIVE_QUOTES.
    error TooManyQuotes(uint256 count);

    /// @notice Thrown when the same symbol appears more than once in a
    ///         single publish input.
    error DuplicateQuoteSymbol(string symbol);

    /// @notice Thrown when referencing a quote that does not exist on the curve.
    error UnknownQuote(bytes32 curveId, string symbol);

    /// @notice Thrown when adding a quote whose symbol is already active.
    error QuoteAlreadyActive(bytes32 curveId, string symbol);

    /// @notice Thrown when an operation requires an active quote but the quote
    ///         is not active (unknown or withdrawn).
    error QuoteNotActive(bytes32 curveId, string symbol);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when a new quote is added to an existing curve
    ///         (including reactivation of a previously withdrawn quote).
    event CurveQuoteAdded(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /// @notice Emitted when an existing active quote's data is updated.
    event CurveQuoteUpdated(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /// @notice Emitted when an active quote is withdrawn from a curve.
    event CurveQuoteWithdrawn(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CONSTRUCTOR                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_ Initial owner authorized to publish and manage curves.
    constructor(address owner_) AbstractProductIndication(owner_) {}

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                     PUBLISHING / QUOTES                   */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Publishes (or fully re-publishes) a curve's active quote board.
    /// @dev Creates the curve on first use; on re-publish the curve must be
    ///      writable (Active or Suspended). The active board becomes exactly
    ///      `quotes`; previously-active symbols absent from `quotes` are
    ///      withdrawn.
    /// @return curveId The derived indication id.
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

    /// @notice Adds a quote to an existing curve (may reactivate a withdrawn one).
    /// @dev Reverts if the symbol is already active.
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

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          HOOKS                            */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc AbstractProductIndication
    function indicationCategory() external pure override returns (bytes32) {
        return CURVE_INDICATION_CATEGORY;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          XML VIEW                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc AbstractProductIndication
    /// @dev Materializes the curve state on-chain. This avoids argument-bearing
    ///      `evmstate:call` bindings, which are not supported by the renderer.
    ///      Quote strings are XML-safe because they are validated on write.
    function _indicationStateXml(bytes32 curveId) internal view override returns (string memory) {
        IndicationCore storage core = _core(curveId);
        CurvePayload storage payload = _payloads[curveId];
        string memory curveIdHex = _bytes32ToHexString(curveId);

        string memory quotesXml;
        for (uint256 i; i < payload.activeSymbols.length; ++i) {
            QuoteStorage storage quote = payload.quotesBySymbol[_symbolId(payload.activeSymbols[i])];
            quotesXml = string.concat(quotesXml, _quoteXml(quote));
        }

        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<CurveIndications curveId=\"", curveIdHex, "\">",
            "<Status>", uint256(core.status).toString(), "</Status>",
            "<ActiveQuoteCount>", payload.activeSymbols.length.toString(), "</ActiveQuoteCount>",
            "<Quotes>", quotesXml, "</Quotes>",
            "</CurveIndications>"
        );
    }

    /// @dev Materializes one active quote using the formats previously applied
    ///      by EvmXmlRenderer.
    function _quoteXml(QuoteStorage storage quote) internal view returns (string memory) {
        string memory xml = string.concat(
            "<Quote>",
            "<Symbol>", quote.symbol, "</Symbol>",
            "<DurationInDays>", Strings.toStringSigned(quote.durationInDays), "</DurationInDays>",
            "<Settlement>", _formatIso8601DateTime(quote.settlementDate), "</Settlement>",
            "<Maturity>", _formatIso8601DateTime(quote.maturityDate), "</Maturity>"
        );

        xml = string.concat(
            xml,
            "<Convention>", quote.dayCountConvention, "</Convention>",
            "<Coupon>", _formatDecimal(quote.couponRateBps, 2), "</Coupon>",
            "<Currency>", quote.currency, "</Currency>",
            "<Yield>", _formatSignedDecimal(quote.yieldBps, 2), "</Yield>"
        );

        return string.concat(
            xml,
            "<IssuePrice>", _formatDecimal(quote.issuePriceE8, 8), "</IssuePrice>",
            "<RedemptionValue>", _formatDecimal(quote.redemptionValueE8, 8), "</RedemptionValue>",
            "<MinNotional>", _formatDecimal(quote.minNotionalE8, 8), "</MinNotional>",
            "<MaxNotional>", _formatDecimal(quote.maxNotionalE8, 8), "</MaxNotional>",
            "</Quote>"
        );
    }

    /// @dev Thin template: curve-level metadata bindings + an array-of-struct
    ///      binding over activeQuotes(curveId). The renderer clones the <Quote>
    ///      row per element and maps tuple fields via item-field. No per-quote
    ///      XML is built on-chain.
    function _indicationStateXmlUnsupported(bytes32 curveId) internal pure returns (string memory) {
        string memory curveIdHex = _bytes32ToHexString(curveId);
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<CurveIndications xmlns:evmstate=\"urn:evm:state:1.0\"",
            " curveId=\"", curveIdHex, "\">",
            // curve-level metadata via scalar bindings
            "<Status evmstate:call=\"indicationStatus(bytes32)(uint8)\" evmstate:args=\"", curveIdHex, "\"/>",
            "<ActiveQuoteCount evmstate:call=\"activeQuoteCount(bytes32)(uint256)\" evmstate:args=\"", curveIdHex, "\" evmstate:format=\"integer\"/>",
            // array-of-struct binding: one <Quote> per active quote
            "<Quotes evmstate:call=\"activeQuotes(bytes32)(tuple(string,int256,uint256,uint256,string,uint256,string,int256,uint256,uint256,uint256,uint256)[])\"",
            " evmstate:args=\"", curveIdHex, "\"",
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

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         READ API                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Number of currently active quotes on a curve.
    function activeQuoteCount(bytes32 curveId) external view returns (uint256) {
        return _payloads[curveId].activeSymbols.length;
    }

    /// @notice Returns all currently active quotes of a curve as a struct array.
    /// @dev Kept as a typed read API. XML rendering reads the same storage
    ///      locally because the renderer does not support call arguments.
    /// @dev Consumed by the renderer via
    ///      evmstate:call="activeQuotes(bytes32)(tuple(...)[])" with per-field
    ///      item-field bindings in the curve terms template.
    function activeQuotes(bytes32 curveId) external view returns (QuoteView[] memory quotes) {
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

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  INTERNAL MUTATION HELPERS               */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

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

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  INTERNAL KEY / HASH LOGIC               */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Curve-scoped symbol key
    function _symbolId(string memory symbol) internal pure returns (bytes32) {
        return keccak256(bytes(symbol));
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    VALIDATION HELPERS                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

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

    /// @dev Strict write-time charset guard so rendered XML stays well-formed.
    ///      Allowed: A-Z a-z 0-9 . _ - / and space. Rejects XML-significant
    ///      characters (< > & " ') and anything else outside the whitelist.
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

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       STRING HELPERS                      */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Formats an unsigned fixed-point value like EvmXmlRenderer's
    ///      decimal format. The fractional component is zero-padded to `scale`.
    function _formatDecimal(uint256 value, uint256 scale) internal pure returns (string memory) {
        if (scale == 0) {
            return value.toString();
        }

        uint256 divisor = 10 ** scale;
        return string.concat(
            (value / divisor).toString(),
            ".",
            _leftPadWithZeros((value % divisor).toString(), scale)
        );
    }

    /// @dev Signed variant of _formatDecimal that also handles int256.min.
    function _formatSignedDecimal(int256 value, uint256 scale) internal pure returns (string memory) {
        if (value >= 0) {
            return _formatDecimal(uint256(value), scale);
        }

        uint256 magnitude;
        unchecked {
            magnitude = uint256(-(value + 1)) + 1;
        }
        return string.concat("-", _formatDecimal(magnitude, scale));
    }

    /// @dev Formats a Unix timestamp as the renderer's ISO-8601 UTC datetime.
    function _formatIso8601DateTime(uint256 timestamp) internal pure returns (string memory) {
        uint256 secondsInDay = timestamp % 86_400;
        (uint256 year, uint256 month, uint256 day) = _daysToDate(timestamp / 86_400);

        return string.concat(
            _leftPadWithZeros(year.toString(), 4), "-",
            _leftPadWithZeros(month.toString(), 2), "-",
            _leftPadWithZeros(day.toString(), 2), "T",
            _leftPadWithZeros((secondsInDay / 3_600).toString(), 2), ":",
            _leftPadWithZeros(((secondsInDay % 3_600) / 60).toString(), 2), ":",
            _leftPadWithZeros((secondsInDay % 60).toString(), 2), "Z"
        );
    }

    /// @dev Gregorian calendar conversion for days since 1970-01-01.
    function _daysToDate(uint256 daysSinceEpoch) internal pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 z = daysSinceEpoch + 719_468;
        uint256 era = z / 146_097;
        uint256 dayOfEra = z - era * 146_097;
        uint256 yearOfEra = (
            dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096
        ) / 365;
        uint256 provisionalYear = yearOfEra + era * 400;
        uint256 dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100);
        uint256 monthPrime = (5 * dayOfYear + 2) / 153;

        day = dayOfYear - (153 * monthPrime + 2) / 5 + 1;
        month = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9;
        year = provisionalYear + (month <= 2 ? 1 : 0);
    }

    function _leftPadWithZeros(string memory value, uint256 minimumLength) internal pure returns (string memory) {
        bytes memory source = bytes(value);
        if (source.length >= minimumLength) {
            return value;
        }

        bytes memory padded = new bytes(minimumLength);
        uint256 offset = minimumLength - source.length;
        for (uint256 i; i < offset; ++i) {
            padded[i] = "0";
        }
        for (uint256 i; i < source.length; ++i) {
            padded[offset + i] = source[i];
        }
        return string(padded);
    }

    function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        return uint256(value).toHexString(32);
    }
}
