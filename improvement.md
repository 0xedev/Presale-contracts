#### Gas and Optimization Tests

1. ❌ **Test High Contribution Count**: Simulate 100 users contributing small amounts to stress `_distributeTokens` and gas usage.
2. ❌ **Test Large Token Deposit**: Set `tokenDeposit` to a very high value (e.g., 10^30) and verify no overflow in calculations.
3. ❌ **Test Struct Gas Efficiency**: Compare gas usage of `_liquify`, `_addLiquidityETH`, `_handleLeftoverTokens`, `_distributeTokens` with and without structs.

#### Failure and Revert Tests

1. ❌ **Test Insufficient Token Deposit**: Deposit less than required tokens (based on `presaleRate` and `hardCap`) and verify `deposit` reverts.
2. ❌ **Test Router Failure**: Mock `MockRouter` to revert in `addLiquidityETH` and verify `_liquify` handles failure gracefully.
3. ❌ **Test SoftCap Not Met Finalize**: Attempt `finalize` with contributions below `softCap` (should revert with `SoftCapNotReached`).
4. ❌ **Test Claim Without Contribution**: Call `claim` from a user with 0 contributions (should revert or return 0 tokens).

#### Edge Case Parameter Tests

1. ❌ **Test Zero Duration Presale**: Set `start=end` and verify contributions and finalization work.
2. ❌ **Test Zero Lockup Duration**: Set `lockupDuration=0` and verify LP tokens are immediately withdrawable.
3. ❌ **Test Invalid Presale Options**: Pass invalid `PresaleOptions` (e.g., `hardCap < softCap`, `presaleRate=0`) and verify constructor reverts.
4. ❌ **Test Max Token Decimals**: Use a token with 0 or 36 decimals and verify calculations in `_distributeTokens` are correct.

