// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/contracts/Presale.sol";
import "src/contracts/PresaleFactory.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockRouter2.sol"; // Assuming this is your intended router mock
import "./mocks/MockFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol"; // For selector
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // For selector
import "src/contracts/Vesting.sol";
import "src/contracts/LiquidityLocker.sol";
import "src/contracts/interfaces/IPresale.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// --- MaliciousReceiver and RevertingToken Contracts (Keep as is from your file) ---
contract MaliciousReceiver {
    Presale public presale;
    bool public attack;
    uint256 public callCount = 0; // Add counter for claim re-entrancy

    constructor(address _presale) {
        presale = Presale(payable(_presale));
    }

    function contribute() external payable {
        attack = true; // Enable attack flag
        presale.contribute{value: msg.value}(new bytes32[](0));
    }

    function claim() external {
        attack = true; // Enable attack flag
        callCount = 0; // Reset counter for claim attack
        presale.claim();
    }

    // receive() fallback for contribute re-entrancy test
    receive() external payable {
        if (attack) {
            // Only attempt re-entry once from receive()
            attack = false; // Prevent infinite loop if ETH keeps coming back
            // Attempt to re-enter contribute
            try presale.contribute{value: 0.01 ether}(new bytes32[](0)) {} catch {}
        }
    }

    // Separate function for claim re-entrancy simulation (called by malicious token)
    function onClaimReentryAttempt() external {
        if (attack && callCount < 1) {
            // Only re-enter once per claim attempt
            callCount++;
            // Attempt to re-enter claim
            presale.claim();
        }
    }
}

contract RevertingToken is MockERC20 {
    bool public shouldRevertTransfer;
    bool public shouldRevertTransferFrom;
    bool public shouldRevertApprove; // Add approve revert flag

    // For claim re-entrancy test
    MaliciousReceiver public maliciousClaimer;

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

    function setMaliciousClaimer(address _claimer) external {
        maliciousClaimer = MaliciousReceiver(payable(_claimer));
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldRevertTransfer) revert("RevertingToken: transfer reverted");
        // Simulate callback for claim re-entrancy
        if (address(maliciousClaimer) != address(0) && to == address(maliciousClaimer)) {
            try maliciousClaimer.onClaimReentryAttempt() {} catch {}
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldRevertTransferFrom) revert("RevertingToken: transferFrom reverted");
        return super.transferFrom(from, to, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (shouldRevertApprove) revert("RevertingToken: approve reverted");
        return super.approve(spender, amount);
    }
}
// --- End Malicious/Reverting Contracts ---

