// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ITextResource.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title TextResourceCancun.sol
 * @notice Immutable on-chain storage for a text resource (e.g. XML / XSLT)
 *         that can be referenced and reused by multiple products via a registry.
 *
 * @dev PUBLISHING MODES
 *      1. One-shot  – pass the full content to the constructor. It is chunked,
 *                     hash-verified and finalized atomically in a single tx.
 *                     Limited by the EIP-3860 init-code size limit (~49 KB),
 *                     so suitable for small to medium resources.
 *      2. Staged    – deploy with empty content, then append chunks across
 *                     several transactions via appendChunk and finalize() at
 *                     the end. Use this for large resources.
 *
 * @dev GAS / MEMORY LIMITATIONS
 *      Staged publishing splits writes across transactions, but this
 *      implementation still reconstructs the full content in memory when
 *      finalize(), content(), or text() is called. Therefore, staged publishing
 *      helps with upload transaction size, but it does not make arbitrarily
 *      large resources practical.
 *
 * @dev CONTENT HASH SCHEME (see ITextResource):
 *      contentHash == keccak256(content())
 *      The hash is verified ON-CHAIN at finalization against the caller-
 *      supplied expected hash, so contentHash() is always reproducible
 *      off-chain from the raw bytes (frontend integrity check).
 *
 * @dev EVM TARGET: relies on the MCOPY opcode (EIP-5656). Must be compiled
 *      and deployed with the Cancun (or later) EVM version.
 *
 * @author Raphael Prandtl
 **/
