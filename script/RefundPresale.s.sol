// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPresale {
    function cancel() external returns (bool);
    function state() external view returns (uint8);
    function refund() external returns (uint256);
}

contract RefundPresale is Script {
    // Set your presale contract address here or load from env
    address PRESALE = vm.envAddress("PRESALE_ADDRESS");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer private key loaded");

        vm.startBroadcast(deployerPrivateKey);
        console.log("Broadcast started for deployer");

        IPresale presale = IPresale(PRESALE);
        console.log("Presale contract address:", PRESALE);

        uint8 presaleState = presale.state();
        console.log("Presale state before cancel:", presaleState);

        // Call cancel
        console.log("Calling cancel...");
        try presale.refund() returns (uint256 amount) {
            console.log("refund succeeded:", amount);
        } catch Error(string memory reason) {
            console.log("refund failed with reason:", reason);
        } catch {
            console.log("refund failed with unknown error");
        }

        uint8 newState = presale.state();
        console.log("Presale state after refund:", newState);

        vm.stopBroadcast();
        console.log("Broadcast stopped");
    }
}
