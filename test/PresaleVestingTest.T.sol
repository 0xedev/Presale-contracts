// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vesting} from "src/contracts/Vesting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VestingTest is Test {
    Vesting vesting;
    ERC20Mock token;
    address owner;
    address beneficiary1;
    address beneficiary2;
    address attacker;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 constant VESTING_AMOUNT = 1000 * 10 ** 18;
    uint256 constant VESTING_DURATION = 365 days;
    uint256 constant VESTING_START = 1_000_000_000;

    event VestingCreated(
        address indexed beneficiary, uint256 amount, uint256 start, uint256 duration, uint256 scheduleId
    );
    event TokensReleased(address indexed beneficiary, uint256 amount, uint256 scheduleId);
    event TokensReleasedBatch(address indexed beneficiary, uint256 totalAmount);
    event VestingDeleted(address indexed beneficiary, uint256 scheduleId, uint256 returnedAmount);
    event Paused(address indexed owner);
    event Unpaused(address indexed owner);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        owner = address(0x1);
        beneficiary1 = address(0x2);
        beneficiary2 = address(0x3);
        attacker = address(0x4);

        vm.startPrank(owner);
        token = new ERC20Mock();
        token.mint(owner, INITIAL_SUPPLY);
        vesting = new Vesting(address(token));
        token.approve(address(vesting), INITIAL_SUPPLY);
        vm.stopPrank();
    }

    function createVestingSchedule(address beneficiary, uint256 amount, uint256 start, uint256 duration)
        internal
        returns (uint256 scheduleId)
    {
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit VestingCreated(beneficiary, amount, start, duration, vesting.scheduleCount(beneficiary));
        vesting.createVesting(beneficiary, amount, start, duration);
        scheduleId = vesting.scheduleCount(beneficiary) - 1;
        vm.stopPrank();
        return scheduleId;
    }

    function testConstructor() public view {
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.owner(), owner);
        assertFalse(vesting.paused());
        assertEq(vesting.totalAllocated(), 0);
    }

    function testConstructorInvalidToken() public {
        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidTokenAddress.selector);
        new Vesting(address(0));
    }

    function testCreateVesting() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);

        (uint256 totalAmount, uint256 released, uint256 start, uint256 duration, bool exists) =
            vesting.schedules(beneficiary1, scheduleId);
        assertEq(totalAmount, VESTING_AMOUNT);
        assertEq(released, 0);
        assertEq(start, VESTING_START);
        assertEq(duration, VESTING_DURATION);
        assertTrue(exists);
        assertEq(vesting.scheduleCount(beneficiary1), 1);
        assertEq(vesting.totalAllocated(), VESTING_AMOUNT);
        assertEq(token.balanceOf(address(vesting)), VESTING_AMOUNT);
    }

    function testCreateVestingInvalidBeneficiary() public {
        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidBeneficiary.selector);
        vesting.createVesting(address(0), VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
    }

    function testCreateVestingInvalidAmount() public {
        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidAmount.selector);
        vesting.createVesting(beneficiary1, 0, VESTING_START, VESTING_DURATION);
    }

    function testCreateVestingInvalidDuration() public {
        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidDuration.selector);
        vesting.createVesting(beneficiary1, VESTING_AMOUNT, VESTING_START, 0);
    }

    function testCreateVestingWhenPaused() public {
        vm.prank(owner);
        vesting.pause();
        vm.prank(owner);
        vm.expectRevert(Vesting.ContractPaused.selector);
        vesting.createVesting(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
    }

    function testCreateVestingInsufficientApproval() public {
        vm.prank(owner);
        token.approve(address(vesting), 0);
        vm.prank(owner);
        vm.expectRevert();
        vesting.createVesting(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
    }

    function testRelease() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION / 2);

        uint256 expectedVested = VESTING_AMOUNT / 2;
        vm.prank(beneficiary1);
        vm.expectEmit(true, false, false, false);
        emit TokensReleased(beneficiary1, expectedVested, scheduleId);
        vesting.release(scheduleId);

        (, uint256 released,,,) = vesting.schedules(beneficiary1, scheduleId);
        assertEq(released, expectedVested);
        assertEq(token.balanceOf(beneficiary1), expectedVested);
        assertEq(vesting.totalAllocated(), VESTING_AMOUNT - expectedVested);
    }

    function testReleaseNoTokensToRelease() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START - 1);

        vm.prank(beneficiary1);
        vm.expectRevert(Vesting.NoTokensToRelease.selector);
        vesting.release(scheduleId);
    }

    function testReleaseInvalidScheduleId() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        uint256 invalidScheduleId = vesting.scheduleCount(beneficiary1);

        vm.prank(beneficiary1);
        vm.expectRevert(Vesting.InvalidScheduleId.selector);
        vesting.release(invalidScheduleId);

        vm.prank(beneficiary2);
        vm.expectRevert(Vesting.InvalidScheduleId.selector);
        vesting.release(0);
    }

    function testReleaseWhenPaused() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.prank(owner);
        vesting.pause();
        vm.prank(beneficiary1);
        vm.expectRevert(Vesting.ContractPaused.selector);
        vesting.release(scheduleId);
    }

    function testReleaseAll() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        createVestingSchedule(beneficiary1, VESTING_AMOUNT * 2, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION);

        uint256 expectedTotal = VESTING_AMOUNT + VESTING_AMOUNT * 2;
        uint256 initialTotalAllocated = vesting.totalAllocated();

        vm.prank(beneficiary1);
        vm.expectEmit(true, false, false, false);
        emit TokensReleasedBatch(beneficiary1, expectedTotal);
        vesting.releaseAll();

        assertEq(token.balanceOf(beneficiary1), expectedTotal);
        assertEq(vesting.totalAllocated(), initialTotalAllocated - expectedTotal);

        (, uint256 released0,,,) = vesting.schedules(beneficiary1, 0);
        (, uint256 released1,,,) = vesting.schedules(beneficiary1, 1);
        assertEq(released0, VESTING_AMOUNT, "Schedule 0 not fully released");
        assertEq(released1, VESTING_AMOUNT * 2, "Schedule 1 not fully released");
    }

    function testReleaseAllNoTokens() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START - 1);

        vm.prank(beneficiary1);
        vm.expectRevert(Vesting.NoTokensToRelease.selector);
        vesting.releaseAll();
    }

    function testReleaseAllMixedSchedules() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        createVestingSchedule(beneficiary1, VESTING_AMOUNT * 2, VESTING_START, VESTING_DURATION * 2);
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START + VESTING_DURATION, VESTING_DURATION);

        vm.warp(VESTING_START + VESTING_DURATION);

        uint256 expectedTotal = VESTING_AMOUNT + VESTING_AMOUNT;
        uint256 initialTotalAllocated = vesting.totalAllocated();

        vm.prank(beneficiary1);
        vm.expectEmit(true, false, false, false);
        emit TokensReleasedBatch(beneficiary1, expectedTotal);
        vesting.releaseAll();

        assertEq(token.balanceOf(beneficiary1), expectedTotal);
        assertEq(vesting.totalAllocated(), initialTotalAllocated - expectedTotal);
        (, uint256 released1,,,) = vesting.schedules(beneficiary1, 0);
        (, uint256 released2,,,) = vesting.schedules(beneficiary1, 1);
        (, uint256 released3,,,) = vesting.schedules(beneficiary1, 2);
        assertEq(released1, VESTING_AMOUNT, "Schedule 1 not fully released");
        assertEq(released2, VESTING_AMOUNT, "Schedule 2 not half released");
        assertEq(released3, 0, "Schedule 3 should not be released");
    }

    function testDeleteVesting() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION / 2);
        uint256 released = VESTING_AMOUNT / 2;
        vm.prank(beneficiary1);
        vesting.release(scheduleId);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit VestingDeleted(beneficiary1, scheduleId, VESTING_AMOUNT - released);
        vesting.deleteVesting(beneficiary1, scheduleId);

        (uint256 totalAmountAfter, uint256 releasedAfter,,,) = vesting.schedules(beneficiary1, scheduleId);
        assertEq(totalAmountAfter, 0, "Total amount should be reset after deletion");
        assertEq(releasedAfter, 0, "Released amount should be reset after deletion");
        assertEq(vesting.totalAllocated(), 0, "totalAllocated should be zero after deletion");
        assertEq(
            token.balanceOf(owner),
            ownerBalanceBefore + (VESTING_AMOUNT - released),
            "Returned tokens not sent to owner"
        );
    }

    function testDeleteVestingInvalidBeneficiary() public {
        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidBeneficiary.selector);
        vesting.deleteVesting(address(0), 0);
    }

    function testDeleteVestingInvalidScheduleId() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        uint256 invalidScheduleId = vesting.scheduleCount(beneficiary1);

        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidScheduleId.selector);
        vesting.deleteVesting(beneficiary1, invalidScheduleId);

        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidScheduleId.selector);
        vesting.deleteVesting(beneficiary2, 0);
    }

    function testDeleteVestingNonOwner() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vesting.deleteVesting(beneficiary1, scheduleId);
    }

    function testDeleteVestingReducesTotalAllocated() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        assertEq(vesting.totalAllocated(), VESTING_AMOUNT);
        vm.prank(owner);
        vesting.deleteVesting(beneficiary1, scheduleId);
        assertEq(vesting.totalAllocated(), 0);
    }

    function testVestedAmount() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION / 4);

        uint256 vested = vesting.vestedAmount(beneficiary1, scheduleId);
        assertEq(vested, VESTING_AMOUNT / 4);

        vm.warp(VESTING_START);
        assertEq(vesting.vestedAmount(beneficiary1, scheduleId), 0);

        vm.warp(VESTING_START + VESTING_DURATION);
        assertEq(vesting.vestedAmount(beneficiary1, scheduleId), VESTING_AMOUNT);

        vm.warp(VESTING_START + VESTING_DURATION + 100);
        assertEq(vesting.vestedAmount(beneficiary1, scheduleId), VESTING_AMOUNT);
    }

    function testVestedAmountInvalidSchedule() public {
        assertEq(vesting.vestedAmount(beneficiary1, 0), 0);
        createVestingSchedule(beneficiary2, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        assertEq(vesting.vestedAmount(beneficiary2, 1), 0);
    }

    function testRemainingVested() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION / 2);
        vm.prank(beneficiary1);
        vesting.release(scheduleId);

        uint256 remaining = vesting.remainingVested(beneficiary1, scheduleId);
        assertEq(remaining, VESTING_AMOUNT / 2);

        vm.warp(VESTING_START + VESTING_DURATION);
        vm.prank(beneficiary1);
        vesting.release(scheduleId);
        assertEq(vesting.remainingVested(beneficiary1, scheduleId), 0);
    }

    function testGetTotalRemainingVested() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START + VESTING_DURATION * 2, VESTING_DURATION);
        uint256 scheduleId2 = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);

        vm.warp(VESTING_START + VESTING_DURATION / 2);
        vm.prank(beneficiary1);
        vesting.release(scheduleId2);

        uint256 expectedTotalRemaining = VESTING_AMOUNT + VESTING_AMOUNT + (VESTING_AMOUNT / 2);
        uint256 totalRemaining = vesting.getTotalRemainingVested(beneficiary1);
        assertEq(totalRemaining, expectedTotalRemaining, "Total remaining vested calculation incorrect");

        vm.warp(VESTING_START + VESTING_DURATION * 3);
        assertEq(
            vesting.getTotalRemainingVested(beneficiary1),
            VESTING_AMOUNT + VESTING_AMOUNT + (VESTING_AMOUNT / 2),
            "Total remaining after end incorrect"
        );

        vm.prank(beneficiary1);
        vesting.release(0);
        assertEq(
            vesting.getTotalRemainingVested(beneficiary1),
            VESTING_AMOUNT + (VESTING_AMOUNT / 2),
            "Total remaining after releasing schedule 0 incorrect"
        );
    }

    function testUniqueScheduleIdsPerBeneficiary() public {
        uint256 id1 = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        uint256 id2 = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        assertEq(id2, id1 + 1);
    }

    function testVestingOneSecondDuration() public {
        uint256 duration = 1; // 1 second
        uint256 id = createVestingSchedule(beneficiary1, VESTING_AMOUNT, block.timestamp, duration);
        vm.warp(block.timestamp + 1);
        vm.prank(beneficiary1);
        vesting.release(id);
        assertEq(token.balanceOf(beneficiary1), VESTING_AMOUNT);
    }

    function testMultipleBeneficiariesVestingIndependently() public {
        uint256 id1 = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        uint256 id2 = createVestingSchedule(beneficiary2, VESTING_AMOUNT * 2, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION);
        vm.prank(beneficiary1);
        vesting.release(id1);
        vm.prank(beneficiary2);
        vesting.release(id2);

        assertEq(token.balanceOf(beneficiary1), VESTING_AMOUNT);
        assertEq(token.balanceOf(beneficiary2), VESTING_AMOUNT * 2);
    }

    function testFinalReleaseCatchesRoundingDust() public {
        uint256 id = createVestingSchedule(beneficiary1, 7, VESTING_START, 3); // uneven vesting
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(VESTING_START + i + 1);
            vm.prank(beneficiary1);
            vesting.release(id);
        }

        assertEq(token.balanceOf(beneficiary1), 7);
    }

    function testDeleteAfterFullRelease() public {
        uint256 id = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.warp(VESTING_START + VESTING_DURATION);
        vm.prank(beneficiary1);
        vesting.release(id);

        vm.prank(owner);
        vesting.deleteVesting(beneficiary1, id);
        (, uint256 releasedAfter,,,) = vesting.schedules(beneficiary1, id);
        assertEq(releasedAfter, 0);
    }

    function testPause() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);
        vesting.pause();
        assertTrue(vesting.paused());
    }

    function testPauseAlreadyPaused() public {
        vm.prank(owner);
        vesting.pause();
        vm.prank(owner);
        vm.expectRevert(Vesting.AlreadyPaused.selector);
        vesting.pause();
    }

    function testUnpause() public {
        vm.prank(owner);
        vesting.pause();
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);
        vesting.unpause();
        assertFalse(vesting.paused());
    }

    function testUnpauseNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(Vesting.NotPaused.selector);
        vesting.unpause();
    }

    function testRescueTokens() public {
        ERC20Mock otherToken = new ERC20Mock();
        otherToken.mint(address(vesting), 1000 * 10 ** 18);
        address recipient = address(0x5);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit TokensRescued(address(otherToken), recipient, 500 * 10 ** 18);
        vesting.rescueTokens(address(otherToken), recipient, 500 * 10 ** 18);

        assertEq(otherToken.balanceOf(recipient), 500 * 10 ** 18);
        assertEq(otherToken.balanceOf(address(vesting)), 500 * 10 ** 18);
    }

    function testRescueVestingTokenFails() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);

        vm.prank(owner);
        vm.expectRevert(Vesting.CannotRescueVestingToken.selector);
        vesting.rescueTokens(address(token), address(0x5), 1000);
    }

    function testRescueTokensInvalidRecipient() public {
        ERC20Mock otherToken = new ERC20Mock();
        otherToken.mint(address(vesting), 1000 * 10 ** 18);

        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidAddress.selector);
        vesting.rescueTokens(address(otherToken), address(0), 500 * 10 ** 18);
    }

    function testRescueTokensZeroAmount() public {
        ERC20Mock otherToken = new ERC20Mock();
        otherToken.mint(address(vesting), 1000 * 10 ** 18);

        vm.prank(owner);
        vm.expectRevert(Vesting.InvalidAmount.selector);
        vesting.rescueTokens(address(otherToken), owner, 0);
    }

    function testRescueUnallocatedVestingTokens() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        uint256 allocated = vesting.totalAllocated();

        vm.startPrank(owner);
        token.mint(address(vesting), VESTING_AMOUNT * 2);
        uint256 contractBalanceBefore = token.balanceOf(address(vesting));
        uint256 amountToRescue = contractBalanceBefore - allocated;
        assertEq(amountToRescue, VESTING_AMOUNT * 2, "Amount to rescue calculation incorrect");

        vm.expectEmit(true, true, false, false);
        emit TokensRescued(address(token), owner, amountToRescue);
        vesting.rescueUnallocatedVestingTokens(owner, amountToRescue);
        vm.stopPrank();

        assertEq(
            token.balanceOf(owner), INITIAL_SUPPLY - VESTING_AMOUNT + amountToRescue, "Rescued tokens not sent to owner"
        );
        assertEq(token.balanceOf(address(vesting)), allocated, "Only unallocated tokens should be rescued");
        assertEq(vesting.totalAllocated(), allocated, "totalAllocated should not change");
    }

    function testRescueUnallocatedNoTokens() public {
        assertEq(token.balanceOf(address(vesting)), 0);
        assertEq(vesting.totalAllocated(), 0);

        vm.prank(owner);
        vm.expectRevert(Vesting.NoTokensToRelease.selector);
        vesting.rescueUnallocatedVestingTokens(owner, 1);
    }

    function testRescueUnallocatedInvalidAmount() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        uint256 allocated = vesting.totalAllocated();

        vm.startPrank(owner);
        token.mint(address(vesting), VESTING_AMOUNT);
        uint256 contractBalance = token.balanceOf(address(vesting));
        uint256 unallocated = contractBalance - allocated;

        vm.expectRevert(Vesting.InvalidAmount.selector);
        vesting.rescueUnallocatedVestingTokens(owner, unallocated + 1);
        vm.stopPrank();
    }

    function testRescueUnallocatedInvalidRecipient() public {
        createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.startPrank(owner);
        token.mint(address(vesting), VESTING_AMOUNT);
        uint256 contractBalance = token.balanceOf(address(vesting));
        uint256 unallocated = contractBalance - vesting.totalAllocated();

        vm.expectRevert(Vesting.InvalidAddress.selector);
        vesting.rescueUnallocatedVestingTokens(address(0), unallocated);
        vm.stopPrank();
    }

    function testReentrancyAttack() public {
        MaliciousToken maliciousToken = new MaliciousToken();
        vm.prank(owner);
        vesting = new Vesting(address(maliciousToken));
        MaliciousBeneficiary malicious = new MaliciousBeneficiary(address(vesting), address(maliciousToken));

        vm.startPrank(owner);
        maliciousToken.mint(owner, VESTING_AMOUNT * 2);
        maliciousToken.approve(address(vesting), VESTING_AMOUNT * 2);
        vesting.createVesting(address(malicious), VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vesting.createVesting(address(malicious), VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.stopPrank();

        vm.warp(VESTING_START + VESTING_DURATION);

        vm.prank(owner);
        maliciousToken.setAttacker(address(malicious));

        vm.prank(address(malicious));
        malicious.setAttack(true, 1);

        vm.prank(address(malicious));
        // Expect the custom error selector from ReentrancyGuard
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector); // <-- NEW, Correct line
        vesting.release(0);
    }

    function testFuzzReleaseAll(
        uint256[] calldata rawAmounts,
        uint256[] calldata rawStarts,
        uint256[] calldata rawDurations,
        uint256 warpChoice
    ) public {
        uint256 len = rawAmounts.length;
        if (len == 0 || len > 6) return; // reasonable limit

        // Make sure all arrays are same length
        if (rawStarts.length != len || rawDurations.length != len) return;

        // Prepare normalized inputs
        uint256[] memory amounts = new uint256[](len);
        uint256[] memory starts = new uint256[](len);
        uint256[] memory durations = new uint256[](len);

        uint256 totalAmount = 0;
        uint256 earliestStart = type(uint256).max;
        uint256 latestEnd = 0;

        for (uint256 i = 0; i < len; i++) {
            amounts[i] = bound(rawAmounts[i], 1e18, 1000e18);
            durations[i] = bound(rawDurations[i], 1 hours, 365 days);
            starts[i] = bound(rawStarts[i], VESTING_START, VESTING_START + 365 days);

            // Track total amount and overflow check
            uint256 prevTotal = totalAmount;
            totalAmount += amounts[i];
            if (totalAmount < prevTotal) return; // overflow, skip case

            if (starts[i] < earliestStart) earliestStart = starts[i];

            uint256 end = starts[i] + durations[i];
            if (end > latestEnd) latestEnd = end;
        }

        if (totalAmount > INITIAL_SUPPLY / 50) return;

        uint256 scheduleStartIndex = vesting.scheduleCount(beneficiary1);

        vm.startPrank(owner);
        token.mint(owner, totalAmount);
        token.approve(address(vesting), totalAmount);

        for (uint256 i = 0; i < len; i++) {
            emit VestingCreated(beneficiary1, amounts[i], starts[i], durations[i], scheduleStartIndex + i);
            vesting.createVesting(beneficiary1, amounts[i], starts[i], durations[i]);
        }

        vm.stopPrank();

        uint256 initialTotalAllocated = vesting.totalAllocated();

        // Warp time
        uint256 warpRange = latestEnd + 2 days - earliestStart;
        uint256 warpTarget = earliestStart + (warpChoice % warpRange);
        if (warpTarget < VESTING_START) warpTarget = VESTING_START;

        vm.warp(warpTarget);

        // Compute expected total to release
        uint256 expectedTotalReleased = 0;
        for (uint256 i = 0; i < len; i++) {
            uint256 scheduleId = scheduleStartIndex + i;
            (, uint256 released,,,) = vesting.schedules(beneficiary1, scheduleId);
            uint256 vested = vesting.vestedAmount(beneficiary1, scheduleId);
            if (vested > released) expectedTotalReleased += vested - released;
        }

        uint256 initialBalance = token.balanceOf(beneficiary1);

        if (expectedTotalReleased > 0) {
            vm.expectEmit(true, false, false, false);
            emit TokensReleasedBatch(beneficiary1, expectedTotalReleased);

            vm.prank(beneficiary1);
            vesting.releaseAll();

            assertEq(token.balanceOf(beneficiary1), initialBalance + expectedTotalReleased);
            assertEq(vesting.totalAllocated(), initialTotalAllocated - expectedTotalReleased);

            for (uint256 i = 0; i < len; i++) {
                uint256 id = scheduleStartIndex + i;
                (, uint256 released,,,) = vesting.schedules(beneficiary1, id);
                assertEq(released, vesting.vestedAmount(beneficiary1, id), "Mismatch in released vs vested");
            }
        } else {
            vm.prank(beneficiary1);
            vm.expectRevert(Vesting.NoTokensToRelease.selector);
            vesting.releaseAll();

            assertEq(token.balanceOf(beneficiary1), initialBalance);
            assertEq(vesting.totalAllocated(), initialTotalAllocated);
        }
    }

    function testSequentialRelease() public {
        MaliciousBeneficiary malicious = new MaliciousBeneficiary(address(vesting), address(token));
        vm.startPrank(owner);
        token.mint(owner, VESTING_AMOUNT * 2);
        token.approve(address(vesting), VESTING_AMOUNT * 2);
        createVestingSchedule(address(malicious), VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        createVestingSchedule(address(malicious), VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.stopPrank();

        vm.warp(VESTING_START + VESTING_DURATION);

        vm.prank(address(malicious));
        malicious.attack(0, false);

        (, uint256 released0,,,) = vesting.schedules(address(malicious), 0);
        (, uint256 released1,,,) = vesting.schedules(address(malicious), 1);
        assertEq(released0, VESTING_AMOUNT, "Schedule 0 should be fully released");
        assertEq(released1, VESTING_AMOUNT, "Schedule 1 should be fully released");
        assertEq(
            token.balanceOf(address(malicious)), VESTING_AMOUNT * 2, "Malicious contract should have all vested tokens"
        );
        assertEq(vesting.totalAllocated(), 0, "Total allocated should be zero after release");
    }

    function testReleaseAllWithDeletedSchedule() public {
        uint256 scheduleId = createVestingSchedule(beneficiary1, VESTING_AMOUNT, VESTING_START, VESTING_DURATION);
        vm.prank(owner);
        vesting.deleteVesting(beneficiary1, scheduleId);
        vm.warp(VESTING_START + VESTING_DURATION);
        vm.prank(beneficiary1);
        vm.expectRevert(Vesting.NoTokensToRelease.selector);
        vesting.releaseAll();
    }
}

contract MaliciousToken is ERC20Mock {
    address public attacker;

    constructor() ERC20Mock() {}

    function setAttacker(address _attacker) external {
        attacker = _attacker;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        if (success && attacker != address(0) && to == attacker && to.code.length > 0) {
            (bool called, bytes memory data) = attacker.call(abi.encodeWithSignature("onTokenReceived()"));
            if (!called) {
                // Propagate the revert data
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
        return success;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        if (success && attacker != address(0) && to == attacker && to.code.length > 0) {
            (bool called, bytes memory data) = attacker.call(abi.encodeWithSignature("onTokenReceived()"));
            if (!called) {
                // Propagate the revert data
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
        return success;
    }
}

contract MaliciousBeneficiary {
    Vesting vesting;
    IERC20 token;
    bool attackEnabled;
    uint256 attackScheduleId;

    constructor(address _vesting, address _token) {
        vesting = Vesting(_vesting);
        token = IERC20(_token);
    }

    function setAttack(bool _attackEnabled, uint256 _attackScheduleId) external {
        attackEnabled = _attackEnabled;
        attackScheduleId = _attackScheduleId;
    }

    function attack(uint256 scheduleId, bool attemptReentrancy) external {
        if (attemptReentrancy) {
            vesting.release(scheduleId);
        } else {
            vesting.release(scheduleId);
            vesting.release(scheduleId + 1);
        }
    }

    function onTokenReceived() external {
        if (attackEnabled) {
            vesting.release(attackScheduleId);
        }
    }
}
