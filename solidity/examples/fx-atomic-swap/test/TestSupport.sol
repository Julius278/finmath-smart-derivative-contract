// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {FxAtomicSwap} from "../contracts/FxAtomicSwap.sol";
import {IERC20RouterToken} from "../contracts/ERC20AtomicSwapSettlementRouter.sol";

/// @dev The suite needs only these Foundry cheatcodes; no external test library is required.
interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

interface ITransferHook {
    function onTransfer() external;
}

/// @dev Exact-transfer fixture that also models common ERC-20 return conventions and failures.
contract ReturnToken is IERC20RouterToken {
    enum Behavior {
        True,
        False,
        Revert,
        NoData,
        ShortData
    }

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    Behavior public behavior;
    ITransferHook public hook;

    function setBehavior(Behavior value) external {
        behavior = value;
    }

    function setHook(ITransferHook value) external {
        hook = value;
    }

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        if (address(hook) != address(0)) hook.onTransfer();
        if (behavior == Behavior.Revert) revert("token failure");
        if (behavior == Behavior.False) return false;
        if (behavior == Behavior.NoData) {
            assembly {
                return(0, 0)
            }
        }
        if (behavior == Behavior.ShortData) {
            assembly {
                mstore(0, 1)
                return(31, 1)
            }
        }
        return true;
    }
}

/// @dev A genuine counterparty reenters from a token callback while its confirmation is running.
contract ReentrantCounterparty is ITransferHook {
    FxAtomicSwap private swap;
    address private inceptor;
    bool public attempted;
    bytes4 public reentryError;

    function approve(ReturnToken token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function confirm(FxAtomicSwap swap_, address inceptor_) external {
        swap = swap_;
        inceptor = inceptor_;
        swap.confirmTrade(inceptor, "terms", -100, 200, "settlement");
    }

    function onTransfer() external {
        attempted = true;
        (bool success, bytes memory errorData) = address(swap)
            .call(
                abi.encodeCall(
                    FxAtomicSwap.confirmTrade, (inceptor, "terms", -100, 200, "settlement")
                )
            );
        require(!success, "reentrant confirmation succeeded");
        require(errorData.length >= 4, "missing reentry error");
        reentryError = bytes4(errorData);
    }
}
