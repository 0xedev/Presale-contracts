// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Use the actual interface from the library
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

/**
 * @title Mock Uniswap V2 Factory
 * @notice Minimal mock for testing Presale interactions, primarily getPair.
 * @dev Implements IUniswapV2Factory. Uses create2 logic for deterministic pair addresses.
 */
contract MockUniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    // Store the pair init code hash (can be pre-calculated or taken from a real deployment)
    // Example hash for standard UniswapV2Pair:
    bytes32 public constant PAIR_INIT_CODE_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    // If using different pair code (e.g., PancakeSwap), use that hash instead.


    constructor() {
        feeToSetter = msg.sender; // Typically deployer in tests
    }

    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }

    /**
     * @notice Mocks pair creation and stores the deterministic address.
     * @dev Uses create2 logic consistent with UniswapV2.
     */
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, "MockV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "MockV2: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "MockV2: PAIR_EXISTS");

        // Calculate the deterministic pair address using create2 logic
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex"ff",
                address(this), // Factory address
                keccak256(abi.encodePacked(token0, token1)), // Salt
                PAIR_INIT_CODE_HASH // Pair contract init code hash
            )))));

        // No actual deployment, just store the calculated address
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
     * @notice Helper function often used in tests to pre-calculate the pair address.
     */
    function pairFor(address tokenA, address tokenB) public view returns (address pair) {
         (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
         pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex"ff",
                address(this),
                keccak256(abi.encodePacked(token0, token1)),
                PAIR_INIT_CODE_HASH
            )))));
    }


    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "MockV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "MockV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
