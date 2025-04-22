// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ==========================================================================================
// Imports
// ==========================================================================================
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Import interfaces and contracts
import {IPresale} from "../src/contracts/interfaces/IPresale.sol";
import {Presale} from "../src/contracts/Presale.sol";
import {TestToken} from "../src/contracts/TestToken.sol";
import {LiquidityLocker} from "../src/contracts/LiquidityLocker.sol";
import {Vesting} from "../src/contracts/Vesting.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ==========================================================================================
// Mocks
// ==========================================================================================

contract MockERC20 is TestToken {
    string internal mockName_;
    string internal mockSymbol_;

    constructor(string memory _name, string memory _symbol, uint256 initialSupply) TestToken(0) {
        mockName_ = _name;
        mockSymbol_ = _symbol;
        if (initialSupply > 0) _mint(msg.sender, initialSupply);
    }

    function name() public view virtual override returns (string memory) {
        return mockName_;
    }

    function symbol() public view virtual override returns (string memory) {
        return mockSymbol_;
    }

    function decimals() public view virtual override returns (uint8) {
        if (compareStrings(mockSymbol_, "USDC")) return 6;
        return 18;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 0) {}
}

contract MockUniswapV2Pair is MockERC20 {
    constructor() MockERC20("Uniswap V2 Pair", "UNI-V2", 0) {}

    mapping(address => uint256) public mintRecord;

    function mint(address to, uint256 value) external {
        _mint(to, value);
        mintRecord[to] += value;
    }
}

contract MockUniswapV2Factory is IUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address public mockRouter;
    address public lastCreatedPairTokenA;
    address public lastCreatedPairTokenB;
    address public pairToReturn;

    constructor(address _pairToReturn) {
        pairToReturn = _pairToReturn;
    }

    function feeTo() external view override returns (address) {
        return address(0);
    }

    function feeToSetter() external view override returns (address) {
        return address(0);
    }

    function allPairs(uint256 i) external view override returns (address pair) {
        return address(0);
    }

    function allPairsLength() external view override returns (uint256) {
        return 0;
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, "Identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
        require(getPair[token0][token1] == address(0), "Pair exists");
        pair = pairToReturn;
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        lastCreatedPairTokenA = tokenA;
        lastCreatedPairTokenB = tokenB;
        emit PairCreated(token0, token1, pair, 1);
    }

    function setFeeTo(address) external override {}
    function setFeeToSetter(address) external override {}

    function setRouter(address _router) external {
        mockRouter = _router;
    }

    function setMockPair(address tokenA, address tokenB, address pair) external {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
    }
}

