// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PresaleFactory} from "../src/contracts/PresaleFactory.sol";
import {Presale} from "../src/contracts/Presale.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CreatePresale is Script {
    function run() external {
        console.log(" [0] Starting CreatePresale script...");

        // Step 0: Load environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        // Step 1: Setup configuration
        address factoryAddress = 0xfBc1Fa497E1314Ef2472986c9313145f631AF9D2;
        address tokenAddress = 0x5Af583f51fC7F5c6f72408294188EcA9BEA25a98;
        address wethAddress = 0x9D36e0edb8BBaBeec5edE8a218dc2B9a6Fce494F;
        address routerAddress = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

        console.log(unicode"🏗 Factory:", factoryAddress);
        console.log(unicode"🪙 Token:", tokenAddress);
        console.log(unicode"💧 WETH:", wethAddress);
        console.log(unicode"🔁 Router:", routerAddress);

        // Step 2: Construct PresaleOptions
        Presale.PresaleOptions memory options = Presale.PresaleOptions({
            tokenDeposit: 1_000_000 * 1e18,
            hardCap: 10 ether,
            softCap: 5 ether,
            min: 0.1 ether,
            max: 2 ether,
            presaleRate: 1000,
            listingRate: 900,
            liquidityBps: 7000,
            slippageBps: 500,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 1 days,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0,
            currency: address(0)
        });

        console.log(unicode"🧮 PresaleOptions prepared:");
        console.log("  Deposit:", options.tokenDeposit);
        console.log("  HardCap:", options.hardCap);
        console.log("  SoftCap:", options.softCap);
        console.log("  Min/Max:", options.min, options.max);
        console.log("  PresaleRate:", options.presaleRate);
        console.log("  ListingRate:", options.listingRate);
        console.log("  LiquidityBps:", options.liquidityBps);
        console.log("  Start:", options.start);
        console.log("  End:", options.end);

        PresaleFactory factory = PresaleFactory(factoryAddress);

        uint256 creationFee;
        address feeToken;
        try factory.getCreationFee() returns (uint256 _fee) {
            creationFee = _fee;
            console.log(unicode"💸 Creation fee:", creationFee);
        } catch {
            revert(unicode"❌ Failed to fetch creationFee from factory.");
        }

        try factory.feeToken() returns (address _feeToken) {
            feeToken = _feeToken;
            console.log(unicode"💳 Fee token:", feeToken);
        } catch {
            revert(unicode"❌ Failed to fetch feeToken from factory.");
        }

        address presaleAddress;

        console.log(unicode"🚀 Starting broadcast...");
        vm.startBroadcast(deployerPrivateKey);

        try this.internalCreatePresale(
            factory, feeToken, creationFee, options, tokenAddress, wethAddress, routerAddress, deployer
        ) returns (address result) {
            presaleAddress = result;
        } catch Error(string memory reason) {
            console.log(unicode"❌ Error:", reason);
            revert("Presale creation failed.");
        } catch {
            revert(unicode"❌ Unknown error during presale creation.");
        }

        vm.stopBroadcast();
        console.log(unicode"✅ Broadcast complete.");

        require(presaleAddress != address(0), unicode"❌ Factory returned address(0)");
        console.log(unicode"🎉 Presale deployed at:", presaleAddress);

        // console.log(unicode"🔍 Checking presale post-conditions...");
        // try Presale(payable(presaleAddress)).owner() returns (address owner) {
        //     console.log(unicode"  👑 Owner:", owner);
        //     require(owner == deployer, unicode"❌ Owner mismatch!");
        // } catch {
        //     console.log(unicode"⚠️ Could not fetch owner.");
        // }

        try Presale(payable(presaleAddress)).token() returns (ERC20 pToken) {
            console.log(unicode"  🪙 Token:", address(pToken)); // cast to address for logging
            require(address(pToken) == tokenAddress, unicode"❌ Token mismatch!");
        } catch {
            console.log(unicode"⚠️ Could not fetch token.");
        }

        try Presale(payable(presaleAddress)).state() returns (Presale.PresaleState state) {
            console.log(unicode"  📦 Initial state (0=Pending):", uint256(state));
            require(uint256(state) == 0, unicode"❌ Presale state is not Pending.");
        } catch {
            console.log(unicode"⚠️ Could not fetch state.");
        }
    }

    // 🧩 Internal helper to abstract createPresale with error handling
    function internalCreatePresale(
        PresaleFactory factory,
        address feeToken,
        uint256 creationFee,
        Presale.PresaleOptions memory options,
        address tokenAddress,
        address wethAddress,
        address routerAddress,
        address deployer
    ) external returns (address) {
        if (feeToken == address(0)) {
            console.log(unicode"💰 Paying fee in ETH...");
            require(deployer.balance >= creationFee, unicode"❌ Not enough ETH for creation fee.");
            return factory.createPresale{value: creationFee}(options, tokenAddress, wethAddress, routerAddress);
        } else {
            console.log(unicode"💳 Paying fee in ERC20...");
            IERC20 token = IERC20(feeToken);
            uint256 allowance = token.allowance(deployer, address(factory));
            console.log(unicode"🔑 Allowance:", allowance);
            require(allowance >= creationFee, unicode"❌ Not enough allowance.");

            uint256 balance = token.balanceOf(deployer);
            console.log(unicode"💼 Balance:", balance);
            require(balance >= creationFee, unicode"❌ Not enough token balance.");

            return factory.createPresale(options, tokenAddress, wethAddress, routerAddress);
        }
    }
}
