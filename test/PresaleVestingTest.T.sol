// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/contracts/PresaleFactory.sol";
import "../src/contracts/Presale.sol";
import "../src/contracts/Vesting.sol";
import "../src/contracts/TestToken.sol";

contract PresaleVestingTest is Test {
    PresaleFactory factory;
    Presale presale;
    TestToken token;
    Vesting vesting;
    uint256 creationFee = 0.1 ether;
    address creator = address(0x1);
    address contributor = address(0x2);
    address house = address(0x5);

    Presale.PresaleOptions options = Presale.PresaleOptions({
        tokenDeposit: 11500 ether,
        hardCap: 10 ether,
        softCap: 5 ether,
        max: 1 ether,
        min: 0.1 ether,
        start: block.timestamp + 1 hours,
        end: block.timestamp + 1 days,
        liquidityBps: 6000,
        slippageBps: 200,
        presaleRate: 1000,
        listingRate: 500,
        lockupDuration: 365 days,
        currency: address(0),
        vestingPercentage: 5000,
        vestingDuration: 180 days,
        leftoverTokenOption: 2
    });

    function setUp() public {
        token = new TestToken(12000 ether);
        factory = new PresaleFactory(creationFee, address(0), address(token), 1000, house); // 10% house fee
        vm.deal(creator, 1 ether);
        vm.startPrank(creator);
        presale =
            Presale(factory.createPresale{value: creationFee}(options, address(token), address(0x3), address(0x4)));
        vm.stopPrank();
        vesting = factory.vestingContract();
    }

    function test_HousePercentageDistribution() public {
        vm.startPrank(creator);
        token.approve(address(presale), options.tokenDeposit);
        presale.deposit();
        vm.stopPrank();

        vm.deal(contributor, 1 ether);
        vm.warp(options.start);
        vm.prank(contributor);
        presale.contribute{value: 1 ether}();

        vm.warp(options.end);
        vm.prank(creator);
        presale.finalize();

        assertEq(house.balance, 0.1 ether, "House did not receive 10%");
        assertEq(
            presale.ownerBalance(), 0.9 ether - (0.9 ether * options.liquidityBps / 10_000), "Incorrect owner balance"
        );
    }

    function test_UpdateHousePercentage() public {
        vm.prank(factory.owner());
        factory.setHousePercentage(2000); // 20%
        assertEq(factory.housePercentage(), 2000, "House percentage not updated");

        vm.prank(creator);
        Presale newPresale =
            Presale(factory.createPresale{value: creationFee}(options, address(token), address(0x3), address(0x4)));

        vm.startPrank(creator);
        token.approve(address(newPresale), options.tokenDeposit);
        newPresale.deposit();
        vm.stopPrank();

        vm.deal(contributor, 1 ether);
        vm.warp(options.start);
        vm.prank(contributor);
        newPresale.contribute{value: 1 ether}();

        vm.warp(options.end);
        vm.prank(creator);
        newPresale.finalize();

        assertEq(house.balance, 0.2 ether, "House did not receive 20%");
    }

    function test_RevertIfInvalidHousePercentage() public {
        vm.prank(factory.owner());
        vm.expectRevert(PresaleFactory.InvalidHousePercentage.selector);
        factory.setHousePercentage(5001);
    }

    function test_RevertIfInvalidHouseAddress() public {
        vm.prank(factory.owner());
        vm.expectRevert(PresaleFactory.InvalidHouseAddress.selector);
        factory.setHouseAddress(address(0));
    }

    function test_LeftoverTokensReturnedOnCancel() public {
        vm.startPrank(creator);
        token.approve(address(presale), options.tokenDeposit);
        presale.deposit();
        uint256 initialBalance = token.balanceOf(creator);
        presale.cancel();
        vm.stopPrank();

        assertEq(token.balanceOf(creator), initialBalance + options.tokenDeposit, "Tokens not returned on cancel");
        assertEq(presale.pool().tokenBalance, 0, "Token balance not zeroed");
    }

    function test_LeftoverTokensReturnedOnFinalize() public {
        Presale.PresaleOptions memory returnOptions = options;
        returnOptions.leftoverTokenOption = 0;
        presale = Presale(
            factory.createPresale{value: creationFee}(returnOptions, address(token), address(0x3), address(0x4))
        );

        vm.startPrank(creator);
        token.approve(address(presale), returnOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();

        vm.warp(returnOptions.end);
        vm.prank(creator);
        presale.finalize();

        uint256 expectedUnsold =
            returnOptions.tokenDeposit - (presale.pool().tokensClaimable + presale.pool().tokensLiquidity);
        assertEq(token.balanceOf(creator), expectedUnsold, "Tokens not returned");
    }

    function test_LeftoverTokensBurnedOnFinalize() public {
        Presale.PresaleOptions memory burnOptions = options;
        burnOptions.leftoverTokenOption = 1;
        presale =
            Presale(factory.createPresale{value: creationFee}(burnOptions, address(token), address(0x3), address(0x4)));

        vm.startPrank(creator);
        token.approve(address(presale), burnOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();

        vm.warp(burnOptions.end);
        vm.prank(creator);
        presale.finalize();

        uint256 expectedUnsold =
            burnOptions.tokenDeposit - (presale.pool().tokensClaimable + presale.pool().tokensLiquidity);
        assertEq(token.balanceOf(address(0)), expectedUnsold, "Tokens not burned");
    }

    function test_LeftoverTokensVestedOnFinalize() public {
        Presale.PresaleOptions memory vestOptions = options;
        vestOptions.leftoverTokenOption = 2;
        presale =
            Presale(factory.createPresale{value: creationFee}(vestOptions, address(token), address(0x3), address(0x4)));

        vm.startPrank(creator);
        token.approve(address(presale), vestOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();

        vm.warp(vestOptions.end);
        vm.prank(creator);
        presale.finalize();

        uint256 expectedUnsold =
            vestOptions.tokenDeposit - (presale.pool().tokensClaimable + presale.pool().tokensLiquidity);
        assertEq(vesting.remainingVested(creator), expectedUnsold, "Tokens not vested");
    }

    function test_RevertIfInvalidLeftoverTokenOption() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.leftoverTokenOption = 3;
        vm.prank(creator);
        vm.expectRevert(Presale.InvalidLeftoverTokenOption.selector);
        factory.createPresale{value: creationFee}(invalidOptions, address(token), address(0x3), address(0x4));
    }

    function test_RevertIfLiquidityBpsBelow5000() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.liquidityBps = 4999;
        vm.expectRevert(Presale.InvalidLiquidityBps.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, address(0x3), address(0x4));
    }

    function test_RevertIfLiquidityBpsNotAllowed() public {
        Presale.PresaleOptions memory invalidOptions = options;
        invalidOptions.liquidityBps = 5500;
        vm.expectRevert(Presale.InvalidLiquidityBps.selector);
        factory.createPresale{value: creationFee}(invalidOptions, token, address(0x3), address(0x4));
    }

    function test_ValidLiquidityBps() public {
        Presale.PresaleOptions memory validOptions = options;
        validOptions.liquidityBps = 5000;
        address presaleAddr = factory.createPresale{value: creationFee}(validOptions, token, address(0x3), address(0x4));
        assertTrue(presaleAddr != address(0), "Presale creation failed with valid liquidityBps");
    }
}
