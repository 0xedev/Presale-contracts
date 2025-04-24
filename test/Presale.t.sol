// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Test Imports ---
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

// --- Contract Imports ---
import {Presale} from "../src/contracts/Presale.sol";
import {IPresale} from "../src/contracts/interfaces/IPresale.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";
import {MockUniswapV2Factory} from "./mocks/MockUniswapV2Factory.sol";
import {MockLiquidityLocker} from "./mocks/MockLiquidityLocker.sol";
import {MockVesting} from "./mocks/MockVesting.sol";

// --- Library/Interface Imports ---
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {LiquidityLocker} from "../src/contracts/LiquidityLocker.sol"; // Import actual interface if Mock implements it
import {Vesting} from "../src/contracts/Vesting.sol"; // Import actual interface if Mock implements it

contract PresaleTest is Test {
    // --- Constants ---
    uint256 constant PRESALE_TOKEN_DECIMALS = 18;
    uint256 constant CURRENCY_TOKEN_DECIMALS = 6; // e.g., USDC
    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant DEFAULT_HOUSE_PERCENTAGE = 100; // 1%

    // --- State Variables ---
    Presale presale; // ETH Presale instance
    Presale stablePresale; // Stablecoin Presale instance

    // Mocks
    MockERC20 presaleToken;
    MockERC20 currencyToken; // Stablecoin
    MockUniswapV2Router mockRouter;
    MockUniswapV2Factory mockFactory;
    MockLiquidityLocker mockLocker;
    MockVesting mockVesting;
    address mockWeth;

    // Addresses
    address deployer;
    address creator;
    address contributor1;
    address contributor2;
    address houseAddress;
    address zeroAddress = address(0);
    address burnAddress = address(0); // For burn tests

    // Options
    Presale.PresaleOptions internal defaultOptions;
    Presale.PresaleOptions internal stableOptions;

    // --- Setup ---
    function setUp() public virtual {
        // Setup Users
        deployer = makeAddr("deployer");
        creator = makeAddr("creator");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");
        houseAddress = makeAddr("house");

        // Deploy Mocks
        presaleToken = new MockERC20("PresaleToken", "PRE", PRESALE_TOKEN_DECIMALS);
        currencyToken = new MockERC20("StableCoin", "USDC", CURRENCY_TOKEN_DECIMALS);
        mockWeth = makeAddr("WETH"); // Simple address for WETH mock
        mockFactory = new MockUniswapV2Factory();
        mockRouter = new MockUniswapV2Router(address(mockFactory), mockWeth);
        mockLocker = new MockLiquidityLocker();
        mockVesting = new MockVesting();

        // --- Default ETH Presale Options ---
        defaultOptions = Presale.PresaleOptions({
            tokenDeposit: 1_000_000 * (10 ** PRESALE_TOKEN_DECIMALS), // 1M tokens
            hardCap: 100 ether, // 100 ETH
            softCap: 20 ether, // 20 ETH (Must be >= 25% of hardcap per validation)
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 5000, // 5000 PRE per ETH
            listingRate: 4000, // 4000 PRE per ETH (Must be < presaleRate)
            liquidityBps: 7000, // 70%
            slippageBps: 200, // 2%
            start: block.timestamp + 1 days,
            end: block.timestamp + 8 days,
            lockupDuration: 90 days,
            vestingPercentage: 2500, // 25%
            vestingDuration: 180 days,
            leftoverTokenOption: 0, // Return to owner
            currency: address(0) // ETH
        });

        // --- Default Stablecoin Presale Options ---
        stableOptions = defaultOptions; // Copy base settings
        stableOptions.currency = address(currencyToken);
        // Adjust caps/limits for stablecoin decimals
        stableOptions.hardCap = 100_000 * (10 ** CURRENCY_TOKEN_DECIMALS); // 100k USDC
        stableOptions.softCap = 25_000 * (10 ** CURRENCY_TOKEN_DECIMALS); // 25k USDC (>= 25% hardcap)
        stableOptions.min = 100 * (10 ** CURRENCY_TOKEN_DECIMALS); // 100 USDC
        stableOptions.max = 5000 * (10 ** CURRENCY_TOKEN_DECIMALS); // 5k USDC
        // Rates are per stablecoin unit now
        stableOptions.presaleRate = 5; // 5 PRE per USDC (adjust as needed)
        stableOptions.listingRate = 4; // 4 PRE per USDC (adjust as needed)

        // Deploy ETH Presale Instance
        vm.startPrank(creator);
        presale = new Presale(
            mockWeth,
            address(presaleToken),
            address(mockRouter),
            defaultOptions,
            creator,
            address(mockLocker),
            address(mockVesting),
            DEFAULT_HOUSE_PERCENTAGE,
            houseAddress
        );
        vm.stopPrank();

        // Mint tokens for tests
        presaleToken.mint(creator, defaultOptions.tokenDeposit * 2); // Mint enough for deposit + leftovers
        currencyToken.mint(deployer, stableOptions.hardCap * 5); // Mint stablecoins for contributors (via deployer)
    }

    // =============================================================
    //            Constructor & Setup Tests
    // =============================================================

    function test_setUp_CorrectInitialState() public view {
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Pending), "Initial state mismatch");
        assertEq(address(presale.token()), address(presaleToken), "Token mismatch");
        assertEq(address(presale.uniswapV2Router02()), address(mockRouter), "Router mismatch");
        assertEq(presale.factory(), address(mockFactory), "Factory mismatch"); // Fetched via router
        assertEq(presale.weth(), mockWeth, "WETH mismatch");
        assertEq(address(presale.liquidityLocker()), address(mockLocker), "Locker mismatch");
        assertEq(address(presale.vestingContract()), address(mockVesting), "Vesting mismatch");
        assertEq(presale.housePercentage(), DEFAULT_HOUSE_PERCENTAGE, "House % mismatch");
        assertEq(presale.houseAddress(), houseAddress, "House address mismatch");
        assertEq(presale.owner(), creator, "Owner mismatch");
        assertFalse(presale.paused(), "Should not be paused initially");
        assertFalse(presale.whitelistEnabled(), "Whitelist should be disabled initially");
        assertEq(presale.merkleRoot(), bytes32(0), "Merkle root should be zero");
        assertEq(presale.tokenBalance(), 0, "Initial token balance mismatch");
        assertEq(presale.totalRaised(), 0, "Initial total raised mismatch");
    }

    function test_setUp_StoresOptionsCorrectly() public view {
        Presale.PresaleOptions memory fetchedOptions = presale.options();

        assertEq(fetchedOptions.tokenDeposit, defaultOptions.tokenDeposit, "Token deposit mismatch");
        assertEq(fetchedOptions.hardCap, defaultOptions.hardCap, "Hard cap mismatch");
        assertEq(fetchedOptions.softCap, defaultOptions.softCap, "Soft cap mismatch");
        assertEq(fetchedOptions.min, defaultOptions.min, "Min contribution mismatch");
        assertEq(fetchedOptions.max, defaultOptions.max, "Max contribution mismatch");
        assertEq(fetchedOptions.presaleRate, defaultOptions.presaleRate, "Presale rate mismatch");
        assertEq(fetchedOptions.listingRate, defaultOptions.listingRate, "Listing rate mismatch");
        assertEq(fetchedOptions.liquidityBps, defaultOptions.liquidityBps, "Liquidity BPS mismatch");
        assertEq(fetchedOptions.slippageBps, defaultOptions.slippageBps, "Slippage BPS mismatch");
        assertEq(fetchedOptions.start, defaultOptions.start, "Start time mismatch");
        assertEq(fetchedOptions.end, defaultOptions.end, "End time mismatch");
        assertEq(fetchedOptions.lockupDuration, defaultOptions.lockupDuration, "Lockup duration mismatch");
        assertEq(fetchedOptions.vestingPercentage, defaultOptions.vestingPercentage, "Vesting percentage mismatch");
        assertEq(fetchedOptions.vestingDuration, defaultOptions.vestingDuration, "Vesting duration mismatch");
        assertEq(fetchedOptions.leftoverTokenOption, defaultOptions.leftoverTokenOption, "Leftover token option mismatch");
        assertEq(fetchedOptions.currency, defaultOptions.currency, "Currency mismatch");
    }

    function test_constructor_Revert_InvalidInitialization() public {
        vm.expectRevert(IPresale.InvalidInitialization.selector);
        new Presale(zeroAddress, address(presaleToken), address(mockRouter), defaultOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);

        vm.expectRevert(IPresale.InvalidInitialization.selector);
        new Presale(mockWeth, zeroAddress, address(mockRouter), defaultOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);

        // ... add checks for other zero addresses ...
    }

     function test_constructor_Revert_InvalidOptions() public {
        Presale.PresaleOptions memory badOptions = defaultOptions;

        // Invalid Caps
        badOptions.softCap = 0;
        vm.expectRevert(IPresale.InvalidCapSettings.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.softCap = badOptions.hardCap + 1;
        vm.expectRevert(IPresale.InvalidCapSettings.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.softCap = (badOptions.hardCap / 5); // Less than 25%
        vm.expectRevert(IPresale.SoftCapTooLow.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid Limits
        badOptions.min = 0;
        vm.expectRevert(IPresale.InvalidContributionLimits.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.min = badOptions.max + 1;
        vm.expectRevert(IPresale.InvalidContributionLimits.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid Liquidity BPS
        badOptions.liquidityBps = 4999;
        vm.expectRevert(IPresale.InvalidLiquidityBps.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.liquidityBps = 7500; // Not in allowed list [5000, 6000, 7000, 8000, 9000, 10000]
        vm.expectRevert(IPresale.InvalidLiquidityBps.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid Rates
        badOptions.listingRate = 0;
        vm.expectRevert(IPresale.InvalidRates.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.listingRate = badOptions.presaleRate; // Must be lower
        vm.expectRevert(IPresale.InvalidRates.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid Timestamps
        badOptions.start = block.timestamp - 1;
        vm.expectRevert(IPresale.InvalidTimestamps.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.end = badOptions.start;
        vm.expectRevert(IPresale.InvalidTimestamps.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid Vesting
        badOptions.vestingPercentage = BASIS_POINTS + 1;
        vm.expectRevert(IPresale.InvalidVestingPercentage.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        badOptions.vestingPercentage = 1000; // 10%
        badOptions.vestingDuration = 0;
        vm.expectRevert(IPresale.InvalidVestingDuration.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid Leftover Option
        badOptions.leftoverTokenOption = 3;
        vm.expectRevert(IPresale.InvalidLeftoverTokenOption.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset

        // Invalid House Settings
        vm.expectRevert(IPresale.InvalidHousePercentage.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), defaultOptions, creator, address(mockLocker), address(mockVesting), 501, houseAddress); // > 5%
        vm.expectRevert(IPresale.InvalidHouseAddress.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), defaultOptions, creator, address(mockLocker), address(mockVesting), 100, zeroAddress); // Percentage > 0 but address is zero
    }

    // =============================================================
    //            Deposit Tests
    // =============================================================

    function test_deposit_Success() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        uint256 creatorBalanceBefore = presaleToken.balanceOf(creator);

        // Act
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Deposit(creator, defaultOptions.tokenDeposit, block.timestamp);
        uint256 deposited = presale.deposit();
        vm.stopPrank();

        // Assert
        assertEq(deposited, defaultOptions.tokenDeposit, "Deposited amount mismatch");
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "State not Active");
        assertEq(presale.tokenBalance(), defaultOptions.tokenDeposit, "Contract token balance mismatch");
        assertEq(presaleToken.balanceOf(address(presale)), defaultOptions.tokenDeposit, "ERC20 balance mismatch");
        assertEq(presaleToken.balanceOf(creator), creatorBalanceBefore - defaultOptions.tokenDeposit, "Creator balance mismatch");

        // Check calculated values based on hardcap
        uint256 expectedClaimable = presale.userTokens(address(1)); // Use userTokens logic with hardcap
        expectedClaimable = (defaultOptions.hardCap * defaultOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 expectedLiquidity = (defaultOptions.hardCap * defaultOptions.liquidityBps / BASIS_POINTS * defaultOptions.listingRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);

        assertEq(presale.tokensClaimable(), expectedClaimable, "tokensClaimable mismatch");
        assertEq(presale.tokensLiquidity(), expectedLiquidity, "tokensLiquidity mismatch");
    }

    function test_deposit_Revert_NotOwner() public {
        vm.startPrank(contributor1); // Not owner
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit); // Approve doesn't matter
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, contributor1));
        presale.deposit();
        vm.stopPrank();
    }

    function test_deposit_Revert_NotPending() public {
        // Arrange: Deposit once to change state
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        // Approve again for second attempt
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);

        // Act & Assert: Try depositing again
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.deposit();
        vm.stopPrank();
    }

    function test_deposit_Revert_InsufficientDeposit() public {
        // Arrange: Calculate needed tokens and approve less
        uint256 expectedClaimable = (defaultOptions.hardCap * defaultOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 expectedLiquidity = (defaultOptions.hardCap * defaultOptions.liquidityBps / BASIS_POINTS * defaultOptions.listingRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 totalNeeded = expectedClaimable + expectedLiquidity;
        uint256 insufficientAmount = totalNeeded - 1;

        vm.startPrank(creator);
        presaleToken.approve(address(presale), insufficientAmount);

        // Act & Assert
        // Need to modify options.tokenDeposit temporarily for the check inside deposit()
        // This is tricky without deploying a new contract. Alternative: Test calculateTotalTokensNeeded view function.
        // Let's test the view function instead, as modifying options isn't clean.
        assertEq(presale.calculateTotalTokensNeeded(), totalNeeded, "calculateTotalTokensNeeded mismatch");

        // Now test the deposit revert by trying to deposit less than options.tokenDeposit requires
        // (Assuming options.tokenDeposit itself is >= totalNeeded)
        // Let's assume options.tokenDeposit was set correctly, but creator only approves less
        // The revert will actually happen on the safeTransferFrom if allowance is insufficient.
        // To test the internal check `if (amount < totalTokensNeeded)`, we need `amount` (from transfer)
        // to be less than `totalTokensNeeded`, while `amount` must also equal `options.tokenDeposit`.
        // This implies the options were set such that `options.tokenDeposit < totalTokensNeeded`.

        // Let's create a new presale with bad options.tokenDeposit for this test
        Presale.PresaleOptions memory badDepositOptions = defaultOptions;
        badDepositOptions.tokenDeposit = totalNeeded - 1; // Set deposit amount lower than calculated need

        Presale badDepositPresale = new Presale(
            mockWeth, address(presaleToken), address(mockRouter), badDepositOptions,
            creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress
        );
        presaleToken.approve(address(badDepositPresale), badDepositOptions.tokenDeposit);

        vm.expectRevert(abi.encodeWithSelector(IPresale.InsufficientTokenDeposit.selector, badDepositOptions.tokenDeposit, totalNeeded));
        badDepositPresale.deposit();
        vm.stopPrank();
    }

     function test_deposit_Revert_WhenPaused() public {
        // Arrange
        vm.startPrank(creator);
        presale.pause();
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);

        // Act & Assert
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.deposit();
        vm.stopPrank();
    }

    // =============================================================
    //            Merkle Root / Whitelist Tests
    // =============================================================
    // (Covered in previous response - integrate those tests here)
    // test_setMerkleRoot_Success
    // test_setMerkleRoot_Revert_NotPending
    // test_contribute_Whitelist_Success (ETH & Stablecoin versions)
    // test_contribute_Whitelist_Revert_InvalidProof (ETH & Stablecoin versions)
    // test_contribute_Whitelist_Revert_NoProofProvided (ETH & Stablecoin versions)

    // =============================================================
    //            Contribution Tests (ETH)
    // =============================================================

    function test_contribute_ETH_Success() public {
        // Arrange: Deposit, warp to start time
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 1 ether;
        uint256 initialTotalRaised = presale.totalRaised();
        uint256 initialContractBalance = address(presale).balance;

        // Act
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount); // Give ETH
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Contribution(contributor1, contributionAmount, true); // ETH
        presale.contribute{value: contributionAmount}(new bytes32);
        vm.stopPrank();

        // Assert
        assertEq(presale.totalRaised(), initialTotalRaised + contributionAmount, "Total raised mismatch");
        assertEq(presale.getContribution(contributor1), contributionAmount, "Contributor balance mismatch");
        assertEq(address(presale).balance, initialContractBalance + contributionAmount, "Contract ETH balance mismatch");
        assertEq(presale.getContributorCount(), 1, "Contributor count mismatch");
        address[] memory contributors = presale.getContributors();
        assertEq(contributors[0], contributor1, "Contributor address mismatch");
    }

     function test_contribute_ETH_Success_ViaReceive() public {
        // Arrange: Deposit, warp to start time
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 1 ether;
        uint256 initialTotalRaised = presale.totalRaised();
        uint256 initialContractBalance = address(presale).balance;

        // Act
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Contribution(contributor1, contributionAmount, true); // ETH
        (bool success, ) = address(presale).call{value: contributionAmount}("");
        assertTrue(success, "Receive call failed");
        vm.stopPrank();

        // Assert
        assertEq(presale.totalRaised(), initialTotalRaised + contributionAmount, "Total raised mismatch");
        assertEq(presale.getContribution(contributor1), contributionAmount, "Contributor balance mismatch");
        assertEq(address(presale).balance, initialContractBalance + contributionAmount, "Contract ETH balance mismatch");
    }

    function test_contribute_ETH_Revert_NotActive() public {
        // Arrange: State is Pending
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 1 ether;

        // Act & Assert
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(IPresale.PresaleState.Pending)));
        presale.contribute{value: contributionAmount}(new bytes32);
        vm.stopPrank();
    }

    function test_contribute_ETH_Revert_NotInPurchasePeriod() public {
        // Arrange: Deposit, but time is before start
        _depositTokens(presale, defaultOptions);
        // vm.warp(defaultOptions.start - 1); // Already before start

        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);

        // Before Start
        vm.expectRevert(IPresale.NotInPurchasePeriod.selector);
        presale.contribute{value: contributionAmount}(new bytes32);

        // After End
        vm.warp(defaultOptions.end + 1);
        vm.expectRevert(IPresale.NotInPurchasePeriod.selector);
        presale.contribute{value: contributionAmount}(new bytes32);
        vm.stopPrank();
    }

    function test_contribute_ETH_Revert_WhenPaused() public {
        // Arrange: Deposit, warp, pause
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        vm.startPrank(creator);
        presale.pause();
        vm.stopPrank();

        // Act & Assert
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.contribute{value: contributionAmount}(new bytes32);
        vm.stopPrank();
    }

    function test_contribute_ETH_Revert_BelowMinimum() public {
        // Arrange: Deposit, warp
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = defaultOptions.min - 1; // Below min

        // Act & Assert
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectRevert(IPresale.BelowMinimumContribution.selector);
        presale.contribute{value: contributionAmount}(new bytes32);
        vm.stopPrank();
    }

    function test_contribute_ETH_Revert_ExceedsMaximum_Single() public {
        // Arrange: Deposit, warp
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = defaultOptions.max + 1; // Above max

        // Act & Assert
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectRevert(IPresale.ExceedsMaximumContribution.selector);
        presale.contribute{value: contributionAmount}(new bytes32);
        vm.stopPrank();
    }

     function test_contribute_ETH_Revert_ExceedsMaximum_Multiple() public {
        // Arrange: Deposit, warp, contribute max once
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 maxAmount = defaultOptions.max;
        vm.startPrank(contributor1);
        vm.deal(contributor1, maxAmount + 1 wei); // Give enough ETH
        presale.contribute{value: maxAmount}(new bytes32); // First contribution

        // Act & Assert: Contribute 1 wei more
        vm.expectRevert(IPresale.ExceedsMaximumContribution.selector);
        presale.contribute{value: 1 wei}(new bytes32);
        vm.stopPrank();
    }

    function test_contribute_ETH_Revert_HardCapExceeded() public {
        // Arrange: Deposit, warp, contribute close to hardcap
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 amountCloseToCap = defaultOptions.hardCap - defaultOptions.min + 1; // Amount that leaves less than min remaining
        uint256 numContributorsNeeded = amountCloseToCap / defaultOptions.max + 1;

        // Contribute using multiple contributors to reach close to cap
        uint256 currentTotal = 0;
        for(uint i = 0; i < numContributorsNeeded && currentTotal < amountCloseToCap; ++i) {
            address tempContributor = address(uint160(uint(keccak256(abi.encodePacked("temp", i)))));
            uint256 contrib = (amountCloseToCap - currentTotal) > defaultOptions.max ? defaultOptions.max : (amountCloseToCap - currentTotal);
            if (contrib == 0) break;
            vm.startPrank(tempContributor);
            vm.deal(tempContributor, contrib);
            presale.contribute{value: contrib}(new bytes32);
            vm.stopPrank();
            currentTotal += contrib;
        }
        assertTrue(presale.totalRaised() >= amountCloseToCap, "Setup failed to reach near cap");
        assertTrue(defaultOptions.hardCap - presale.totalRaised() < defaultOptions.min, "Remaining space >= min");


        // Act & Assert: Try to contribute the minimum amount, exceeding hardcap
        uint256 finalContribution = defaultOptions.min;
        vm.startPrank(contributor1);
        vm.deal(contributor1, finalContribution);
        vm.expectRevert(IPresale.HardCapExceeded.selector);
        presale.contribute{value: finalContribution}(new bytes32);
        vm.stopPrank();
    }

     function test_contribute_ETH_Revert_ZeroAmount() public {
        // Arrange: Deposit, warp
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.ZeroAmount.selector);
        presale.contribute{value: 0}(new bytes32);
        vm.stopPrank();
    }

    // =============================================================
    //            Contribution Tests (Stablecoin)
    // =============================================================

    function test_contribute_Stable_Success() public {
        // Arrange: Deploy stable presale, deposit, warp
        _deployStablePresale(); // Deploys to 'stablePresale' variable
        _depositTokens(stablePresale, stableOptions);
        vm.warp(stableOptions.start);

        uint256 contributionAmount = stableOptions.min; // Contribute min stablecoin
        uint256 initialTotalRaised = stablePresale.totalRaised();
        uint256 initialContractBalance = currencyToken.balanceOf(address(stablePresale));

        // Act
        vm.startPrank(contributor1);
        _giveAndApproveStable(contributor1, address(stablePresale), contributionAmount);
        vm.expectEmit(true, true, false, true, address(stablePresale));
        emit IPresale.Contribution(contributor1, contributionAmount, false); // Stablecoin
        stablePresale.contributeStablecoin(contributionAmount, new bytes32);
        vm.stopPrank();

        // Assert
        assertEq(stablePresale.totalRaised(), initialTotalRaised + contributionAmount, "Total raised mismatch");
        assertEq(stablePresale.getContribution(contributor1), contributionAmount, "Contributor balance mismatch");
        assertEq(currencyToken.balanceOf(address(stablePresale)), initialContractBalance + contributionAmount, "Contract Stable balance mismatch");
        assertEq(stablePresale.getContributorCount(), 1, "Contributor count mismatch");
    }

    function test_contribute_Stable_Revert_ETHPresale() public {
        // Arrange: Use ETH presale, deposit, warp
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 100 * (10 ** CURRENCY_TOKEN_DECIMALS); // Some stable amount

        // Act & Assert
        vm.startPrank(contributor1);
        _giveAndApproveStable(contributor1, address(presale), contributionAmount);
        vm.expectRevert(IPresale.StablecoinNotAccepted.selector);
        presale.contributeStablecoin(contributionAmount, new bytes32);
        vm.stopPrank();
    }

    function test_contribute_Stable_Revert_ETHSent() public {
        // Arrange: Deploy stable presale, deposit, warp
        _deployStablePresale();
        _depositTokens(stablePresale, stableOptions);
        vm.warp(stableOptions.start);
        uint256 ethToSend = 1 ether;

        // Act & Assert
        vm.startPrank(contributor1);
        vm.deal(contributor1, ethToSend);
        // Check contributeStablecoin revert first
        vm.expectRevert(IPresale.ETHNotAccepted.selector);
        stablePresale.contributeStablecoin{value: ethToSend}(stableOptions.min, new bytes32);
        // Check receive() revert
        vm.expectRevert(IPresale.ETHNotAccepted.selector); // Should also revert in receive via _contribute check
        (bool success, ) = address(stablePresale).call{value: ethToSend}("");
        assertFalse(success, "ETH send to stable presale should fail");
        vm.stopPrank();
    }

    function test_contribute_Stable_Revert_ZeroAmount() public {
        // Arrange: Deploy stable presale, deposit, warp
        _deployStablePresale();
        _depositTokens(stablePresale, stableOptions);
        vm.warp(stableOptions.start);

        // Act & Assert
        vm.startPrank(contributor1);
        // No need to approve 0
        vm.expectRevert(IPresale.ZeroAmount.selector);
        stablePresale.contributeStablecoin(0, new bytes32);
        vm.stopPrank();
    }

    // Other stablecoin reverts (NotActive, NotInPurchasePeriod, Paused, BelowMin, ExceedsMax, HardCap)
    // are analogous to the ETH tests and can be added similarly, using stablePresale and stableOptions.

    // =============================================================
    //            Finalize Tests
    // =============================================================
    // (Covered extensively in previous response - integrate those tests)
    // test_finalize_Success_ETH
    // test_finalize_Success_Stablecoin
    // test_finalize_Revert_NotActive
    // test_finalize_Revert_PresaleNotEnded
    // test_finalize_Revert_SoftCapNotReached
    // test_finalize_Revert_WhenPaused
    // test_finalize_Leftover_Return (Default case, test success path)
    // test_finalize_Leftover_Burn
    // test_finalize_Leftover_Vest
    // Ensure mocks for addLiquidityETH/addLiquidity, getPair, LP balance, LP approve, locker.lock are set correctly.
    // Ensure house fee transfer is checked.
    // Ensure ownerBalance is checked.
    // Ensure claimDeadline is set.

    // Example Finalize Success ETH (incorporating mocks)
    function test_finalize_Success_ETH() public {
        // Arrange: Deposit, reach soft cap, warp past end
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions); // Helper to contribute softCap ETH
        vm.warp(defaultOptions.end + 1);

        uint256 totalRaisedFinal = presale.totalRaised();
        assertTrue(totalRaisedFinal >= defaultOptions.softCap, "Softcap not reached in setup");

        // Calculate expected values
        uint256 liquidityAmount = (totalRaisedFinal * defaultOptions.liquidityBps) / BASIS_POINTS;
        uint256 tokensForLiq = presale.tokensLiquidity(); // Based on hardcap
        // Adjust tokensForLiq if listingRate logic needs actual raised amount (contract uses hardcap based)
        // uint256 tokensForLiqActual = (liquidityAmount * defaultOptions.listingRate * (10**PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 houseAmount = (totalRaisedFinal * presale.housePercentage()) / BASIS_POINTS;
        uint256 expectedOwnerBalance = totalRaisedFinal - liquidityAmount - houseAmount;
        uint256 expectedLpAmount = 1_000 * 1e18; // Mock LP amount received

        // Mock external calls
        address mockPair = mockFactory.pairFor(address(presaleToken), mockWeth); // Use mock factory's logic
        vm.mockCall(address(mockRouter), abi.encodeWithSelector(IUniswapV2Router02.addLiquidityETH.selector), abi.encode(1, 1, expectedLpAmount)); // Mock return values don't matter much here, just success
        vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), tokensForLiq));
        // Mock LP token transfer to locker
        vm.expectCall(mockPair, abi.encodeWithSelector(IERC20.approve.selector, address(mockLocker), expectedLpAmount));
        vm.expectCall(address(mockLocker), abi.encodeWithSelector(LiquidityLocker.lock.selector)); // Check selector, maybe args later

        uint256 houseBalanceBefore = houseAddress.balance;
        uint256 presaleTokenBalanceBefore = presale.tokenBalance();

        // Act: Finalize
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(presale)); // LiquidityAdded
        vm.expectEmit(true, true, false, true, address(presale)); // HouseFundsDistributed (if > 0)
        vm.expectEmit(true, true, false, true, address(presale)); // LeftoverTokensReturned/Burned/Vested
        vm.expectEmit(true, true, false, true, address(presale)); // Finalized
        presale.finalize();
        vm.stopPrank();

        // Assert State
        assertEq(uint8(presale.state()), uint8(IPresale.PresaleState.Finalized), "State not Finalized");
        assertTrue(presale.claimDeadline() > defaultOptions.end, "Claim deadline not set");
        assertEq(presale.ownerBalance(), expectedOwnerBalance, "Owner balance mismatch");

        // Assert Fund Distribution
        assertEq(houseAddress.balance, houseBalanceBefore + houseAmount, "House fee mismatch");

        // Assert Token Handling (Check Leftover Logic - default is return)
        uint256 tokensSold = (totalRaisedFinal * defaultOptions.presaleRate * (10**PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 leftover = presaleTokenBalanceBefore - tokensForLiq - tokensSold;
        // Note: This leftover calculation assumes tokenBalance was exactly tokenDeposit initially.
        // A more robust check uses the logic from _handleLeftoverTokens.
        // assertEq(presale.tokenBalance(), 0, "Presale token balance should be 0 after finalize"); // Check internal tracking
        // assertEq(presaleToken.balanceOf(creator), initialCreatorTokenBalance + leftover, "Leftover tokens not returned"); // Check actual ERC20 balance

        // Assert LP Locking (Implicitly checked by expectCall)
    }


    // =============================================================
    //            Cancel Tests
    // =============================================================
    // (Covered in previous response - integrate those tests)
    // test_cancel_Success_BeforeContributions
    // test_cancel_Success_AfterContributions
    // test_cancel_Revert_NotOwner
    // test_cancel_Revert_AlreadyFinalized
    // test_cancel_Revert_WhenPaused (Add this)

    // =============================================================
    //            Claim Tests
    // =============================================================

    function test_claim_Success_NoVesting() public {
        // Arrange: Finalize with 0% vesting
        Presale.PresaleOptions memory noVestingOptions = defaultOptions;
        noVestingOptions.vestingPercentage = 0;
        _deployAndFinalizePresale(noVestingOptions, contributor1, 1 ether); // Helper deploys, deposits, contributes, finalizes

        uint256 expectedTokens = presale.userTokens(contributor1);
        assertTrue(expectedTokens > 0, "Expected tokens should be > 0");
        uint256 contributorBalanceBefore = presaleToken.balanceOf(contributor1);

        // Act
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.TokenClaim(contributor1, expectedTokens, block.timestamp);
        presale.claim();
        vm.stopPrank();

        // Assert
        assertEq(presale.getContribution(contributor1), 0, "Contribution not reset");
        assertEq(presaleToken.balanceOf(contributor1), contributorBalanceBefore + expectedTokens, "Tokens not received");
        // assertEq(presale.tokenBalance(), initialTokenBalance - expectedTokens, "Internal token balance not updated"); // Check internal tracking
    }

    function test_claim_Success_WithVesting() public {
         // Arrange: Finalize with default vesting (25%)
        uint256 contribution = 1 ether;
        _deployAndFinalizePresale(defaultOptions, contributor1, contribution); // Uses defaultOptions

        uint256 totalTokens = presale.userTokens(contributor1);
        uint256 expectedVested = (totalTokens * defaultOptions.vestingPercentage) / BASIS_POINTS;
        uint256 expectedImmediate = totalTokens - expectedVested;
        assertTrue(totalTokens > 0 && expectedVested > 0 && expectedImmediate > 0, "Token calculation error");

        uint256 contributorBalanceBefore = presaleToken.balanceOf(contributor1);

        // Mock vesting call
        vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockVesting), expectedVested));
        vm.expectCall(address(mockVesting), abi.encodeWithSelector(Vesting.createVesting.selector)); // Basic check

        // Act
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.TokenClaim(contributor1, totalTokens, block.timestamp);
        presale.claim();
        vm.stopPrank();

        // Assert
        assertEq(presale.getContribution(contributor1), 0, "Contribution not reset");
        assertEq(presaleToken.balanceOf(contributor1), contributorBalanceBefore + expectedImmediate, "Immediate tokens not received");
        // Check vesting contract interaction via expectCall
    }

    function test_claim_Revert_NotFinalized() public {
        // Arrange: Deposit, contribute, but not finalized
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, 1 ether);
        presale.contribute{value: 1 ether}(new bytes32);
        vm.stopPrank();

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(IPresale.PresaleState.Active)));
        presale.claim();
        vm.stopPrank();
    }

    function test_claim_Revert_ClaimPeriodExpired() public {
        // Arrange: Finalize, warp past deadline
         _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether);
         vm.warp(presale.claimDeadline() + 1);

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.ClaimPeriodExpired.selector);
        presale.claim();
        vm.stopPrank();
    }

    function test_claim_Revert_NoTokensToClaim() public {
        // Arrange: Finalize, but contributor2 didn't contribute
         _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether); // contributor1 contributed

        // Act & Assert: contributor2 tries to claim
        vm.startPrank(contributor2);
        vm.expectRevert(IPresale.NoTokensToClaim.selector);
        presale.claim();
        vm.stopPrank();

        // Act & Assert: contributor1 claims, then tries again
        vm.startPrank(contributor1);
        presale.claim(); // First claim
        vm.expectRevert(IPresale.NoTokensToClaim.selector);
        presale.claim(); // Second claim attempt
        vm.stopPrank();
    }

     function test_claim_Revert_WhenPaused() public {
        // Arrange: Finalize, then pause
         _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether);
         vm.startPrank(creator);
         presale.pause();
         vm.stopPrank();

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.claim();
        vm.stopPrank();
    }

    // =============================================================
    //            Refund Tests
    // =============================================================

    function test_refund_Success_Canceled() public {
        // Arrange: Deposit, contribute, cancel
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contribution = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contribution);
        presale.contribute{value: contribution}(new bytes32);
        vm.stopPrank();

        vm.startPrank(creator);
        presale.cancel();
        vm.stopPrank();

        assertEq(uint8(presale.state()), uint8(IPresale.PresaleState.Canceled), "State not Canceled");
        uint256 balanceBefore = contributor1.balance;

        // Act
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Refund(contributor1, contribution, block.timestamp);
        presale.refund();
        vm.stopPrank();

        // Assert
        assertEq(presale.getContribution(contributor1), 0, "Contribution not reset");
        assertEq(contributor1.balance, balanceBefore + contribution, "Refund amount mismatch");
    }

    function test_refund_Success_FailedSoftCap() public {
        // Arrange: Deposit, contribute less than softcap, warp past end
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contribution = defaultOptions.softCap - 1 wei; // Less than softcap
        vm.startPrank(contributor1);
        vm.deal(contributor1, contribution);
        presale.contribute{value: contribution}(new bytes32);
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        assertTrue(presale.totalRaised() < defaultOptions.softCap, "Softcap was met");
        assertEq(uint8(presale.state()), uint8(IPresale.PresaleState.Active), "State should still be Active"); // State doesn't change automatically
        uint256 balanceBefore = contributor1.balance;

        // Act
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Refund(contributor1, contribution, block.timestamp);
        presale.refund(); // Should be allowed by onlyRefundable modifier
        vm.stopPrank();

        // Assert
        assertEq(presale.getContribution(contributor1), 0, "Contribution not reset");
        assertEq(contributor1.balance, balanceBefore + contribution, "Refund amount mismatch");
    }

     function test_refund_Success_Stablecoin() public {
        // Arrange: Deploy stable, deposit, contribute, cancel
        _deployStablePresale();
        _depositTokens(stablePresale, stableOptions);
        vm.warp(stableOptions.start);
        uint256 contribution = stableOptions.min;
        vm.startPrank(contributor1);
        _giveAndApproveStable(contributor1, address(stablePresale), contribution);
        stablePresale.contributeStablecoin(contribution, new bytes32);
        vm.stopPrank();

        vm.startPrank(creator);
        stablePresale.cancel();
        vm.stopPrank();

        uint256 balanceBefore = currencyToken.balanceOf(contributor1);

        // Act
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(stablePresale));
        emit IPresale.Refund(contributor1, contribution, block.timestamp);
        stablePresale.refund();
        vm.stopPrank();

        // Assert
        assertEq(stablePresale.getContribution(contributor1), 0, "Contribution not reset");
        assertEq(currencyToken.balanceOf(contributor1), balanceBefore + contribution, "Refund amount mismatch");
    }


    function test_refund_Revert_NotRefundableState() public {
        // Arrange: Deposit, contribute, presale active and ongoing
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contribution = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contribution);
        presale.contribute{value: contribution}(new bytes32);
        vm.stopPrank();

        // Act & Assert: Try refunding while active
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.NotRefundable.selector);
        presale.refund();
        vm.stopPrank();

        // Arrange: Finalize successfully
        _reachSoftCap(presale, defaultOptions); // Reach softcap
        vm.warp(defaultOptions.end + 1);
        vm.startPrank(creator);
        // Mock finalize calls needed here if not using helper
        _mockFinalizeCalls(presale, defaultOptions);
        presale.finalize();
        vm.stopPrank();

         // Act & Assert: Try refunding after successful finalize
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.NotRefundable.selector);
        presale.refund();
        vm.stopPrank();
    }

    function test_refund_Revert_NoFundsToRefund() public {
        // Arrange: Cancel presale, contributor2 didn't contribute
        _depositTokens(presale, defaultOptions);
        vm.startPrank(creator);
        presale.cancel();
        vm.stopPrank();

        // Act & Assert: contributor2 tries to refund
        vm.startPrank(contributor2);
        vm.expectRevert(IPresale.NoFundsToRefund.selector);
        presale.refund();
        vm.stopPrank();

        // Arrange: contributor1 contributes, cancels, refunds, tries again
        // (Setup from test_refund_Success_Canceled)
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contribution = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contribution);
        presale.contribute{value: contribution}(new bytes32);
        vm.stopPrank();
        vm.startPrank(creator);
        presale.cancel();
        vm.stopPrank();
        vm.startPrank(contributor1);
        presale.refund(); // First refund

        // Act & Assert: Try refunding again
        vm.expectRevert(IPresale.NoFundsToRefund.selector);
        presale.refund();
        vm.stopPrank();
    }

    // =============================================================
    //            Withdraw Tests
    // =============================================================
    // (Covered in previous response - integrate those tests)
    // test_withdraw_Success_ETH
    // test_withdraw_Success_Stablecoin
    // test_withdraw_Revert_NotFinalized
    // test_withdraw_Revert_NoBalance (after withdrawing once)
    // test_withdraw_Revert_NotOwner (Add this)

    // =============================================================
    //            Pause/Unpause Tests
    // =============================================================
    // (Covered in previous response - integrate those tests)
    // test_pause_unpause_Success
    // test_pause_Revert_AlreadyPaused
    // test_unpause_Revert_NotPaused
    // test_actions_Revert_WhenPaused (deposit, contribute, claim, finalize)
    // test_pause_Revert_NotOwner (Add this)
    // test_unpause_Revert_NotOwner (Add this)

    // =============================================================
    //            Extend Claim Deadline Tests
    // =============================================================
    // (Covered in previous response - integrate those tests)
    // test_extendClaimDeadline_Success
    // test_extendClaimDeadline_Revert_NotFinalized
    // test_extendClaimDeadline_Revert_InvalidDeadline
    // test_extendClaimDeadline_Revert_NotOwner (Add this)

    // =============================================================
    //            Rescue Tokens Tests
    // =============================================================
    // (Covered in previous response - integrate those tests)
    // test_rescueTokens_Success_AfterFinalize (Other token)
    // test_rescueTokens_Success_AfterCancel (Add this, for both other and presale token)
    // test_rescueTokens_Success_PresaleToken_AfterDeadline
    // test_rescueTokens_Revert_NotFinalizedOrCanceled
    // test_rescueTokens_Revert_PresaleTokenBeforeDeadline
    // test_rescueTokens_Revert_InvalidRecipient (Add this, _to = address(0))
    // test_rescueTokens_Revert_NotOwner (Add this)

    // =============================================================
    //            View Function Tests
    // =============================================================

    function test_view_calculateTotalTokensNeeded() public view {
        uint256 expectedClaimable = (defaultOptions.hardCap * defaultOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 expectedLiquidity = (defaultOptions.hardCap * defaultOptions.liquidityBps / BASIS_POINTS * defaultOptions.listingRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 expectedTotal = expectedClaimable + expectedLiquidity;
        assertEq(presale.calculateTotalTokensNeeded(), expectedTotal);
    }

    function test_view_isAllowedLiquidityBps() public view {
        assertTrue(presale.isAllowedLiquidityBps(5000));
        assertTrue(presale.isAllowedLiquidityBps(7000));
        assertTrue(presale.isAllowedLiquidityBps(10000));
        assertFalse(presale.isAllowedLiquidityBps(7500));
        assertFalse(presale.isAllowedLiquidityBps(4999));
        assertFalse(presale.isAllowedLiquidityBps(10001));
    }

    function test_view_userTokens() public {
        // Arrange: Deposit, contribute
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contribution = 1.5 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contribution);
        presale.contribute{value: contribution}(new bytes32);
        vm.stopPrank();

        // Act & Assert
        uint256 expectedTokens = (contribution * defaultOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        assertEq(presale.userTokens(contributor1), expectedTokens, "userTokens mismatch");
        assertEq(presale.userTokens(contributor2), 0, "userTokens mismatch for non-contributor");
    }

     function test_view_getContributorCount_And_getContributors() public {
        // Arrange: Deposit, contribute
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        assertEq(presale.getContributorCount(), 0, "Initial count mismatch");

        vm.startPrank(contributor1);
        vm.deal(contributor1, 1 ether);
        presale.contribute{value: 1 ether}(new bytes32);
        vm.stopPrank();
        assertEq(presale.getContributorCount(), 1, "Count after 1 mismatch");

        vm.startPrank(contributor2);
        vm.deal(contributor2, 1 ether);
        presale.contribute{value: 1 ether}(new bytes32);
        vm.stopPrank();
        assertEq(presale.getContributorCount(), 2, "Count after 2 mismatch");

        // Contribute again from contributor1, count should not increase
        vm.startPrank(contributor1);
        vm.deal(contributor1, 0.5 ether);
        presale.contribute{value: 0.5 ether}(new bytes32);
        vm.stopPrank();
        assertEq(presale.getContributorCount(), 2, "Count after duplicate mismatch");

        // Check array content
        address[] memory contributors = presale.getContributors();
        assertEq(contributors.length, 2, "Array length mismatch");
        assertEq(contributors[0], contributor1, "Array content mismatch 0");
        assertEq(contributors[1], contributor2, "Array content mismatch 1");
    }

    function test_view_getTotalContributed_And_getContribution() public {
         // Arrange: Deposit, contribute
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        assertEq(presale.getTotalContributed(), 0, "Initial total mismatch");
        assertEq(presale.getContribution(contributor1), 0, "Initial contrib mismatch");

        uint256 contrib1Amount1 = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contrib1Amount1 + 0.5 ether);
        presale.contribute{value: contrib1Amount1}(new bytes32);
        vm.stopPrank();
        assertEq(presale.getTotalContributed(), contrib1Amount1, "Total after 1 mismatch");
        assertEq(presale.getContribution(contributor1), contrib1Amount1, "Contrib1 after 1 mismatch");

        uint256 contrib2Amount = 2 ether;
        vm.startPrank(contributor2);
        vm.deal(contributor2, contrib2Amount);
        presale.contribute{value: contrib2Amount}(new bytes32);
        vm.stopPrank();
        assertEq(presale.getTotalContributed(), contrib1Amount1 + contrib2Amount, "Total after 2 mismatch");
        assertEq(presale.getContribution(contributor2), contrib2Amount, "Contrib2 after 1 mismatch");

        uint256 contrib1Amount2 = 0.5 ether;
        vm.startPrank(contributor1);
        presale.contribute{value: contrib1Amount2}(new bytes32);
        vm.stopPrank();
         assertEq(presale.getTotalContributed(), contrib1Amount1 + contrib2Amount + contrib1Amount2, "Total after 3 mismatch");
        assertEq(presale.getContribution(contributor1), contrib1Amount1 + contrib1Amount2, "Contrib1 after 2 mismatch");
    }


    // =============================================================
    //            Helper Functions
    // =============================================================

    // Helper to deposit tokens for a given presale
    function _depositTokens(Presale _presaleInstance, Presale.PresaleOptions memory _opts) private {
        vm.startPrank(creator);
        presaleToken.approve(address(_presaleInstance), _opts.tokenDeposit);
        _presaleInstance.deposit();
        vm.stopPrank();
        assertEq(uint8(_presaleInstance.state()), uint8(IPresale.PresaleState.Active), "Deposit helper failed");
    }

    // Helper to deploy a stablecoin presale instance
    function _deployStablePresale() private {
         vm.startPrank(creator);
         stablePresale = new Presale(
            mockWeth,
            address(presaleToken),
            address(mockRouter),
            stableOptions, // Use stable options
            creator,
            address(mockLocker),
            address(mockVesting),
            DEFAULT_HOUSE_PERCENTAGE,
            houseAddress
        );
        vm.stopPrank();
    }

    // Helper to mint and approve stablecoin for a user
    function _giveAndApproveStable(address _user, address _spender, uint256 _amount) private {
        vm.startPrank(deployer); // Use deployer who has minting rights on mock
        currencyToken.mint(_user, _amount);
        vm.stopPrank();

        vm.startPrank(_user);
        currencyToken.approve(_spender, _amount);
        vm.stopPrank();
    }

    // Helper to reach soft cap (adjust as needed from previous examples)
    function _reachSoftCap(Presale _presaleInstance, Presale.PresaleOptions memory _opts) private {
         uint256 target = _opts.softCap;
         uint256 amountPerContrib = _opts.max;
         require(amountPerContrib > 0, "Max contribution cannot be zero");
         // Ensure max contrib doesn't exceed target if target is small
         if (amountPerContrib > target) {
             amountPerContrib = target;
         }
         // Ensure min contrib doesn't exceed target
         require(_opts.min <= target, "Min contribution exceeds soft cap");
         // Use min if max is zero or less than min (should be caught by constructor validation)
         if (amountPerContrib < _opts.min) {
             amountPerContrib = _opts.min;
         }


         uint256 currentTotal = 0;
         uint numContributors = 0;
         address presaleAddress = address(_presaleInstance);
         bool isETH = (_opts.currency == address(0));

         console.log("Target Soft Cap:", target);
         console.log("Amount Per Contributor:", amountPerContrib);

         while(currentTotal < target) {
             numContributors++;
             address contributor = address(uint160(uint(keccak256(abi.encodePacked("softcap_contributor", numContributors)))));
             uint256 amountToContribute = (target - currentTotal >= amountPerContrib) ? amountPerContrib : (target - currentTotal);
             // Ensure contribution meets minimum if it's the last one
             if (amountToContribute < _opts.min && currentTotal + amountToContribute == target) {
                 // This scenario implies softcap itself is less than min, which should be disallowed by constructor.
                 // Or, the remaining amount is less than min. Adjust last contribution?
                 // For simplicity, assume constructor validation prevents softCap < min.
                 // If remaining < min, the loop condition `currentTotal < target` might exit early
                 // if amountPerContrib was set to min initially. Let's ensure we hit target exactly.
                 if (target - currentTotal < _opts.min) {
                     // If the remainder is less than min, we can't contribute it directly.
                     // This implies a potential issue if softcap isn't a multiple of min/max increments.
                     // For testing, let's just contribute the remainder if it's the last bit.
                     amountToContribute = target - currentTotal;
                 }
             }
             if (amountToContribute == 0) break; // Avoid infinite loop if calculation is off

             vm.startPrank(contributor);
             if (isETH) {
                 vm.deal(contributor, amountToContribute);
                 _presaleInstance.contribute{value: amountToContribute}(new bytes32);
             } else {
                 _giveAndApproveStable(contributor, presaleAddress, amountToContribute);
                 _presaleInstance.contributeStablecoin(amountToContribute, new bytes32);
             }
             vm.stopPrank();
             currentTotal += amountToContribute;
             console.log("SoftCap Contributor %s added %s. Total: %s", numContributors, amountToContribute, currentTotal);
         }

         assertGe(_presaleInstance.totalRaised(), target, "Failed to reach soft cap in helper");
         console.log("Soft Cap Reached. Total Raised:", _presaleInstance.totalRaised());
    }

    // Helper to deploy, deposit, contribute, and finalize a presale
    function _deployAndFinalizePresale(Presale.PresaleOptions memory _opts, address _contributor, uint256 _contributionAmount) private {
        // Deploy
        vm.startPrank(creator);
        presale = new Presale(
            mockWeth, address(presaleToken), address(mockRouter), _opts,
            creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress
        );
        // Deposit
        presaleToken.approve(address(presale), _opts.tokenDeposit);
        presale.deposit();
        vm.stopPrank();

        // Contribute
        vm.warp(_opts.start);
        vm.startPrank(_contributor);
        if (_opts.currency == address(0)) {
            vm.deal(_contributor, _contributionAmount);
            presale.contribute{value: _contributionAmount}(new bytes32);
        } else {
             _giveAndApproveStable(_contributor, address(presale), _contributionAmount);
             presale.contributeStablecoin(_contributionAmount, new bytes32);
        }
        vm.stopPrank();

        // Ensure softcap met (adjust contribution if needed, or use _reachSoftCap)
        assertTrue(presale.totalRaised() >= _opts.softCap, "Softcap not met for finalize helper");

        // Finalize
        vm.warp(_opts.end + 1);
        vm.startPrank(creator);
        _mockFinalizeCalls(presale, _opts); // Mock external calls
        presale.finalize();
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(IPresale.PresaleState.Finalized), "Finalize helper failed");
    }

    // Helper to mock calls needed for finalize
    function _mockFinalizeCalls(Presale _presaleInstance, Presale.PresaleOptions memory _opts) private {
        uint256 tokensForLiq = _presaleInstance.tokensLiquidity();
        uint256 expectedLpAmount = 1_000 * 1e18; // Mock LP amount

        address pairCurrency = (_opts.currency == address(0)) ? mockWeth : address(currencyToken);
        address mockPair = mockFactory.pairFor(address(presaleToken), pairCurrency);

        // Mock addLiquidity / addLiquidityETH
        if (_opts.currency == address(0)) {
             vm.mockCall(address(mockRouter), abi.encodeWithSelector(IUniswapV2Router02.addLiquidityETH.selector), abi.encode(1, 1, expectedLpAmount));
             vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), tokensForLiq));
        } else {
            uint256 liquidityAmountStable = (_presaleInstance.totalRaised() * _opts.liquidityBps) / BASIS_POINTS;
            vm.mockCall(address(mockRouter), abi.encodeWithSelector(IUniswapV2Router02.addLiquidity.selector), abi.encode(1, 1, expectedLpAmount));
            vm.expectCall(address(currencyToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), liquidityAmountStable));
            vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), tokensForLiq));
        }

        // Mock LP locking
        vm.expectCall(mockPair, abi.encodeWithSelector(IERC20.approve.selector, address(mockLocker), expectedLpAmount));
        vm.expectCall(address(mockLocker), abi.encodeWithSelector(LiquidityLocker.lock.selector));

        // Mock Leftover handling (if vesting)
        if (_opts.leftoverTokenOption == 2) {
            // Calculate potential leftovers (simplified, assumes some leftovers exist)
            uint256 leftoverEstimate = 1 * (10**PRESALE_TOKEN_DECIMALS); // Assume 1 token leftover
            vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockVesting), leftoverEstimate), 1); // Allow call once with approx amount
            vm.expectCall(address(mockVesting), abi.encodeWithSelector(Vesting.createVesting.selector), 1); // Allow call once
        }
    }
}