contract PresaleAdditionalTests is Test {
    PresaleFactory factory;
    MockERC20 token;
    MockRouter router; // Use MockRouter2 if that's the correct one
    MockFactory mockFactory;
    Vesting vesting;
    LiquidityLocker locker;
    address weth = address(0xbEEF); // Use a mock or real WETH
    address user = address(0x1234);
    address user2 = address(0x5678);
    address nonOwner = address(0xABCD); // Add nonOwner for tests
    address owner;

    function setUp() public {
        owner = address(this); // Test contract is owner
        vm.label(owner, "Owner/TestContract");
        vm.label(user, "User");
        vm.label(user2, "User2");
        vm.label(nonOwner, "NonOwner");

        token = new MockERC20("Test Token", "TT", 18);
        mockFactory = new MockFactory();
        // Ensure MockRouter constructor matches your mock
        // If your MockRouter takes factory and weth:
        // router = new MockRouter(address(mockFactory), weth);
        // If it only takes factory:
        router = new MockRouter(address(mockFactory));
        // If it takes no arguments and needs setFactory():
        // router = new MockRouter();
        // router.setFactory(address(mockFactory));

        // Deploy Factory as owner
        vm.prank(owner);
        // Adjust constructor args based on your actual PresaleFactory:
        // constructor(uint256 _creationFee, address _feeToken, uint256 _housePercentage, address _houseAddress)
        factory = new PresaleFactory(0, address(0), 100, address(0x9999)); // Example: No creation fee, 1% house fee

        // Get deployed contracts (factory is admin by default)
        vesting = Vesting(factory.vestingContract());
        locker = LiquidityLocker(factory.liquidityLocker());

        // --- ROLE GRANTING REMOVED ---
        // The PresaleFactory handles granting VESTER_ROLE and LOCKER_ROLE
        // to the Presale instances it creates. The 'owner' (this test contract)
        // does not need admin rights on the global vesting/locker contracts.

        // Mint tokens for the owner (test contract)
        token.mint(address(this), 1_000_000 ether);

        // Deal ETH to test users
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(nonOwner, 10 ether);
    }

    // Helper creates presale, approves token, but DOES NOT deposit
    function _createPresale(
        uint256 leftoverOption,
        uint256 liquidityBps,
        uint256 tokenDeposit,
        uint256 vestingPercentage,
        uint256 vestingDuration
    ) internal returns (Presale) {
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: tokenDeposit,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 1000, // 1 ETH = 1000 TT
            listingRate: 800, // 1 ETH = 800 TT
            liquidityBps: liquidityBps,
            slippageBps: 300,
            start: block.timestamp + 1 hours, // Start in 1 hour
            end: block.timestamp + 1 days + 1 hours, // End 1 day later
            lockupDuration: 30 days,
            vestingPercentage: vestingPercentage,
            vestingDuration: vestingDuration,
            leftoverTokenOption: leftoverOption,
            currency: address(0), // ETH presale
            whitelistType: Presale.WhitelistType.None,
            merkleRoot: bytes32(0),
            nftContractAddress: address(0)

        });

        // Owner creates the presale via the factory
        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        // Owner approves the presale contract to pull deposit tokens
        vm.prank(owner);
        token.approve(address(presale), opts.tokenDeposit);

        return presale;
    }

    // --- Helper for Merkle Proofs ---
    bytes32 root;
    mapping(address => bytes32[]) proofs;

    function _setupWhitelist(address[] memory _whitelistees) internal {
        require(_whitelistees.length > 0, "Need at least one user");
        bytes32[] memory leaves = new bytes32[](_whitelistees.length);
        for (uint256 i = 0; i < _whitelistees.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(_whitelistees[i]));
        }

        // --- Basic Merkle Tree Construction (Example for 2 leaves) ---
        if (_whitelistees.length == 2) {
            bytes32 leaf1Hash = leaves[0]; // Already hashed leaf
            bytes32 leaf2Hash = leaves[1];
            // Ensure consistent ordering for hashing pairs
            if (uint256(leaf1Hash) < uint256(leaf2Hash)) {
                root = keccak256(abi.encodePacked(leaf1Hash, leaf2Hash));
            } else {
                root = keccak256(abi.encodePacked(leaf2Hash, leaf1Hash));
            }
            // Generate proofs
            proofs[_whitelistees[0]] = new bytes32[](1);
            proofs[_whitelistees[0]][0] = leaf2Hash;
            proofs[_whitelistees[1]] = new bytes32[](1);
            proofs[_whitelistees[1]][0] = leaf1Hash;
        } else if (_whitelistees.length == 1) {
            root = leaves[0]; // Root is just the leaf hash
            proofs[_whitelistees[0]] = new bytes32[](0); // No proof needed for single leaf
        } else {
            // --- Add logic for more leaves or revert ---
            // This requires a proper recursive tree builder
            revert("Merkle tree builder for >2 leaves not implemented in helper");
        }
        // --- End Basic Construction ---
    }

    // ============================================
    // ==      Leftover Token Handling Tests     ==
    // ============================================

    function testLeftoverTokenOptionBurn() public {
        uint256 depositAmount = 500_000 ether;
        Presale presale = _createPresale(1, 8000, depositAmount, 0, 0);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(block.timestamp + 1 days + 1 hours + 1);

        uint256 tokensSold = (5 ether * 1000);
        uint256 currencyForLiquidity = (5 ether * 8000) / 10000;
        uint256 tokensForLiquidity = (currencyForLiquidity * 800);
        uint256 expectedLeftovers = depositAmount - tokensSold - tokensForLiquidity;

        uint256 balanceBeforeBurn = token.balanceOf(address(0));
        vm.expectEmit(true, false, false, true, address(presale));
        emit IPresale.LeftoverTokensBurned(expectedLeftovers);

        vm.prank(owner);
        presale.finalize();

        assertEq(
            token.balanceOf(address(0)), balanceBeforeBurn + expectedLeftovers, "Leftover tokens not sent to address(0)"
        );
        assertEq(token.balanceOf(address(presale)), 0, "Presale contract should have 0 tokens");
    }

    function testLeftoverTokenOptionVest() public {
        uint256 depositAmount = 600_000 ether;
        uint256 vestingDuration = 30 days;
        Presale presale = _createPresale(2, 8000, depositAmount, 0, vestingDuration);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(block.timestamp + 1 days + 1 hours);

        uint256 tokensSold = (5 ether * 1000);
        uint256 currencyForLiquidity = (5 ether * 8000) / 10000;
        uint256 tokensForLiquidity = (currencyForLiquidity * 800);
        uint256 expectedLeftovers = depositAmount - tokensSold - tokensForLiquidity;

        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.LeftoverTokensVested(expectedLeftovers, owner);

        uint256 vestingBalanceBefore = token.balanceOf(address(vesting));
        vm.prank(owner);
        presale.finalize();

        assertEq(
            vesting.remainingVested(address(presale), owner), expectedLeftovers, "Leftover tokens not vested for owner"
        );
        assertEq(
            vesting.vestedAmount(address(presale), owner), 0, "Vested amount should be 0 immediately after finalize"
        );
        assertEq(
            token.balanceOf(address(vesting)),
            vestingBalanceBefore + expectedLeftovers,
            "Vesting contract balance incorrect"
        );
        assertEq(token.balanceOf(address(presale)), 0, "Presale contract should have 0 tokens");
    }

    function testNoLeftoverTokens() public {
        uint256 hardCap = 10 ether;
        uint256 presaleRate = 1000;
        uint256 listingRate = 800;
        uint256 liquidityBps = 10000;

        uint256 tokensForSale = hardCap * presaleRate;
        uint256 currencyForLiq = (hardCap * liquidityBps) / 10000;
        uint256 tokensForLiq = currencyForLiq * listingRate;
        uint256 tokenDeposit = tokensForSale + tokensForLiq;

        Presale presale = _createPresale(0, liquidityBps, tokenDeposit, 0, 0);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.prank(user2);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        assertEq(presale.totalRaised(), hardCap);

        vm.warp(block.timestamp + 1 days + 1 hours + 1);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        vm.prank(owner);
        presale.finalize();

        vm.prank(user);
        presale.claim();
        vm.prank(user2);
        presale.claim();

        assertEq(token.balanceOf(address(presale)), 0, "Contract should have no leftover tokens");
        assertEq(token.balanceOf(owner), ownerBalanceBefore, "No tokens should be returned to owner");
        assertEq(vesting.remainingVested(address(presale), owner), 0, "No tokens should be vested for owner");
        assertEq(token.balanceOf(user), 5 ether * presaleRate, "User token balance incorrect");
        assertEq(token.balanceOf(user2), 5 ether * presaleRate, "User2 token balance incorrect");
    }

    // ============================================
    // ==   Whitelist and Merkle Root Tests      ==
    // ============================================

    function testMultipleWhitelistedUsers() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        address[] memory whitelistees = new address[](2);
        whitelistees[0] = user;
        whitelistees[1] = user2;
        _setupWhitelist(whitelistees);

        vm.prank(owner);
        presale.setMerkleRoot(root);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 2 ether}(proofs[user]);
        vm.prank(user2);
        presale.contribute{value: 3 ether}(proofs[user2]);

        assertEq(presale.contributions(user), 2 ether, "User1 contribution incorrect");
        assertEq(presale.contributions(user2), 3 ether, "User2 contribution incorrect");

        vm.prank(nonOwner);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: 1 ether}(new bytes32[](0));
    }

    function testInvalidMerkleProof() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        address[] memory whitelistees = new address[](1);
        whitelistees[0] = user2;
        _setupWhitelist(whitelistees);

        vm.prank(owner);
        presale.setMerkleRoot(root);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("garbage"));
        vm.prank(user);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: 2 ether}(invalidProof);
    }

    // Test updating Merkle root *before* deposit (should succeed)
    function testMerkleRootUpdate() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        address[] memory oldWhitelist = new address[](1);
        oldWhitelist[0] = user;
        _setupWhitelist(oldWhitelist);
        bytes32 oldRoot = root;
        bytes32[] memory userProof = proofs[user];

        address[] memory newWhitelist = new address[](1);
        newWhitelist[0] = user2;
        _setupWhitelist(newWhitelist);
        bytes32 newRoot = root;
        bytes32[] memory user2Proof = proofs[user2];

        vm.prank(owner);
        presale.setMerkleRoot(oldRoot);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 2 ether}(userProof);

        vm.prank(owner);
        presale.cancel();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Canceled)));
        presale.setMerkleRoot(newRoot);

        vm.prank(user);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: 1 ether}(userProof);

        vm.prank(user2);
        presale.contribute{value: 1 ether}(user2Proof);

        assertEq(presale.contributions(user2), 1 ether, "Contribution after root update incorrect");
    }

    // Test attempting to update Merkle root *after* deposit (should fail)
    function test_RevertWhen_SetMerkleRootAfterDeposit() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        // Owner deposits tokens
        vm.prank(owner);
        presale.deposit(); // State becomes Active

        // Setup a new whitelist
        address[] memory whitelistees = new address[](1);
        whitelistees[0] = nonOwner;
        _setupWhitelist(whitelistees);

        // Attempt to update root (state is Active)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.setMerkleRoot(root);
    }

    function testNonWhitelistedPresale() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        vm.prank(owner);
        presale.setMerkleRoot(bytes32(0));
        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 2 ether}(new bytes32[](0));
        assertEq(presale.contributions(user), 2 ether, "Contribution without whitelist incorrect");
    }

    // ============================================
    // ==          Security Tests                ==
    // ============================================

    function testReentrancyInClaim() public {
        RevertingToken badToken = new RevertingToken("Reverting Token", "RVT", 18);
        badToken.mint(owner, 1_000_000 ether);

        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000,
            slippageBps: 300,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 1 days + 1 hours,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0),
            whitelistType: Presale.WhitelistType.None,
            merkleRoot: bytes32(0),
            nftContractAddress: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(badToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        MaliciousReceiver attacker = new MaliciousReceiver(address(presale));
        badToken.setMaliciousClaimer(address(attacker));

        vm.prank(owner);
        badToken.approve(address(presale), opts.tokenDeposit);
        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.deal(address(attacker), 10 ether);
        vm.prank(address(attacker));
        presale.contribute{value: 5 ether}(new bytes32[](0));

        vm.warp(block.timestamp + 1 days + 1 hours + 1);
        vm.prank(owner);
        presale.finalize();

        vm.prank(address(attacker));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attacker.claim();

        assertEq(presale.contributions(address(attacker)), 5 ether, "Contribution should remain after failed claim");
        assertEq(badToken.balanceOf(address(attacker)), 0, "Attacker should have 0 tokens after failed claim");
    }

    function testUnauthorizedAccess() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        presale.deposit();

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        presale.setMerkleRoot(bytes32(uint256(1)));

        vm.warp(block.timestamp + 1 days + 1 hours);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        presale.finalize();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        presale.cancel();
    }

    // Test transferFrom failure on deposit
    // function testTokenTransferFailureOnDeposit() public {
    //     RevertingToken badToken = new RevertingToken("Bad Token", "BT", 18);
    //     badToken.mint(address(this), 1_000_000 ether);

    //     // Create presale with badToken address
    //     Presale.PresaleOptions memory opts = Presale.PresaleOptions({
    //         tokenDeposit: 600_000 ether,
    //         hardCap: 10 ether,
    //         softCap: 5 ether,
    //         min: 0.1 ether,
    //         max: 5 ether,
    //         presaleRate: 1000,
    //         listingRate: 800,
    //         liquidityBps: 8000,
    //         slippageBps: 300,
    //         start: block.timestamp + 1 hours,
    //         end: block.timestamp + 1 days + 1 hours,
    //         lockupDuration: 30 days,
    //         vestingPercentage: 0,
    //         vestingDuration: 0,
    //         leftoverTokenOption: 0,
    //         currency: address(0)
    //     });

    //     vm.prank(owner);
    //     address presaleAddr = factory.createPresale(opts, address(badToken), weth, address(router));
    //     Presale presale = Presale(payable(presaleAddr)); // Reassign presale variable

    //     vm.prank(owner);
    //     badToken.approve(address(presale), opts.tokenDeposit);
    //     vm.warp(opts.start - 10); // Before start

    //     // Configure token to revert on transferFrom
    //     badToken.setRevertTransferFrom(true);

    //     // Expect deposit to fail because transferFrom reverts
    //     vm.expectRevert("RevertingToken: transferFrom reverted");
    //     vm.prank(owner);
    //     presale.deposit();
    // }

    // // Test transfer failure on claim
    // function testTokenTransferFailureOnClaim() public {
    //     RevertingToken badToken = new RevertingToken("Bad Token", "BT", 18);
    //     badToken.mint(address(this), 1_000_000 ether);

    //     // Create presale with badToken address
    //     Presale.PresaleOptions memory opts = Presale.PresaleOptions({
    //         tokenDeposit: 600_000 ether,
    //         hardCap: 10 ether,
    //         softCap: 5 ether,
    //         min: 0.1 ether,
    //         max: 5 ether,
    //         presaleRate: 1000,
    //         listingRate: 800,
    //         liquidityBps: 8000,
    //         slippageBps: 300,
    //         start: block.timestamp + 1 hours,
    //         end: block.timestamp + 1 days + 1 hours,
    //         lockupDuration: 30 days,
    //         vestingPercentage: 0,
    //         vestingDuration: 0, // No vesting
    //         leftoverTokenOption: 0,
    //         currency: address(0)
    //     });
    //     vm.prank(owner);
    //     address presaleAddr = factory.createPresale(opts, address(badToken), weth, address(router));
    //     Presale presale = Presale(payable(presaleAddr)); // Reassign presale variable

    //     // Standard flow
    //     vm.prank(owner);
    //     badToken.approve(address(presale), opts.tokenDeposit);
    //     vm.prank(owner);
    //     presale.deposit();
    //     vm.warp(opts.start + 1); // Warp to active state

    //     vm.prank(user);
    //     presale.contribute{value: 3 ether}(new bytes32[](0));
    //     vm.prank(user2);
    //     presale.contribute{value: 3 ether}(new bytes32[](0));
    //     vm.warp(opts.end + 1);
    //     vm.prank(owner);
    //     presale.finalize();

    //     // Configure token to revert on transfer
    //     badToken.setRevertTransfer(true);

    //     // Expect claim to fail because transfer reverts
    //     vm.expectRevert("RevertingToken: transfer reverted");
    //     vm.prank(user);
    //     presale.claim();
    // }

    // Test transferFrom failure during liquify
    function testTokenTransferFailureOnLiquify() public {
        RevertingToken badToken = new RevertingToken("Bad Token", "BT", 18);
        badToken.mint(address(this), 1_000_000 ether);

        // Create presale with badToken address
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000, // Ensure liquidity is attempted
            slippageBps: 300,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 1 days + 1 hours,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0),
            whitelistType: Presale.WhitelistType.None,
            merkleRoot: bytes32(0),
            nftContractAddress: address(0)
        });
        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(badToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr)); // Reassign presale variable

        // Standard flow
        vm.prank(owner);
        badToken.approve(address(presale), opts.tokenDeposit);
        vm.prank(owner);
        presale.deposit();
        vm.warp(opts.start + 1); // Warp to active state

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0)); // Reach hardcap

        vm.prank(user2);
        presale.contribute{value: 5 ether}(new bytes32[](0)); // Reach hardcap

        vm.warp(opts.end + 1);

        // Configure token to revert on transferFrom (used by router.addLiquidityETH)
        badToken.setRevertTransferFrom(true);

        // Expect finalize to fail inside _addLiquidityETH -> router call
        // The exact revert depends on the try/catch in Presale._addLiquidityETH
        vm.expectRevert(
            abi.encodeWithSelector(IPresale.LiquificationFailedReason.selector, "RevertingToken: transferFrom reverted")
        );
        vm.prank(owner);
        presale.finalize();
    }

    // Test approve failure during liquify
    function testTokenApproveFailureOnLiquify() public {
        RevertingToken badToken = new RevertingToken("Bad Token", "BT", 18);
        badToken.mint(address(this), 1_000_000 ether);

        // Create presale with badToken address
        Presale.PresaleOptions memory opts = Presale.PresaleOptions({
            tokenDeposit: 600_000 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 8000, // Ensure liquidity is attempted
            slippageBps: 300,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 1 days + 1 hours,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0),
            whitelistType: Presale.WhitelistType.None,
            merkleRoot: bytes32(0),
            nftContractAddress: address(0)
        });
        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(badToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr)); // Reassign presale variable

        // Standard flow
        vm.prank(owner);
        badToken.approve(address(presale), opts.tokenDeposit); // Initial approve works
        vm.prank(owner);
        presale.deposit();
        vm.warp(opts.start + 1); // Warp to active state

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0)); // Reach hardcap
        vm.prank(user2);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(opts.end + 1);

        // Configure token to revert on approve (needed before router.addLiquidityETH)
        badToken.setRevertApprove(true);

        // Expect finalize to fail because approve reverts inside _liquify
        vm.expectRevert("RevertingToken: approve reverted");
        vm.prank(owner);
        presale.finalize();
    }
}
