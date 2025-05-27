// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/contracts/Presale.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000_000_000 * 10 ** 18); // 1T tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockLiquidityLocker {
    // Simulate receiving LP tokens
    function lock(address lpTokenAddress, uint256 amount, uint256, /*unlockTime*/ address /*beneficiary*/ ) external {
        // In a real scenario, this would call transferFrom on the lpTokenAddress
        // For the mock, we'll assume the Presale contract (msg.sender to this function via Presale.sol)
        // has approved this contract, and this contract now "owns" the LP tokens.
        MockUniswapV2Pair(lpTokenAddress).transferFrom(msg.sender, address(this), amount);
    }
}

contract MockVesting {
    function createVesting(address, address, address, uint256, uint256, uint256) external {}
}

contract PresaleTest is Test {
    Presale presaleGlobal; // Renamed to avoid conflict with local var in tests
    MockERC20 tokenGlobal;
    MockERC20 currencyGlobal;
    MockLiquidityLocker liquidityLockerGlobal;
    MockVesting vestingGlobal;
    IUniswapV2Router02 routerGlobal;
    IUniswapV2Factory factoryGlobal;
    address weth;
    address deployer;
    address user1;
    address house;
    uint256 startTime;

    // Presale parameters
    Presale.PresaleOptions internal baseOptions;

    // Helper to setup base addresses and deals
    function _setupAddressesAndDeals() internal {
        deployer = makeAddr("deployer");
        house = makeAddr("house");
        vm.deal(deployer, 100_000 ether);
        vm.deal(user1, 20_000 ether);

        // Set fixed start time
        startTime = block.timestamp + 100;
        baseOptions = Presale.PresaleOptions({
            tokenDeposit: 704_000_000_000 * 10 ** 18, // 704B tokens
            hardCap: 50_000 * 10 ** 18, // 50,000 ETH
            softCap: 10_000 * 10 ** 18, // 10,000 ETH
            min: 1 * 10 ** 18, // 1 ETH
            max: 20_000 * 10 ** 18, // 20,000 ETH
            presaleRate: 10_000_000, // 10M tokens/ETH
            listingRate: 8_000_000, // 8M tokens/ETH
            liquidityBps: 5100, // 51%
            slippageBps: 300, // 3%
            start: startTime,
            end: startTime + 1 hours,
            lockupDuration: 30 days,
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 2,
            currency: address(0), // ETH
            whitelistType: Presale.WhitelistType.None,
            merkleRoot: bytes32(0),
            nftContractAddress: address(0)
        });

        // Deploy mock Uniswap V2
        weth = address(new MockERC20("WETH", "WETH"));
        factoryGlobal = IUniswapV2Factory(deployUniswapV2Factory());
        routerGlobal = IUniswapV2Router02(deployUniswapV2Router(address(factoryGlobal), weth));

        // Deploy contracts
        vm.startPrank(deployer);
        tokenGlobal = new MockERC20("TestToken", "TTK");
        liquidityLockerGlobal = new MockLiquidityLocker();
        vestingGlobal = new MockVesting();
        currencyGlobal = new MockERC20("Currency", "CUR"); // Though not used if currency is address(0)
        vm.stopPrank();
    }

    // Setup for tests where a pool already exists
    function setUp_WithExistingPool() internal {
        _setupAddressesAndDeals();
        user1 = makeAddr("user1_existing_pool_test"); // Ensure unique user for this setup context
        vm.deal(user1, 20_000 ether);

        vm.startPrank(deployer);
        presaleGlobal = new Presale(
            weth,
            address(tokenGlobal),
            address(routerGlobal),
            baseOptions,
            deployer,
            address(liquidityLockerGlobal),
            address(vestingGlobal),
            100, // 1% house fee
            house,
            deployer // Factory address
        );

        // Create Uniswap pair and add initial liquidity
        factoryGlobal.createPair(address(tokenGlobal), weth);
        tokenGlobal.approve(address(routerGlobal), 141_704_869_404 * 10 ** 18);
        vm.deal(deployer, 10_200 ether); // Increased to match presale liquidity
        routerGlobal.addLiquidityETH{value: 10_200 ether}(
            address(tokenGlobal), 141_704_869_404 * 10 ** 18, 0, 0, deployer, block.timestamp + 1 hours
        );
        vm.stopPrank();
    }

    // Setup for tests where the presale should create the pool
    function setUp_ForNewPoolCreation() internal returns (Presale currentPresale) {
        _setupAddressesAndDeals();
        user1 = makeAddr("user1_new_pool_test"); // Ensure unique user for this setup context
        vm.deal(user1, 20_000 ether);

        vm.startPrank(deployer);
        // Create a new token instance for this test to avoid interference
        MockERC20 localToken = new MockERC20("LocalTestToken", "LTT");

        currentPresale = new Presale(
            weth,
            address(localToken),
            address(routerGlobal),
            baseOptions,
            deployer,
            address(liquidityLockerGlobal),
            address(vestingGlobal),
            100,
            house,
            deployer
        );

        localToken.approve(address(currentPresale), baseOptions.tokenDeposit);
        localToken.transfer(address(currentPresale), baseOptions.tokenDeposit);
        currentPresale.initializeDeposit();
        vm.stopPrank();
    }

    // Scenario 5: initializeDeposit fails if a pool already exists (was testFinalizeFailure)
    function testInitializeDeposit_Fails_IfPairExists_FromLiquidityMismatchSetup() public {
        setUp_WithExistingPool(); // This setup creates a pool with a specific rate
        // Deposit tokens to this specific presale instance
        vm.startPrank(deployer);
        tokenGlobal.approve(address(presaleGlobal), baseOptions.tokenDeposit);
        tokenGlobal.transfer(address(presaleGlobal), baseOptions.tokenDeposit);

        // Attempt to initializeDeposit (should fail because pair for tokenGlobal exists)
        vm.expectRevert(abi.encodeWithSelector(IPresale.PairAlreadyExists.selector, address(tokenGlobal), weth));
        presaleGlobal.initializeDeposit();
        vm.stopPrank();
    }

    // Scenario 1: Successful finalization, pool creation
    function testFinalize_Success_CreatesPoolAndAddsLiquidity() public {
        Presale currentPresale = setUp_ForNewPoolCreation();
        MockERC20 localToken = MockERC20(address(currentPresale.token()));

        // Assert no pair exists initially
        address pairAddressBefore = factoryGlobal.getPair(address(localToken), weth);
        assertEq(pairAddressBefore, address(0), "Pair should not exist before finalize");

        // Advance time to within presale period
        vm.warp(baseOptions.start + 1);

        // Contribute 20,000 ETH
        vm.prank(user1);
        currentPresale.contribute{value: 20_000 ether}(new bytes32[](0)); // Meet hardcap

        // Advance time to after presale end
        vm.warp(baseOptions.end + 1);

        // Finalize (should succeed)
        // Capture deployer's balance before operations that spend its gas and give it income
        // uint256 deployerBalanceBeforeFinalizeAndWithdraw = deployer.balance;

        vm.startPrank(deployer);
        currentPresale.finalize();
        // Deployer withdraws their share
        currentPresale.withdraw();
        vm.stopPrank();

        uint256 deployerBalanceAfterFinalizeAndWithdraw = deployer.balance;

        // Assertions
        assertEq(uint256(currentPresale.state()), uint256(Presale.PresaleState.Finalized), "Presale not finalized");
        address pairAddressAfter = factoryGlobal.getPair(address(localToken), weth);
        assertNotEq(pairAddressAfter, address(0), "Pair was not created");
        assertTrue(IUniswapV2Pair(pairAddressAfter).balanceOf(address(liquidityLockerGlobal)) > 0, "LP not locked");

        uint256 expectedOwnerBalance = (20_000 ether * (10000 - baseOptions.liquidityBps - 100)) / 10000; // 1% house fee
        // Check that deployer's balance increased by expectedOwnerBalance, accounting for gas.
        // (Balance After) should be (Balance Before) + expectedOwnerBalance - gas costs.
        // So, (Balance After - Balance Before - expectedOwnerBalance) should be negative (representing gas).
        // For simplicity, we'll check if the final balance is greater than the initial balance if owner portion > gas.
        // A more precise check would involve estimating gas or using assertApproxEqAbs if gas is an issue.
        // Given the trace showed deployer.balance as 100k ETH, let's assume for this check it means "initial deal + received funds - gas".
        // The most reliable check is that the ownerBalance in contract is now 0.
        assertEq(currentPresale.ownerBalance(), 0, "Owner balance in presale contract not zero after withdrawal");
        // And deployer's balance is roughly initial + owner's share (actual gas makes this an approximation)
        // The trace indicates `deployer.balance` in assertEq might refer to the raw `vm.deal` value.
        // If so, after withdraw, it should be `initial_deal + expectedOwnerBalance - total_gas_spent_by_deployer`.
        // Let's try asserting the final balance is close to initial + expected gain, allowing for some gas.
        uint256 expectedFinalDeployerBalance = 100_000 ether + expectedOwnerBalance; // Ideal balance ignoring gas
        // Allow for up to 0.1 ETH in gas costs for all deployer's operations in this test. This is a rough estimate.
        assertTrue(deployerBalanceAfterFinalizeAndWithdraw <= expectedFinalDeployerBalance, "Deployer balance too high");
        assertTrue(
            deployerBalanceAfterFinalizeAndWithdraw >= expectedFinalDeployerBalance - 0.1 ether,
            "Deployer ETH balance incorrect after withdraw"
        );

        assertEq(house.balance, (20_000 ether * 100) / 10000, "House ETH balance incorrect");
    }

    // Scenario 2: initializeDeposit fails if pair already exists
    function testInitializeDeposit_Fails_IfPairAlreadyExists() public {
        setUp_WithExistingPool(); // This setup creates a pair (tokenGlobal with weth)

        // Need to deploy a new presale instance that uses tokenGlobal for this test
        vm.startPrank(deployer);
        Presale currentPresale = new Presale(
            weth,
            address(tokenGlobal), // Use the token for which a pair already exists
            address(routerGlobal),
            baseOptions,
            deployer,
            address(liquidityLockerGlobal),
            address(vestingGlobal),
            100,
            house,
            deployer
        );
        tokenGlobal.approve(address(currentPresale), baseOptions.tokenDeposit);
        tokenGlobal.transfer(address(currentPresale), baseOptions.tokenDeposit);
        // Attempt to initialize deposit, which should fail
        vm.expectRevert(abi.encodeWithSelector(IPresale.PairAlreadyExists.selector, address(tokenGlobal), weth));
        currentPresale.initializeDeposit();
        vm.stopPrank();
    }

    // Scenario 3: Finalization fails if soft cap not met
    function testFinalize_Fails_IfSoftCapNotMet() public {
        Presale currentPresale = setUp_ForNewPoolCreation();

        vm.warp(baseOptions.start + 1);
        vm.prank(user1);
        currentPresale.contribute{value: 1 ether}(new bytes32[](0)); // Less than softCap

        vm.warp(baseOptions.end + 1);
        vm.prank(deployer);
        vm.expectRevert(IPresale.SoftCapNotReached.selector);
        currentPresale.finalize();
    }

    // Scenario 4: Finalization fails if presale not ended
    function testFinalize_Fails_IfPresaleNotEnded() public {
        Presale currentPresale = setUp_ForNewPoolCreation();

        vm.warp(baseOptions.start + 1);
        vm.prank(user1);
        currentPresale.contribute{value: 20_000 ether}(new bytes32[](0)); // Meet hardcap

        // DO NOT warp time past presale.end
        vm.prank(deployer);
        vm.expectRevert(IPresale.PresaleNotEnded.selector);
        currentPresale.finalize();
    }

    // Helper to deploy Uniswap V2 Factory
    function deployUniswapV2Factory() internal returns (address) {
        return address(new MockUniswapV2Factory(deployer));
    }

    // Helper to deploy Uniswap V2 Router
    function deployUniswapV2Router(address _factory, address _weth) internal returns (address) {
        return address(new MockUniswapV2Router02(_factory, _weth));
    }
}

