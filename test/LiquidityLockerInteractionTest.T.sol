// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/contracts/PresaleFactory.sol";
import "../src/contracts/Presale.sol";
import "../src/contracts/LiquidityLocker.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Uniswap V2 contracts
contract MockUniswapV2Factory {
    address public pair;

    constructor(address _pair) {
        pair = _pair;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pair;
    }
}

contract MockUniswapV2Pair is ERC20 {
    constructor() ERC20("LP Token", "LPT") {
        _mint(msg.sender, 1000 ether); // Mint some LP tokens for testing
    }
}

contract MockUniswapV2Router {
    address public factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        // Simulate liquidity addition
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        return (amountTokenDesired, msg.value, 100 ether); // Return dummy values
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("Presale Token", "PST") {
        _mint(msg.sender, 1000 ether);
    }
}

contract LiquidityLockerInteractionTest is Test {
    PresaleFactory factory;
    Presale presale;
    MockUniswapV2Factory uniswapFactory;
    MockUniswapV2Router uniswapRouter;
    MockUniswapV2Pair uniswapPair;
    uint256 creationFee = 0.1 ether;

    Presale.PresaleOptions options = Presale.PresaleOptions({
        tokenDeposit: 100 ether,
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
    address weth;

    function setUp() public {
        factory = new PresaleFactory(creationFee, address(0));
        uniswapPair = new MockUniswapV2Pair();
        uniswapFactory = new MockUniswapV2Factory(address(uniswapPair));
        uniswapRouter = new MockUniswapV2Router(address(uniswapFactory));
        weth = address(0x2); // Keep as a placeholder, not strictly needed with mocks
    }

    receive() external payable {}

    function test_LiquidityLockedAfterPresaleFinalization() public {
        MockToken presaleToken = new MockToken();
        Presale.PresaleOptions memory testOptions = options;

        // Create presale with mock Uniswap contracts
        address presaleAddr = factory.createPresale{value: creationFee}(
            testOptions,
            address(presaleToken),
            weth,
            address(uniswapRouter)
        );
        presale = Presale(payable(presaleAddr));

        // Approve and deposit tokens
        presaleToken.approve(presaleAddr, testOptions.tokenDeposit);
        presale.deposit();

        // Simulate contributions to reach soft cap
        vm.warp(testOptions.start);
        vm.deal(address(this), 10 ether);
        presale.contribute{value: 1 ether}();

        address[4] memory contributors = [
            address(0x123),
            address(0x456),
            address(0x789),
            address(0xABC)
        ];
        for (uint i = 0; i < 4; i++) {
            vm.deal(contributors[i], 10 ether);
            vm.prank(contributors[i]);
            presale.contribute{value: 1 ether}();
        }

        // Finalize presale
        vm.warp(testOptions.end + 1);
        presale.finalize();

        // Verify liquidity locking
        (, , address factoryAddr, , , , , , , ) = presale.pool();
        LiquidityLocker locker = factory.liquidityLocker();
        uint256 lockId = locker.lockCount() - 1;
        (address lockedToken, uint256 lockedAmount, uint256 unlockTime, address lockOwner) = locker.getLock(lockId);

        assertEq(lockedToken, address(uniswapPair), "Incorrect token locked (should be LP token)");
        assertGt(lockedAmount, 0, "No tokens locked in LiquidityLocker");
        assertEq(unlockTime, testOptions.end + testOptions.lockupDuration, "Incorrect unlock time");
        assertEq(lockOwner, address(this), "Incorrect lock owner");
    }

    function test_LiquidityUnlockAfterDuration() public {
        MockToken presaleToken = new MockToken();
        Presale.PresaleOptions memory testOptions = options;

        // Create presale with mock Uniswap contracts
        address presaleAddr = factory.createPresale{value: creationFee}(
            testOptions,
            address(presaleToken),
            weth,
            address(uniswapRouter) // Fixed: Use uniswapRouter instead of router
        );
        presale = Presale(payable(presaleAddr));

        // Approve and deposit tokens
        presaleToken.approve(presaleAddr, testOptions.tokenDeposit);
        presale.deposit();

        // Simulate contributions to reach soft cap
        vm.warp(testOptions.start);
        vm.deal(address(this), 10 ether);
        presale.contribute{value: 1 ether}();

        address[4] memory contributors = [
            address(0x123),
            address(0x456),
            address(0x789),
            address(0xABC)
        ];
        for (uint i = 0; i < 4; i++) {
            vm.deal(contributors[i], 10 ether);
            vm.prank(contributors[i]);
            presale.contribute{value: 1 ether}();
        }

        // Finalize presale
        vm.warp(testOptions.end + 1);
        presale.finalize();

        // Access liquidity locker and withdraw
        (, , address factoryAddr, , , , , , , ) = presale.pool();
        LiquidityLocker locker = factory.liquidityLocker();
        uint256 lockId = locker.lockCount() - 1;
        (, uint256 lockedAmount, , ) = locker.getLock(lockId);

        // Warp past lockup duration and withdraw
        vm.warp(testOptions.end + testOptions.lockupDuration + 1);
        locker.withdraw(lockId);

        // Verify withdrawal
        assertEq(IERC20(uniswapPair).balanceOf(address(locker)), 0, "Tokens not unlocked from LiquidityLocker");
        assertEq(IERC20(uniswapPair).balanceOf(address(this)), lockedAmount, "LP tokens not returned to owner");
    }
}