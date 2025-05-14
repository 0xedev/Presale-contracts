// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPresale {
    function finalize() external returns (bool);
    function getPresaleOptions()
        external
        view
        returns (
            uint256 tokenDeposit,
            uint256 hardCap,
            uint256 softCap,
            uint256 min,
            uint256 max,
            uint256 presaleRate,
            uint256 listingRate,
            uint256 liquidityBps,
            uint256 slippageBps,
            uint256 start,
            uint256 end,
            uint256 lockupDuration,
            uint256 vestingPercentage,
            uint256 vestingDuration,
            uint256 leftoverTokenOption,
            address currency,
            uint8 whitelistType,
            bytes32 merkleRoot,
            address nftContractAddress
        );
    function getTotalContributed() external view returns (uint256);
    function tokenBalance() external view returns (uint256);
    function tokensLiquidity() external view returns (uint256);
    function state() external view returns (uint8);
    function simulateLiquidityAddition() external view returns (bool, uint256, uint256);
}

contract FinalizePresale is Script {
    address constant PRESALE = 0xFA5B34a76a2A39BB7B3Cf1C43ce14EB34CB6464d;

    function run() external {
        // Load private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer private key loaded");

        // Start broadcasting from deployer's account
        vm.startBroadcast(deployerPrivateKey);
        console.log("Broadcast started for deployer");

        // Fetch presale contract
        IPresale presale = IPresale(PRESALE);
        console.log("Presale contract address:", PRESALE);

        // Log presale state and options
        uint8 presaleState = presale.state();
        console.log("Presale state:", presaleState);

        (
            uint256 tokenDeposit,
            uint256 hardCap,
            uint256 softCap,
            uint256 min,
            uint256 max,
            uint256 presaleRate,
            uint256 listingRate,
            uint256 liquidityBps,
            uint256 slippageBps,
            uint256 start,
            uint256 end,
            uint256 lockupDuration,
            uint256 vestingPercentage,
            uint256 vestingDuration,
            uint256 leftoverTokenOption,
            address currency,
            uint8 whitelistType,
            bytes32 merkleRoot,
            address nftContractAddress
        ) = presale.getPresaleOptions();
        console.log("Presale options:");
        console.log("  tokenDeposit:", tokenDeposit);
        console.log("  hardCap:", hardCap);
        console.log("  softCap:", softCap);
        console.log("  min:", min);
        console.log("  max:", max);
        console.log("  presaleRate:", presaleRate);
        console.log("  listingRate:", listingRate);
        console.log("  liquidityBps:", liquidityBps);
        console.log("  slippageBps:", slippageBps);
        console.log("  start:", start);
        console.log("  end:", end);
        console.log("  lockupDuration:", lockupDuration);
        console.log("  vestingPercentage:", vestingPercentage);
        console.log("  vestingDuration:", vestingDuration);
        console.log("  leftoverTokenOption:", leftoverTokenOption);
        console.log("  currency:", currency);
        console.log("  whitelistType:", whitelistType);
        console.log("  merkleRoot:", uint256(merkleRoot));
        console.log("  nftContractAddress:", nftContractAddress);

        // Log total contributed and token balance
        uint256 totalRaised = presale.getTotalContributed();
        console.log("Total raised:", totalRaised);
        uint256 tokenBalance = presale.tokenBalance();
        console.log("Token balance:", tokenBalance);
        uint256 tokensLiquidity = presale.tokensLiquidity();
        console.log("Tokens for liquidity:", tokensLiquidity);

        // Simulate liquidity addition
        console.log("Simulating liquidity addition...");
        (bool canAddLiquidity, uint256 tokenAmount, uint256 currencyAmount) = presale.simulateLiquidityAddition();
        console.log("Simulate liquidity result:");
        console.log("  Can add liquidity:", canAddLiquidity);
        console.log("  Token amount:", tokenAmount);
        console.log("  Currency amount:", currencyAmount);

        // Call finalize
        console.log("Calling finalize...");
        try presale.finalize() returns (bool success) {
            console.log("Finalize succeeded:", success);
        } catch Error(string memory reason) {
            console.log("Finalize failed with reason:", reason);
        } catch {
            console.log("Finalize failed with unknown error");
        }

        vm.stopBroadcast();
        console.log("Broadcast stopped");
    }
}
