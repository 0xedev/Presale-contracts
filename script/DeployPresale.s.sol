// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/contracts/PresaleFactory.sol";
import "../src/contracts/Presale.sol";

contract DeployPresale is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PresaleFactory factory = PresaleFactory(0xF62c03E08ada871A0bEb309762E260a7a6a880E6); // Replace with deployed factory address
        address token = 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141;
        address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address router = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;

        Presale.PresaleOptions memory options = Presale.PresaleOptions({
            tokenDeposit: 11500 ether,
            hardCap: 10 ether,
            softCap: 5 ether,
            max: 1 ether,
            min: 0.1 ether,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 1 days,
            liquidityBps: 6000,
            slippageBps: 200,
            presaleRate: 1000,
            listingRate: 500,
            lockupDuration: 365 days,
            currency: address(0),
            vestingPercentage: 5000,
            vestingDuration: 180 days,
            leftoverTokenOption: 2 // Vest unsold tokens
        });

        factory.createPresale{value: 0.1 ether}(options, token, weth, router);
        vm.stopBroadcast();
    }
}
