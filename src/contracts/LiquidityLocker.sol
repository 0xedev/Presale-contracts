// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidityLocker is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant LOCKER_ROLE = keccak256("LOCKER_ROLE");

    struct Lock {
        address token;
        uint256 amount;
        uint256 unlockTime;
        address owner;
    }

    Lock[] public locks;
    mapping(address => uint256[]) public userLocks;

  event LiquidityLocked(uint256 indexed lockId, address indexed token, uint256 amount, uint256 unlockTime, address indexed owner);
event LiquidityWithdrawn(uint256 indexed lockId, address indexed token, uint256 amount, address indexed owner);


    error InvalidTokenAddress();
    error ZeroAmount();
    error InvalidUnlockTime();
    error InvalidOwnerAddress();
    error InvalidLockId();
    error NotLockOwner();
    error TokensStillLocked();
    error NoTokensToWithdraw();

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // PresaleFactory is admin
    }

    function lock(address _token, uint256 _amount, uint256 _unlockTime, address _owner)
        external
        onlyRole(LOCKER_ROLE)
    {
        if (_token == address(0)) revert InvalidTokenAddress();
        if (_amount == 0) revert ZeroAmount();
        if (_unlockTime <= block.timestamp) revert InvalidUnlockTime();
        if (_owner == address(0)) revert InvalidOwnerAddress();

        uint256 lockId = locks.length;

        userLocks[_owner].push(lockId);
        locks.push(Lock({token: _token, amount: _amount, unlockTime: _unlockTime, owner: _owner}));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit LiquidityLocked(lockId, _token, _amount, _unlockTime, _owner);
    }

    // Rest of the contract remains unchanged
    function withdraw(uint256 _lockId) external  nonReentrant{
        if (_lockId >= locks.length) revert InvalidLockId();
        Lock storage lockData = locks[_lockId];
        if (msg.sender != lockData.owner) revert NotLockOwner();
        if (block.timestamp < lockData.unlockTime) revert TokensStillLocked();
        if (lockData.amount == 0) revert NoTokensToWithdraw();

        uint256 amount = lockData.amount;
        address token = lockData.token;
        lockData.amount = 0;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit LiquidityWithdrawn(_lockId, token, amount, msg.sender);
    }

    function getLock(uint256 _lockId) external view returns (address, uint256, uint256, address) {
        if (_lockId >= locks.length) revert InvalidLockId();
        Lock memory lockInfo = locks[_lockId];
        return (lockInfo.token, lockInfo.amount, lockInfo.unlockTime, lockInfo.owner);
    }

    function lockCount() external view returns (uint256) {
        return locks.length;
    }

    function getUserLocks(address _user) external view returns (uint256[] memory) {
        return userLocks[_user];
    }

    function getUserLockDetails(address _user) external view returns (Lock[] memory) {
        uint256[] memory userLockIds = userLocks[_user];
        Lock[] memory userLockDetails = new Lock[](userLockIds.length);

        for (uint256 i = 0; i < userLockIds.length; i++) {
            userLockDetails[i] = locks[userLockIds[i]];
        }

        return userLockDetails;
    }

    function getLocksPaginated(uint256 _offset, uint256 _limit) external view returns (Lock[] memory) {
        require(_offset < locks.length, "Offset out of bounds");

        uint256 end = _offset + _limit;
        if (end > locks.length) {
            end = locks.length;
        }

        Lock[] memory result = new Lock[](end - _offset);
        for (uint256 i = _offset; i < end; i++) {
            result[i - _offset] = locks[i];
        }

        return result;
    }
}
