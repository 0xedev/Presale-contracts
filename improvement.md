#### Leftover Token Handling

1. ❌ **Test LeftoverTokenOption Burn**: Set `leftoverTokenOption=1` (burn) and verify leftover tokens are burned (sent to `0x0` or reduced supply).
2. ❌ **Test LeftoverTokenOption Keep**: Set `leftoverTokenOption=2` (keep in contract) and verify tokens remain in `Presale` contract.
3. ❌ **Test No Leftover Tokens**: Contribute `hardCap` and set high `liquidityBps` to consume all tokens, verify no leftovers.

#### Whitelist and Merkle Root Tests

1. ❌ **Test Multiple Whitelisted Users**: Add multiple users to Merkle tree and verify contributions succeed with valid proofs.
2. ❌ **Test Invalid Merkle Proof**: Provide incorrect proof for a whitelisted user (should revert with `NotWhitelisted`).
3. ❌ **Test Merkle Root Update**: Update Merkle root mid-presale and verify new whitelist applies.
4. ❌ **Test Non-Whitelisted Presale**: Set empty Merkle root and verify all users can contribute.

#### Security Tests

1. ❌ **Test Reentrancy in Contribute**: Simulate reentrant call in `contribute` (requires mock malicious contract) to ensure protection.
2. ❌ **Test Reentrancy in Claim**: Simulate reentrant call in `claim` to verify token distribution safety.
3. ❌ **Test Unauthorized Access**: Attempt `finalize`, `cancel`, or `setMerkleRoot` from non-owner (should revert with `OwnableUnauthorizedAccount`).
4. ❌ **Test Token Transfer Failure**: Use a mock token that reverts on `transfer` or `transferFrom` to ensure presale handles failures.

#### Gas and Optimization Tests

1. ❌ **Test High Contribution Count**: Simulate 100 users contributing small amounts to stress `_distributeTokens` and gas usage.
2. ❌ **Test Large Token Deposit**: Set `tokenDeposit` to a very high value (e.g., 10^30) and verify no overflow in calculations.
3. ❌ **Test Struct Gas Efficiency**: Compare gas usage of `_liquify`, `_addLiquidityETH`, `_handleLeftoverTokens`, `_distributeTokens` with and without structs.

#### Failure and Revert Tests

1. ❌ **Test Insufficient Token Deposit**: Deposit less than required tokens (based on `presaleRate` and `hardCap`) and verify `deposit` reverts.
2. ❌ **Test Router Failure**: Mock `MockRouter` to revert in `addLiquidityETH` and verify `_liquify` handles failure gracefully.
3. ❌ **Test SoftCap Not Met Finalize**: Attempt `finalize` with contributions below `softCap` (should revert with `SoftCapNotReached`).
4. ❌ **Test Claim Without Contribution**: Call `claim` from a user with 0 contributions (should revert or return 0 tokens).

#### Edge Case Parameter Tests

1. ❌ **Test Zero Duration Presale**: Set `start=end` and verify contributions and finalization work.
2. ❌ **Test Zero Lockup Duration**: Set `lockupDuration=0` and verify LP tokens are immediately withdrawable.
3. ❌ **Test Invalid Presale Options**: Pass invalid `PresaleOptions` (e.g., `hardCap < softCap`, `presaleRate=0`) and verify constructor reverts.
4. ❌ **Test Max Token Decimals**: Use a token with 0 or 36 decimals and verify calculations in `_distributeTokens` are correct.
