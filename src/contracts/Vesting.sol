// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Vesting Contract
/// @notice Manages linear vesting schedules for beneficiaries.
/// @dev Schedules are indexed uniquely per beneficiary using an internal counter.
contract Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token; // Token to vest
    bool public paused;
    uint256 public totalAllocated; // Total tokens allocated across all schedules

    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to vest
        uint256 released; // Tokens already released
        uint256 start; // Vesting start time
        uint256 duration; // Vesting duration
        bool exists; // Flag to indicate if the slot is used
    }

    // beneficiary => scheduleId (internal index) => VestingSchedule
    mapping(address => mapping(uint256 => VestingSchedule)) public schedules;
    // beneficiary => Number of schedules created for this beneficiary (also next available ID)
    mapping(address => uint256) public scheduleCount;

    /// @dev Emitted when a new vesting schedule is created.
    /// @param beneficiary The address of the recipient.
    /// @param amount The total vested amount.
    /// @param start The vesting start time.
    /// @param duration The vesting duration.
    /// @param scheduleId The unique ID assigned to this schedule for the beneficiary.
    event VestingCreated(
        address indexed beneficiary, uint256 amount, uint256 start, uint256 duration, uint256 scheduleId
    );
    /// @dev Emitted when tokens are released from a specific schedule.
    /// @param beneficiary The address receiving tokens.
    /// @param amount The amount of tokens released.
    /// @param scheduleId The ID of the schedule.
    event TokensReleased(address indexed beneficiary, uint256 amount, uint256 scheduleId);
    /// @dev Emitted when tokens are released from multiple schedules.
    /// @param beneficiary The address receiving tokens.
    /// @param totalAmount The total amount of tokens released.
    event TokensReleasedBatch(address indexed beneficiary, uint256 totalAmount);
    /// @dev Emitted when a vesting schedule is deleted.
    /// @param beneficiary The address of the beneficiary.
    /// @param scheduleId The ID of the deleted schedule.
    /// @param returnedAmount The amount of tokens returned to the owner.
    event VestingDeleted(address indexed beneficiary, uint256 scheduleId, uint256 returnedAmount);
    /// @dev Emitted when the contract is paused.
    /// @param owner The address of the owner.
    event Paused(address indexed owner);
    /// @dev Emitted when the contract is unpaused.
    /// @param owner The address of the owner.
    event Unpaused(address indexed owner);
    /// @dev Emitted when tokens are rescued.
    /// @param token The address of the rescued token.
    /// @param to The recipient address.
    /// @param amount The rescued amount.
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // Custom Errors
    error ContractPaused();
    error InvalidTokenAddress();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidDuration();
    error NoTokensToRelease();
    error InvalidAddress();
    error CannotRescueVestingToken();
    error InvalidScheduleId();
    error AlreadyPaused();
    error NotPaused();
    error NoTokensToRescue();

    /// @notice Initializes the Vesting contract.
    /// @param _token The address of the ERC20 token to be vested.
    constructor(address _token) Ownable(msg.sender) {
        if (_token == address(0)) revert InvalidTokenAddress();
        token = IERC20(_token);
    }

    /// @notice Creates a new vesting schedule for a beneficiary.
    /// @dev Only the owner can call this function. Tokens must be approved for transfer to this contract.
    /// The scheduleId is automatically assigned based on the beneficiary's schedule count.
    /// Reverts if the contract is paused or if the transferred amount doesn't match due to fee-on-transfer tokens.
    /// @param _beneficiary The address receiving the vested tokens.
    /// @param _amount The total amount of tokens to vest.
    /// @param _start The timestamp when vesting begins.
    /// @param _duration The duration of the vesting period in seconds.
    function createVesting(address _beneficiary, uint256 _amount, uint256 _start, uint256 _duration)
        external
        onlyOwner
    {
        if (paused) revert ContractPaused();
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_amount == 0) revert InvalidAmount();
        if (_duration == 0) revert InvalidDuration();

        uint256 newScheduleId = scheduleCount[_beneficiary];
        schedules[_beneficiary][newScheduleId] =
            VestingSchedule({totalAmount: _amount, released: 0, start: _start, duration: _duration, exists: true});
        scheduleCount[_beneficiary]++;
        totalAllocated += _amount;

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter - balanceBefore != _amount) revert InvalidAmount();

        emit VestingCreated(_beneficiary, _amount, _start, _duration, newScheduleId);
    }

    /// @notice Releases vested tokens for a specific schedule to the beneficiary.
    /// @dev Can be called by the beneficiary. Uses ReentrancyGuard to prevent reentrant calls.
    /// @param _scheduleId The internal ID of the schedule to release tokens from.
    function release(uint256 _scheduleId) external nonReentrant {
        if (paused) revert ContractPaused();
        if (_scheduleId >= scheduleCount[msg.sender]) revert InvalidScheduleId();
        VestingSchedule storage schedule = schedules[msg.sender][_scheduleId];
        if (!schedule.exists) revert InvalidScheduleId();

        uint256 releasable = vestedAmount(msg.sender, _scheduleId) - schedule.released;
        if (releasable == 0) revert NoTokensToRelease();

        schedule.released += releasable;
        totalAllocated -= releasable;
        token.safeTransfer(msg.sender, releasable);
        emit TokensReleased(msg.sender, releasable, _scheduleId);
    }

    /// @notice Releases vested tokens from all schedules for the caller.
    /// @dev Can be called by the beneficiary. Uses ReentrancyGuard to prevent reentrant calls.
    function releaseAll() external nonReentrant {
        if (paused) revert ContractPaused();
        uint256 totalReleased = 0;
        uint256 count = scheduleCount[msg.sender];
        for (uint256 i = 0; i < count; i++) {
            VestingSchedule storage schedule = schedules[msg.sender][i];
            if (!schedule.exists) continue;
            uint256 releasable = vestedAmount(msg.sender, i) - schedule.released;
            if (releasable == 0) continue;
            schedule.released += releasable;
            totalReleased += releasable;
        }
        if (totalReleased == 0) revert NoTokensToRelease();
        totalAllocated -= totalReleased;
        token.safeTransfer(msg.sender, totalReleased);
        emit TokensReleasedBatch(msg.sender, totalReleased);
    }

    /// @notice Deletes a vesting schedule and returns remaining tokens to the owner.
    /// @dev Only the owner can call this. Returns unvested tokens to the owner.
    /// @param _beneficiary The address of the beneficiary.
    /// @param _scheduleId The ID of the schedule to delete.
    function deleteVesting(address _beneficiary, uint256 _scheduleId) external onlyOwner nonReentrant {
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_scheduleId >= scheduleCount[_beneficiary]) revert InvalidScheduleId();
        VestingSchedule storage schedule = schedules[_beneficiary][_scheduleId];
        if (!schedule.exists) revert InvalidScheduleId();
        uint256 remaining = schedule.totalAmount - schedule.released;
        if (remaining > 0) {
            totalAllocated -= remaining;
            token.safeTransfer(owner(), remaining);
        }
        delete schedules[_beneficiary][_scheduleId];
        emit VestingDeleted(_beneficiary, _scheduleId, remaining);
    }

    /// @notice Calculates the amount of tokens vested for a specific schedule up to the current time.
    /// @dev View function. Uses integer division, resulting in tokens vesting in chunks.
    /// @param _beneficiary The address of the beneficiary.
    /// @param _scheduleId The internal ID of the schedule.
    /// @return The total amount of tokens vested for the schedule at the current block timestamp.
    function vestedAmount(address _beneficiary, uint256 _scheduleId) public view returns (uint256) {
        if (_scheduleId >= scheduleCount[_beneficiary]) return 0;
        VestingSchedule memory schedule = schedules[_beneficiary][_scheduleId];
        if (block.timestamp < schedule.start || schedule.totalAmount == 0 || schedule.duration == 0) return 0;
        uint256 currentTime = block.timestamp;
        if (currentTime >= schedule.start + schedule.duration) return schedule.totalAmount;
        uint256 timeElapsed = currentTime - schedule.start;
        return (schedule.totalAmount * timeElapsed) / schedule.duration;
    }

    /// @notice Calculates the remaining tokens yet to be released for a specific schedule.
    /// @dev View function.
    /// @param _beneficiary The address of the beneficiary.
    /// @param _scheduleId The internal ID of the schedule.
    /// @return The total amount remaining (total - released) for the schedule.
    function remainingVested(address _beneficiary, uint256 _scheduleId) external view returns (uint256) {
        if (_scheduleId >= scheduleCount[_beneficiary]) return 0;
        VestingSchedule memory schedule = schedules[_beneficiary][_scheduleId];
        return schedule.totalAmount - schedule.released;
    }

    /// @notice Calculates the total remaining tokens yet to be released across all schedules for a beneficiary.
    /// @dev View function. Iterates through all schedules for the beneficiary.
    /// @param _beneficiary The address of the beneficiary.
    /// @return The sum of remaining amounts across all schedules.
    function getTotalRemainingVested(address _beneficiary) external view returns (uint256) {
        uint256 totalRemaining = 0;
        uint256 count = scheduleCount[_beneficiary];
        for (uint256 i = 0; i < count; i++) {
            VestingSchedule memory schedule = schedules[_beneficiary][i];
            if (schedule.exists) {
                totalRemaining += schedule.totalAmount - schedule.released;
            }
        }
        return totalRemaining;
    }

    /// @notice Pauses the contract, preventing token releases and schedule creation.
    /// @dev Only the owner can call this. Reverts if already paused.
    function pause() external onlyOwner {
        if (paused) revert AlreadyPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpauses the contract, allowing token releases and schedule creation.
    /// @dev Only the owner can call this. Reverts if not paused.
    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Rescues stuck tokens, excluding the vesting token.
    /// @dev Only the owner can call this. Prevents rescuing the main vesting token.
    /// @param _token The address of the token to rescue.
    /// @param _to The address to send the rescued tokens to.
    /// @param _amount The amount of tokens to rescue.
    function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();
        if (_token == address(token)) revert CannotRescueVestingToken();
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRescued(_token, _to, _amount);
    }

    /// @notice Rescues unallocated vesting tokens.
    /// @dev Only the owner can call this. Ensures only unallocated tokens are rescued.
    /// @param _to The address to send the rescued tokens to.
    /// @param _amount The amount of tokens to rescue.
    function rescueUnallocatedVestingTokens(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert InvalidAddress();
        uint256 balance = token.balanceOf(address(this));
        if (balance <= totalAllocated) revert NoTokensToRelease();
        uint256 available = balance - totalAllocated;
        if (_amount > available) revert InvalidAmount();
        if (_amount == 0) revert InvalidAmount();
        token.safeTransfer(_to, _amount);
        emit TokensRescued(address(token), _to, _amount);
    }
}
