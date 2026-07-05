// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProductSpecificFactory} from "./IProductFactory.sol";
import {ProductDeploymentParams} from "./ProductDeploymentTypes.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AbstractProductSpecificFactory
/// @notice Base for factories that construct exactly one product type. Handles
///         the generic-factory caller guard, payload schema validation, and
///         ERC-165, and delegates the actual construction to _deployProduct.
/// @dev Concrete factories implement productTypeId(), productSpecificSchemaHash()
///      (the schema their payload must match), and the _deployProduct hook.
///
/// @author Raphael Prandtl
abstract contract AbstractProductSpecificFactory is IProductSpecificFactory {
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       IMMUTABLE STATE                     */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice The generic factory allowed to call deployProduct.
    address public immutable genericFactory;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          STORAGE                          */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Whether an address was deployed through this factory.
    /// @dev Convenience authenticity check for consumers of deployed products.
    mapping(address => bool) public isFactoryDeployedProduct;

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                       CUSTOM ERRORS                       */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress(string field);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                  CONSTRUCTOR / MODIFIERS                  */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @param genericFactory_ The generic factory that will invoke this factory.
    constructor(address genericFactory_) {
        if (genericFactory_ == address(0)) {
            revert ZeroAddress("genericFactory");
        }
        genericFactory = genericFactory_;
    }

    modifier onlyGenericFactory() {
        if (msg.sender != genericFactory) {
            revert NotGenericFactory(msg.sender);
        }
        _;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                          ERC-165                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IProductSpecificFactory).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                      PRODUCT DEPLOYMENT                   */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Enforces the caller guard and schema check, then delegates to the
    ///      concrete _deployProduct. Product address validity is asserted by the
    ///      generic factory.
    function deployProduct(ProductDeploymentParams calldata params) external override onlyGenericFactory returns (address product) {
        bytes32 expected = productSpecificSchemaHash();
        if (params.productSpecificSchemaHash != expected) {
            revert SchemaMismatch(expected, params.productSpecificSchemaHash);
        }
        bytes32 expectedType = productTypeId();
        if (params.common.productTypeId != expectedType) {
            revert ProductTypeMismatch(expectedType, params.common.productTypeId);
        }
        product = _deployProduct(params);
        isFactoryDeployedProduct[product] = true;
    }

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                    PRODUCT SPECIFICATION                  */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @inheritdoc IProductSpecificFactory
    function productTypeId() external pure virtual override returns (bytes32);

    /// @notice Human-readable schema describing the expected
    ///         productSpecificPayload encoding (documentation / off-chain aid).
    function productSpecificPayloadSchema() external pure virtual returns (string memory);

    /// @notice The hash the incoming payload schema must match.
    /// @dev Compared against params.productSpecificSchemaHash in deployProduct.
    function productSpecificSchemaHash() public pure virtual returns (bytes32);

    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/
    /*                     CONCRETE HOOK                         */
    /*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*-+-*/

    /// @dev Called by the base only after caller + schema validation (and the
    ///      base's productTypeId match). Economic validation happens inside the
    ///      product, which owns and decodes its payload.
    function _deployProduct(ProductDeploymentParams calldata params) internal virtual returns (address product);
}
