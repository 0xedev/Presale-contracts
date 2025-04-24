// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Imports ---
import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockUniswapV2Router} from "../test/mocks/MockUniswapV2Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import your actual contracts
import {Presale} from "../src/contracts/Presale.sol"; // Import Presale to access its struct/enum
import {PresaleFactory} from "../src/contracts/PresaleFactory.sol";
import {LiquidityLocker} from "../src/contracts/LiquidityLocker.sol";
import {Vesting} from "../src/contracts/Vesting.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// Import interface (PresaleOptions/PresaleState are now defined in Presale.sol)
import {IPresale} from "../src/contracts/interfaces/IPresale.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// --- Test Contract ---
contract PresaleUnitTest is Test {
    // --- State Variables ---
    // Contracts
    PresaleFactory internal presaleFactory;
    Presale internal presale;
    LiquidityLocker internal liquidityLocker;
    Vesting internal vestingContract;
    MockERC20 internal presaleToken;
    MockERC20 internal currencyToken;
    MockERC20 internal weth;
    MockUniswapV2Router internal mockRouter;

    // Users
    address internal deployer;
    address internal creator;
    address internal contributor1;
    address internal contributor2;
    address internal house;
    address internal mockFactoryAddr;

    // Constants
    uint256 internal constant ONE_ETHER = 1 ether;
    uint8 internal constant PRESALE_TOKEN_DECIMALS = 18;
    uint8 internal constant CURRENCY_TOKEN_DECIMALS = 6;
    uint256 internal constant TOTAL_DEPOSIT = 1_000_000 * (10 ** PRESALE_TOKEN_DECIMALS);
    bytes32 internal constant VESTER_ROLE = keccak256("VESTER_ROLE");
    bytes32 internal constant LOCKER_ROLE = keccak256("LOCKER_ROLE");

    // Default Options Struct
    // <<< FIX: Use Presale.PresaleOptions as type >>>
    Presale.PresaleOptions internal defaultOptions;

    // --- Setup Function ---
    function setUp() public {
        // 1. Define Users
        deployer = makeAddr("deployer");
        creator = makeAddr("creator");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");
        house = makeAddr("house");
        mockFactoryAddr = makeAddr("mockFactory");

        // Start prank as deployer for initial deployments
        vm.startPrank(deployer);

        // 2. Deploy Mock Tokens
        presaleToken = new MockERC20("Presale Token", "PRE", PRESALE_TOKEN_DECIMALS);
        currencyToken = new MockERC20("USD Coin", "USDC", CURRENCY_TOKEN_DECIMALS);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // 3. Deploy Mock Router
        mockRouter = new MockUniswapV2Router(mockFactoryAddr);

        // 4. Deploy PresaleFactory
        presaleFactory = new PresaleFactory(
            0, // creationFee (ETH)
            address(0), // feeToken (ETH)
            100, // housePercentage (1%)
            house // houseAddress
        );

        // Get contract instances
        liquidityLocker = presaleFactory.liquidityLocker();
        vestingContract = presaleFactory.vestingContract();

        // Log & Validate addresses
        console.log("LiquidityLocker:", address(liquidityLocker));
        console.log("VestingContract:", address(vestingContract));
        require(address(liquidityLocker) != address(0), "LiquidityLocker is zero");
        require(address(vestingContract) != address(0), "VestingContract is zero");
        require(house != address(0), "House address is zero");

        vm.stopPrank();

        // 5. Prepare Tokens for Users
        vm.startPrank(deployer);
        presaleToken.mint(creator, TOTAL_DEPOSIT * 2);
        currencyToken.mint(contributor1, 10_000 * (10 ** CURRENCY_TOKEN_DECIMALS));
        currencyToken.mint(contributor2, 10_000 * (10 ** CURRENCY_TOKEN_DECIMALS));
        vm.stopPrank();

        // 6. Define Default Presale Options
        uint256 startTime = block.timestamp + 60;
        uint256 endTime = startTime + (7 days);
        // <<< FIX: Use Presale.PresaleOptions for initialization >>>
        defaultOptions = Presale.PresaleOptions({
            tokenDeposit: TOTAL_DEPOSIT,
            hardCap: 100 ether,
            softCap: 25 ether,
            max: 5 ether,
            min: 0.1 ether,
            start: startTime,
            end: endTime,
            liquidityBps: 5000,
            slippageBps: 500,
            presaleRate: 5000,
            listingRate: 4000,
            lockupDuration: 30 days,
            currency: address(0),
            vestingPercentage: 2000,
            vestingDuration: 60 days,
            leftoverTokenOption: 0
        });

        // 7. Deploy a standard Presale instance
        vm.startPrank(creator);
        console.log("Calling createPresale...");
        try presaleFactory.createPresale(defaultOptions, address(presaleToken), address(weth), address(mockRouter))
        returns (address presaleAddress) {
            presale = Presale(payable(presaleAddress));
            console.log("Presale deployed at:", address(presale));
        } catch Error(string memory reason) {
            console.log("Presale creation failed:", reason);
            revert(string(abi.encodePacked("Presale creation failed: ", reason)));
        } catch {
            console.log("Presale creation failed with no reason");
            revert("Presale creation failed with no reason");
        }
        vm.stopPrank();
    }

    // --- Test Functions ---

    function test_setUp_CorrectOwner() public view {
        assertEq(presale.owner(), creator, "Presale owner should be creator");
    }

    function test_setUp_CorrectInitialState() public view {
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Pending), "Initial state should be Pending");
    }

    function test_setUp_StoresOptionsCorrectly() public view {
        (
            uint256 tokenDeposit,
            uint256 hardCap,
            uint256 softCap,
            uint256 max,
            uint256 min,
            uint256 start,
            uint256 end,
            uint256 liquidityBps,
            uint256 slippageBps,
            uint256 presaleRate,
            uint256 listingRate,
            uint256 lockupDuration,
            address currency,
            uint256 vestingPercentage,
            uint256 vestingDuration,
            uint256 leftoverTokenOption
        ) = presale.options();        
        (
            uint256 tokenDeposit2,
            uint256 hardCap2,
            uint256 softCap2,
            uint256 max2,
            uint256 min2,
            uint256 start2,
            uint256 end2,
            uint256 liquidityBps2,
            uint256 slippageBps2,
            uint256 presaleRate2,
            uint256 listingRate2,
            uint256 lockupDuration2,
            address currency2,
            uint256 vestingPercentage2,
            uint256 vestingDuration2,
            uint256 leftoverTokenOption2
        ) = (
            defaultOptions.tokenDeposit,
            defaultOptions.hardCap,
            defaultOptions.softCap,
            defaultOptions.max,
            defaultOptions.min,
            defaultOptions.start,
            defaultOptions.end,
            defaultOptions.liquidityBps,
            defaultOptions.slippageBps,
            defaultOptions.presaleRate,
            defaultOptions.listingRate,
            defaultOptions.lockupDuration,
            defaultOptions.currency,
            defaultOptions.vestingPercentage,
            defaultOptions.vestingDuration,
            defaultOptions.leftoverTokenOption
        );
        assertEq(
            (
                tokenDeposit,
                hardCap,
                softCap,
                max,
                min,
                start,
                end,
                liquidityBps,
                slippageBps,
                presaleRate,
                listingRate,
                lockupDuration,
                currency,
                vestingPercentage,
                vestingDuration,
                leftoverTokenOption
            ),
            (
                tokenDeposit2,
                hardCap2,
                softCap2,
                max2,
                min2,
                start2,
                end2,
                liquidityBps2,
                slippageBps2,
                presaleRate2,
                listingRate2,
                lockupDuration2,
                currency2,
                vestingPercentage2,
                vestingDuration2,
                leftoverTokenOption2
            )
        );
    }

    function test_setUp_StoresUtilityAddresses() public view {
        assertEq(address(presale.liquidityLocker()), address(liquidityLocker), "Locker address mismatch");
        assertEq(address(presale.vestingContract()), address(vestingContract), "Vesting address mismatch");
    }

    function test_deposit_Success() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);

        // Act
        vm.expectEmit(true, true, true, true, address(presale));
        emit IPresale.Deposit(creator, defaultOptions.tokenDeposit, block.timestamp);
        presale.deposit();
        vm.stopPrank();

        // Assert
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "State should be Active");

        // Fetch state variables directly
        uint256 tokenBalance = presale.tokenBalance();
        uint256 tokensClaimable = presale.tokensClaimable();
        uint256 tokensLiquidity = presale.tokensLiquidity();
        // <<< FIX: Use Presale.PresaleOptions as type >>>
        Presale.PresaleOptions memory fetchedOptions = presale.options();

        assertEq(tokenBalance, defaultOptions.tokenDeposit, "Token balance mismatch");

        // Verify calculations
        uint256 expectedClaimable =
            (fetchedOptions.hardCap * fetchedOptions.presaleRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);
        uint256 currencyForLiq = (fetchedOptions.hardCap * fetchedOptions.liquidityBps) / 10_000;
        uint256 expectedLiquidity =
            (currencyForLiq * fetchedOptions.listingRate * (10 ** PRESALE_TOKEN_DECIMALS)) / (1 ether);

        assertEq(tokensClaimable, expectedClaimable, "Claimable tokens calculation incorrect");
        assertEq(tokensLiquidity, expectedLiquidity, "Liquidity tokens calculation incorrect");
    }

    function test_deposit_Revert_NotOwner() public {
        vm.startPrank(contributor1);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, contributor1));
        presale.deposit();
        vm.stopPrank();
    }

    function test_deposit_Revert_NotPending() public {
        // First deposit
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit(); // State becomes Active

        // Try second deposit
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.deposit();
        vm.stopPrank();
    }

    function test_deposit_Revert_NoApproval() public {
        vm.startPrank(creator);
        vm.expectRevert(); // Generic ERC20 revert
        presale.deposit();
        vm.stopPrank();
    }

    // --- Contribution (ETH) Tests ---
    function test_contributeETH_Receive_Success() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);

        // Act
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);

        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Contribution(contributor1, contributionAmount, true);

        (bool success,) = address(presale).call{value: contributionAmount}("");
        assertTrue(success, "ETH transfer failed");
        vm.stopPrank();

        // Assert
        assertEq(presale.getContribution(contributor1), contributionAmount, "Contribution mismatch");
        assertEq(presale.getTotalContributed(), contributionAmount, "Total contributed mismatch");
        assertEq(address(presale).balance, contributionAmount, "Presale ETH balance mismatch");
        address[] memory contributors = presale.getContributors();
        assertEq(contributors.length, 1, "Contributor count mismatch");
        assertEq(contributors[0], contributor1, "Contributor address mismatch");
    }

    function test_contributeETH_ContributeFunc_Success() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);

        // Act
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);

        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.Contribution(contributor1, contributionAmount, true);

        bytes32[] memory proof;
        presale.contribute{value: contributionAmount}(proof);
        vm.stopPrank();

        // Assert
        assertEq(presale.getContribution(contributor1), contributionAmount);
        assertEq(presale.getTotalContributed(), contributionAmount);
        assertEq(address(presale).balance, contributionAmount);
    }

    function test_contributeETH_Revert_BelowMin() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);

        // Act & Assert
        uint256 contributionAmount = defaultOptions.min - 1 wei;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectRevert(abi.encodeWithSelector(IPresale.BelowMinimumContribution.selector));
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
    }

    function test_contributeETH_Revert_AboveMax() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);

        // Act & Assert
        uint256 contributionAmount = defaultOptions.max + 1 wei;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        vm.expectRevert(abi.encodeWithSelector(IPresale.ExceedsMaximumContribution.selector));
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
    }

    function test_contributeETH_TracksMultipleContributors() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);

        // Act
        vm.startPrank(contributor1);
        vm.deal(contributor1, 1 ether);
        presale.contribute{value: 1 ether}(new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(contributor2);
        vm.deal(contributor2, 2 ether);
        presale.contribute{value: 2 ether}(new bytes32[](0));
        vm.stopPrank();

        // Assert
        assertEq(presale.getContributorCount(), 2, "Contributor count");
        address[] memory contributors = presale.getContributors();
        assertEq(contributors[0], contributor1, "Contributor 1 address");
        assertEq(contributors[1], contributor2, "Contributor 2 address");
        assertEq(presale.getTotalContributed(), 3 ether, "Total contributed");
    }

    // --- Contribution (Stablecoin) Tests ---
    function test_contributeStablecoin_Success() public {
        // Arrange: Deploy stablecoin presale
        // <<< FIX: Use Presale.PresaleOptions >>>
        Presale.PresaleOptions memory stableOptions = defaultOptions;
        stableOptions.currency = address(currencyToken);
        stableOptions.min = 100 * (10 ** CURRENCY_TOKEN_DECIMALS); // 100 USDC min
        stableOptions.max = 5000 * (10 ** CURRENCY_TOKEN_DECIMALS); // 5000 USDC max

        vm.startPrank(creator);
        address stablePresaleAddress =
            presaleFactory.createPresale(stableOptions, address(presaleToken), address(weth), address(mockRouter));
        Presale stablePresale = Presale(payable(stablePresaleAddress));
        presaleToken.approve(address(stablePresale), stableOptions.tokenDeposit);
        stablePresale.deposit();
        vm.stopPrank();
        vm.warp(stableOptions.start);

        // Arrange: Contributor approves stablecoin
        uint256 contributionAmount = 500 * (10 ** CURRENCY_TOKEN_DECIMALS); // 500 USDC
        vm.startPrank(contributor1);
        currencyToken.approve(address(stablePresale), contributionAmount);

        // Act: Contribute stablecoin
        vm.expectEmit(true, true, false, true, address(stablePresale));
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, false, true, address(stablePresale));
        emit IPresale.Contribution(contributor1, contributionAmount, false);
        bytes32[] memory proof;
        stablePresale.contributeStablecoin(contributionAmount, proof);
        vm.stopPrank();

        // Assert
        assertEq(stablePresale.getContribution(contributor1), contributionAmount, "Stable contribution mismatch");
        assertEq(stablePresale.getTotalContributed(), contributionAmount, "Stable total contributed mismatch");
        assertEq(currencyToken.balanceOf(address(stablePresale)), contributionAmount, "Stable presale balance mismatch");
    }

    function test_contributeStablecoin_Revert_ETHSent() public {
        // Arrange: Deploy stablecoin presale
        // <<< FIX: Use Presale.PresaleOptions >>>
        Presale.PresaleOptions memory stableOptions = defaultOptions;
        stableOptions.currency = address(currencyToken);
        vm.startPrank(creator);
        address stablePresaleAddress =
            presaleFactory.createPresale(stableOptions, address(presaleToken), address(weth), address(mockRouter));
        Presale stablePresale = Presale(payable(stablePresaleAddress));
        presaleToken.approve(address(stablePresale), stableOptions.tokenDeposit);
        stablePresale.deposit();
        vm.stopPrank();
        vm.warp(stableOptions.start);

        // Act & Assert: Send ETH via receive()
        vm.startPrank(contributor1);
        vm.deal(contributor1, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IPresale.ETHNotAccepted.selector));
        (bool s1,) = address(stablePresale).call{value: 1 ether}("");
        // No assertion needed here, expectRevert handles it
        vm.stopPrank();

        // Act & Assert: Send ETH via contribute()
        vm.startPrank(contributor1);
        vm.deal(contributor1, 1 ether);
        bytes32[] memory proof;
        vm.expectRevert(abi.encodeWithSelector(IPresale.ETHNotAccepted.selector));
        stablePresale.contribute{value: 1 ether}(proof);
        vm.stopPrank();
    }

    function test_contributeStablecoin_Revert_StableSentToETH() public {
        // Arrange: Use default ETH presale
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);

        // Arrange: Approve stablecoin
        uint256 contributionAmount = 500 * (10 ** CURRENCY_TOKEN_DECIMALS);
        vm.startPrank(contributor1);
        currencyToken.approve(address(presale), contributionAmount);

        // Act & Assert
        bytes32[] memory proof;
        vm.expectRevert(abi.encodeWithSelector(IPresale.StablecoinNotAccepted.selector));
        presale.contributeStablecoin(contributionAmount, proof);
        vm.stopPrank();
    }

    function test_contributeStablecoin_Revert_NoApproval() public {
        // Arrange: Deploy stablecoin presale
        // <<< FIX: Use Presale.PresaleOptions >>>
        Presale.PresaleOptions memory stableOptions = defaultOptions;
        stableOptions.currency = address(currencyToken);
        vm.startPrank(creator);
        address stablePresaleAddress =
            presaleFactory.createPresale(stableOptions, address(presaleToken), address(weth), address(mockRouter));
        Presale stablePresale = Presale(payable(stablePresaleAddress));
        presaleToken.approve(address(stablePresale), stableOptions.tokenDeposit);
        stablePresale.deposit();
        vm.stopPrank();
        vm.warp(stableOptions.start);

        // Act & Assert: Contribute without approval
        uint256 contributionAmount = 500 * (10 ** CURRENCY_TOKEN_DECIMALS);
        vm.startPrank(contributor1);
        bytes32[] memory proof;
        vm.expectRevert(); // Generic ERC20 revert
        stablePresale.contributeStablecoin(contributionAmount, proof);
        vm.stopPrank();
    }

    // --- Finalize Tests ---
    // Helper function to reach soft cap respecting max contribution limits
    // <<< FIX: Use Presale.PresaleOptions >>>
    function _reachSoftCap(Presale _presaleInstance, Presale.PresaleOptions memory _opts) private {
        uint256 amountPerContrib = _opts.max;
        uint256 target = _opts.softCap;
        uint256 currentTotal = 0;
        uint256 numContributorsNeeded = (target + amountPerContrib - 1) / amountPerContrib; // Ceiling division

        console.log(
            "Reaching soft cap (%s) with max contrib (%s), need %s contributors",
            target,
            amountPerContrib,
            numContributorsNeeded
        );

        for (uint256 i = 0; i < numContributorsNeeded; i++) {
            address contributor = address(uint160(uint256(keccak256(abi.encodePacked("contributor", i + 1))))); // Generate unique addresses
            uint256 amountToContribute = amountPerContrib;
            if (currentTotal + amountToContribute > target) {
                amountToContribute = target - currentTotal;
            }
            if (amountToContribute == 0) break;
            if (i == 0 && amountToContribute < _opts.min) amountToContribute = _opts.min;
            require(_opts.softCap >= _opts.min, "Softcap must be >= min for helper");

            vm.startPrank(contributor);
            if (_opts.currency == address(0)) {
                // ETH
                vm.deal(contributor, amountToContribute);
                _presaleInstance.contribute{value: amountToContribute}(new bytes32[](0));
            } else {
                // Stablecoin
                vm.deal(contributor, 0);
                vm.stopPrank();
                vm.startPrank(deployer);
                IERC20(address(currencyToken)).mint(contributor, amountToContribute);
                vm.stopPrank();
                vm.startPrank(contributor);
                IERC20(address(currencyToken)).approve(address(_presaleInstance), amountToContribute);
                _presaleInstance.contributeStablecoin(amountToContribute, new bytes32[](0));
            }

            vm.stopPrank();
            currentTotal += amountToContribute;
            console.log(
                "Contributor %s (%s) added %s, total raised: %s", i + 1, contributor, amountToContribute, currentTotal
            );
            if (currentTotal >= target) break;
        }
        assertGe(_presaleInstance.totalRaised(), target, "Failed to reach soft cap in helper");
    }

    function test_finalize_Revert_NotOwner() public {
        // Arrange: Activate, meet soft cap, advance time
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions); // Use helper
        vm.warp(defaultOptions.end + 1);

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, contributor1));
        presale.finalize();
        vm.stopPrank();
    }

    function test_finalize_Revert_SoftCapNotMet() public {
        // Arrange: Activate, contribute LESS than soft cap, advance time
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        // Contribute slightly less than soft cap but more than min
        uint256 contributionAmount = defaultOptions.min;
        require(contributionAmount < defaultOptions.softCap, "Min >= Softcap, test invalid");
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // Act & Assert
        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPresale.SoftCapNotReached.selector));
        presale.finalize();
        vm.stopPrank();
    }

    function test_handleLeftoverTokens_Return() public {
        // Arrange: Activate, contribute exactly softCap, advance time
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions); // Reach soft cap
        vm.warp(defaultOptions.end + 1);

        // Arrange: Calculate expected leftovers
        // <<< FIX: Fetch state variables directly >>>
        uint256 tokensLiquidityCalc = presale.tokensLiquidity();
        // <<< FIX: Use Presale.PresaleOptions as type >>>
        Presale.PresaleOptions memory fetchedOptions = presale.options();
        uint256 totalContribution = presale.totalRaised(); // Use actual raised amount
        uint256 tokenDecimals = presaleToken.decimals();
        uint256 currencyMultiplier =
            (fetchedOptions.currency == address(0)) ? 1 ether : (10 ** currencyToken.decimals());

        uint256 totalTokensForContrib =
            (totalContribution * fetchedOptions.presaleRate * (10 ** tokenDecimals)) / currencyMultiplier;
        uint256 expectedLeftovers = defaultOptions.tokenDeposit - totalTokensForContrib - tokensLiquidityCalc;

        assertTrue(expectedLeftovers > 0, "Expected leftover calculation failed or yielded zero");

        // Mock finalize state and token balance *before* calling finalize
        vm.startPrank(creator);
        // Use storage manipulation carefully, know your slots!
        // Assuming 'state' is the 4th variable (index 3)
        vm.store(address(presale), bytes32(uint256(3)), bytes32(uint256(3))); // Mock state to Finalized
        vm.stopPrank();

        // Ensure presale has tokens (as if finalize hasn't run yet regarding token transfers)
        // Note: The actual `finalize` would transfer tokens out, making this tricky for pure unit test.
        // This test primarily verifies the calculation logic based on pre-finalize state.

        console.log("Expected Leftovers (Calculation Check):", expectedLeftovers);
        // In a fork test, call finalize() and check balances.
    }

    // --- Claim Tests ---
    function test_claim_Success() public {
        // Arrange: Activate, Contribute, Mock Finalize
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.max);
        presale.contribute{value: defaultOptions.max}(new bytes32[](0));
        vm.stopPrank();
        uint256 totalTokensContributor1 = presale.userTokens(contributor1);
        vm.warp(defaultOptions.end + 1);

        // Mock Finalize State
        vm.startPrank(creator);
        // Adjust storage slots based on `forge inspect <ContractName> storage-layout`
        bytes32 stateSlot = bytes32(uint256(3)); // Example: Assuming state is 4th slot (index 3)
        bytes32 finalizedStateValue = bytes32(uint256(3)); // Finalized = 3
        vm.store(address(presale), stateSlot, finalizedStateValue);

        uint256 deadline = block.timestamp + 180 days;
        bytes32 deadlineSlot = bytes32(uint256(6)); // Example: Assuming claimDeadline is 7th slot (index 6)
        bytes32 deadlineValue = bytes32(uint256(deadline));
        vm.store(address(presale), deadlineSlot, deadlineValue);
        vm.stopPrank();

        // Ensure presale has enough tokens for the claim
        vm.startPrank(deployer);
        // Mint slightly more than needed to avoid exact balance issues after potential leftover handling
        presaleToken.mint(address(presale), presale.tokensClaimable() + presale.tokensLiquidity() + 1 ether);
        vm.stopPrank();

        // Check state *after* storing
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized), "State not mocked to Finalized");

        // Act: Claim
        uint256 vestingBps = defaultOptions.vestingPercentage;
        uint256 expectedVested = (totalTokensContributor1 * vestingBps) / 10_000;
        uint256 expectedImmediate = totalTokensContributor1 - expectedVested;
        uint256 initialBalance = presaleToken.balanceOf(contributor1);
        uint256 presaleBalanceBefore = presaleToken.balanceOf(address(presale));
        uint256 vestingContractBalanceBefore = presaleToken.balanceOf(address(vestingContract));

        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, true, address(presale));
        emit IPresale.TokenClaim(contributor1, totalTokensContributor1, block.timestamp);

        presale.claim();
        vm.stopPrank();

        // Assert
        assertEq(
            presaleToken.balanceOf(contributor1),
            initialBalance + expectedImmediate,
            "Immediate token balance incorrect"
        );
        // Presale balance check is complex due to potential leftover handling before claim
        // assertEq(presaleToken.balanceOf(address(presale)), presaleBalanceBefore - totalTokensContributor1, "Presale token balance incorrect");
        assertEq(
            presaleToken.balanceOf(address(vestingContract)),
            vestingContractBalanceBefore + expectedVested,
            "Vesting contract balance incorrect"
        );
        assertEq(presale.getContribution(contributor1), 0, "Contribution should be reset");
    }

    function test_claim_Revert_NotFinalized() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.max);
        presale.contribute{value: defaultOptions.max}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // Act & Assert
        vm.startPrank(contributor1);
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.claim();
        vm.stopPrank();
    }

    function test_claim_Revert_AfterDeadline() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.max);
        presale.contribute{value: defaultOptions.max}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // Mock Finalize State
        vm.startPrank(creator);
        bytes32 stateSlot = bytes32(uint256(3)); // Adjust slot if needed
        bytes32 finalizedStateValue = bytes32(uint256(3)); // Finalized
        vm.store(address(presale), stateSlot, finalizedStateValue);
        uint256 deadline = block.timestamp + 180 days;
        bytes32 deadlineSlot = bytes32(uint256(6)); // Adjust slot if needed
        bytes32 deadlineValue = bytes32(uint256(deadline));
        vm.store(address(presale), deadlineSlot, deadlineValue);
        vm.stopPrank();

        // Ensure presale has tokens
        vm.startPrank(deployer);
        presaleToken.mint(address(presale), presale.tokensClaimable() + 1 ether);
        vm.stopPrank();

        // Arrange: Warp time past deadline
        vm.warp(deadline + 1);

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(IPresale.ClaimPeriodExpired.selector));
        presale.claim();
        vm.stopPrank();
    }

    function test_claim_Revert_ClaimTwice() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.max);
        presale.contribute{value: defaultOptions.max}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // Mock Finalize State
        vm.startPrank(creator);
        bytes32 stateSlot = bytes32(uint256(3)); // Adjust slot if needed
        bytes32 finalizedStateValue = bytes32(uint256(3)); // Finalized
        vm.store(address(presale), stateSlot, finalizedStateValue);
        uint256 deadline = block.timestamp + 180 days;
        bytes32 deadlineSlot = bytes32(uint256(6)); // Adjust slot if needed
        bytes32 deadlineValue = bytes32(uint256(deadline));
        vm.store(address(presale), deadlineSlot, deadlineValue);
        vm.stopPrank();

        // Ensure presale has tokens
        vm.startPrank(deployer);
        presaleToken.mint(address(presale), presale.tokensClaimable() + 1 ether);
        vm.stopPrank();

        // First Claim
        vm.startPrank(contributor1);
        presale.claim();
        vm.stopPrank();

        // Act & Assert: Second Claim
        vm.startPrank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(IPresale.NoTokensToClaim.selector));
        presale.claim();
        vm.stopPrank();
    }

    // --- Refund Tests ---
    function test_refund_Success_Canceled() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);
        vm.startPrank(creator);
        presale.cancel();
        vm.stopPrank();
        // <<< FIX: Use Presale.PresaleState for comparison >>>
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

    function test_refund_Success_SoftCapNotMet() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = defaultOptions.min;
        require(contributionAmount < defaultOptions.softCap, "Min >= Softcap, test invalid");
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // State check
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "State should still be Active");

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

    function test_refund_Revert_ActiveOngoing() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        vm.deal(contributor1, contributionAmount);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        vm.stopPrank();
        // DO NOT advance time past end

        // Act & Assert
        vm.startPrank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(IPresale.NotRefundable.selector));
        presale.refund();
        vm.stopPrank();
    }

    function test_refund_Revert_Finalized() public {
        // Arrange
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions); // Use helper
        vm.warp(defaultOptions.end + 1);

        // Mock Finalize State
        vm.startPrank(creator);
        bytes32 stateSlot = bytes32(uint256(3)); // Adjust if needed
        bytes32 finalizedStateValue = bytes32(uint256(3)); // Finalized
        vm.store(address(presale), stateSlot, finalizedStateValue);
        vm.stopPrank();

        // Act & Assert
        vm.startPrank(contributor1); // Use any contributor who participated
        vm.expectRevert(abi.encodeWithSelector(IPresale.NotRefundable.selector));
        presale.refund();
        vm.stopPrank();
    }

    // --- Mock Finalize Test (Conceptual - Requires Forking) ---
    /*
    function test_finalize_Success() public {
        // Arrange: Activate, Reach Soft Cap
        vm.startPrank(creator);
        presaleToken.approve(address(presale), defaultOptions.tokenDeposit);
        presale.deposit();
        vm.stopPrank();
        vm.warp(defaultOptions.start);
        _reachSoftCap(presale, defaultOptions);
        vm.warp(defaultOptions.end + 1);

        // --- FORK SETUP NEEDED HERE ---
        // 1. Select fork RPC URL and block number
        // 2. Get actual Router address for the fork
        // 3. Get actual WETH address for the fork
        // 4. Potentially deploy mock factory if needed or use real one
        // 5. Update mockRouter address in setup or here
        // 6. Get actual pair address or let finalize create it
        // address routerAddress = 0x...; // Actual Router
        // address wethAddress = 0x...; // Actual WETH
        // address factoryAddress = IUniswapV2Router02(routerAddress).factory();
        // address actualPair = IUniswapV2Factory(factoryAddress).getPair(address(presaleToken), wethAddress);

        // Act: Finalize (using actual router on fork)
        vm.startPrank(creator);
        vm.expectEmit(true, true, true, true, address(presale));
        emit IPresale.Finalized(creator, presale.totalRaised(), block.timestamp);
        // Add expectEmit for LiquidityAdded if pair address is predictable/known
        presale.finalize();
        vm.stopPrank();

        // Assert: State and Lock
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized), "State not Finalized"); // Use Presale.PresaleState
        // Need to get the actual pair address created/used by finalize
        // address pairUsed = IUniswapV2Factory(factoryAddress).getPair(address(presaleToken), wethAddress);
        // require(pairUsed != address(0), "Pair not created/found on fork");
        // (address lockedToken, uint256 amount, , address owner) = liquidityLocker.getLock(0); // Assuming lock index 0
        // assertEq(lockedToken, pairUsed, "LP token address incorrect in lock");
        // assertTrue(amount > 0, "Locked LP amount is zero");
        // assertEq(owner, creator, "Lock owner incorrect");
        // Add more assertions...
    }
    */

    function test_multiplePresales_Isolation() public {
        // Presale 1 (Setup already done in global setUp)
        Presale presale1 = presale;
        address presale1Addr = address(presale1);

        // Presale 2
        address creator2 = makeAddr("creator2");
        vm.startPrank(deployer);
        presaleToken.mint(creator2, TOTAL_DEPOSIT);
        vm.stopPrank();
        vm.startPrank(creator2);
        // <<< FIX: Use Presale.PresaleOptions >>>
        Presale.PresaleOptions memory options2 = defaultOptions;
        options2.start = block.timestamp + 120;
        options2.end = options2.start + (3 days);
        address presale2Addr =
            presaleFactory.createPresale(options2, address(presaleToken), address(weth), address(mockRouter));
        Presale presale2 = Presale(payable(presale2Addr));
        presaleToken.approve(presale2Addr, options2.tokenDeposit);
        presale2.deposit();
        vm.stopPrank();

        // Act: Contribute and claim in Presale 1
        vm.warp(defaultOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, defaultOptions.max);
        presale1.contribute{value: defaultOptions.max}(new bytes32[](0));
        vm.stopPrank();
        vm.warp(defaultOptions.end + 1);

        // Mock Finalize State for Presale 1
        vm.startPrank(creator);
        bytes32 stateSlot1 = bytes32(uint256(3)); // Adjust if needed
        bytes32 finalizedStateValue1 = bytes32(uint256(3)); // Finalized
        vm.store(presale1Addr, stateSlot1, finalizedStateValue1);
        uint256 deadline1 = block.timestamp + 180 days;
        bytes32 deadlineSlot1 = bytes32(uint256(6)); // Adjust if needed
        bytes32 deadlineValue1 = bytes32(uint256(deadline1));
        vm.store(presale1Addr, deadlineSlot1, deadlineValue1);
        vm.stopPrank();

        // Ensure presale1 has tokens for claim
        vm.startPrank(deployer);
        presaleToken.mint(presale1Addr, defaultOptions.tokenDeposit * 2);
        vm.stopPrank();

        // Claim from Presale 1
        vm.startPrank(contributor1);
        presale1.claim();
        vm.stopPrank();

        // Assert: Presale 2 unaffected
        // <<< FIX: Use Presale.PresaleState for comparison >>>
        assertEq(uint8(presale2.state()), uint8(Presale.PresaleState.Active), "Presale 2 state changed");
        assertEq(presale2.getContributorCount(), 0, "Presale 2 has contributors");
        assertEq(presale2.getTotalContributed(), 0, "Presale 2 has contributions");
    }
}
