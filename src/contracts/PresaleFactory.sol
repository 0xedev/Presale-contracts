// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Presale} from "./Presale.sol";
import {LiquidityLocker} from "./LiquidityLocker.sol";
import {Vesting} from "./Vesting.sol";

//remove Add a pause function to halt presale creation.

contract PresaleFactory is Ownable {
    LiquidityLocker public liquidityLocker;
    Vesting public vestingContract;

    using SafeERC20 for IERC20;
    using Address for address payable;

    mapping(address => bool) public whitelistedCreators;
    uint256 public creationFee;
    address public feeToken;
    address[] public presales;
    uint256 public housePercentage; // Platform fee (0-500 BPS)
    address public houseAddress; // Address to receive platform fee

    error InsufficientFee();
    error ZeroFee();
    error InvalidHousePercentage();
    error InvalidHouseAddress();

    event PresaleCreated(address indexed creator, address indexed presale, address token, uint256 start, uint256 end);
    event HousePercentageUpdated(uint256 percentage);
    event HouseAddressUpdated(address houseAddress);

    constructor(
        uint256 _creationFee,
        address _feeToken,
        address _token,
        uint256 _housePercentage,
        address _houseAddress
    ) Ownable(msg.sender) {
        if (_housePercentage > 500) revert InvalidHousePercentage();
        if (_houseAddress == address(0) && _housePercentage > 0) revert InvalidHouseAddress();
        creationFee = _creationFee;
        feeToken = _feeToken;
        housePercentage = _housePercentage;
        houseAddress = _houseAddress;
        liquidityLocker = new LiquidityLocker();
        vestingContract = new Vesting(_token);
        liquidityLocker.transferOwnership(address(this));
        vestingContract.transferOwnership(address(this));
    }

    function createPresale(Presale.PresaleOptions memory _options, address _token, address _weth, address _router)
        external
        payable
        returns (address)
    {
        if (feeToken == address(0)) {
            if (msg.value < creationFee) revert InsufficientFee();
        } else {
            IERC20(feeToken).safeTransferFrom(msg.sender, address(this), creationFee);
        }

        Presale presale = new Presale(
            _weth,
            _token,
            _router,
            _options,
            msg.sender,
            address(liquidityLocker),
            address(vestingContract),
            housePercentage,
            houseAddress
        );
        presales.push(address(presale));
        emit PresaleCreated(msg.sender, address(presale), _token, _options.start, _options.end);

        return address(presale);
    }
    //remove setHousePercentage, pause

    function setHousePercentage(uint256 _percentage) external onlyOwner {
        if (_percentage > 500) revert InvalidHousePercentage();
        if (_percentage > 0 && houseAddress == address(0)) revert InvalidHouseAddress();
        housePercentage = _percentage;
        emit HousePercentageUpdated(_percentage);
    }

    function setHouseAddress(address _houseAddress) external onlyOwner {
        if (_houseAddress == address(0) && housePercentage > 0) revert InvalidHouseAddress();
        houseAddress = _houseAddress;
        emit HouseAddressUpdated(_houseAddress);
    }

    function setCreationFee(uint256 _fee) external onlyOwner {
        if (_fee == 0) revert ZeroFee();
        creationFee = _fee;
    }

    function withdrawFees() external onlyOwner {
        if (feeToken == address(0)) {
            uint256 balance = address(this).balance;
            if (balance > 0) {
                payable(owner()).sendValue(balance);
            }
        } else {
            uint256 balance = IERC20(feeToken).balanceOf(address(this));
            if (balance > 0) {
                IERC20(feeToken).safeTransfer(owner(), balance);
            }
        }
    }

    function getPresaleCount() external view returns (uint256) {
        return presales.length;
    }

    function getPresales() external view returns (address[] memory) {
        return presales;
    }
}
