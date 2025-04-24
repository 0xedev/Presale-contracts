// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Script.sol";
// import "../src/contracts/PresaleFactory.sol";

// contract DeployPresaleFactory is Script {
//     function run() external {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         uint256 creationFee = 0.1 ether;
//         address feeToken = address(0); // ETH
//         address token = 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141; // Presale token
//         uint256 housePercentage = 1000; // 10%
//         address houseAddress = 0x1234567890123456789012345678901234567890;

//         PresaleFactory factory = new PresaleFactory(creationFee, feeToken, token, housePercentage, houseAddress);
//         console.log("PresaleFactory deployed at:", address(factory));

//         vm.stopBroadcast();
//     }
// }
