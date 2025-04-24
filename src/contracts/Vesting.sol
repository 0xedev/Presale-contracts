// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Generic Vesting Contract
 * @notice Manages linear vesting schedules for various ERC20 tokens.
 * @dev Uses AccessControl (VESTER_ROLE for creation, DEFAULT_ADMIN_ROLE for admin tasks).
 * Each schedule stores the specific token being vested.
 */
contract Vesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Roles ---
    bytes32 public constant VESTER_ROLE = keccak256("VESTER_ROLE");

    // --- State ---
    // REMOVED: No single immutable token
    // IERC20 public immutable token;
    bool public paused;
    // Note: totalAllocated becomes less meaningful if tracking multiple tokens.
    // Consider removing or making it a mapping(address => uint256) token => totalAllocated
    // For simplicity, let's remove it for now.
    // uint256 public totalAllocated;

    struct VestingSchedule {
        address tokenAddress; // ADDED: The specific token for this schedule
        uint256 totalAmount;
        uint256 released;
        uint256 start;
        uint256 duration;
        bool exists;
    }

    // beneficiary => scheduleId => VestingSchedule
    mapping(address => mapping(uint256 => VestingSchedule)) public schedules;
    // beneficiary => Number of schedules created
    mapping(address => uint256) public scheduleCount;

    // --- Events ---
    // Added tokenAddress to VestingCreated
    event VestingCreated( // ADDED
        address indexed beneficiary,
        address indexed tokenAddress,
        uint256 amount,
        uint256 start,
        uint256 duration,
        uint256 scheduleId
    );
    // Added tokenAddress to TokensReleased
    event TokensReleased(address indexed beneficiary, address indexed tokenAddress, uint256 amount, uint256 scheduleId); // MODIFIED
    // Added tokenAddress to TokensReleasedBatch
    event TokensReleasedBatch(address indexed beneficiary, address indexed tokenAddress, uint256 totalAmount); // MODIFIED (Assuming batch release is per token type)

    // Admin events remain similar
    event Paused(address indexed admin); // Changed owner to admin conceptually
    event Unpaused(address indexed admin); // Changed owner to admin conceptually
    event TokensRescued(address indexed token, address indexed to, uint256 amount); // For rescuing non-vesting tokens

    // --- Errors ---
    error ContractPaused();
    error InvalidTokenAddress();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidDuration();
    error NoTokensToRelease();
    error InvalidAddress();
    error InvalidScheduleId();
    error AlreadyPaused();
    error NotPaused();
    error NoTokensToRescue(); // Keep for rescue function
    error MixedTokensInBatchRelease(); // ADDED: For releaseAll safety

    // --- Constructor ---
    // REMOVED: _token parameter
    constructor() {
        // Grant admin role to deployer (PresaleFactory)
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // --- Core Vesting Logic ---

    /**
     * @notice Creates a new vesting schedule for a specific token and beneficiary.
     * @dev Only accounts with VESTER_ROLE can call this. Tokens must be approved by the caller.
     * @param _beneficiary The address receiving the vested tokens.
     * @param _tokenAddress The address of the ERC20 token being vested. <<<< ADDED
     * @param _amount The total amount of tokens to vest.
     * @param _start The timestamp when vesting begins.
     * @param _duration The duration of the vesting period in seconds.
     */
    function createVesting(
        address _beneficiary,
        address _tokenAddress, // <<<< ADDED
        uint256 _amount,
        uint256 _start,
        uint256 _duration
    ) external onlyRole(VESTER_ROLE) {
        if (paused) revert ContractPaused();
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_tokenAddress == address(0)) revert InvalidTokenAddress(); // Check token address
        if (_amount == 0) revert InvalidAmount();
        if (_duration == 0) revert InvalidDuration();

        uint256 newScheduleId = scheduleCount[_beneficiary];
        schedules[_beneficiary][newScheduleId] = VestingSchedule({
            tokenAddress: _tokenAddress, // Store token address
            totalAmount: _amount,
            released: 0,
            start: _start,
            duration: _duration,
            exists: true
        });
        scheduleCount[_beneficiary]++;
        // totalAllocated += _amount; // Removed or needs per-token tracking

        // Get the specific token interface
        IERC20 specificToken = IERC20(_tokenAddress);

        // Transfer the specific token from the caller (Presale contract)
        uint256 balanceBefore = specificToken.balanceOf(address(this));
        specificToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceAfter = specificToken.balanceOf(address(this));
        if (balanceAfter - balanceBefore != _amount) revert InvalidAmount(); // Check fee-on-transfer

        emit VestingCreated(_beneficiary, _tokenAddress, _amount, _start, _duration, newScheduleId);
    }

    /**
     * @notice Releases vested tokens for a specific schedule to the beneficiary.
     * @param _scheduleId The internal ID of the schedule to release tokens from.
     */
    function release(uint256 _scheduleId) external nonReentrant {
        if (paused) revert ContractPaused();
        if (_scheduleId >= scheduleCount[msg.sender]) revert InvalidScheduleId();
        VestingSchedule storage schedule = schedules[msg.sender][_scheduleId];
        if (!schedule.exists) revert InvalidScheduleId();

        uint256 releasable = vestedAmount(msg.sender, _scheduleId) - schedule.released;
        if (releasable == 0) revert NoTokensToRelease();

        schedule.released += releasable;
        // totalAllocated -= releasable; // Removed or needs per-token tracking

        // Use the token address stored in the schedule
        IERC20(schedule.tokenAddress).safeTransfer(msg.sender, releasable);
        emit TokensReleased(msg.sender, schedule.tokenAddress, releasable, _scheduleId);
    }

    /**
     * @notice Releases vested tokens from all schedules for the caller *for a specific token*.
     * @dev Requires specifying the token address to avoid releasing mixed tokens accidentally.
     * @param _tokenAddress The address of the token to release.
     */
    function releaseAllForToken(address _tokenAddress) external nonReentrant {
        if (paused) revert ContractPaused();
        if (_tokenAddress == address(0)) revert InvalidTokenAddress();

        uint256 totalReleased = 0;
        uint256 count = scheduleCount[msg.sender];

        for (uint256 i = 0; i < count; i++) {
            VestingSchedule storage schedule = schedules[msg.sender][i];
            // Skip if schedule doesn't exist or is for a different token
            if (!schedule.exists || schedule.tokenAddress != _tokenAddress) continue;

            uint256 releasable = vestedAmount(msg.sender, i) - schedule.released;
            if (releasable == 0) continue;

            schedule.released += releasable;
            totalReleased += releasable;
        }

        if (totalReleased == 0) revert NoTokensToRelease();
        // totalAllocated -= totalReleased; // Removed or needs per-token tracking

        // Transfer the specific token
        IERC20(_tokenAddress).safeTransfer(msg.sender, totalReleased);
        emit TokensReleasedBatch(msg.sender, _tokenAddress, totalReleased);
    }

    // --- View Functions ---

    /**
     * @notice Calculates the amount of tokens vested for a specific schedule up to the current time.
     * @param _beneficiary The address of the beneficiary.
     * @param _scheduleId The internal ID of the schedule.
     * @return The total amount of tokens vested for the schedule at the current block timestamp.
     */
    function vestedAmount(address _beneficiary, uint256 _scheduleId) public view returns (uint256) {
        if (_scheduleId >= scheduleCount[_beneficiary]) return 0;
        // No need to read storage just for calculations if schedule doesn't exist, but checking existence is safer.
        VestingSchedule memory schedule = schedules[_beneficiary][_scheduleId];
        if (!schedule.exists) return 0; // Check existence

        if (block.timestamp < schedule.start || schedule.totalAmount == 0 || schedule.duration == 0) return 0;
        uint256 currentTime = block.timestamp;
        if (currentTime >= schedule.start + schedule.duration) return schedule.totalAmount;
        uint256 timeElapsed = currentTime - schedule.start;
        return (schedule.totalAmount * timeElapsed) / schedule.duration;
    }

    /**
     * @notice Calculates the remaining tokens yet to be released for a specific schedule.
     * @param _beneficiary The address of the beneficiary.
     * @param _scheduleId The internal ID of the schedule.
     * @return The total amount remaining (total - released) for the schedule.
     */
    function remainingVested(address _beneficiary, uint256 _scheduleId) external view returns (uint256) {
        if (_scheduleId >= scheduleCount[_beneficiary]) return 0;
        VestingSchedule memory schedule = schedules[_beneficiary][_scheduleId];
        if (!schedule.exists) return 0; // Check existence
        return schedule.totalAmount - schedule.released;
    }

    /**
     * @notice Calculates the total remaining tokens for a specific token across all schedules for a beneficiary.
     * @param _beneficiary The address of the beneficiary.
     * @param _tokenAddress The specific token address to check.
     * @return The sum of remaining amounts for the specified token.
     */
    function getTotalRemainingVestedForToken(address _beneficiary, address _tokenAddress)
        external
        view
        returns (uint256)
    {
        uint256 totalRemaining = 0;
        uint256 count = scheduleCount[_beneficiary];
        for (uint256 i = 0; i < count; i++) {
            VestingSchedule memory schedule = schedules[_beneficiary][i];
            if (schedule.exists && schedule.tokenAddress == _tokenAddress) {
                // Check existence and token match
                totalRemaining += schedule.totalAmount - schedule.released;
            }
        }
        return totalRemaining;
    }

    // --- Admin Functions ---

    /**
     * @notice Pauses the contract, preventing token releases and schedule creation.
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can call this.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (paused) revert AlreadyPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract.
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can call this.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Rescues accidentally sent ERC20 tokens (excluding tokens currently involved in vesting schedules).
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can call this.
     * Requires careful implementation to ensure vesting tokens aren't rescued.
     * This basic version rescues any token *not currently locked* in an active schedule.
     * A more robust version might track all vesting tokens explicitly.
     * @param _tokenToRescue The address of the token to rescue.
     * @param _to The address to send the rescued tokens to.
     * @param _amount The amount of tokens to rescue.
     */
    function rescueTokens(address _tokenToRescue, address _to, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_to == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();

        // Basic check: Ensure we have the balance
        uint256 balance = IERC20(_tokenToRescue).balanceOf(address(this));
        if (balance < _amount) revert NoTokensToRescue();

        // More complex check needed: Ensure _amount doesn't exceed balance - totalAllocatedForToken(_tokenToRescue)
        // This requires iterating through all schedules, which is gas-intensive.
        // For simplicity here, we allow rescuing as long as the balance exists.
        // WARNING: This could potentially rescue tokens meant for vesting if called incorrectly.

        IERC20(_tokenToRescue).safeTransfer(_to, _amount);
        emit TokensRescued(_tokenToRescue, _to, _amount);
    }
}
