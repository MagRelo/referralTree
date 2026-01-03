// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ReferralGraph} from "../src/core/ReferralGraph.sol";
import {IReferralGraph} from "../src/interfaces/IReferralGraph.sol";

/**
 * @title ReferralGraphInvariantTest
 * @notice Invariant tests for ReferralGraph to ensure structural integrity
 */
contract ReferralGraphInvariantTest is Test {
    ReferralGraph public referralGraph;
    address public owner = address(1);
    address public root = address(2);
    address public oracle = address(7);
    
    // Track registered users for invariant checking
    mapping(bytes32 => address[]) private registeredUsers;
    mapping(bytes32 => mapping(address => address)) private userReferrers;
    
    bytes32 public constant TEST_GROUP = keccak256("invariant-test-group");

    function setUp() public {
        vm.prank(owner);
        referralGraph = new ReferralGraph(owner, address(0));

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle);
        
        // Target the referral graph contract for invariant testing
        targetContract(address(referralGraph));
        
        // Exclude owner-only functions from fuzzing
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("authorizeOracle(address)"));
        selectors[1] = bytes4(keccak256("unauthorizeOracle(address)"));

        excludeSelector(FuzzSelector({
            addr: address(referralGraph),
            selectors: selectors
        }));
    }

    /// @notice Helper function to register a user (called by fuzzer via targetContract)
    /// @dev This will be called by Foundry's invariant fuzzer
    function registerUser(address user, address referrer) public {
        // Filter invalid inputs
        if (user == address(0) || user == root) return;
        if (referrer == address(0)) referrer = root;
        if (user == referrer) return;
        
        // If referrer is not root, it must be registered first
        if (referrer != root) {
            bool referrerRegistered = referralGraph.isRegistered(referrer, TEST_GROUP);
            if (!referrerRegistered) return;
        }
        
        // Try to register
        vm.prank(oracle);
        try referralGraph.register(user, referrer, TEST_GROUP) {
            // Track successful registration
            if (!_isUserTracked(user)) {
                registeredUsers[TEST_GROUP].push(user);
            }
            userReferrers[TEST_GROUP][user] = referrer;
        } catch {
            // Registration failed, which is fine for fuzzing
        }
    }

    /// @notice Helper to check if user is tracked
    function _isUserTracked(address user) internal view returns (bool) {
        address[] memory users = registeredUsers[TEST_GROUP];
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) return true;
        }
        return false;
    }
    
    /// @notice Get all registered users for invariant checking
    function getRegisteredUsers() public view returns (address[] memory) {
        return registeredUsers[TEST_GROUP];
    }

    // ============ INVARIANTS ============

    /// @notice Invariant: No cycles can exist in the referral graph
    /// @dev A user can never be their own ancestor
    function invariant_NoCyclesInGraph() public view {
        address[] memory users = registeredUsers[TEST_GROUP];
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            address referrer = referralGraph.getReferrer(user, TEST_GROUP);
            
            // Traverse up the chain and ensure we never loop back to user
            address current = referrer;
            uint256 depth = 0;
            uint256 maxDepth = 100; // Safety limit
            
            while (current != address(0) && current != root && depth < maxDepth) {
                // If we encounter the user in the ancestor chain, we have a cycle
                assertTrue(current != user, "Cycle detected: user is their own ancestor");
                
                current = referralGraph.getReferrer(current, TEST_GROUP);
                depth++;
            }
        }
    }

    /// @notice Invariant: Referrer consistency - if A refers B, then B's referrer must be A
    function invariant_ReferrerConsistency() public view {
        address[] memory users = registeredUsers[TEST_GROUP];
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (!referralGraph.isRegistered(user, TEST_GROUP)) continue;
            
            address storedReferrer = referralGraph.getReferrer(user, TEST_GROUP);
            
            // If user has a referrer, verify consistency
            if (storedReferrer != address(0)) {
                // Check that stored referrer matches our tracking
                address trackedReferrer = userReferrers[TEST_GROUP][user];
                if (trackedReferrer != address(0)) {
                    assertEq(storedReferrer, trackedReferrer, "Referrer mismatch");
                }
                
                // Verify that if referrer is not root, it's registered
                if (storedReferrer != root) {
                    assertTrue(
                        referralGraph.isRegistered(storedReferrer, TEST_GROUP),
                        "Referrer must be registered"
                    );
                }
            }
        }
    }

    /// @notice Invariant: Children consistency - if A refers B, then B must be in A's children
    function invariant_ChildrenConsistency() public view {
        address[] memory users = registeredUsers[TEST_GROUP];
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (!referralGraph.isRegistered(user, TEST_GROUP)) continue;
            
            address referrer = referralGraph.getReferrer(user, TEST_GROUP);
            
            if (referrer != address(0)) {
                // User should be in referrer's children list
                address[] memory children = referralGraph.getChildren(referrer, TEST_GROUP);
                bool found = false;
                
                for (uint256 j = 0; j < children.length; j++) {
                    if (children[j] == user) {
                        found = true;
                        break;
                    }
                }
                
                assertTrue(found, "User not found in referrer's children");
            }
        }
    }

    /// @notice Invariant: No duplicate registrations - a user can only be registered once
    function invariant_NoDuplicateRegistrations() public view {
        address[] memory users = registeredUsers[TEST_GROUP];
        
        // Check for duplicates in our tracking
        for (uint256 i = 0; i < users.length; i++) {
            for (uint256 j = i + 1; j < users.length; j++) {
                assertTrue(users[i] != users[j], "Duplicate user in tracking");
            }
        }
        
        // Verify each tracked user is actually registered
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                assertTrue(
                    referralGraph.isRegistered(users[i], TEST_GROUP),
                    "Tracked user should be registered"
                );
            }
        }
    }

    /// @notice Invariant: Ancestors are consistent with referrer chain
    function invariant_AncestorsConsistency() public view {
        address[] memory users = registeredUsers[TEST_GROUP];
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            if (!referralGraph.isRegistered(user, TEST_GROUP)) continue;
            
            // Get ancestors
            address[] memory ancestors = referralGraph.getAncestors(user, TEST_GROUP, 100);
            
            // Verify ancestors match referrer chain
            address current = referralGraph.getReferrer(user, TEST_GROUP);
            uint256 ancestorIndex = 0;
            
            while (current != address(0) && current != root && ancestorIndex < ancestors.length) {
                assertEq(ancestors[ancestorIndex], current, "Ancestor mismatch");
                current = referralGraph.getReferrer(current, TEST_GROUP);
                ancestorIndex++;
            }
            
            // All ancestors should have been traversed
            assertEq(ancestorIndex, ancestors.length, "Ancestor count mismatch");
        }
    }
}