```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/contracts/Presale.sol";
import "src/contracts/PresaleFactory.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockRouter2.sol";
import "./mocks/MockFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "src/contracts/Vesting.sol";
import "src/contracts/LiquidityLocker.sol";
import "src/contracts/interfaces/IPresale.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MaliciousReceiver {
    Presale public presale;
    bool public attack;
    uint256 public callCount = 0;

    constructor(address _presale) {
        presale = Presale(payable(_presale));
    }

    function contribute() external payable {
        attack = true;
        presale.contribute{value: msg.value}(new bytes32[](0));
    }

    function claim() external {
        attack = true;
        callCount = 0;
        presale.claim(new bytes32[](0));
    }

    receive() external payable {
        if (attack) {
            attack = false;
            try presale.contribute{value: 0.01 ether}(new bytes32[](0)) {} catch {}
        }
    }

    function onClaimReentryAttempt() external {
        if (attack && callCount < 1) {
            callCount++;
            try presale.claim(new bytes32[](0)) {} catch {}
        }
    }
}

contract RevertingToken is MockERC20 {
    bool public shouldRevertTransfer;
    bool public shouldRevertTransferFrom;
    bool public shouldRevertApprove;
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

contract PresaleAdditionalTests is Test {
    PresaleFactory factory;
    MockERC20 token;
    MockRouter router;
    MockFactory mockFactory;
    Vesting vesting;
    LiquidityLocker locker;
    address weth = address(0xbEEF);
    address user = address(0x1234);
    address user2 = address(0x5678);
    address nonOwner = address(0xABCD);
    address owner;

    function setUp() public {
        owner = address(this);
        vm.label(owner, "Owner/TestContract");
        vm.label(user, "User");
        vm.label(user2, "User2");
        vm.label(nonOwner, "NonOwner");

        token = new MockERC20("Test Token", "TT", 18);
        mockFactory = new MockFactory();
        router = new MockRouter(address(mockFactory));
        factory = new PresaleFactory(0, address(0), 100, address(0x9999));

        vesting = Vesting(factory.vestingContract());
        locker = LiquidityLocker(factory.liquidityLocker());

        // Grant DEFAULT_ADMIN_ROLE to test contract using factory's admin privileges
        vm.prank(address(factory));
        locker.grantRole(locker.DEFAULT_ADMIN_ROLE(), owner);
        vm.prank(address(factory));
        vesting.grantRole(vesting.DEFAULT_ADMIN_ROLE(), owner);

        // Now test contract can grant other roles
        vesting.grantRole(vesting.VESTER_ROLE(), address(factory));
        locker.grantRole(locker.LOCKER_ROLE(), address(factory));

        token.mint(address(this), 1_000_000 ether);
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(nonOwner, 10 ether);
    }

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
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: liquidityBps,
            slippageBps: 300,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 1 days + 1 hours,
            lockupDuration: 30 days,
            vestingPercentage: vestingPercentage,
            vestingDuration: vestingDuration,
            leftoverTokenOption: leftoverOption,
            currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(token), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));
        vm.prank(owner);
        token.approve(address(presale), opts.tokenDeposit);
        return presale;
    }

    bytes32 root;
    mapping(address => bytes32[]) proofs;

    function _setupWhitelist(address[] memory _whitelistees) internal {
        bytes32[] memory leaves = new bytes32[](_whitelistees.length);
        for (uint i = 0; i < _whitelistees.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(_whitelistees[i]));
        }
        // Sort leaves to ensure consistent Merkle tree
        for (uint i = 0; i < leaves.length; i++) {
            for (uint j = i + 1; j < leaves.length; j++) {
                if (leaves[i] > leaves[j]) {
                    bytes32 temp = leaves[i];
                    leaves[i] = leaves[j];
                    leaves[j] = temp;
                }
            }
        }
        // Build Merkle tree
        while (leaves.length > 1) {
            bytes32[] memory newLeaves = new bytes32[]((leaves.length + 1) / 2);
            for (uint i = 0; i < leaves.length; i += 2) {
                if (i + 1 < leaves.length) {
                    newLeaves[i / 2] = keccak256(abi.encodePacked(leaves[i], leaves[i + 1]));
                } else {
                    newLeaves[i / 2] = leaves[i];
                }
            }
            leaves = newLeaves;
        }
        root = leaves[0];

        // Generate proofs for each whitelisted address
        for (uint i = 0; i < _whitelistees.length; i++) {
            bytes32 leaf = keccak256(abi.encodePacked(_whitelistees[i]));
            bytes32[] memory proof = new bytes32[](0); // Simplified for single-level tree
            proofs[_whitelistees[i]] = proof;
        }
    }

    function testLeftoverTokenOptionBurn() public {
        uint256 depositAmount = 600_000 ether;
        Presale presale = _createPresale(1, 8000, depositAmount, 0, 0);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user);
        presale.contribute{value: 6 ether}(new bytes32[](0));
        vm.warp(block.timestamp + 1 days + 1 hours);

        uint256 tokensSold = (6 ether * 1000);
        uint256 currencyForLiquidity = (6 ether * 8000) / 10000;
        uint256 tokensForLiquidity = (currencyForLiquidity * 800);
        uint256 expectedLeftovers = depositAmount - tokensSold - tokensForLiquidity;

        uint256 balanceBeforeBurn = token.balanceOf(address(0));
        vm.expectEmit(true, false, false, true, address(presale));
        emit IPresale.LeftoverTokensBurned(expectedLeftovers);

        vm.prank(owner);
        presale.finalize();

        assertEq(token.balanceOf(address(0)), balanceBeforeBurn + expectedLeftovers, "Leftover tokens not sent to address(0)");
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
        presale.contribute{value: 6 ether}(new bytes32[](0));
        vm.warp(block.timestamp + 1 days + 1 hours);

        uint256 tokensSold = (6 ether * 1000);
        uint256 currencyForLiquidity = (6 ether * 8000) / 10000;
        uint256 tokensForLiquidity = (currencyForLiquidity * 800);
        uint256 expectedLeftovers = depositAmount - tokensSold - tokensForLiquidity;

        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.LeftoverTokensVested(expectedLeftovers, owner);

        uint256 vestingBalanceBefore = token.balanceOf(address(vesting));
        vm.prank(owner);
        presale.finalize();

        assertEq(vesting.remainingVested(address(presale), owner), expectedLeftovers, "Leftover tokens not vested for owner");
        assertEq(vesting.vestedAmount(address(presale), owner), 0, "Vested amount should be 0 immediately after finalize");
        assertEq(token.balanceOf(address(vesting)), vestingBalanceBefore + expectedLeftovers, "Vesting contract balance incorrect");
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

        vm.warp(block.timestamp + 1 days + 1 hours);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        vm.prank(owner);
        presale.finalize();

        vm.prank(user);
        presale.claim(new bytes32[](0));
        vm.prank(user2);
        presale.claim(new bytes32[](0));

        assertEq(token.balanceOf(address(presale)), 0, "Contract should have no leftover tokens");
        assertEq(token.balanceOf(owner), ownerBalanceBefore, "No tokens should be returned to owner");
        assertEq(vesting.remainingVested(address(presale), owner), 0, "No tokens should be vested for owner");
        assertEq(token.balanceOf(user), 5 ether * presaleRate, "User token balance incorrect");
        assertEq(token.balanceOf(user2), 5 ether * presaleRate, "User2 token balance incorrect");
    }

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
        presale.setMerkleRoot(newRoot);

        vm.prank(user);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: 1 ether}(userProof);

        vm.prank(user2);
        presale.contribute{value: 1 ether}(user2Proof);

        assertEq(presale.contributions(user2), 1 ether, "Contribution after root update incorrect");
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

    function testReentrancyInContribute() public {
        Presale presale = _createPresale(0, 8000, 600_000 ether, 0, 0);

        vm.prank(owner);
        presale.deposit();
        vm.warp(block.timestamp + 2 hours);

        MaliciousReceiver attacker = new MaliciousReceiver(address(presale));
        vm.deal(address(attacker), 10 ether);

        vm.prank(address(attacker));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        attacker.contribute{value: 2 ether}();

        assertEq(presale.contributions(address(attacker)), 0, "Reentrant contribution should not be recorded");
    }

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
            currency: address(0)
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

        vm.warp(block.timestamp + 1 days + 1 hours);
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

    function testTokenTransferFailure() public {
        RevertingToken badToken = new RevertingToken("Bad Token", "BT", 18);
        badToken.mint(address(this), 1_000_000 ether);

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
            currency: address(0)
        });

        vm.prank(owner);
        address presaleAddr = factory.createPresale(opts, address(badToken), weth, address(router));
        Presale presale = Presale(payable(presaleAddr));

        vm.prank(owner);
        badToken.approve(address(presale), opts.tokenDeposit);
        vm.warp(block.timestamp + 2 hours);

        badToken.setRevertTransferFrom(true);
        vm.expectRevert("RevertingToken: transferFrom reverted");
        vm.prank(owner);
        presale.deposit();

        badToken.setRevertTransferFrom(false);
        vm.prank(owner);
        presale.deposit();

        vm.prank(user);
        presale.contribute{value: 5 ether}(new bytes32[](0));
        vm.warp(block.timestamp + 1 days + 1 hours);

        badToken.setRevertTransfer(true);
        vm.expectRevert("RevertingToken: transfer reverted");
        vm.prank(user);
        presale.claim(new bytes32[](0));

        badToken.setRevertTransfer(false);
        vm.prank(owner);
        presale.finalize();

        badToken.setRevertApprove(true);
        vm.expectRevert("RevertingToken: approve reverted");
        vm.prank(owner);
        presale.finalize();
    }
}
```
