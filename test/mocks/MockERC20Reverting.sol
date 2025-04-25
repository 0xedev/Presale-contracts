// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Mock ERC20 that can be configured to revert
import {MockERC20} from "test/mocks/MockERC20.sol"; // Assuming you have this
import "./MaliciousReentrant.sol";

contract MockERC20Reverting is MockERC20 {
    bool public shouldRevertTransfer = false;
    bool public shouldRevertTransferFrom = false;
    bool public shouldRevertApprove = false;

    // Track calls for reentrancy simulation in claim
    MaliciousReentrantClaimer public reentrancyTarget;

    constructor(string memory name, string memory symbol, uint8 decimals) MockERC20(name, symbol, decimals) {}

    function setRevertTransfer(bool _revert) external {
        shouldRevertTransfer = _revert;
    }

    function setRevertTransferFrom(bool _revert) external {
        shouldRevertTransferFrom = _revert;
    }

    function setRevertApprove(bool _revert) external {
        shouldRevertApprove = _revert;
    }

    function setReentrancyTarget(address _target) external {
        reentrancyTarget = MaliciousReentrantClaimer(_target);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (shouldRevertTransfer) {
            revert("MockERC20Reverting: transfer reverted");
        }
        // Simulate reentrancy callback for claim test
        if (address(reentrancyTarget) != address(0)) {
            try reentrancyTarget.onTokenTransfer() {} catch {} // Ignore revert in callback
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (shouldRevertTransferFrom) {
            revert("MockERC20Reverting: transferFrom reverted");
        }
        return super.transferFrom(from, to, amount);
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        if (shouldRevertApprove) {
            revert("MockERC20Reverting: approve reverted");
        }
        return super.approve(spender, amount);
    }
}
