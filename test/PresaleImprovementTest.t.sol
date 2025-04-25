// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";// For whitelist tests
import {Presale} from "../src/contracts/Presale.sol";
import {IPresale} from "src/contracts/interfaces/IPresale.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {PresaleFactory} from "../src/contracts/PresaleFactory.sol";
import {Vesting} from "../src/contracts/Vesting.sol";
import {LiquidityLocker} from "../src/contracts/LiquidityLocker.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRouter} from "./mocks/MockRouter.sol";
import {MockFactory} from "./mocks/MockFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For revert selector
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // For revert selector
import {MaliciousReentrantContributor, MaliciousReentrantClaimer } from "test/mocks/MaliciousReentrant.sol"; 
import {MockERC20Reverting} from "test/mocks/MockERC20Reverting.sol"; // For reentrancy tests

contract PresaleImprovementTest is Test {
    // --- Existing Setup ---
    PresaleFactory factory;
    LiquidityLocker locker;
    Vesting vesting;
    MockERC20 token;
    MockERC20 stablecoin; // For stablecoin tests if needed
    MockRouter router;
    MockFactory uniswapFactory;
    address weth; // Use a real WETH address or mock

    address owner; // Presale creator/owner
    address user;
    address user2;
    address nonOwner;
    address houseAddress;

    uint256 constant DEFAULT_VESTING_DURATION = 30 days;
    uint256 constant DEFAULT_LOCKUP_DURATION = 60 days;

    function setUp() public virtual {
        owner = makeAddr("owner");
        user = makeAddr("user");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        houseAddress = makeAddr("house");

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(user2, "User2");
        vm.label(nonOwner, "NonOwner");
        vm.label(houseAddress, "House");

        // Deploy Mocks
        token = new MockERC20("Test Token", "TKN", 18);
        stablecoin = new MockERC20("Stable Coin", "STBL", 6); // Example 6 decimals
        weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mainnet WETH or deploy mock
        uniswapFactory = new MockFactory();
        router = new MockRouter();

        // Deploy Core Contracts via Factory
        vm.startPrank(owner);
        factory = new PresaleFactory(0, address(0), 100, houseAddress); // 1% house fee
        locker = LiquidityLocker(factory.liquidityLocker());
        vesting = Vesting(factory.vestingContract());
        vm.stopPrank();

        // Fund accounts
        token.mint(owner, 1_000_000 ether);
        token.mint(user, 1_000_000 ether); // For testing transfers if needed
        stablecoin.mint(user, 1_000_000 * 1e6);
        stablecoin.mint(user2, 1_000_000 * 1e6);

        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(nonOwner, 100 ether);
        vm.deal(owner, 100 ether);
    }

    // --- Helper Function for Presale Creation ---
    function createDefaultPresale(uint256 leftoverOption, uint256 vestingPercent)
        internal
        returns (Presale presale, Presale.PresaleOptions memory opts)
    {
        opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, // Needs 500k for presale, 80k for liquidity
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 50_000, // 1 ETH = 50,000 TKN
            listingRate: 40_000, // 1 ETH = 40,000 TKN
            liquidityBps: 8000, // 80%
            slippageBps: 300, // 3%
            start: block.timestamp + 1 hours,
            end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION,
            vestingPercentage: vestingPercent, // e.g., 0 or 5000 (50%)
            vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: leftoverOption, // 0: Owner, 1: Burn, 2: Vest
            currency: address(0) // ETH presale
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        presale = Presale(payable(presaleAddr));

        // Grant roles (assuming factory doesn't do this automatically for owner)
        // If factory grants roles, these might not be needed or might need different sender
        vm.prank(owner);
        locker.grantRole(locker.DEFAULT_ADMIN_ROLE(), owner); // Example: Owner needs admin
        vesting.grantRole(vesting.DEFAULT_ADMIN_ROLE(), owner); // Example: Owner needs admin
        vesting.grantRole(vesting.VESTER_ROLE(), address(factory)); // Factory needs to be able to vest
        locker.grantRole(locker.LOCKER_ROLE(), address(factory)); // Factory needs to be able to lock

        // Approve and deposit
        vm.prank(owner);
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes); // Ensure deposit happens before start
        presale.deposit();
        vm.warp(opts.start + 1); // Move time to active presale
    }

     // --- Helper for Merkle Proofs ---
    using MerkleProof for bytes32;
    bytes32 root;
    mapping(address => bytes32[]) proofs;

    function _setupWhitelist(address[] memory _whitelistees) internal {
        bytes32[] memory leaves = new bytes32[](_whitelistees.length);
        for (uint i = 0; i < _whitelistees.length; i++) {
            leaves[i] = keccak256(abi.encodePacked((_whitelistees[i])));
        }
        root = MerkleProof.processMultiProof(new bytes32[](0), new bool[](0), leaves);

        for (uint i = 0; i < _whitelistees.length; i++) {
            bytes32[] memory proof = new bytes32[](0);
            proofs[_whitelistees[i]] = proof;
            proofs[_whitelistees[i]][0] = keccak256(abi.encodePacked(_whitelistees[i]));
        } 
    }


    // ============================================
    // ==      Leftover Token Handling Tests     ==
    // ============================================

    function testLeftoverTokenOptionBurn() public {
        uint256 leftoverOption = 1; // Burn
        (Presale presale, Presale.PresaleOptions memory opts) = createDefaultPresale(leftoverOption, 0);

        // Contribute less than hardcap
        uint256 contribution = opts.softCap + 1 ether; // Ensure softcap met
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));

        // Calculate expected leftovers
        uint256 tokensForPresale = (opts.hardCap * opts.presaleRate * (10**token.decimals())) / 1 ether;
        uint256 currencyForLiquidity = (contribution * opts.liquidityBps) / 10000; // Based on actual raised
        uint256 tokensForLiquidity = (currencyForLiquidity * opts.listingRate * (10**token.decimals())) / 1 ether;
        uint256 tokensSold = (contribution * opts.presaleRate * (10**token.decimals())) / 1 ether;
        uint256 expectedLeftovers = opts.tokenDeposit - tokensForLiquidity - tokensSold;

        // Finalize
        vm.warp(opts.end + 1);
        uint256 balanceBeforeBurn = token.balanceOf(address(0));
        uint256 supplyBeforeBurn = token.totalSupply();

        vm.prank(owner);
        presale.finalize();

        // Assertions
        // Option 1: Check balance of address(0) if burn transfers there
         assertEq(token.balanceOf(address(0)), balanceBeforeBurn + expectedLeftovers, "Burn address balance mismatch");
        // Option 2: Check total supply if burn actually burns
        // assertEq(token.totalSupply(), supplyBeforeBurn - expectedLeftovers, "Total supply after burn mismatch");

        assertEq(token.balanceOf(address(presale)), 0, "Presale should have 0 tokens left");
        assertEq(token.balanceOf(owner), 0, "Owner should not receive tokens"); // Assuming owner started with 0 for this test run context
    }

    function testLeftoverTokenOptionVest() public {
        uint256 leftoverOption = 2; // Vest for owner
        (Presale presale, Presale.PresaleOptions memory opts) = createDefaultPresale(leftoverOption, 0);

        // Contribute less than hardcap
        uint256 contribution = opts.softCap + 1 ether; // Ensure softcap met
        vm.prank(user);
        presale.contribute{value: contribution}(new bytes32[](0));

        // Calculate expected leftovers
        uint256 tokensForPresale = (opts.hardCap * opts.presaleRate * (10**token.decimals())) / 1 ether;
        uint256 currencyForLiquidity = (contribution * opts.liquidityBps) / 10000; // Based on actual raised
        uint256 tokensForLiquidity = (currencyForLiquidity * opts.listingRate * (10**token.decimals())) / 1 ether;
        uint256 tokensSold = (contribution * opts.presaleRate * (10**token.decimals())) / 1 ether;
        uint256 expectedLeftovers = opts.tokenDeposit - tokensForLiquidity - tokensSold;

        // Finalize
        vm.warp(opts.end + 1);
        uint256 vestingBalanceBefore = token.balanceOf(address(vesting));

        vm.prank(owner);
        presale.finalize();

       // Assertions
        (uint256 amount, address userAddress, uint256 start, uint256 duration, uint256 released, uint256 revoked) = vesting.schedules(address(presale), address(owner));

        assertEq(amount, expectedLeftovers, "Owner vesting amount mismatch");
        assertEq(userAddress, owner, "Owner vesting beneficiary mismatch"); // Beneficiary should be owner
        assertEq(start, block.timestamp, "Owner vesting start time mismatch"); // Starts at finalize time
        assertEq(duration, opts.vestingDuration, "Owner vesting duration mismatch");
        assertEq(released, 0, "Owner vesting released mismatch");
        assertEq(revoked, 0, "Owner vesting revoked mismatch");
        assertEq(token.balanceOf(address(vesting)), vestingBalanceBefore + expectedLeftovers, "Vesting contract balance mismatch");
        assertEq(token.balanceOf(address(presale)), 0, "Presale should have 0 tokens left");
    }

    function testNoLeftoverTokens() public {
        // Setup options to consume all tokens
        uint256 hardCap = 10 ether;
        uint256 presaleRate = 50_000;
        uint256 listingRate = 40_000;
        uint256 liquidityBps = 10000; // 100% liquidity

        uint256 tokensForSale = (hardCap * presaleRate * (10**token.decimals())) / 1 ether;
        uint256 currencyForLiq = (hardCap * liquidityBps) / 10000; // Will be == hardCap
        uint256 tokensForLiq = (currencyForLiq * listingRate * (10**token.decimals())) / 1 ether;
        uint256 totalDepositNeeded = tokensForSale + tokensForLiq;

         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: totalDepositNeeded, // Exact amount
            hardCap: hardCap,
            softCap: 1 ether, // Low softcap
            min: 0.1 ether,
            max: hardCap, // Allow full contribution
            presaleRate: presaleRate,
            listingRate: listingRate,
            liquidityBps: liquidityBps, // 100%
            slippageBps: 300,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION,
            vestingPercentage: 0,
            vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, // Return to owner (should be 0)
            currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        vm.prank(owner);
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes);
        presale.deposit();
        vm.warp(opts.start + 1);

        // Contribute exactly hardcap
        vm.prank(user);
        presale.contribute{value: hardCap}(new bytes32[](0));
        assertEq(presale.totalRaised(), hardCap);

        // Finalize
        vm.warp(opts.end + 1);
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        presale.finalize();

        // Assertions
        assertEq(token.balanceOf(owner), ownerBalanceBefore, "Owner should receive no leftover tokens");
        assertEq(token.balanceOf(address(presale)), 0, "Presale contract should have 0 tokens");
        // Check LP token balance locked for owner
        address pair = uniswapFactory.getPair(address(token), weth);        
        (, uint256 totalAmount, , ) = locker.getLock(locker.lockCount() - 1);
        assertTrue(totalAmount > 0, "LP tokens not locked for owner");

    }

    // ============================================
    // ==   Whitelist and Merkle Root Tests      ==
    // ============================================

     function testMultipleWhitelistedUsers() public {
        (Presale presale, Presale.PresaleOptions memory opts) = createDefaultPresale(0, 0);

        // Setup whitelist
        address[] memory whitelistees = new address[](2);
        whitelistees[0] = user;
        whitelistees[1] = user2;
        _setupWhitelist(whitelistees);

        vm.prank(owner);
        presale.setMerkleRoot(root); // Set root before deposit

        // Deposit happens in createDefaultPresale after setting root conceptually

        // Test contributions
        vm.prank(user);
        presale.contribute{value: 1 ether}(proofs[user]); // User should succeed

        vm.prank(user2);
        presale.contribute{value: 1 ether}(proofs[user2]); // User2 should succeed

        // Test non-whitelisted
        vm.expectRevert(Presale.NotWhitelisted.selector);
        vm.prank(nonOwner);
        presale.contribute{value: 1 ether}(new bytes32[](0)); // nonOwner fails without proof

        vm.expectRevert(Presale.NotWhitelisted.selector);
        vm.prank(nonOwner);
        presale.contribute{value: 1 ether}(proofs[user]); // nonOwner fails with wrong proof
    }

    function testInvalidMerkleProof() public {
         (Presale presale, Presale.PresaleOptions memory opts) = createDefaultPresale(0, 0);

        // Setup whitelist
        address[] memory whitelistees = new address[](2);
        whitelistees[0] = user;
        whitelistees[1] = user2;
        _setupWhitelist(whitelistees);

        vm.prank(owner);
        presale.setMerkleRoot(root);

        // Try contributing as user2 with user1's proof
        vm.expectRevert(Presale.NotWhitelisted.selector);
        vm.prank(user2);
        presale.contribute{value: 1 ether}(proofs[user]);

        // Try contributing with an empty proof
         vm.expectRevert(Presale.NotWhitelisted.selector);
        vm.prank(user);
        presale.contribute{value: 1 ether}(new bytes32[](0));

        // Try contributing with a completely fabricated proof
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("invalid proof");
        vm.expectRevert(Presale.NotWhitelisted.selector);
        vm.prank(user);
        presale.contribute{value: 1 ether}(badProof);
    }

    // Note: Contract logic prevents updating Merkle root after state != Pending
    function testFailMerkleRootUpdateAfterDeposit() public {
        (Presale presale, ) = createDefaultPresale(0, 0); // Deposit happens inside

        // Setup a new whitelist
        address[] memory whitelistees = new address[](1);
        whitelistees[0] = nonOwner; // Different user
         _setupWhitelist(whitelistees);

        // Attempt to update root after deposit (state is Active)
        vm.expectRevert(abi.encodeWithSelector(Presale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        vm.prank(owner);
        presale.setMerkleRoot(root);
    }

     function testNonWhitelistedPresale() public {
        // Create presale WITHOUT setting a merkle root
         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether, softCap: 5 ether, min: 0.1 ether, max: 5 ether,
            presaleRate: 50_000, listingRate: 40_000, liquidityBps: 8000, slippageBps: 300,
            start: block.timestamp + 1 hours, end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION, vestingPercentage: 0, vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));
        // DO NOT set merkle root

        vm.prank(owner);
        token.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes);
        presale.deposit(); // State becomes Active
        vm.warp(opts.start + 1);

        // Anyone should be able to contribute without proof
        vm.prank(user);
        presale.contribute{value: 1 ether}(new bytes32[](0));

        vm.prank(nonOwner);
        presale.contribute{value: 1 ether}(new bytes32[](0));

        assertEq(presale.totalRaised(), 2 ether);
    }


    // ============================================
    // ==          Security Tests                ==
    // ============================================

    function testReentrancyContribute() public {
        (Presale presale, Presale.PresaleOptions memory opts) = createDefaultPresale(0, 0);

        MaliciousReentrantContributor attacker = new MaliciousReentrantContributor(address(presale));
        vm.deal(address(attacker), 1 ether);

        // Expect the reentrant call within the receive() fallback to fail
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attacker.attackContribute{value: 0.5 ether}();
    }

     function testReentrancyClaim() public {
        // Use the reverting token mock to simulate callback
        MockERC20Reverting revertingToken = new MockERC20Reverting("Reverting Token", "RVT", 18);
        revertingToken.mint(owner, 1_000_000 ether);

         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, hardCap: 10 ether, softCap: 5 ether, min: 0.1 ether, max: 5 ether,
            presaleRate: 50_000, listingRate: 40_000, liquidityBps: 8000, slippageBps: 300,
            start: block.timestamp + 1 hours, end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION, vestingPercentage: 0, vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(revertingToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Setup attacker contract
        MaliciousReentrantClaimer attacker = new MaliciousReentrantClaimer(address(presale), address(revertingToken));
        revertingToken.setReentrancyTarget(address(attacker)); // Tell token who to call back

        // Standard presale flow
        vm.prank(owner);
        revertingToken.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes);
        presale.deposit();
        vm.warp(opts.start + 1);

        vm.deal(address(attacker), 1 ether); // Give attacker ETH to contribute
        vm.prank(address(attacker));
        presale.contribute{value: 1 ether}(new bytes32[](0)); // Attacker contributes

        vm.warp(opts.end + 1);
        vm.prank(owner);
        presale.finalize();

        // Expect the reentrant call within the token transfer callback to fail
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(attacker));
        attacker.attackClaim();
    }


    function testUnauthorizedAccess() public {
        (Presale presale, Presale.PresaleOptions memory opts) = createDefaultPresale(0, 0);

        bytes32 randomRoot = keccak256("random");
        uint256 futureTime = block.timestamp + 100 days;

        vm.prank(nonOwner); // Switch to non-owner

        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.setMerkleRoot(randomRoot);

        // Deposit requires owner, test it just in case (though setup does it)
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.deposit(); // Assuming deposit wasn't done yet for this specific check

        // Need to progress time and state for other checks
        vm.warp(opts.end + 1);
        // Can't finalize as nonOwner to test withdraw/rescue yet.
        // Test finalize attempt
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.finalize();

        // Test cancel attempt
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.cancel();

        // Test pause/unpause
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.pause();
        // Need owner to pause first to test unpause
        vm.prank(owner);
        presale.pause();
        vm.prank(nonOwner);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.unpause();

        // Test other owner functions (assuming finalized state could be reached)
        // These would require owner to finalize first in a separate setup if needed
        // vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        // presale.withdraw();
        // vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        // presale.extendClaimDeadline(futureTime);
        // vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        // presale.rescueTokens(address(token), nonOwner, 1 ether);
    }

    function testTokenTransferFailureOnDeposit() public {
        MockERC20Reverting revertingToken = new MockERC20Reverting("Reverting Token", "RVT", 18);
        revertingToken.mint(owner, 1_000_000 ether);

         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, hardCap: 10 ether, softCap: 5 ether, min: 0.1 ether, max: 5 ether,
            presaleRate: 50_000, listingRate: 40_000, liquidityBps: 8000, slippageBps: 300,
            start: block.timestamp + 1 hours, end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION, vestingPercentage: 0, vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(revertingToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Configure token to revert on transferFrom
        revertingToken.setRevertTransferFrom(true);

        vm.prank(owner);
        revertingToken.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes);

        // Expect deposit to fail because transferFrom reverts
        vm.expectRevert("MockERC20Reverting: transferFrom reverted");
        presale.deposit();
    }

     function testTokenTransferFailureOnClaim() public {
        MockERC20Reverting revertingToken = new MockERC20Reverting("Reverting Token", "RVT", 18);
        revertingToken.mint(owner, 1_000_000 ether);

         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, hardCap: 10 ether, softCap: 5 ether, min: 0.1 ether, max: 5 ether,
            presaleRate: 50_000, listingRate: 40_000, liquidityBps: 8000, slippageBps: 300,
            start: block.timestamp + 1 hours, end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION, vestingPercentage: 0, // No vesting for simplicity
            vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(revertingToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Standard flow
        vm.prank(owner);
        revertingToken.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes);
        presale.deposit();
        vm.warp(opts.start + 1);

        vm.prank(user);
        presale.contribute{value: 1 ether}(new bytes32[](0));

        vm.warp(opts.end + 1);
        vm.prank(owner);
        presale.finalize();

        // Configure token to revert on transfer
        revertingToken.setRevertTransfer(true);

        // Expect claim to fail because transfer reverts
        vm.expectRevert("MockERC20Reverting: transfer reverted");
        vm.prank(user);
        presale.claim();
    }

     function testTokenTransferFailureOnLiquify() public {
        MockERC20Reverting revertingToken = new MockERC20Reverting("Reverting Token", "RVT", 18);
        revertingToken.mint(owner, 1_000_000 ether);

         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, hardCap: 10 ether, softCap: 5 ether, min: 0.1 ether, max: 5 ether,
            presaleRate: 50_000, listingRate: 40_000, liquidityBps: 8000, // Ensure liquidity is attempted
            slippageBps: 300,
            start: block.timestamp + 1 hours, end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION, vestingPercentage: 0,
            vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(revertingToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Standard flow
        vm.prank(owner);
        revertingToken.approve(address(presale), opts.tokenDeposit);
        vm.warp(opts.start - 30 minutes);
        presale.deposit();
        vm.warp(opts.start + 1);

        vm.prank(user);
        presale.contribute{value: opts.hardCap}(new bytes32[](0)); // Reach hardcap

        vm.warp(opts.end + 1);

        // Configure token to revert on transferFrom (used by router)
        revertingToken.setRevertTransferFrom(true);

        // Expect finalize to fail because addLiquidityETH -> transferFrom reverts
        // The exact revert might depend on the try/catch in Presale._addLiquidityETH
        // It could be LiquificationFailedReason or LiquificationFailed
        vm.expectRevert(Presale.LiquificationFailedReason.selector); // Or just expectRevert() if reason is complex/empty
        vm.prank(owner);
        presale.finalize();
    }

     function testTokenApproveFailureOnLiquify() public {
        MockERC20Reverting revertingToken = new MockERC20Reverting("Reverting Token", "RVT", 18);
        revertingToken.mint(owner, 1_000_000 ether);

         Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether, hardCap: 10 ether, softCap: 5 ether, min: 0.1 ether, max: 5 ether,
            presaleRate: 50_000, listingRate: 40_000, liquidityBps: 8000, // Ensure liquidity is attempted
            slippageBps: 300,
            start: block.timestamp + 1 hours, end: block.timestamp + 3 days,
            lockupDuration: DEFAULT_LOCKUP_DURATION, vestingPercentage: 0,
            vestingDuration: DEFAULT_VESTING_DURATION,
            leftoverTokenOption: 0, currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(revertingToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Standard flow
        vm.prank(owner);
        revertingToken.approve(address(presale), opts.tokenDeposit); // Initial approve works
        vm.warp(opts.start - 30 minutes);
        presale.deposit();
        vm.warp(opts.start + 1);

        vm.prank(user);
        presale.contribute{value: opts.hardCap}(new bytes32[](0)); // Reach hardcap

        vm.warp(opts.end + 1);

        // Configure token to revert on approve (needed before addLiquidity)
        revertingToken.setRevertApprove(true);

        // Expect finalize to fail because approve reverts
        vm.expectRevert("MockERC20Reverting: approve reverted");
        vm.prank(owner);
        presale.finalize();
    }


}
