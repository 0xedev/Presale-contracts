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
        currency: address(0)
    });
    address token = address(0x1);
    address weth = address(0x2);
    address router = address(0x3);

    function setUp() public {
        factory = new PresaleFactory(creationFee, address(0));
    }

    receive() external payable {}

    // Presale Options Validation Tests
    function test_RevertIfStartAfterEnd() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.start = block.timestamp + 7 days;
        invalidOptions.end = block.timestamp + 1 days;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfStartInPast() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.start = block.timestamp - 1 days;
        invalidOptions.end = block.timestamp + 7 days;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfSoftCapExceedsHardCap() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.softCap = 15 ether;
        invalidOptions.hardCap = 10 ether;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfMinExceedsMax() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.min = 2 ether;
        invalidOptions.max = 1 ether;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfZeroCaps() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.hardCap = 0;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfPresaleRateZero() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.presaleRate = 0;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfListingRateZero() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.listingRate = 0;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfLiquidityBpsExceeds10000() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.liquidityBps = 10001;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_RevertIfSlippageBpsExceeds10000() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.slippageBps = 10001;
        vm.expectRevert();
        factory.createPresale{value: creationFee}(invalidOptions, token, weth, router);
    }

    function test_LiquidityBpsBoundaryValues() public {
        Presale.PresaleOptions memory boundaryOptions = options;
        boundaryOptions.liquidityBps = 0;
        address presale1 = factory.createPresale{value: creationFee}(boundaryOptions, token, weth, router);
        assertTrue(presale1 != address(0), "Presale creation failed with 0 liquidityBps");

        boundaryOptions.liquidityBps = 10000;
        address presale2 = factory.createPresale{value: creationFee}(boundaryOptions, token, weth, router);
        assertTrue(presale2 != address(0), "Presale creation failed with 10000 liquidityBps");
    }
}