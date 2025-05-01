// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Imports ---
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol"; // Assuming Vesting/Locker use this

// Import necessary contracts and interfaces
import {Presale} from "./Presale.sol"; // Import Presale to access its struct/enum
import {LiquidityLocker} from "./LiquidityLocker.sol";
import {Vesting} from "./Vesting.sol";
import {IPresale} from "./interfaces/IPresale.sol"; // Import for event/error interfaces if needed

contract PresaleFactory is Ownable {
    using SafeERC20 for IERC20;

    // --- State Variables ---

    // Addresses of core utility contracts deployed by the factory
    LiquidityLocker public immutable liquidityLocker;
    Vesting public immutable vestingContract;

    // Fee configuration
    uint256 public creationFee; // Fee in ETH or feeToken
    address public feeToken; // Address(0) for ETH fee, otherwise ERC20 token address
    uint256 public constant BASIS_POINTS = 10_000;

    // House fee configuration (passed to Presale instances)
    uint256 public immutable housePercentage; // Percentage (BPS) taken from raised funds for the house
    address public immutable houseAddress; // Address receiving the house fee

    // Role identifiers (assuming Vesting/Locker use OpenZeppelin AccessControl)
    bytes32 public constant VESTER_ROLE = keccak256("VESTER_ROLE");
    bytes32 public constant LOCKER_ROLE = keccak256("LOCKER_ROLE");

    address[] public createdPresales; // Track all presale contracts created by this factory
    mapping(address => Presale.PresaleOptions) public presaleConfigurations; // Store configurations for each presale

    // --- Events ---

    event PresaleCreated(
        address indexed creator, address indexed presaleContract, address indexed token, uint256 start, uint256 end
    );

    event PresaleConfiguration(Presale.PresaleOptions indexed options);

    event FeeConfigurationChanged(uint256 newCreationFee, address newFeeToken);

    // --- Errors ---
    error FeePaymentFailed();
    error InvalidFeeConfiguration();
    error InvalidHouseConfiguration();
    error RoleGrantFailed();
    error ZeroAddress();
    error IndexOutOfBounds();
    error NotAPresaleContract();
    error InvalidCapSettings();
    error InvalidCurrencyDecimals();

    // --- Constructor ---
    constructor(
        uint256 _creationFee,
        address _feeToken,
        uint256 _housePercentage, // e.g., 100 for 1%
        address _houseAddress
    ) Ownable(msg.sender) {
        // <<< FIX: Removed check involving msg.value >>>
        // Fee validation happens in createPresale, not here.
        // if (_feeToken == address(0) && _creationFee > 0 && msg.value != _creationFee) {
        //     // If fee is in ETH, constructor doesn't receive value, handle in createPresale
        // }
        if (_feeToken != address(0) && _creationFee > 0) {
            // Cannot verify ERC20 fee payment in constructor easily
        }
        if (_housePercentage > 500) revert InvalidHouseConfiguration(); // Max 5% house fee
        if (_houseAddress == address(0) && _housePercentage > 0) revert InvalidHouseConfiguration();

        creationFee = _creationFee;
        feeToken = _feeToken;
        housePercentage = _housePercentage;
        houseAddress = _houseAddress;

        // Deploy dependent contracts
        // The factory automatically becomes the DEFAULT_ADMIN_ROLE for these
        liquidityLocker = new LiquidityLocker();
        vestingContract = new Vesting();
    }

    // --- External Functions ---

    /**
     * @notice Creates a new Presale contract instance.
     * @param _options The configuration options for the presale.
     * @param _token The address of the ERC20 token being sold.
     * @param _weth The address of the Wrapped Ether contract (used for ETH pairs).
     * @param _uniswapV2Router02 The address of the Uniswap V2 compatible router.
     * @return presaleAddress The address of the newly created Presale contract.
     */
    function createPresale(
        Presale.PresaleOptions memory _options, // Use struct from Presale.sol
        address _token,
        address _weth,
        address _uniswapV2Router02
    ) external payable returns (address presaleAddress) {
        // Keep payable as fee might be ETH
        // 1. Handle Creation Fee
        if (creationFee > 0) {
            if (feeToken == address(0)) {
                // ETH Fee
                if (msg.value < creationFee) revert FeePaymentFailed();
                // Forward excess ETH if any? Or require exact amount. Assuming require exact for now.
                if (msg.value > creationFee) {
                    payable(msg.sender).transfer(msg.value - creationFee); // Return excess
                }
                // Note: The actual creationFee amount stays with the factory temporarily
                // and can be withdrawn by the owner using withdrawFees().
            } else {
                // ERC20 Fee
                if (msg.value > 0) revert InvalidFeeConfiguration(); // Should not send ETH if fee is token
                IERC20(feeToken).safeTransferFrom(msg.sender, owner(), creationFee); // Send fee directly to owner
            }
        } else {
            if (msg.value > 0) revert InvalidFeeConfiguration(); // Should not send ETH if no fee
        }

        // 2. Deploy the Presale Contract
        Presale newPresale = new Presale(
            _weth,
            _token,
            _uniswapV2Router02,
            _options,
            msg.sender, // The creator of the presale via the factory
            address(liquidityLocker),
            address(vestingContract),
            housePercentage,
            houseAddress
        );

        presaleAddress = address(newPresale);

        // Transfer presale tokens to the presale contract
        IERC20(_token).safeTransferFrom(msg.sender, presaleAddress, _options.tokenDeposit);
        newPresale.initializeDeposit(_options.tokenDeposit);

        // 3. Grant Roles to the new Presale contract
        // The factory needs DEFAULT_ADMIN_ROLE on Locker/Vesting (granted by constructor)
        try vestingContract.grantRole(VESTER_ROLE, presaleAddress) {}
        catch {
            revert RoleGrantFailed();
        }
        try liquidityLocker.grantRole(LOCKER_ROLE, presaleAddress) {}
        catch {
            revert RoleGrantFailed();
        }
        createdPresales.push(presaleAddress);
        // 4. Emit Factory-level event (optional, as Presale constructor also emits)
        emit PresaleCreated(msg.sender, presaleAddress, _token, _options.start, _options.end);
        emit PresaleConfiguration(_options);
        return presaleAddress;
    }

    /**
     * @notice Updates the creation fee configuration. Only callable by the owner.
     * @param _newCreationFee The new fee amount.
     * @param _newFeeToken The new fee token address (address(0) for ETH).
     */
    function setFeeConfiguration(uint256 _newCreationFee, address _newFeeToken) external onlyOwner {
        if (_newFeeToken != address(0)) {
            // Basic check if it looks like a contract
            uint32 size;
            assembly {
                size := extcodesize(_newFeeToken)
            }
            if (size == 0) revert ZeroAddress(); // Use a more specific error if desired
        }

        creationFee = _newCreationFee;
        feeToken = _newFeeToken;
        emit FeeConfigurationChanged(_newCreationFee, _newFeeToken);
    }

    /**
     * @notice Allows the owner to withdraw collected ETH fees from this factory contract.
     * @dev ERC20 fees are sent directly to the owner during creation.
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool success,) = owner().call{value: balance}(""); // Use call for safer transfer
        require(success, "ETH fee withdrawal failed");
    }

    function calculateTotalTokensNeededForPresale(Presale.PresaleOptions memory _options, address _token)
        external
        view
        returns (uint256 totalTokensNeeded)
    {
        if (_token == address(0)) revert ZeroAddress();
        if (_options.hardCap == 0 || _options.presaleRate == 0 || _options.listingRate == 0) {
            revert InvalidCapSettings();
        }

        uint256 currencyMultiplier = _getCurrencyMultiplier(_options.currency);
        uint256 tokenDecimals = 10 ** ERC20(_token).decimals();

        // Calculate tokens for presale: (hardCap * presaleRate * 10^tokenDecimals) / currencyMultiplier
        uint256 tokensForPresale = (_options.hardCap * _options.presaleRate * tokenDecimals) / currencyMultiplier;

        // Calculate tokens for liquidity: (currencyForLiquidity * listingRate * 10^tokenDecimals) / currencyMultiplier
        uint256 currencyForLiquidity = (_options.hardCap * _options.liquidityBps) / 10_000;
        uint256 tokensForLiquidity = (currencyForLiquidity * _options.listingRate * tokenDecimals) / currencyMultiplier;

        totalTokensNeeded = tokensForPresale + tokensForLiquidity;
        return totalTokensNeeded;
    }

    function _getCurrencyMultiplier(address _currency) private view returns (uint256) {
        if (_currency == address(0)) {
            return 1 ether; // ETH uses 10^18
        }
        try ERC20(_currency).decimals() returns (uint8 decimals) {
            return 10 ** decimals;
        } catch {
            revert InvalidCurrencyDecimals();
        }
    }

    // --- View Functions ---

    function getCreationFee() external view returns (uint256) {
        return creationFee;
    }

    function getHousePercentage() external view returns (uint256) {
        return housePercentage;
    }

    function getHouseAddress() external view returns (address) {
        return houseAddress;
    }

    function getPresaleCount() external view returns (uint256) {
        return createdPresales.length;
    }

    function getPresaleAt(uint256 index) external view returns (address) {
        if (index >= createdPresales.length) revert IndexOutOfBounds(); // Use custom error
        return createdPresales[index];
    }

    function getAllPresales() external view returns (address[] memory) {
        return createdPresales;
    }

    function getPresaleOptionsByAddress(address _presaleAddress)
        external
        view
        returns (Presale.PresaleOptions memory options)
    {
        // Basic check: Ensure the address is a contract
        uint32 size;
        assembly {
            size := extcodesize(_presaleAddress)
        }
        if (size == 0) revert NotAPresaleContract();

        // Call the getOptions function on the target Presale contract
        // This requires Presale.sol to have a public/external view function getOptions()
        // and IPresale interface to declare it.
        try IPresale(_presaleAddress).getOptions() returns (Presale.PresaleOptions memory _options) {
            return _options;
        } catch {
            // Handle cases where the call fails (e.g., address is not a Presale contract
            // or doesn't implement getOptions correctly)
            revert NotAPresaleContract(); // Or a more specific error
        }
    }
}
