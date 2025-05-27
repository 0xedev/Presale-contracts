// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Vesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VESTER_ROLE = keccak256("VESTER_ROLE");

    bool public paused;

    struct VestingSchedule {
        address tokenAddress;
        uint256 totalAmount;
        uint256 released;
        uint256 start;
        uint256 duration;
        bool exists;
    }

    // presale => beneficiary => VestingSchedule
    mapping(address => mapping(address => VestingSchedule)) public schedules;

    event VestingCreated(
        address indexed presale,
        address indexed beneficiary,
        address indexed tokenAddress,
        uint256 amount,
        uint256 start,
        uint256 duration
    );
    event TokensReleased(
        address indexed presale, address indexed beneficiary, address indexed tokenAddress, uint256 amount
    );
    event TokensReleasedBatch(
        address indexed presale, address indexed beneficiary, address indexed tokenAddress, uint256 totalAmount
    );
    event Paused(address indexed admin);
    event Unpaused(address indexed admin);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    error ContractPaused();
    error InvalidTokenAddress();
    error InvalidBeneficiary();
    error InvalidPresale();
    error InvalidAmount();
    error InvalidDuration();
    error NoTokensToRelease();
    // error InvalidAddress();
    // error NoTokensToRescue();
    error AlreadyPaused();
    error NotPaused();

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createVesting(
        address _presale,
        address _beneficiary,
        address _tokenAddress,
        uint256 _amount,
        uint256 _start,
        uint256 _duration
    ) external onlyRole(VESTER_ROLE) {
        if (paused) revert ContractPaused();
        if (_presale == address(0)) revert InvalidPresale();
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_tokenAddress == address(0)) revert InvalidTokenAddress();
        if (_amount == 0) revert InvalidAmount();
        if (_duration == 0) revert InvalidDuration();

        VestingSchedule storage schedule = schedules[_presale][_beneficiary];
        if (schedule.exists) {
            schedule.totalAmount += _amount;
        } else {
            schedule.tokenAddress = _tokenAddress;
            schedule.totalAmount = _amount;
            schedule.released = 0;
            schedule.start = _start;
            schedule.duration = _duration;
            schedule.exists = true;
        }

        IERC20 specificToken = IERC20(_tokenAddress);
        uint256 balanceBefore = specificToken.balanceOf(address(this));
        specificToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceAfter = specificToken.balanceOf(address(this));
        if (balanceAfter - balanceBefore != _amount) revert InvalidAmount();

        emit VestingCreated(_presale, _beneficiary, _tokenAddress, _amount, _start, _duration);
    }

    function release(address _presale) external nonReentrant {
        if (paused) revert ContractPaused();
        VestingSchedule storage schedule = schedules[_presale][msg.sender];
        if (!schedule.exists) revert NoTokensToRelease();

        uint256 currentVested = vestedAmount(_presale, msg.sender);
        uint256 releasable = currentVested - schedule.released;
        console.log("--- Vesting Release ---");
        console.log("Timestamp:", block.timestamp);
        console.log("Presale:", _presale);
        console.log("Beneficiary:", msg.sender);
        console.log("Total Vested So Far:", currentVested);
        console.log("Already Released:", schedule.released);
        console.log("Calculated Releasable (Delta):", releasable);

        if (releasable == 0) revert NoTokensToRelease();

        schedule.released += releasable;
        console.log("Transferring Amount:", releasable);
        IERC20(schedule.tokenAddress).safeTransfer(msg.sender, releasable);
        emit TokensReleased(_presale, msg.sender, schedule.tokenAddress, releasable);
    }

    function vestedAmount(address _presale, address _beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = schedules[_presale][_beneficiary];
        if (!schedule.exists) return 0;
        if (block.timestamp < schedule.start || schedule.totalAmount == 0 || schedule.duration == 0) return 0;
        uint256 currentTime = block.timestamp;
        if (currentTime >= schedule.start + schedule.duration) return schedule.totalAmount;
        uint256 timeElapsed = currentTime - schedule.start;
        return (schedule.totalAmount * timeElapsed) / schedule.duration;
    }

    function remainingVested(address _presale, address _beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = schedules[_presale][_beneficiary];
        if (!schedule.exists) return 0;
        return schedule.totalAmount - schedule.released;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (paused) revert AlreadyPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }
}
