// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/contracts/LiquidityLocker.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract LiquidityLockerTest is Test {
    LiquidityLocker locker;
    MockERC20 token;
    address owner;
    address user1;
    address user2;
    uint256 constant INITIAL_SUPPLY = 1000 ether;
    uint256 constant LOCK_AMOUNT = 100 ether;
    uint256 constant UNLOCK_TIME = 1 days;

    // Events for testing
    event LiquidityLocked(address indexed token, uint256 amount, uint256 unlockTime, address indexed owner);
    event LiquidityWithdrawn(address indexed token, uint256 amount, address indexed owner);

    // Setup function to initialize contracts and accounts
    function setUp() public {
        owner = address(this); // Test contract is the owner
        user1 = address(0x123);
        user2 = address(0x456);

        // Deploy mock token
        token = new MockERC20("Test Token", "TST", INITIAL_SUPPLY);

        // Deploy LiquidityLocker
        locker = new LiquidityLocker();

        // Transfer tokens to user1 for specific tests
        token.transfer(user1, 200 ether);
    }

    // Helper function to approve and lock tokens
    function lockTokens(address caller, address tokenAddr, uint256 amount, uint256 unlockTime, address lockOwner)
        internal
    {
        vm.startPrank(caller);
        emit log_named_uint("Caller balance before lock", token.balanceOf(caller));
        emit log_named_uint("Caller allowance before lock", token.allowance(caller, address(locker)));
        token.approve(address(locker), amount);
        emit log_named_uint("Caller allowance after approve", token.allowance(caller, address(locker)));
        locker.lock(tokenAddr, amount, unlockTime, lockOwner);
        vm.stopPrank();
    }

    // Test: Successful token locking (debug version without vm.expectEmit)
    function testLockTokensDebug() public {
        uint256 unlockTime = block.timestamp + UNLOCK_TIME;
        uint256 balanceBefore = token.balanceOf(address(locker));

        // Verify owner has sufficient tokens
        assertEq(token.balanceOf(owner), 800 ether, "Owner should have 800 ether");

        // Log for debugging
        emit log_named_address("Token address", address(token));
        emit log_named_uint("Lock amount", LOCK_AMOUNT);
        emit log_named_uint("Unlock time", unlockTime);
        emit log_named_address("Lock owner", user1);

        // Direct call to lock with explicit approval
        vm.startPrank(owner);
        token.approve(address(locker), LOCK_AMOUNT);
        emit log_named_uint("Owner allowance after approve", token.allowance(owner, address(locker)));
        emit log_named_uint("Owner balance before lock", token.balanceOf(owner));
        locker.lock(address(token), LOCK_AMOUNT, unlockTime, user1);
        vm.stopPrank();

        // Verify lock data
        (address lockedToken, uint256 amount, uint256 time, address lockOwner) = locker.getLock(0);
        assertEq(lockedToken, address(token), "Incorrect token address");
        assertEq(amount, LOCK_AMOUNT, "Incorrect lock amount");
        assertEq(time, unlockTime, "Incorrect unlock time");
        assertEq(lockOwner, user1, "Incorrect lock owner");
        assertEq(locker.lockCount(), 1, "Incorrect lock count");
        assertEq(token.balanceOf(address(locker)), balanceBefore + LOCK_AMOUNT, "Incorrect locker balance");
    }

    // Test: Successful token locking with event emission

    function testLockTokens() public {
        uint256 unlockTime = block.timestamp + UNLOCK_TIME;
        uint256 balanceBefore = token.balanceOf(address(locker));

        // Verify owner has sufficient tokens
        assertEq(token.balanceOf(owner), 800 ether, "Owner should have 800 ether"); // Adjusted based on setup

        // Log for debugging
        emit log_named_address("Token address", address(token));
        emit log_named_uint("Lock amount", LOCK_AMOUNT);
        emit log_named_uint("Unlock time", unlockTime);
        emit log_named_address("Lock owner", user1);

        // Direct call to lock with explicit approval
        vm.startPrank(owner);
        token.approve(address(locker), LOCK_AMOUNT);
        emit log_named_uint("Owner allowance after approve", token.allowance(owner, address(locker)));
        emit log_named_uint("Owner balance before lock", token.balanceOf(owner));

        // --- Expect Emit Moved Here ---
        vm.expectEmit(true, true, false, true); // Check address(token), LOCK_AMOUNT, user1 (ignore unlockTime)
        emit LiquidityLocked(address(token), LOCK_AMOUNT, unlockTime, user1);
        // --- Expect Emit Moved Here ---

        locker.lock(address(token), LOCK_AMOUNT, unlockTime, user1); // Now this call is checked
        vm.stopPrank();

        // Verify lock data
        (address lockedToken, uint256 amount, uint256 time, address lockOwner) = locker.getLock(0);
        assertEq(lockedToken, address(token), "Incorrect token address");
        assertEq(amount, LOCK_AMOUNT, "Incorrect lock amount");
        assertEq(time, unlockTime, "Incorrect unlock time");
        assertEq(lockOwner, user1, "Incorrect lock owner");
        assertEq(locker.lockCount(), 1, "Incorrect lock count");
        assertEq(token.balanceOf(address(locker)), balanceBefore + LOCK_AMOUNT, "Incorrect locker balance");
    }

    // Test: Revert on invalid token address
    function testRevertLockInvalidTokenAddress() public {
        vm.prank(owner);
        token.approve(address(locker), LOCK_AMOUNT);
        vm.expectRevert(LiquidityLocker.InvalidTokenAddress.selector);
        locker.lock(address(0), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, user1);
    }

    // Test: Revert on zero amount
    function testRevertLockZeroAmount() public {
        vm.prank(owner);
        token.approve(address(locker), 0);
        vm.expectRevert(LiquidityLocker.ZeroAmount.selector);
        locker.lock(address(token), 0, block.timestamp + UNLOCK_TIME, user1);
    }

    // Test: Revert on invalid unlock time
    function testRevertLockInvalidUnlockTime() public {
        vm.prank(owner);
        token.approve(address(locker), LOCK_AMOUNT);
        vm.expectRevert(LiquidityLocker.InvalidUnlockTime.selector);
        locker.lock(address(token), LOCK_AMOUNT, block.timestamp, user1);
    }

    // Test: Revert on invalid owner address
    function testRevertLockInvalidOwnerAddress() public {
        vm.prank(owner);
        token.approve(address(locker), LOCK_AMOUNT);
        vm.expectRevert(LiquidityLocker.InvalidOwnerAddress.selector);
        locker.lock(address(token), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, address(0));
    }

    // Test: Revert on non-owner calling lock
    function testRevertLockNonOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        locker.lock(address(token), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, user1);
    }

    // Test: Successful withdrawal after unlock time
    function testWithdrawTokens() public {
        uint256 unlockTime = block.timestamp + UNLOCK_TIME;
        lockTokens(owner, address(token), LOCK_AMOUNT, unlockTime, user1);

        // Fast forward time
        vm.warp(unlockTime + 1);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.expectEmit(true, true, false, true);
        emit LiquidityWithdrawn(address(token), LOCK_AMOUNT, user1);

        vm.prank(user1);
        locker.withdraw(0);

        // Verify withdrawal
        (, uint256 amount,,) = locker.getLock(0);
        assertEq(amount, 0, "Lock amount should be zero after withdrawal");
        assertEq(token.balanceOf(user1), balanceBefore + LOCK_AMOUNT, "Incorrect user1 balance");
        assertEq(token.balanceOf(address(locker)), 0, "Locker should have no tokens");
    }

    // Test: Revert on invalid lock ID
    function testRevertWithdrawInvalidLockId() public {
        vm.prank(user1);
        vm.expectRevert(LiquidityLocker.InvalidLockId.selector);
        locker.withdraw(0);
    }

    // Test: Revert on non-owner withdrawal
    function testRevertWithdrawNotLockOwner() public {
        lockTokens(owner, address(token), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, user1);
        vm.warp(block.timestamp + UNLOCK_TIME + 1);

        vm.prank(user2);
        vm.expectRevert(LiquidityLocker.NotLockOwner.selector);
        locker.withdraw(0);
    }

    // Test: Revert on withdrawal before unlock time
    function testRevertWithdrawTokensStillLocked() public {
        lockTokens(owner, address(token), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, user1);

        vm.prank(user1);
        vm.expectRevert(LiquidityLocker.TokensStillLocked.selector);
        locker.withdraw(0);
    }

    // Test: Revert on withdrawal with zero amount
    function testRevertWithdrawNoTokens() public {
        lockTokens(owner, address(token), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, user1);
        vm.warp(block.timestamp + UNLOCK_TIME + 1);

        vm.prank(user1);
        locker.withdraw(0); // First withdrawal

        vm.expectRevert(LiquidityLocker.NoTokensToWithdraw.selector);
        vm.prank(user1);
        locker.withdraw(0); // Second withdrawal should fail
    }

    // Test: Multiple locks for different users
    function testMultipleLocks() public {
        uint256 unlockTime1 = block.timestamp + UNLOCK_TIME;
        uint256 unlockTime2 = block.timestamp + 2 * UNLOCK_TIME;

        lockTokens(owner, address(token), LOCK_AMOUNT, unlockTime1, user1);
        lockTokens(owner, address(token), LOCK_AMOUNT / 2, unlockTime2, user2);

        // Verify lock data
        (address token1, uint256 amount1, uint256 time1, address owner1) = locker.getLock(0);
        (address token2, uint256 amount2, uint256 time2, address owner2) = locker.getLock(1);

        assertEq(token1, address(token), "Incorrect token1");
        assertEq(amount1, LOCK_AMOUNT, "Incorrect amount1");
        assertEq(time1, unlockTime1, "Incorrect time1");
        assertEq(owner1, user1, "Incorrect owner1");

        assertEq(token2, address(token), "Incorrect token2");
        assertEq(amount2, LOCK_AMOUNT / 2, "Incorrect amount2");
        assertEq(time2, unlockTime2, "Incorrect time2");
        assertEq(owner2, user2, "Incorrect owner2");

        assertEq(locker.lockCount(), 2, "Incorrect lock count");
    }

    // Test: View function getLock with invalid ID
    function testRevertGetLockInvalidId() public {
        vm.expectRevert(LiquidityLocker.InvalidLockId.selector);
        locker.getLock(0);
    }

    // Test: Reentrancy protection
    function testReentrancyWithdraw() public {
        // Deploy a malicious contract that attempts reentrancy
        MaliciousReceiver malicious = new MaliciousReceiver(address(locker));
        uint256 unlockTime = block.timestamp + UNLOCK_TIME;

        // Lock tokens for malicious contract
        lockTokens(owner, address(token), LOCK_AMOUNT, unlockTime, address(malicious));

        vm.warp(unlockTime + 1);
        vm.prank(address(malicious));
        // Reentrancy should be prevented by ReentrancyGuard
        locker.withdraw(0);

        // Verify only one withdrawal occurred
        (, uint256 amount,,) = locker.getLock(0);
        assertEq(amount, 0, "Lock amount should be zero after withdrawal");
    }

    // Fuzz test: Lock with varying amounts and unlock times
    function testFuzzLockTokens(uint256 amount, uint256 unlockTimeOffset) public {
        // Bound inputs to avoid reverts
        amount = bound(amount, 1, token.balanceOf(owner)); // Respect owner's balance (800 ether)
        unlockTimeOffset = bound(unlockTimeOffset, 1, 365 days);
        uint256 unlockTime = block.timestamp + unlockTimeOffset;

        lockTokens(owner, address(token), amount, unlockTime, user1);

        // Verify lock data
        (address lockedToken, uint256 lockedAmount, uint256 time, address lockOwner) = locker.getLock(0);
        assertEq(lockedToken, address(token), "Incorrect token address");
        assertEq(lockedAmount, amount, "Incorrect lock amount");
        assertEq(time, unlockTime, "Incorrect unlock time");
        assertEq(lockOwner, user1, "Incorrect lock owner");
    }

    // Test: Maximum lock amount
    function testLockMaxAmount() public {
        uint256 maxAmount = token.balanceOf(owner); // 800 ether after setup
        uint256 unlockTime = block.timestamp + UNLOCK_TIME;

        lockTokens(owner, address(token), maxAmount, unlockTime, user1);

        // Verify lock data
        (, uint256 amount,,) = locker.getLock(0);
        assertEq(amount, maxAmount, "Incorrect lock amount");
        assertEq(token.balanceOf(address(locker)), maxAmount, "Incorrect locker balance");
    }

    // Test: Gas usage for lockTokens
    function testGasLockTokens() public {
        uint256 unlockTime = block.timestamp + UNLOCK_TIME;
        uint256 gasStart = gasleft();
        lockTokens(owner, address(token), LOCK_AMOUNT, unlockTime, user1);
        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas used for lockTokens", gasUsed);
    }

    // Test: Lock count increments correctly
    function testLockCountIncrements() public {
        assertEq(locker.lockCount(), 0, "Initial lock count should be 0");
        lockTokens(owner, address(token), LOCK_AMOUNT, block.timestamp + UNLOCK_TIME, user1);
        assertEq(locker.lockCount(), 1, "Lock count should be 1");
    }
}

// Malicious contract to test reentrancy
contract MaliciousReceiver {
    LiquidityLocker locker;
    bool attacked;

    constructor(address _locker) {
        locker = LiquidityLocker(_locker);
    }

    function withdraw(uint256 lockId) external {
        locker.withdraw(lockId);
    }

    // Attempt reentrancy on token transfer
    receive() external payable {
        if (!attacked) {
            attacked = true;
            locker.withdraw(0);
        }
    }
}
