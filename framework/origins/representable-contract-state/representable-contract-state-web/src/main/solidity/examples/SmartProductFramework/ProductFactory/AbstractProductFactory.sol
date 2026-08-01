// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductFactory} from "./IProductFactory.sol";
import {ProductDeploymentParams, CommonDeploymentParams} from "./ProductDeploymentTypes.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title AbstractProductFactory.sol
 * @notice Base for factories that construct exactly one product type. Handles
 *         the generic-factory caller guard, payload schema validation, and
 *         ERC-165, and delegates the actual construction to _deployProduct.
 * @dev Concrete factories implement productTypeId(), productSpecificSchemaHash()
 *      (the schema their payload must match), and the _deployProduct hook.
 *
 * @author Raphael Prandtl
 */
abstract contract AbstractProductFactory is IProductFactory {

    // ------------------------------ Immutable State ------------------------------ */

    /// @notice The product registry allowed to call deployProduct.
    address public immutable override productRegistryAddress;

    /**
     * @notice Whether an address was deployed through this factory.
     * @dev Convenience authenticity check for consumers of deployed products.
     */
    mapping(address => bool) private _isFactoryDeployedProduct;


    // ------------------------------ Custom Errors ------------------------------ */

    /// @notice Thrown when a required address value is the zero address.
    error ZeroAddress(string field);

    /// @notice Thrown when deployProduct is called by an address other than the configured product registry.
    error NotProductRegistry(address caller);

    /**
     * @notice Thrown when the product-specific factory returns an invalid
     *         (zero or codeless) product address.
     */
    error ProductDeploymentFailed(bytes32 tradeId);

    // ------------------------------ Constructor / Modifiers ------------------------------ */

    /// @param productRegistry_ The product registry that will invoke this factory.
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

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IProductFactory).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------ Product Deployment ------------------------------ */

    /**
     * @dev Enforces the caller guard and schema check, then delegates to the
     *      concrete _deployProduct. Product address validity is asserted by the
     *      generic factory.
     */
    function deployProduct(ProductDeploymentParams calldata params) external override onlyProductRegistry returns (address product) {
        CommonDeploymentParams calldata common = params.common;
        product = _deployProduct(params);
        // Verify factory specific _deployProduct() implementation
        if (product == address(0) || product.code.length == 0) {
            revert ProductDeploymentFailed(common.tradeId);
        }
        _isFactoryDeployedProduct[product] = true;
        emit ProductDeployed(common.tradeId, common.productDefinitionId, product, common.productProvider, common.client);
    }


    // ------------------------------ Product Specification ------------------------------ */

    function productPayloadSchema() external pure virtual override returns (string memory);

    function productTermsTemplateResourceType() external pure virtual override returns (bytes32);

    /// @notice Returns the resource type required for the product documentation template.
    function productDocumentationTemplateResourceType() external pure virtual override returns (bytes32);


    // ------------------------------ Product Indication ------------------------------ */

    function isAcceptedIndicationCategory(bytes32 indicationCategory) external view virtual override returns (bool);

    // ------------------------------ Product Authenticity ------------------------------ */

    /// @notice Returns whether a product address was deployed by this factory.
    function isFactoryDeployedProduct(address product) external view override returns (bool) {
        return _isFactoryDeployedProduct[product];
    }

    // ------------------------------ Concrete Hook ------------------------------ */

    /**
     * @dev Called by the base only after caller + schema validation (and the
     *      base's productTypeId match). Economic validation happens inside the
     *      product, which owns and decodes its payload.
     */
    function _deployProduct(ProductDeploymentParams calldata params) internal virtual returns (address product);
}
