// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PresaleFactory} from "../src/contracts/PresaleFactory.sol";
import {Presale} from "../src/contracts/Presale.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CreatePresale is Script {
    using SafeERC20 for IERC20;

    // --- Configuration - Load from environment variables ---
    address factoryAddress = vm.envAddress("FACTORY_ADDRESS"); // Your deployed factory: 0xB70f14D9478dD54454898a4dE0EDae34a3a3E03d
    address presaleTokenAddress = vm.envAddress("PRESALE_TOKEN_ADDRESS"); // Token being sold
    address currencyTokenAddress = vm.envAddress("CURRENCY_TOKEN_ADDRESS"); // address(0) for ETH
    address wethAddress = vm.envAddress("WETH_ADDRESS"); // e.g., 0x4200000000000000000000000000000000000006 on Base
    address routerAddress = vm.envAddress("ROUTER_ADDRESS"); // e.g., 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24 on Base
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    // Presale Options - Load from environment or set defaults
    // Ensure these values make sense together!
    uint256 hardCap = vm.envUint("HARD_CAP"); // e.g., 10 ether or 10_000 * 1e6 for 10k USDC
    uint256 softCap = vm.envUint("SOFT_CAP"); // e.g., 5 ether or 5_000 * 1e6 for 5k USDC
    uint256 minContribution = vm.envUint("MIN_CONTRIBUTION"); // e.g., 0.01 ether or 10 * 1e6 for 10 USDC
    uint256 maxContribution = vm.envUint("MAX_CONTRIBUTION"); // e.g., 1 ether or 1_000 * 1e6 for 1k USDC
    uint256 presaleRate = vm.envUint("PRESALE_RATE"); // Tokens per 1 unit of currency (e.g., 1000 tokens per 1 ETH/USDC)
    uint256 listingRate = vm.envUint("LISTING_RATE"); // Tokens per 1 unit of currency for liquidity (MUST be < presaleRate)
    uint256 liquidityBps = vm.envUint("LIQUIDITY_BPS"); // e.g., 7000 (70%)
    uint256 slippageBps = vm.envOr("SLIPPAGE_BPS", uint256(500)); // Default 5%
    uint256 startOffset = vm.envOr("START_TIME_OFFSET", uint256(600)); // Default 10 mins from now
    uint256 duration = vm.envOr("DURATION", uint256(3 days)); // Default 3 days
    uint256 lockupDuration = vm.envOr("LOCKUP_DURATION", uint256(90 days)); // Default 90 days
    uint256 vestingPercentage = vm.envOr("VESTING_PERCENTAGE", uint256(0)); // Default 0% (0 BPS)
    uint256 vestingDuration = vm.envOr("VESTING_DURATION", uint256(0)); // Default 0 seconds
    uint256 leftoverTokenOption = vm.envOr("LEFTOVER_OPTION", uint256(0)); // Default 0 (Return to owner)
      uint8 whitelistType = uint8(vm.envOr("WHITELIST_TYPE", uint256(0))); // 0=None, 1=Merkle, 2=NFT
    bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT"); // Only needed if WHITELIST_TYPE=1
    address nftContractAddress = vm.envAddress("NFT_CONTRACT_ADDRESS"); // Only needed if WHITELIST_TYPE=2

    function run() external returns (address presaleAddress) {
        // --- Input Validation ---
        require(factoryAddress != address(0), "FACTORY_ADDRESS not set");
        require(presaleTokenAddress != address(0), "PRESALE_TOKEN_ADDRESS not set");
        require(wethAddress != address(0), "WETH_ADDRESS not set");
        require(routerAddress != address(0), "ROUTER_ADDRESS not set");
        require(hardCap > 0 && softCap > 0 && softCap <= hardCap, "Invalid caps");
        require(minContribution > 0 && maxContribution > 0 && minContribution <= maxContribution && maxContribution <= hardCap, "Invalid contribution limits");
        require(presaleRate > 0 && listingRate > 0 && listingRate < presaleRate, "Invalid rates");
        require(liquidityBps >= 5000 && liquidityBps <= 10000, "Invalid liquidity BPS (5000-10000)"); // Basic check
        require(whitelistType <= 2, "Invalid WHITELIST_TYPE (0, 1, or 2)");
        if (whitelistType == 1) { // Merkle
            require(merkleRoot != bytes32(0), "MERKLE_ROOT required for WHITELIST_TYPE=1");
        } else if (whitelistType == 2) { // NFT
            require(nftContractAddress != address(0), "NFT_CONTRACT_ADDRESS required for WHITELIST_TYPE=2");
        }

        // --- Instantiate Contracts ---
        PresaleFactory factory = PresaleFactory(payable(factoryAddress));
        IERC20 presaleToken = IERC20(presaleTokenAddress);

        // --- Prepare Presale Options ---
        uint256 startTime = block.timestamp + startOffset;
        uint256 endTime = startTime + duration;

        // Calculate required token deposit using the factory's helper
        Presale.PresaleOptions memory optionsPreCalc = Presale.PresaleOptions({
            tokenDeposit: 0, // Will be calculated
            hardCap: hardCap,
            softCap: softCap,
            min: minContribution,
            max: maxContribution,
            presaleRate: presaleRate,
            listingRate: listingRate,
            liquidityBps: liquidityBps,
            slippageBps: slippageBps,
            start: startTime,
            end: endTime,
            lockupDuration: lockupDuration,
            vestingPercentage: vestingPercentage,
            vestingDuration: vestingDuration,
            leftoverTokenOption: leftoverTokenOption,
            currency: currencyTokenAddress,
            whitelistType: Presale.WhitelistType(whitelistType), // Set from env var
            merkleRoot: merkleRoot, // Set from env var
            nftContractAddress: nftContractAddress // Set from env var
        });

        uint256 requiredTokenDeposit = factory.calculateTotalTokensNeededForPresale(optionsPreCalc, presaleTokenAddress);
        console.log("Required Presale Token Deposit:", requiredTokenDeposit);

        Presale.PresaleOptions memory options = optionsPreCalc;
        options.tokenDeposit = requiredTokenDeposit; // Set the calculated deposit amount

        // --- Approvals & Fee Handling ---
        vm.startBroadcast(deployerPrivateKey);

        // 1. Approve Presale Tokens
        console.log("Approving factory to spend presale tokens...");
        presaleToken.approve(factoryAddress, requiredTokenDeposit);
        console.log("Presale token approval successful.");

        // 2. Handle Creation Fee
        uint256 creationFee = factory.creationFee();
        address feeTokenAddress = factory.feeToken();
        uint256 ethFeeToSend = 0;

        if (creationFee > 0) {
            if (feeTokenAddress == address(0)) {
                // ETH Fee
                ethFeeToSend = creationFee;
                console.log("Paying ETH creation fee:", ethFeeToSend);
            } else {
                // ERC20 Fee
                console.log("Approving factory to spend fee token:", feeTokenAddress);
                IERC20 feeToken = IERC20(feeTokenAddress);
                feeToken.approve(factoryAddress, creationFee); // Approve factory to pull fee
                console.log("Fee token approval successful.");
                // Note: Factory transfers fee to owner in createPresale
            }
        } else {
            console.log("No creation fee required.");
        }

        // --- Create Presale ---
        console.log("Creating presale...");
        presaleAddress = factory.createPresale{value: ethFeeToSend}(
            options,
            presaleTokenAddress,
            wethAddress,
            routerAddress
        );

        vm.stopBroadcast();

        console.log("Presale contract created successfully at:", presaleAddress);
        return presaleAddress;
    }
}