// Mock UniswapV2Factory
contract MockUniswapV2Factory {
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(new MockUniswapV2Pair(token0, token1));
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
    }
}

// Mock UniswapV2Pair
contract MockUniswapV2Pair {
    address public token0;
    address public token1;
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public blockTimestampLast;
    mapping(address => uint256) public balanceOf;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address, /*spender*/ uint256 /*value*/ ) external pure returns (bool) {
        // Mock approval, does nothing but allows the call to succeed
        return true;
    }

    // Mock transferFrom to allow LiquidityLocker to pull tokens
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // Basic check, a real ERC20 would check allowance
        require(balanceOf[from] >= amount, "MockUniswapV2Pair: insufficient balance for transferFrom");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        // emit Transfer(from, to, amount); // Optional: emit event
        return true;
    }
}

// Mock UniswapV2Router02
contract MockUniswapV2Router02 {
    address public factory;
    address public WETH;

    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin, // Commented out to silence warning, but kept for signature
        uint256 amountETHMin, // Commented out to silence warning, but kept for signature
        address to,
        uint256 deadline
    ) external payable returns (uint256, uint256, uint256) {
        require(block.timestamp <= deadline, "UniswapV2Router: EXPIRED");
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        (uint112 reserve0, uint112 reserve1,) = MockUniswapV2Pair(pair).getReserves();
        (uint112 rToken, uint112 rETH) = token < WETH ? (reserve0, reserve1) : (reserve1, reserve0);

        uint256 amountETHDesired = msg.value; // ETH actually sent by the caller (Presale contract)
        uint256 actualAmountTokenToAdd = amountTokenDesired;
        uint256 actualAmountETHToAdd = amountETHDesired;

        if (rToken > 0 && rETH > 0) {
            // If there's existing liquidity
            uint256 amountBOptimal = (amountTokenDesired * uint256(rETH)) / uint256(rToken); // Optimal ETH for amountTokenDesired
            if (amountBOptimal <= amountETHDesired) {
                // We have enough ETH for the desired tokens; router would use amountTokenDesired and amountBOptimal ETH.
                // Check slippage against amountETHMin.
                require(amountBOptimal >= amountETHMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
                actualAmountETHToAdd = amountBOptimal;
            } else {
                // Not enough ETH for desired tokens; router would use all amountETHDesired and calculate optimal tokens.
                uint256 amountAOptimal = (amountETHDesired * uint256(rToken)) / uint256(rETH);
                require(amountAOptimal >= amountTokenMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
                actualAmountTokenToAdd = amountAOptimal;
            }
        }

        // These are the total new reserves for 'token' (the presale token) and 'WETH'
        uint112 newTotalReserveToken = uint112(rToken + actualAmountTokenToAdd);
        uint112 newTotalReserveETH = uint112(rETH + actualAmountETHToAdd);

        address pairToken0 = MockUniswapV2Pair(pair).token0();

        // Ensure reserves are set in the pair contract according to its token0/token1 order
        if (token == pairToken0) {
            // If the presale token ('token') is token0 of the pair
            MockUniswapV2Pair(pair).setReserves(newTotalReserveToken, newTotalReserveETH);
        } else {
            // The presale token ('token') must be token1 of the pair (so WETH is token0)
            MockUniswapV2Pair(pair).setReserves(newTotalReserveETH, newTotalReserveToken);
        }

        MockUniswapV2Pair(pair).mint(to, 1e18); // Mock LP tokens

        return (actualAmountTokenToAdd, actualAmountETHToAdd, 1e18); // Return actual amounts used
    }
}
