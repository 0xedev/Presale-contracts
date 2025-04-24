// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Test Imports ---
import {Test, console} from "forge-std/Test.sol";
// import {StdCheats} from "forge-std/StdCheats.sol"; // Included in Test

// --- Contract Imports ---
import {Presale} from "../src/contracts/Presale.sol"; // Import Presale for struct/enum access
import {IPresale} from "../src/contracts/interfaces/IPresale.sol"; // Import interface for events/errors
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Router} from "./mocks/MockUniswapV2Router.sol";
import {MockUniswapV2Factory} from "./mocks/MockUniswapV2Factory.sol";
import {MockLiquidityLocker} from "./mocks/MockLiquidityLocker.sol";
import {MockVesting} from "./mocks/MockVesting.sol";
import {LiquidityLocker} from "../src/contracts/LiquidityLocker.sol"; // Import actual for typecasting/interface
import {Vesting} from "../src/contracts/Vesting.sol"; // Import actual for typecasting/interface

// --- Library/Interface Imports ---
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
contract PresaleUnitTest is Test { // Renamed from PresaleTest
    // --- Constants ---
    uint256 constant PRESALE_TOKEN_DECIMALS = 18;
    uint256 constant CURRENCY_TOKEN_DECIMALS = 6; // e.g., USDC
    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant DEFAULT_HOUSE_PERCENTAGE = 100; // 1%

    // --- State Variables ---
    // Presale instance (using the one deployed in setUp for most tests)
    Presale internal presale;

    // Mocks
    MockERC20 internal presaleToken;
    MockERC20 internal currencyToken; // Stablecoin
    MockUniswapV2Router internal mockRouter;
    MockUniswapV2Factory internal mockFactory; // Instance needed for router
    MockLiquidityLocker internal mockLocker;
    MockVesting internal mockVesting;
    address internal mockWeth; // Using address type is sufficient for mock router

    // Addresses
    address internal deployer;
    address internal creator;
    address internal contributor1;
    address internal contributor2;
    address internal houseAddress;
    address internal zeroAddress = address(0);
    address internal burnAddress = address(0); // For burn tests

    // Options
    // <<< FIX: Use Presale.PresaleOptions type >>>
    Presale.PresaleOptions internal defaultOptions;

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
        // Deploy mock factory first, then pass its address to the mock router
        mockFactory = new MockUniswapV2Factory();
        mockRouter = new MockUniswapV2Router(address(mockFactory), mockWeth); // Pass factory address
        mockLocker = new MockLiquidityLocker();
        mockVesting = new MockVesting();

        // --- Default ETH Presale Options ---
        // <<< FIX: Use Presale.PresaleOptions type >>>
        defaultOptions = Presale.PresaleOptions({
            tokenDeposit: 1_000_000 * (10 ** PRESALE_TOKEN_DECIMALS), // 1M tokens
            hardCap: 100 ether, // 100 ETH
            softCap: 25 ether, // 25 ETH (Must be >= 25% of hardcap)
            min: 0.1 ether,
            max: 5 ether,
            presaleRate: 5000, // 5000 PRE per ETH
            listingRate: 4000, // 4000 PRE per ETH (Must be < presaleRate)
            liquidityBps: 7000, // 70%
            slippageBps: 200, // 2%
            start: block.timestamp + 1 days, // Start in future
            end: block.timestamp + 8 days, // End later
            lockupDuration: 90 days,
            vestingPercentage: 2500, // 25%
            vestingDuration: 180 days,
            leftoverTokenOption: 0, // Return to owner
            currency: address(0) // ETH
        });

        // Deploy ETH Presale Instance using Mocks
        vm.startPrank(creator);
        presale = new Presale(
            mockWeth,
            address(presaleToken),
            address(mockRouter), // Use mock router address
            defaultOptions,
            creator,
            address(mockLocker), // Use mock locker address
            address(mockVesting), // Use mock vesting address
            DEFAULT_HOUSE_PERCENTAGE,
            houseAddress
        );
        vm.stopPrank();

        // Mint tokens for tests
        presaleToken.mint(creator, defaultOptions.tokenDeposit * 2); // Mint enough for deposit + leftovers
        currencyToken.mint(deployer, 1_000_000 * (10 ** CURRENCY_TOKEN_DECIMALS)); // Mint stablecoins (e.g., 1M USDC)
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
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        assertEq(uint8(_presaleInstance.state()), uint8(Presale.PresaleState.Active), "Deposit helper failed");
    }

    // Helper to deploy a stablecoin presale instance
    // <<< FIX: Use Presale.PresaleOptions as parameter type >>>
    function _deployStablePresale(Presale.PresaleOptions memory _stableOpts) internal returns (Presale) {
         vm.startPrank(creator);
         Presale stableInstance = new Presale(
            mockWeth,
            address(presaleToken),
            address(mockRouter),
            _stableOpts, // Use provided stable options
            creator,
            address(mockLocker),
            address(mockVesting),
            DEFAULT_HOUSE_PERCENTAGE,
            houseAddress
        );
        vm.stopPrank();
        return stableInstance;
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

    // Helper to reach soft cap respecting max contribution limits
    // <<< FIX: Use Presale.PresaleOptions as parameter type >>>
    function _reachSoftCap(Presale _presaleInstance, Presale.PresaleOptions memory _opts) private {
         uint256 amountPerContrib = _opts.max;
         uint256 target = _opts.softCap;
         uint256 currentTotal = 0;
         require(amountPerContrib > 0, "Max contribution cannot be zero for helper");
         require(_opts.min <= target, "Min contribution exceeds soft cap");
         require(_opts.softCap >= _opts.min, "Softcap must be >= min for helper");
         if (amountPerContrib < _opts.min) amountPerContrib = _opts.min;

         uint numContributorsNeeded = (target + amountPerContrib - 1) / amountPerContrib; // Ceiling division

         console.log("Reaching soft cap (%s) with max contrib (%s), need %s contributors", target, amountPerContrib, numContributorsNeeded);

         for (uint i = 0; i < numContributorsNeeded; i++) {
             address contributor = address(uint160(uint(keccak256(abi.encodePacked("softcap_contributor", i + 1)))));
             uint256 amountToContribute = amountPerContrib;

             if (currentTotal + amountToContribute > target) {
                 amountToContribute = target - currentTotal;
             }
             if (amountToContribute == 0) break;
             if (i==0 && amountToContribute < _opts.min) amountToContribute = _opts.min;
             if (target - currentTotal < _opts.min && currentTotal + amountToContribute == target) {
                 if (target - currentTotal < _opts.min) break; // Cannot make final contribution if less than min
             }


             vm.startPrank(contributor);
             if (_opts.currency == address(0)) { // ETH
                 vm.deal(contributor, amountToContribute);
                 _presaleInstance.contribute{value: amountToContribute}(new bytes32[](0));
             } else { // Stablecoin
                 vm.deal(contributor, 0);
                 vm.stopPrank();
                 vm.startPrank(deployer);
                 currencyToken.mint(contributor, amountToContribute);
                 vm.stopPrank();
                 vm.startPrank(contributor);
                 currencyToken.approve(address(_presaleInstance), amountToContribute);
                 _presaleInstance.contributeStablecoin(amountToContribute, new bytes32[](0));
             }

             vm.stopPrank();
             currentTotal += amountToContribute;
             console.log("SoftCap Contributor %s added %s. Total: %s", i+1, amountToContribute, currentTotal);
             if (currentTotal >= target) break;
         }
         assertGe(_presaleInstance.totalRaised(), target, "Failed to reach soft cap in helper");
         console.log("Soft Cap Reached. Total Raised:", _presaleInstance.totalRaised());
    }

    // Helper to mock calls needed for finalize
    // <<< FIX: Use Presale.PresaleOptions as parameter type >>>
    function _mockFinalizeCalls(Presale _presaleInstance, Presale.PresaleOptions memory _opts) private {
        uint256 totalRaisedFinal = _presaleInstance.totalRaised();
        uint256 liquidityAmount = (totalRaisedFinal * _opts.liquidityBps) / BASIS_POINTS;
        uint256 tokensForLiq = _presaleInstance.tokensLiquidity();
        uint256 expectedLpAmount = 1_000 * 1e18; // Mock LP amount

        address pairCurrency = (_opts.currency == address(0)) ? mockWeth : address(currencyToken);
        address mockPair = mockFactory.pairFor(address(presaleToken), pairCurrency);

        // --- Mock Router Calls ---
        if (_opts.currency == address(0)) { // ETH
             vm.mockCall(address(mockRouter), abi.encodeWithSelector(IUniswapV2Router01.addLiquidityETH.selector), abi.encode(1, 1, expectedLpAmount));
             vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), tokensForLiq));
        } else { // Stablecoin
            vm.mockCall(address(mockRouter), abi.encodeWithSelector(IUniswapV2Router01.addLiquidity.selector), abi.encode(1, 1, expectedLpAmount));
            vm.expectCall(address(currencyToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), liquidityAmount));
            vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockRouter), tokensForLiq));
        }

        // --- Mock LP Token and Locker Calls ---
        vm.expectCall(mockPair, abi.encodeWithSelector(IERC20.approve.selector, address(mockLocker), expectedLpAmount));
        vm.expectCall(address(mockLocker), abi.encodeWithSelector(LiquidityLocker.lock.selector));

        // --- Mock Vesting Calls (if applicable) ---
        if (_opts.leftoverTokenOption == 2) {
            vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockVesting), 1), 1);
            vm.expectCall(address(mockVesting), abi.encodeWithSelector(Vesting.createVesting.selector), 1);
        }
    }

     // Helper to deploy, deposit, contribute, and finalize a presale
     // <<< FIX: Use Presale.PresaleOptions as parameter type >>>
    function _deployAndFinalizePresale(Presale.PresaleOptions memory _opts, address _contributor, uint256 _contributionAmount) internal returns (Presale) {
        // Deploy
        vm.startPrank(creator);
        Presale instance = new Presale(
            mockWeth, address(presaleToken), address(mockRouter), _opts,
            creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress
        );
        // Deposit
        presaleToken.approve(address(instance), _opts.tokenDeposit);
        instance.deposit();
        vm.stopPrank();

        // Contribute
        vm.warp(_opts.start);
        vm.startPrank(_contributor);
        if (_opts.currency == address(0)) {
            vm.deal(_contributor, _contributionAmount);
            instance.contribute{value: _contributionAmount}(new bytes32[](0));
        } else {
             _giveAndApproveStable(_contributor, address(instance), _contributionAmount);
             instance.contributeStablecoin(_contributionAmount, new bytes32[](0));
        }
        vm.stopPrank();

        // Ensure softcap met
        assertTrue(instance.totalRaised() >= _opts.softCap, "Softcap not met for finalize helper");

        // Finalize
        vm.warp(_opts.end + 1);
        vm.startPrank(creator);
        _mockFinalizeCalls(instance, _opts); // Mock external calls
        instance.finalize();
        vm.stopPrank();
        // <<< FIX: Use Presale.PresaleState enum >>>
        assertEq(uint8(instance.state()), uint8(Presale.PresaleState.Finalized), "Finalize helper failed");
        return instance; // Return the finalized instance
    }


    // =============================================================
    //            Constructor & Setup Tests
    // =============================================================

    function test_setUp_CorrectInitialState() public view {
        // <<< FIX: Use Presale.PresaleState enum >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Pending), "Initial state mismatch");
        assertEq(address(presale.token()), address(presaleToken), "Token mismatch");
        assertEq(address(presale.uniswapV2Router02()), address(mockRouter), "Router mismatch");
        assertEq(presale.factory(), address(mockFactory), "Factory mismatch");
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
        // <<< FIX: Use Presale.PresaleOptions type >>>
        Presale.PresaleOptions memory fetchedOptions = presale.options();

        assertEq(fetchedOptions.tokenDeposit, defaultOptions.tokenDeposit, "Token deposit mismatch");
        // ... (rest of assertions) ...
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
        // <<< FIX: Use Presale.PresaleOptions type >>>
        Presale.PresaleOptions memory badOptions = defaultOptions;

        // Invalid Caps
        badOptions.softCap = 0;
        vm.expectRevert(IPresale.InvalidCapSettings.selector);
        new Presale(mockWeth, address(presaleToken), address(mockRouter), badOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
        badOptions = defaultOptions; // Reset
        // ... (rest of invalid option tests remain the same) ...
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
        vm.expectEmit(true, true, false, true, address(presale)); // Check emitter address
        emit IPresale.Deposit(creator, defaultOptions.tokenDeposit, block.timestamp);
        uint256 deposited = presale.deposit();
        vm.stopPrank();

        // Assert
        assertEq(deposited, defaultOptions.tokenDeposit, "Deposited amount mismatch");
        // <<< FIX: Use Presale.PresaleState enum >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "State not Active");
        assertEq(presale.tokenBalance(), defaultOptions.tokenDeposit, "Contract token balance mismatch");
        assertEq(presaleToken.balanceOf(address(presale)), defaultOptions.tokenDeposit, "ERC20 balance mismatch");
        assertEq(presaleToken.balanceOf(creator), creatorBalanceBefore - defaultOptions.tokenDeposit, "Creator balance mismatch");

        // Check calculated values based on hardcap
        uint256 expectedClaimable = (defaultOptions.hardCap * defaultOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 expectedLiquidity = (defaultOptions.hardCap * defaultOptions.liquidityBps / BASIS_POINTS * defaultOptions.listingRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);

        assertEq(presale.tokensClaimable(), expectedClaimable, "tokensClaimable mismatch");
        assertEq(presale.tokensLiquidity(), expectedLiquidity, "tokensLiquidity mismatch");
    }

    function test_deposit_Revert_NotOwner() public {
        vm.startPrank(contributor1); // Not owner
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, contributor1));
        presale.deposit();
        vm.stopPrank();
    }

    function test_deposit_Revert_NotPending() public {
        // Arrange: Deposit once to change state
        _depositTokens(presale, defaultOptions); // Helper ensures state is Active
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);

        // Act & Assert: Try depositing again
        // <<< FIX: Use Presale.PresaleState enum >>>
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.deposit();
        vm.stopPrank();
    }

    function test_deposit_Revert_InsufficientDeposit() public {
         // Arrange: Calculate needed tokens
        uint256 expectedClaimable = (defaultOptions.hardCap * defaultOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 expectedLiquidity = (defaultOptions.hardCap * defaultOptions.liquidityBps / BASIS_POINTS * defaultOptions.listingRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 totalNeeded = expectedClaimable + expectedLiquidity;

        // Create new presale with options.tokenDeposit < totalNeeded
        // <<< FIX: Use Presale.PresaleOptions type >>>
        Presale.PresaleOptions memory badDepositOptions = defaultOptions;
        badDepositOptions.tokenDeposit = totalNeeded - 1;

        vm.startPrank(creator);
        Presale badDepositPresale = new Presale(
            mockWeth, address(presaleToken), address(mockRouter), badDepositOptions,
            creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress
        );
        presaleToken.approve(address(badDepositPresale), badDepositOptions.tokenDeposit);

        // Act & Assert
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
    //            Contribution Tests (ETH)
    // =============================================================
    // (Tests seem mostly correct, ensure empty proof `new bytes32[](0)` is used)

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
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Contribution(contributor1, contributionAmount, true);
        presale.contribute{value: contributionAmount}(new bytes32[](0)); // Use empty proof
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
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Contribution(contributor1, contributionAmount, true);
        (bool success, ) = address(presale).call{value: contributionAmount}("");
        assertTrue(success, "Receive call failed");
        vm.stopPrank();

        // Assert
        assertEq(presale.totalRaised(), initialTotalRaised + contributionAmount, "Total raised mismatch");
        assertEq(presale.getContribution(contributor1), contributionAmount, "Contributor balance mismatch");
        assertEq(address(presale).balance, initialContractBalance + contributionAmount, "Contract ETH balance mismatch");
    }

    // ... (Other ETH contribution tests using `new bytes32[](0)` for proof) ...

    // =============================================================
    //            Contribution Tests (Stablecoin)
    // =============================================================

    function test_contribute_Stable_Success() public {
        // Arrange: Deploy stable presale, deposit, warp
        // <<< FIX: Use Presale.PresaleOptions type >>>
        Presale.PresaleOptions memory stableOptions = defaultOptions;
        stableOptions.currency = address(currencyToken);
        stableOptions.min = 100 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOptions.max = 5000 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOptions.hardCap = 100_000 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOptions.softCap = 25_000 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOptions.presaleRate = 5;
        stableOptions.listingRate = 4;

        Presale stableInstance = _deployStablePresale(stableOptions);
        _depositTokens(stableInstance, stableOptions);
        vm.warp(stableOptions.start);

        uint256 contributionAmount = 500 * (10 ** CURRENCY_TOKEN_DECIMALS);
        uint256 initialTotalRaised = stableInstance.totalRaised();
        uint256 initialContractBalance = currencyToken.balanceOf(address(stableInstance));

        // Act
        vm.startPrank(contributor1);
        _giveAndApproveStable(contributor1, address(stableInstance), contributionAmount);
        vm.expectEmit(true, true, false, true, address(stableInstance));
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(stableInstance));
        emit IPresale.Contribution(contributor1, contributionAmount, false);
        stableInstance.contributeStablecoin(contributionAmount, new bytes32[](0)); // Use empty proof
        vm.stopPrank();

        // Assert
        assertEq(stableInstance.totalRaised(), initialTotalRaised + contributionAmount, "Total raised mismatch");
        assertEq(stableInstance.getContribution(contributor1), contributionAmount, "Contributor balance mismatch");
        assertEq(currencyToken.balanceOf(address(stableInstance)), initialContractBalance + contributionAmount, "Contract Stable balance mismatch");
        assertEq(stableInstance.getContributorCount(), 1, "Contributor count mismatch");
    }

    // ... (Other Stablecoin contribution tests using `new bytes32[](0)` for proof) ...

    // =============================================================
    //            Finalize Tests
    // =============================================================
    // (Tests seem mostly correct, ensure state enum usage and mocking)

    // --- test_finalize_Success (Conceptual Mocking) ---
    function test_finalize_Success_ETH_Mocked() public {
        // Arrange: Deposit, reach soft cap, warp past end
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions);
        vm.warp(defaultOptions.end + 1);

        uint256 totalRaisedFinal = presale.totalRaised();
        uint256 liquidityAmount = (totalRaisedFinal * defaultOptions.liquidityBps) / BASIS_POINTS;
        uint256 houseAmount = (totalRaisedFinal * presale.housePercentage()) / BASIS_POINTS;
        uint256 expectedOwnerBalance = totalRaisedFinal - liquidityAmount - houseAmount;
        uint256 expectedLpAmount = 1_000 * 1e18; // Mock LP amount

        // Mock external calls
        _mockFinalizeCalls(presale, defaultOptions);

        uint256 houseBalanceBefore = houseAddress.balance;
        uint256 creatorBalanceBefore = creator.balance;

        // Act: Finalize
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(presale)); // Finalized
        // Add other expectEmits as needed
        presale.finalize();
        vm.stopPrank();

        // Assert State
        // <<< FIX: Use Presale.PresaleState enum >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized), "State not Finalized");
        assertTrue(presale.claimDeadline() > defaultOptions.end, "Claim deadline not set");
        assertEq(presale.ownerBalance(), expectedOwnerBalance, "Owner balance mismatch");

        // Assert Fund Distribution
        assertEq(houseAddress.balance, houseBalanceBefore + houseAmount, "House fee mismatch");
        assertEq(creator.balance, creatorBalanceBefore, "Creator ETH balance changed unexpectedly");

        // Assert LP Locking (Implicitly checked by expectCall in _mockFinalizeCalls)
    }

    // --- test_handleLeftoverTokens_Return (Conceptual Mocking) ---
    function test_handleLeftoverTokens_Return_Mocked() public {
        // Arrange: Deposit, reach soft cap, warp past end
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions);
        vm.warp(defaultOptions.end + 1);

        // Calculate expected leftovers
        // <<< FIX: Use Presale.PresaleOptions type >>>
        Presale.PresaleOptions memory fetchedOptions = presale.options();
        uint256 tokensLiquidityCalc = presale.tokensLiquidity();
        uint256 totalContribution = presale.totalRaised();
        uint256 tokenDecimals = presaleToken.decimals();
        uint256 currencyMultiplier = (fetchedOptions.currency == address(0)) ? 1 ether : (10 ** currencyToken.decimals());
        uint256 totalTokensForContrib = (totalContribution * fetchedOptions.presaleRate * (10 ** tokenDecimals)) / currencyMultiplier;
        uint256 expectedLeftovers = defaultOptions.tokenDeposit - totalTokensForContrib - tokensLiquidityCalc;
        assertTrue(expectedLeftovers > 0, "Expected leftover calculation failed or yielded zero");

        // Mock external calls needed for finalize
        _mockFinalizeCalls(presale, defaultOptions);

        uint256 creatorTokenBalanceBefore = presaleToken.balanceOf(creator);
        uint256 presaleTokenBalanceBefore = presaleToken.balanceOf(address(presale));

        // Act: Finalize
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(presale)); // Expect LeftoverTokensReturned
        emit IPresale.LeftoverTokensReturned(expectedLeftovers, creator);
        presale.finalize();
        vm.stopPrank();

        // Assert
        assertEq(presaleToken.balanceOf(creator), creatorTokenBalanceBefore + expectedLeftovers, "Creator balance mismatch (Leftovers)");
        assertEq(presaleToken.balanceOf(address(presale)), 0, "Presale token balance mismatch after finalize");
    }

    // =============================================================
    //            Claim Tests
    // =============================================================
     function test_claim_Success() public {
        // Arrange: Activate, Contribute, Finalize (using helper)
        Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, defaultOptions.max); // Use helper
        uint256 totalTokensContributor1 = finalizedPresale.userTokens(contributor1);

        // Ensure state is finalized by helper
        assertEq(uint8(finalizedPresale.state()), uint8(Presale.PresaleState.Finalized), "Helper did not finalize");

        // Act: Claim
        uint256 vestingBps = finalizedPresale.options().vestingPercentage; // Get options from finalized instance
        uint256 expectedVested = (totalTokensContributor1 * vestingBps) / BASIS_POINTS;
        uint256 expectedImmediate = totalTokensContributor1 - expectedVested;
        uint256 initialBalance = presaleToken.balanceOf(contributor1);
        // uint256 presaleBalanceBefore = presaleToken.balanceOf(address(finalizedPresale)); // Balance after finalize is complex
        uint256 vestingContractBalanceBefore = presaleToken.balanceOf(address(mockVesting)); // Use mock address

        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(finalizedPresale));
        emit IPresale.TokenClaim(contributor1, totalTokensContributor1, block.timestamp);

        // Mock vesting calls if vesting is enabled
        if (expectedVested > 0) {
             vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockVesting), expectedVested));
             vm.expectCall(address(mockVesting), abi.encodeWithSelector(Vesting.createVesting.selector));
        }

        finalizedPresale.claim();
        vm.stopPrank();

        // Assert
        assertEq(
            presaleToken.balanceOf(contributor1),
            initialBalance + expectedImmediate,
            "Immediate token balance incorrect"
        );
        assertEq(
            presaleToken.balanceOf(address(mockVesting)), // Check balance of mock vesting contract
            vestingContractBalanceBefore + expectedVested,
            "Vesting contract balance incorrect"
        );
        assertEq(finalizedPresale.getContribution(contributor1), 0, "Contribution should be reset");
    }

     function test_claim_Revert_NotFinalized() public {
        // Arrange: Deposit, contribute, but not finalized
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.max);
        presale.contribute{value: defaultOptions.max}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // Act & Assert
        vm.startPrank(contributor1);
        // <<< FIX: Use Presale.PresaleState enum >>>
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.claim();
        vm.stopPrank();
    }

    function test_claim_Revert_ClaimPeriodExpired() public {
        // Arrange: Finalize, warp past deadline
         Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether);
         vm.warp(finalizedPresale.claimDeadline() + 1);

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.ClaimPeriodExpired.selector);
        finalizedPresale.claim();
        vm.stopPrank();
    }

     function test_claim_Revert_NoTokensToClaim() public {
        // Arrange: Finalize, but contributor2 didn't contribute
         Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether); // contributor1 contributed

        // Act & Assert: contributor2 tries to claim
        vm.startPrank(contributor2);
        vm.expectRevert(IPresale.NoTokensToClaim.selector);
        finalizedPresale.claim();
        vm.stopPrank();

        // Act & Assert: contributor1 claims, then tries again
        vm.startPrank(contributor1);
        // Mock vesting calls if needed for first claim
        if (finalizedPresale.options().vestingPercentage > 0) {
             uint256 totalTokens = finalizedPresale.userTokens(contributor1);
             uint256 vested = (totalTokens * finalizedPresale.options().vestingPercentage) / BASIS_POINTS;
             vm.expectCall(address(presaleToken), abi.encodeWithSelector(IERC20.approve.selector, address(mockVesting), vested));
             vm.expectCall(address(mockVesting), abi.encodeWithSelector(Vesting.createVesting.selector));
        }
        finalizedPresale.claim(); // First claim
        vm.expectRevert(IPresale.NoTokensToClaim.selector);
        finalizedPresale.claim(); // Second claim attempt
        vm.stopPrank();
    }

     function test_claim_Revert_WhenPaused() public {
        // Arrange: Finalize, then pause
         Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether);
         vm.startPrank(creator);
         finalizedPresale.pause();
         vm.stopPrank();

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.ContractPaused.selector);
        finalizedPresale.claim();
        vm.stopPrank();
    }

    // =============================================================
    //            Refund Tests
    // =============================================================
     function test_refund_Success_Canceled() public {
        // Arrange: Deposit, contribute, cancel
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
        // vm.warp(defaultOptions.end + 1); // No need to warp past end for cancel
        vm.startPrank(creator);
        presale.cancel();
        vm.stopPrank();
        // <<< FIX: Use Presale.PresaleState enum >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Canceled), "State should be Canceled");

        // Act
        uint256 initialBalance = contributor1.balance;
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Refund(contributor1, contributionAmount, block.timestamp);
        presale.refund();
        vm.stopPrank();

        // Assert
        assertEq(contributor1.balance, initialBalance + contributionAmount, "Refund amount incorrect");
        assertEq(presale.getContribution(contributor1), 0, "Contribution should be reset after refund");
    }

     function test_refund_Success_FailedSoftCap() public {
        // Arrange: Deposit, contribute less than softcap, warp past end
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = defaultOptions.min;
        require(contributionAmount < defaultOptions.softCap, "Min >= Softcap, test invalid");
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1); // MUST be past end time

        // State check
        // <<< FIX: Use Presale.PresaleState enum >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "State should still be Active");
        assertTrue(presale.totalRaised() < defaultOptions.softCap, "Softcap was met");

        // Act
        uint256 initialBalance = contributor1.balance;
        vm.startPrank(contributor1);
         vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Refund(contributor1, contributionAmount, block.timestamp);
        presale.refund(); // Should be allowed by onlyRefundable modifier
        vm.stopPrank();

        // Assert
        assertEq(contributor1.balance, initialBalance + contributionAmount, "Refund amount incorrect");
        assertEq(presale.getContribution(contributor1), 0, "Contribution should be reset after refund");
    }

     function test_refund_Success_Stablecoin() public {
        // Arrange: Deploy stable, deposit, contribute, cancel
        // <<< FIX: Use Presale.PresaleOptions type >>>
        Presale.PresaleOptions memory stableOpts = defaultOptions;
        stableOpts.currency = address(currencyToken);
        stableOpts.min = 100 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOpts.max = 5000 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOpts.hardCap = 100_000 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOpts.softCap = 25_000 * (10 ** CURRENCY_TOKEN_DECIMALS);
        stableOpts.presaleRate = 5;
        stableOpts.listingRate = 4;

        Presale stableInstance = _deployStablePresale(stableOpts);
        _depositTokens(stableInstance, stableOpts);
        vm.warp(stableOpts.start);
        uint256 contribution = stableOpts.min;
        vm.startPrank(contributor1);
        _giveAndApproveStable(contributor1, address(stableInstance), contribution);
        stableInstance.contributeStablecoin(contribution, new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(creator);
        stableInstance.cancel();
        vm.stopPrank();

        uint256 balanceBefore = currencyToken.balanceOf(contributor1);

        // Act
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(stableInstance));
        emit IPresale.Refund(contributor1, contribution, block.timestamp);
        stableInstance.refund();
        vm.stopPrank();

        // Assert
        assertEq(stableInstance.getContribution(contributor1), 0, "Contribution not reset");
        assertEq(currencyToken.balanceOf(contributor1), balanceBefore + contribution, "Refund amount mismatch");
    }


    function test_refund_Revert_NotRefundableState() public {
        // Arrange: Deposit, contribute, presale active and ongoing
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 contribution = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contribution);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.stopPrank();

        // Act & Assert: Try refunding while active and before end
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.NotRefundable.selector);
        presale.refund();
        vm.stopPrank();

        // Arrange: Finalize successfully
        Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, defaultOptions.softCap); // Use helper

         // Act & Assert: Try refunding after successful finalize
        vm.startPrank(contributor1);
        vm.expectRevert(IPresale.NotRefundable.selector);
        finalizedPresale.refund();
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
        // Need a fresh instance for this part
         Presale presaleInst2 = new Presale(mockWeth, address(presaleToken), address(mockRouter), defaultOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);
         _depositTokens(presaleInst2, defaultOptions);
         vm.warp(defaultOptions.start);
         uint256 contribution = 1 ether;
         vm.startPrank(contributor1);
         vm.deal(contributor1, contribution);
         presaleInst2.contribute{value: contribution}(new bytes32[](0));
         vm.stopPrank();
         vm.startPrank(creator);
         presaleInst2.cancel();
         vm.stopPrank();
         vm.startPrank(contributor1);
         presaleInst2.refund(); // First refund

        // Act & Assert: Try refunding again
        vm.expectRevert(IPresale.NoFundsToRefund.selector);
        presaleInst2.refund();
        vm.stopPrank();
    }

    // =============================================================
    //            Withdraw Tests
    // =============================================================
    // (Tests from previous response seem mostly okay)

    // =============================================================
    //            Pause/Unpause Tests
    // =============================================================
    // (Tests from previous response seem mostly okay)

    // =============================================================
    //            Extend Claim Deadline Tests
    // =============================================================
     function test_extendClaimDeadline_Revert_InvalidDeadline() public {
        Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether);
        uint256 invalidDeadline = finalizedPresale.claimDeadline(); // Current deadline is invalid
        vm.startPrank(creator);
        vm.expectRevert(IPresale.InvalidDeadline.selector);
        finalizedPresale.extendClaimDeadline(invalidDeadline);
        vm.stopPrank();
    }
    // (Other tests from previous response seem mostly okay)

    // =============================================================
    //            Rescue Tokens Tests
    // =============================================================
     function test_rescueTokens_Revert_PresaleTokenBeforeDeadline() public {
        Presale finalizedPresale = _deployAndFinalizePresale(defaultOptions, contributor1, 1 ether);
        // Don't warp past deadline
        vm.startPrank(creator);
        vm.expectRevert(IPresale.CannotRescuePresaleTokens.selector);
        finalizedPresale.rescueTokens(address(presaleToken), creator, 1000);
        vm.stopPrank();
    }
    // (Other tests from previous response seem mostly okay)

    // =============================================================
    //            View Function Tests
    // =============================================================
    // (Tests from previous response seem mostly okay)

    // =============================================================
    //            Finalize Leftover Tests
    // =============================================================

    function test_finalize_Leftover_Return() public {
        // Arrange: Deposit, reach soft cap, warp past end
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions);
        vm.warp(defaultOptions.end + 1);

        // Calculate expected leftovers
        Presale.PresaleOptions memory fetchedOptions = presale.options();
        uint256 tokensLiquidityCalc = presale.tokensLiquidity();
        uint256 totalContribution = presale.totalRaised();
        uint256 tokenDecimals = presaleToken.decimals();
        uint256 currencyMultiplier = (fetchedOptions.currency == address(0)) ? 1 ether : (10 ** currencyToken.decimals());
        uint256 totalTokensForContrib = (totalContribution * fetchedOptions.presaleRate * (10 ** tokenDecimals)) / currencyMultiplier;
        uint256 expectedLeftovers = defaultOptions.tokenDeposit - totalTokensForContrib - tokensLiquidityCalc;
        assertTrue(expectedLeftovers > 0, "Expected leftover calculation failed or yielded zero");

        // Mock external calls needed for finalize
        _mockFinalizeCalls(presale, defaultOptions);

        uint256 creatorTokenBalanceBefore = presaleToken.balanceOf(creator);
        uint256 presaleTokenBalanceBefore = presaleToken.balanceOf(address(presale));

        // Act: Finalize
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(presale)); // Expect LeftoverTokensReturned
        emit IPresale.LeftoverTokensReturned(expectedLeftovers, creator);
        presale.finalize();
        vm.stopPrank();

        // Assert
        assertEq(presaleToken.balanceOf(creator), creatorTokenBalanceBefore + expectedLeftovers, "Creator balance mismatch (Leftovers)");
        assertEq(presaleToken.balanceOf(address(presale)), 0, "Presale token balance mismatch after finalize");
    }

    function test_finalize_Leftover_Burn() public {
        // Arrange: Deploy presale with burn option
        Presale.PresaleOptions memory burnOptions = defaultOptions;
        burnOptions.leftoverTokenOption = 1; // Burn
        Presale burnPresale = new Presale(mockWeth, address(presaleToken), address(mockRouter), burnOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);

        // Deposit, reach soft cap, warp past end
        _depositTokens(burnPresale, burnOptions);
        vm.warp(burnOptions.start);
        _reachSoftCap(burnPresale, burnOptions);
        vm.warp(burnOptions.end + 1);

        // Calculate expected leftovers
        uint256 tokensLiquidityCalc = burnPresale.tokensLiquidity();
        uint256 totalContribution = burnPresale.totalRaised();
        uint256 tokenDecimals = presaleToken.decimals();
        uint256 currencyMultiplier = (burnOptions.currency == address(0)) ? 1 ether : (10 ** currencyToken.decimals());
        uint256 totalTokensForContrib = (totalContribution * burnOptions.presaleRate * (10 ** tokenDecimals)) / currencyMultiplier;
        uint256 expectedLeftovers = burnOptions.tokenDeposit - totalTokensForContrib - tokensLiquidityCalc;
        assertTrue(expectedLeftovers > 0, "Expected leftover calculation failed or yielded zero");

        // Mock external calls
        _mockFinalizeCalls(burnPresale, burnOptions);

        uint256 burnAddressBalanceBefore = presaleToken.balanceOf(burnAddress);

        // Act: Finalize
        vm.startPrank(creator);
        vm.expectEmit(true, false, false, true, address(burnPresale)); // Expect LeftoverTokensBurned
        emit IPresale.LeftoverTokensBurned(expectedLeftovers);
        burnPresale.finalize();
        vm.stopPrank();

        // Assert
        assertEq(presaleToken.balanceOf(burnAddress), burnAddressBalanceBefore + expectedLeftovers, "Leftover tokens not burned");
        assertEq(presaleToken.balanceOf(address(burnPresale)), 0, "Presale token balance mismatch after finalize");
    }

    function test_finalize_Leftover_Vest() public {
        // Arrange: Deploy presale with vest option
        Presale.PresaleOptions memory vestOptions = defaultOptions;
        vestOptions.leftoverTokenOption = 2; // Vest
        Presale vestPresale = new Presale(mockWeth, address(presaleToken), address(mockRouter), vestOptions, creator, address(mockLocker), address(mockVesting), DEFAULT_HOUSE_PERCENTAGE, houseAddress);

        // Deposit, reach soft cap, warp past end
        _depositTokens(vestPresale, vestOptions);
        vm.warp(vestOptions.start);
        _reachSoftCap(vestPresale, vestOptions);
        vm.warp(vestOptions.end + 1);

        // Calculate expected leftovers
        uint256 tokensLiquidityCalc = vestPresale.tokensLiquidity();
        uint256 totalContribution = vestPresale.totalRaised();
        uint256 tokenDecimals = presaleToken.decimals();
        uint256 currencyMultiplier = (vestOptions.currency == address(0)) ? 1 ether : (10 ** currencyToken.decimals());
        uint256 totalTokensForContrib = (totalContribution * vestOptions.presaleRate * (10 ** tokenDecimals)) / currencyMultiplier;
        uint256 expectedLeftovers = vestOptions.tokenDeposit - totalTokensForContrib - tokensLiquidityCalc;
        assertTrue(expectedLeftovers > 0, "Expected leftover calculation failed or yielded zero");

        // Mock external calls (including vesting)
        _mockFinalizeCalls(vestPresale, vestOptions); // _mockFinalizeCalls already expects vesting calls if option is 2

        // Act: Finalize
        vm.startPrank(creator);
        vm.expectEmit(true, true, false, true, address(vestPresale)); // Expect LeftoverTokensVested
        emit IPresale.LeftoverTokensVested(expectedLeftovers, creator);
        vestPresale.finalize();
        vm.stopPrank();

        // Assert
        assertEq(presaleToken.balanceOf(address(vestPresale)), 0, "Presale token balance mismatch after finalize");
        // Further checks would involve interacting with the mockVesting contract if needed
    }


    // =============================================================
    //            Edge Case Tests
    // =============================================================

    function test_contribute_ETH_ExactHardCap() public {
        // Arrange
        _depositTokens(presale, defaultOptions);
        vm.warp(defaultOptions.start);
        uint256 numContributorsNeeded = (defaultOptions.hardCap + defaultOptions.max - 1) / defaultOptions.max;

        // Contribute using multiple contributors to reach hard cap exactly
        uint256 currentTotal = 0;
        for(uint i = 0; i < numContributorsNeeded; ++i) {
            address tempContributor = address(uint160(uint(keccak256(abi.encodePacked("hardcap_contributor", i)))));
            uint256 contrib = (defaultOptions.hardCap - currentTotal >= defaultOptions.max) ? defaultOptions.max : (defaultOptions.hardCap - currentTotal);
            if (contrib == 0) break;
            vm.startPrank(tempContributor);
            vm.deal(tempContributor, contrib);
            presale.contribute{value: contrib}(new bytes32[](0));
            vm.stopPrank();
            currentTotal += contrib;
        }
        assertEq(presale.totalRaised(), defaultOptions.hardCap, "Hardcap not reached exactly");

        // Act & Assert: Try to contribute more
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.min);
        vm.expectRevert(IPresale.HardCapExceeded.selector);
        presale.contribute{value: defaultOptions.min}(new bytes32[](0));
        vm.stopPrank();
    }


}
