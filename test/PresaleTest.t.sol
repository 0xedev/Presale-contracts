// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Presale} from "src/contracts/Presale.sol";
import {Vesting} from "src/contracts/Vesting.sol";
import {LiquidityLocker} from "src/contracts/LiquidityLocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IPresale} from "src/contracts/interfaces/IPresale.sol";

// Mock Uniswap V2 interfaces
interface IUniswapV2Router02Mock {
    function factory() external view returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IUniswapV2FactoryMock {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

// Mock Uniswap V2 Pair
contract UniswapV2PairMock is ERC20Mock {
    constructor() ERC20Mock() {}
}

// Mock Uniswap V2 Factory
contract UniswapV2FactoryMock is IUniswapV2FactoryMock {
    mapping(address => mapping(address => address)) public getPair;
    address[] public pairs;
    
    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, "Identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(getPair[token0][token1] == address(0), "Pair exists");
        pair = address(new UniswapV2PairMock());
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        pairs.push(pair);
        return pair;
    }
}

// Mock Uniswap V2 Router
contract UniswapV2Router02Mock is IUniswapV2Router02Mock {
    address public immutable factory;
    
    constructor(address _factory) {
        factory = _factory;
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "Expired");
        require(amountADesired >= amountAMin && amountBDesired >= amountBMin, "Insufficient amounts");
        UniswapV2PairMock pair = UniswapV2PairMock(IUniswapV2FactoryMock(factory).getPair(tokenA, tokenB));
        liquidity = amountADesired; // Simplified for testing
        pair.mint(to, liquidity);
        return (amountADesired, amountBDesired, liquidity);
    }
    
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(block.timestamp <= deadline, "Expired");
        require(amountTokenDesired >= amountTokenMin && msg.value >= amountETHMin, "Insufficient amounts");
        address pairAddr = IUniswapV2FactoryMock(factory).getPair(token, address(this));
        if (pairAddr == address(0)) {
            pairAddr = IUniswapV2FactoryMock(factory).createPair(token, address(this));
        }
        UniswapV2PairMock pair = UniswapV2PairMock(pairAddr);
        liquidity = amountTokenDesired; // Simplified for testing
        pair.mint(to, liquidity);
        return (amountTokenDesired, msg.value, liquidity);
    }
}

