## 🧪 **Test Plan for Presale Platform**

---

### 🔹 **1. PresaleFactory.sol**

#### ✅ Basic Functionality

- [ ] Deploys successfully with correct fee and token. Test successful deployment: Verify creationFee, feeToken, and liquidityLocker are set correctly.
- [ ] Can create a presale with valid parameters and emits `PresaleCreated`.
- [ ] Tracks presale addresses correctly.
- [ ] Returns correct presale count from `getPresaleCount()`.
- Test ownership: Confirm the deployer is the owner using owner()

Presale Creation
Test successful presale creation with ETH fee: Pay the creationFee in ETH, check the presale address is added to presales, and verify the PresaleCreated event.

Test successful presale creation with ERC20 fee: Pay the creationFee in a mock ERC20 token, verify the transfer and event emission.

Test insufficient ETH fee: Send less than creationFee in ETH, expect InsufficientFee revert.

Test insufficient ERC20 fee: Approve less than creationFee, expect InsufficientFee revert.

Test zero address inputs: Pass address(0) for \_token, \_weth, or \_router, expect revert (handled in Presale constructor).

Test presale count: Create multiple presales and check getPresaleCount() increments correctly.

#### 💸 Fee Handling

- [ ] Reverts if ETH fee is insufficient.
- [ ] Transfers ERC20 fee if specified.
- [ ] Owner can successfully withdraw ETH fees.
- [ ] Owner can successfully withdraw ERC20 fees.
- [ ] Reverts if `setCreationFee(0)` is called.

Fee Management
Test setCreationFee: As owner, update creationFee, verify the new value.

Test setCreationFee zero value: Attempt to set creationFee to 0, expect ZeroFee revert.

Test setCreationFee non-owner: As a non-owner, attempt to update creationFee, expect revert.

Test withdrawFees ETH: Send ETH to the contract (e.g., via presale creation), call withdrawFees, verify owner receives funds.

Test withdrawFees ERC20: Send ERC20 tokens to the contract, call withdrawFees, verify owner receives tokens.

Test withdrawFees non-owner: As a non-owner, attempt to call withdrawFees, expect revert.

#### 🔒 Access Control

- [ ] Only owner can call `setCreationFee()`.
- [ ] Only owner can call `withdrawFees()`.

#### 🛠 Optional (if implemented)

- [ ] Whitelisted addresses can create presale.
- [ ] Reverts if non-whitelisted address tries to create.
- [ ] Can update and return `feeRecipient`.

---

### 🔹 **2. Presale.sol**

#### 🔧 Deployment / Initialization

- [ ] Initializes correctly with provided parameters.
- [ ] Rejects deployment with invalid caps or dates.

Test successful deployment: Deploy with valid parameters, verify pool struct fields (e.g., token, uniswapV2Router02, options).

Test invalid initialization: Pass address(0) for \_weth, \_token, \_uniswapV2Router02, or \_liquidityLocker, expect InvalidInitialization revert.

Test pool validation: Test \_prevalidatePool with invalid options (e.g., tokenDeposit = 0, hardCap = 0, start > end, liquidityBps < 5100), expect revert.

#### 📥 Token Deposit

- [ ] Creator can deposit exact number of tokens.
- [ ] Reverts if insufficient allowance.
- [ ] Reverts if deposit is called by non-creator.
- [ ] `calculateTotalTokensNeeded()` returns correct value.

Test successful deposit: As owner, approve and call deposit(), verify tokens transfer, state changes to 2, and Deposit event is emitted.

Test deposit wrong state: Call deposit() after state changes (e.g., post-finalization), expect InvalidState revert.

Test deposit non-owner: As a non-owner, call deposit(), expect revert.

Test deposit insufficient approval: Approve less than tokenDeposit, expect ERC20 transfer revert.

#### 💰 Contributions

- [ ] Accepts ETH within time window.
- [ ] Accepts stablecoin if configured.
- [ ] Reverts if before start or after end time.
- [ ] Rejects contributions after hard cap is reached.
- [ ] Tracks user contributions and token allocation.

Test successful ETH contribution: Send ETH via contribute() or receive(), verify weiRaised, contributions, and Contribution event.

Test ETH contribution paused: Pause contract, attempt contribution, expect ContractPaused revert.

Test ETH contribution wrong currency: Set currency to an ERC20, send ETH, expect ETHNotAccepted revert.

Test ETH contribution inactive: Call before deposit() (state 1) or after finalize() (state 4), expect NotActive revert.

Test ETH contribution hard cap exceeded: Send ETH exceeding hardCap, expect HardCapExceeded revert.

Test ETH contribution below minimum: Send less than min, expect BelowMinimumContribution revert.

Test ETH contribution exceeds maximum: Send more than max for a single user, expect ExceedsMaximumContribution revert.

Test ETH contribution whitelist: Enable whitelist, attempt contribution from non-whitelisted address, expect NotWhitelisted revert.

Test ETH contribution timing: Warp time before start or after end, expect NotInPurchasePeriod revert.

Test successful stablecoin contribution: Approve and call contributeStablecoin(), verify weiRaised and token transfer.

Test stablecoin contribution wrong currency: Set currency to address(0), call contributeStablecoin(), expect StablecoinNotAccepted revert.

Test stablecoin contribution edge cases: Similar to ETH (paused, inactive, caps, whitelist, timing).

#### 🔁 Refunds (Soft Cap not met or cancelation)

