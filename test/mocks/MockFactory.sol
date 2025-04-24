// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

contract MockFactory {
    address public pair;
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address) {
        // Sort tokens to ensure consistent pair address
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // Deploy a MockERC20 to simulate the pair
        MockERC20 pairContract = new MockERC20(string(abi.encodePacked("LP Token ", token0, "-", token1)), "LP", 18);
        pair = address(pairContract);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        return pair;
    }
}
