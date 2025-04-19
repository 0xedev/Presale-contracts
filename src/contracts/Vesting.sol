// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to vest
        uint256 released; // Tokens already released
        uint256 start; // Vesting start time
        uint256 duration; // Vesting duration
    }

    IERC20 public immutable token; // Token to vest
    mapping(address => VestingSchedule) public schedules; // Contributor -> VestingSchedule

    event VestingCreated(address indexed beneficiary, uint256 amount, uint256 start, uint256 duration);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    // Called by the presale contract to create a vesting schedule
    function createVesting(address _beneficiary, uint256 _amount, uint256 _start, uint256 _duration)
        external
        onlyOwner
    {
        require(_beneficiary != address(0), "Invalid beneficiary");
        require(_amount > 0, "Amount must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(schedules[_beneficiary].totalAmount == 0, "Vesting already exists");

        schedules[_beneficiary] =
            VestingSchedule({totalAmount: _amount, released: 0, start: _start, duration: _duration});

        token.safeTransferFrom(msg.sender, address(this), _amount);
        emit VestingCreated(_beneficiary, _amount, _start, _duration);
    }

    // Allows contributors to release vested tokens
    function release() external {
        VestingSchedule storage schedule = schedules[msg.sender];
        uint256 releasable = vestedAmount(msg.sender) - schedule.released;
        require(releasable > 0, "No tokens to release");

        schedule.released += releasable;
        token.safeTransfer(msg.sender, releasable);
        emit TokensReleased(msg.sender, releasable);
    }

    // Calculates the vested amount for a beneficiary
    function vestedAmount(address _beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = schedules[_beneficiary];
        if (block.timestamp < schedule.start || schedule.totalAmount == 0) {
            return 0;
        }
        if (block.timestamp >= schedule.start + schedule.duration) {
            return schedule.totalAmount;
        }
        return (schedule.totalAmount * (block.timestamp - schedule.start)) / schedule.duration;
    }

    // View function to check remaining vested tokens
    function remainingVested(address _beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = schedules[_beneficiary];
        return schedule.totalAmount - schedule.released;
    }
}
