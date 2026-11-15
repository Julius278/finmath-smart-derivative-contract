// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AbstractProductIndication} from "../AbstractProductIndication.sol";

/**
 * @title CurveIndications
 * @notice Example indication contract managing quote curves.
 *
 * @dev Publishing a curve replaces its active quote set. Quotes omitted from
 *      a later publication are withdrawn but remain stored. Curve version tracks
 *      quote publications and active-set changes; quoteVersion tracks the quote's
 *      published parameters and is preserved when that quote is withdrawn.
 *
 * @author Raphael Prandtl
 */
contract CurveIndications is AbstractProductIndication {
    // ------------------------------ Constants ------------------------------ */

    /// @notice Indication category exposed by this contract.
    bytes32 private constant INDICATION_CATEGORY = keccak256("CURVE");

    /// @notice Maximum number of active quotes per curve.
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

    /// @notice Parameters used to publish or update a quote.
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

    /// @dev Stored quote state. quoteVersion tracks parameter publications;
    ///      updatedAt also tracks withdrawal without changing those parameters.
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
     * @notice Active quote representation returned by the read API.
     * @dev Field order is used by the XML renderer.
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

    /// @notice Fixed-size discovery summary, including withdrawn quotes.
    /// @dev Status is independent of the parent lifecycle; withdrawal preserves quoteVersion.
    struct QuoteState {
        bytes32 symbolId;
        QuoteStatus status;
        uint64 updatedAt;
        uint256 quoteVersion;
    }

    /// @dev Curve-specific quote storage.
    struct CurvePayload {
        string[] activeSymbols;
        mapping(bytes32 symbolId => uint256 indexPlusOne) activeIndexPlusOne;
        mapping(bytes32 symbolId => QuoteStorage quote) quotesBySymbol;
        bytes32[] symbolIds;
        string name;
    }

    mapping(bytes32 curveId => CurvePayload payload) private _payloads;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required string is empty.
    error EmptyString(string field);

    /// @notice Thrown when a string contains an unsupported character.
    error InvalidCharacter(string field);

    /// @notice Thrown when a curve is published without quotes.
    error EmptyQuotes();

    /// @notice Thrown when the active quote limit is exceeded.
    error TooManyQuotes(uint256 count);

    /// @notice Thrown when a symbol occurs more than once in one publication.
    error DuplicateQuoteSymbol(string symbol);

    /// @notice Thrown when a quote is not known to the curve.
    error UnknownQuote(bytes32 curveId, string symbol);

    /// @notice Thrown when a quote id is not known to the curve.
    error UnknownQuoteId(bytes32 curveId, bytes32 symbolId);

    /// @notice Thrown when adding a quote that is already active.
    error QuoteAlreadyActive(bytes32 curveId, string symbol);

    /// @notice Thrown when a quote is not active.
    error QuoteNotActive(bytes32 curveId, string symbol);

    // ------------------------------ Events ------------------------------ */

    /// @notice Emitted when a quote is added or reactivated.
    event CurveQuoteAdded(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /// @notice Emitted when an active quote is updated.
    event CurveQuoteUpdated(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    /// @notice Emitted when an active quote is withdrawn.
    event CurveQuoteWithdrawn(bytes32 indexed curveId, bytes32 indexed symbolId, string symbol, uint256 quoteVersion);

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to manage curves.
    constructor(address owner_)AbstractProductIndication(owner_) {}

    // ------------------------------ Curve Management ------------------------------ */

    /**
     * @notice Publishes a new curve or replaces the active quotes of an existing curve.
     * @return curveId Derived indication identifier.
     */
    function publishCurveIndications(string calldata name, QuoteParams[] calldata quotes) external onlyOwner returns (bytes32 curveId) {
        _validateCurveName(name);
        _validateQuoteInputs(quotes);
        _validateNoDuplicateSymbols(quotes);

        curveId = _indicationIdFromName(name);
        IndicationCore storage core = _openForPublish(curveId);
        CurvePayload storage payload = _payloads[curveId];
        if (bytes(payload.name).length == 0) {
            payload.name = name;
        }

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

    /// @notice Adds or reactivates a quote on an existing curve.
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

    /// @notice Updates an active quote.
    function updateCurveQuote(bytes32 curveId, QuoteParams calldata params) external onlyOwner {
        IndicationCore storage core = _existingCore(curveId);
        _ensureWritable(curveId, core.status);

        CurvePayload storage payload = _payloads[curveId];
        bytes32 symbolId = _symbolId(params.symbol);
        QuoteStatus status = payload.quotesBySymbol[symbolId].status;
        if (status == QuoteStatus.Unknown) {
            revert UnknownQuote(curveId, params.symbol);
        }
        if (status != QuoteStatus.Active) {
            revert QuoteNotActive(curveId, params.symbol);
        }

        uint256 quoteVersion = _upsertQuote(payload, params);
        _touchIndication(curveId, core);
        emit CurveQuoteUpdated(curveId, symbolId, params.symbol, quoteVersion);
    }

    /// @notice Withdraws an active quote from a curve.
    /// @dev Changes curve content and version, but retains the quote's parameter version.
    function withdrawCurveQuote(bytes32 curveId, string calldata symbol) external onlyOwner {
        IndicationCore storage core = _existingCore(curveId);
        _ensureWritable(curveId, core.status);

        CurvePayload storage payload = _payloads[curveId];
        uint256 quoteVersion = _withdrawQuote(curveId, payload, symbol);
        _touchIndication(curveId, core);
        emit CurveQuoteWithdrawn(curveId, _symbolId(symbol), symbol, quoteVersion);
    }

    // ------------------------------ Product Indication ------------------------------ */

    /// @inheritdoc AbstractProductIndication
    function indicationCategory() external pure override returns (bytes32) {
        return INDICATION_CATEGORY;
    }

    // ------------------------------ XML View ------------------------------ */

    /// @inheritdoc AbstractProductIndication
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

    /// @notice Returns the original name of a published curve, in any lifecycle status.
    function curveName(bytes32 curveId) external view returns (string memory) {
        _existingCore(curveId);
        return _payloads[curveId].name;
    }

    /// @notice Number of distinct quotes ever published on a curve, including withdrawn quotes.
    function quoteCount(bytes32 curveId) external view returns (uint256) {
        _existingCore(curveId);
        return _payloads[curveId].symbolIds.length;
    }

    /**
     * @notice Returns quote summaries in first-publication order, without status filtering.
     * @dev At most min(limit, MAX_DISCOVERY_PAGE_SIZE, remaining) fixed-size entries.
     *      Updates, withdrawals and reactivation never move or duplicate ids. Zero limit or
     *      an offset at/past the end returns an empty page. Pin reads to one block for a snapshot.
     */
    function getQuoteStates(bytes32 curveId, uint256 offset, uint256 limit) external view returns (QuoteState[] memory states) {
        _existingCore(curveId);
        CurvePayload storage payload = _payloads[curveId];
        uint256 count = _discoveryPageLength(payload.symbolIds.length, offset, limit);
        states = new QuoteState[](count);
        for (uint256 i; i < count; ++i) {
            bytes32 symbolId = payload.symbolIds[offset + i];
            QuoteStorage storage quote = payload.quotesBySymbol[symbolId];
            states[i] = QuoteState(symbolId, quote.status, quote.updatedAt, quote.quoteVersion);
        }
    }

    /// @notice Returns the last published data for one active or withdrawn quote.
    /// @dev symbolId is keccak256(bytes(symbol)), also returned by getQuoteStates.
    function quoteById(bytes32 curveId, bytes32 symbolId) external view returns (QuoteView memory) {
        _existingCore(curveId);
        QuoteStorage storage quote = _payloads[curveId].quotesBySymbol[symbolId];
        if (quote.status == QuoteStatus.Unknown) {
            revert UnknownQuoteId(curveId, symbolId);
        }
        return _quoteView(quote);
    }

    /// @notice Returns the number of active quotes on a curve.
    function activeQuoteCount(bytes32 curveId) external view returns (uint256) {
        _existingCore(curveId);
        return _payloads[curveId].activeSymbols.length;
    }

    /// @notice Returns the number of active quotes for a state-part id.
    function activeQuoteCountByPartId(uint256 partId) external view returns (uint256) {
        bytes32 curveId = _indicationIdFromPartId(partId);
        _existingCore(curveId);
        return _payloads[curveId].activeSymbols.length;
    }

    /// @notice Returns the indication status for a state-part id.
    function indicationStatusByPartId(uint256 partId) external view returns (IndicationStatus) {
        return _existingCore(_indicationIdFromPartId(partId)).status;
    }

    /// @notice Returns the active quotes of a curve.
    function activeQuotes(bytes32 curveId) external view returns (QuoteView[] memory) {
        _existingCore(curveId);
        return _activeQuotes(curveId);
    }

    /// @notice Returns active quotes for a state-part id.
    function activeQuotesByPartId(uint256 partId) external view returns (QuoteView[] memory) {
        bytes32 curveId = _indicationIdFromPartId(partId);
        _existingCore(curveId);
        return _activeQuotes(curveId);
    }

    // ------------------------------ Internal Quote Views ------------------------------ */

    function _activeQuotes(bytes32 curveId) internal view returns (QuoteView[] memory quotes) {
        CurvePayload storage payload = _payloads[curveId];
        uint256 count = payload.activeSymbols.length;
        quotes = new QuoteView[](count);
        for (uint256 i; i < count; ++i) {
            QuoteStorage storage quote = payload.quotesBySymbol[_symbolId(payload.activeSymbols[i])];
            quotes[i] = _quoteView(quote);
        }
    }

    function _quoteView(QuoteStorage storage quote) internal view returns (QuoteView memory) {
        return QuoteView({
            symbol: quote.symbol,
            durationInDays: quote.durationInDays,
            settlementDate: quote.settlementDate,
            maturityDate: quote.maturityDate,
            dayCountConvention: quote.dayCountConvention,
            couponRateBps: quote.couponRateBps,
            currency: quote.currency,
            yieldBps: quote.yieldBps,
            issuePriceE8: quote.issuePriceE8,
            redemptionValueE8: quote.redemptionValueE8,
            minNotionalE8: quote.minNotionalE8,
            maxNotionalE8: quote.maxNotionalE8
        });
    }

    // ------------------------------ Internal Mutation Helpers ------------------------------ */

    /// @dev Each parameter publication advances quoteVersion, even for identical input,
    ///      matching explicit content updates in ProductDefinitionRegistry.
    function _upsertQuote(CurvePayload storage payload, QuoteParams calldata params) internal returns (uint256 quoteVersion) {
        _validateQuoteStrings(params);

        bytes32 symbolId = _symbolId(params.symbol);
        QuoteStorage storage quote = payload.quotesBySymbol[symbolId];

        if (quote.status == QuoteStatus.Unknown) {
            payload.symbolIds.push(symbolId);
            quote.symbol = params.symbol;
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

        _removeActiveSymbol(payload, symbolId);
        return quote.quoteVersion;
    }

    function _addActiveSymbol(CurvePayload storage payload, string memory symbol, bytes32 symbolId) internal {
        if (payload.activeIndexPlusOne[symbolId] != 0) {
            return;
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

    // ------------------------------ Internal Id Logic ------------------------------ */

    function _symbolId(string memory symbol) internal pure returns (bytes32) {
        return keccak256(bytes(symbol));
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    function _validateCurveName(string calldata name) internal pure {
        if (bytes(name).length == 0) {
            revert EmptyString("curveName");
        }
    }

    function _validateQuoteInputs(QuoteParams[] calldata quotes) internal pure {
        if (quotes.length == 0) {
            revert EmptyQuotes();
        }
        if (quotes.length > MAX_ACTIVE_QUOTES) {
            revert TooManyQuotes(quotes.length);
        }
    }

    function _validateQuoteStrings(QuoteParams calldata params) internal pure {
        if (bytes(params.symbol).length == 0) {
            revert EmptyString("symbol");
        }
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
        bytes32 symbolId = _symbolId(symbol);
        for (uint256 i; i < quotes.length; ++i) {
            if (symbolId == _symbolId(quotes[i].symbol)) {
                return true;
            }
        }
        return false;
    }

    /// @notice Ensures that a string can be inserted into the XML representation.
    function _requireXmlSafe(string memory value, string memory field) internal pure {
        bytes memory characters = bytes(value);
        for (uint256 i; i < characters.length; ++i) {
            bytes1 character = characters[i];
            bool valid =
                (character >= 0x30 && character <= 0x39) ||
                (character >= 0x41 && character <= 0x5A) ||
                (character >= 0x61 && character <= 0x7A) ||
                character == 0x2E ||
                character == 0x5F ||
                character == 0x2D ||
                character == 0x2F ||
                character == 0x20;
            if (!valid) {
                revert InvalidCharacter(field);
            }
        }
    }
}
