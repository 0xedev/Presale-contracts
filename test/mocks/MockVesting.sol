// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface matching the relevant parts of the actual Vesting contract
interface IVesting {
    event VestingCreated(
        address indexed beneficiary,
        address indexed tokenAddress,
        uint256 amount,
        uint256 start,
        uint256 duration,
        uint256 scheduleId
    );
    event TokensReleased(address indexed beneficiary, address indexed tokenAddress, uint256 amount, uint256 scheduleId);
    event TokensReleasedBatch(address indexed beneficiary, address indexed tokenAddress, uint256 totalAmount);
    event Paused(address indexed admin);
    event Unpaused(address indexed admin);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function createVesting(
        address _beneficiary,
        address _tokenAddress,
        uint256 _amount,
        uint256 _start,
        uint256 _duration
    ) external;

    function release(uint256 _scheduleId) external;
    function releaseAllForToken(address _tokenAddress) external;
    function vestedAmount(address _beneficiary, uint256 _scheduleId) external view returns (uint256);
    function pause() external;
    function unpause() external;
    function rescueTokens(address _tokenToRescue, address _to, uint256 _amount) external;
    function scheduleCount(address _beneficiary) external view returns (uint256);
    // Add other view functions if needed by tests
}

/**
 * @title Mock Vesting Contract
 * @notice Minimal mock for testing Presale interactions.
 * @dev Implements the IVesting interface. Relies on vm.expectCall in tests.
 */
contract MockVesting is IVesting, AccessControl {
    // Keep VESTER_ROLE consistent if PresaleFactory grants it during setup
    bytes32 public constant VESTER_ROLE = keccak256("VESTER_ROLE");

    // Optional: Track calls
    struct VestingCall {
        address beneficiary;
        address tokenAddress;
        uint256 amount;
        uint256 start;
        uint256 duration;
        address caller; // msg.sender who called createVesting
    }
    VestingCall[] public vestingCalls;
    uint256 public nextScheduleId; // Simple counter

    constructor() {
        // Grant admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Optional: Grant VESTER_ROLE immediately if needed, or handle in test setup
        // _grantRole(VESTER_ROLE, address(presaleFactory)); // Example
    }

    /**
     * @notice Mock createVesting function. Primarily verified using vm.expectCall.
     */
    function createVesting(
        address _beneficiary,
        address _tokenAddress,
        uint256 _amount,
        uint256 _start,
        uint256 _duration
    )
        external
        // onlyRole(VESTER_ROLE) // Can omit role check in mock
    {
        // Optional: Record call details
        vestingCalls.push(VestingCall({
            beneficiary: _beneficiary,
            tokenAddress: _tokenAddress,
            amount: _amount,
            start: _start,
            duration: _duration,
            caller: msg.sender
        }));

        // Emit event to satisfy test expectations
        emit VestingCreated(_beneficiary, _tokenAddress, _amount, _start, _duration, nextScheduleId);
        nextScheduleId++; // Increment mock schedule ID

        // No actual token transfer logic needed here - Presale handles the transfer *to* this mock
    }

    // --- Other Mock Functions (Empty/Default Implementation) ---

    function release(uint256 /*_scheduleId*/) external {
        // emit TokensReleased(...);
    }

    function releaseAllForToken(address /*_tokenAddress*/) external {
        // emit TokensReleasedBatch(...);
    }

    function vestedAmount(address /*_beneficiary*/, uint256 /*_scheduleId*/) external pure returns (uint256) {
        return 0; // Return 0 or a mock value if needed
    }

    function pause() external {
        // emit Paused(msg.sender);
    }

    function unpause() external {
        // emit Unpaused(msg.sender);
    }

    function rescueTokens(address /*_tokenToRescue*/, address /*_to*/, uint256 /*_amount*/) external {
        // emit TokensRescued(...);
    }

     function scheduleCount(address /*_beneficiary*/) external view returns (uint256) {
        return nextScheduleId; // Return the number of times createVesting was called
    }
}
