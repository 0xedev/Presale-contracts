// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "src/contracts/TestToken.sol";
import "forge-std/console.sol";

contract DeployTestToken {
    function run() public {
        uint256 initialSupply = 12000000000000000000000;
        TestToken token = new TestToken(initialSupply);

        // Log the deployed contract address
        console.log("Deployed TestToken address:", address(token));
    }
}
