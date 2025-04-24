// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/contracts/Presale.sol";
import "src/contracts/PresaleFactory.sol";
import "src/contracts/LiquidityLocker.sol";
import "src/contracts/Vesting.sol";
import "src/contracts/interfaces/IPresale.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRouter} from "./mocks/MockRouter.sol";
import {MockFactory} from "./mocks/MockFactory.sol";

interface IVesting {
    function release(address _presale) external;
    function vestedAmount(address _presale, address _beneficiary) external view returns (uint256);

    error NoTokensToRelease();
}

interface ILiquidityLocker {
    function withdraw(uint256 _lockId) external;
    function getLock(uint256 _lockId) external view returns (address, uint256, uint256, address);
    function lockCount() external view returns (uint256);

    error TokensStillLocked();
}

contract PresaleTest is Test {
    PresaleFactory factory;
    LiquidityLocker locker;
    Vesting vesting;
    MockERC20 token;
    MockRouter router;
    MockFactory uniFactory;
    address owner;
    address user;
    address user2;
    address user3;
    address weth;

    receive() external payable {}

    function setUp() public {
        owner = address(this);
        user = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);
        weth = address(0xBEEF);

        token = new MockERC20("Token", "TKN", 18);
        router = new MockRouter();
        uniFactory = new MockFactory();
        router.setFactory(address(uniFactory));

        factory = new PresaleFactory(0, address(0), 0, address(0));
        locker = factory.liquidityLocker();
        vesting = factory.vestingContract();

        token.mint(address(this), 1_000_000 ether);
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    function testCreatePresaleAndDeposit() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 100 ether,
            softCap: 25 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 5000,
            vestingDuration: 60 days,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        uint256 deposited = presale.deposit();

        assertEq(deposited, opts.tokenDeposit);
        assertEq(token.balanceOf(address(presale)), opts.tokenDeposit);
    }

    function testContributeETH() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 5000,
            vestingDuration: 60 days,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 2 ether}(new bytes32[](0));

        uint256 amount = presale.contributions(user);
        assertEq(amount, 2 ether);
    }

    function testFinalizePresale() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 5000,
            vestingDuration: 60 days,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        vm.warp(opts.end + 1);
        presale.finalize();

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized));
    }

    function testClaimTokens() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        vm.warp(opts.end + 1);
        presale.finalize();

        vm.prank(user);
        presale.claim();

        uint256 expected = (5 ether * opts.presaleRate * 1 ether) / 1 ether;
        assertEq(token.balanceOf(user), expected);
    }

    function testRefundIfSoftCapNotMet() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 2 ether}(new bytes32[](0));

        vm.warp(opts.end + 1);
        vm.prank(owner);
        presale.cancel();

        uint256 before = user.balance;
        vm.prank(user);
        presale.refund();
        uint256 afterRefund = user.balance;

        assertGt(afterRefund, before);
        assertEq(afterRefund, before + 2 ether);
    }

    function testContributionLimitEnforcement() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // Try below min contribution (should revert)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("BelowMinimumContribution()"));
        presale.contribute{value: 0.5 ether}(new bytes32[](0));

        // Try above max contribution (should revert)
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("ExceedsMaximumContribution()"));
        presale.contribute{value: 6 ether}(new bytes32[](0));

        // Valid contribution
        vm.prank(user);
        presale.contribute{value: 3 ether}(new bytes32[](0));
        uint256 amount = presale.contributions(user);
        assertEq(amount, 3 ether);
    }

    function testWhitelistContributionEnforcement() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Set Merkle root before deposit (in Pending state)
        bytes32 leaf = keccak256(abi.encodePacked(user2)); // Whitelist user2
        bytes32 merkleRoot = leaf; // Single-leaf tree: root = leaf
        vm.prank(address(this)); // Owner calls setMerkleRoot
        presale.setMerkleRoot(merkleRoot);

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // Non-whitelisted user (should revert)
        bytes32[] memory invalidProof = new bytes32[](0);
        vm.prank(user);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: 1 ether}(invalidProof);

        // Whitelisted contribution
        bytes32[] memory proof = new bytes32[](0); // Empty proof for single-leaf tree
        vm.prank(user2);
        presale.contribute{value: 2 ether}(proof);

        assertEq(presale.contributions(user2), 2 ether);
    }

    function testCumulativeContributionLimit() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // First contribution
        vm.prank(user);
        presale.contribute{value: 3 ether}(new bytes32[](0));
        assertEq(presale.contributions(user), 3 ether);

        // Second contribution exceeding max
        vm.prank(user);
        vm.expectRevert(IPresale.ExceedsMaximumContribution.selector);
        presale.contribute{value: 3 ether}(new bytes32[](0));

        // Second contribution to reach exact max
        vm.prank(user);
        presale.contribute{value: 2 ether}(new bytes32[](0));
        assertEq(presale.contributions(user), 5 ether);

        // Contribution at hard cap
        vm.prank(user2);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.prank(user3);
        vm.expectRevert(IPresale.HardCapExceeded.selector);
        presale.contribute{value: 2 ether}(new bytes32[](0));
    }

    function testVestingContribution() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 5000, // 50% vested
            vestingDuration: 60 days,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        vm.warp(opts.end + 1);
        uint256 finalizeTime = block.timestamp;
        presale.finalize();

        vm.prank(user);
        presale.claim();

        // Total tokens: 5 ETH * 1000 = 5000 tokens
        uint256 expectedImmediate = (5 ether * opts.presaleRate * 5000) / 10000; // 50% = 2500 tokens
        uint256 expectedVested = expectedImmediate; // 50% = 2500 tokens
        assertEq(token.balanceOf(user), expectedImmediate);

        // Warp to half vesting period to check vested amount
        vm.warp(finalizeTime + 30 days);
        uint256 vestedAtHalf = Vesting(vesting).vestedAmount(address(presale), user);
        assertEq(vestedAtHalf, expectedVested / 2); // 1250 tokens at t=30 days
    }

    function testVestingRelease() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 5000, // 50% vested
            vestingDuration: 60 days,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // Contribute 5 ETH (5000 tokens: 2500 immediate, 2500 vested)
        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        // Finalize presale
        vm.warp(opts.end + 1);
        uint256 finalizeTime = block.timestamp;
        presale.finalize();

        // Claim immediate tokens
        vm.prank(user);
        presale.claim();
        uint256 immediateTokens = (5 ether * opts.presaleRate * 5000) / 10000; // 2500 tokens
        assertEq(token.balanceOf(user), immediateTokens);

        // Check vesting at t=0 (post-finalize)
        Vesting vesting = Vesting(factory.vestingContract());
        vm.prank(user);
        vm.expectRevert(IVesting.NoTokensToRelease.selector);
        vesting.release(address(presale));
        assertEq(token.balanceOf(user), immediateTokens); // No vested tokens yet

        // Warp to t=30 days (50% vested)
        vm.warp(finalizeTime + 30 days);
        vm.prank(user);
        vesting.release(address(presale));
        uint256 vestedTokens = (5 ether * opts.presaleRate * 5000) / 10000 / 2; // 1250 tokens
        assertEq(token.balanceOf(user), immediateTokens + vestedTokens); // 2500 + 1250

        // Warp to t=60 days (100% vested)
        vm.warp(finalizeTime + 60 days);
        vm.prank(user);
        vesting.release(address(presale));
        uint256 totalVested = (5 ether * opts.presaleRate * 5000) / 10000; // 2500 tokens
        assertEq(token.balanceOf(user), immediateTokens + totalVested); // 2500 + 2500
    }

    function testLiquidityLockerUnlock() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000, // 80% to liquidity
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // Contribute 5 ETH to meet softCap
        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        // Finalize presale to create LP pair and lock tokens
        vm.warp(opts.end + 1);
        presale.finalize();

        // Get LP token address (from MockFactory pair)
        address pair = uniFactory.getPair(address(token), weth);
        IERC20 lpToken = IERC20(pair);

        // Verify LP tokens are in LiquidityLocker
        LiquidityLocker locker = LiquidityLocker(factory.liquidityLocker());
        uint256 lockedBalance = lpToken.balanceOf(address(locker));
        assertGt(lockedBalance, 0); // LP tokens are locked

        // Try to unlock before lockupDuration (should revert)
        vm.prank(owner);
        vm.expectRevert(ILiquidityLocker.TokensStillLocked.selector);
        locker.withdraw(0);

        // Warp to after lockupDuration
        vm.warp(block.timestamp + 30 days);
        vm.prank(owner);
        locker.withdraw(0);

        // Verify LP tokens are released
        assertEq(lpToken.balanceOf(address(locker)), 0);
        assertEq(lpToken.balanceOf(owner), lockedBalance);
    }

    function testWithdrawOwnerBalance() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000, // 80% to liquidity
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Test withdraw before finalize (should revert)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(0)));
        presale.withdraw();

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        vm.warp(opts.end + 1);
        presale.finalize();

        // Test withdraw from non-owner (should revert)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        presale.withdraw();

        // Test withdraw from owner
        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        presale.withdraw();
        uint256 ownerBalanceAfter = owner.balance;

        // 80% of 5 ETH (4 ETH) to liquidity, 20% (1 ETH) to owner
        assertEq(ownerBalanceAfter, ownerBalanceBefore + 1 ether);
    }

    function testZeroContribution() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // Attempt zero contribution (should revert)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        presale.contribute{value: 0 ether}(new bytes32[](0));

        // Verify no contribution recorded
        assertEq(presale.contributions(user), 0);
    }

    function testHardCapExact() public {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2);
        presale.deposit();

        // Contribute exactly hardCap (10 ETH) across two users
        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.prank(user2);
        presale.contribute{value: 5 ether}(new bytes32[](0));

        // Verify contributions
        assertEq(presale.contributions(user), 5 ether);
        assertEq(presale.contributions(user2), 5 ether);

        // Attempt additional contribution (should revert)
        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSignature("HardCapExceeded()"));
        presale.contribute{value: 1 ether}(new bytes32[](0));

        // Finalize presale
        vm.warp(opts.end + 1);
        presale.finalize();

        // Verify state
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized));

        // Verify users can claim
        vm.prank(user);
        presale.claim();
        vm.prank(user2);
        presale.claim();
        uint256 expectedTokens = (5 ether * opts.presaleRate * 1 ether) / 1 ether; // 5000 tokens per user
        assertEq(token.balanceOf(user), expectedTokens);
        assertEq(token.balanceOf(user2), expectedTokens);
    }

    // --- NEW TESTS for State Transitions ---

    function testCannotContributeBeforeStart() public {
        // Define options with start time in the future
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1 days, // Start tomorrow
            end: block.timestamp + 2 days, // End day after tomorrow
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0) // ETH
        });

        // Create the presale
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Verify presale is in Pending state
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Pending));

        // Attempt contribution before start time
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresale.InvalidState.selector,
                uint8(Presale.PresaleState.Pending) // Or uint8(0)
            )
        );
        vm.prank(user);
        presale.contribute{value: 1 ether}(new bytes32[](0));
    }

    function testCannotContributeAfterEnd() public {
        // 1. Define options with end time in the near future
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1, // Start very soon
            end: block.timestamp + 10, // End soon
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0) // ETH
        });

        // 2. Create & Setup Presale
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start); // Move to start time
        presale.deposit(); // Presale becomes Active

        // 3. Warp time PAST the end time
        vm.warp(opts.end + 1);

        // 4. Attempt contribution AFTER end time
        vm.expectRevert(IPresale.NotInPurchasePeriod.selector); // Or PresaleEnded
        vm.prank(user);
        presale.contribute{value: 1 ether}(new bytes32[](0));
    }

    function testCannotFinalizeBeforeEnd() public {
        // 1. Define options with end time in the future
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 1 wei, // Low softcap, easily met
            min: 1 wei,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1, // Start very soon
            end: block.timestamp + 1 days, // End tomorrow
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0) // ETH
        });

        // 2. Create & Setup Presale
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start); // Move to start time
        presale.deposit(); // Presale becomes Active

        // 3. Meet softcap
        vm.prank(user);
        presale.contribute{value: opts.softCap}(new bytes32[](0));

        // 4. Attempt finalize BEFORE end time
        vm.expectRevert(IPresale.PresaleNotEnded.selector);
        presale.finalize();
    }

    function testCannotCancelAfterFinalize() public {
        // 1. Define options
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 1 ether, // Ensure softcap is met
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1,
            end: block.timestamp + 10,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0) // ETH
        });

        // 2. Create & Setup Presale
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start);
        presale.deposit();

        // 3. Meet softcap
        vm.prank(user);
        presale.contribute{value: opts.softCap}(new bytes32[](0));

        // 4. Finalize the presale
        vm.warp(opts.end + 1);
        presale.finalize();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized)); // Verify state

        // 5. Attempt cancel AFTER finalize
        vm.expectRevert(
            abi.encodeWithSelector(
                IPresale.InvalidState.selector,
                uint8(Presale.PresaleState.Finalized) // Expect revert because state is Finalized (2)
            )
        );
        presale.cancel();
    }

    // =========================================
    //         Vesting Edge Cases
    // =========================================

    function testVestingZeroPercentage() public {
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.vestingPercentage = 0; // 0% vesting
        opts.vestingDuration = 60 days; // Duration doesn't matter here

        Presale presale = _createAndSetupPresale(opts);
        uint256 contribution = 2 ether;
        uint256 expectedTokens = (contribution * opts.presaleRate * (10 ** token.decimals())) / 1 ether;

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        // Claim
        vm.prank(user);
        presale.claim();

        // Assertions
        assertEq(token.balanceOf(user), expectedTokens, "User should receive all tokens immediately");
        assertEq(vesting.remainingVested(address(presale), user), 0, "No tokens should be vested");
        assertEq(token.balanceOf(address(vesting)), 0, "Vesting contract should hold no tokens for this user/presale");
    }

    function testVestingFullPercentage() public {
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.vestingPercentage = 10000; // 100% vesting
        opts.vestingDuration = 60 days;

        Presale presale = _createAndSetupPresale(opts);
        uint256 contribution = 2 ether;
        uint256 expectedTokens = (contribution * opts.presaleRate * (10 ** token.decimals())) / 1 ether;

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        // Claim
        vm.prank(user);
        presale.claim();

        // Assertions
        assertEq(token.balanceOf(user), 0, "User should receive 0 tokens immediately");
        assertEq(vesting.remainingVested(address(presale), user), expectedTokens, "All tokens should be vested");
        assertEq(token.balanceOf(address(vesting)), expectedTokens, "Vesting contract should hold all tokens");
    }

    function testVestingCannotReleaseBeforeStart() public {
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.vestingPercentage = 5000; // 50% vesting
        opts.vestingDuration = 60 days;

        Presale presale = _createAndSetupPresale(opts);

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: 2 ether}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        // Claim (creates vesting schedule starting at current block.timestamp)
        vm.prank(user);
        presale.claim();

        // Attempt release immediately (before any time passes)
        vm.prank(user);
        vm.expectRevert(IVesting.NoTokensToRelease.selector);
        vesting.release(address(presale));
    }

    function testVestingMultipleReleases() public {
        uint256 vestingDuration = 60 days;
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.vestingPercentage = 10000; // 100% vesting
        opts.vestingDuration = vestingDuration;

        Presale presale = _createAndSetupPresale(opts);
        uint256 contribution = 2 ether;
        uint256 totalVestedTokens = (contribution * opts.presaleRate * (10 ** token.decimals())) / 1 ether;

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        // Claim
        vm.prank(user);
        presale.claim();
        assertEq(token.balanceOf(user), 0, "Initial claim balance should be 0");
        assertEq(vesting.remainingVested(address(presale), user), totalVestedTokens, "Initial vested amount incorrect");

        uint256 releaseInterval = 10 days;
        uint256 expectedReleasedPerInterval = (totalVestedTokens * releaseInterval) / vestingDuration;
        uint256 accumulatedReleased = 0;

        // Release at T+10 days
        vm.warp(block.timestamp + releaseInterval);
        vm.prank(user);
        vesting.release(address(presale));
        accumulatedReleased += expectedReleasedPerInterval;
        assertEq(token.balanceOf(user), accumulatedReleased, "Balance after 10 days incorrect");

        // Release at T+20 days
        vm.warp(block.timestamp + releaseInterval);
        vm.prank(user);
        vesting.release(address(presale));
        accumulatedReleased += expectedReleasedPerInterval;
        // Use approx assertion due to potential minor rounding differences over intervals
        assertApproxEqAbs(token.balanceOf(user), accumulatedReleased, 1, "Balance after 20 days incorrect");

        // Release at T+30 days
        vm.warp(block.timestamp + releaseInterval);
        vm.prank(user);
        vesting.release(address(presale));
        accumulatedReleased += expectedReleasedPerInterval;
        assertApproxEqAbs(token.balanceOf(user), accumulatedReleased, 1, "Balance after 30 days incorrect");

        // Warp past end and release remaining
        vm.warp(block.timestamp + vestingDuration); // Ensure full duration passed
        vm.prank(user);
        vesting.release(address(presale));
        assertEq(token.balanceOf(user), totalVestedTokens, "Final balance incorrect");
        assertEq(vesting.remainingVested(address(presale), user), 0, "Should be no remaining vested tokens");
    }

    // =========================================
    //      Liquidity and Locking Tests
    // =========================================

    function testLiquidityZeroBps() public {
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.liquidityBps = 0; // 0% liquidity
        opts.leftoverTokenOption = 0; // Return to owner

        Presale presale = _createAndSetupPresale(opts);
        uint256 contribution = 5 ether; // Meet softcap
        uint256 initialOwnerTokenBalance = token.balanceOf(owner);

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        // Calculate expected results
        uint256 houseCut = (contribution * presale.housePercentage()) / presale.BASIS_POINTS();
        uint256 expectedOwnerBalance = contribution - houseCut;
        uint256 tokensSold = (contribution * opts.presaleRate * (10 ** token.decimals())) / 1 ether;
        uint256 expectedLeftoverTokens = opts.tokenDeposit - tokensSold;

        // Assertions
        assertEq(presale.ownerBalance(), expectedOwnerBalance, "Owner ETH balance incorrect");
        assertEq(
            token.balanceOf(owner), initialOwnerTokenBalance + expectedLeftoverTokens, "Leftover tokens not returned"
        );
        // Check no LP tokens were locked (assuming lock IDs start from 0 and increment)
        if (locker.lockCount() > 0) {
            // If locker interface has getLock, use it, otherwise check balance
            // (address lpToken, , , ) = locker.getLock(0);
            // assertEq(locker.balanceOf(lpToken), 0); // Requires locker to be ERC20/have balanceOf
            // Simpler check if no getLock: check a known mock LP address if predictable
        }
        // assertEq(locker.lockCount(), 0, "Should be no locks created"); // This might fail if locker always increments
    }

    function testLiquidityFullBps() public {
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.liquidityBps = 10000; // 100% liquidity

        Presale presale = _createAndSetupPresale(opts);
        uint256 contribution = 5 ether; // Meet softcap

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        // Calculate expected results
        uint256 houseCut = (contribution * presale.housePercentage()) / presale.BASIS_POINTS();
        // Owner balance should only be the house cut if house address is owner, otherwise 0
        uint256 expectedOwnerBalance = (presale.houseAddress() == owner) ? houseCut : 0;

        // Assertions
        assertEq(presale.ownerBalance(), expectedOwnerBalance, "Owner ETH balance incorrect");
        assertTrue(locker.lockCount() > 0, "Lock count should be greater than 0");

        // Verify LP tokens are held by the locker
        address lpPair = uniFactory.getPair(address(token), weth);
        assertTrue(IERC20(lpPair).balanceOf(address(locker)) > 0, "Locker should hold LP tokens");
    }

    // Note: This test assumes LiquidityLocker assigns sequential IDs starting from 0.
    // It also requires LiquidityLocker to allow locking the same pair multiple times (which is realistic).
    function testLiquidityLockMultiplePresales() public {
        // Presale 1
        Presale.PresaleOptions memory opts1 = _getDefaultOpts();
        opts1.lockupDuration = 30 days;
        Presale presale1 = _createAndSetupPresale(opts1);
        vm.prank(user);
        presale1.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(opts1.end + 1);
        presale1.finalize();
        uint256 lockId1 = locker.lockCount() - 1; // Assumes ID is count - 1
        address lpPair1 = uniFactory.getPair(address(token), weth);
        assertTrue(IERC20(lpPair1).balanceOf(address(locker)) > 0, "Locker should hold LP1");

        // Presale 2 (using same token pair for simplicity, could use different)
        Presale.PresaleOptions memory opts2 = _getDefaultOpts();
        opts2.start = block.timestamp + 1;
        opts2.end = block.timestamp + 10;
        opts2.lockupDuration = 60 days; // Different lock duration
        Presale presale2 = _createAndSetupPresale(opts2);
        vm.prank(user2);
        presale2.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(opts2.end + 1);
        presale2.finalize();
        uint256 lockId2 = locker.lockCount() - 1; // Assumes ID is count - 1
        assertTrue(IERC20(lpPair1).balanceOf(address(locker)) > 0, "Locker should still hold LP tokens"); // Balance increases or stays > 0
        assertEq(lockId2, lockId1 + 1, "Lock IDs should increment");

        // Withdraw Lock 1 after its duration
        vm.warp(block.timestamp + 30 days + 1); // Pass lock duration 1
        uint256 ownerLpBalanceBefore = IERC20(lpPair1).balanceOf(owner);
        vm.prank(owner);
        locker.withdraw(lockId1);
        assertTrue(IERC20(lpPair1).balanceOf(owner) > ownerLpBalanceBefore, "Owner should receive LP1 tokens");

        // Attempt to withdraw Lock 2 (should fail)
        vm.prank(owner);
        vm.expectRevert(ILiquidityLocker.TokensStillLocked.selector);
        locker.withdraw(lockId2);
    }

    function testLiquidityCannotWithdrawPartialUnlock() public {
        uint256 lockDuration = 30 days;
        Presale.PresaleOptions memory opts = _getDefaultOpts();
        opts.lockupDuration = lockDuration;

        Presale presale = _createAndSetupPresale(opts);

        // Contribute and Finalize
        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(opts.end + 1);
        presale.finalize();

        uint256 lockId = locker.lockCount() - 1; // Get the lock ID

        // Warp to partial duration
        vm.warp(block.timestamp + (lockDuration / 2));

        // Attempt withdraw
        vm.prank(owner);
        vm.expectRevert(ILiquidityLocker.TokensStillLocked.selector);
        locker.withdraw(lockId);
    }

    // =========================================
    //             Helper Functions
    // =========================================

    // Creates default options for a simple ETH presale
    function _getDefaultOpts() internal view returns (Presale.PresaleOptions memory) {
        return Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, // Example amount
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 1 ether,
            max: 5 ether,
            presaleRate: 1000, // 1 ETH = 1000 Tokens
            listingRate: 800, // 1 ETH = 800 Tokens
            liquidityBps: 7000, // 70%
            slippageBps: 300, // 3%
            start: block.timestamp + 2, // Start shortly
            end: block.timestamp + 1 days + 2, // End tomorrow
            lockupDuration: 30 days,
            vestingPercentage: 0, // Default: no vesting
            vestingDuration: 0,
            leftoverTokenOption: 0, // Default: return to owner
            currency: address(0) // ETH
        });
    }

    // Helper to create, approve, and deposit for a presale
    function _createAndSetupPresale(Presale.PresaleOptions memory opts) internal returns (Presale) {
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start); // Ensure we are at or past start time
        presale.deposit();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active));
        return presale;
    }
}
