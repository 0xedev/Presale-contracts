// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Imports ---
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
    // using SafeERC20 for ERC20; // Redundant if using for IERC20
    using Address for address payable;

    enum PresaleState {
        Pending,
        Active,
        Canceled,
        Finalized
    }

    struct PresaleOptions {
        uint256 tokenDeposit; // Tokens deposited for presale
        uint256 hardCap; // Max currency to raise
        uint256 softCap; // Min currency to raise
        uint256 min; // Min contribution per user
        uint256 max; // Max contribution per user
        uint256 presaleRate; // Tokens per currency unit
        uint256 listingRate; // Tokens per currency unit at listing
        uint256 liquidityBps; // Basis points for liquidity (5000-10000)
        uint256 slippageBps; // Max slippage for liquidity
        uint256 start; // Presale start timestamp
        uint256 end; // Presale end timestamp
        uint256 lockupDuration; // LP token lock duration
        uint256 vestingPercentage; // Percentage of tokens vested (BPS)
        uint256 vestingDuration; // Vesting duration
        uint256 leftoverTokenOption; // 0: return, 1: burn, 2: vest
        address currency; // Address(0) for ETH, else stablecoin
    }

    // --- State Variables ---
    uint256 public totalRefundable; // Tracks refundable amount (ETH or Stable)
    uint256 public constant BASIS_POINTS = 10_000;
    bool public paused;
    bool public whitelistEnabled; // Controlled by merkleRoot != 0
    uint256 public claimDeadline;
    uint256 public ownerBalance; // Tracks owner's share after finalize

    // Immutable variables set by factory
    LiquidityLocker public immutable liquidityLocker;
    Vesting public immutable vestingContract;
    uint256 public immutable housePercentage;
    address public immutable houseAddress;

    // Presale Configuration
    PresaleOptions public options;

    // Presale State Machine

    PresaleState public state;

    // Contribution Tracking
    mapping(address => uint256) public contributions; // Tracks amount contributed per user (ETH or Stable)
    mapping(address => bool) private isContributor; // Tracks if an address has contributed
    address[] public contributors; // Array of unique contributor addresses

    // Whitelist
    bytes32 public merkleRoot;

    // Constants & Allowed Values
    uint256[] private ALLOWED_LIQUIDITY_BPS = [5000, 6000, 7000, 8000, 9000, 10000];

    // Internal Pool Data (Removed redundant state, simplified)

    ERC20 public immutable token; // Presale token
    IUniswapV2Router02 public immutable uniswapV2Router02;
    address public immutable factory; // Uniswap V2 Factory
    address public immutable weth; // WETH address
    uint256 public tokenBalance; // Current balance of presale tokens held by this contract
    uint256 public tokensClaimable; // Total tokens allocated for contributors (based on hardcap)
    uint256 public tokensLiquidity; // Total tokens allocated for liquidity (based on hardcap)
    uint256 public totalRaised; // Total amount raised (ETH or Stable)

    // --- Modifiers ---
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // Modifier to check if the presale is in a refundable state
    modifier onlyRefundable() {
        // Refundable if Canceled OR if Active period ended AND softcap not met
        if (
            !(
                state == PresaleState.Canceled
                    || (state == PresaleState.Active && block.timestamp > options.end && totalRaised < options.softCap)
            )
        ) {
            revert NotRefundable();
        }
        _;
    }

    // --- Constructor ---
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
        // Input Validations
        if (
            _weth == address(0) || _token == address(0) || _uniswapV2Router02 == address(0)
                || _liquidityLocker == address(0) || _vestingContract == address(0)
        ) {
            revert InvalidInitialization();
        }
        if (_options.leftoverTokenOption > 2) {
            revert InvalidLeftoverTokenOption();
        }
        if (_housePercentage > 500) revert InvalidHousePercentage(); // Max 5%
        if (_houseAddress == address(0) && _housePercentage > 0) {
            revert InvalidHouseAddress();
        }
        _prevalidatePool(_options); // Validate numeric options

        // Set immutable variables
        weth = _weth;
        token = ERC20(_token);
        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);
        try uniswapV2Router02.factory() returns (address _factory) {
            factory = _factory;
        } catch {
            revert InvalidRouter(); // Ensure router provides a factory address
        }
        liquidityLocker = LiquidityLocker(_liquidityLocker);
        vestingContract = Vesting(_vestingContract);
        housePercentage = _housePercentage;
        houseAddress = _houseAddress;

        // Set configurable options
        options = _options;

        // Initial state is Pending
        state = PresaleState.Pending; // <<< FIX: Explicitly set initial state

        // Emit event for creation
        emit PresaleCreated(_creator, address(this), _token, _options.start, _options.end);
    }

    // --- Owner Functions ---

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        if (state != PresaleState.Pending) revert InvalidState(uint8(state));
        merkleRoot = _merkleRoot;
        whitelistEnabled = (_merkleRoot != bytes32(0)); // Update flag based on root
        emit MerkleRootUpdated(_merkleRoot);
    }

    // Deposit presale tokens (can only be called once)
    function deposit() external onlyOwner whenNotPaused returns (uint256) {
        if (state != PresaleState.Pending) revert InvalidState(uint8(state)); // <<< FIX: Check against main state enum

        uint256 amount = options.tokenDeposit;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount); // Use IERC20 interface

        // Calculate required tokens based on hardcap
        tokensClaimable = _tokensForPresale();
        tokensLiquidity = _tokensForLiquidity();
        uint256 totalTokensNeeded = tokensClaimable + tokensLiquidity;

        // Ensure enough tokens were deposited for hardcap + liquidity
        if (amount < totalTokensNeeded) {
            revert InsufficientTokenDeposit(amount, totalTokensNeeded);
        }

        tokenBalance = amount; // Update contract's token balance

        // <<< FIX: Update State >>>
        state = PresaleState.Active;

        emit Deposit(msg.sender, amount, block.timestamp);
        return amount;
    }

    // Finalize the presale (if softcap met)
    function finalize() external onlyOwner whenNotPaused nonReentrant returns (bool) {
        if (state != PresaleState.Active) revert InvalidState(uint8(state)); // <<< FIX: Check against main state enum
        if (block.timestamp <= options.end) revert PresaleNotEnded(); // Ensure presale period is over
        if (totalRaised < options.softCap) revert SoftCapNotReached();

        // <<< FIX: Update State >>>
        state = PresaleState.Finalized;

        uint256 liquidityAmount = _weiForLiquidity(); // Currency amount for liquidity
        uint256 tokensForLiq = tokensLiquidity; // Use pre-calculated value

        // Add Liquidity
        _liquify(liquidityAmount, tokensForLiq);
        tokenBalance -= tokensForLiq; // Decrease token balance by amount used for liquidity

        // Distribute house percentage
        uint256 houseAmount = (totalRaised * housePercentage) / BASIS_POINTS;
        if (houseAmount > 0) {
            _safeTransferCurrency(houseAddress, houseAmount);
            emit HouseFundsDistributed(houseAddress, houseAmount);
        }

        // Calculate and store owner's share
        ownerBalance = totalRaised - liquidityAmount - houseAmount;

        // Set claim deadline
        claimDeadline = block.timestamp + 180 days; // Default 180 days

        // Handle leftover/unsold tokens
        _handleLeftoverTokens();

        emit Finalized(msg.sender, totalRaised, block.timestamp);
        return true;
    }

    // Cancel the presale (only before finalization)
    function cancel() external nonReentrant onlyOwner whenNotPaused returns (bool) {
        // Can cancel if Pending or Active
        if (state != PresaleState.Pending && state != PresaleState.Active) {
            revert InvalidState(uint8(state));
        }

        // <<< FIX: Update State >>>
        state = PresaleState.Canceled;

        // Return all deposited presale tokens to creator
        if (tokenBalance > 0) {
            uint256 amountToReturn = tokenBalance;
            tokenBalance = 0; // Reset balance
            IERC20(token).safeTransfer(msg.sender, amountToReturn); // Use IERC20
            emit LeftoverTokensReturned(amountToReturn, msg.sender); // Reuse event
        }

        // Note: Contributions become refundable via the refund() function due to Canceled state

        emit Cancel(msg.sender, block.timestamp);
        return true;
    }

    // Withdraw owner's share after finalization
    function withdraw() external onlyOwner nonReentrant {
        if (state != PresaleState.Finalized) revert InvalidState(uint8(state)); // Can only withdraw after finalize
        uint256 amount = ownerBalance;
        if (amount == 0) revert NoFundsToWithdraw(); // Changed error for clarity
        ownerBalance = 0; // Reset balance before transfer
        _safeTransferCurrency(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // Extend the claim deadline
    function extendClaimDeadline(uint256 _newDeadline) external onlyOwner {
        if (state != PresaleState.Finalized) revert InvalidState(uint8(state)); // Must be finalized
        if (_newDeadline <= claimDeadline) revert InvalidDeadline();
        claimDeadline = _newDeadline;
        emit ClaimDeadlineExtended(_newDeadline);
    }

    // Rescue mistakenly sent ERC20 tokens
    function rescueTokens(address _erc20Token, address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0)) revert InvalidAddress();
        // Can only rescue after finalization or cancellation
        if (state != PresaleState.Finalized && state != PresaleState.Canceled) {
            revert CannotRescueBeforeFinalizationOrCancellation(); // More accurate error
        }
        // Cannot rescue the presale token before the claim deadline if finalized
        if (
            state == PresaleState.Finalized && address(_erc20Token) == address(token)
                && block.timestamp <= claimDeadline
        ) {
            revert CannotRescuePresaleTokens();
        }
        IERC20(_erc20Token).safeTransfer(_to, _amount);
        emit TokensRescued(_erc20Token, _to, _amount);
    }

    // Pause/Unpause contract functions
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

    // --- Public Contribution Functions ---

    // Contribute ETH
    function contribute(bytes32[] calldata _merkleProof) external payable whenNotPaused nonReentrant {
        // Use receive() logic internally
        _contribute(msg.sender, msg.value, _merkleProof);
    }

    // Fallback receive function for ETH contributions
    receive() external payable whenNotPaused nonReentrant {
        // Empty proof for non-whitelist scenario
        bytes32[] memory emptyProof;
        _contribute(msg.sender, msg.value, emptyProof);
    }

    // Contribute Stablecoin
    function contributeStablecoin(uint256 _amount, bytes32[] calldata _merkleProof)
        external
        whenNotPaused
        nonReentrant
    {
        if (options.currency == address(0)) revert StablecoinNotAccepted();
        if (_amount == 0) revert ZeroAmount(); // Check amount before transfer

        IERC20 stablecoin = IERC20(options.currency);
        stablecoin.safeTransferFrom(msg.sender, address(this), _amount);

        _contribute(msg.sender, _amount, _merkleProof);
    }

    // --- Claim & Refund Functions ---

    // Claim purchased tokens after finalization
    function claim() external nonReentrant whenNotPaused returns (uint256) {
        if (state != PresaleState.Finalized) revert InvalidState(uint8(state)); // <<< FIX: Check against main state enum
        if (block.timestamp > claimDeadline) revert ClaimPeriodExpired();

        uint256 totalTokens = userTokens(msg.sender); // Calculate tokens based on contribution
        if (totalTokens == 0) revert NoTokensToClaim();

        // Reset contribution amount for the user to prevent double claim
        contributions[msg.sender] = 0;

        // Ensure contract has enough balance (sanity check, should be covered by finalize logic)
        if (tokenBalance < totalTokens) revert InsufficientTokenBalance();
        tokenBalance -= totalTokens; // Decrease contract balance

        // Calculate vesting split
        uint256 vestingBps = options.vestingPercentage;
        uint256 vestedTokens = 0;
        uint256 immediateTokens = totalTokens;

        if (vestingBps > 0) {
            vestedTokens = (totalTokens * vestingBps) / BASIS_POINTS;
            immediateTokens = totalTokens - vestedTokens;
        }

        // Transfer immediate tokens
        if (immediateTokens > 0) {
            IERC20(token).safeTransfer(msg.sender, immediateTokens); // Use IERC20
        }

        // Set up vesting for vested tokens
        if (vestedTokens > 0) {
            IERC20(token).approve(address(vestingContract), vestedTokens); // Use IERC20
            vestingContract.createVesting(
                msg.sender, address(token), vestedTokens, block.timestamp, options.vestingDuration
            );
        }

        emit TokenClaim(msg.sender, totalTokens, block.timestamp);
        return totalTokens;
    }

    // Refund contribution if presale is Canceled or Failed (softcap not met after end)
    function refund() external nonReentrant onlyRefundable returns (uint256) {
        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoFundsToRefund();

        // Reset contribution amount to prevent double refund
        contributions[msg.sender] = 0;

        // Decrease total refundable amount tracking
        // Note: totalRefundable might not be strictly necessary if relying on `contributions` mapping
        if (totalRefundable >= amount) {
            // Prevent underflow
            totalRefundable -= amount;
        } else {
            totalRefundable = 0; // Should not happen if tracked correctly
        }

        // Transfer currency back to contributor
        _safeTransferCurrency(msg.sender, amount);

        emit Refund(msg.sender, amount, block.timestamp);
        return amount;
    }

    // --- Internal Logic Functions ---

    // Internal contribution processing logic
    function _contribute(address _contributor, uint256 _amount, bytes32[] memory _merkleProof) private {
        // Basic state and time checks
        if (state != PresaleState.Active) revert InvalidState(uint8(state));
        if (block.timestamp < options.start || block.timestamp > options.end) {
            revert NotInPurchasePeriod();
        }
        if (_contributor == address(0)) revert InvalidContributorAddress();

        // Whitelist check
        if (whitelistEnabled) {
            // Check flag instead of root directly
            if (!MerkleProof.verify(_merkleProof, merkleRoot, keccak256(abi.encodePacked(_contributor)))) {
                revert NotWhitelisted();
            }
        }

        // Currency check (ensure ETH sent to ETH presale, stablecoin amount for stable presale)
        if (options.currency == address(0)) {
            // ETH Presale
            if (msg.value == 0) revert ZeroAmount();
            // Amount validation happens in _validateContribution using msg.value
        } else {
            // Stablecoin Presale
            if (msg.value > 0) revert ETHNotAccepted(); // Cannot send ETH to stablecoin presale
            if (_amount == 0) revert ZeroAmount();
            // Amount validation happens in _validateContribution using _amount
        }

        // Validate contribution limits (Min/Max/HardCap)
        _validateContribution(_contributor, _amount); // <<< FIX: Pass stablecoin amount here

        // Track contribution amount
        uint256 contributionAmount = (options.currency == address(0)) ? msg.value : _amount;
        totalRaised += contributionAmount;
        totalRefundable += contributionAmount; // Track total that might need refunding

        // <<< FIX: Correct Contribution Tracking >>>
        if (!isContributor[_contributor]) {
            isContributor[_contributor] = true;
            contributors.push(_contributor);
        }
        contributions[_contributor] += contributionAmount; // Increment contribution *once*

        emit Purchase(_contributor, contributionAmount); // Use the actual amount contributed
        emit Contribution(_contributor, contributionAmount, options.currency == address(0)); // Track correct type
    }

    // Internal function to handle leftover tokens after finalization
    function _handleLeftoverTokens() private {
        // Calculate unsold tokens based on contributions vs tokens needed for them
        uint256 tokensSold = (totalRaised * options.presaleRate * 10 ** token.decimals()) / _getCurrencyMultiplier();

        // Ensure calculated sold tokens don't exceed claimable tokens (sanity check)
        if (tokensSold > tokensClaimable) {
            tokensSold = tokensClaimable; // Cap at max claimable
        }

        // Calculate unsold presale tokens
        uint256 unsoldPresaleTokens = tokensClaimable - tokensSold;

        // Total leftover = unsold presale tokens + any excess deposited beyond needed for hardcap+liq
        uint256 totalTokensNeededAtDeposit = tokensClaimable + tokensLiquidity;
        uint256 excessDeposit = (tokenBalance + tokensLiquidity > totalTokensNeededAtDeposit) // Add back tokensLiquidity as it was subtracted before calling this
            ? (tokenBalance + tokensLiquidity - totalTokensNeededAtDeposit)
            : 0;

        uint256 totalLeftover = unsoldPresaleTokens + excessDeposit;

        if (totalLeftover > 0) {
            // Ensure contract balance is sufficient (should always be true if logic is correct)
            if (tokenBalance < totalLeftover) {
                // This indicates a potential logic error elsewhere, but handle gracefully
                totalLeftover = tokenBalance;
            }

            tokenBalance -= totalLeftover; // Decrease balance

            if (options.leftoverTokenOption == 0) {
                // Return to creator
                IERC20(token).safeTransfer(owner(), totalLeftover); // Use IERC20
                emit LeftoverTokensReturned(totalLeftover, owner());
            } else if (options.leftoverTokenOption == 1) {
                // Burn
                IERC20(token).safeTransfer(address(0), totalLeftover); // Use IERC20
                emit LeftoverTokensBurned(totalLeftover);
            } else {
                // Vest for the owner
                IERC20(token).approve(address(vestingContract), totalLeftover); // Use IERC20
                vestingContract.createVesting(
                    owner(), address(token), totalLeftover, block.timestamp, options.vestingDuration
                );
                emit LeftoverTokensVested(totalLeftover, owner());
            }
        }
    }

    // Internal function to add liquidity to Uniswap V2
    function _liquify(uint256 _currencyAmount, uint256 _tokenAmount) private {
        if (_currencyAmount == 0 || _tokenAmount == 0) {
            revert ZeroLiquidityAmounts(); // Cannot add zero liquidity
        }

        // Calculate minimum amounts considering slippage
        uint256 minToken = (_tokenAmount * (BASIS_POINTS - options.slippageBps)) / BASIS_POINTS;
        uint256 minCurrency = (_currencyAmount * (BASIS_POINTS - options.slippageBps)) / BASIS_POINTS;

        // Get or create the pair address
        address pairCurrency = (options.currency == address(0)) ? weth : options.currency;
        address pair = IUniswapV2Factory(factory).getPair(address(token), pairCurrency);
        if (pair == address(0)) {
            // This should ideally not happen if the pair exists, but handle creation defensively
            // Note: Pair creation might fail if one token is non-standard or already in another pair type
            try IUniswapV2Factory(factory).createPair(address(token), pairCurrency) returns (address newPair) {
                pair = newPair;
            } catch {
                revert PairCreationFailed(address(token), pairCurrency);
            }
        }
        if (pair == address(0)) {
            // Double check after potential creation
            revert PairAddressZero();
        }

        // Approve router
        IERC20(token).approve(address(uniswapV2Router02), _tokenAmount); // Use IERC20

        // Add liquidity based on currency type
        uint256 lpAmountBefore = IERC20(pair).balanceOf(address(this));

        try uniswapV2Router02.addLiquidityETH{value: _currencyAmount}(
            address(token),
            _tokenAmount,
            minToken,
            minCurrency,
            address(this), // LP tokens sent to this contract
            block.timestamp + 600 // Deadline
        ) {
            // ETH Liquidity Added
        } catch Error(string memory reason) {
            revert LiquificationFailedReason(reason);
        } catch {
            revert LiquificationFailed();
        }

        // Reset token approval
        IERC20(token).approve(address(uniswapV2Router02), 0); // Use IERC20

        // Lock LP tokens
        uint256 lpAmount = IERC20(pair).balanceOf(address(this)) - lpAmountBefore;
        if (lpAmount == 0) revert LiquificationYieldedZeroLP(); // Check if LP tokens were actually received

        uint256 unlockTime = block.timestamp + options.lockupDuration;
        IERC20(pair).approve(address(liquidityLocker), lpAmount); // Approve locker

        // Lock LP tokens in the locker contract
        try liquidityLocker.lock(pair, lpAmount, unlockTime, owner()) {}
        catch Error(string memory reason) {
            revert LPLockFailedReason(reason);
        } catch {
            revert LPLockFailed();
        }
        emit LiquidityAdded(pair, lpAmount, unlockTime);
    }

    // Internal validation for purchase amounts and limits
    function _validateContribution(address _contributor, uint256 _stablecoinAmountIfAny) private view {
        PresaleOptions memory opts = options;
        uint256 amount = (opts.currency == address(0)) ? msg.value : _stablecoinAmountIfAny;

        // Check against hard cap
        if (totalRaised + amount > opts.hardCap) revert HardCapExceeded();

        // <<< FIX: Stablecoin Min/Max Check >>>
        uint256 minCheck = opts.min;
        uint256 maxCheck = opts.max;
        uint256 contributionCheck = contributions[_contributor] + amount;

        if (opts.currency != address(0)) {
            // If stablecoin, assume min/max are defined in stablecoin units
            // (Requires presale creator to set appropriate min/max for stablecoin)
            // No conversion needed here if options are set correctly.
            // If min/max were intended as ETH equivalents, conversion logic would be needed here.
            // Example (if rates were reliable, which they aren't pre-liquidity):
            // uint256 stableDecimals = ERC20(opts.currency).decimals();
            // uint256 ethRateEstimate = 3000 * (10**stableDecimals); // Highly unreliable estimate!
            // minCheck = (opts.min * ethRateEstimate) / (1 ether);
            // maxCheck = (opts.max * ethRateEstimate) / (1 ether);
            if (amount < minCheck) revert BelowMinimumContribution();
            if (contributionCheck > maxCheck) {
                revert ExceedsMaximumContribution();
            }
        } else {
            // ETH presale - direct comparison
            if (amount < minCheck) revert BelowMinimumContribution();
            if (contributionCheck > maxCheck) {
                revert ExceedsMaximumContribution();
            }
        }
    }

    // --- View Functions ---

    // Calculate total tokens needed for the presale (hardcap + liquidity)
    function calculateTotalTokensNeeded() external view returns (uint256) {
        return _tokensForPresale() + _tokensForLiquidity();
    }

    // Check if a liquidity BPS value is allowed
    function isAllowedLiquidityBps(uint256 _bps) public view returns (bool) {
        // Made public for potential UI use
        for (uint256 i = 0; i < ALLOWED_LIQUIDITY_BPS.length; i++) {
            if (_bps == ALLOWED_LIQUIDITY_BPS[i]) return true;
        }
        return false;
    }

    // Calculate tokens a user is entitled to based on their contribution
    function userTokens(address _contributor) public view returns (uint256) {
        uint256 contribution = contributions[_contributor];
        if (contribution == 0) return 0;

        // Calculate based on presale rate
        return (contribution * options.presaleRate * 10 ** token.decimals()) / _getCurrencyMultiplier();
    }

    // Get the count of unique contributors
    function getContributorCount() external view returns (uint256) {
        return contributors.length;
    }

    // Get the array of contributor addresses
    function getContributors() external view returns (address[] memory) {
        return contributors;
    }

    // Get the total amount raised so far
    function getTotalContributed() external view returns (uint256) {
        return totalRaised;
    }

    // Get the contribution amount for a specific contributor
    function getContribution(address _contributor) external view returns (uint256) {
        return contributions[_contributor];
    }

    // --- Helper Functions ---

    // Get the multiplier based on currency decimals (1e18 for ETH, 1e(decimals) for stable)
    function _getCurrencyMultiplier() private view returns (uint256) {
        if (options.currency == address(0)) {
            return 1 ether; // 10**18
        } else {
            // Cache decimals? For now, query each time.
            try ERC20(options.currency).decimals() returns (uint8 decimals) {
                return 10 ** decimals;
            } catch {
                revert InvalidCurrencyDecimals(); // Handle case where currency contract is invalid
            }
        }
    }

    // Safely transfer ETH or Stablecoin
    function _safeTransferCurrency(address _to, uint256 _amount) private {
        if (_amount == 0) return; // No need to transfer zero

        if (options.currency == address(0)) {
            // Use sendValue for ETH transfer with reentrancy guard implicitly handled
            payable(_to).sendValue(_amount);
        } else {
            // Use SafeERC20 for stablecoin transfer
            IERC20(options.currency).safeTransfer(_to, _amount);
        }
    }

    // Validate numeric options during construction
    function _prevalidatePool(PresaleOptions memory _opts) private view {
        // Note: _opts.tokenDeposit is checked in deposit() against calculated needs
        if (_opts.hardCap == 0 || _opts.softCap == 0 || _opts.softCap > _opts.hardCap) {
            revert InvalidCapSettings();
        }
        // Softcap check: Ensure it's at least 25% of hardcap (can be adjusted)
        if (_opts.softCap * 4 < _opts.hardCap) {
            revert SoftCapTooLow();
        }
        if (_opts.max == 0 || _opts.min == 0 || _opts.min > _opts.max || _opts.max > _opts.hardCap) {
            revert InvalidContributionLimits();
        }
        if (!isAllowedLiquidityBps(_opts.liquidityBps)) {
            // liquidityBps >= 5000 check is implicit
            revert InvalidLiquidityBps();
        }
        if (_opts.slippageBps > 500) revert InvalidSlippage(); // Max 5% slippage
        if (_opts.presaleRate == 0 || _opts.listingRate == 0 || _opts.listingRate >= _opts.presaleRate) {
            revert InvalidRates();
        }
        if (_opts.start < block.timestamp || _opts.end <= _opts.start) {
            revert InvalidTimestamps();
        }
        if (_opts.lockupDuration == 0) revert InvalidLockupDuration();
        if (_opts.vestingPercentage > BASIS_POINTS) {
            revert InvalidVestingPercentage();
        }
        if (_opts.vestingPercentage > 0 && _opts.vestingDuration == 0) {
            revert InvalidVestingDuration();
        }
        // leftoverTokenOption checked in constructor
    }

    // Add after Helper Functions section
    function _tokensForPresale() private view returns (uint256) {
        return (options.hardCap * options.presaleRate * 10 ** token.decimals()) / _getCurrencyMultiplier();
    }

    function _tokensForLiquidity() private view returns (uint256) {
        uint256 currencyForLiquidity = (options.hardCap * options.liquidityBps) / BASIS_POINTS;
        return (currencyForLiquidity * options.listingRate * 10 ** token.decimals()) / _getCurrencyMultiplier();
    }

    function _weiForLiquidity() private view returns (uint256) {
        return (totalRaised * options.liquidityBps) / BASIS_POINTS;
    }

    function toggleWhitelist(bool enabled) external {}

    function updateWhitelist(address[] calldata addresses, bool add) external override {}
}
