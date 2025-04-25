// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LiquidityLocker} from "src/contracts/LiquidityLocker.sol"; // Adjust path if needed
import {Vesting} from "src/contracts/Vesting.sol";             // Adjust path if needed
import {PresaleFactory} from "src/contracts/PresaleFactory.sol"; // Adjust path if needed
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // For fee token check

contract DeployPresaleSystem is Script {

    // --- Configuration ---

    // Default PresaleFactory Constructor Args (used if env vars not set)
    // Use vm.envOr to fetch from .env, otherwise use these:
    uint256 public constant DEFAULT_CREATION_FEE_ETH = 0.00001 ether; // Default if FEE_TOKEN is address(0)
    uint256 public constant DEFAULT_CREATION_FEE_TOKEN_UNITS = 10 * 10**18; // Example: 10 units if FEE_TOKEN is an ERC20 (adjust decimals if needed)
    address public constant DEFAULT_FEE_TOKEN = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81;   // address(0) for native currency (ETH)
    uint256 public constant DEFAULT_HOUSE_PERCENTAGE = 100;   // Example: 100 basis points = 1%

    // Addresses (fetched from environment variables)
    address public deployer;
    address public houseAddress; // Address to receive factory fees

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        houseAddress = vm.envAddress("HOUSE_ADDRESS");

        if (houseAddress == address(0)) {
            console.log("Warning: HOUSE_ADDRESS environment variable not set. Defaulting to deployer address.");
            houseAddress = deployer;
        }
    }

    function run() external {
        // --- Get Configuration ---
        address feeToken = vm.envAddress("FEE_TOKEN");
        uint256 creationFee;
        if (feeToken == address(0)) {
            // If using ETH, get fee in wei, default to DEFAULT_CREATION_FEE_ETH
            creationFee = vm.envUint("CREATION_FEE");
        } else {
            // If using ERC20, get fee in token units, default to DEFAULT_CREATION_FEE_TOKEN_UNITS
            // Assumes the value in .env is already in the correct base units (like wei for 18 decimals)
            creationFee = vm.envUint("CREATION_FEE");
        }
        uint256 housePercentage = vm.envUint("HOUSE_PERCENTAGE");
        uint256 chainId = vm.envUint("CHAIN_ID"); // Get chain ID from env or current block

        console.log("\n--- Deployment Configuration ---");
        console.log("Deployer Address:", deployer);
        console.log("Target Chain ID:", chainId);
        console.log("House Address:", houseAddress);
        console.log("Creation Fee:", creationFee);
        console.log("Fee Token:", feeToken);
        console.log("House Percentage (Basis Points):", housePercentage);
        console.log("---------------------------------");

        // --- Start Deployment ---
        vm.startBroadcast(deployer);

        // 1. Deploy LiquidityLocker
        LiquidityLocker locker = new LiquidityLocker();
        console.log("LiquidityLocker deployed at:", address(locker));

        // 2. Deploy Vesting
        // Foundry automatically uses the artifact from out/Vesting.sol/Vesting.json
        Vesting vesting = new Vesting();
        console.log("Vesting deployed at:", address(vesting));

        // 3. Deploy PresaleFactory
        // Pass constructor arguments. Foundry automatically links immutable addresses
        // for locker and vesting based on the PresaleFactory source code.
        PresaleFactory factory = new PresaleFactory(
            creationFee,
            feeToken,
            housePercentage,
            houseAddress
        );
        console.log("PresaleFactory deployed at:", address(factory));

        // 4. Grant Roles to the Factory
        // The deployer initially has DEFAULT_ADMIN_ROLE on locker and vesting.
        bytes32 lockerRole = locker.LOCKER_ROLE();
        locker.grantRole(lockerRole, address(factory));
        console.log("Granted LOCKER_ROLE to Factory on LiquidityLocker");

        bytes32 vesterRole = vesting.VESTER_ROLE();
        vesting.grantRole(vesterRole, address(factory));
        console.log("Granted VESTER_ROLE to Factory on Vesting");

        vm.stopBroadcast();

        // --- Verification ---
        string memory etherscanApiKey = vm.envString("ETHERSCAN_API_KEY"); // Use placeholder if not set
        if (bytes(etherscanApiKey).length > 0 && bytes(etherscanApiKey).length != 20) { // Basic check if API key seems set
             console.log("\n--- Attempting Verification ---");

             // LiquidityLocker Verification
             _verifyContract(
                 chainId,
                 address(locker),
                 "src/contracts/LiquidityLocker.sol:LiquidityLocker", // Adjust path if needed
                 "", // No constructor args
                 etherscanApiKey
             );

             // Vesting Verification
             _verifyContract(
                 chainId,
                 address(vesting),
                 "src/contracts/Vesting.sol:Vesting", // Adjust path if needed
                 "", // No constructor args
                 etherscanApiKey
             );

             // PresaleFactory Verification
             bytes memory factoryArgs = abi.encode(creationFee, feeToken, housePercentage, houseAddress);
             _verifyContract(
                 chainId,
                 address(factory),
                 "src/contracts/PresaleFactory.sol:PresaleFactory", // Adjust path if needed
                 vm.toString(factoryArgs), // ABI encoded constructor args
                 etherscanApiKey
             );
             console.log("-------------------------------");
        } else {
            console.log("\n--- Skipping Verification (Set ETHERSCAN_API_KEY and CHAIN_ID in .env) ---");
            // Output manual commands if needed
        }
    }

    // Helper function for verification to avoid repetition
    function _verifyContract(
        uint256 _chainId,
        address _contractAddress,
        string memory _contractPathAndName,
        string memory _constructorArgsHex,
        string memory _etherscanApiKey
    ) internal {
        string[] memory args = new string[](11);
        args[0] = "forge"; 
        args[1] = "verify-contract";
        args[2] = "--chain-id";
        args[3] = vm.toString(_chainId);
        args[4] = vm.toString(_contractAddress);
        args[5] = _contractPathAndName;
        args[6] = "--etherscan-api-key";
        args[7] = _etherscanApiKey;
        if (bytes(_constructorArgsHex).length > 0) {
            args[8] = "--constructor-args";
            args[9] = _constructorArgsHex;
            args[10] = ""; // Placeholder if needed, adjust array size if not using args[10]
        } else { 
            // Adjust array size or handle differently if no constructor args
             string[] memory noArgs = new string[](9);
             for(uint i=0; i < 8; i++){
                 noArgs[i] = args[i];
             }
             noArgs[8] = ""; // Placeholder 
             args = noArgs;
        }


        console.log("Running verification for:", _contractPathAndName);
        // Execute the command
        bytes memory output = vm.ffi(args);
        console.log(string(output));
    }
}
