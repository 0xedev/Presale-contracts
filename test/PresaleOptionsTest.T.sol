// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/contracts/PresaleFactory.sol";
import "../src/contracts/Presale.sol";

contract PresaleOptionsTest is Test {
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
        currency: address(0),
        vestingPercentage: 0, // Add missing fields
        vestingDuration: 0, // Add missing fields
        leftoverTokenOption: 0 // Add missing fields
    });
    address token = address(0x1);
    address weth = address(0x2);
    address router = address(0x3);

    function setUp() public {
        factory = new PresaleFactory(creationFee, address(0), address(router), address(weth), address(this));
    }

    receive() external payable {}

    function test_RevertIfStartAfterEnd() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.start = block.timestamp + 7 days;
        invalidOptions.end = block.timestamp + 1 days;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfStartInPast() public {
        vm.warp(block.timestamp + 2 days); // Set timestamp forward to avoid underflow
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.start = block.timestamp - 1 days;
        invalidOptions.end = block.timestamp - 1 hours; // Ensure end > start
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfSoftCapBelowHardCapQuarter() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.hardCap = 10 ether;
        invalidOptions.softCap = 1 ether; // < hardCap / 4 = 2.5 ether
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfMinExceedsMax() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.min = 2 ether;
        invalidOptions.max = 1 ether;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfZeroCaps() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.hardCap = 0;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfPresaleRateZero() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.presaleRate = 0;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfListingRateZero() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.listingRate = 0;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfLiquidityBpsExceeds10000() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.liquidityBps = 10001;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfSlippageBpsExceeds500() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.slippageBps = 501;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_LiquidityBpsBoundaryValues() public {
        Presale.PresaleOptions memory boundaryOptions = options;
        boundaryOptions.liquidityBps = 5100; // Minimum allowed
        address presale1 = factory.createPresale{value: creationFee}(boundaryOptions, token, weth, router);
        assertTrue(presale1 != address(0), "Presale creation failed with 5100 liquidityBps");

        boundaryOptions.liquidityBps = 10000; // Maximum allowed
        address presale2 = factory.createPresale{value: creationFee}(boundaryOptions, token, weth, router);
        assertTrue(presale2 != address(0), "Presale creation failed with 10000 liquidityBps");
    }
}