- [ ] Contributors can claim refund if soft cap not met.
- [ ] Creator can cancel presale.
- [ ] Tokens refunded to creator after cancelation.
- [ ] Reverts if trying to refund twice or when not eligible.

#### ✅ Finalization (Soft Cap met)

- [ ] Creator can finalize only after end and soft cap met.
- [ ] LP tokens created and sent to LiquidityLocker.
- [ ] Funds split correctly between liquidity and owner.
- [ ] Extra unsold tokens returned to creator (if any).

Test successful finalization: Meet softCap, call finalize(), verify liquidity added, LP tokens locked, ownerBalance set, and Finalized event.

Test finalization below soft cap: Raise less than softCap, expect SoftCapNotReached revert.

Test finalization wrong state: Call in state 1 or 4, expect InvalidState revert.

Test finalization non-owner: As non-owner, expect revert.

Test finalization slippage: Mock Uniswap to return less than minimum amounts, expect revert.

Test successful cancellation: Call cancel() before finalization, verify tokens returned and Cancel event.

Test cancellation wrong state: Call after finalization, expect InvalidState revert.

Test cancellation non-owner: As non-owner, expect revert.

#### 🪙 Claiming Tokens

- [ ] Contributors can claim tokens after finalize.
- [ ] Reverts if claim is called twice.

Test successful claim: After finalization, contributor claims tokens, verify transfer and TokenClaim event.

Test claim before finalization: Call in state 2, expect InvalidState revert.

Test claim after deadline: Warp past claimDeadline, expect ClaimPeriodExpired revert.

Test claim no contribution: Non-contributor calls, expect NoTokensToClaim revert.

Test claim insufficient balance: Reduce contract token balance, expect InsufficientTokenBalance revert.

Refunding
Test successful refund: After cancellation or soft cap failure, contributor calls refund(), verify funds returned and Refund event.

Test refund no contribution: Non-contributor calls, expect NoFundsToRefund revert.

Test refund insufficient balance: Reduce contract balance, expect InsufficientContractBalance revert.

Test refund wrong state: Call during active presale, expect NotRefundable revert.

Withdrawal
Test successful withdrawal: After finalization, owner withdraws ownerBalance, verify transfer and Withdrawn event.

Test withdrawal no funds: Call with ownerBalance = 0, expect NoFundsToRefund revert.

Test withdrawal non-owner: As non-owner, expect revert.

Rescue Tokens
Test successful rescue: Owner rescues unrelated tokens, verify transfer and TokensRescued event.

Test rescue presale tokens: Attempt to rescue presale tokens before cancellation, expect CannotRescuePresaleTokens revert.

Test rescue non-owner: As non-owner, expect revert.

Whitelist
Test toggle whitelist: Enable/disable whitelist, verify WhitelistToggled event.

Test update whitelist: Add/remove addresses, verify WhitelistUpdated events and mapping.

Test whitelist non-owner: As non-owner, expect revert.

Pause/Unpause
Test pause: Owner pauses, verify Paused event and state.

Test unpause: Owner unpauses, verify Unpaused event and state.

Test pause/unpause non-owner: As non-owner, expect revert.

View Functions
Test calculateTotalTokensNeeded: Verify calculation matches presale and liquidity token amounts.

Test userTokens: Check token allocation for contributors.

Test contributor tracking: Verify getContributorCount(), getContributors(), getTotalContributed(), and getContribution().

---

### 🔹 **3. LiquidityLocker.sol**

#### 🔒 Locking

- [ ] Only owner of lock can initiate a lock.
- [ ] LP tokens are held correctly until `unlockTime`.
      Test successful deployment: Verify owner is set correctly.
      Test successful lock: Owner locks tokens, verify locks array and LiquidityLocked event.

Test lock invalid token: Pass address(0), expect InvalidTokenAddress revert.

Test lock zero amount: Pass 0, expect ZeroAmount revert.

Test lock invalid time: Pass past timestamp, expect InvalidUnlockTime revert.

Test lock non-owner: As non-owner, expect revert.

#### 🔓 Unlocking

- [ ] Reverts if unlocking before `unlockTime`.
- [ ] Allows withdrawal after unlock by the lock owner.
- [ ] Reverts if anyone else tries to withdraw.
      Test successful withdrawal: Lock tokens, warp past unlockTime, withdraw as lock owner, verify transfer and LiquidityWithdrawn event.

Test withdraw invalid ID: Pass out-of-bounds \_lockId, expect InvalidLockId revert.

Test withdraw not owner: As non-lock-owner, expect NotLockOwner revert.

Test withdraw locked: Warp before unlockTime, expect TokensStillLocked revert.

Test withdraw zero amount: After withdrawal, attempt again, expect NoTokensToWithdraw revert.
Test getLock: Verify lock details are returned correctly.

Test lockCount: Lock multiple times, verify count increments.

---

## ⚠️ Edge Case Tests

- [ ] Contribution right at hard cap (boundary case).
- [ ] Contribution just before/after `start` or `end`.
- [ ] Refund attempt before end time.
- [ ] Finalize attempt before end time.
- [ ] Reentrancy (e.g., malicious token on claim/refund).
- [ ] Multiple presales running simultaneously.

---

## 🧪 Test Environment Suggestions

- Use **Foundry** (ultra fast) or **Hardhat**.
- Use **mainnet forking** to simulate actual tokens (WETH, USDC).
- Test both ETH and ERC20 fee modes.
- Write **fixtures** for reusable setup (deploy contracts, create presale).
- Use `time.increaseTo()` to simulate future timestamps.
