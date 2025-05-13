// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface IPresale {
    function finalize() external;
}

contract FinalizePresale is Script {
    address constant PRESALE = 0x600FE9F072f59539e31bC593b203105B6d0ce9c2;

    function run() external {
        // Load private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting from deployer's account
        vm.startBroadcast(deployerPrivateKey);

        // Call finalize()
        IPresale(PRESALE).finalize();

        vm.stopBroadcast();
    }
}
