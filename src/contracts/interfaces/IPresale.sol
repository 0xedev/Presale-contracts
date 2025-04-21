// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * This interface outlines the functions related to managing and interacting
 * with presale contracts. It includes capabilities such as depositing funds,
 * finalizing the presale, canceling the presale, claiming tokens, and refunding
 * contributions. Implementing contracts should provide the logic for these
 * operations in the context of a presale event.
 */
interface IPresale {
    /**
     * @dev Emitted when an unauthorized address attempts an action requiring specific permissions.
     */
    error Unauthorized();

    /**
     * @dev Emitted when an action is performed in an invalid state.
     * @param currentState The current state of the contract.
     */
    error InvalidState(uint8 currentState);

    /**
     * @dev Emitted when attempting to finalize a presale that has not reached its soft cap.
     */
    error SoftCapNotReached();

    /**
     * @dev Emitted when a purchase attempt exceeds the presale's hard cap.
     */
    error HardCapExceed();

    /**
     * @dev Emitted when user with no contribution attempts to claim tokens.
     */
    error NotClaimable();

    /**
     * @dev Emitted when a purchase or refund attempt is made outside the presale period.
     */
    error NotInPurchasePeriod();

    /**
     * @dev Emitted when a purchase amount is below the minimum allowed.
     */
    error PurchaseBelowMinimum();

    /**
     * @dev Emitted when a participant's purchase would exceed the maximum allowed contribution.
     */
    error PurchaseLimitExceed();

    /**
     * @dev Emitted when a refund is requested under conditions that do not permit refunds.
     */
    error NotRefundable();

    /**
     * @dev Emitted when the process of adding liquidity to a liquidity pool fails.
     */
    error LiquificationFailed();

    /**
     * @dev Emitted when the initialization parameters provided to the contract are invalid.
     */
    error InvalidInitializationParameters();

    /**
     * @dev Emitted when the pool validation parameters provided to the contract are invalid.
     */
    error InvalidCapValue();

    /**
     * @dev Emitted when the pool validation parameters provided to the contract are invalid.
     */
    error InvalidLimitValue();

    /**
     * @dev Emitted when the pool validation parameters provided to the contract are invalid.
     */
    error InvalidLiquidityValue();

    /**
     * @dev Emitted when the pool validation parameters provided to the contract are invalid.
     */
    error InvalidTimestampValue();

    /**
     * @dev Emitted when the presale contract owner deposits tokens for sale.
     * This is usually done before the presale starts to ensure tokens are available for purchase.
     * @param sender Address of the contract owner who performs the deposit.
     * @param amount Amount of tokens deposited.
     * @param timestamp Block timestamp when the deposit occurred.
     */
    event Deposit(address indexed sender, uint256 amount, uint256 timestamp);

    /**
     * @dev Emitted for each purchase made during the presale. Tracks the buyer, the amount of ETH contributed,
     * and the amount of tokens purchased.
     * @param buyer Address of the participant who made the purchase.
     * @param amount Amount of ETH contributed by the participant.
     */
    event Purchase(address indexed buyer, uint256 amount);

    /**
     * @dev Emitted when the presale is successfully finalized. Finalization may involve distributing tokens,
     * transferring raised funds to a designated wallet, and/or enabling token claim functionality.
     * @param owner Address of the contract owner who finalized the presale.
     * @param amountRaised Total amount of ETH raised in the presale.
     * @param timestamp Block timestamp when the finalization occurred.
     */
    event Finalized(address indexed owner, uint256 amountRaised, uint256 timestamp);

    /**
     * @dev Emitted when a participant successfully claims a refund. This is typically allowed when the presale
     * is cancelled or does not meet its funding goals.
     * @param contributor Address of the participant receiving the refund.
     * @param amount Amount of wei refunded.
     * @param timestamp Block timestamp when the refund occurred.
     */
    event Refund(address indexed contributor, uint256 amount, uint256 timestamp);

    /**
     * @dev Emitted when participants claim their purchased tokens after the presale is finalized.
     * @param claimer Address of the participant claiming tokens.
     * @param amount Amount of tokens claimed.
     * @param timestamp Block timestamp when the claim occurred.
     */
    event TokenClaim(address indexed claimer, uint256 amount, uint256 timestamp);

