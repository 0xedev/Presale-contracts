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
