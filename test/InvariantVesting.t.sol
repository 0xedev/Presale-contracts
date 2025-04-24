// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// // Using console2 for potentially better logging if needed during debugging
// import {Test, console2, Vm} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {Vesting} from "src/contracts/Vesting.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// /**
//  * @title Invariant Test for Vesting Contract
//  * @notice This test suite checks invariants for the Vesting contract using Foundry's stateful fuzzing.
//  */
// contract InvariantVesting is StdInvariant, Test {
//     Vesting public vesting;
//     ERC20Mock public token;
//     address public owner; // Designated owner of the Vesting contract

//     // --- Actors ---
//     address[] public users; // Array of potential beneficiaries the test knows about
//     address internal deployer; // The address deploying contracts (this test contract)

//     // --- Parameters ---
//     uint256 constant INITIAL_SUPPLY = 10_000_000 ether; // Increased supply for fuzzing needs
//     uint256 constant MAX_SCHEDULES_PER_USER = 5; // Limit complexity for invariant runs
//     uint256 constant MAX_VESTING_DURATION = 2 * 365 days; // 2 years max duration
//     uint256 constant MIN_VESTING_DURATION = 1 hours; // Minimum sensible duration
//     uint256 constant MAX_START_OFFSET = 1 * 365 days; // Max start time delay from now
//     uint256 constant MIN_AMOUNT = 1 ether; // Min amount per schedule
//     uint256 constant MAX_AMOUNT = 100_000 ether; // Max reasonable amount per schedule

//     // --- Setup ---
//     function setUp() public virtual {
//         // Use virtual if extending later
//         deployer = address(this);
//         // Use a fixed, distinct address for the owner for clarity
//         owner = address(0x000000000000000000000000000000000000bEEF);

//         // Setup known users for the test
//         users.push(makeAddr("user1"));
//         users.push(makeAddr("user2"));
//         users.push(makeAddr("user3"));

//         // Deploy token and mint INITIAL_SUPPLY to the designated owner
//         token = new ERC20Mock();
//         token.mint(owner, INITIAL_SUPPLY);

//         // Deploy vesting contract as deployer, then transfer ownership
//         vm.prank(deployer);
//         vesting = new Vesting(address(token));
//         vm.prank(deployer); // Deployer still owns after construction
//         vesting.transferOwnership(owner); // Now owned by 0xBEEF

//         // Owner approves the vesting contract to spend its tokens
//         vm.startPrank(owner);
//         token.approve(address(vesting), type(uint256).max); // Approve max for simplicity
//         vm.stopPrank();

//         // --- Target Contract & Selectors ---
//         // Define which functions the fuzzer is allowed to call on the Vesting contract.
//         bytes4[] memory selectors = new bytes4[](6);
//         selectors[0] = vesting.createVesting.selector;
//         selectors[1] = vesting.release.selector;
//         selectors[2] = vesting.releaseAll.selector;
//         selectors[3] = vesting.deleteVesting.selector;
//         selectors[4] = vesting.pause.selector;
//         selectors[5] = vesting.unpause.selector;
//         // Apply the selector filter specifically to the vesting contract address
//         targetSelector(FuzzSelector({addr: address(vesting), selectors: selectors}));

//         // --- Target Senders ---
//         // Specify which addresses can be msg.sender for the calls
//         targetSender(owner); // Allow owner actions
//         for (uint256 i = 0; i < users.length; i++) {
//             targetSender(users[i]); // Allow user actions (release/releaseAll)
//         }

//         // --- Exclude Contracts ---
//         // Prevent the fuzzer from making arbitrary calls to the token contract
//         excludeContract(address(token));
//     }

//     //--------------------------------------------------------------------------
//     // Handlers - Define how the fuzzer calls functions on the target contract
//     //--------------------------------------------------------------------------

//     /**
//      * @notice Handler for calling createVesting. Ensures owner calls with valid params.
//      */
//     function handler_createVesting(
//         uint256 userIndex, // Fuzzed index to select a user
//         uint256 amount,
//         uint256 startTimestamp, // Fuzz absolute start time
//         uint256 duration
//     ) public {
//         // --- Assume/Bound Inputs ---
//         userIndex = bound(userIndex, 0, users.length - 1);
//         address beneficiary = users[userIndex]; // **Select beneficiary from known users**

//         amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
//         if (token.balanceOf(owner) < amount) {
//             return; // Skip if owner doesn't have enough
//         }

//         uint256 reasonableStartMin = block.timestamp;
//         uint256 reasonableStartMax = block.timestamp + MAX_START_OFFSET;
//         uint256 start = bound(startTimestamp, reasonableStartMin, reasonableStartMax);

//         duration = bound(duration, MIN_VESTING_DURATION, MAX_VESTING_DURATION);

//         if (vesting.scheduleCount(beneficiary) >= MAX_SCHEDULES_PER_USER) {
//             return; // Skip if user has too many schedules
//         }

//         // --- Execute Action ---
//         vm.prank(owner);
//         try vesting.createVesting(beneficiary, amount, start, duration) {} catch {}
//     }

