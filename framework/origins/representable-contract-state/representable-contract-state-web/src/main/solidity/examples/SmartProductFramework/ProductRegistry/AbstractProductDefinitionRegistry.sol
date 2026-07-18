// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductDefinitionRegistry} from "./IProductDefinitionRegistry.sol";
import {ITextResource} from "../TextResource/ITextResource.sol";
import {IXMLRepresentableStatePart} from "../../../IRepresentableState.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";


/**
 * @title AbstractProductDefinitionRegistry.sol
 * @notice Layer 1: completes the product definition publication lifecycle on
 *         top of the IProductDefinitionRegistry base interface.
 *         Product-agnostic; product-specific rules, such as accepted resource
 *         types, are supplied by the concrete contract via
 *         _isAcceptedResourceType.
 *
 * @dev PRODUCT DEFINITION ID / PART ID
 *      productDefinitionId == keccak256(abi.encode(name, address(this)))
 *      partId    == uint256(productDefinitionId)   (bijective; not stored)
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProductDefinitionRegistry is IProductDefinitionRegistry, IXMLRepresentableStatePart, Ownable2Step {
    using Strings for uint256;
    using Strings for address;

    // ------------------------------ Enums ------------------------------ */

    /// @notice Logical slot a resource occupies within a product definition.
    enum ResourceSlot {
        Unknown,
        ProductTermsTemplate,
        ProductDocumentationTemplate
    }

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice ERC-8100: requested partId does not map to a known product definition.
    error UnknownPart(uint256 partId);

    /// @notice Resource address has no contract code.
    error InvalidResourceContract(address resource);

    /// @notice Resource does not implement the ITextResource interface.
    error InvalidResourceInterface(address resource);

    /// @notice Resource is not finalized (and thus not immutable).
    error ResourceNotFinalized(address resource);

    /// @notice Resource type is not accepted for the given slot.
    error InvalidResourceType(address resource, ResourceSlot slot, bytes32 actualResourceType);

    // ------------------------------ Events ------------------------------ */

    /// @notice Generic ERC-8100-style state-part update event.
    event StatePartUpdated(address indexed sender, address indexed stateContract, uint256 indexed partId, uint256 partVersion);

    // ------------------------------ Storage ------------------------------ */

    /// @dev partId is not stored because it is derivable from the key.
    struct ProductDefinitionStorage {
        ProductDefinitionStatus status;
        uint64 publishedAt;
        uint64 updatedAt;
        string name;
        uint256 version;
        ProductDefinitionResources resources;
    }


    mapping(bytes32 => ProductDefinitionStorage) internal _productDefinitionsById;

    // ------------------------------ Constructor ------------------------------ */

    /// @param owner_ Initial owner authorized to manage product definitions.
    constructor(address owner_) Ownable(owner_) {}

    // ------------------------------ Product Definition Publication and Lifecycle Management ------------------------------ */

    function publishProductDefinition(ProductDefinitionPublicationParams calldata params) external override onlyOwner returns (bytes32 productDefinitionId) {
        _validateProductDefinitionPublicationParams(params);

        productDefinitionId = _productDefinitionId(params.name);
        ProductDefinitionStorage storage definition = _productDefinitionsById[productDefinitionId];
        if (definition.status != ProductDefinitionStatus.Unknown) {
            revert ProductDefinitionAlreadyExists(productDefinitionId);
        }

        definition.status = ProductDefinitionStatus.Active;
        definition.name = params.name;
        definition.publishedAt = uint64(block.timestamp);
        definition.resources = params.resources;

        _touchProductDefinition(definition);

        emit ProductDefinitionPublished(productDefinitionId, params.resources.productTypeId, params.resources.productTermsTemplate, params.resources.productDocumentationTemplate);
        emit ProductDefinitionStatusChanged(productDefinitionId, ProductDefinitionStatus.Unknown, ProductDefinitionStatus.Active);
        emit StatePartUpdated(msg.sender, address(this),             _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    function updateProductDefinitionResources(bytes32 productDefinitionId, ProductDefinitionResources calldata resources) external override onlyOwner {
        _validateProductDefinitionResources(resources);

        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        _ensureProductDefinitionWritable(productDefinitionId, definition.status);

        definition.resources = resources;
        _touchProductDefinition(definition);

        emit ProductDefinitionResourcesUpdated(productDefinitionId, resources.productTypeId, resources.productTermsTemplate, resources.productDocumentationTemplate, definition.version);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    function setProductDefinitionStatus(bytes32 productDefinitionId, ProductDefinitionStatus newStatus) external override onlyOwner {
        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        ProductDefinitionStatus oldStatus = definition.status;

        if (oldStatus == newStatus) {
            return;
        }
        _validateStatusTransition(oldStatus, newStatus);

        definition.status = newStatus;
        _touchProductDefinition(definition);

        emit ProductDefinitionStatusChanged(productDefinitionId, oldStatus, newStatus);
        emit StatePartUpdated(msg.sender, address(this), _partIdFromProductDefinitionId(productDefinitionId), definition.version);
    }

    // ------------------------------ Product Definition Read API ------------------------------ */

    function getProductDefinition(bytes32 productDefinitionId) external view override returns (ProductDefinitionView memory) {
        ProductDefinitionStorage storage definition = _existingProductDefinition(productDefinitionId);
        return ProductDefinitionView({
            status: definition.status,
            publishedAt: definition.publishedAt,
            updatedAt: definition.updatedAt,
            name: definition.name,
            partId: _partIdFromProductDefinitionId(productDefinitionId),
            version: definition.version,
            resources: definition.resources
        });
    }

    function getProductDefinitionStatus(bytes32 productDefinitionId) external view override returns (ProductDefinitionStatus) {
        return _productDefinitionsById[productDefinitionId].status;
    }

    function productTypeByDefinitionId(bytes32 productDefinitionId) external view override returns (bytes32 productTypeId) {
        return _existingProductDefinition(productDefinitionId).resources.productTypeId;
    }

    // ------------------------------ XML View ------------------------------ */

    function statePartXmlTemplate(uint256 partId) external view override returns (string memory) {
        bytes32 productDefinitionId = _productDefinitionIdFromPartId(partId);
        ProductDefinitionStorage storage definition = _productDefinitionsById[productDefinitionId];
        if (definition.status == ProductDefinitionStatus.Unknown) {
            revert UnknownPart(partId);
        }
        return _productDefinitionStateXml(productDefinitionId, definition);
    }


    /**
     * @dev The registry only anchors the product terms template and product
     *      documentation template; it does not resolve
     *      the `evmstate:call` bindings itself (those are served by the deployed
     *      product implementing the declared product type interface).
     */
    function _productDefinitionStateXml(bytes32 productDefinitionId, ProductDefinitionStorage storage definition) internal view returns (string memory) {
        return string.concat(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<ProductDefinition xmlns:xi=\"http://www.w3.org/2001/XInclude\"",
            " xmlns:evmstate=\"urn:evm:state:1.0\"",
            " productDefinitionId=\"", _bytes32ToHexString(productDefinitionId), "\"",
            " status=\"", uint256(definition.status).toString(), "\"",
            " productDefinitionVersion=\"", definition.version.toString(), "\"",
            " updatedAt=\"", uint256(definition.updatedAt).toString(), "\"",
            ">",
            _include(definition.resources.productTermsTemplate),
            _include(definition.resources.productDocumentationTemplate),
            "</ProductDefinition>"
        );
    }

    function _include(address resource) internal view returns (string memory) {
        ITextResource textResource = ITextResource(resource);
        string memory href = string.concat(
            "web3://", resource.toHexString(), ":", block.chainid.toString(), "/text"
        );
        string memory integrity = string.concat(
            "keccak256-", _bytes32ToHexString(textResource.contentHash())
        );
        return string.concat(
            "<xi:include href=\"", href,
            "\" parse=\"text\" evmstate:integrity=\"", integrity, "\"/>"
        );
    }

    // ------------------------------ Internal Key / Hash Logic ------------------------------ */

    function computeProductDefinitionId(string calldata name) external view override returns (bytes32 productDefinitionId) {
        return _productDefinitionId(name);
    }

    function _productDefinitionId(string memory name) internal view returns (bytes32) {
        return keccak256(abi.encode(name, address(this)));
    }

    function _productDefinitionIdFromPartId(uint256 partId) internal pure returns (bytes32) {
        return bytes32(partId);
    }

    function _partIdFromProductDefinitionId(bytes32 productDefinitionId) internal pure returns (uint256) {
        return uint256(productDefinitionId);
    }

    function _touchProductDefinition(ProductDefinitionStorage storage definition) internal {
        unchecked { definition.version += 1; }
        definition.updatedAt = uint64(block.timestamp);
    }

    // ------------------------------ Validation Helpers ------------------------------ */

    function _existingProductDefinition(bytes32 productDefinitionId) internal view returns (ProductDefinitionStorage storage definition) {
        definition = _productDefinitionsById[productDefinitionId];
        if (definition.status == ProductDefinitionStatus.Unknown) {
            revert UnknownProductDefinition(productDefinitionId);
        }
    }

    function _ensureProductDefinitionWritable(bytes32 productDefinitionId, ProductDefinitionStatus status) internal pure {
        if (status == ProductDefinitionStatus.Retired || status == ProductDefinitionStatus.Archived) {
            revert ProductDefinitionNotWritable(productDefinitionId, status);
        }
    }

    /**
     * @dev Allowed transitions:
     *      Active    -> Suspended | Closed
     *      Suspended -> Active | Closed
     *      Closed    -> Archived
     *      Archived  -> (terminal)
     */
    function _validateStatusTransition(ProductDefinitionStatus  oldStatus, ProductDefinitionStatus  newStatus) internal pure {
        if (newStatus == ProductDefinitionStatus .Unknown) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == ProductDefinitionStatus .Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
        if (oldStatus == ProductDefinitionStatus .Retired && newStatus != ProductDefinitionStatus .Archived) {
            revert InvalidStatusTransition(oldStatus, newStatus);
        }
    }

    function _validateProductDefinitionPublicationParams(ProductDefinitionPublicationParams calldata params) internal view {
        if (bytes(params.name).length == 0) {
            revert EmptyString("name");
        }
        _validateProductDefinitionResources(params.resources);
    }

    function _validateProductDefinitionResources(ProductDefinitionResources calldata resources) internal view {
        _validateTextResource(resources.productTermsTemplate, ResourceSlot.ProductTermsTemplate);
        _validateTextResource(resources.productDocumentationTemplate, ResourceSlot.ProductDocumentationTemplate);

        if (resources.productTypeId == bytes32(0)) {
            revert ZeroHash("productTypeId");
        }
    }

    function _validateTextResource(address resource, ResourceSlot slot) internal view {
        if (resource == address(0)) {
            revert ZeroAddress("resource");
        }
        if (resource.code.length == 0) {
            revert InvalidResourceContract(resource);
        }

        // Must advertise ITextResource via ERC-165.
        try IERC165(resource).supportsInterface(type(ITextResource).interfaceId) returns (bool ok) {
            if (!ok) {
                revert InvalidResourceInterface(resource);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }

        ITextResource textResource = ITextResource(resource);

        // Must be finalized (immutable).
        try textResource.isFinalized() returns (bool finalized) {
            if (!finalized) {
                revert ResourceNotFinalized(resource);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }

        // Must carry an accepted resource type for this slot.
        try textResource.resourceType() returns (bytes32 actualResourceType) {
            if (!_isAcceptedResourceType(slot, actualResourceType)) {
                revert InvalidResourceType(resource, slot, actualResourceType);
            }
        } catch {
            revert InvalidResourceInterface(resource);
        }
    }

    // ------------------------------ Final-Contract Hook ------------------------------ */

    /// @dev Product-specific rule: which resource types are accepted per slot.
    function _isAcceptedResourceType(ResourceSlot slot, bytes32 resourceType) internal view virtual returns (bool);

    // ------------------------------ String Helpers ------------------------------ */

    function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        return uint256(value).toHexString(32);
    }

}
