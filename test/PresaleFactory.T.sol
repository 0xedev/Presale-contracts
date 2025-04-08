// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/contracts/PresaleFactory.sol";
import "../src/contracts/Presale.sol";
import "../src/contracts/LiquidityLocker.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000 ether);
    }
}

interface PresaleFactoryEvents {
    event PresaleCreated(address indexed creator, address indexed presale, address token, uint256 start, uint256 end);
}

contract PresaleFactoryTest is Test, PresaleFactoryEvents {
    PresaleFactory factory;
    MockERC20 feeToken;
    address owner = address(this);
    address nonOwner = address(0x123);
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
        feeToken = new MockERC20();
        factory = new PresaleFactory(creationFee, address(0));
    }

    receive() external payable {}

    // Deployment Tests
    function test_DeploySuccessfullyWithCorrectFeeAndToken_ETH() public {
        assertEq(factory.creationFee(), creationFee, "Creation fee mismatch");
        assertEq(factory.feeToken(), address(0), "Fee token mismatch");
        assertTrue(address(factory.liquidityLocker()) != address(0), "LiquidityLocker not set");
    }

    function test_DeploySuccessfullyWithCorrectFeeAndToken_ERC20() public {
        factory = new PresaleFactory(creationFee, address(feeToken));
        assertEq(factory.creationFee(), creationFee, "Creation fee mismatch");
        assertEq(factory.feeToken(), address(feeToken), "Fee token mismatch");
        assertTrue(address(factory.liquidityLocker()) != address(0), "LiquidityLocker not set");
    }

    function test_Ownership() public {
        assertEq(factory.owner(), owner, "Deployer is not owner");
    }

    // Presale Creation Tests
    function test_CreatePresaleWithValidParameters_ETH() public {
        address expectedPresale = vm.computeCreateAddress(address(factory), factory.getPresaleCount() + 2);
        vm.expectEmit(true, true, false, true);
        emit PresaleCreated(owner, expectedPresale, token, options.start, options.end);

        uint256 gasStart = gasleft();
        address presale = factory.createPresale{value: creationFee}(options, token, weth, router);
        uint256 gasUsed = gasStart - gasleft();

        assertEq(presale, expectedPresale, "Returned presale address mismatch");
        address[] memory presales = factory.getPresales();
        assertEq(presales.length, 1, "Presale not added to array");
        assertEq(presales[0], presale, "Presale address mismatch in array");
        assertTrue(address(presale).code.length > 0, "Presale address is not a contract");
        assertLt(gasUsed, 5_000_000, "Gas usage for createPresale exceeds reasonable limit");
    }

    function test_CreatePresaleWithValidParameters_ERC20() public {
        factory = new PresaleFactory(creationFee, address(feeToken));
        feeToken.approve(address(factory), creationFee);

        address expectedPresale = vm.computeCreateAddress(address(factory), factory.getPresaleCount() + 2);
        vm.expectEmit(true, true, false, true);
        emit PresaleCreated(owner, expectedPresale, token, options.start, options.end);

        address presale = factory.createPresale(options, token, weth, router);
        assertEq(presale, expectedPresale, "Returned presale address mismatch");
        assertEq(feeToken.balanceOf(address(factory)), creationFee, "ERC20 fee not transferred");
        assertEq(factory.getPresaleCount(), 1, "Presale count not incremented");
        assertTrue(address(presale).code.length > 0, "Presale address is not a contract");
    }

    function test_TracksPresaleAddressesCorrectly() public {
        address presale1 = factory.createPresale{value: creationFee}(options, token, weth, router);
        address presale2 = factory.createPresale{value: creationFee}(options, token, weth, router);
        address[] memory presales = factory.getPresales();
        assertEq(presales[0], presale1, "First presale address mismatch");
        assertEq(presales[1], presale2, "Second presale address mismatch");
    }

    function test_ReturnsCorrectPresaleCount() public {
        factory.createPresale{value: creationFee}(options, token, weth, router);
        factory.createPresale{value: creationFee}(options, token, weth, router);
        assertEq(factory.getPresaleCount(), 2, "Presale count incorrect");
    }

    function test_InsufficientETHFee() public {
        vm.expectRevert(PresaleFactory.InsufficientFee.selector);
        factory.createPresale{value: creationFee - 1}(options, token, weth, router);
    }

    function test_InsufficientERC20Fee() public {
        factory = new PresaleFactory(creationFee, address(feeToken));
        feeToken.approve(address(factory), creationFee - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(factory),
                creationFee - 1,
                creationFee
            )
        );
        factory.createPresale(options, token, weth, router);
    }

    function test_ZeroAddressInputs() public {
        vm.expectRevert();
        factory.createPresale{value: creationFee}(options, address(0), weth, router);
        vm.expectRevert();
        factory.createPresale{value: creationFee}(options, token, address(0), router);
        vm.expectRevert();
        factory.createPresale{value: creationFee}(options, token, weth, address(0));
    }

    // Fee Handling Tests
    function test_OwnerCanWithdrawETHFees() public {
        factory.createPresale{value: creationFee}(options, token, weth, router);
        uint256 initialBalance = owner.balance;
        factory.withdrawFees();
        assertEq(owner.balance, initialBalance + creationFee, "ETH fees not withdrawn");
        assertEq(address(factory).balance, 0, "Factory balance not zero");
    }

    function test_OwnerCanWithdrawERC20Fees() public {
        factory = new PresaleFactory(creationFee, address(feeToken));
        feeToken.approve(address(factory), creationFee);
        factory.createPresale(options, token, weth, router);
        uint256 initialBalance = feeToken.balanceOf(owner);
        factory.withdrawFees();
        assertEq(feeToken.balanceOf(owner), initialBalance + creationFee, "ERC20 fees not withdrawn");
        assertEq(feeToken.balanceOf(address(factory)), 0, "Factory balance not zero");
    }

    function test_RevertsIfSetCreationFeeZero() public {
        vm.expectRevert(PresaleFactory.ZeroFee.selector);
        factory.setCreationFee(0);
    }

    function test_SetCreationFee() public {
        uint256 newFee = 0.2 ether;
        factory.setCreationFee(newFee);
        assertEq(factory.creationFee(), newFee, "Creation fee not updated");
    }

    function test_SetCreationFeeNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        factory.setCreationFee(0.2 ether);
    }

    function test_WithdrawFeesNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        factory.withdrawFees();
    }

    // Edge Case Tests
    function test_CreatePresaleWithMaxHardCap() public {
        Presale.PresaleOptions memory maxOptions = options;
        maxOptions.hardCap = type(uint256).max;
        maxOptions.softCap = type(uint256).max / 4;
        factory.createPresale{value: creationFee}(maxOptions, token, weth, router);
    }

    function test_CreatePresaleWithFeeTokenAsWeth() public {
        MockERC20 wethToken = new MockERC20();
        factory = new PresaleFactory(creationFee, address(wethToken));
        wethToken.approve(address(factory), creationFee);

        address presale = factory.createPresale(options, token, address(wethToken), router);
        assertEq(wethToken.balanceOf(address(factory)), creationFee, "WETH fee not transferred");
        assertEq(factory.getPresaleCount(), 1, "Presale count not incremented");
    }

    // Factory State Tests
    function test_FactoryETHBalanceAfterPresaleCreation() public {
        uint256 initialFactoryBalance = address(factory).balance;
        factory.createPresale{value: creationFee}(options, token, weth, router);
        assertEq(
            address(factory).balance,
            initialFactoryBalance + creationFee,
            "Factory ETH balance not increased by creation fee"
        );
    }

    function test_FactoryERC20BalanceAfterPresaleCreation() public {
        factory = new PresaleFactory(creationFee, address(feeToken));
        feeToken.approve(address(factory), creationFee);
        uint256 initialFactoryBalance = feeToken.balanceOf(address(factory));
        factory.createPresale(options, token, weth, router);
        assertEq(
            feeToken.balanceOf(address(factory)),
            initialFactoryBalance + creationFee,
            "Factory ERC20 balance not increased by creation fee"
        );
    }
}