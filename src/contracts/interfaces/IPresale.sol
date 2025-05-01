// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Presale} from "../Presale.sol";

/**
 * This interface outlines the functions related to managing and interacting
 * with presale contracts. It includes capabilities such as depositing funds,
 * finalizing the presale, canceling the presale, claiming tokens, and refunding
 * contributions. Implementing contracts should provide the logic for these
 * operations in the context of a presale event.
 */
interface IPresale {
    // --- Errors ---
    error NotFactory();
    error InvalidSettings();
    error Unauthorized();
    error InvalidState(uint8 currentState);
    error SoftCapNotReached();
    error HardCapExceed(); // Note: Presale.sol uses HardCapExceeded
    error NotClaimable();
    error NotInPurchasePeriod();
    error PurchaseBelowMinimum(); // Note: Presale.sol uses BelowMinimumContribution
    error PurchaseLimitExceed(); // Note: Presale.sol uses ExceedsMaximumContribution
    error NotRefundable();
    error LiquificationFailed();
    error InvalidInitializationParameters(); // Note: Presale.sol uses InvalidInitialization
    error InvalidCapValue(); // Note: Presale.sol uses InvalidCapSettings
    error InvalidLimitValue(); // Note: Presale.sol uses InvalidContributionLimits
    error InvalidLiquidityValue(); // Note: Presale.sol uses InvalidLiquidityBps
    error InvalidTimestampValue(); // Note: Presale.sol uses InvalidTimestamps
    error InvalidHouseConfiguration();
    error NoFundsToWithdraw();
    error PresaleNotEnded();
    error InsufficientTokenDeposit(uint256 amount, uint256 totalTokensNeeded);
    error InvalidRouter();
    error LiquificationFailedReason(string reason);
    error ZeroAmount();
    error ZeroLiquidityAmounts();
    error InvalidCapSettings();
    error PairCreationFailed(address token, address pairCurrency);
    error LPLockFailedReason(string reason);
    error CannotRescueBeforeFinalizationOrCancellation();
    error InvalidContributionLimits();
    error InvalidSlippage();
    error InvalidTimestamps();
    error LPLockFailed();
    error InvalidLiquidityAmounts();
    error BatchTooLarge();
    error InvalidDeadline();
    error CannotRescueBeforeFinalization();
    error InvalidLockupDuration();
    error InvalidRates();
    error SoftCapTooLow();
    error LiquificationYieldedZeroLP();
    error PairAddressZero();
    error InvalidCurrencyDecimals();
    error ContractPaused();
    error ETHNotAccepted();
    error StablecoinNotAccepted();
    error NotActive();
    error ClaimPeriodExpired();
    error NoTokensToClaim();
    error InsufficientTokenBalance();
    error NoFundsToRefund();
    error InsufficientContractBalance();
    error InvalidContributorAddress();
    error HardCapExceeded();
    error BelowMinimumContribution();
    error ExceedsMaximumContribution();
    error NotWhitelisted();
    error InvalidAddress();
    error CannotRescuePresaleTokens();
    error AlreadyPaused();
    error NotPaused();
    error ZeroTokensForContribution();
    error InvalidInitialization();
    error InvalidVestingDuration();
    error InvalidLeftoverTokenOption();
    error InvalidLiquidityBps();
    error InvalidHousePercentage();
    error InvalidHouseAddress();
    error InvalidVestingPercentage();
    error ZeroDecimals(); // Added from Presale.sol check
    error LiquificationFailedReasonBytes(bytes reason); // Added from Presale.sol check
    error DeprecatedFunction(); // Added for deprecated functions

    // --- Events ---
    event Deposit(address indexed sender, uint256 amount, uint256 timestamp);
    event Purchase(address indexed buyer, uint256 amount);
    event Finalized(address indexed owner, uint256 amountRaised, uint256 timestamp);
    event Refund(address indexed contributor, uint256 amount, uint256 timestamp);
    event TokenClaim(address indexed claimer, uint256 amount, uint256 timestamp);
    event Cancel(address indexed owner, uint256 timestamp);
    event PresaleCreated(
        address indexed creator, address indexed presale, address indexed token, uint256 start, uint256 end
    );
    event LiquidityAdded(address indexed pair, uint256 lpAmount, uint256 unlockTime);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event Withdrawn(address indexed owner, uint256 amount);
    event WhitelistToggled(bool enabled);
    event WhitelistUpdated(address indexed contributor, bool added);
    event Contribution(address indexed contributor, uint256 amount, bool isETH);
    event LeftoverTokensReturned(uint256 amount, address indexed beneficiary);
    event LeftoverTokensBurned(uint256 amount);
    event LeftoverTokensVested(uint256 amount, address indexed beneficiary);
    event HouseFundsDistributed(address indexed house, uint256 amount);
    event MerkleRootUpdated(bytes32 indexed _merkleRoot);
    event ClaimDeadlineExtended(uint256 newDeadline);

    // --- Functions ---
    // <<< FIX: Removed explicit options() getter declaration >>>
    // function options() external view returns (IPresale.PresaleOptions memory);

    function deposit() external returns (uint256);
    function finalize() external returns (bool);
    function cancel() external returns (bool);
    function claim() external returns (uint256);
    function refund() external returns (uint256);
    function withdraw() external;
    function updateWhitelist(address[] calldata addresses, bool add) external;
    function pause() external;
    function unpause() external;
    function calculateTotalTokensNeeded() external view returns (uint256);
    function userTokens(address contributor) external view returns (uint256);
    function getContributorCount() external view returns (uint256);
    function getContributors() external view returns (address[] memory);
    function getTotalContributed() external view returns (uint256);
    function getContribution(address contributor) external view returns (uint256);
    function rescueTokens(address _erc20Token, address _to, uint256 _amount) external; // Added missing definition
    function toggleWhitelist(bool enabled) external; // Added missing definition
    function setMerkleRoot(bytes32 _merkleRoot) external; // Added missing definition
    function extendClaimDeadline(uint256 _newDeadline) external;
    function contributeStablecoin(uint256 _amount, bytes32[] calldata _merkleProof) external; // Added missing definition
    function getOptions() external view returns (Presale.PresaleOptions memory); // Added missing definition

    // Note: contribute(bytes32[]) payable and receive() payable are implicitly part of the interface
    // if the implementing contract defines them as public/external payable.
}
