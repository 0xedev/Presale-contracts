Additional Tests to Add

## test_Fork_FullCycle_Stablecoin_Presale

Purpose: Verify the full presale cycle using a stablecoin (e.g., mock USDC) instead of ETH.
Steps:
Deploy a mock stablecoin (6 decimals, like USDC).
Create a presale with options.currency set to the stablecoin.
Contributors use contributeStablecoin to contribute.
Finalize the presale, add liquidity, lock LP tokens, and claim tokens (immediate and vested).
Assertions:
Stablecoin contributions are recorded correctly.
Liquidity is added with the correct stablecoin amount.
Tokens are distributed (immediate and vested) correctly.
House fees and owner funds are in stablecoin.
Rationale: Tests the contributeStablecoin function and stablecoin-specific logic, which differs from ETH due to ERC20 transfers and decimal handling.

## test_Fork_Merkle_Whitelist_Presale

Purpose: Test a presale with Merkle-based whitelisting.
Steps:
Generate a Merkle tree with contributor1 and contributor2 as whitelisted addresses.
Create a presale with whitelistType = Merkle and set merkleRoot.
Have contributor1 contribute with a valid Merkle proof.
Attempt contribution from a non-whitelisted address (should fail).
Assertions:
Whitelisted contributors can contribute.
Non-whitelisted contributors revert with NotWhitelisted.
Merkle proof validation works correctly.
Rationale: Tests the MerkleProof.verify logic in \_contribute for Merkle-based whitelisting.

## test_Fork_NFT_Whitelist_Presale

Purpose: Test a presale with NFT-based whitelisting.
Steps:
Deploy a mock ERC721 contract and mint an NFT to contributor1.
Create a presale with whitelistType = NFT and set nftContractAddress.
Have contributor1 contribute (should succeed due to NFT ownership).
Have contributor2 (no NFT) attempt to contribute (should fail).
Assertions:
NFT holders can contribute.
Non-NFT holders revert with NotNftHolder.
Failed balanceOf calls revert with NftCheckFailed.
Rationale: Tests the NFT whitelist logic, including the IERC721.balanceOf check and error handling.

## test_Fork_Pause_And_Unpause

Purpose: Test pausing and unpausing the presale.
Steps:
Create a presale and pause it as the owner.
Attempt to contribute, claim, and refund while paused (should fail).
Unpause and verify contributions work.
Assertions:
pause sets paused = true and emits Paused.
contribute, claim, and refund revert with ContractPaused when paused.
unpause sets paused = false and emits Unpaused.
Contributions succeed after unpausing.
Rationale: Tests the whenNotPaused modifier and pause/unpause functions.

## test_Fork_Extend_Claim_Deadline

Purpose: Test extending the claim deadline after finalization.
Steps:
Create and finalize a presale.
Extend the claim deadline as the owner.
Attempt to claim tokens after the original deadline but before the new deadline.
Assertions:
extendClaimDeadline updates claimDeadline and emits ClaimDeadlineExtended.
Claims succeed before the new deadline.
Claims revert with ClaimPeriodExpired after the new deadline.
Non-owner calls to extendClaimDeadline revert.
Rationale: Tests the extendClaimDeadline function and claim deadline logic.

## test_Fork_Rescue_Tokens

Purpose: Test rescuing ERC20 tokens after finalization or cancellation.
Steps:
Create and finalize a presale.
Transfer a different ERC20 token (not the presale token) to the presale contract.
Rescue the tokens as the owner.
Attempt to rescue presale tokens before the claim deadline (should fail).
Cancel a presale and rescue presale tokens.
Assertions:
Non-presale tokens can be rescued after finalization.
Presale tokens cannot be rescued before claimDeadline (reverts with CannotRescuePresaleTokens).
Tokens can be rescued after cancellation.
Non-owner calls revert.
Rationale: Tests the rescueTokens function and its restrictions.

## test_Fork_Initialize_Deposit_Failure

Purpose: Test failure cases for initializeDeposit.
Steps:
Create a presale and attempt to call initializeDeposit:
After the presale starts (should fail).
When a pair already exists (should fail).
With insufficient token deposit (should fail).
From a non-factory address (should fail).
Assertions:
Reverts with NotInPurchasePeriod if called after options.start.
Reverts with PairAlreadyExists if a Uniswap pair exists.
Reverts with InsufficientTokenDeposit if token balance is too low.
Reverts with NotFactory if not called by the factory.
Rationale: Tests the onlyFactory modifier and deposit validation logic.