contract MockUniswapV2Router02 is IUniswapV2Router02 {
    using SafeERC20 for IERC20;

    // address public immutable factory;
    address public immutable weth;
    MockUniswapV2Pair public immutable pair;
    uint256 public addLiquidityETHTokenAmount;
    uint256 public addLiquidityETHValue;
    address public addLiquidityETHToken;
    uint256 public addLiquidityTokenAAmount;
    uint256 public addLiquidityTokenBAmount;
    address public addLiquidityTokenA;
    address public addLiquidityTokenB;

    constructor(address _factory, address _weth, address _pair) {
        factory = _factory;
        weth = _weth;
        pair = MockUniswapV2Pair(_pair);
    }

    receive() external payable {}

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        addLiquidityTokenA = tokenA;
        addLiquidityTokenB = tokenB;
        addLiquidityTokenAAmount = amountADesired;
        addLiquidityTokenBAmount = amountBDesired;
        IERC20(tokenA).safeTransferFrom(msg.sender, address(pair), amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(pair), amountBDesired);
        liquidity = (amountADesired + amountBDesired) / 2;
        pair.mint(to, liquidity);
        return (amountADesired, amountBDesired, liquidity);
    }

    function addLiquidityETH(address token, uint256 amountTokenDesired, uint256, uint256, address to, uint256)
        external
        payable
        override
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        addLiquidityETHToken = token;
        addLiquidityETHTokenAmount = amountTokenDesired;
        addLiquidityETHValue = msg.value;
        IERC20(token).safeTransferFrom(msg.sender, address(pair), amountTokenDesired);
        liquidity = (amountTokenDesired + msg.value) / 2;
        pair.mint(to, liquidity);
        return (amountTokenDesired, msg.value, liquidity);
    }

    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256)
        external
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }

    function removeLiquidityETH(address, uint256, uint256, uint256, address, uint256)
        external
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }

    function removeLiquidityWithPermit(
        address,
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external override returns (uint256, uint256) {
        return (0, 0);
    }

    function removeLiquidityETHWithPermit(
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external override returns (uint256, uint256) {
        return (0, 0);
    }

    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](0);
    }

    function swapTokensForExactTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](0);
    }

    function swapExactETHForTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](0);
    }

    function swapTokensForExactETH(uint256, uint256, address[] calldata, address, uint256)
        external
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](0);
    }

    function swapExactTokensForETH(uint256, uint256, address[] calldata, address, uint256)
        external
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](0);
    }

    function swapETHForExactTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](0);
    }

    function quote(uint256, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getAmountOut(uint256, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getAmountIn(uint256, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getAmountsOut(uint256, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
    }

    function getAmountsIn(uint256, address[] calldata path) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(address, uint256, uint256, uint256, address, uint256)
        external
        override
        returns (uint256)
    {
        return 0;
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external override returns (uint256) {
        return 0;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external override {}
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        override
    {}
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        override
    {}

    function WETH() external pure override returns (address) {
        return weth;
    }

    function factory() external view override returns (address) {
        return factory;
    }
}

contract MockLiquidityLocker {
    address public lastLockedToken;
    uint256 public lastLockedAmount;
    uint256 public lastUnlockTime;
    address public lastLockedOwner;
    uint256 public lockCallCount;

    event LiquidityLocked(address indexed token, uint256 amount, uint256 unlockTime, address indexed owner);

    function lock(address _token, uint256 _amount, uint256 _unlockTime, address _owner) external {
        lastLockedToken = _token;
        lastLockedAmount = _amount;
        lastUnlockTime = _unlockTime;
        lastLockedOwner = _owner;
        lockCallCount++;
        emit LiquidityLocked(_token, _amount, _unlockTime, _owner);
    }
}

contract MockVesting {
    using SafeERC20 for IERC20;

    address public lastBeneficiary;
    uint256 public lastAmount;
    uint256 public lastStart;
    uint256 public lastDuration;
    uint256 public lastScheduleId;
    uint256 public createVestingCallCount;
    IERC20 public immutable token;
    mapping(address => uint256) public scheduleCount;
    uint256 public totalAllocated;

    event VestingCreated(
        address indexed beneficiary, uint256 amount, uint256 start, uint256 duration, uint256 scheduleId
    );

    address private _owner;

    modifier onlyOwner() {
        require(msg.sender == _owner, "MockVesting: caller is not the owner");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        _owner = msg.sender;
    }

    function createVesting(address _beneficiary, uint256 _amount, uint256 _start, uint256 _duration)
        external
        onlyOwner
    {
        lastBeneficiary = _beneficiary;
        lastAmount = _amount;
        lastStart = _start;
        lastDuration = _duration;
        lastScheduleId = scheduleCount[_beneficiary];
        createVestingCallCount++;
        token.safeTransferFrom(msg.sender, address(this), _amount);
        scheduleCount[_beneficiary]++;
        totalAllocated += _amount;
        emit VestingCreated(_beneficiary, _amount, _start, _duration, lastScheduleId);
    }
}

// ==========================================================================================
// Helper Functions (Defined outside contracts)
// ==========================================================================================

function generateMerkleTree(bytes32[] memory leaves, uint256 leafIndex)
    internal
    
    returns (bytes32 root, bytes32[] memory proof)
{
    uint256 n = leaves.length;
    require(n > 0, "Empty leaves");
    require(leafIndex < n, "Leaf index out of bounds");
    if (n == 1) {
        root = leaves[0];
        proof = new bytes32[](0);
        return (root, proof);
    }
    bytes32[] memory tree = new bytes32[](2 * n - 1);
    for (uint256 i = 0; i < n; i++) {
        tree[i] = leaves[i];
    }
    uint256 levelOffset = 0;
    uint256 levelNodeCount = n;
    uint256 treeIndex = n;
    while (levelNodeCount > 1) {
        for (uint256 i = 0; i < levelNodeCount / 2; i++) {
            bytes32 left = tree[levelOffset + i * 2];
            bytes32 right = tree[levelOffset + i * 2 + 1];
            tree[treeIndex++] = MerkleProof.hashPair(left, right);
        }
        if (levelNodeCount % 2 == 1) tree[treeIndex++] = tree[levelOffset + levelNodeCount - 1];
        levelOffset += levelNodeCount;
        levelNodeCount = (levelNodeCount + 1) / 2;
    }
    root = tree[tree.length - 1];
    uint256 proofSize = 0;
    uint256 tempSize = n;
    while (tempSize > 1) {
        proofSize++;
        tempSize = (tempSize + 1) / 2;
    }
    proof = new bytes32[](proofSize);
    uint256 currentIndex = leafIndex;
    levelOffset = 0;
    uint256 proofIndex = 0;
    levelNodeCount = n;
    treeIndex = 0;
    while (levelNodeCount > 1) {
        uint256 pairIndex = currentIndex / 2;
        uint256 siblingIndex;
        if (currentIndex % 2 == 0) {
            siblingIndex = currentIndex + 1;
            if (siblingIndex < levelNodeCount) proof[proofIndex++] = tree[levelOffset + siblingIndex];
        } else {
            siblingIndex = currentIndex - 1;
            proof[proofIndex++] = tree[levelOffset + siblingIndex];
        }
        currentIndex = pairIndex;
        levelOffset += levelNodeCount;
        levelNodeCount = (levelNodeCount + 1) / 2;
    }
    assembly {
        mstore(proof, proofIndex)
    }
}

// ==========================================================================================
// Base Test Contract
// ==========================================================================================
contract PresaleTestBase is Test {
    // Contracts
    Presale presale; // The contract under test
    MockERC20 presaleToken;
    MockERC20 currencyToken;
    MockWETH weth;
    MockLiquidityLocker locker;
    MockVesting vesting;
    MockUniswapV2Router02 router;
    MockUniswapV2Factory factory;
    MockUniswapV2Pair pair;

    // Users
    address internal owner; // Use internal for inheritance access
    address internal contributor1;
    address internal contributor2;
    address internal houseAddress;
    address internal otherUser;

    // Presale Params
    uint256 internal start;
    uint256 internal end;
    uint256 internal lockupDuration = 30 days;
    uint256 internal tokenDecimals = 18;
    uint256 internal currencyDecimals = 6;
    uint256 internal presaleRate = 1000 * (10 ** tokenDecimals / 1 ether);
    uint256 internal listingRate = 800 * (10 ** tokenDecimals / 1 ether);
    uint256 internal hardCap = 100 ether;
    uint256 internal softCap = 25 ether;
    uint256 internal maxContribution = 10 ether;
    uint256 internal minContribution = 0.1 ether;
    uint256 internal liquidityBps = 5000;
    uint256 internal housePercentage = 100;
    uint256 internal vestingPercentage = 2500;
    uint256 internal vestingDuration = 90 days;

    Presale.PresaleOptions internal optionsETH;
    Presale.PresaleOptions internal optionsStable;

    // Merkle Tree setup
    bytes32[] internal proof1;
    bytes32 internal merkleRoot;

    // ======================== Setup ========================
    function setUp() public virtual {
        // Make setUp virtual for potential overrides
        // Define users
        owner = makeAddr("owner");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");
        houseAddress = makeAddr("house");
        otherUser = makeAddr("otherUser");

        // Deploy Mocks
        vm.startPrank(owner); // Deploy mocks as owner for convenience
        presaleToken = new MockERC20("Presale Token", "PRE", 10_000_000 * 10 ** tokenDecimals);
        currencyToken = new MockERC20("USD Coin", "USDC", 10_000_000 * 10 ** currencyDecimals);
        weth = new MockWETH();
        locker = new MockLiquidityLocker(); // Deployed as owner
        vesting = new MockVesting(address(presaleToken)); // Deployed as owner
        pair = new MockUniswapV2Pair();
        factory = new MockUniswapV2Factory(address(pair));
        router = new MockUniswapV2Router02(address(factory), address(weth), address(pair));
        factory.setRouter(address(router));
        factory.setMockPair(address(presaleToken), address(weth), address(pair));
        factory.setMockPair(address(presaleToken), address(currencyToken), address(pair));
        vm.stopPrank();

        // Setup time
        start = block.timestamp + 1 days;
        end = start + 7 days;

        // Configure Options (ETH)
        optionsETH = Presale.PresaleOptions({
            tokenDeposit: 0,
            hardCap: hardCap,
            softCap: softCap,
            max: maxContribution,
            min: minContribution,
            start: start,
            end: end,
            liquidityBps: liquidityBps,
            slippageBps: 100,
            presaleRate: presaleRate,
            listingRate: listingRate,
            lockupDuration: lockupDuration,
            currency: address(0),
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0
        });
        optionsETH.tokenDeposit = calculateDeposit(optionsETH);

        // Configure Options (Stable)
        optionsStable = Presale.PresaleOptions({
            tokenDeposit: 0,
            hardCap: hardCap * (10 ** currencyDecimals) / (10 ** 18),
            softCap: softCap * (10 ** currencyDecimals) / (10 ** 18),
            max: maxContribution * (10 ** currencyDecimals) / (10 ** 18),
            min: minContribution * (10 ** currencyDecimals) / (10 ** 18),
            start: start,
            end: end,
            liquidityBps: liquidityBps,
            slippageBps: 100,
            presaleRate: presaleRate * (10 ** 18) / (10 ** currencyDecimals),
            listingRate: listingRate * (10 ** 18) / (10 ** currencyDecimals),
            lockupDuration: lockupDuration,
            currency: address(currencyToken),
            vestingPercentage: 0,
            vestingDuration: 0,
            leftoverTokenOption: 0
        });
        optionsStable.tokenDeposit = calculateDeposit(optionsStable);

        // Deploy Presale (ETH version for default tests) - Tests can redeploy if needed
        vm.startPrank(owner);
        presale = deployPresale(optionsETH);
        vm.stopPrank();

        // Initial setup for contributors
        currencyToken.mint(contributor1, optionsStable.max * 2); // Mint stablecoin directly
        currencyToken.mint(contributor2, optionsStable.max * 2);
        vm.deal(contributor1, maxContribution * 2);
        vm.deal(contributor2, maxContribution * 2);
        vm.deal(houseAddress, 1 ether);

        // Setup Merkle Tree
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(contributor1));
        leaves[1] = keccak256(abi.encodePacked(contributor2));
        (merkleRoot, proof1) = generateMerkleTree(leaves, 0);
    }

    // ======================== Helpers ========================
    // Helpers are now part of the base contract
    function deployPresale(Presale.PresaleOptions memory _options) internal returns (Presale) {
        uint256 requiredDeposit = calculateDeposit(_options);
        uint256 currentBalance = presaleToken.balanceOf(owner);
        if (currentBalance < requiredDeposit) {
            vm.prank(owner); // Ensure mint is done as owner if needed by MockERC20
            presaleToken.mint(owner, requiredDeposit - currentBalance);
        }
        vm.prank(owner); // Ensure deployment and approval are done as owner
        Presale newPresale = new Presale(
            address(weth),
            address(presaleToken),
            address(router),
            _options,
            owner,
            address(locker),
            address(vesting),
            housePercentage,
            houseAddress
        );
        presaleToken.approve(address(newPresale), requiredDeposit);
        vm.stopPrank(); // Stop prank after deployment/approval
        return newPresale;
    }

    function calculateDeposit(Presale.PresaleOptions memory _opts) internal view returns (uint256) {
        uint256 _currencyDecimals = _opts.currency == address(0) ? 18 : MockERC20(_opts.currency).decimals();
        uint256 _tokenDecimals = presaleToken.decimals();
        uint256 factor = 10 ** _currencyDecimals;
        if (factor == 0) factor = 1;
        uint256 presaleTokens = (_opts.hardCap * _opts.presaleRate * (10 ** _tokenDecimals)) / factor;
        uint256 liquidityAmountBase = (_opts.hardCap * _opts.liquidityBps) / Presale.BASIS_POINTS;
        uint256 liquidityTokens = (liquidityAmountBase * _opts.listingRate * (10 ** _tokenDecimals)) / factor;
        return presaleTokens + liquidityTokens;
    }

    function _depositTokens() internal {
        vm.startPrank(owner);
        uint256 depositAmount = presale.pool_options_tokenDeposit();
        uint256 ownerBalance = presaleToken.balanceOf(owner);
        if (ownerBalance < depositAmount) {
            presaleToken.mint(owner, depositAmount - ownerBalance);
        }
        presaleToken.approve(address(presale), depositAmount);
        presale.deposit();
        vm.stopPrank();
        assertEq(uint8(presale.state()), uint8(Presale.PresaleState.Active));
    }
}
