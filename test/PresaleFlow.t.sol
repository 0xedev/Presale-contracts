// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Import Base Test and Interfaces/Contracts needed for tests
import {PresaleTestBase, generateMerkleTree} from "./PresaleTestBase.t.sol"; // Import base and helper
import {IPresale} from "../src/contracts/interfaces/IPresale.sol";
import {Presale} from "../src/contracts/Presale.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockVesting} from "./PresaleTestBase.t.sol"; // Import mock for event check

// ==========================================================================================
// Test Contract: Presale Flow (Finalize, Claim, Refund, Cancel etc.) - Inherits from Base
// ==========================================================================================
contract PresaleFlowTest is PresaleTestBase {
    // NOTE: setUp() is inherited and runs automatically

    // ==========================================================================================
    // Test Cases: Finalize
    // ==========================================================================================
    function test_Revert_Finalize_NotOwner() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: softCap}(new bytes32[](0));
        vm.stopPrank();
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.finalize();
    }

    function test_Revert_Finalize_Paused() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: softCap}(new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(owner);
        presale.pause();
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.finalize();
        vm.stopPrank();
    }

    function test_Revert_Finalize_WrongState() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Pending)));
        presale.finalize();
    } // Already pending

    function test_Revert_Finalize_SoftCapNotReached() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: softCap - 1 wei}(new bytes32[](0));
        vm.stopPrank();
        vm.prank(owner);
        vm.expectRevert(IPresale.SoftCapNotReached.selector);
        presale.finalize();
    }

    function test_Finalize_Success_ETH_LeftoverReturn() public {
        vm.startPrank(owner);
        Presale.PresaleOptions memory opts = optionsETH;
        opts.leftoverTokenOption = 0;
        opts.tokenDeposit = calculateDeposit(opts);
        presale = deployPresale(opts);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        uint256 contribution = softCap;
        vm.prank(contributor1);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.stopPrank();
        uint256 expectedLiquidityTokens = presale.pool_tokensLiquidity();
        uint256 expectedWeiForLiquidity = (contribution * opts.liquidityBps) / Presale.BASIS_POINTS;
        uint256 expectedHouseAmount = (contribution * housePercentage) / Presale.BASIS_POINTS;
        uint256 expectedOwnerBalance = contribution - expectedWeiForLiquidity - expectedHouseAmount;
        uint256 actualTokensSold = presale.userTokens(contributor1);
        uint256 initialDeposit = opts.tokenDeposit;
        uint256 expectedUnsold = initialDeposit - actualTokensSold - expectedLiquidityTokens;
        uint256 ownerInitialTokenBalance = presaleToken.balanceOf(owner);
        uint256 houseInitialBalance = houseAddress.balance;
        uint256 presaleInitialETHBalance = address(presale).balance;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Finalized(owner, contribution, block.timestamp);
        if (expectedHouseAmount > 0) {
            vm.expectEmit(true, true, false, true);
            emit IPresale.HouseFundsDistributed(houseAddress, expectedHouseAmount);
        }
        if (expectedUnsold > 0) {
            vm.expectEmit(true, false, true, true);
            emit IPresale.LeftoverTokensReturned(expectedUnsold, owner);
        }
        bool success = presale.finalize();
        assertTrue(success);
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized));
        assertTrue(presale.claimDeadline() > block.timestamp);
        assertEq(presale.ownerBalance(), expectedOwnerBalance);
        assertEq(router.addLiquidityETHToken(), address(presaleToken));
        assertEq(router.addLiquidityETHValue(), expectedWeiForLiquidity);
        assertEq(router.addLiquidityETHTokenAmount(), expectedLiquidityTokens);
        assertEq(locker.lockCallCount(), 1);
        assertEq(locker.lastLockedToken(), address(pair));
        assertTrue(locker.lastLockedAmount() > 0);
        assertEq(locker.lastUnlockTime(), block.timestamp + opts.lockupDuration);
        assertEq(locker.lastLockedOwner(), owner);
        assertEq(houseAddress.balance, houseInitialBalance + expectedHouseAmount);
        assertEq(presaleToken.balanceOf(owner), ownerInitialTokenBalance + expectedUnsold);
        assertEq(address(presale).balance, presaleInitialETHBalance - expectedWeiForLiquidity - expectedHouseAmount);
        uint256 expectedPresaleTokenBalanceAfter = actualTokensSold;
        assertEq(presale.pool_tokenBalance(), expectedPresaleTokenBalanceAfter);
    }

    function test_Finalize_Success_ETH_LeftoverBurn() public {
        vm.startPrank(owner);
        Presale.PresaleOptions memory opts = optionsETH;
        opts.leftoverTokenOption = 1;
        opts.tokenDeposit = calculateDeposit(opts);
        presale = deployPresale(opts);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: softCap}(new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(owner);
        uint256 initialDeposit = opts.tokenDeposit;
        uint256 actualTokensSold = presale.userTokens(contributor1);
        uint256 expectedLiquidityTokens = presale.pool_tokensLiquidity();
        uint256 expectedUnsold = initialDeposit - actualTokensSold - expectedLiquidityTokens;
        if (expectedUnsold > 0) {
            vm.expectEmit(true, false, false, true);
            emit IPresale.LeftoverTokensBurned(expectedUnsold);
        }
        vm.expectEmit(true, true, true, true);
        emit IPresale.Finalized(owner, softCap, block.timestamp);
        uint256 burnAddressInitialBalance = presaleToken.balanceOf(address(0));
        uint256 ownerInitialTokenBalance = presaleToken.balanceOf(owner);
        presale.finalize();
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized));
        if (expectedUnsold > 0) {
            assertEq(presaleToken.balanceOf(address(0)), burnAddressInitialBalance + expectedUnsold);
        }
        assertEq(presaleToken.balanceOf(owner), ownerInitialTokenBalance);
    }

    function test_Finalize_Success_ETH_LeftoverVest() public {
        vm.startPrank(owner);
        Presale.PresaleOptions memory opts = optionsETH;
        opts.leftoverTokenOption = 2;
        opts.vestingDuration = 180 days;
        opts.tokenDeposit = calculateDeposit(opts);
        presale = deployPresale(opts);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: softCap}(new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(owner);
        uint256 initialDeposit = opts.tokenDeposit;
        uint256 actualTokensSold = presale.userTokens(contributor1);
        uint256 expectedLiquidityTokens = presale.pool_tokensLiquidity();
        uint256 expectedUnsold = initialDeposit - actualTokensSold - expectedLiquidityTokens;
        if (expectedUnsold > 0) {
            vm.expectEmit(true, false, true, true);
            emit IPresale.LeftoverTokensVested(expectedUnsold, owner);
            vm.expectEmit(true, true, false, true);
            emit MockVesting.VestingCreated(owner, expectedUnsold, block.timestamp, opts.vestingDuration, 0);
        }
        vm.expectEmit(true, true, true, true);
        emit IPresale.Finalized(owner, softCap, block.timestamp);
        uint256 vestingContractInitialBalance = presaleToken.balanceOf(address(vesting));
        uint256 vestingCallCountBefore = vesting.createVestingCallCount();
        presale.finalize();
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized));
        if (expectedUnsold > 0) {
            assertEq(vesting.createVestingCallCount(), vestingCallCountBefore + 1);
            assertEq(vesting.lastBeneficiary(), owner);
            assertEq(vesting.lastAmount(), expectedUnsold);
            assertEq(vesting.lastDuration(), opts.vestingDuration);
            assertEq(presaleToken.balanceOf(address(vesting)), vestingContractInitialBalance + expectedUnsold);
        } else {
            assertEq(vesting.createVestingCallCount(), vestingCallCountBefore);
        }
    }

    function test_Finalize_Success_Stablecoin() public {
        vm.startPrank(owner);
        presale = deployPresale(optionsStable);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        uint256 contribution = optionsStable.softCap;
        vm.startPrank(contributor1);
        uint256 currentStableBalance = currencyToken.balanceOf(contributor1);
        if (currentStableBalance < contribution) currencyToken.mint(contributor1, contribution - currentStableBalance);
        currencyToken.approve(address(presale), contribution);
        presale.contributeStablecoin(contribution, new bytes32[](0));
        vm.stopPrank();
        uint256 expectedLiquidityTokens = presale.pool_tokensLiquidity();
        uint256 expectedCurrencyForLiquidity = (contribution * optionsStable.liquidityBps) / Presale.BASIS_POINTS;
        uint256 expectedHouseAmount = (contribution * housePercentage) / Presale.BASIS_POINTS;
        uint256 expectedOwnerBalance = contribution - expectedCurrencyForLiquidity - expectedHouseAmount;
        uint256 houseInitialBalance = currencyToken.balanceOf(houseAddress);
        uint256 presaleInitialStableBalance = currencyToken.balanceOf(address(presale));
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Finalized(owner, contribution, block.timestamp);
        if (expectedHouseAmount > 0) {
            vm.expectEmit(true, true, false, true);
            emit IPresale.HouseFundsDistributed(houseAddress, expectedHouseAmount);
        }
        bool success = presale.finalize();
        assertTrue(success);
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized));
        assertEq(presale.ownerBalance(), expectedOwnerBalance);
        address tokenA = router.addLiquidityTokenA();
        address tokenB = router.addLiquidityTokenB();
        uint256 amountA = router.addLiquidityTokenAAmount();
        uint256 amountB = router.addLiquidityTokenBAmount();
        if (tokenA == address(presaleToken)) {
            assertEq(tokenB, address(currencyToken));
            assertEq(amountA, expectedLiquidityTokens);
            assertEq(amountB, expectedCurrencyForLiquidity);
        } else {
            assertEq(tokenA, address(currencyToken));
            assertEq(tokenB, address(presaleToken));
            assertEq(amountA, expectedCurrencyForLiquidity);
            assertEq(amountB, expectedLiquidityTokens);
        }
        assertEq(locker.lockCallCount(), 1);
        assertEq(locker.lastLockedToken(), address(pair));
        assertTrue(locker.lastLockedAmount() > 0);
        assertEq(locker.lastUnlockTime(), block.timestamp + optionsStable.lockupDuration);
        assertEq(locker.lastLockedOwner(), owner);
        assertEq(currencyToken.balanceOf(houseAddress), houseInitialBalance + expectedHouseAmount);
        assertEq(
            currencyToken.balanceOf(address(presale)),
            presaleInitialStableBalance - expectedCurrencyForLiquidity - expectedHouseAmount
        );
    }

    // ==========================================================================================
    // Test Cases: Claim
    // ==========================================================================================
    function test_Revert_Claim_WrongState() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: minContribution}(new bytes32[](0));
        vm.stopPrank();
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.claim();
    }

    function test_Revert_Claim_Paused() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        vm.startPrank(owner);
        presale.pause();
        vm.stopPrank();
        vm.prank(contributor1);
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.claim();
    }

    function test_Revert_Claim_DeadlineExpired() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        uint256 deadline = presale.claimDeadline();
        vm.warp(deadline + 1 seconds);
        vm.prank(contributor1);
        vm.expectRevert(IPresale.ClaimPeriodExpired.selector);
        presale.claim();
    }

    function test_Revert_Claim_NoTokensToClaim() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        vm.prank(otherUser);
        vm.expectRevert(IPresale.NoTokensToClaim.selector);
        presale.claim();
        vm.prank(contributor1);
        presale.claim();
        vm.expectRevert(IPresale.NoTokensToClaim.selector);
        presale.claim();
    }

    function test_Claim_Success_NoVesting() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        uint256 expectedTokens = presale.userTokens(contributor1);
        uint256 initialUserBalance = presaleToken.balanceOf(contributor1);
        uint256 initialContractTokenBalance = presale.pool_tokenBalance();
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit IPresale.TokenClaim(contributor1, expectedTokens, block.timestamp);
        uint256 claimedAmount = presale.claim();
        vm.stopPrank();
        assertEq(claimedAmount, expectedTokens);
        assertEq(presaleToken.balanceOf(contributor1), initialUserBalance + expectedTokens);
        assertEq(presale.contributions(contributor1), 0);
        assertEq(presale.pool_tokenBalance(), initialContractTokenBalance - expectedTokens);
    }

    function test_Claim_Success_WithVesting() public {
        vm.startPrank(owner);
        Presale.PresaleOptions memory opts = optionsETH;
        opts.vestingPercentage = vestingPercentage;
        opts.vestingDuration = vestingDuration;
        opts.tokenDeposit = calculateDeposit(opts);
        presale = deployPresale(opts);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: softCap}(new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(owner);
        presale.finalize();
        vm.stopPrank();
        uint256 totalTokens = presale.userTokens(contributor1);
        uint256 expectedVestedTokens = (totalTokens * vestingPercentage) / Presale.BASIS_POINTS;
        uint256 expectedImmediateTokens = totalTokens - expectedVestedTokens;
        uint256 initialUserBalance = presaleToken.balanceOf(contributor1);
        uint256 initialVestingBalance = presaleToken.balanceOf(address(vesting));
        uint256 vestingCallCountBefore = vesting.createVestingCallCount();
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit IPresale.TokenClaim(contributor1, totalTokens, block.timestamp);
        vm.expectEmit(true, true, false, true);
        emit MockVesting.VestingCreated(contributor1, expectedVestedTokens, block.timestamp, vestingDuration, 0);
        uint256 claimedAmount = presale.claim();
        vm.stopPrank();
        assertEq(claimedAmount, totalTokens);
        assertEq(presaleToken.balanceOf(contributor1), initialUserBalance + expectedImmediateTokens);
        assertEq(vesting.createVestingCallCount(), vestingCallCountBefore + 1);
        assertEq(vesting.lastBeneficiary(), contributor1);
        assertEq(vesting.lastAmount(), expectedVestedTokens);
        assertEq(vesting.lastDuration(), vestingDuration);
        assertEq(presaleToken.balanceOf(address(vesting)), initialVestingBalance + expectedVestedTokens);
        assertEq(presale.contributions(contributor1), 0);
    }

    // ==========================================================================================
    // Test Cases: Refund
    // ==========================================================================================
    function test_Revert_Refund_NotRefundable() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: minContribution}(new bytes32[](0));
        vm.stopPrank();
        vm.prank(contributor1);
        vm.expectRevert(IPresale.NotRefundable.selector);
        presale.refund();
        vm.startPrank(owner);
        uint256 currentRaised = presale.pool_weiRaised();
        if (currentRaised < softCap) {
            vm.prank(contributor2);
            vm.deal(contributor2, softCap);
            presale.contribute{value: softCap - currentRaised}(new bytes32[](0));
            vm.stopPrank();
        }
        vm.prank(owner);
        presale.finalize();
        vm.stopPrank();
        vm.prank(contributor1);
        vm.expectRevert(IPresale.NotRefundable.selector);
        presale.refund();
    }

    function test_Revert_Refund_NoFundsToRefund() public {
        vm.startPrank(owner);
        _depositTokens();
        presale.cancel();
        vm.stopPrank();
        vm.prank(otherUser);
        vm.expectRevert(IPresale.NoFundsToRefund.selector);
        presale.refund();
    }

    function test_Refund_Success_Cancelled_ETH() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        uint256 initialUserBalance = contributor1.balance;
        uint256 initialContractBalance = address(presale).balance;
        uint256 initialTotalRefundable = presale.totalRefundable();
        vm.stopPrank();
        vm.startPrank(owner);
        presale.cancel();
        vm.stopPrank();
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Refund(contributor1, contributionAmount, block.timestamp);
        uint256 refundedAmount = presale.refund();
        vm.stopPrank();
        assertEq(refundedAmount, contributionAmount);
        assertEq(contributor1.balance, initialUserBalance + contributionAmount);
        assertEq(address(presale).balance, initialContractBalance - contributionAmount);
        assertEq(presale.contributions(contributor1), 0);
        assertEq(presale.totalRefundable(), initialTotalRefundable - contributionAmount);
    }

    function test_Refund_Success_FailedSoftCap_ETH() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        uint256 contributionAmount = softCap - 1 ether;
        vm.startPrank(contributor1);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        uint256 initialUserBalance = contributor1.balance;
        uint256 initialTotalRefundable = presale.totalRefundable();
        vm.stopPrank();
        vm.warp(end + 1 hours);
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Refund(contributor1, contributionAmount, block.timestamp);
        uint256 refundedAmount = presale.refund();
        vm.stopPrank();
        assertEq(refundedAmount, contributionAmount);
        assertEq(contributor1.balance, initialUserBalance + contributionAmount);
        assertEq(presale.contributions(contributor1), 0);
        assertEq(presale.totalRefundable(), initialTotalRefundable - contributionAmount);
    }

    function test_Refund_Success_Cancelled_Stablecoin() public {
        vm.startPrank(owner);
        presale = deployPresale(optionsStable);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        uint256 contributionAmount = optionsStable.min;
        vm.startPrank(contributor1);
        uint256 currentStableBalance = currencyToken.balanceOf(contributor1);
        if (currentStableBalance < contributionAmount) {
            currencyToken.mint(contributor1, contributionAmount - currentStableBalance);
        }
        currencyToken.approve(address(presale), contributionAmount);
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        uint256 initialUserStableBalance = currencyToken.balanceOf(contributor1);
        uint256 initialContractStableBalance = currencyToken.balanceOf(address(presale));
        uint256 initialTotalRefundable = presale.totalRefundable();
        vm.stopPrank();
        vm.startPrank(owner);
        presale.cancel();
        vm.stopPrank();
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Refund(contributor1, contributionAmount, block.timestamp);
        uint256 refundedAmount = presale.refund();
        vm.stopPrank();
        assertEq(refundedAmount, contributionAmount);
        assertEq(currencyToken.balanceOf(contributor1), initialUserStableBalance + contributionAmount);
        assertEq(currencyToken.balanceOf(address(presale)), initialContractStableBalance - contributionAmount);
        assertEq(presale.contributions(contributor1), 0);
        assertEq(presale.totalRefundable(), initialTotalRefundable - contributionAmount);
    }

    // ==========================================================================================
    // Test Cases: Cancel
    // ==========================================================================================
    function test_Revert_Cancel_NotOwner() public {
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.cancel();
    }

    function test_Revert_Cancel_Paused() public {
        vm.startPrank(owner);
        presale.pause();
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.cancel();
        vm.stopPrank();
    }

    function test_Revert_Cancel_WrongState() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Finalized)));
        presale.cancel();
    }

    function test_Cancel_Success() public {
        _depositTokens();
        uint256 depositAmount = optionsETH.tokenDeposit;
        uint256 ownerInitialBalance = presaleToken.balanceOf(owner);
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Cancel(owner, block.timestamp);
        vm.expectEmit(true, false, true, true);
        emit IPresale.LeftoverTokensReturned(depositAmount, owner);
        bool success = presale.cancel();
        assertTrue(success);
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Canceled));
        assertEq(presale.pool_tokenBalance(), 0);
        assertEq(presaleToken.balanceOf(address(presale)), 0);
        assertEq(presaleToken.balanceOf(owner), ownerInitialBalance + depositAmount);
    }

    // ==========================================================================================
    // Test Cases: Withdraw (Owner Proceeds)
    // ==========================================================================================
    function test_Revert_Withdraw_NotOwner() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.withdraw();
    }

    function test_Revert_Withdraw_NoFunds() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        vm.prank(owner);
        presale.withdraw();
        vm.expectRevert(IPresale.NoFundsToRefund.selector);
        presale.withdraw();
        vm.stopPrank();
    }

    function test_Withdraw_Success_ETH() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        uint256 expectedAmount = presale.ownerBalance();
        assertTrue(expectedAmount > 0, "Owner balance should be > 0");
        uint256 ownerInitialETH = owner.balance;
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit IPresale.Withdrawn(owner, expectedAmount);
        presale.withdraw();
        vm.stopPrank();
        assertEq(presale.ownerBalance(), 0);
        assertEq(owner.balance, ownerInitialETH + expectedAmount);
    }

    function test_Withdraw_Success_Stablecoin() public {
        test_Finalize_Success_Stablecoin();
        uint256 expectedAmount = presale.ownerBalance();
        assertTrue(expectedAmount > 0, "Owner stable balance should be > 0");
        uint256 ownerInitialStable = currencyToken.balanceOf(owner);
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit IPresale.Withdrawn(owner, expectedAmount);
        presale.withdraw();
        vm.stopPrank();
        assertEq(presale.ownerBalance(), 0);
        assertEq(currencyToken.balanceOf(owner), ownerInitialStable + expectedAmount);
    }

    // ==========================================================================================
    // Test Cases: Admin Functions (Flow related)
    // ==========================================================================================
    function test_ExtendClaimDeadline() public {
        test_Finalize_Success_ETH_LeftoverReturn();
        uint256 oldDeadline = presale.claimDeadline();
        uint256 newDeadline = oldDeadline + 1 days;
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit IPresale.ClaimDeadlineExtended(newDeadline);
        presale.extendClaimDeadline(newDeadline);
        assertEq(presale.claimDeadline(), newDeadline);
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.extendClaimDeadline(newDeadline + 1 days);
        vm.prank(owner);
        vm.expectRevert(IPresale.InvalidDeadline.selector);
        presale.extendClaimDeadline(newDeadline);
        vm.expectRevert(IPresale.InvalidDeadline.selector);
        presale.extendClaimDeadline(oldDeadline);
        vm.stopPrank();
    }

    function test_RescueTokens() public {
        MockERC20 rescueToken = new MockERC20("Rescue Me", "ESC", 1000 ether);
        vm.prank(owner);
        rescueToken.mint(address(presale), 100 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.expectRevert(IPresale.CannotRescueBeforeFinalization.selector);
        presale.rescueTokens(address(rescueToken), owner, 50 ether);
        vm.stopPrank();
        test_Finalize_Success_ETH_LeftoverReturn();
        uint256 deadline = presale.claimDeadline();
        vm.startPrank(owner);
        if (presaleToken.balanceOf(address(presale)) > 0) {
            vm.expectRevert(IPresale.CannotRescuePresaleTokens.selector);
            presale.rescueTokens(address(presaleToken), owner, 1);
        }
        vm.warp(deadline + 1 days);
        uint256 presaleTokenBalance = presaleToken.balanceOf(address(presale));
        if (presaleTokenBalance > 0) {
            vm.expectEmit(true, true, true, true);
            emit IPresale.TokensRescued(address(presaleToken), owner, presaleTokenBalance);
            uint256 ownerPresaleTokenBefore = presaleToken.balanceOf(owner);
            presale.rescueTokens(address(presaleToken), owner, presaleTokenBalance);
            assertEq(presaleToken.balanceOf(address(presale)), 0);
            assertEq(presaleToken.balanceOf(owner), ownerPresaleTokenBefore + presaleTokenBalance);
        }
        vm.prank(owner);
        rescueToken.mint(address(presale), 100 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        uint256 rescueAmount = 50 ether;
        uint256 ownerInitialRescue = rescueToken.balanceOf(owner);
        uint256 presaleInitialRescue = rescueToken.balanceOf(address(presale));
        vm.expectEmit(true, true, true, true);
        emit IPresale.TokensRescued(address(rescueToken), owner, rescueAmount);
        presale.rescueTokens(address(rescueToken), owner, rescueAmount);
        assertEq(rescueToken.balanceOf(owner), ownerInitialRescue + rescueAmount);
        assertEq(rescueToken.balanceOf(address(presale)), presaleInitialRescue - rescueAmount);
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.rescueTokens(address(rescueToken), otherUser, 1 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.expectRevert(IPresale.InvalidAddress.selector);
        presale.rescueTokens(address(rescueToken), address(0), 1 ether);
        vm.stopPrank();
    }
}
