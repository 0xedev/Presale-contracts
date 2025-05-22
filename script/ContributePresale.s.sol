// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Presale} from "../src/contracts/Presale.sol";

interface IPresale {
    function contribute(bytes32[] calldata _merkleProof) external payable;
    function contributeStablecoin(uint256 _amount, bytes32[] calldata _merkleProof) external;
    function state() external view returns (uint8);
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
}

contract ContributeToPresale is Script {
    using SafeERC20 for IERC20;

    // Configuration - Load from environment variables
    address presaleAddress = vm.envAddress("PRESALE_ADDRESS");
    address currencyTokenAddress = vm.envAddress("CURRENCY_TOKEN_ADDRESS");
    uint256 contributionAmount = vm.envUint("CONTRIBUTION_AMOUNT");
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    function run() external {
        // Input Validation
        require(presaleAddress != address(0), "PRESALE_ADDRESS not set");
        require(contributionAmount > 0, "CONTRIBUTION_AMOUNT must be greater than 0");

        // Instantiate Contracts
        IPresale presale = IPresale(presaleAddress);
        IERC20 currencyToken = IERC20(currencyTokenAddress);

        // Check Presale State and Options
        uint8 presaleState = presale.state();
        console.log("Presale state:", presaleState);
        require(presaleState == 1, "Presale is not active");

        (
            , // tokenDeposit
            ,
            ,
            uint256 min,
            uint256 max,
            , // presaleRate
            , // listingRate
            , // liquidityBps
            , // slippageBps
            uint256 start,
            uint256 end,
            , // lockupDuration
            , // vestingPercentage
            , // vestingDuration
            , // leftoverTokenOption
            address currency,
            , // whitelistType
            , // merkleRoot
                // nftContractAddress
        ) = presale.getPresaleOptions();

        // Validate Contribution
        require(block.timestamp >= start && block.timestamp <= end, "Presale not in active period");
        require(contributionAmount >= min, "Contribution below minimum");
        require(contributionAmount <= max, "Contribution above maximum");
        require(currency == currencyTokenAddress || currency == address(0), "Currency mismatch");

        // Start Broadcast
        vm.startBroadcast(deployerPrivateKey);
        console.log("Contributing to presale...");

        // Handle Contribution
        if (currency == address(0)) {
            // ETH Contribution (no whitelist)
            console.log("Sending ETH contribution:", contributionAmount);
            bytes32[] memory emptyProof = new bytes32[](0);
            presale.contribute{value: contributionAmount}(emptyProof);
        } else {
            // ERC20 Contribution (no whitelist)
            console.log("Approving currency token:", currencyTokenAddress);
            currencyToken.approve(presaleAddress, contributionAmount);
            console.log("Sending ERC20 contribution:", contributionAmount);
            bytes32[] memory emptyProof = new bytes32[](0);
            presale.contributeStablecoin(contributionAmount, emptyProof);
        }

        console.log("Contribution successful!");
        vm.stopBroadcast();
    }
}
