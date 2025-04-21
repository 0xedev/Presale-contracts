// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Vesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token; // Token to vest
    bool public paused;

    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to vest
        uint256 released; // Tokens already released
        uint256 start; // Vesting start time
        uint256 duration; // Vesting duration
    }

    mapping(address => mapping(uint256 => VestingSchedule)) public schedules; // beneficiary => scheduleId => VestingSchedule
    mapping(address => uint256) public scheduleCount; // Tracks number of schedules per beneficiary

    event VestingCreated(address indexed beneficiary, uint256 amount, uint256 start, uint256 duration, uint256 scheduleId);
    event TokensReleased(address indexed beneficiary, uint256 amount, uint256 scheduleId);
    event Paused(address indexed owner);
    event Unpaused(address indexed owner);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    error ContractPaused();
    error InvalidTokenAddress();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidDuration();
    error ScheduleExists();
    error NoTokensToRelease();
    error InvalidAddress();

    constructor(address _token) Ownable(msg.sender) {
        if (_token == address(0)) revert InvalidTokenAddress();
        token = IERC20(_token);
    }

    function createVesting(
        address _beneficiary,
        uint256 _amount,
        uint256 _start,
        uint256 _duration,
        uint256 _scheduleId
    ) external onlyOwner {
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_amount == 0) revert InvalidAmount();
        if (_duration == 0) revert InvalidDuration();
        if (schedules[_beneficiary][_scheduleId].totalAmount != 0) revert ScheduleExists();

        schedules[_beneficiary][_scheduleId] = VestingSchedule({
            totalAmount: _amount,
            released: 0,
            start: _start,
            duration: _duration
        });
        scheduleCount[_beneficiary]++;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit VestingCreated(_beneficiary, _amount, _start, _duration, _scheduleId);
    }

    function release(uint256 _scheduleId) external nonReentrant {
        if (paused) revert ContractPaused();
        VestingSchedule storage schedule = schedules[msg.sender][_scheduleId];
        uint256 releasable = vestedAmount(msg.sender, _scheduleId) - schedule.released;
        if (releasable == 0) revert NoTokensToRelease();

        schedule.released += releasable;
        token.safeTransfer(msg.sender, releasable);
        emit TokensReleased(msg.sender, releasable, _scheduleId);
    }

    function vestedAmount(address _beneficiary, uint256 _scheduleId) public view returns (uint256) {
        VestingSchedule memory schedule = schedules[_beneficiary][_scheduleId];
        if (block.timestamp < schedule.start || schedule.totalAmount == 0) return 0;
        uint256 currentTime = block.timestamp;
        if (currentTime >= schedule.start + schedule.duration) return schedule.totalAmount;
        return (schedule.totalAmount * (currentTime - schedule.start)) / schedule.duration;
    }

    function remainingVested(address _beneficiary, uint256 _scheduleId) external view returns (uint256) {
        VestingSchedule memory schedule = schedules[_beneficiary][_scheduleId];
        return schedule.totalAmount - schedule.released;
    }

    function getTotalRemainingVested(address _beneficiary) external view returns (uint256) {
        uint256 totalRemaining = 0;
        uint256 count = scheduleCount[_beneficiary];
        for (uint256 i = 0; i < count; i++) {
            VestingSchedule memory schedule = schedules[_beneficiary][i];
            totalRemaining += schedule.totalAmount - schedule.released;
        }
        return totalRemaining;
    }

    function pause() external onlyOwner {
        if (paused) revert ContractPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!paused) revert ContractPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert InvalidAddress();
        if (_token == address(token)) revert InvalidTokenAddress(); // Prevent rescuing vesting token
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRescued(_token, _to, _amount);
    }
}