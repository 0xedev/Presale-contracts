// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";
import {MockFactory} from "./MockFactory.sol";

contract MockRouter {
    address public factory;
    address public WETH;

    constructor() {
        WETH = address(0xBEEF); // Match test setup
    }

    function setFactory(address _factory) external {
        factory = _factory;
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(deadline >= block.timestamp, "MockRouter: EXPIRED");
        require(amountTokenDesired > 0 && msg.value > 0, "MockRouter: INVALID_AMOUNTS");
        require(to != address(0), "MockRouter: INVALID_TO");

        // Get pair from factory
        address pair = getPair(token, WETH);
        require(pair != address(0), "MockRouter: PAIR_NOT_FOUND");

        // Simulate token transfer
        MockERC20(token).transferFrom(msg.sender, pair, amountTokenDesired);

        // Simulate LP token minting
        uint256 lpAmount = amountTokenDesired; // Simplified: 1:1 token to LP for testing
        MockERC20(pair).mint(to, lpAmount);

        // Return values
        amountToken = amountTokenDesired;
        amountETH = msg.value;
        liquidity = lpAmount;

        return (amountToken, amountETH, liquidity);
    }

    function getPair(address tokenA, address tokenB) internal view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return MockFactory(factory).getPair(token0, token1);
    }

    // function factory() external view returns (address) {
    //     return factory;
    // }
}
