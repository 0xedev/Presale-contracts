// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PresaleFactory} from "../src/contracts/PresaleFactory.sol";
import {Presale} from "../src/contracts/Presale.sol";
import {LiquidityLocker} from "../src/contracts/LiquidityLocker.sol";
import {Vesting} from "../src/contracts/Vesting.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {ERC721Mock} from "test/mocks/mockErc721.sol";
import {IPresale} from "../src/contracts/interfaces/IPresale.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract PresaleForkTest is Test {
    using SafeERC20 for IERC20;

    // Sepolia Addresses
    address constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant SEPOLIA_ROUTER = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;

    PresaleFactory factory;
    ERC20Mock presaleToken;
    ERC20Mock currencyToken;
    address deployer;
    address contributor1;
    address contributor2;
    address houseFeeAddress;

    string sepoliaRpcUrl;

    function setUp() public {
        sepoliaRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        require(bytes(sepoliaRpcUrl).length > 0, "SEPOLIA_RPC_URL env var not set");
        vm.createSelectFork(sepoliaRpcUrl);

        deployer = makeAddr("deployer");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");
        houseFeeAddress = makeAddr("houseFeeAddress");

        vm.label(deployer, "Deployer/Owner");
        vm.label(contributor1, "Contributor1");
        vm.label(contributor2, "Contributor2");
        vm.label(houseFeeAddress, "HouseFeeAddress");
        vm.label(SEPOLIA_WETH, "Sepolia_WETH");
        vm.label(SEPOLIA_ROUTER, "Sepolia_Router");

        vm.deal(deployer, 100 ether);
        vm.deal(contributor1, 10 ether);
        vm.deal(contributor2, 10 ether);

        vm.startPrank(deployer);
        presaleToken = new ERC20Mock(); // No constructor args
        presaleToken.mint(deployer, 1_000_000 * 1e18);
        currencyToken = new ERC20Mock(); // No constructor args
        currencyToken.mint(deployer, 1_000_000 * 1e18);
        currencyToken.mint(contributor1, 1_000_000 * 1e18);
        currencyToken.mint(contributor2, 1_000_000 * 1e18);

        uint256 creationFee = 0.01 ether;
        address feeTokenForFactory = address(0);
        uint256 houseBps = 100;

        factory = new PresaleFactory(creationFee, feeTokenForFactory, houseBps, houseFeeAddress);
        vm.stopPrank();
    }

    function _getDefaultPresaleOptions(address _currency)
        internal
        view
        returns (Presale.PresaleOptions memory options)
    {
        uint256 currencyMultiplier = 1 ether;
        uint8 currencyDecimals = 18;
        if (_currency != address(0)) {
            currencyDecimals = ERC20(_currency).decimals();
            currencyMultiplier = 10 ** currencyDecimals;
        }

        uint256 hardCapAmount = 10;
        uint256 softCapAmount = 5;
        uint256 minContribAmount = 1;
        uint256 maxContribAmount = 5;

        options = Presale.PresaleOptions({
            tokenDeposit: 0,
            hardCap: hardCapAmount * currencyMultiplier,
            softCap: softCapAmount * currencyMultiplier,
            min: minContribAmount * currencyMultiplier,
            max: maxContribAmount * currencyMultiplier,
            presaleRate: 1000,
            listingRate: 800,
            liquidityBps: 7000,
            slippageBps: 500,
            start: block.timestamp + 1 hours,
            end: block.timestamp + 25 hours,
            lockupDuration: 30 days,
            vestingPercentage: 2000,
            vestingDuration: 15 days,
            leftoverTokenOption: 0,
            currency: _currency,
            whitelistType: Presale.WhitelistType.None,
            merkleRoot: bytes32(0),
            nftContractAddress: address(0)
        });

        uint256 requiredTokens = factory.calculateTotalTokensNeededForPresale(options, address(presaleToken));
        options.tokenDeposit = requiredTokens;
    }

    function test_Fork_FullCycle_ETH_Presale() public {
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(0));
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "ETH_Presale");
        vm.stopPrank();

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "Presale should be Active");
        assertEq(presale.tokenBalance(), requiredTokenDeposit, "Initial token balance mismatch");

        vm.warp(presaleOptions.start);

        uint256 contribution1Amount = 3 ether;
        uint256 contribution2Amount = 4 ether;
        vm.prank(contributor1);
        presale.contribute{value: contribution1Amount}(new bytes32[](0));
        vm.prank(contributor2);
        presale.contribute{value: contribution2Amount}(new bytes32[](0));

        assertEq(presale.totalRaised(), contribution1Amount + contribution2Amount, "Total raised mismatch");

        vm.warp(presaleOptions.end + 1 hours);
        assertTrue(presale.totalRaised() >= presaleOptions.softCap, "Softcap not met for finalization");

        (bool canAdd,,) = presale.simulateLiquidityAddition();
        assertTrue(canAdd, "Simulate liquidity addition should be true");

        vm.prank(deployer);
        assertTrue(presale.finalize(), "Finalization failed");

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized), "Presale should be Finalized");

        uint256 expectedHouseFee = (presale.totalRaised() * factory.housePercentage()) / 10_000;
        assertEq(houseFeeAddress.balance, expectedHouseFee, "House fee mismatch");

        LiquidityLocker locker = factory.liquidityLocker();
        require(locker.lockCount() > 0, "No LP lock found");
        (, uint256 lpAmount, uint256 unlockTime, address lockOwner) = locker.getLock(0);
        assertTrue(lpAmount > 0, "LP amount should be > 0");
        assertEq(lockOwner, deployer, "LP lock owner mismatch");
        assertEq(unlockTime, block.timestamp + presaleOptions.lockupDuration, "LP unlock time mismatch");

        uint256 ownerBalanceBeforeWithdraw = presale.ownerBalance();
        assertTrue(ownerBalanceBeforeWithdraw > 0, "Owner balance should be > 0 after finalize");
        vm.prank(deployer);
        uint256 deployerEthBefore = deployer.balance;
        presale.withdraw();
        assertApproxEqAbs(
            deployer.balance - deployerEthBefore,
            ownerBalanceBeforeWithdraw,
            0.01 ether,
            "Owner withdrawal amount mismatch"
        );

        uint256 totalTokensC1 = presale.userTokens(contributor1);
        uint256 vestingBps = presaleOptions.vestingPercentage;
        uint256 immediateTokensC1 = (totalTokensC1 * (10_000 - vestingBps)) / 10_000;
        uint256 vestedTokensC1 = totalTokensC1 - immediateTokensC1;

        vm.prank(contributor1);
        presale.claim();
        assertEq(presaleToken.balanceOf(contributor1), immediateTokensC1, "C1 immediate token balance mismatch");

        Vesting vestingContract = factory.vestingContract();
        if (vestedTokensC1 > 0) {
            (, uint256 totalAmountC1,,,, bool existsC1) = vestingContract.schedules(presaleAddress, contributor1);
            assertTrue(existsC1, "Vesting schedule for C1 should exist");
            assertEq(totalAmountC1, vestedTokensC1, "C1 vested amount mismatch");
        }

        uint256 totalTokensC2 = presale.userTokens(contributor2);
        uint256 immediateTokensC2 = (totalTokensC2 * (10_000 - vestingBps)) / 10_000;
        uint256 vestedTokensC2 = totalTokensC2 - immediateTokensC2;

        vm.prank(contributor2);
        presale.claim();
        assertEq(presaleToken.balanceOf(contributor2), immediateTokensC2, "C2 immediate token balance mismatch");

        if (vestedTokensC2 > 0) {
            (, uint256 totalAmountC2,,,, bool existsC2) = vestingContract.schedules(presaleAddress, contributor2);
            assertTrue(existsC2, "Vesting schedule for C2 should exist");
            assertEq(totalAmountC2, vestedTokensC2, "C2 vested amount mismatch");
        }

        if (vestedTokensC1 > 0) {
            // We need to re-fetch or use the values from the earlier destructuring for C1
            (
                /*address tokenAddressC1_vesting*/
                ,
                /*uint256 totalAmountC1_vesting*/
                ,
                uint256 releasedC1_vesting_before_release,
                uint256 startC1_vesting,
                /*uint256 durationC1_vesting*/
                ,
                /*bool existsC1_vesting*/
            ) = vestingContract.schedules(presaleAddress, contributor1);

            uint256 vestingDurationC1 = presaleOptions.vestingDuration;
            vm.warp(startC1_vesting + vestingDurationC1 + 1 days);

            uint256 releasableC1Before =
                vestingContract.vestedAmount(presaleAddress, contributor1) - releasedC1_vesting_before_release;
            assertApproxEqAbs(
                releasableC1Before, vestedTokensC1, 1, "C1 releasable amount should be full vested amount"
            );

            vm.prank(contributor1);
            vestingContract.release(presaleAddress);
            assertEq(
                presaleToken.balanceOf(contributor1),
                totalTokensC1,
                "C1 total token balance after vesting release mismatch"
            );
        }
    }

    function test_Fork_Refund_SoftCapNotMet() public {
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(0));
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.stopPrank();

        vm.warp(presaleOptions.start);
        vm.prank(contributor1);
        presale.contribute{value: 2 ether}(new bytes32[](0)); // Below soft cap (5 ETH)

        vm.warp(presaleOptions.end + 1);
        vm.prank(contributor1);
        uint256 balanceBefore = contributor1.balance;
        presale.refund();
        assertEq(contributor1.balance, balanceBefore + 2 ether, "Refund amount mismatch");
        assertEq(presale.getContribution(contributor1), 0, "Contribution not reset");
    }

    function test_Fork_CancelPresale_And_Refund() public {
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(0));
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.stopPrank();

        vm.warp(presaleOptions.start);
        uint256 contributionAmount = 3 ether;
        vm.prank(contributor1);
        presale.contribute{value: contributionAmount}(new bytes32[](0));

        uint256 deployerTokenBalanceBeforeCancel = presaleToken.balanceOf(deployer);
        vm.prank(deployer);
        presale.cancel();

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Canceled), "Presale should be Canceled");
        // Check that the presale tokens were returned to the deployer during cancel()
        assertEq(
            presaleToken.balanceOf(deployer),
            deployerTokenBalanceBeforeCancel + requiredTokenDeposit,
            "Token deposit not returned during cancel"
        );

        vm.prank(contributor1);
        uint256 balanceBefore = contributor1.balance;
        presale.refund();
        assertEq(contributor1.balance, balanceBefore + contributionAmount, "Refund amount mismatch");
        assertEq(presale.getContribution(contributor1), 0, "Contribution not reset");
    }

    function test_Fork_FullCycle_Stablecoin_Presale() public {
        // Deploy mock USDC with 6 decimals
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000 * 1e6);
        usdc.mint(contributor2, 1_000_000 * 1e6);
        vm.stopPrank();

        assertEq(usdc.decimals(), 6, "USDC decimals should be 6");

        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "USDC_Presale");
        vm.stopPrank();

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "Presale should be Active");
        assertEq(presale.tokenBalance(), requiredTokenDeposit, "Initial token balance mismatch");

        vm.warp(presaleOptions.start);

        uint256 contribution1Amount = 3 * 1e6;
        uint256 contribution2Amount = 4 * 1e6;
        vm.startPrank(contributor1);
        usdc.approve(presaleAddress, contribution1Amount);
        presale.contributeStablecoin(contribution1Amount, new bytes32[](0));
        vm.stopPrank();
        vm.startPrank(contributor2);
        usdc.approve(presaleAddress, contribution2Amount);
        presale.contributeStablecoin(contribution2Amount, new bytes32[](0));
        vm.stopPrank();

        assertEq(presale.totalRaised(), contribution1Amount + contribution2Amount, "Total raised mismatch");

        vm.warp(presaleOptions.end + 1 hours);
        assertTrue(presale.totalRaised() >= presaleOptions.softCap, "Softcap not met for finalization");

        (bool canAdd,,) = presale.simulateLiquidityAddition();
        assertTrue(canAdd, "Simulate liquidity addition should be true");

        vm.prank(deployer);
        assertTrue(presale.finalize(), "Finalization failed");

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Finalized), "Presale should be Finalized");

        uint256 expectedHouseFee = (presale.totalRaised() * factory.housePercentage()) / 10_000;
        assertEq(usdc.balanceOf(houseFeeAddress), expectedHouseFee, "House fee mismatch");

        LiquidityLocker locker = factory.liquidityLocker();
        require(locker.lockCount() > 0, "No LP lock found");
        (, uint256 lpAmount, uint256 unlockTime, address lockOwner) = locker.getLock(0);
        assertTrue(lpAmount > 0, "LP amount should be > 0");
        assertEq(lockOwner, deployer, "LP lock owner mismatch");
        assertEq(unlockTime, block.timestamp + presaleOptions.lockupDuration, "LP unlock time mismatch");

        uint256 ownerBalanceBeforeWithdraw = presale.ownerBalance();
        assertTrue(ownerBalanceBeforeWithdraw > 0, "Owner balance should be > 0 after finalize");

        address currentOwner = presale.owner();
        console.log("Presale contract owner:", currentOwner);
        console.log("Expected owner (deployer):", deployer);
        assertEq(currentOwner, deployer, "Deployer is not the owner of the presale contract");

        // Debug withdraw
        vm.startPrank(deployer);
        uint256 deployerUsdcBefore = usdc.balanceOf(deployer);
        (bool success, bytes memory data) = address(presale).call(abi.encodeWithSignature("withdraw()"));
        console.log("Withdraw success:", success);
        console.logBytes(data);
        require(success, "Withdraw call failed");
        assertApproxEqAbs(
            usdc.balanceOf(deployer),
            deployerUsdcBefore + ownerBalanceBeforeWithdraw,
            1,
            "Owner withdrawal amount mismatch"
        );
        vm.stopPrank();

        uint256 totalTokensC1 = presale.userTokens(contributor1);

        uint256 vestingBps = presaleOptions.vestingPercentage;
        uint256 immediateTokensC1 = (totalTokensC1 * (10_000 - vestingBps)) / 10_000;
        uint256 vestedTokensC1 = totalTokensC1 - immediateTokensC1;

        vm.prank(contributor1);
        presale.claim();
        assertEq(presaleToken.balanceOf(contributor1), immediateTokensC1, "C1 immediate token balance mismatch");

        Vesting vestingContract = factory.vestingContract();
        if (vestedTokensC1 > 0) {
            (, uint256 totalAmountC1,,,, bool existsC1) = vestingContract.schedules(presaleAddress, contributor1);
            assertTrue(existsC1, "Vesting schedule for C1 should exist");
            assertEq(totalAmountC1, vestedTokensC1, "C1 vested amount mismatch");
        }

        uint256 totalTokensC2 = presale.userTokens(contributor2);
        uint256 immediateTokensC2 = (totalTokensC2 * (10_000 - vestingBps)) / 10_000;
        uint256 vestedTokensC2 = totalTokensC2 - immediateTokensC2;

        vm.prank(contributor2);
        presale.claim();
        assertEq(presaleToken.balanceOf(contributor2), immediateTokensC2, "C2 immediate token balance mismatch");

        if (vestedTokensC2 > 0) {
            (, uint256 totalAmountC2,,,, bool existsC2) = vestingContract.schedules(presaleAddress, contributor2);
            assertTrue(existsC2, "Vesting schedule for C2 should exist");
            assertEq(totalAmountC2, vestedTokensC2, "C2 vested amount mismatch");
        }

        if (vestedTokensC1 > 0) {
            (,, uint256 releasedC1_vesting_before_release, uint256 startC1_vesting,,) =
                vestingContract.schedules(presaleAddress, contributor1);

            uint256 vestingDurationC1 = presaleOptions.vestingDuration;
            vm.warp(startC1_vesting + vestingDurationC1 + 1 days);

            uint256 releasableC1Before =
                vestingContract.vestedAmount(presaleAddress, contributor1) - releasedC1_vesting_before_release;
            assertApproxEqAbs(
                releasableC1Before, vestedTokensC1, 1, "C1 releasable amount should be full vested amount"
            );

            vm.prank(contributor1);
            vestingContract.release(presaleAddress);
            assertEq(
                presaleToken.balanceOf(contributor1),
                totalTokensC1,
                "C1 total token balance after vesting release mismatch"
            );
        }
    }

    function test_Fork_NFT_Whitelist_Presale() public {
        // Deploy mock ERC721
        ERC721Mock nft = new ERC721Mock();
        nft.mint(contributor1, 1);
        assertEq(nft.balanceOf(contributor1), 1, "Contributor1 should own NFT");
        assertEq(nft.balanceOf(contributor2), 0, "Contributor2 should not own NFT");

        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000 * 1e6);
        usdc.mint(contributor2, 1_000_000 * 1e6);
        vm.stopPrank();

        // Create presale with NFT whitelist
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        presaleOptions.whitelistType = Presale.WhitelistType.NFT;
        presaleOptions.nftContractAddress = address(nft);
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "NFT_Whitelist_Presale");
        vm.stopPrank();

        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active), "Presale should be Active");

        vm.warp(presaleOptions.start);

        // Contributor1 (NFT holder) contributes
        uint256 contributionAmount = 3 * 1e6; // 3 USDC
        vm.startPrank(contributor1);
        usdc.approve(presaleAddress, contributionAmount);
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        vm.stopPrank();
        assertEq(presale.totalRaised(), contributionAmount, "Contributor1 contribution failed");

        // Contributor2 (no NFT) attempts to contribute
        vm.startPrank(contributor2);
        usdc.approve(presaleAddress, contributionAmount);
        vm.expectRevert(abi.encodeWithSelector(IPresale.NotNftHolder.selector));
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        vm.stopPrank();

        // Test failed balanceOf call
        vm.mockCallRevert(
            address(nft), abi.encodeWithSignature("balanceOf(address)", contributor1), abi.encode("MockRevert")
        );
        vm.startPrank(contributor1);
        usdc.approve(presaleAddress, contributionAmount); // Re-approve allowance
        vm.expectRevert(abi.encodeWithSelector(IPresale.NftCheckFailed.selector));
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        vm.stopPrank();
    }

    function test_Fork_Initialize_Deposit_Failure_OriginalInstance() public {
        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));

        // Create presale
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "Presale");
        vm.stopPrank();

        assertEq(
            uint8(presale.state()),
            uint8(Presale.PresaleState.Active),
            "Presale should be Active after factory creation"
        );

        // Case 1: Call initializeDeposit when state is already Active (and time is after start)
        vm.warp(presaleOptions.start + 1);
        vm.startPrank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.initializeDeposit();
        vm.stopPrank();

        // Case 2: Call initializeDeposit when state is already Active (and time is before start)
        // The PairAlreadyExists check would only be reached if the state was Pending.
        vm.warp(presaleOptions.start - 1); // Ensure before presale start
        vm.mockCall(SEPOLIA_ROUTER, abi.encodeWithSignature("factory()"), abi.encode(address(0x1234)));
        vm.mockCall(
            address(0x1234),
            abi.encodeWithSignature("getPair(address,address)", address(presaleToken), address(usdc)),
            abi.encode(address(0x5678)) // Simulate pair exists
        );
        vm.startPrank(address(factory));
        // The state is Active, so InvalidState will be hit before PairAlreadyExists.
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.initializeDeposit();
        vm.stopPrank();
        vm.clearMockedCalls();

        // Case 3: Call initializeDeposit on a new presale (presale2) which is also Active.
        // presale2 will be created successfully by the factory, which calls initializeDeposit internally,
        // making presale2 Active.
        Presale.PresaleOptions memory presaleOptionsForPresale2 = _getDefaultPresaleOptions(address(usdc));
        vm.startPrank(deployer);
        presaleToken.approve(address(factory), presaleOptionsForPresale2.tokenDeposit); // Approve enough for successful creation
        address presaleAddress2 = factory.createPresale{value: factory.creationFee()}(
            presaleOptionsForPresale2, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale2 = Presale(payable(presaleAddress2));
        vm.stopPrank();
        vm.startPrank(address(factory));
        // presale2 is already Active, so InvalidState will be hit.
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale2.initializeDeposit();
        vm.stopPrank();

        // Case 4: Non-factory caller
        vm.startPrank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(IPresale.NotFactory.selector));
        presale.initializeDeposit();
        vm.stopPrank();
    }

    function test_Fork_Leftover_Tokens_Burn() public {
        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000 * 1e6);
        vm.stopPrank();

        // Create presale with leftoverTokenOption = 1
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        presaleOptions.leftoverTokenOption = 1; // Burn option
        uint256 requiredTokenDeposit = presaleOptions.tokenDeposit;

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "Burn_Presale");
        vm.stopPrank();

        // Contribute below hard cap
        // Softcap is 5 * 1e6. Let's contribute exactly the softcap.
        uint256 contributionAmount = 5 * 1e6; // 5 USDC
        vm.warp(presaleOptions.start);
        vm.startPrank(contributor1);
        usdc.approve(presaleAddress, contributionAmount);
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        vm.stopPrank();
        uint256 totalRaisedActual = presale.totalRaised();
        assertEq(totalRaisedActual, contributionAmount, "Contribution failed or totalRaised mismatch");
        assertTrue(totalRaisedActual >= presaleOptions.softCap, "Soft cap not met with contribution");

        // Finalize presale as owner
        vm.warp(presaleOptions.end + 1);
        uint256 initialDeadBalance = presaleToken.balanceOf(address(0xdead));
        uint256 initialPresaleBalance = presaleToken.balanceOf(presaleAddress);

        // Calculate expectedBurn accurately based on Presale.sol logic
        // 1. Tokens sold for the raised amount
        uint256 tokensSoldForRaisedAmount =
            (totalRaisedActual * presaleOptions.presaleRate * (10 ** presaleToken.decimals())) / (10 ** usdc.decimals());
        if (tokensSoldForRaisedAmount > presale.tokensClaimable()) {
            tokensSoldForRaisedAmount = presale.tokensClaimable();
        }

        // 2. Unsold presale tokens (from the portion allocated for sale)
        uint256 unsoldPresaleTokens = presale.tokensClaimable() - tokensSoldForRaisedAmount;

        // 3. Tokens used for actual liquidity based on totalRaisedActual
        uint256 currencyForActualLiquidity = (totalRaisedActual * presaleOptions.liquidityBps) / 10_000;
        uint256 tokensNeededForActualLiquidity = (
            currencyForActualLiquidity * presaleOptions.listingRate * (10 ** presaleToken.decimals())
        ) / (10 ** usdc.decimals());
        uint256 tokensUsedForActualLiquidity = tokensNeededForActualLiquidity > presale.tokensLiquidity()
            ? presale.tokensLiquidity()
            : tokensNeededForActualLiquidity;

        // 4. Token balance in contract after liquidity is notionally removed, before leftover handling
        uint256 tokenBalanceAfterLiquidityProvision = initialPresaleBalance - tokensUsedForActualLiquidity;

        // 5. Excess deposit calculation (as per _handleLeftoverTokens logic)
        uint256 excessDeposit;
        uint256 totalTokensNeededAtHardcap = presale.tokensClaimable() + presale.tokensLiquidity();
        if (tokenBalanceAfterLiquidityProvision + presale.tokensLiquidity() > totalTokensNeededAtHardcap) {
            excessDeposit =
                (tokenBalanceAfterLiquidityProvision + presale.tokensLiquidity()) - totalTokensNeededAtHardcap;
        } else {
            excessDeposit = 0;
        }

        uint256 expectedBurn = unsoldPresaleTokens + excessDeposit;
        if (expectedBurn > tokenBalanceAfterLiquidityProvision) {
            // Cannot burn more than what's left
            expectedBurn = tokenBalanceAfterLiquidityProvision;
        }

        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit IPresale.LeftoverTokensBurned(expectedBurn);
        presale.finalize();

        // Assertions
        assertEq(
            presaleToken.balanceOf(address(0xdead)), initialDeadBalance + expectedBurn, "Tokens not burned to 0xdead"
        );
    }

    function test_Fork_Leftover_Tokens_Vest() public {
        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));

        // Mint tokens to contributor
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000_000_000); // 1B USDC
        vm.stopPrank();

        // Create presale with leftoverTokenOption = 2 (vesting)
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        presaleOptions.leftoverTokenOption = 2; // Vest leftover tokens
        uint256 requiredTokenDeposit =
            factory.calculateTotalTokensNeededForPresale(presaleOptions, address(presaleToken));

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "Vesting_Presale");
        vm.stopPrank();

        uint256 contributionAmount = 5_000_000; // 5 USDC (5 * 1e6)
        vm.warp(presaleOptions.start);
        vm.startPrank(contributor1);
        usdc.approve(presaleAddress, contributionAmount);
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        vm.stopPrank();

        // Verify contribution
        assertEq(presale.totalRaised(), 5_000_000, "Contribution failed or totalRaised mismatch");
        assertTrue(presale.totalRaised() >= presaleOptions.softCap, "Soft cap not met");

        // Warp to after presale end and finalize
        vm.warp(presaleOptions.end + 1);
        uint256 initialPresaleTokenBalanceInPresale = presaleToken.balanceOf(presaleAddress);
        uint256 totalRaisedActual = presale.totalRaised();

        // Calculate expectedLeftover accurately based on Presale.sol logic
        // 1. Tokens sold for the raised amount
        uint256 tokensSoldForRaisedAmount =
            (totalRaisedActual * presaleOptions.presaleRate * (10 ** presaleToken.decimals())) / (10 ** usdc.decimals());
        if (tokensSoldForRaisedAmount > presale.tokensClaimable()) {
            tokensSoldForRaisedAmount = presale.tokensClaimable();
        }

        // 2. Unsold presale tokens (from the portion allocated for sale)
        uint256 unsoldPresaleTokens = presale.tokensClaimable() - tokensSoldForRaisedAmount;

        // 3. Tokens used for actual liquidity based on totalRaisedActual
        uint256 currencyForActualLiquidity = (totalRaisedActual * presaleOptions.liquidityBps) / 10_000;
        uint256 tokensNeededForActualLiquidity = (
            currencyForActualLiquidity * presaleOptions.listingRate * (10 ** presaleToken.decimals())
        ) / (10 ** usdc.decimals());
        uint256 tokensUsedForActualLiquidity = tokensNeededForActualLiquidity > presale.tokensLiquidity()
            ? presale.tokensLiquidity()
            : tokensNeededForActualLiquidity;

        // 4. Token balance in presale contract that _handleLeftoverTokens will operate on
        // This is the balance after liquidity provision.
        uint256 tokenBalanceForLeftoverCalc = initialPresaleTokenBalanceInPresale - tokensUsedForActualLiquidity;

        // 5. Excess deposit calculation (as per _handleLeftoverTokens logic in Presale.sol)
        uint256 excessDeposit;
        uint256 totalTokensNeededAtHardcap = presale.tokensClaimable() + presale.tokensLiquidity();
        if (tokenBalanceForLeftoverCalc + presale.tokensLiquidity() > totalTokensNeededAtHardcap) {
            excessDeposit = (tokenBalanceForLeftoverCalc + presale.tokensLiquidity()) - totalTokensNeededAtHardcap;
        } else {
            excessDeposit = 0;
        }

        uint256 expectedLeftover = unsoldPresaleTokens + excessDeposit;
        if (expectedLeftover > tokenBalanceForLeftoverCalc) {
            expectedLeftover = tokenBalanceForLeftoverCalc;
        }

        vm.startPrank(deployer); // Use startPrank for clarity if single prank is suspected
        vm.expectEmit(true, true, true, true);
        emit IPresale.LeftoverTokensVested(expectedLeftover, deployer); // Beneficiary is the presale owner
        bool finalized = presale.finalize();
        vm.stopPrank();
        assertTrue(finalized, "Finalization failed");

        // Verify vesting schedule
        Vesting vestingContract = factory.vestingContract();
        (, uint256 amount, uint256 claimed, uint256 start, uint256 duration,) =
            vestingContract.schedules(presaleAddress, deployer); // Corrected schedule lookup
        assertEq(amount, expectedLeftover, "Vesting schedule amount mismatch");
        assertEq(start, block.timestamp, "Vesting start time incorrect");
        assertEq(duration, presaleOptions.vestingDuration, "Vesting duration incorrect");
        assertEq(claimed, 0, "Vesting claimed amount should be 0");

        // Verify presale token balance
        assertEq(
            presaleToken.balanceOf(presaleAddress),
            initialPresaleTokenBalanceInPresale - tokensUsedForActualLiquidity - expectedLeftover,
            // initialPresaleBalance - tokensUsedForActualLiquidity - expectedLeftover,
            "Presale contract token balance after finalize is incorrect"
        );
    }

    function test_Fork_Leftover_Tokens_Return() public {
        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));

        // Mint tokens to contributor
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000_000_000); // 1B USDC
        vm.stopPrank();

        // Create presale with leftoverTokenOption = 0 (return)
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        presaleOptions.leftoverTokenOption = 0; // Return leftover tokens
        uint256 requiredTokenDeposit =
            factory.calculateTotalTokensNeededForPresale(presaleOptions, address(presaleToken));

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "Return_Presale");
        vm.stopPrank();

        // Contribute below hard cap (5M USDC < 10M hard cap)
        vm.warp(presaleOptions.start);
        vm.startPrank(contributor1);
        usdc.approve(address(presale), 5_000_000);
        presale.contributeStablecoin(5_000_000, new bytes32[](0));
        vm.stopPrank();

        // Verify contribution
        assertEq(presale.totalRaised(), 5_000_000, "Contribution failed or totalRaised mismatch");
        assertTrue(presale.totalRaised() >= presaleOptions.softCap, "Soft cap not met");

        // Warp to after presale end and finalize
        vm.warp(presaleOptions.end + 1);
        uint256 initialPresaleTokenBalanceInPresale = presaleToken.balanceOf(presaleAddress);
        uint256 initialCreatorBalance = presaleToken.balanceOf(deployer);
        uint256 totalRaisedActual = presale.totalRaised();

        // Calculate expectedLeftover accurately based on Presale.sol logic
        // 1. Tokens sold for the raised amount
        uint256 tokensSoldForRaisedAmount =
            (totalRaisedActual * presaleOptions.presaleRate * (10 ** presaleToken.decimals())) / (10 ** usdc.decimals());
        if (tokensSoldForRaisedAmount > presale.tokensClaimable()) {
            tokensSoldForRaisedAmount = presale.tokensClaimable();
        }

        // 2. Unsold presale tokens (from the portion allocated for sale)
        uint256 unsoldPresaleTokens = presale.tokensClaimable() - tokensSoldForRaisedAmount;

        // 3. Tokens used for actual liquidity based on totalRaisedActual
        uint256 currencyForActualLiquidity = (totalRaisedActual * presaleOptions.liquidityBps) / 10_000;
        uint256 tokensNeededForActualLiquidity = (
            currencyForActualLiquidity * presaleOptions.listingRate * (10 ** presaleToken.decimals())
        ) / (10 ** usdc.decimals());
        uint256 tokensUsedForActualLiquidity = tokensNeededForActualLiquidity > presale.tokensLiquidity()
            ? presale.tokensLiquidity()
            : tokensNeededForActualLiquidity;

        // 4. Token balance in presale contract that _handleLeftoverTokens will operate on
        uint256 tokenBalanceForLeftoverCalc = initialPresaleTokenBalanceInPresale - tokensUsedForActualLiquidity;

        // 5. Excess deposit calculation
        uint256 excessDeposit;
        uint256 totalTokensNeededAtHardcap = presale.tokensClaimable() + presale.tokensLiquidity();
        if (tokenBalanceForLeftoverCalc + presale.tokensLiquidity() > totalTokensNeededAtHardcap) {
            excessDeposit = (tokenBalanceForLeftoverCalc + presale.tokensLiquidity()) - totalTokensNeededAtHardcap;
        } else {
            excessDeposit = 0;
        }

        uint256 expectedLeftover = unsoldPresaleTokens + excessDeposit;
        if (expectedLeftover > tokenBalanceForLeftoverCalc) {
            expectedLeftover = tokenBalanceForLeftoverCalc;
        }

        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit IPresale.LeftoverTokensReturned(expectedLeftover, deployer);
        bool finalized = presale.finalize();
        assertTrue(finalized, "Finalization failed");

        // Verify creator balance
        assertEq(
            presaleToken.balanceOf(deployer),
            initialCreatorBalance + expectedLeftover,
            "Creator did not receive leftover tokens"
        );

        // Verify presale token balance
        assertEq(
            presaleToken.balanceOf(presaleAddress),
            tokensSoldForRaisedAmount, // Should hold tokens due to contributors
            "Presale contract token balance after finalize is incorrect"
        );
    }

    function test_Fork_Contribution_Edge_Cases() public {
        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));

        // Mint tokens to contributors
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000_000_000); // 1B USDC
        usdc.mint(contributor2, 1_000_000_000_000); // 1B USDC
        vm.stopPrank();

        // Create presale with default options
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        uint256 requiredTokenDeposit =
            factory.calculateTotalTokensNeededForPresale(presaleOptions, address(presaleToken));

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "Edge_Case_Presale");
        vm.stopPrank();

        // Test 1: Contribute exactly options.min (1M USDC)
        vm.warp(presaleOptions.start);
        vm.startPrank(contributor1);
        usdc.approve(address(presale), presaleOptions.min);
        presale.contributeStablecoin(presaleOptions.min, new bytes32[](0));
        assertEq(presale.totalRaised(), presaleOptions.min, "Minimum contribution failed");
        vm.stopPrank();

        // Test 2: Contribute exactly options.max (5M USDC)
        vm.startPrank(contributor2);
        usdc.approve(address(presale), presaleOptions.max);
        presale.contributeStablecoin(presaleOptions.max, new bytes32[](0));
        assertEq(presale.totalRaised(), presaleOptions.min + presaleOptions.max, "Maximum contribution failed");
        vm.stopPrank();

        // Test 3: Contribute just below hard cap, then attempt to exceed it
        uint256 remainingToHardCap = presaleOptions.hardCap - presale.totalRaised();
        vm.startPrank(contributor1);
        usdc.approve(address(presale), remainingToHardCap);
        presale.contributeStablecoin(remainingToHardCap, new bytes32[](0));
        assertEq(presale.totalRaised(), presaleOptions.hardCap, "Contribution to hard cap failed");

        // FIX: Grant allowance before attempting to exceed hard cap
        usdc.approve(address(presale), 1);
        // Attempt to exceed hard cap (should revert)
        vm.expectRevert(abi.encodeWithSelector(IPresale.HardCapExceeded.selector));
        presale.contributeStablecoin(1, new bytes32[](0));
        vm.stopPrank();

        // Test 4: Contribute before presale starts (should revert)
        vm.warp(presaleOptions.start - 1);
        vm.startPrank(contributor1);
        usdc.approve(address(presale), presaleOptions.min);
        vm.expectRevert(abi.encodeWithSelector(IPresale.NotInPurchasePeriod.selector));
        presale.contributeStablecoin(presaleOptions.min, new bytes32[](0));
        vm.stopPrank();

        // Test 5: Contribute after presale ends (should revert)
        vm.warp(presaleOptions.end + 1);
        vm.startPrank(contributor1);
        usdc.approve(address(presale), presaleOptions.min);
        vm.expectRevert(abi.encodeWithSelector(IPresale.NotInPurchasePeriod.selector));
        presale.contributeStablecoin(presaleOptions.min, new bytes32[](0));
        vm.stopPrank();

        // Test 6: Contribute ETH when stablecoin is expected (should revert)
        vm.warp(presaleOptions.start);
        vm.startPrank(contributor1);
        vm.deal(contributor1, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IPresale.ETHNotAccepted.selector));
        presale.contribute{value: 1 ether}(new bytes32[](0));
        vm.stopPrank();
    }

    function test_Fork_Liquidity_Edge_Cases() public {
        // Deploy mock USDC
        ERC20Mock usdc = new ERC20Mock();
        vm.etch(address(usdc), type(ERC20Mock).runtimeCode);
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(6));

        // Mint tokens to contributors
        vm.startPrank(deployer);
        usdc.mint(contributor1, 1_000_000_000_000); // 1B USDC
        usdc.mint(contributor2, 1_000_000_000_000); // 1B USDC
        vm.stopPrank();

        // Create presale with default options
        Presale.PresaleOptions memory presaleOptions = _getDefaultPresaleOptions(address(usdc));
        uint256 requiredTokenDeposit =
            factory.calculateTotalTokensNeededForPresale(presaleOptions, address(presaleToken));

        vm.startPrank(deployer);
        presaleToken.approve(address(factory), requiredTokenDeposit);
        address presaleAddress = factory.createPresale{value: factory.creationFee()}(
            presaleOptions, address(presaleToken), SEPOLIA_WETH, SEPOLIA_ROUTER
        );
        Presale presale = Presale(payable(presaleAddress));
        vm.label(presaleAddress, "Liquidity_Edge_Case_Presale");
        vm.stopPrank();

        // Test 1: Low totalRaised (softCap) to test reserve adjustments in _liquify
        vm.warp(presaleOptions.start);
        vm.startPrank(contributor1);
        usdc.approve(address(presale), presaleOptions.softCap);
        presale.contributeStablecoin(presaleOptions.softCap, new bytes32[](0)); // 5M USDC
        vm.stopPrank();

        vm.warp(presaleOptions.end + 1);
        vm.startPrank(deployer);
        bool finalized = presale.finalize();
        assertTrue(finalized, "Finalization failed");

        // Verify LP tokens created and locked
        LiquidityLocker locker = factory.liquidityLocker();
        assertTrue(locker.lockCount() > 0, "No LP lock found");
        (, uint256 lpAmountActual,,) = locker.getLock(0);
        assertTrue(lpAmountActual > 0, "LP amount should be > 0");

        // Verify tokensLiquidity (max allocation based on hardCap)
        uint256 maxTokensLiquidity = presale.tokensLiquidity();
        assertTrue(maxTokensLiquidity > 0, "Max tokens for liquidity should be > 0");
        vm.stopPrank();

        // Test 2: Simulate liquidity addition when internal tokenBalance state variable is insufficient
        {
            // Use new token instances to avoid pair conflicts
            ERC20Mock presaleTokenTest2 = new ERC20Mock();
            presaleTokenTest2.mint(deployer, 1_000_000_000 * 1e18); // Mint enough for deposit
            ERC20Mock usdcTest2 = new ERC20Mock();
            vm.etch(address(usdcTest2), type(ERC20Mock).runtimeCode);
            vm.mockCall(address(usdcTest2), abi.encodeWithSignature("decimals()"), abi.encode(6));

            Presale.PresaleOptions memory optionsForTest2 = _getDefaultPresaleOptions(address(usdcTest2));
            optionsForTest2.tokenDeposit =
                factory.calculateTotalTokensNeededForPresale(optionsForTest2, address(presaleTokenTest2));

            vm.startPrank(deployer);
            presaleTokenTest2.approve(address(factory), optionsForTest2.tokenDeposit);
            address presaleAddressTest2 = factory.createPresale{value: factory.creationFee()}(
                optionsForTest2, address(presaleTokenTest2), SEPOLIA_WETH, SEPOLIA_ROUTER
            );
            Presale presaleTest2 = Presale(payable(presaleAddressTest2));
            vm.label(presaleAddressTest2, "Presale_For_Simulate_Insufficient_State_Balance");
            vm.stopPrank();

            // Mint enough usdcTest2 for contributors
            vm.startPrank(deployer);
            usdcTest2.mint(contributor1, optionsForTest2.max);
            usdcTest2.mint(contributor2, optionsForTest2.max);
            vm.stopPrank();

            // Contribute from contributor1
            vm.warp(optionsForTest2.start);
            vm.startPrank(contributor1);
            usdcTest2.approve(address(presaleTest2), optionsForTest2.max);
            presaleTest2.contributeStablecoin(optionsForTest2.max, new bytes32[](0)); // 5M USDC
            vm.stopPrank();

            // Contribute from contributor2
            vm.startPrank(contributor2);
            usdcTest2.approve(address(presaleTest2), optionsForTest2.max);
            presaleTest2.contributeStablecoin(optionsForTest2.max, new bytes32[](0)); // 5M USDC
            vm.stopPrank();

            assertEq(presaleTest2.totalRaised(), optionsForTest2.hardCap, "Test 2: Hardcap not reached");

            // Finalize presaleTest2
            vm.warp(optionsForTest2.end + 1);
            vm.prank(deployer);
            presaleTest2.finalize();
            assertEq(uint8(presaleTest2.state()), uint8(Presale.PresaleState.Finalized), "Test 2: Finalization failed");

            // Contributor1 claims all tokens
            uint256 tokensToClaimC1 = presaleTest2.userTokens(contributor1);
            assertTrue(tokensToClaimC1 > 0, "Test 2: C1 should have tokens to claim");
            vm.prank(contributor1);
            presaleTest2.claim();

            // Contributor2 claims all tokens
            uint256 tokensToClaimC2 = presaleTest2.userTokens(contributor2);
            assertTrue(tokensToClaimC2 > 0, "Test 2: C2 should have tokens to claim");
            vm.prank(contributor2);
            presaleTest2.claim();

            assertEq(presaleTest2.tokenBalance(), 0, "Test 2: Token balance should be 0 after claims");

            // Simulate liquidity addition
            (bool canAddLiquidityTest2,,) = presaleTest2.simulateLiquidityAddition();
            assertFalse(canAddLiquidityTest2, "Simulate liquidity should fail when tokenBalance is 0");
        }

        // Test 3: Validate allowed liquidityBps values
        {
            ERC20Mock presaleTokenTest3 = new ERC20Mock();
            presaleTokenTest3.mint(deployer, 1_000_000_000 * 1e18);
            ERC20Mock usdcTest3 = new ERC20Mock();
            vm.etch(address(usdcTest3), type(ERC20Mock).runtimeCode);
            vm.mockCall(address(usdcTest3), abi.encodeWithSignature("decimals()"), abi.encode(6));

            Presale.PresaleOptions memory optionsForTest3 = _getDefaultPresaleOptions(address(usdcTest3));
            optionsForTest3.tokenDeposit =
                factory.calculateTotalTokensNeededForPresale(optionsForTest3, address(presaleTokenTest3));

            vm.startPrank(deployer);
            presaleTokenTest3.approve(address(factory), optionsForTest3.tokenDeposit);
            address presaleAddressTest3 = factory.createPresale{value: factory.creationFee()}(
                optionsForTest3, address(presaleTokenTest3), SEPOLIA_WETH, SEPOLIA_ROUTER
            );
            Presale presaleTest3 = Presale(payable(presaleAddressTest3));
            vm.label(presaleAddressTest3, "Presale_For_BPS_Validation");
            vm.stopPrank();

            uint256[] memory allowedBps = new uint256[](6);
            allowedBps[0] = 5000;
            allowedBps[1] = 6000;
            allowedBps[2] = 7000;
            allowedBps[3] = 8000;
            allowedBps[4] = 9000;
            allowedBps[5] = 10000;

            for (uint256 i = 0; i < allowedBps.length; i++) {
                bool isAllowed = presaleTest3.isAllowedLiquidityBps(allowedBps[i]);
                assertTrue(
                    isAllowed,
                    string(abi.encodePacked("Valid liquidityBps rejected: ", Strings.toString(allowedBps[i])))
                );
            }

            bool isInvalid = presaleTest3.isAllowedLiquidityBps(6001);
            assertFalse(isInvalid, "Invalid liquidityBps (6001) accepted");

            isInvalid = presaleTest3.isAllowedLiquidityBps(4999);
            assertFalse(isInvalid, "Invalid liquidityBps (4999) accepted");

            isInvalid = presaleTest3.isAllowedLiquidityBps(10001);
            assertFalse(isInvalid, "Invalid liquidityBps (10001) accepted");

            isInvalid = presaleTest3.isAllowedLiquidityBps(0);
            assertFalse(isInvalid, "Invalid liquidityBps (0) accepted");
        }

        // Test 4: Simulate liquidity addition with existing reserves
        {
            // At this point, `presale` has been finalized, so:
            // - `presale.totalRaised()` is `presaleOptions.softCap`.
            // - A pair exists with reserves.
            // - `presale.tokenBalance()` holds tokens allocated for claims.
            // `simulateLiquidityAddition` will calculate amounts based on the current `totalRaised`.

            uint256 currentTotalRaised = presale.totalRaised(); // This will be presaleOptions.softCap
            uint256 expectedSimLiquidityAmount = (currentTotalRaised * presaleOptions.liquidityBps) / 10_000;
            
            uint8 presaleTokenDecimals = presaleToken.decimals(); // Mock ERC20 default is 18
            uint8 currencyTokenDecimals = usdc.decimals(); // Mock USDC set to 6
            uint256 currencyMultiplier = 10 ** currencyTokenDecimals;

            uint256 expectedSimTokenAmount = (expectedSimLiquidityAmount * presaleOptions.listingRate * (10 ** presaleTokenDecimals)) / currencyMultiplier;
            uint256 maxTokensForLiq = presale.tokensLiquidity(); // Max allocation based on hardCap
            if (expectedSimTokenAmount > maxTokensForLiq) {
                expectedSimTokenAmount = maxTokensForLiq;
            }
            // The third return value `expectedCurrency` from simulateLiquidityAddition
            // should be equal to expectedSimLiquidityAmount if reserves are proportional or zero.
            uint256 expectedSimCurrencyReturned = expectedSimLiquidityAmount;

            (bool canAddInit, uint256 simTokenAmountInit, uint256 simCurrencyAmountInit) =
                presale.simulateLiquidityAddition();
            assertTrue(canAddInit, "simulateLiquidityAddition should be possible on a finalized presale with sufficient balance");
            assertEq(simTokenAmountInit, expectedSimTokenAmount, "Simulated token amount mismatch on finalized presale");
            assertEq(simCurrencyAmountInit, expectedSimCurrencyReturned, "Simulated currency amount mismatch on finalized presale");
        }
    }
}
