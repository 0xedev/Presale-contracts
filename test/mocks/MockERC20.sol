    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol"; // Optional: for setting name/symbol

/**
 * @title MockERC20
 * @notice A simplified ERC20 token implementation for testing purposes.
 * @dev Includes minting functionality and basic ERC20 operations.
 * Does not include advanced features like permits, snapshots, or complex fee logic.
 */
contract MockERC20 is IERC20 {
    // --- State Variables ---
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalSupply;
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    // --- Errors ---
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20InvalidApprover(address approver);

    // --- Constructor ---
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    // --- ERC20 Functions ---

    function approve(address spender, uint256 value) external override returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        uint256 currentBalance = balanceOf[msg.sender];
        if (currentBalance < value) revert ERC20InsufficientBalance(msg.sender, currentBalance, value);

        balanceOf[msg.sender] = currentBalance - value;
        // SafeMath not needed in 0.8+
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (to == address(0)) revert ERC20InvalidReceiver(to);

        // Check allowance
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            // Allow infinite approval
            if (currentAllowance < value) revert ERC20InsufficientAllowance(msg.sender, currentAllowance, value);
            allowance[from][msg.sender] = currentAllowance - value;
        }

        // Check balance
        uint256 currentBalance = balanceOf[from];
        if (currentBalance < value) revert ERC20InsufficientBalance(from, currentBalance, value);

        balanceOf[from] = currentBalance - value;
        balanceOf[to] += value;

        emit Transfer(from, to, value);
        // Approval event only emitted on explicit approve calls generally
        // emit Approval(from, msg.sender, allowance[from][msg.sender]); // Optional: emit updated allowance

        return true;
    }

    // --- Minting Function (for testing) ---

    /**
     * @notice Mints new tokens to a specific address.
     * @dev Only callable by anyone in this mock version for ease of testing.
     * In real scenarios, this would be restricted (e.g., Ownable).
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external {
        if (_to == address(0)) revert ERC20InvalidReceiver(_to);
        totalSupply += _amount;
        balanceOf[_to] += _amount;
        emit Transfer(address(0), _to, _amount); // Standard mint event
    }

    // --- Burn Function (Optional - for testing) ---
    /**
     * @notice Burns tokens from the caller's balance.
     * @param _amount Amount to burn.
     */
    function burn(uint256 _amount) external {
        uint256 currentBalance = balanceOf[msg.sender];
        if (currentBalance < _amount) revert ERC20InsufficientBalance(msg.sender, currentBalance, _amount);

        balanceOf[msg.sender] = currentBalance - _amount;
        totalSupply -= _amount;
        emit Transfer(msg.sender, address(0), _amount);
    }
}
