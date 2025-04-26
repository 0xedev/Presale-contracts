// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PresaleFactory} from "../src/contracts/PresaleFactory.sol"; // Adjust path if needed

contract DeployPresale is Script {
    function run() external returns (PresaleFactory) {
        // Load environment variables
        uint256 creationFee = vm.envUint("CREATION_FEE");
        address feeToken = vm.envAddress("FEE_TOKEN");
        uint256 housePercentage = vm.envUint("HOUSE_PERCENTAGE");
        address houseAddress = vm.envAddress("HOUSE_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Or PK_ACCOUNT1

        // --- Input Validation (Optional but Recommended) ---
        require(creationFee > 0 || feeToken == address(0), "Invalid fee config");
        require(housePercentage <= 500, "House percentage too high"); // Max 5%
        require(houseAddress != address(0) || housePercentage == 0, "Invalid house address");
        if (feeToken != address(0)) {
             uint32 size;
             address tokenAddr = feeToken; // Avoid stack too deep
             assembly { size := extcodesize(tokenAddr) }
             require(size > 0, "Fee token is not a contract");
        }

        vm.startBroadcast(deployerPrivateKey);

        // --- Deploy ONLY the Factory ---
        // The factory constructor will deploy LiquidityLocker and Vesting internally.
        PresaleFactory presaleFactory = new PresaleFactory(
            creationFee,
            feeToken,
            housePercentage,
            houseAddress
        );

        console.log("PresaleFactory deployed to:", address(presaleFactory));
        // Log the internally deployed addresses if needed for verification
        console.log(" -> LiquidityLocker deployed to:", address(presaleFactory.liquidityLocker()));
        console.log(" -> Vesting deployed to:", address(presaleFactory.vestingContract()));

        vm.stopBroadcast();
        return presaleFactory;
    }
}

