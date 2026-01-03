// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {ReferralGraph} from "../src/core/ReferralGraph.sol";
import {IReferralGraph} from "../src/interfaces/IReferralGraph.sol";

contract ReferralGraphTest is Test {
    ReferralGraph public referralGraph;
    address public owner = address(1);
    address public root = address(2);
    address public oracle = address(7);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public user4 = address(6);

    bytes32 public testGroup = keccak256("test-group");

    function setUp() public {
        vm.prank(owner);
        referralGraph = new ReferralGraph(owner, address(0));

        // Authorize oracle for registration
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle);
        // Groups are auto-created on first registration - no setup needed
    }

    function testInitialSetup() public {
        assertEq(referralGraph.owner(), owner);
        assertEq(referralGraph.REFERRAL_ROOT(), address(0x0000000000000000000000000000000000000001));
    }

    function testGroupAutoCreated() public {
        // Group should not exist before first registration
        // Register first user with null referrer - group should be auto-created
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        // Verify user is registered (proving group exists)
        assertTrue(referralGraph.isRegistered(user1, testGroup));
        assertEq(referralGraph.getReferrer(user1, testGroup), 0x0000000000000000000000000000000000000001);
    }

    function testRegisterUser() public {
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        assertEq(referralGraph.getReferrer(user1, testGroup), 0x0000000000000000000000000000000000000001);
        assertTrue(referralGraph.isRegistered(user1, testGroup));
        assertEq(referralGraph.getChildren(0x0000000000000000000000000000000000000001, testGroup).length, 1);
        assertEq(referralGraph.getChildren(0x0000000000000000000000000000000000000001, testGroup)[0], user1);
    }

    function testRegisterUserWithReferrer() public {
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        assertEq(referralGraph.getReferrer(user2, testGroup), user1);
        assertEq(referralGraph.getChildren(user1, testGroup).length, 1);
        assertEq(referralGraph.getChildren(user1, testGroup)[0], user2);
    }

    function testGetAncestors() public {
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        vm.prank(oracle);
        referralGraph.register(user3, user2, testGroup);

        address[] memory ancestors = referralGraph.getAncestors(user3, testGroup, 5);
        assertEq(ancestors.length, 2);
        assertEq(ancestors[0], user2);
        assertEq(ancestors[1], user1);
    }

    function testCannotRegisterTwice() public {
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UserAlreadyRegistered.selector);
        referralGraph.register(user1, user2, testGroup);
    }

    function testCannotRegisterWithSelf() public {
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.SelfReferralNotAllowed.selector);
        referralGraph.register(user1, user1, testGroup);
    }

    function testCannotRegisterZeroUser() public {
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
        referralGraph.register(address(0), user1, testGroup);
    }

    function testCannotRegisterZeroReferrer() public {
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidReferrerAddress.selector);
        referralGraph.register(user1, address(0), testGroup);
    }

    function testReferrerMustBeInTree() public {
        // Try to register user2 with user1 as referrer, but user1 is not in the tree yet
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.ReferrerNotInTree.selector);
        referralGraph.register(user2, user1, testGroup);

        // Register user1 first
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        // Now user2 can register with user1 as referrer
        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);
        assertEq(referralGraph.getReferrer(user2, testGroup), user1);
    }

    function testCannotCreateCycle() public {
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);

        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        // Try to make user1 refer to user2 (creating a cycle)
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UserAlreadyRegistered.selector);
        referralGraph.register(user1, user2, testGroup);
    }

    function testUnlimitedTreeDepth() public {
        // Register chain of any depth - all should succeed
        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup); // depth 1

        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup); // depth 2

        vm.prank(oracle);
        referralGraph.register(user3, user2, testGroup); // depth 3

        vm.prank(oracle);
        referralGraph.register(user4, user3, testGroup); // depth 4

        // All registrations succeed - no depth limit
        assertTrue(referralGraph.isRegistered(user1, testGroup));
        assertTrue(referralGraph.isRegistered(user2, testGroup));
        assertTrue(referralGraph.isRegistered(user3, testGroup));
        assertTrue(referralGraph.isRegistered(user4, testGroup));
    }



    function testBatchRegister() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        vm.prank(oracle);
        vm.recordLogs();
        referralGraph.batchRegister(users, 0x0000000000000000000000000000000000000001, testGroup);

        // Check that UserRegistered events were emitted for each user
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3, "Should have 3 UserRegistered events");

        for (uint256 i = 0; i < entries.length; i++) {
            assertEq(entries[i].topics[0], keccak256("UserRegistered(address,address)"), "Event signature should match");
            assertEq(address(uint160(uint256(entries[i].topics[1]))), users[i], "Event should contain correct user");
            assertEq(address(uint160(uint256(entries[i].topics[2]))), address(0x0000000000000000000000000000000000000001), "Event should contain correct referrer");
        }

        assertEq(referralGraph.getReferrer(user1, testGroup), 0x0000000000000000000000000000000000000001);
        assertEq(referralGraph.getReferrer(user2, testGroup), 0x0000000000000000000000000000000000000001);
        assertEq(referralGraph.getReferrer(user3, testGroup), 0x0000000000000000000000000000000000000001);
        assertEq(referralGraph.getChildren(0x0000000000000000000000000000000000000001, testGroup).length, 3);
    }



    function testUnauthorizedCannotRegister() public {
        // Try to register without being an authorized oracle
        vm.prank(user1);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);
    }

    function testUnauthorizedCannotBatchRegister() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Try to batch register without being an authorized oracle
        vm.prank(user1);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.batchRegister(users, 0x0000000000000000000000000000000000000001, testGroup);
    }

    function testAuthorizeOracle() public {
        address newOracle = address(8);
        
        // Owner can authorize oracle
        vm.prank(owner);
        referralGraph.authorizeOracle(newOracle);
        
        assertTrue(referralGraph.isAuthorizedOracle(newOracle));
        
        // New oracle can now register
        vm.prank(newOracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);
        assertTrue(referralGraph.isRegistered(user1, testGroup));
    }

    function testUnauthorizeOracle() public {
        // Unauthorize the oracle
        vm.prank(owner);
        referralGraph.unauthorizeOracle(oracle);
        
        assertFalse(referralGraph.isAuthorizedOracle(oracle));
        
        // Oracle can no longer register
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.register(user1, root, testGroup);
    }

    function testGetAuthorizedOracles() public {
        address newOracle1 = address(8);
        address newOracle2 = address(9);
        
        vm.prank(owner);
        referralGraph.authorizeOracle(newOracle1);
        
        vm.prank(owner);
        referralGraph.authorizeOracle(newOracle2);
        
        address[] memory oracles = referralGraph.getAuthorizedOracles();
        assertEq(oracles.length, 3); // oracle + newOracle1 + newOracle2
        assertTrue(oracles.length >= 3);
    }

    function testOnlyOwnerCanAuthorizeOracle() public {
        address newOracle = address(8);
        
        vm.prank(user1);
        vm.expectRevert();
        referralGraph.authorizeOracle(newOracle);
    }

    function testOnlyOwnerCanUnauthorizeOracle() public {
        vm.prank(user1);
        vm.expectRevert();
        referralGraph.unauthorizeOracle(oracle);
    }

    function testConstructorWithInitialOracle() public {
        address initialOracle = address(10);

        vm.prank(owner);
        ReferralGraph newGraph = new ReferralGraph(owner, address(0));

        // Manually authorize the oracle
        vm.prank(owner);
        newGraph.authorizeOracle(initialOracle);

        assertTrue(newGraph.isAuthorizedOracle(initialOracle));

        // Initial oracle can register
        vm.prank(initialOracle);
        newGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);
        assertTrue(newGraph.isRegistered(user1, testGroup));
    }

    // ============ FUZZ TESTS ============

    /// @notice Fuzz test: Register user with random valid addresses
    function testFuzz_RegisterWithRandomAddresses(address user, address referrer, bytes32 groupId) public {
        // Filter out invalid addresses
        vm.assume(user != address(0));
        vm.assume(referrer != address(0));
        vm.assume(user != referrer);
        vm.assume(user != referralGraph.REFERRAL_ROOT());
        vm.assume(referrer != referralGraph.REFERRAL_ROOT());

        vm.startPrank(oracle);
        // First register the referrer with REFERRAL_ROOT
        referralGraph.register(referrer, referralGraph.REFERRAL_ROOT(), groupId);

        // Now register user with referrer
        referralGraph.register(user, referrer, groupId);
        vm.stopPrank();

        // Verify registration
        assertTrue(referralGraph.isRegistered(user, groupId));
        assertEq(referralGraph.getReferrer(user, groupId), referrer);


    }

    /// @notice Fuzz test: Batch register with random addresses
    function testFuzz_BatchRegisterRandomUsers(uint8 numUsers, bytes32 groupId) public {
        // Limit to reasonable number to avoid gas issues
        vm.assume(numUsers > 0 && numUsers <= 50);

        // Generate unique addresses
        address[] memory users = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            // Generate deterministic but unique addresses
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked(groupId, i)))));
            vm.assume(users[i] != address(0));
            vm.assume(users[i] != referralGraph.REFERRAL_ROOT());
        }

        vm.startPrank(oracle);
        // Register all users with REFERRAL_ROOT
        referralGraph.batchRegister(users, referralGraph.REFERRAL_ROOT(), groupId);
        vm.stopPrank();

        // Verify all users are registered
        for (uint256 i = 0; i < numUsers; i++) {
            assertTrue(referralGraph.isRegistered(users[i], groupId));
            assertEq(referralGraph.getReferrer(users[i], groupId), referralGraph.REFERRAL_ROOT());
        }

        // Verify REFERRAL_ROOT has all users as children
        address[] memory children = referralGraph.getChildren(referralGraph.REFERRAL_ROOT(), groupId);
        assertEq(children.length, numUsers);
    }

    /// @notice Fuzz test: Get ancestors with random depth
    function testFuzz_GetAncestorsRandomDepth(uint8 depth, bytes32 groupId) public {
        vm.assume(depth > 0 && depth <= 20);

        // Build a chain of the specified depth ending with REFERRAL_ROOT
        // Start with REFERRAL_ROOT as the root
        address[] memory chain = new address[](depth + 1);
        chain[0] = referralGraph.REFERRAL_ROOT();

        vm.startPrank(oracle);
        for (uint256 i = 1; i <= depth; i++) {
            chain[i] = address(uint160(uint256(keccak256(abi.encodePacked(groupId, i)))));
            vm.assume(chain[i] != address(0));
            vm.assume(chain[i] != referralGraph.REFERRAL_ROOT());

            // Register this user with previous user as referrer
            referralGraph.register(chain[i], chain[i - 1], groupId);
        }
        vm.stopPrank();

        // Get ancestors for the last user (should not include REFERRAL_ROOT)
        address[] memory ancestors = referralGraph.getAncestors(chain[depth], groupId, depth + 10);

        // Verify ancestors match expected chain (in reverse, excluding REFERRAL_ROOT)
        assertEq(ancestors.length, depth - 1);
        for (uint256 i = 0; i < ancestors.length; i++) {
            assertEq(ancestors[i], chain[depth - 1 - i]);
        }
    }

    /// @notice Fuzz test: Cannot register with invalid addresses
    function testFuzz_CannotRegisterWithInvalidAddresses(address user, address referrer, bytes32 groupId) public {
        // Test that zero user address is rejected
        if (user == address(0)) {
            vm.prank(oracle);
            vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
            referralGraph.register(user, referrer, groupId);
            return;
        }

        // Test that zero referrer address is rejected
        if (referrer == address(0)) {
            vm.prank(oracle);
            vm.expectRevert(IReferralGraph.InvalidReferrerAddress.selector);
            referralGraph.register(user, referrer, groupId);
            return;
        }
        
        // Test that self-referral is rejected
        if (user == referrer) {
            vm.prank(oracle);
            vm.expectRevert(IReferralGraph.SelfReferralNotAllowed.selector);
            referralGraph.register(user, referrer, groupId);
            return;
        }
    }
}
