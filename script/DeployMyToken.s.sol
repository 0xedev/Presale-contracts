// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/contracts/MyPresaleToken.sol"; // Adjust path if needed

contract DeployMyToken is Script {
    function run() external returns (MyPresaleToken) {
        vm.startBroadcast();

        // --- Token Configuration ---
        string memory tokenName = "My Presale Token";
        string memory tokenSymbol = "MPT1";
        uint256 initialSupply = 1_000_000_000 * (10 ** 18); // 1 Billion tokens with 18 decimals

        MyPresaleToken token = new MyPresaleToken(tokenName, tokenSymbol, initialSupply);
        console.log("MyPresaleToken deployed at:", address(token));
        console.log("Token Name:", token.name());
        console.log("Token Symbol:", token.symbol());
        console.log("Total Supply:", token.totalSupply());
        console.log("Deployer Balance:", token.balanceOf(msg.sender));

        vm.stopBroadcast();
        return token;
    }
}