contract PresaleTest is Test {
    Presale presale;
    Vesting vesting;
    LiquidityLocker liquidityLocker;
    ERC20Mock token;
    ERC20Mock stablecoin;
    UniswapV2FactoryMock uniswapFactory;
    UniswapV2Router02Mock uniswapRouter;
    address owner;
    address contributor1;
    address contributor2;
    address houseAddress;
    address weth;

    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 constant PRESALE_RATE = 1000; // 1000 tokens per ETH/stablecoin
    uint256 constant LISTING_RATE = 500; // 500 tokens per ETH/stablecoin
    uint256 constant HARD_CAP = 100 ether;
    uint256 constant SOFT_CAP = 25 ether;
    uint256 constant MIN_CONTRIBUTION = 0.1 ether;
    uint256 constant MAX_CONTRIBUTION = 10 ether;
    uint256 constant LIQUIDITY_BPS = 7000; // 70%
    uint256 constant SLIPPAGE_BPS = 200; // 2%
    uint256 constant VESTING_PERCENTAGE = 5000; // 50%
    uint256 constant VESTING_DURATION = 365 days;
    uint256 constant LOCKUP_DURATION = 180 days;
    uint256 constant HOUSE_PERCENTAGE = 200; // 2%
    uint256 constant START_TIME = 1_000_000_000;
    uint256 constant END_TIME = START_TIME + 7 days;

    Presale.PresaleOptions optionsETH;
    Presale.PresaleOptions optionsStablecoin;
    bytes32 merkleRoot;
    
    event Contribution(address indexed contributor, uint256 amount, bool isETH);
    event Purchase(address indexed beneficiary, uint256 amount);
    event Deposit(address indexed sender, uint256 amount, uint256 timestamp);
    event Finalized(address indexed sender, uint256 weiRaised, uint256 timestamp);
    event TokenClaim(address indexed claimant, uint256 amount, uint256 timestamp);
    event Refund(address indexed claimant, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed owner, uint256 amount);
    event MerkleRootUpdated(bytes32 merkleRoot);
    event WhitelistToggled(bool enabled);
    event WhitelistUpdated(address indexed user, bool added);
    event Paused(address indexed owner);
    event Unpaused(address indexed owner);
    event LeftoverTokensReturned(uint256 amount, address indexed recipient);
    event LeftoverTokensBurned(uint256 amount);
    event LeftoverTokensVested(uint256 amount, address indexed recipient);
    event HouseFundsDistributed(address indexed houseAddress, uint256 amount);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event ClaimDeadlineExtended(uint256 newDeadline);
    event Cancel(address indexed owner, uint256 timestamp);

    function setUp() public {
        owner = address(0x1);
        contributor1 = address(0x2);
        contributor2 = address(0x3);
        houseAddress = address(0x4);
        weth = address(0x5);
        
        // Deploy contracts
        token = new ERC20Mock();
        stablecoin = new ERC20Mock();
        vesting = new Vesting(address(token));
        liquidityLocker = new LiquidityLocker();
        uniswapFactory = new UniswapV2FactoryMock();
        uniswapRouter = new UniswapV2Router02Mock(address(uniswapFactory));
        
        // Mint tokens
        vm.startPrank(owner);
        token.mint(owner, INITIAL_SUPPLY);
        stablecoin.mint(contributor1, 1000 ether);
        stablecoin.mint(contributor2, 1000 ether);
        
        // Set up presale options (ETH)
        optionsETH = Presale.PresaleOptions({
            tokenDeposit: 100_000 * 10**18,
            hardCap: HARD_CAP,
            softCap: SOFT_CAP,
            max: MAX_CONTRIBUTION,
            min: MIN_CONTRIBUTION,
            start: START_TIME,
            end: END_TIME,
            liquidityBps: LIQUIDITY_BPS,
            slippageBps: SLIPPAGE_BPS,
            presaleRate: PRESALE_RATE,
            listingRate: LISTING_RATE,
            lockupDuration: LOCKUP_DURATION,
            currency: address(0), // ETH
            vestingPercentage: VESTING_PERCENTAGE,
            vestingDuration: VESTING_DURATION,
            leftoverTokenOption: 0 // Return
        });
        
        // Set up presale options (Stablecoin)
        optionsStablecoin = Presale.PresaleOptions({
            tokenDeposit: 100_000 * 10**18,
            hardCap: HARD_CAP,
            softCap: SOFT_CAP,
            max: MAX_CONTRIBUTION,
            min: MIN_CONTRIBUTION,
            start: START_TIME,
            end: END_TIME,
            liquidityBps: LIQUIDITY_BPS,
            slippageBps: SLIPPAGE_BPS,
            presaleRate: PRESALE_RATE,
            listingRate: LISTING_RATE,
            lockupDuration: LOCKUP_DURATION,
            currency: address(stablecoin),
            vestingPercentage: VESTING_PERCENTAGE,
            vestingDuration: VESTING_DURATION,
            leftoverTokenOption: 0 // Return
        });
        
        // Deploy presale (ETH)
        presale = new Presale(
            weth,
            address(token),
            address(uniswapRouter),
            optionsETH,
            owner,
            address(liquidityLocker),
            address(vesting),
            HOUSE_PERCENTAGE,
            houseAddress
        );
        
        // Approve tokens
        token.approve(address(presale), INITIAL_SUPPLY);
        vm.stopPrank();
        
        // Set up Merkle root
        address[] memory users = new address[](2);
        users[0] = contributor1;
        users[1] = contributor2;
        merkleRoot = getMerkleRoot(users);
    }
    
    function testConstructor() public view {
        assertEq(presale.owner(), owner);
        assertEq(address(presale.pool().token), address(token));
        assertEq(address(presale.pool().uniswapV2Router02), address(uniswapRouter));
        assertEq(presale.pool().factory, address(uniswapFactory));
        assertEq(presale.pool().weth, weth);
        assertEq(uint8(presale.pool().state), 1); // Pending
        assertEq(presale.pool().options.hardCap, HARD_CAP);
        assertEq(presale.pool().options.softCap, SOFT_CAP);
        assertEq(presale.pool().options.currency, address(0));
        assertEq(address(presale.liquidityLocker()), address(liquidityLocker));
        assertEq(address(presale.vestingContract()), address(vesting));
        assertEq(presale.housePercentage(), HOUSE_PERCENTAGE);
        assertEq(presale.houseAddress(), houseAddress);
        assertFalse(presale.paused());
        assertFalse(presale.whitelistEnabled());
    }
    
    function testConstructorInvalidInputs() public {
        vm.expectRevert(IPresale.InvalidInitialization.selector);
        new Presale(
            address(0), // Invalid WETH
            address(token),
            address(uniswapRouter),
            optionsETH,
            owner,
            address(liquidityLocker),
            address(vesting),
            HOUSE_PERCENTAGE,
            houseAddress
        );
        
        Presale.PresaleOptions memory invalidOptions = optionsETH;
        invalidOptions.leftoverTokenOption = 3;
        vm.expectRevert(IPresale.InvalidLeftoverTokenOption.selector);
        new Presale(
            weth,
            address(token),
            address(uniswapRouter),
            invalidOptions,
            owner,
            address(liquidityLocker),
            address(vesting),
            HOUSE_PERCENTAGE,
            houseAddress
        );
        
        vm.expectRevert(IPresale.InvalidHousePercentage.selector);
        new Presale(
            weth,
            address(token),
            address(uniswapRouter),
            optionsETH,
            owner,
            address(liquidityLocker),
            address(vesting),
            501,
            houseAddress
        );
    }
    
    function testDeposit() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Deposit(owner, optionsETH.tokenDeposit, block.timestamp);
        presale.deposit();
        
        assertEq(uint8(presale.pool().state), 2); // Active
        assertEq(presale.pool().tokenBalance, optionsETH.tokenDeposit);
        assertEq(presale.pool().tokensClaimable, HARD_CAP * PRESALE_RATE);
        assertEq(presale.pool().tokensLiquidity, (HARD_CAP * LIQUIDITY_BPS * LISTING_RATE) / BASIS_POINTS);
        assertEq(token.balanceOf(address(presale)), optionsETH.tokenDeposit);
    }
    
    function testDepositInvalidState() public {
        vm.prank(owner);
        presale.deposit();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPresale.InvalidState.selector, 2));
        presale.deposit();
    }
    
    function testContributeETH() public {
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        uint256 contribution = 1 ether;
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit Contribution(contributor1, contribution, true);
        presale.contribute{value: contribution}(new bytes32[](0));
        
        assertEq(presale.pool().weiRaised, contribution);
        assertEq(presale.contributions(contributor1), contribution);
        assertEq(presale.totalRefundable(), contribution);
        assertEq(presale.getContributorCount(), 1);
        assertEq(presale.getContributors()[0], contributor1);
        assertEq(presale.userTokens(contributor1), contribution * PRESALE_RATE);
    }
    
    function testContributeETHWithWhitelist() public {
        vm.prank(owner);
        presale.toggleWhitelist(true);
        vm.prank(owner);
        presale.setMerkleRoot(merkleRoot);
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        uint256 contribution = 1 ether;
        bytes32[] memory proof = getMerkleProof(contributor1);
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        presale.contribute{value: contribution}(proof);
        
        assertEq(presale.pool().weiRaised, contribution);
        assertEq(presale.contributions(contributor1), contribution);
    }
    
    function testContributeETHNotWhitelisted() public {
        vm.prank(owner);
        presale.toggleWhitelist(true);
        vm.prank(owner);
        presale.setMerkleRoot(merkleRoot);
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        address nonWhitelisted = address(0x6);
        vm.deal(nonWhitelisted, 1 ether);
        vm.prank(nonWhitelisted);
        vm.expectRevert(IPresale.NotWhitelisted.selector);
        presale.contribute{value: 1 ether}(new bytes32[](0));
    }
    
    function testContributeStablecoin() public {
        vm.startPrank(owner);
        presale = new Presale(
            weth,
            address(token),
            address(uniswapRouter),
            optionsStablecoin,
            owner,
            address(liquidityLocker),
            address(vesting),
            HOUSE_PERCENTAGE,
            houseAddress
        );
        token.approve(address(presale), INITIAL_SUPPLY);
        presale.deposit();
        vm.stopPrank();
        vm.warp(START_TIME);
        
        uint256 contribution = 1 ether;
        vm.prank(contributor1);
        stablecoin.approve(address(presale), contribution);
        vm.prank(contributor1);
        presale.contributeStablecoin(contribution, new bytes32[](0));
        
        assertEq(presale.pool().weiRaised, contribution);
        assertEq(presale.contributions(contributor1), contribution);
        assertEq(stablecoin.balanceOf(address(presale)), contribution);
    }
    
    function testFinalize() public {
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        uint256 contribution = 50 ether;
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(END_TIME + 1);
        
        uint256 liquidityAmount = (contribution * LIQUIDITY_BPS) / BASIS_POINTS;
        uint256 houseAmount = (contribution * HOUSE_PERCENTAGE) / BASIS_POINTS;
        uint256 ownerAmount = contribution - liquidityAmount - houseAmount;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Finalized(owner, contribution, block.timestamp);
        presale.finalize();
        
        assertEq(uint8(presale.pool().state), 4); // Finalized
        assertEq(presale.ownerBalance(), ownerAmount);
        assertEq(houseAddress.balance, houseAmount);
        assertEq(liquidityLocker.lockCount(), 1);
        (address lockToken, uint256 lockAmount, uint256 unlockTime, address lockOwner) = liquidityLocker.getLock(0);
        assertEq(lockOwner, owner);
        assertEq(unlockTime, block.timestamp + LOCKUP_DURATION);
        assertGt(lockAmount, 0);
    }
    
    function testFinalizeWithLeftoverTokensVest() public {
        optionsETH.leftoverTokenOption = 2; // Vest
        vm.startPrank(owner);
        presale = new Presale(
            weth,
            address(token),
            address(uniswapRouter),
            optionsETH,
            owner,
            address(liquidityLocker),
            address(vesting),
            HOUSE_PERCENTAGE,
            houseAddress
        );
        token.approve(address(presale), INITIAL_SUPPLY);
        presale.deposit();
        vm.stopPrank();
        
        uint256 contribution = 50 ether;
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(END_TIME + 1);
        
        vm.prank(owner);
        presale.finalize();
        
        uint256 unsoldTokens = optionsETH.tokenDeposit - (presale.pool().tokensClaimable + presale.pool().tokensLiquidity);
        (uint256 totalAmount, , , , bool exists) = vesting.schedules(owner, 0);
        assertTrue(exists);
        assertEq(totalAmount, unsoldTokens);
    }
    
    function testClaim() public {
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        uint256 contribution = 1 ether;
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(END_TIME + 1);
        
        vm.prank(owner);
        presale.finalize();
        
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit TokenClaim(contributor1, contribution * PRESALE_RATE, block.timestamp);
        presale.claim();
        
        uint256 totalTokens = contribution * PRESALE_RATE;
        uint256 vestedTokens = (totalTokens * VESTING_PERCENTAGE) / BASIS_POINTS;
        uint256 immediateTokens = totalTokens - vestedTokens;
        
        assertEq(token.balanceOf(contributor1), immediateTokens);
        (uint256 totalAmount, , , , bool exists) = vesting.schedules(contributor1, 0);
        assertTrue(exists);
        assertEq(totalAmount, vestedTokens);
    }
    
    function testRefund() public {
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        uint256 contribution = 1 ether;
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(END_TIME + 1);
        
        vm.prank(contributor1);
        vm.expectEmit(true, true, true, true);
        emit Refund(contributor1, contribution, block.timestamp);
        presale.refund();
        
        assertEq(contributor1.balance, contribution);
        assertEq(presale.contributions(contributor1), 0);
        assertEq(presale.totalRefundable(), 0);
    }
    
    function testCancel() public {
        vm.prank(owner);
        presale.deposit();
        
        uint256 tokenBalance = presale.pool().tokenDeposit;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Cancel(owner, block.timestamp);
        presale.cancel();
        
        assertEq(uint8(presale.pool().state), 3); // Canceled
        assertEq(presale.pool().tokenBalance, 0);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }
    
    function testWithdraw() public {
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        uint256 contribution = 50 ether;
        vm.deal(contributor1, contribution);
        vm.prank(contributor1);
        presale.contribute{value: contribution}(new bytes32[](0));
        vm.warp(END_TIME + 1);
        
        vm.prank(owner);
        presale.finalize();
        
        uint256 ownerBalance = presale.ownerBalance();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(owner, ownerBalance);
        presale.withdraw();
        
        assertEq(owner.balance, ownerBalance);
        assertEq(presale.ownerBalance(), 0);
    }
    
    function testRescueTokens() public {
        vm.prank(owner);
        presale.deposit();
        vm.prank(owner);
        presale.cancel();
        
        ERC20Mock otherToken = new ERC20Mock();
        otherToken.mint(address(presale), 1000 * 10**18);
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TokensRescued(address(otherToken), owner, 500 * 10**18);
        presale.rescueTokens(address(otherToken), owner, 500 * 10**18);
        
        assertEq(otherToken.balanceOf(owner), 500 * 10**18);
    }
    
    function testToggleWhitelist() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelistToggled(true);
        presale.toggleWhitelist(true);
        assertTrue(presale.whitelistEnabled());
    }
    
    function testUpdateWhitelist() public {
        address[] memory addresses = new address[](2);
        addresses[0] = contributor1;
        addresses[1] = contributor2;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(contributor1, true);
        presale.updateWhitelist(addresses, true);
        
        assertTrue(presale.whitelist(contributor1));
        assertTrue(presale.whitelist(contributor2));
    }
    
    function testPause() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Paused(owner);
        presale.pause();
        assertTrue(presale.paused());
    }
    
    function testFuzzContributeETH(uint256 amount) public {
        vm.prank(owner);
        presale.deposit();
        vm.warp(START_TIME);
        
        vm.assume(amount >= MIN_CONTRIBUTION && amount <= MAX_CONTRIBUTION);
        vm.assume(amount <= HARD_CAP);
        
        vm.deal(contributor1, amount);
        vm.prank(contributor1);
        presale.contribute{value: amount}(new bytes32[](0));
        
        assertEq(presale.pool().weiRaised, amount);
        assertEq(presale.contributions(contributor1), amount);
    }
    
    // Helper functions
    function getMerkleRoot(address[] memory users) internal pure returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(users[i]));
        }
        if (leaves.length == 0) return bytes32(0);
        while (leaves.length > 1) {
            bytes32[] memory newLeaves = new bytes32[]((leaves.length + 1) / 2);
            for (uint256 i = 0; i < leaves.length; i += 2) {
                bytes32 left = leaves[i];
                bytes32 right = i + 1 < leaves.length ? leaves[i + 1] : left;
                newLeaves[i / 2] = keccak256(abi.encodePacked(left < right ? left : right, left < right ? right : left));
            }
            leaves = newLeaves;
        }
        return leaves[0];
    }
    
    function getMerkleProof(address user) internal pure returns (bytes32[] memory) {
        address[] memory users = new address[](2);
        users[0] = address(0x2); // contributor1
        users[1] = address(0x3); // contributor2
        bytes32[] memory leaves = new bytes32[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(users[i]));
        }
        bytes32 leaf = keccak256(abi.encodePacked(user));
        bytes32[] memory proof = new bytes32[](1); // Simplified for 2 users
        uint256 index = user == users[0] ? 0 : 1;
        proof[0] = leaves[index == 0 ? 1 : 0];
        return proof;
    }
}