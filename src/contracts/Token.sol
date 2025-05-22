// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyPresaleToken
 * @dev A simple ERC20 token for presale purposes.
 * The entire initial supply is minted to the deployer of the contract.
 */
contract MyPresaleToken is ERC20, Ownable {
    /**
     * @dev Constructor that gives msg.sender all of initialSupply.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     * @param initialSupply_ The total initial supply of the token, minted to the deployer.
     */
    constructor(string memory name_, string memory symbol_, uint256 initialSupply_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply_);
    }
}