## test_Fork_Leftover_Tokens_Burn

Purpose: Test burning leftover tokens when leftoverTokenOption = 1.
Steps:
Create a presale with leftoverTokenOption = 1.
Contribute below the hard cap to leave unsold tokens.
Finalize the presale and verify tokens are sent to 0xdead.
Assertions:
Leftover tokens are transferred to 0xdead.
LeftoverTokensBurned event is emitted.
tokenBalance is reduced correctly.
Rationale: Tests the burn option in \_handleLeftoverTokens.

## test_Fork_Leftover_Tokens_Vest

Purpose: Test vesting leftover tokens when leftoverTokenOption = 2.
Steps:
Create a presale with leftoverTokenOption = 2.
Contribute below the hard cap.
Finalize the presale and verify a vesting schedule is created.
Assertions:
Vesting schedule is created for the owner with leftover tokens.
LeftoverTokensVested event is emitted.
tokenBalance is reduced correctly.
Rationale: Tests the vesting option in \_handleLeftoverTokens.

## test_Fork_Contribution_Edge_Cases

Purpose: Test edge cases for contributions.
Steps:
Contribute exactly options.min and options.max.
Contribute just below the hard cap, then attempt to exceed it (should fail).
Contribute after the presale ends (should fail).
Contribute before the presale starts (should fail).
Contribute with ETH when stablecoin is expected (should fail).
Assertions:
Minimum and maximum contributions are accepted.
Exceeding the hard cap reverts with HardCapExceeded.
Contributions outside the presale period revert with NotInPurchasePeriod.
ETH contributions to a stablecoin presale revert with ETHNotAccepted.
Rationale: Tests validation in \_validateContribution and \_contribute.

## test_Fork_Liquidity_Edge_Cases

Purpose: Test edge cases for liquidity addition.
Steps:
Create a presale with low totalRaised to test reserve adjustments in \_liquify.
Simulate liquidity addition with insufficient tokens (should return false).
Test with different liquidityBps values (from ALLOWED_LIQUIDITY_BPS).
Assertions:
\_liquify adjusts amounts based on pair reserves.
simulateLiquidityAddition returns false when tokenBalance is insufficient.
Only allowed liquidityBps values are accepted.
Rationale: Tests \_liquify, simulateLiquidityAddition, and isAllowedLiquidityBps.

## test_Fork_NonOwner_Access

Purpose: Test that non-owners cannot call restricted functions.
Steps:
Attempt to call finalize, cancel, withdraw, pause, unpause, extendClaimDeadline, and rescueTokens as a non-owner.
Assertions:
All calls revert with Ownable: caller is not the owner.
Rationale: Ensures onlyOwner modifier works correctly.

## test_Fork_Receive_ETH

Purpose: Test the receive function for ETH contributions.
Steps:
Create an ETH presale.
Send ETH directly to the contract (not via contribute).
Verify contribution is recorded.
Assertions:
ETH is recorded as a contribution.
Contribution and Purchase events are emitted.
Non-zero ETH contributions are accepted.
Rationale: Tests the receive fallback function.

## test_Fork_Zero_Amount_Contribution

Purpose: Test zero-amount contributions.
Steps:
Attempt to call contribute with 0 ETH.
Attempt to call contributeStablecoin with 0 amount.
Assertions:
Both calls revert with ZeroAmount.
Rationale: Tests validation in \_validateCurrencyAndAmount.
Implementation Notes

forge script script/DeployPresale.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv

forge script script/CreatePresale.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv

forge script script/DeployMyToken.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv

forge script --tc script/FinalizePresaleScript.s.sol --rpc-url $BASE_MAINNET_HTTPS --private-key $PRIVATE_KEY

# To load the variables in the .env file

source .env

# To get the USDT balance of Binance

cast balance --private-key $PRIVATE_KEY --rpc-url $RPC_URL

// Future tests to consider:
// - test_Fork_FullCycle_ERC20_Presale() ||
// - test_Fork_Refund_SoftCapNotMet() ||
// - test_Fork_CancelPresale_And_Refund()
// - test_Fork_Whitelist_Merkle_Contribution()
// - test_Fork_Whitelist_NFT_Contribution()
// - test_Fork_LeftoverTokens_Burn()
// - test_Fork_LeftoverTokens_VestForOwner()
// - test_Fork_ClaimPeriodExpired()
