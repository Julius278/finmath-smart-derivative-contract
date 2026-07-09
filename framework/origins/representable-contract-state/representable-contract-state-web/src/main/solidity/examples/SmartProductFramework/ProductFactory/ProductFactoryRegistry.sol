// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductFactory} from "./IProductFactory.sol";
import {IProductSpecificFactory} from "./IProductFactory.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "./ProductDeploymentTypes.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ProductFactoryRegistry.sol
/// @notice Generic factory-of-factories. Maintains a lifecycle-managed registry
///         of product-specific factories keyed by productTypeId, and forwards
///         registry deployment requests to the resolved factory.
/// @dev Sole caller of deployProduct is the product registry
///      (productRegistryAddress). Product-specific factories are managed by the
///      owner (Ownable2Step).
///
/// @author Raphael Prandtl
contract ProductFactoryRegistry is IProductFactory, Ownable2Step, ReentrancyGuard {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                           ENUMS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Lifecycle status of a registered product-specific factory.
    /// @dev `Unknown` is the default value and the "not registered" sentinel.
    enum ProductFactoryStatus {
        Unknown,
        Active,
        Suspended,
        Deprecated
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       IMMUTABLE STATE                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc IProductFactory
    address public immutable override productRegistryAddress;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STORAGE                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Registration record for a product-specific factory.
    struct ProductFactoryConfig {
        ProductFactoryStatus status;
        uint64 registeredAt;
        uint64 updatedAt;
        address factory;
    }

    /// @dev productTypeId -> product-specific factory registration.
    mapping(bytes32 => ProductFactoryConfig) internal _configs;

    /// @notice Maps a tradeId to the product deployed for it.
    /// @dev Enforces per-trade deployment idempotency and enables lookups.
    mapping(bytes32 => address) public productByTradeId;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when a registration cannot be modified in its current
    ///         status (Deprecated).
    error ProductFactoryConfigNotWritable(bytes32 productTypeId, ProductFactoryStatus status);

    /// @notice Thrown when deployment is attempted for a product type whose
    ///         factory is not active.
    error ProductFactoryNotActive(bytes32 productTypeId, address factory, ProductFactoryStatus status);

    /// @notice Thrown when registering a product type that already has a factory.
    error ProductTypeAlreadyRegistered(bytes32 productTypeId, address factory);

    /// @notice Thrown when a status transition is not allowed
    ///         (e.g. to Unknown, or away from terminal Deprecated).
    error InvalidProductFactoryStatus(ProductFactoryStatus status);

    /// @notice Thrown when a candidate factory is invalid (no code or does not
    ///         implement IProductSpecificFactory).
    error InvalidSpecificFactory(address factory);

    /// @notice Thrown when a factory's self-declared product type does not match
    ///         the product type it is being registered under.
    error FactoryTypeMismatch(bytes32 productTypeId, bytes32 declaredType);

    /// @notice Thrown when a tradeId has already been used for a deployment.
    error TradeIdAlreadyUsed(bytes32 tradeId);

    /// @notice Thrown when the product-specific factory returns an invalid
    ///         (zero or codeless) product address.
    error ProductDeploymentFailed(bytes32 productTypeId);

    /// @notice Thrown when a zero product type id is provided.
    error ZeroProductTypeId();

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          EVENTS                           */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Emitted when a product-specific factory is registered for a type
    ///         (initial status Active).
    event ProductFactoryRegistered(bytes32 indexed productTypeId, address indexed factory);

    /// @notice Emitted when the factory for an existing product type is replaced.
    event ProductFactoryUpdated(bytes32 indexed productTypeId, address indexed factory);

    /// @notice Emitted on every registration status change, including the
    ///         initial Unknown -> Active transition at registration.
    event ProductFactoryStatusChanged(bytes32 indexed productTypeId, ProductFactoryStatus oldStatus, ProductFactoryStatus newStatus);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  CONSTRUCTOR / MODIFIERS                  */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param owner_            Owner managing product-specific factories.
    /// @param productRegistry_  The registry allowed to call deployProduct.
    constructor(address owner_, address productRegistry_) Ownable(owner_) {
        if (productRegistry_ == address(0)) {
            revert ZeroAddress("productRegistry");
        }
        productRegistryAddress = productRegistry_;
    }

    modifier onlyProductRegistry() {
        if (msg.sender != productRegistryAddress) {
            revert NotProductRegistry(msg.sender);
        }
        _;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          ERC-165                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool){
        return interfaceId == type(IProductFactory).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    FACTORY MANAGEMENT                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Registers a product-specific factory for a product type.
    function registerProductFactory(bytes32 productTypeId, address factory) external onlyOwner {
        _validateProductTypeId(productTypeId);
        _validateSpecificFactory(productTypeId, factory);

        ProductFactoryConfig storage config = _configs[productTypeId];
        if (config.status != ProductFactoryStatus.Unknown) {
            revert ProductTypeAlreadyRegistered(productTypeId, config.factory);
        }

        uint64 nowTs = uint64(block.timestamp);
        config.status = ProductFactoryStatus.Active;
        config.factory = factory;
        config.registeredAt = nowTs;
        config.updatedAt = nowTs;

        emit ProductFactoryRegistered(productTypeId, factory);
        emit ProductFactoryStatusChanged(productTypeId, ProductFactoryStatus.Unknown, ProductFactoryStatus.Active);
    }

    /// @notice Replaces the factory for an existing product type.
    /// @dev Allowed while Active or Suspended (not Deprecated).
    function updateProductFactory(bytes32 productTypeId, address factory) external onlyOwner {
        _validateSpecificFactory(productTypeId, factory);

        ProductFactoryConfig storage config = _existingConfig(productTypeId);
        _ensureConfigWritable(productTypeId, config.status);

        config.factory = factory;
        config.updatedAt = uint64(block.timestamp);

        emit ProductFactoryUpdated(productTypeId, factory);
    }

    /// @notice Changes the lifecycle status of a product type's factory.
    function setProductFactoryStatus(bytes32 productTypeId, ProductFactoryStatus newStatus) external onlyOwner {
        ProductFactoryConfig storage config = _existingConfig(productTypeId);
        ProductFactoryStatus oldStatus = config.status;

        if (oldStatus == newStatus) {
            return;
        }
        _validateStatusTransition(oldStatus, newStatus);

        config.status = newStatus;
        config.updatedAt = uint64(block.timestamp);

        emit ProductFactoryStatusChanged(productTypeId, oldStatus, newStatus);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    PRODUCT DEPLOYMENT                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc IProductDeployer
    function deployProduct(ProductDeploymentParams calldata params) external override onlyProductRegistry nonReentrant returns (address product) {
        CommonDeploymentParams calldata common = params.common;
        bytes32 productTypeId = common.productTypeId;

        ProductFactoryConfig storage config = _existingConfig(productTypeId);
        if (config.status != ProductFactoryStatus.Active) {
            revert ProductFactoryNotActive(productTypeId, config.factory, config.status);
        }

        bytes32 tradeId = common.tradeId;
        if (productByTradeId[tradeId] != address(0)) {
            revert TradeIdAlreadyUsed(tradeId);
        }

        product = IProductSpecificFactory(config.factory).deployProduct(params);
        if (product == address(0) || product.code.length == 0) {
            revert ProductDeploymentFailed(productTypeId);
        }

        productByTradeId[tradeId] = product;

        emit ProductDeployed(tradeId, common.productDefinitionId, productTypeId, product, common.productProvider, common.investor);
    }

    function canDeployProduct(bytes32 productTypeId) external view override returns (bool) {
        ProductFactoryConfig storage config = _configs[productTypeId];
        return config.status == ProductFactoryStatus.Active && config.factory != address(0);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                         READ API                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Returns the registered factory for a product type.
    function productFactoryOf(bytes32 productTypeId) external view returns (address) {
        return _existingConfig(productTypeId).factory;
    }

    /// @notice Returns the full config for a product type.
    function getProductFactoryConfig(bytes32 productTypeId) external view returns (ProductFactoryConfig memory) {
        return _existingConfig(productTypeId);
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    VALIDATION HELPERS                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function _existingConfig(bytes32 productTypeId) internal view returns (ProductFactoryConfig storage config) {
        config = _configs[productTypeId];
        if (config.status == ProductFactoryStatus.Unknown) {
            revert UnknownProductType(productTypeId);
        }
    }

    function _ensureConfigWritable(bytes32 productTypeId, ProductFactoryStatus status) internal pure {
        if (status == ProductFactoryStatus.Deprecated) {
            revert ProductFactoryConfigNotWritable(productTypeId, status);
        }
    }

    /// @dev Allowed transitions:
    ///      Active     -> Suspended | Deprecated
    ///      Suspended  -> Active | Deprecated
    ///      Deprecated -> (terminal)
    function _validateStatusTransition(ProductFactoryStatus oldStatus, ProductFactoryStatus newStatus) internal pure {
        if (newStatus == ProductFactoryStatus.Unknown) {
            revert InvalidProductFactoryStatus(newStatus);
        }
        if (oldStatus == ProductFactoryStatus.Deprecated) {
            revert InvalidProductFactoryStatus(newStatus);
        }
    }

    function _validateProductTypeId(bytes32 productTypeId) internal pure {
        if (productTypeId == bytes32(0)) revert ZeroProductTypeId();
    }

    /// @dev Validates a specific factory: has code, implements
    ///      IProductSpecificFactory (ERC-165), and self-declares the same type.
    function _validateSpecificFactory(bytes32 productTypeId, address factory) internal view {
        if (factory == address(0) || factory.code.length == 0) {
            revert InvalidSpecificFactory(factory);
        }

        try IERC165(factory).supportsInterface(type(IProductSpecificFactory).interfaceId) returns (bool ok) {
            if (!ok) {
                revert InvalidSpecificFactory(factory);
            }
        } catch {
            revert InvalidSpecificFactory(factory);
        }

        try IProductSpecificFactory(factory).productTypeId() returns (bytes32 declaredType) {
            if (declaredType != productTypeId) {
                revert FactoryTypeMismatch(productTypeId, declaredType);
            }
        } catch {
            revert InvalidSpecificFactory(factory);
        }
    }
}
