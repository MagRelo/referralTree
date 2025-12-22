// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
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
        referralGraph = new ReferralGraph(owner, root, false, address(0));
        
        // Authorize oracle for registration
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle);
        // Groups are auto-created on first registration - no setup needed
    }

    function testInitialSetup() public {
        assertEq(referralGraph.owner(), owner);
        assertEq(referralGraph.getRoot(), root);
        bool allowlistEnabled = referralGraph.isAllowlistEnabled();
        assertEq(allowlistEnabled, false);
    }

    function testGroupAutoCreated() public {
        // Group should not exist before first registration
        // Register first user - group should be auto-created
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

        // Verify user is registered (proving group exists)
        assertTrue(referralGraph.isRegistered(user1, testGroup));
        assertEq(referralGraph.getReferrer(user1, testGroup), root);
    }

    function testRegisterUser() public {
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

        assertEq(referralGraph.getReferrer(user1, testGroup), root);
        assertTrue(referralGraph.isRegistered(user1, testGroup));
        assertEq(referralGraph.getChildren(root, testGroup).length, 1);
        assertEq(referralGraph.getChildren(root, testGroup)[0], user1);
    }

    function testRegisterUserWithReferrer() public {
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        assertEq(referralGraph.getReferrer(user2, testGroup), user1);
        assertEq(referralGraph.getChildren(user1, testGroup).length, 1);
        assertEq(referralGraph.getChildren(user1, testGroup)[0], user2);
    }

    function testGetAncestors() public {
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

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
        referralGraph.register(user1, root, testGroup);

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.AlreadyRegistered.selector);
        referralGraph.register(user1, user2, testGroup);
    }

    function testCannotRegisterWithSelf() public {
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidReferrer.selector);
        referralGraph.register(user1, user1, testGroup);
    }

    function testReferrerMustBeInTree() public {
        // Try to register user2 with user1 as referrer, but user1 is not in the tree yet
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidReferrer.selector);
        referralGraph.register(user2, user1, testGroup);

        // Register user1 first
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

        // Now user2 can register with user1 as referrer
        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);
        assertEq(referralGraph.getReferrer(user2, testGroup), user1);
    }

    function testCannotCreateCycle() public {
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        // Try to make user1 refer to user2 (creating a cycle)
        vm.prank(oracle);
        vm.expectRevert(); // Just expect any revert
        referralGraph.register(user1, user2, testGroup);
    }

    function testUnlimitedTreeDepth() public {
        // Register chain of any depth - all should succeed
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup); // depth 1

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

    function testAllowlistFunctionality() public {
        // Enable allowlist
        vm.prank(owner);
        referralGraph.setAllowlistEnabled(true);

        // Add user1 as allowed referrer
        vm.prank(owner);
        referralGraph.allowReferrer(user1);

        // Register user1 with root first (so user1 is in the referral tree)
        vm.prank(oracle);
        referralGraph.register(user1, root, testGroup);

        // Register user2 with user1 (should work)
        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        // Try to register user3 with user2 (should fail, user2 not allowed)
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.ReferrerNotAllowed.selector);
        referralGraph.register(user3, user2, testGroup);
    }

    function testBatchRegister() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        vm.prank(oracle);
        referralGraph.batchRegister(users, root, testGroup);

        assertEq(referralGraph.getReferrer(user1, testGroup), root);
        assertEq(referralGraph.getReferrer(user2, testGroup), root);
        assertEq(referralGraph.getReferrer(user3, testGroup), root);
        assertEq(referralGraph.getChildren(root, testGroup).length, 3);
    }

    function testOnlyOwnerCanConfigure() public {
        vm.prank(user1);
        vm.expectRevert();
        referralGraph.setAllowlistEnabled(true);

        vm.prank(user1);
        vm.expectRevert();
        referralGraph.allowReferrer(user2);
    }

    function testUnauthorizedCannotRegister() public {
        // Try to register without being an authorized oracle
        vm.prank(user1);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.register(user1, root, testGroup);
    }

    function testUnauthorizedCannotBatchRegister() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        // Try to batch register without being an authorized oracle
        vm.prank(user1);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.batchRegister(users, root, testGroup);
    }

    function testAuthorizeOracle() public {
        address newOracle = address(8);
        
        // Owner can authorize oracle
        vm.prank(owner);
        referralGraph.authorizeOracle(newOracle);
        
        assertTrue(referralGraph.isAuthorizedOracle(newOracle));
        
        // New oracle can now register
        vm.prank(newOracle);
        referralGraph.register(user1, root, testGroup);
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
        ReferralGraph newGraph = new ReferralGraph(owner, root, false, initialOracle);
        
        assertTrue(newGraph.isAuthorizedOracle(initialOracle));
        
        // Initial oracle can register
        vm.prank(initialOracle);
        newGraph.register(user1, root, testGroup);
        assertTrue(newGraph.isRegistered(user1, testGroup));
    }
}
