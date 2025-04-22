//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IPresale} from "./interfaces/IPresale.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LiquidityLocker} from "./LiquidityLocker.sol";
import {Vesting} from "./Vesting.sol";

contract Presale is IPresale, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;
    using Address for address payable;

    uint256 public totalRefundable;
    uint256 public constant BASIS_POINTS = 10_000;
    bool public paused;
    bool public whitelistEnabled;
    uint256 public claimDeadline;
    uint256 public ownerBalance;

    LiquidityLocker public immutable liquidityLocker;
    Vesting public immutable vestingContract;
    uint256 public immutable housePercentage; // Set by factory
    address public immutable houseAddress; // Set by factory

    struct PresaleOptions {
        uint256 tokenDeposit;
        uint256 hardCap;
        uint256 softCap;
        uint256 max;
        uint256 min;
        uint256 start;
        uint256 end;
        uint256 liquidityBps;
        uint256 slippageBps;
        uint256 presaleRate;
        uint256 listingRate;
        uint256 lockupDuration;
        address currency;
        uint256 vestingPercentage;
        uint256 vestingDuration;
        uint8 leftoverTokenOption; // 0 = return, 1 = burn, 2 = vest
    }

    enum PresaleState {
        Pending,
        Active,
        Canceled,
        Finalized
    }

    PresaleState public state;

    struct Pool {
        ERC20 token;
        IUniswapV2Router02 uniswapV2Router02;
        address factory;
        uint256 tokenBalance;
        uint256 tokensClaimable;
        uint256 tokensLiquidity;
        uint256 weiRaised;
        address weth;
        uint8 state;
        PresaleOptions options;
    }

    mapping(address => uint256) public totalClaimed;
    mapping(address => uint256) public totalRefunded;
    mapping(address => uint256) public totalContributed;
    mapping(address => uint256) public contributions;
    mapping(address => bool) public whitelist;
    bytes32 public merkleRoot;
    address[] public contributors;
    Pool public pool;

    uint256[] private ALLOWED_LIQUIDITY_BPS = [5000, 6000, 7000, 8000, 9000, 10000];

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyRefundable() {
        if (!(pool.state == 3 || (block.timestamp > pool.options.end && pool.weiRaised < pool.options.softCap))) {
            revert NotRefundable();
        }
        _;
    }

    constructor(
        address _weth,
        address _token,
        address _uniswapV2Router02,
        PresaleOptions memory _options,
        address _creator,
        address _liquidityLocker,
        address _vestingContract,
        uint256 _housePercentage,
        address _houseAddress
    ) Ownable(_creator) {
        if (
            _weth == address(0) || _token == address(0) || _uniswapV2Router02 == address(0)
                || _liquidityLocker == address(0) || _vestingContract == address(0)
        ) {
            revert InvalidInitialization();
        }
        if (_options.leftoverTokenOption > 2) {
            revert InvalidLeftoverTokenOption();
        }
        if (_housePercentage > 500) revert InvalidHousePercentage();
        if (_houseAddress == address(0) && _housePercentage > 0) {
            revert InvalidHouseAddress();
        }
        _prevalidatePool(_options);

        liquidityLocker = LiquidityLocker(_liquidityLocker);
        vestingContract = Vesting(_vestingContract);
        housePercentage = _housePercentage;
        houseAddress = _houseAddress;
        pool = Pool({
            token: ERC20(_token),
            uniswapV2Router02: IUniswapV2Router02(_uniswapV2Router02),
            factory: IUniswapV2Router02(_uniswapV2Router02).factory(),
            tokenBalance: 0,
            tokensClaimable: 0,
            tokensLiquidity: 0,
            weiRaised: 0,
            weth: _weth,
            state: 1,
            options: _options
        });
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        if (state != PresaleState.Pending) revert InvalidState(uint8(state));
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    function contribute(bytes32[] calldata _merkleProof) external payable whenNotPaused nonReentrant {
        if (whitelistEnabled && !MerkleProof.verify(_merkleProof, merkleRoot, keccak256(abi.encodePacked(msg.sender))))
        {
            revert NotWhitelisted();
        }
        if (pool.options.currency != address(0)) revert ETHNotAccepted();
        if (pool.state != 2) revert NotActive();
        uint256 tokenAmount =
            userTokens(msg.sender) + ((msg.value * pool.options.presaleRate * 10 ** pool.token.decimals()) / 10 ** 18);
        if (tokenAmount == 0) revert ZeroTokensForContribution();
        _purchase(msg.sender, msg.value);
        _trackContribution(msg.sender, msg.value, true);
    }

    receive() external payable whenNotPaused nonReentrant {
        if (pool.options.currency != address(0)) revert ETHNotAccepted();
        if (pool.state != 2) revert NotActive();
        uint256 tokenAmount =
            userTokens(msg.sender) + ((msg.value * pool.options.presaleRate * 10 ** pool.token.decimals()) / 10 ** 18);
        if (tokenAmount == 0) revert ZeroTokensForContribution();
        _purchase(msg.sender, msg.value);
        _trackContribution(msg.sender, msg.value, true);
    }

    // New tracking function
    function _trackContribution(address _contributor, uint256 _amount, bool _isETH) private {
        if (contributions[_contributor] == 0) {
            contributors.push(_contributor); // Add new contributor
        }
        contributions[_contributor] += _amount; // Update contribution amount
        emit Contribution(_contributor, _amount, _isETH); // Emit event
    }

    // View functions for tracking
    function getContributorCount() external view returns (uint256) {
        return contributors.length;
    }

    function getContributors() external view returns (address[] memory) {
        return contributors;
    }

    function getTotalContributed() external view returns (uint256) {
        return pool.weiRaised; // Already tracked in pool.weiRaised
    }

    function getContribution(address _contributor) external view returns (uint256) {
        return contributions[_contributor];
    }

    function contributeStablecoin(uint256 _amount, bytes32[] calldata _merkleProof)
        external
        whenNotPaused
        nonReentrant
    {
        if (whitelistEnabled && !MerkleProof.verify(_merkleProof, merkleRoot, keccak256(abi.encodePacked(msg.sender))))
        {
            revert NotWhitelisted();
        }
        if (pool.options.currency == address(0)) revert StablecoinNotAccepted();
        if (pool.state != 2) revert NotActive();
        IERC20(pool.options.currency).safeTransferFrom(msg.sender, address(this), _amount);
        if (_amount == 0) revert ZeroTokensForContribution();
        _purchase(msg.sender, _amount); // Update _purchase to remove whitelist mapping check
        _trackContribution(msg.sender, _amount, false);
    }

    function deposit() external onlyOwner whenNotPaused returns (uint256) {
        if (pool.state != 1) revert InvalidState(pool.state);
        uint256 amount = pool.options.tokenDeposit;
        pool.token.safeTransferFrom(msg.sender, address(this), amount);
        pool.state = 2;
        pool.tokenBalance = amount;
        pool.tokensClaimable = _tokensForPresale();
        pool.tokensLiquidity = _tokensForLiquidity();
        emit Deposit(msg.sender, amount, block.timestamp);
        return amount;
    }

    function _handleLeftoverTokens() private {
        // Calculate unsold tokens
        if (pool.tokenBalance < pool.tokensClaimable + pool.tokensLiquidity) {
            revert InsufficientTokenBalance();
        }
        uint256 unsoldTokens = pool.tokenBalance - (pool.tokensClaimable + pool.tokensLiquidity);
        if (unsoldTokens > 0) {
            pool.tokenBalance -= unsoldTokens;
            if (pool.options.leftoverTokenOption == 0) {
                // Return to creator
                pool.token.safeTransfer(owner(), unsoldTokens);
                emit LeftoverTokensReturned(unsoldTokens, owner());
            } else if (pool.options.leftoverTokenOption == 1) {
                // Burn by sending to address(0)
                pool.token.safeTransfer(address(0), unsoldTokens);
                emit LeftoverTokensBurned(unsoldTokens);
            } else {
                // Vest for the owner
                pool.token.approve(address(vestingContract), unsoldTokens);
                // In Presale.sol
                vestingContract.createVesting(msg.sender, unsoldTokens, block.timestamp, pool.options.vestingDuration);
                emit LeftoverTokensVested(unsoldTokens, owner());
            }
        }
    }

    function finalize() external onlyOwner whenNotPaused nonReentrant returns (bool) {
        if (pool.state != 2) revert InvalidState(pool.state);
        if (pool.weiRaised < pool.options.softCap) revert SoftCapNotReached();

        pool.state = 4;
        uint256 liquidityAmount = _weiForLiquidity();
        _liquify(liquidityAmount, pool.tokensLiquidity);
        pool.tokenBalance -= pool.tokensLiquidity;

        // Distribute house percentage
        uint256 houseAmount = (pool.weiRaised * housePercentage) / BASIS_POINTS;
        if (houseAmount > 0) {
            if (pool.options.currency == address(0)) {
                payable(houseAddress).sendValue(houseAmount);
            } else {
                IERC20(pool.options.currency).safeTransfer(houseAddress, houseAmount);
            }
            emit HouseFundsDistributed(houseAddress, houseAmount);
        }

        ownerBalance = pool.weiRaised - liquidityAmount - houseAmount;
        claimDeadline = block.timestamp + 180 days;

        // Handle leftover tokens
        _handleLeftoverTokens();

        emit Finalized(msg.sender, pool.weiRaised, block.timestamp);
        return true;
    }

    function cancel() external nonReentrant onlyOwner whenNotPaused returns (bool) {
        if (pool.state > 2) revert InvalidState(pool.state);
        pool.state = 3;
        // Return all deposited tokens to creator
        if (pool.tokenBalance > 0) {
            uint256 amount = pool.tokenBalance;
            pool.tokenBalance = 0;
            pool.token.safeTransfer(msg.sender, amount);
            emit LeftoverTokensReturned(amount, msg.sender);
        }
        emit Cancel(msg.sender, block.timestamp);
        return true;
    }

    function claim() external nonReentrant whenNotPaused returns (uint256) {
        if (pool.state != 4) revert InvalidState(pool.state);
        if (block.timestamp > claimDeadline) revert ClaimPeriodExpired();
        uint256 totalTokens = userTokens(msg.sender);
        if (totalTokens == 0) revert NoTokensToClaim();
        if (pool.tokenBalance < totalTokens) revert InsufficientTokenBalance();

        pool.tokenBalance -= totalTokens;
        contributions[msg.sender] = 0;

        uint256 vestingBps = pool.options.vestingPercentage;
        uint256 vestedTokens = (totalTokens * vestingBps) / BASIS_POINTS;
        uint256 immediateTokens = totalTokens - vestedTokens;

        // Transfer immediate tokens
        if (immediateTokens > 0) {
            pool.token.safeTransfer(msg.sender, immediateTokens);
        }

        // Set up vesting for vested tokens
        if (vestedTokens > 0) {
            pool.token.approve(address(vestingContract), vestedTokens);
            vestingContract.createVesting(msg.sender, vestedTokens, block.timestamp, pool.options.vestingDuration);
        }

        emit TokenClaim(msg.sender, totalTokens, block.timestamp);
        return totalTokens;
    }

    function extendClaimDeadline(uint256 _newDeadline) external onlyOwner {
        if (_newDeadline <= claimDeadline) revert InvalidDeadline();
        claimDeadline = _newDeadline;
        emit ClaimDeadlineExtended(_newDeadline);
    }

    function refund() external nonReentrant onlyRefundable returns (uint256) {
        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoFundsToRefund();
        if (
            pool.options.currency == address(0)
                ? address(this).balance < amount
                : IERC20(pool.options.currency).balanceOf(address(this)) < amount
        ) {
            revert InsufficientContractBalance();
        }
        contributions[msg.sender] = 0;
        totalRefundable -= amount;
        if (pool.options.currency == address(0)) {
            payable(msg.sender).sendValue(amount);
        } else {
            IERC20(pool.options.currency).safeTransfer(msg.sender, amount);
        }
        emit Refund(msg.sender, amount, block.timestamp);
        return amount;
    }

    function withdraw() external onlyOwner {
        uint256 amount = ownerBalance;
        if (amount == 0) revert NoFundsToRefund();
        ownerBalance = 0;
        if (pool.options.currency == address(0)) {
            payable(msg.sender).sendValue(amount);
        } else {
            IERC20(pool.options.currency).safeTransfer(msg.sender, amount);
        }
        emit Withdrawn(msg.sender, amount);
    }

    function rescueTokens(address _token, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert InvalidAddress();
        if (pool.state < 3) revert CannotRescueBeforeFinalization();
        if (_token == address(pool.token) && block.timestamp <= claimDeadline) {
            revert CannotRescuePresaleTokens();
        }
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRescued(_token, _to, _amount);
    }

    //remove  The owner can toggle and update the whitelist at any time, potentially excluding legitimate contributors. Fix: Lock whitelist changes after the presale starts or emit events for transparency.

    function toggleWhitelist(bool _enabled) external onlyOwner {
        if (state != PresaleState.Pending) revert InvalidState(uint8(state));
        whitelistEnabled = _enabled;
        emit WhitelistToggled(_enabled);
    }

    //remove . Consider batch processing or a merkle tree for scalability

    function updateWhitelist(address[] calldata _addresses, bool _add) external onlyOwner {
        if (state != PresaleState.Pending) revert InvalidState(uint8(state));
        uint256 length = _addresses.length;
        if (length > 100) revert BatchTooLarge();
        for (uint256 i = 0; i < length; i++) {
            if (_addresses[i] == address(0)) revert InvalidAddress();
            whitelist[_addresses[i]] = _add;
            emit WhitelistUpdated(_addresses[i], _add);
        }
    }

    function pause() external onlyOwner {
        if (paused) revert AlreadyPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function calculateTotalTokensNeeded() external view returns (uint256) {
        uint256 currencyDecimals = pool.options.currency == address(0) ? 18 : ERC20(pool.options.currency).decimals(); // Fixed to ERC20
        uint256 tokenDecimals = pool.token.decimals();
        uint256 presaleTokens =
            (pool.options.hardCap * pool.options.presaleRate * 10 ** tokenDecimals) / 10 ** currencyDecimals;
        uint256 liquidityTokens = (
            ((pool.options.hardCap * pool.options.liquidityBps) / BASIS_POINTS) * pool.options.listingRate
                * 10 ** tokenDecimals
        ) / 10 ** currencyDecimals;
        return presaleTokens + liquidityTokens;
    }

    function _purchase(address _beneficiary, uint256 _amount) private {
        _prevalidatePurchase(_beneficiary, _amount);
        pool.weiRaised += _amount;
        totalRefundable += _amount;
        contributions[_beneficiary] += _amount;
        emit Purchase(_beneficiary, _amount);
    }

    function _liquify(uint256 _currencyAmount, uint256 _tokenAmount) private {
        uint256 minToken = (_tokenAmount * (BASIS_POINTS - pool.options.slippageBps)) / BASIS_POINTS;
        uint256 minCurrency = (_currencyAmount * (BASIS_POINTS - pool.options.slippageBps)) / BASIS_POINTS;

        pool.token.approve(address(pool.uniswapV2Router02), _tokenAmount); // Fixed with SafeERC20 for ERC20
        address pair = IUniswapV2Factory(pool.factory).getPair(
            address(pool.token), pool.options.currency == address(0) ? pool.weth : pool.options.currency
        );
        if (pair == address(0)) {
            pair = IUniswapV2Factory(pool.factory).createPair(
                address(pool.token), pool.options.currency == address(0) ? pool.weth : pool.options.currency
            );
        }

        if (pool.options.currency == address(0)) {
            pool.uniswapV2Router02.addLiquidityETH{value: _currencyAmount}(
                address(pool.token), _tokenAmount, minToken, minCurrency, address(this), block.timestamp + 600
            );
        } else {
            ERC20(pool.options.currency).approve(address(pool.uniswapV2Router02), _currencyAmount); // Fixed with ERC20
            pool.uniswapV2Router02.addLiquidity(
                address(pool.token),
                pool.options.currency,
                _tokenAmount,
                _currencyAmount,
                minToken,
                minCurrency,
                address(this),
                block.timestamp + 600
            );
            ERC20(pool.options.currency).approve(address(pool.uniswapV2Router02), 0); // Reset approval
        }
        pool.token.approve(address(pool.uniswapV2Router02), 0); // Reset approval

        IERC20 lpToken = IERC20(pair);
        uint256 lpAmount = lpToken.balanceOf(address(this));
        if (lpAmount == 0) revert LiquificationFailed();
        uint256 unlockTime = block.timestamp + pool.options.lockupDuration;

        lpToken.approve(address(liquidityLocker), lpAmount);
        liquidityLocker.lock(pair, lpAmount, unlockTime, owner());
    }

    function _prevalidatePurchase(address _beneficiary, uint256 _amount) private view {
        PresaleOptions memory opts = pool.options;
        if (pool.state != 2) revert InvalidState(pool.state);
        if (_beneficiary == address(0)) revert InvalidContributorAddress();
        if (block.timestamp < opts.start || block.timestamp > opts.end) {
            revert NotInPurchasePeriod();
        }
        if (pool.weiRaised + _amount > opts.hardCap) revert HardCapExceeded();
        if (_amount < opts.min) revert BelowMinimumContribution();
        if (contributions[_beneficiary] + _amount > opts.max) {
            revert ExceedsMaximumContribution();
        }
    }

    function _prevalidatePool(PresaleOptions memory _options) private view {
        if (_options.tokenDeposit == 0) revert InvalidInitialization();
        if (_options.hardCap == 0 || _options.softCap < _options.hardCap / 4) {
            revert InvalidInitialization();
        }
        if (_options.max == 0 || _options.min == 0 || _options.min > _options.max) revert InvalidInitialization();
        if (_options.liquidityBps < 5000 || !isAllowedLiquidityBps(_options.liquidityBps)) revert InvalidLiquidityBps();
        if (_options.slippageBps > 500) revert InvalidInitialization();
        if (_options.presaleRate == 0 || _options.listingRate == 0 || _options.listingRate >= _options.presaleRate) {
            revert InvalidInitialization();
        }
        if (_options.start < block.timestamp || _options.end <= _options.start) {
            revert InvalidInitialization();
        }
        if (_options.lockupDuration == 0) revert InvalidInitialization();
        if (_options.vestingPercentage > BASIS_POINTS) {
            revert InvalidVestingPercentage();
        }
        if (_options.vestingPercentage > 0 && _options.vestingDuration == 0) {
            revert InvalidVestingDuration();
        }
        if (_options.leftoverTokenOption > 2) {
            revert InvalidLeftoverTokenOption();
        }
    }

    function isAllowedLiquidityBps(uint256 _bps) private view returns (bool) {
        for (uint256 i = 0; i < ALLOWED_LIQUIDITY_BPS.length; i++) {
            if (_bps == ALLOWED_LIQUIDITY_BPS[i]) return true;
        }
        return false;
    }

    function userTokens(address _contributor) public view returns (uint256) {
        if (pool.weiRaised == 0) return 0;
        uint256 currencyDecimals = pool.options.currency == address(0) ? 18 : ERC20(pool.options.currency).decimals(); // Fixed to ERC20
        uint256 tokenDecimals = pool.token.decimals();
        return (contributions[_contributor] * pool.options.presaleRate * 10 ** tokenDecimals) / 10 ** currencyDecimals;
    }

    function _tokensForLiquidity() private view returns (uint256) {
        uint256 currencyDecimals = pool.options.currency == address(0) ? 18 : ERC20(pool.options.currency).decimals(); // Fixed to ERC20
        uint256 tokenDecimals = pool.token.decimals();
        return (
            ((pool.options.hardCap * pool.options.liquidityBps) / BASIS_POINTS) * pool.options.listingRate
                * 10 ** tokenDecimals
        ) / 10 ** currencyDecimals;
    }

    function _tokensForPresale() private view returns (uint256) {
        uint256 currencyDecimals = pool.options.currency == address(0) ? 18 : ERC20(pool.options.currency).decimals(); // Fixed to ERC20
        uint256 tokenDecimals = pool.token.decimals();
        return (pool.options.hardCap * pool.options.presaleRate * 10 ** tokenDecimals) / 10 ** currencyDecimals;
    }

    function _weiForLiquidity() private view returns (uint256) {
        return (pool.weiRaised * pool.options.liquidityBps) / BASIS_POINTS;
    }

    function retryLiquify(uint256 _currencyAmount, uint256 _tokenAmount) external onlyOwner {
        if (pool.state != 4) revert InvalidState(pool.state);
        if (_currencyAmount > pool.weiRaised || _tokenAmount > pool.tokenBalance) {
            revert InvalidLiquidityAmounts();
        }
        _liquify(_currencyAmount, _tokenAmount);
    }
}