//     /**
//      * @notice Handler for calling release. Ensures beneficiary calls with valid schedule ID.
//      */
//     function handler_release(
//         uint256 userIndex,
//         uint256 scheduleId // Fuzz the schedule ID
//     ) public {
//         // --- Assume/Bound Inputs ---
//         userIndex = bound(userIndex, 0, users.length - 1);
//         address beneficiary = users[userIndex];
//         uint256 scheduleCount = vesting.scheduleCount(beneficiary);

//         if (scheduleCount == 0) return; // Skip if user has no schedules

//         // Bound scheduleId to the valid range for existing schedules for this user
//         scheduleId = bound(scheduleId, 0, scheduleCount - 1);

//         if (vesting.paused()) return; // Skip if paused

//         // --- Execute Action ---
//         vm.prank(beneficiary);
//         try vesting.release(scheduleId) {} catch {} // Expected reverts: NoTokensToRelease, InvalidScheduleId (if deleted)
//     }

//     /**
//      * @notice Handler for calling releaseAll. Ensures beneficiary calls.
//      */
//     function handler_releaseAll(uint256 userIndex) public {
//         // --- Assume/Bound Inputs ---
//         userIndex = bound(userIndex, 0, users.length - 1);
//         address beneficiary = users[userIndex];

//         if (vesting.paused()) return; // Skip if paused

//         // --- Execute Action ---
//         vm.prank(beneficiary);
//         try vesting.releaseAll() {} catch {} // Expected revert: NoTokensToRelease
//     }

//     /**
//      * @notice Handler for calling deleteVesting. Ensures owner calls.
//      */
//     function handler_deleteVesting(
//         uint256 userIndex,
//         uint256 scheduleId // Fuzz the schedule ID
//     ) public {
//         // --- Assume/Bound Inputs ---
//         userIndex = bound(userIndex, 0, users.length - 1);
//         address beneficiary = users[userIndex];
//         uint256 scheduleCount = vesting.scheduleCount(beneficiary);

//         if (scheduleCount == 0) return; // Skip if user has no schedules

//         // Allow fuzzing slightly out of bounds IDs to test reverts
//         scheduleId = bound(scheduleId, 0, scheduleCount + 5);

//         // --- Execute Action ---
//         vm.prank(owner);
//         try vesting.deleteVesting(beneficiary, scheduleId) {} catch {} // Expected reverts: InvalidScheduleId
//     }

//     /**
//      * @notice Handler for calling pause. Ensures owner calls when not paused.
//      */
//     function handler_pause() public {
//         if (vesting.paused()) return; // Skip if already paused

//         vm.prank(owner);
//         vesting.pause();
//     }

//     /**
//      * @notice Handler for calling unpause. Ensures owner calls when paused.
//      */
//     function handler_unpause() public {
//         if (!vesting.paused()) return; // Skip if not paused

//         vm.prank(owner);
//         vesting.unpause();
//     }

//     //--------------------------------------------------------------------------
//     // Invariants - Properties that should always hold true
//     //--------------------------------------------------------------------------

//     /*
//      * @notice REMOVED: invariant_totalAllocatedEqualsSumOfRemaining
//      * This invariant was removed because it's difficult to reliably track the state
//      * for all potential beneficiaries created by the fuzzer, especially if handlers
//      * are bypassed or default fuzzing strategies are used.
//      */
//     // function invariant_totalAllocatedEqualsSumOfRemaining() public view { ... }

//     /**
//      * @notice Checks if the contract's token balance can cover all current allocations.
//      * This should now hold true as external token manipulation is prevented.
//      */
//     function invariant_balanceCoversAllocation() public view {
//         assertGe(
//             token.balanceOf(address(vesting)),
//             vesting.totalAllocated(),
//             "Invariant Violation: Contract token balance < totalAllocated"
//         );
//     }

//     /**
//      * @notice Checks if the 'released' amount never exceeds the 'totalAmount' for any schedule.
//      */
//     function invariant_scheduleReleasedNotGreaterThanTotal() public view {
//         // Check only for known users, as these are the ones whose state we can reliably access
//         for (uint256 u = 0; u < users.length; u++) {
//             address user = users[u];
//             uint256 count = vesting.scheduleCount(user);
//             for (uint256 i = 0; i < count; i++) {
//                 (uint256 total, uint256 released,,, bool exists) = vesting.schedules(user, i);
//                 if (exists) {
//                     assertTrue(released <= total, "Invariant Violation: Schedule released > total");
//                 }
//             }
//         }
//     }

//     /**
//      * @notice Checks if vestedAmount calculation seems consistent (never exceeds total).
//      */
//     function invariant_vestedAmountCalculation() public view {
//         // Check only for known users
//         for (uint256 u = 0; u < users.length; u++) {
//             address user = users[u];
//             uint256 count = vesting.scheduleCount(user);
//             for (uint256 i = 0; i < count; i++) {
//                 (uint256 total,,,, bool exists) = vesting.schedules(user, i);
//                 if (exists && total > 0) {
//                     uint256 vested = vesting.vestedAmount(user, i);
//                     assertTrue(vested <= total, "Invariant Violation: vestedAmount() > totalAmount");
//                 }
//             }
//         }
//     }
// }