    /**
     * @dev Emitted when the presale is cancelled by the contract owner. A cancellation may allow participants
     * to claim refunds for their contributions.
     * @param owner Address of the contract owner who cancelled the presale.
     * @param timestamp Block timestamp when the cancellation occurred.
     */
    event Cancel(address indexed owner, uint256 timestamp);

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

/// @notice Thrown when the contract is paused and an action cannot be performed.
error ContractPaused();

/// @notice Thrown when ETH is not accepted for the current operation.
error ETHNotAccepted();

/// @notice Thrown when stablecoins are not accepted for the current operation.
error StablecoinNotAccepted();

/// @notice Thrown when the presale is not active.
error NotActive();

/// @notice Thrown when the claim period has expired.
error ClaimPeriodExpired();

/// @notice Thrown when there are no tokens available to claim.
error NoTokensToClaim();

/// @notice Thrown when the token balance is insufficient for the operation.
error InsufficientTokenBalance();

/// @notice Thrown when there are no funds available to refund.
error NoFundsToRefund();

/// @notice Thrown when the contract balance is insufficient for the operation.
error InsufficientContractBalance();

/// @notice Thrown when the contributor address is invalid.
error InvalidContributorAddress();

/// @notice Thrown when the hard cap for the presale is exceeded.
error HardCapExceeded();

/// @notice Thrown when the contribution is below the minimum allowed amount.
error BelowMinimumContribution();

/// @notice Thrown when the contribution exceeds the maximum allowed amount.
error ExceedsMaximumContribution();

/// @notice Thrown when the contributor is not whitelisted.
error NotWhitelisted();

/// @notice Thrown when an invalid address is provided.
error InvalidAddress();

/// @notice Thrown when attempting to rescue presale tokens, which is not allowed.
error CannotRescuePresaleTokens();

/// @notice Thrown when the contract is already paused.
error AlreadyPaused();

/// @notice Thrown when the contract is not paused but an action requires it to be paused.
error NotPaused();

/// @notice Thrown when the contribution results in zero tokens being allocated.
error ZeroTokensForContribution();

/// @notice Thrown when the initialization parameters are invalid.
error InvalidInitialization();

/// @notice Thrown when the vesting duration is invalid.
error InvalidVestingDuration();

/// @notice Thrown when the leftover token option is invalid.
error InvalidLeftoverTokenOption();

/// @notice Thrown when the liquidity basis points (bps) are invalid.
error InvalidLiquidityBps();

/// @notice Thrown when the house percentage is invalid.
error InvalidHousePercentage();

/// @notice Thrown when the house address is invalid.
error InvalidHouseAddress();

/// @notice Thrown when the vesting percentage is invalid.
error InvalidVestingPercentage();
 
    /**
     * @notice Allows a user to contribute to the presale using native currency.
     * @dev This function is payable and accepts native currency contributions.
     */
    function contribute() external payable;

    /**
     * @notice Allows a user to contribute to the presale using stablecoins.
     * @param amount The amount of stablecoins to contribute.
     */
    function contributeStablecoin(uint256 amount) external;

    /**
     * @notice Deposits funds into the presale contract.
     * @return The amount of funds deposited.
     */
    function deposit() external returns (uint256);

    /**
     * @notice Finalizes the presale, locking in contributions and enabling token distribution.
     * @return A boolean indicating whether the presale was successfully finalized.
     */
    function finalize() external returns (bool);

    /**
     * @notice Cancels the presale and enables refunds for contributors.
     * @return A boolean indicating whether the presale was successfully canceled.
     */
    function cancel() external returns (bool);

    /**
     * @notice Allows a user to claim their allocated tokens after the presale is finalized.
     * @return The amount of tokens claimed by the user.
     */
    function claim() external returns (uint256);

    /**
     * @notice Allows a user to request a refund of their contribution if the presale is canceled.
     * @return The amount refunded to the user.
     */
    function refund() external returns (uint256);

    /**
     * @notice Withdraws funds from the presale contract to the owner's address.
     */
    function withdraw() external;

    /**
     * @notice Rescues tokens mistakenly sent to the contract.
     * @param token The address of the token to rescue.
     * @param to The address to send the rescued tokens to.
     * @param amount The amount of tokens to rescue.
     */
    function rescueTokens(address token, address to, uint256 amount) external;

    /**
     * @notice Toggles the whitelist functionality for the presale.
     * @param enabled A boolean indicating whether the whitelist should be enabled or disabled.
     */
    function toggleWhitelist(bool enabled) external;

    /**
     * @notice Updates the whitelist by adding or removing addresses.
     * @param addresses The list of addresses to update in the whitelist.
     * @param add A boolean indicating whether to add (true) or remove (false) the addresses.
     */
    function updateWhitelist(address[] calldata addresses, bool add) external;

    /**
     * @notice Pauses the presale, preventing contributions and other actions.
     */
    function pause() external;

    /**
     * @notice Unpauses the presale, allowing contributions and other actions to resume.
     */
    function unpause() external;

    /**
     * @notice Calculates the total number of tokens needed for the presale.
     * @return The total number of tokens required.
     */
    function calculateTotalTokensNeeded() external view returns (uint256);

    /**
     * @notice Retrieves the number of tokens allocated to a specific contributor.
     * @param contributor The address of the contributor.
     * @return The number of tokens allocated to the contributor.
     */
    function userTokens(address contributor) external view returns (uint256);

    /**
     * @notice Retrieves the total number of contributors to the presale.
     * @return The total number of contributors.
     */
    function getContributorCount() external view returns (uint256);

    /**
     * @notice Retrieves the list of all contributors to the presale.
     * @return An array of addresses representing the contributors.
     */
    function getContributors() external view returns (address[] memory);

    /**
     * @notice Retrieves the total amount of contributions made to the presale.
     * @return The total amount of contributions.
     */
    function getTotalContributed() external view returns (uint256);

    /**
     * @notice Retrieves the contribution amount of a specific contributor.
     * @param contributor The address of the contributor.
     * @return The amount contributed by the specified contributor.
     */
    function getContribution(address contributor) external view returns (uint256);
}
