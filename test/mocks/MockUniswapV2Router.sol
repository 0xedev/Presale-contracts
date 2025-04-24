// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Mock Uniswap V2 Factory (minimal)
 */
contract MockUniswapV2Factory {
    // You might want to store created pairs if your tests need it
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // Simple mock: generate a predictable, non-zero address for the pair
        // This is NOT a real pair address.
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        // <<< FIX: Cast bytes32 hash to uint160 then to address >>>
        pair = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1)))));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair; // Pairs are bidirectional
        return pair;
    }
}

/**
 * @notice Mock Uniswap V2 Router (minimal for Presale testing)
 */
contract MockUniswapV2Router {
    address public immutable WETH;
    // Make factory public state variable (auto-getter)
    address public immutable factory;

    constructor(address _weth) {
        WETH = _weth;
        // Deploy the mock factory and store its address
        factory = address(new MockUniswapV2Factory());
    }

    // Remove explicit factory() function - getter is automatic

    // Mock implementations of addLiquidity functions
    // These just need to exist to prevent reverts during calls.
    // They don't need realistic logic for these unit tests.
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // Pretend some liquidity was added - return non-zero if needed by caller checks
        // In the Presale contract's _liquify, it checks the LP balance,
        // so this mock doesn't directly affect that unit test path.
        // Fork testing is needed for real liquidity checks.
        return (amountTokenDesired, msg.value, 1 ether); // Mock return values
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Mock return values
        return (amountADesired, amountBDesired, 1 ether);
    }

    // Add a fallback or receive function to accept ETH during addLiquidityETH calls
    receive() external payable {}
    fallback() external payable {}
}
