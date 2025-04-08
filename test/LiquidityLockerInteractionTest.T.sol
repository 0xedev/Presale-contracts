// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/contracts/PresaleFactory.sol";
import "../src/contracts/Presale.sol";
import "../src/contracts/LiquidityLocker.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Presale Token", "PST") {
        _mint(msg.sender, 1000 ether);
    }
}

contract LiquidityLockerInteractionTest is Test {
    PresaleFactory factory;
    uint256 creationFee = 0.1 ether;

    Presale.PresaleOptions options = Presale.PresaleOptions({
        tokenDeposit: 1e18,
        hardCap: 10 ether,
        softCap: 5 ether,
        max: 1 ether,
        min: 0.1 ether,
        start: block.timestamp + 1 days,
        end: block.timestamp + 7 days,
        liquidityBps: 6000,
        slippageBps: 200,
        presaleRate: 1000,
        listingRate: 500,
        lockupDuration: 365 days,
        currency: address(0)
    });
    address weth = address(0x2);
    address router = address(0x3);

    function setUp() public {
        factory = new PresaleFactory(creationFee, address(0));
    }

    receive() external payable {}

    // Liquidity Locker Interaction Tests
    function test_LiquidityLockedAfterPresaleFinalization() public {
        MockToken presaleToken = new MockToken();
        Presale.PresaleOptions memory testOptions = options;
        testOptions.tokenDeposit = 100 ether;
        testOptions.currency = address(0);

        presaleToken.approve(address(factory), testOptions.tokenDeposit);
        address presaleAddr = factory.createPresale{value: creationFee}(testOptions, address(presaleToken), weth, router);
        Presale presale = Presale(payable(presaleAddr));

        vm.deal(address(this), 10 ether);
        presale.contribute{value: 5 ether}();

        vm.warp(testOptions.end + 1);
        presale.finalize();

        LiquidityLocker locker = factory.liquidityLocker();
        uint256 lockId = locker.lockCount() - 1;
        (address lockedToken, uint256 lockedAmount, uint256 unlockTime, address lockOwner) = locker.getLock(lockId);

        uint256 expectedLockedAmount = (5 ether * testOptions.listingRate / 1e18) * testOptions.liquidityBps / 10000;
        assertEq(lockedToken, address(presaleToken), "Incorrect token locked");
        assertEq(lockedAmount, expectedLockedAmount, "Incorrect amount locked in LiquidityLocker");
        assertEq(unlockTime, testOptions.end + testOptions.lockupDuration, "Incorrect unlock time");
        assertEq(lockOwner, address(this), "Incorrect lock owner");
    }

    function test_LiquidityUnlockAfterDuration() public {
        MockToken presaleToken = new MockToken();
        Presale.PresaleOptions memory testOptions = options;
        testOptions.tokenDeposit = 100 ether;
        testOptions.currency = address(0);

        presaleToken.approve(address(factory), testOptions.tokenDeposit);
        address presaleAddr = factory.createPresale{value: creationFee}(testOptions, address(presaleToken), weth, router);
        Presale presale = Presale(payable(presaleAddr));

        vm.deal(address(this), 10 ether);
        presale.contribute{value: 5 ether}();

        vm.warp(testOptions.end + 1);
        presale.finalize();

        LiquidityLocker locker = factory.liquidityLocker();
        uint256 lockId = locker.lockCount() - 1;
        (, uint256 lockedAmount, , ) = locker.getLock(lockId);

        vm.warp(testOptions.end + testOptions.lockupDuration + 1);
        locker.withdraw(lockId);

        assertEq(presaleToken.balanceOf(address(locker)), 0, "Tokens not unlocked from LiquidityLocker");
        assertEq(presaleToken.balanceOf(address(this)), 1000 ether, "Tokens not returned to owner");
    }
}