contract TextResourceCancun is ITextResource {
    /*
     * Constants
     */

    /**
     * @notice Maximum total content size in bytes.
     **/
    uint256 public constant MAX_CONTENT_SIZE = 200_000;

    /**
     * @notice Maximum size of a single chunk in bytes.
     * @dev Bounded by the SSTORE2 / contract-code size limit (24_576 bytes).
     **/
    uint256 public constant MAX_CHUNK_SIZE = 20_000;

    /*
     * Storage
     */

    /**
     * @dev SSTORE2 storage pointers, in content order.
     **/
    address[] internal _pointers;

    address public immutable owner;
    bytes32 public immutable resourceType;
    string public mediaType;

    bytes32 public contentHash;
    uint256 public contentLength;

    /*
     * Custom errors
     */

    /**
     * @notice Thrown when an empty chunk is appended.
     **/
    error EmptyChunk(uint256 index);

    /**
     * @notice Thrown when the content exceeds MAX_CONTENT_SIZE.
     **/
    error ContentTooLarge(uint256 length, uint256 maxLength);

    /**
     * @notice Thrown when a chunk exceeds MAX_CHUNK_SIZE.
     **/
    error ChunkTooLarge(uint256 index, uint256 length, uint256 maxLength);

    /*
     * Events
     */

    /**
     * @notice Content chunk appended
     **/
    event ChunkAppended(address indexed sender, address indexed pointer, uint256 chunkIndex, uint256 chunkLength);

    /*
     * Constructor / modifiers
     */

    /**
     * @notice Deploys a text resource, optionally publishing content one-shot.
     * @param owner_               Address authorized to publish / finalize.
     * @param resourceType_        Application-defined resource type.
     * @param mediaType_           IANA media type, e.g. "application/xml".
     * @param content_             Full content for one-shot mode, or empty
     *                             bytes to publish later via the staged API.
     * @param expectedContentHash_ Required iff content_ is non-empty; verified
     *                             on-chain as keccak256(content_).
     **/
    constructor(address owner_, bytes32 resourceType_, string memory mediaType_, bytes memory content_, bytes32 expectedContentHash_) {
        if (owner_ == address(0)) revert ZeroOwner();
        if (resourceType_ == bytes32(0)) revert ZeroResourceType();
        if (bytes(mediaType_).length == 0) revert EmptyMediaType();

        owner = owner_;
        resourceType = resourceType_;
        mediaType = mediaType_;

        // One-shot mode: publish and finalize atomically.
        if (content_.length != 0) {
            _appendContentInChunks(content_);
            _finalize(expectedContentHash_);
        }
        // Otherwise: staged mode – content is appended later by the owner.
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier onlyBeforeFinalized() {
        if (contentHash != bytes32(0)) revert AlreadyFinalized();
        _;
    }

    /*
     * Resource publishing
     */

    /**
     * @notice Appends a single pre-chunked data segment (staged mode).
     * @dev Caller is responsible for splitting data into MAX_CHUNK_SIZE pieces.
     **/
    function appendChunk(bytes calldata chunk) external onlyOwner onlyBeforeFinalized {
        _appendChunk(chunk);
    }

    /**
     * @notice Finalizes the resource and locks it as immutable (staged mode).
     * @param expectedContentHash Hash the caller expects; verified on-chain
     *        as keccak256 of the full stored content.
     **/
    function finalize(bytes32 expectedContentHash) external onlyOwner onlyBeforeFinalized {
        _finalize(expectedContentHash);
    }

    /*
     * ERC-165
     */

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(ITextResource).interfaceId;
    }

    /*
     * Metadata / state
     */

    function isFinalized() external view virtual override returns (bool) {
        return contentHash != bytes32(0);
    }

    /**
     * @notice Returns the number of stored chunks.
     **/
    function chunkCount() external view returns (uint256) {
        return _pointers.length;
    }

    /*
     * Content read
     */

    function content() external view virtual override returns (bytes memory) {
        _requireFinalized();
        return _readContent();
    }

    function text() external view virtual override returns (string memory) {
        _requireFinalized();
        return string(_readContent());
    }

    /*
     * Internal write helpers
     */

    /**
     * @notice Appends a single pre-chunked data segment.
     **/
    function _appendChunk(bytes memory chunk_) private {
        uint256 index = _pointers.length;
        uint256 chunkLength = chunk_.length;

        if (chunkLength == 0) {
            revert EmptyChunk(index);
        }
        if (chunkLength > MAX_CHUNK_SIZE) {
            revert ChunkTooLarge(index, chunkLength, MAX_CHUNK_SIZE);
        }
        uint256 newContentLength = contentLength + chunkLength;
        if (newContentLength > MAX_CONTENT_SIZE) {
            revert ContentTooLarge(newContentLength, MAX_CONTENT_SIZE);
        }
        address pointer = SSTORE2.write(chunk_);
        _pointers.push(pointer);
        contentLength = newContentLength;

        emit ChunkAppended(msg.sender, pointer, index, chunkLength);
    }

    /**
     * @notice Splits full content into MAX_CHUNK_SIZE segments and appends them.
     **/
    function _appendContentInChunks(bytes memory content_) private {
        uint256 totalLength = content_.length;
        if (totalLength == 0) revert EmptyContent();

        uint256 offset;
        while (offset < totalLength) {
            uint256 remaining = totalLength - offset;
            uint256 chunkLength = remaining > MAX_CHUNK_SIZE ? MAX_CHUNK_SIZE : remaining;

            bytes memory chunk = new bytes(chunkLength);
            assembly {
                mcopy(add(chunk, 32), add(add(content_, 32), offset), chunkLength)
            }

            _appendChunk(chunk);
            unchecked { offset += chunkLength; }
        }
    }

    /**
     * @dev Recomputes keccak256 over the full stored content and verifies it
     *      against the caller-supplied expected hash.
     **/
    function _finalize(bytes32 expectedContentHash) private {
        if (_pointers.length == 0 || contentLength == 0) revert EmptyContent();
        if (expectedContentHash == bytes32(0)) revert ZeroContentHash();

        bytes32 computedHash = keccak256(_readContent());
        if (computedHash != expectedContentHash) {
            revert ContentHashMismatch(expectedContentHash, computedHash);
        }

        contentHash = computedHash;

        emit ResourceFinalized(resourceType, contentLength, computedHash);
    }

    /*
     * Internal read helpers
     */

    /**
     * @notice Reconstructs the full content from all chunks.
     **/
    function _readContent() private view returns (bytes memory result) {
        result = new bytes(contentLength);

        uint256 offset;
        uint256 pointersLength = _pointers.length;
        for (uint256 i; i < pointersLength; ) {
            address pointer = _pointers[i];
            uint256 chunkLength;

            assembly ("memory-safe") {
                // SSTORE2 prefixes the stored data with one STOP byte.
                chunkLength := sub(extcodesize(pointer), 1)
                extcodecopy(pointer, add(add(result, 0x20), offset), 1, chunkLength)
            }

            unchecked {
                offset += chunkLength;
                ++i;
            }
        }
    }

    /*
     * Internal validation helpers
     */

    function _requireFinalized() private view {
        if (contentHash == bytes32(0)) revert NotFinalized();
    }
}
