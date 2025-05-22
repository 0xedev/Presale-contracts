// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPresale {
    function cancel() external returns (bool);
    function state() external view returns (uint8);
    function withdraw() external;
}

contract WithdrawPresale is Script {
    // Set your presale contract address here or load from env
    address  PRESALE = vm.envAddress("PRESALE_ADDRESS");

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
        try presale.withdraw() {
            console.log("Withdraw succeeded");
        } catch Error(string memory reason) {
            console.log("Withdraw failed with reason:", reason);
        } catch {
            console.log("Withdraw failed with unknown error");
        }

        uint8 newState = presale.state();
        console.log("Presale state after Withdraw:", newState);

        vm.stopBroadcast();
        console.log("Broadcast stopped");
    }
}