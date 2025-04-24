// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface matching the relevant parts of the actual LiquidityLocker
interface ILiquidityLocker {
    event LiquidityLocked(address indexed token, uint256 amount, uint256 unlockTime, address indexed owner);
    event LiquidityWithdrawn(address indexed token, uint256 amount, address indexed owner);

    function lock(address _token, uint256 _amount, uint256 _unlockTime, address _owner) external;
    function withdraw(uint256 _lockId) external;
    function getLock(uint256 _lockId) external view returns (address, uint256, uint256, address);
    function lockCount() external view returns (uint256);
}

/**
 * @title Mock Liquidity Locker
 * @notice Minimal mock for testing Presale interactions.
 * @dev Implements the ILiquidityLocker interface. Relies on vm.expectCall in tests.
 */
contract MockLiquidityLocker is ILiquidityLocker, AccessControl {
    // Keep LOCKER_ROLE consistent if PresaleFactory grants it during setup
    bytes32 public constant LOCKER_ROLE = keccak256("LOCKER_ROLE");

    // Optional: Track calls if needed beyond vm.expectCall
    struct LockCall {
        address token;
        uint256 amount;
        uint256 unlockTime;
        address owner;
        address caller; // msg.sender who called lock
    }
    LockCall[] public lockCalls;

    constructor() {
        // Grant admin role to deployer, mimicking real contract setup
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Optional: Grant LOCKER_ROLE immediately if needed, or handle in test setup
        // _grantRole(LOCKER_ROLE, address(presaleFactory)); // Example
    }

    /**
     * @notice Mock lock function. Primarily verified using vm.expectCall.
     */
    function lock(address _token, uint256 _amount, uint256 _unlockTime, address _owner)
        external
        // onlyRole(LOCKER_ROLE) // Can omit role check in mock if tests handle caller correctly
    {
        // Optional: Record the call details
        lockCalls.push(LockCall({
            token: _token,
            amount: _amount,
            unlockTime: _unlockTime,
            owner: _owner,
            caller: msg.sender
        }));

        // Emit event to satisfy test expectations if vm.expectEmit is used
        emit LiquidityLocked(_token, _amount, _unlockTime, _owner);

        // No actual token transfer logic needed here - Presale handles the transfer *to* this mock
    }

    /**
     * @notice Mock withdraw function (empty implementation).
     */
    function withdraw(uint256 /*_lockId*/) external {
        // No logic needed for Presale tests
        // emit LiquidityWithdrawn(...); // Emit if needed by tests
    }

    /**
     * @notice Mock getLock function (returns default values).
     */
    function getLock(uint256 /*_lockId*/) external pure returns (address, uint256, uint256, address) {
        // Return empty/default values, not needed for Presale tests
        return (address(0), 0, 0, address(0));
    }

    /**
     * @notice Mock lockCount function (returns tracked calls or 0).
     */
    function lockCount() external view returns (uint256) {
        return lockCalls.length; // Or just return 0
    }
}
