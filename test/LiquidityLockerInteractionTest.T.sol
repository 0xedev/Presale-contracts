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
        _mint(msg.sender, 12000 ether); // Mint to test contract
    }
}

contract MockUniswapV2Router {
    address public factory;
    MockUniswapV2Pair public pair;

    constructor(address _factory) {
        factory = _factory;
        pair = MockUniswapV2Pair(MockUniswapV2Factory(_factory).pair());
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        uint256 liquidityAmount = 100 ether; // Simulated LP tokens to mint
        pair.transfer(to, liquidityAmount); // Transfer LP tokens to the caller (Presale contract)
        return (amountTokenDesired, msg.value, liquidityAmount);
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("Presale Token", "PST") {
        _mint(msg.sender, 12000 ether);
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
        tokenDeposit: 11500 ether,
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
    address weth;

    function setUp() public {
        uniswapPair = new MockUniswapV2Pair();
        uniswapFactory = new MockUniswapV2Factory(address(uniswapPair));
        uniswapRouter = new MockUniswapV2Router(address(uniswapFactory));
        weth = address(0x2); // Initialize WETH address

        // Initialize the router variable
        address router = address(uniswapRouter);

        factory = new PresaleFactory(creationFee, router, weth, 0, address(this));

        // Transfer some LP tokens to the router to simulate a liquidity pool
        uniswapPair.transfer(address(uniswapRouter), 1000 ether); // Enough for multiple tests
    }

    receive() external payable {}
}
