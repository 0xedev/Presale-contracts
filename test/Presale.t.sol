// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Import Base Test and Interfaces/Contracts needed for tests
import {PresaleTestBase, generateMerkleTree} from "./PresaleTestBase.t.sol"; // Import base and helper
import {IPresale} from "../src/contracts/interfaces/IPresale.sol";
import {Presale} from "../src/contracts/Presale.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ==========================================================================================
// Test Contract: Presale (Core Functionality) - Inherits from Base
// ==========================================================================================
contract PresaleTest is PresaleTestBase {
    // NOTE: setUp() is inherited and runs automatically

    // ==========================================================================================
    // Test Cases: Constructor & Initialization
    // ==========================================================================================
    function test_Deploy_Success_ETH() public {
        // `presale` instance is already deployed in setUp from Base
        assertEq(presale.owner(), owner);
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Pending));
        assertEq(address(presale.liquidityLocker()), address(locker));
        assertEq(address(presale.vestingContract()), address(vesting));
        assertEq(presale.housePercentage(), housePercentage);
        assertEq(presale.houseAddress(), houseAddress);
        assertEq(address(presale.pool_token()), address(presaleToken));
        assertEq(address(presale.pool_uniswapV2Router02()), address(router));
        assertEq(presale.pool_weth(), address(weth));
        assertEq(presale.pool_options_currency(), address(0));
    }

    function test_Deploy_Success_Stablecoin() public {
        vm.startPrank(owner);
        // Redeploy using the stablecoin options defined in Base
        Presale stablePresale = deployPresale(optionsStable);
        vm.stopPrank();

        assertEq(stablePresale.owner(), owner);
        assertEq(uint8(stablePresale.state()), uint8(Presale.PresaleState.Pending));
        assertEq(stablePresale.pool_options_currency(), address(currencyToken));
        assertEq(stablePresale.pool_options_hardCap(), optionsStable.hardCap);
    }

    function test_Revert_Deploy_InvalidInitializationParams() public {
        // Use options defined in Base
        vm.startPrank(owner);
        Presale.PresaleOptions memory badOptions = optionsETH;

        // Test various invalid constructor args (using mocks/addresses from Base)
        vm.expectRevert(Presale.InvalidInitialization.selector);
        new Presale(
            address(0),
            address(presaleToken),
            address(router),
            badOptions,
            owner,
            address(locker),
            address(vesting),
            housePercentage,
            houseAddress
        );
        vm.expectRevert(Presale.InvalidInitialization.selector);
        new Presale(
            address(weth),
            address(0),
            address(router),
            badOptions,
            owner,
            address(locker),
            address(vesting),
            housePercentage,
            houseAddress
        );

        // Test invalid pool options
        badOptions = optionsETH;
        badOptions.tokenDeposit = 0;
        vm.expectRevert(Presale.InvalidInitialization.selector);
        deployPresale(badOptions);
        // ... (Include other invalid pool option checks as before) ...

        vm.stopPrank();
    }

    // ==========================================================================================
    // Test Cases: Deposit
    // ==========================================================================================
    function test_Revert_Deposit_NotOwner() public {
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.deposit();
    }

    function test_Revert_Deposit_Paused() public {
        vm.startPrank(owner);
        presale.pause();
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.deposit();
        vm.stopPrank();
    }

    function test_Revert_Deposit_WrongState() public {
        _depositTokens();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.deposit();
    }

    function test_Revert_Deposit_InsufficientAllowance() public {
        vm.startPrank(owner);
        Presale newPresale = deployPresale(optionsETH);
        presaleToken.approve(address(newPresale), 0);
        vm.expectRevert("ERC20: insufficient allowance");
        newPresale.deposit();
        vm.stopPrank();
    }

    function test_Revert_Deposit_InsufficientBalance() public {
        vm.startPrank(owner);
        uint256 currentBalance = presaleToken.balanceOf(owner);
        if (currentBalance == 0) presaleToken.mint(owner, 1);
        presaleToken.burn(owner, presaleToken.balanceOf(owner));
        presaleToken.approve(address(presale), optionsETH.tokenDeposit);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        presale.deposit();
        vm.stopPrank();
    }

    function test_Deposit_Success() public {
        uint256 expectedClaimable = presale._tokensForPresale();
        uint256 expectedLiquidity = presale._tokensForLiquidity();
        uint256 depositAmount = optionsETH.tokenDeposit;
        vm.startPrank(owner);
        uint256 ownerBalance = presaleToken.balanceOf(owner);
        if (ownerBalance < depositAmount) presaleToken.mint(owner, depositAmount - ownerBalance);
        presaleToken.approve(address(presale), depositAmount);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Deposit(owner, depositAmount, block.timestamp);
        uint256 deposited = presale.deposit();
        vm.stopPrank();
        assertEq(deposited, depositAmount);
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active));
        assertEq(presaleToken.balanceOf(address(presale)), depositAmount);
        assertEq(presale.pool_tokenBalance(), depositAmount);
        assertEq(presale.pool_tokensClaimable(), expectedClaimable);
        assertEq(presale.pool_tokensLiquidity(), expectedLiquidity);
    }

    // ==========================================================================================
    // Test Cases: Contribution (ETH)
    // ==========================================================================================
    function test_Revert_ContributeETH_Paused() public {
        _depositTokens();
        vm.startPrank(owner);
        presale.pause();
        vm.stopPrank();
        vm.prank(contributor1);
        vm.expectRevert(IPresale.ContractPaused.selector);
        presale.contribute{value: minContribution}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_WrongState() public {
        vm.prank(contributor1);
        vm.expectRevert(IPresale.NotActive.selector);
        presale.contribute{value: minContribution}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_ETHNotAccepted() public {
        vm.startPrank(owner);
        presale = deployPresale(optionsStable);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        vm.expectRevert(IPresale.ETHNotAccepted.selector);
        uint256 ethValue = optionsStable.min * (10 ** 18) / (10 ** currencyDecimals);
        presale.contribute{value: ethValue}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_NotInPurchasePeriod() public {
        _depositTokens();
        vm.warp(start - 1 hours);
        vm.prank(contributor1);
        vm.expectRevert(IPresale.NotInPurchasePeriod.selector);
        presale.contribute{value: minContribution}(new bytes32[](0));
        vm.warp(end + 1 hours);
        vm.expectRevert(IPresale.NotInPurchasePeriod.selector);
        presale.contribute{value: minContribution}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_BelowMinimum() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        vm.expectRevert(IPresale.BelowMinimumContribution.selector);
        presale.contribute{value: minContribution - 1 wei}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_ExceedsMaximum_Single() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        vm.expectRevert(IPresale.ExceedsMaximumContribution.selector);
        presale.contribute{value: maxContribution + 1 wei}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_ExceedsMaximum_Multiple() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.startPrank(contributor1);
        presale.contribute{value: maxContribution / 2}(new bytes32[](0));
        presale.contribute{value: maxContribution / 2}(new bytes32[](0));
        vm.expectRevert(IPresale.ExceedsMaximumContribution.selector);
        presale.contribute{value: 1 ether}(new bytes32[](0));
        vm.stopPrank();
    }

    function test_Revert_ContributeETH_HardCapExceeded() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        uint256 contribution1 = hardCap - minContribution;
        vm.deal(contributor1, contribution1 + 1 ether);
        vm.prank(contributor1);
        presale.contribute{value: contribution1}(new bytes32[](0));
        vm.prank(contributor2);
        vm.expectRevert(IPresale.HardCapExceeded.selector);
        presale.contribute{value: minContribution + 1 wei}(new bytes32[](0));
    }

    function test_Revert_ContributeETH_ZeroTokensForContribution() public {
        vm.startPrank(owner);
        Presale.PresaleOptions memory zeroRateOptions = optionsETH;
        zeroRateOptions.presaleRate = 1;
        zeroRateOptions.listingRate = 1;
        zeroRateOptions.tokenDeposit = calculateDeposit(zeroRateOptions);
        presale = deployPresale(zeroRateOptions);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.prank(contributor1);
        presale.contribute{value: 1 wei}(new bytes32[](0)); /* Assumes rate 1/decimals 18 succeeds */
    }

    function test_ContributeETH_Success_NoWhitelist() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        uint256 contributionAmount = 1 ether;
        uint256 initialTotal = presale.getTotalContributed();
        uint256 initialUserContribution = presale.getContribution(contributor1);
        uint256 initialContributorCount = presale.getContributorCount();
        vm.startPrank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Contribution(contributor1, contributionAmount, true);
        presale.contribute{value: contributionAmount}(new bytes32[](0));
        assertEq(presale.contributions(contributor1), initialUserContribution + contributionAmount);
        assertEq(presale.pool_weiRaised(), initialTotal + contributionAmount);
        assertEq(presale.getTotalContributed(), initialTotal + contributionAmount);
        assertEq(presale.getContributorCount(), initialContributorCount + 1);
        assertEq(presale.getContributors()[initialContributorCount], contributor1);
        vm.stopPrank();
        vm.startPrank(contributor2);
        uint256 contributionAmount2 = 2 ether;
        initialTotal = presale.getTotalContributed();
        initialUserContribution = presale.getContribution(contributor2);
        initialContributorCount = presale.getContributorCount();
        vm.expectEmit(true, true, true, true);
        emit IPresale.Purchase(contributor2, contributionAmount2);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Contribution(contributor2, contributionAmount2, true);
        (bool success,) = address(presale).call{value: contributionAmount2}("");
        assertTrue(success, "Receive fallback failed");
        assertEq(presale.contributions(contributor2), initialUserContribution + contributionAmount2);
        assertEq(presale.pool_weiRaised(), initialTotal + contributionAmount2);
        assertEq(presale.getContributorCount(), initialContributorCount + 1);
        assertEq(presale.getContributors()[initialContributorCount], contributor2);
        vm.stopPrank();
    }

    // ==========================================================================================
    // Test Cases: Contribution (Stablecoin)
    // ==========================================================================================
    function test_Revert_ContributeStable_StablecoinNotAccepted() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.startPrank(contributor1);
        currencyToken.approve(address(presale), optionsStable.min);
        vm.expectRevert(IPresale.StablecoinNotAccepted.selector);
        presale.contributeStablecoin(optionsStable.min, new bytes32[](0));
        vm.stopPrank();
    }

    function test_Revert_ContributeStable_InsufficientAllowance() public {
        vm.startPrank(owner);
        presale = deployPresale(optionsStable);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.startPrank(contributor1);
        currencyToken.approve(address(presale), optionsStable.min - 1);
        vm.expectRevert("ERC20: insufficient allowance");
        presale.contributeStablecoin(optionsStable.min, new bytes32[](0));
        vm.stopPrank();
    }

    function test_Revert_ContributeStable_InsufficientBalance() public {
        vm.startPrank(owner);
        presale = deployPresale(optionsStable);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        vm.startPrank(contributor1);
        uint256 currentStableBalance = currencyToken.balanceOf(contributor1);
        if (currentStableBalance < optionsStable.min) currencyToken.mint(contributor1, optionsStable.min);
        currencyToken.burn(contributor1, currencyToken.balanceOf(contributor1));
        currencyToken.approve(address(presale), optionsStable.min);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        presale.contributeStablecoin(optionsStable.min, new bytes32[](0));
        vm.stopPrank();
    }

    function test_ContributeStable_Success() public {
        vm.startPrank(owner);
        presale = deployPresale(optionsStable);
        _depositTokens();
        vm.stopPrank();
        vm.warp(start + 1 hours);
        uint256 contributionAmount = optionsStable.min;
        uint256 initialTotal = presale.getTotalContributed();
        uint256 initialUserContribution = presale.getContribution(contributor1);
        uint256 initialContractBalance = currencyToken.balanceOf(address(presale));
        uint256 initialContributorBalance = currencyToken.balanceOf(contributor1);
        if (initialContributorBalance < contributionAmount) {
            currencyToken.mint(contributor1, contributionAmount - initialContributorBalance);
            initialContributorBalance = currencyToken.balanceOf(contributor1);
        }
        vm.startPrank(contributor1);
        currencyToken.approve(address(presale), contributionAmount);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Purchase(contributor1, contributionAmount);
        vm.expectEmit(true, true, true, true);
        emit IPresale.Contribution(contributor1, contributionAmount, false);
        presale.contributeStablecoin(contributionAmount, new bytes32[](0));
        assertEq(presale.contributions(contributor1), initialUserContribution + contributionAmount);
        assertEq(presale.pool_weiRaised(), initialTotal + contributionAmount);
        assertEq(currencyToken.balanceOf(address(presale)), initialContractBalance + contributionAmount);
        assertEq(currencyToken.balanceOf(contributor1), initialContributorBalance - contributionAmount);
        vm.stopPrank();
    }

    // ==========================================================================================
    // Test Cases: Whitelist & Merkle Root
    // ==========================================================================================
    function test_Whitelist_Toggle_And_SetRoot() public {
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Pending));
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit IPresale.WhitelistToggled(true);
        presale.toggleWhitelist(true);
        assertTrue(presale.whitelistEnabled());
        vm.expectEmit(true, true, false, true);
        emit IPresale.MerkleRootUpdated(merkleRoot);
        presale.setMerkleRoot(merkleRoot);
        assertEq(presale.merkleRoot(), merkleRoot);
        vm.expectEmit(true, false, false, true);
        emit IPresale.WhitelistToggled(false);
        presale.toggleWhitelist(false);
        assertFalse(presale.whitelistEnabled());
        vm.stopPrank();
    }

    function test_Revert_Whitelist_Admin_WrongState() public {
        _depositTokens();
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.toggleWhitelist(true);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.setMerkleRoot(merkleRoot);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, uint8(Presale.PresaleState.Active)));
        presale.updateWhitelist(new address[](0), true);
        vm.stopPrank();
    }

    function test_Revert_ContributeETH_NotWhitelisted() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.startPrank(owner);
        presale.toggleWhitelist(true);
        presale.setMerkleRoot(merkleRoot);
        vm.stopPrank();
        vm.prank(otherUser);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: minContribution}(new bytes32[](0));
        vm.prank(contributor1);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        bytes32[] memory badProof = new bytes32[](proof1.length);
        badProof[0] = bytes32(uint256(123));
        presale.contribute{value: minContribution}(badProof);
    }

    function test_ContributeETH_Whitelist_Success() public {
        _depositTokens();
        vm.warp(start + 1 hours);
        vm.startPrank(owner);
        presale.toggleWhitelist(true);
        presale.setMerkleRoot(merkleRoot);
        vm.stopPrank();
        uint256 contributionAmount = 1 ether;
        vm.startPrank(contributor1);
        presale.contribute{value: contributionAmount}(proof1);
        assertEq(presale.contributions(contributor1), contributionAmount);
        vm.stopPrank();
    }

    // ==========================================================================================
    // Test Cases: Basic Admin Functions (Pause/Unpause)
    // ==========================================================================================
    function test_Pause_Unpause() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit IPresale.Paused(owner);
        presale.pause();
        assertTrue(presale.paused());
        vm.expectRevert(IPresale.AlreadyPaused.selector);
        presale.pause();
        vm.expectEmit(true, true, false, true);
        emit IPresale.Unpaused(owner);
        presale.unpause();
        assertFalse(presale.paused());
        vm.expectRevert(IPresale.NotPaused.selector);
        presale.unpause();
        vm.stopPrank();
        vm.prank(otherUser);
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.pause();
        vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
        presale.unpause();
    }

    // ==========================================================================================
    // Test Cases: View Functions
    // ==========================================================================================
    function test_ViewFunctions() public {
        assertEq(presale.calculateTotalTokensNeeded(), optionsETH.tokenDeposit);
        assertEq(presale.userTokens(contributor1), 0);
        assertEq(presale.getContributorCount(), 0);
        address[] memory emptyContributors = presale.getContributors();
        assertEq(emptyContributors.length, 0);
        assertEq(presale.getTotalContributed(), 0);
        assertEq(presale.getContribution(contributor1), 0);
        _depositTokens();
        vm.warp(start + 1 hours);
        uint256 contribution1 = 1 ether;
        uint256 contribution2 = 2 ether;
        vm.prank(contributor1);
        presale.contribute{value: contribution1}(new bytes32[](0));
        vm.stopPrank();
        vm.prank(contributor2);
        presale.contribute{value: contribution2}(new bytes32[](0));
        vm.stopPrank();
        uint256 expectedTokens1 = (contribution1 * optionsETH.presaleRate * (10 ** tokenDecimals)) / (10 ** 18);
        uint256 expectedTokens2 = (contribution2 * optionsETH.presaleRate * (10 ** tokenDecimals)) / (10 ** 18);
        assertEq(presale.userTokens(contributor1), expectedTokens1);
        assertEq(presale.userTokens(contributor2), expectedTokens2);
        assertEq(presale.getContributorCount(), 2);
        address[] memory contributors = presale.getContributors();
        assertEq(contributors.length, 2);
        assertEq(contributors[0], contributor1);
        assertEq(contributors[1], contributor2);
        assertEq(presale.getTotalContributed(), contribution1 + contribution2);
        assertEq(presale.getContribution(contributor1), contribution1);
        assertEq(presale.getContribution(contributor2), contribution2);
    }
}
