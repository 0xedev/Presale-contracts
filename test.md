### 🔹 1. PresaleFactory.sol

#### 💸 House Percentage

- [ ] Sets initial `housePercentage` and `houseAddress` correctly.
- [ ] Updates `housePercentage` via `setHousePercentage` (owner-only).
- [ ] Updates `houseAddress` via `setHouseAddress` (owner-only).
- [ ] Reverts if `housePercentage` > 5000.
- [ ] Reverts if `houseAddress` is zero when `housePercentage` > 0.
- [ ] Passes `housePercentage` and `houseAddress` to new presale contracts.

### 🔹 2. Presale.sol

#### 🛠 Leftover Token Handling

- [ ] Returns all tokens to creator on `cancel`.
- [ ] Returns unsold tokens to creator if `leftoverTokenOption = 0` on `finalize`.
- [ ] Burns unsold tokens if `leftoverTokenOption = 1` on `finalize`.
- [ ] Vests unsold tokens if `leftoverTokenOption = 2` on `finalize`.
- [ ] Reverts for invalid `leftoverTokenOption` (> 2).
- [ ] Correctly handles zero unsold tokens.

#### 🔒 Liquidity BPS

- [ ] Reverts if `liquidityBps` < 5000.
- [ ] Reverts if `liquidityBps` not in [5000, 6000, 7000, 8000, 9000, 10000].
- [ ] Accepts valid `liquidityBps` values (5000, 6000, 7000, 8000, 9000, 10000).

#### 💸 House Percentage

- [ ] Distributes factory’s `housePercentage` of contributions to `houseAddress` on `finalize`.
- [ ] Correctly adjusts `ownerBalance` after house distribution.
- [ ] Handles zero `housePercentage` correctly.
- [ ] Uses immutable `housePercentage` and `houseAddress` set by factory.

#### ⚠️ Edge Cases

- [ ] Leftover tokens with full hard cap reached (no unsold tokens).
- [ ] Leftover tokens with partial contributions.
- [ ] Cancel with no contributions.
- [ ] House percentage of 0 or 5000.
- [ ] Liquidity BPS boundary values (5000, 10000).
- [ ] Multiple presales with different house percentages (updated via factory).

forge script script/DeployPresale.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
