// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductFactory} from "./IProductFactory.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "./ProductDeploymentTypes.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title AbstractProductFactory
 * @notice Base contract for factories deploying one product specification.
 *
 * @dev Restricts deployment to the configured product registry, validates the
 *      returned product address, and records deployed products. Concrete
 *      factories provide the product specification and deployment hook.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProductFactory is IProductFactory {
    // ------------------------------ Immutable State ------------------------------ */

    /// @inheritdoc IProductFactory
    address public immutable override productRegistryAddress;

    /// @notice Tracks products deployed by this factory.
    mapping(address product => bool deployed) private _isFactoryDeployedProduct;

    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address value is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when the caller is not the configured product registry.
    error NotProductRegistry(address caller);

    /// @notice Thrown when the deployment hook returns an invalid product address.
    error ProductDeploymentFailed(bytes32 tradeId);

    // ------------------------------ Constructor / Modifiers ------------------------------ */

    /// @param productRegistry_ Product registry authorized to use this factory.
    constructor(address productRegistry_) {
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

    // ------------------------------ ERC-165 ------------------------------ */

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IProductFactory).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------ Product Deployment ------------------------------ */

    /// @inheritdoc IProductFactory
    function deployProduct(ProductDeploymentParams calldata params) external override onlyProductRegistry returns (address product) {
        CommonDeploymentParams calldata common = params.common;

        product = _deployProduct(params);
        if (product == address(0) || product.code.length == 0) {
            revert ProductDeploymentFailed(common.tradeId);
        }

        _isFactoryDeployedProduct[product] = true;
        emit ProductDeployed(common.tradeId, common.productDefinitionId, product, common.productProvider, common.client);
    }

    // ------------------------------ Product Specification ------------------------------ */

    /// @inheritdoc IProductFactory
    function productPayloadSchema() external pure virtual override returns (string memory);

    /// @inheritdoc IProductFactory
    function productTermsTemplateResourceType() external pure virtual override returns (bytes32);

    /// @inheritdoc IProductFactory
    function productDocumentationTemplateResourceType() external pure virtual override returns (bytes32);

    // ------------------------------ Product Indication ------------------------------ */

    function isAcceptedIndicationCategory(bytes32 indicationCategory) external view virtual override returns (bool);

    // ------------------------------ Product Authenticity ------------------------------ */

    /// @inheritdoc IProductFactory
    function isFactoryDeployedProduct(address product) external view override returns (bool) {
        return _isFactoryDeployedProduct[product];
    }

    // ------------------------------ Concrete Hook ------------------------------ */

    /// @notice Deploys the concrete product implementation.
    function _deployProduct(ProductDeploymentParams calldata params) internal virtual returns (address product);
}
