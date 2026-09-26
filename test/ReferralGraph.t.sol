// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {ReferralGraph} from "../src/core/ReferralGraph.sol";
import {IReferralGraph} from "../src/interfaces/IReferralGraph.sol";
import {RewardCalculator} from "../src/core/RewardCalculator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

/// Worthless token whose transferFrom is a no-op returning true (used by the tx.origin regression test).
contract NoopToken {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

/// Contract an oracle EOA might touch (prize payout callback, phishing dapp). Under the old tx.origin auth it could settle.
contract OriginAttacker {
    IReferralGraph internal immutable graph;
    bytes32 internal immutable groupId;
    bytes32 internal immutable settlementId;
    address internal immutable user;

    constructor(IReferralGraph _graph, bytes32 _groupId, bytes32 _settlementId, address _user) {
        graph = _graph;
        groupId = _groupId;
        settlementId = _settlementId;
        user = _user;
    }

    receive() external payable {
        // No oracle signature available; any garbage signature must be rejected.
        graph.settle(
            groupId, settlementId, user, address(new NoopToken()), 1e30, type(uint256).max, tx.origin, new bytes(65)
        );
    }
}

contract ReferralGraphTest is Test {
    ReferralGraph public referralGraph;
    address public owner = address(1);
    address public root = address(2);
    uint256 internal constant ORACLE_PK = 0x0AC1E;
    address public oracle = vm.addr(ORACLE_PK);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public user4 = address(6);

    bytes32 public testGroup = keccak256("test-group");

    function setUp() public {
        vm.prank(owner);
        referralGraph = new ReferralGraph(owner, address(0), bytes32(0));

        // Authorize oracle for registration in test group
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, testGroup);
        // Groups are auto-created on first registration - no setup needed
    }

    function testInitialSetup() public {
        assertEq(referralGraph.owner(), owner);
        assertEq(referralGraph.REFERRAL_ROOT(), address(0x0000000000000000000000000000000000000001));
        assertEq(referralGraph.feeBps(), 0);
        assertEq(referralGraph.feeRecipient(), address(0));
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

    function testCannotRegisterReferralRootAsUser() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
        referralGraph.register(referralRoot, user1, testGroup);
    }

    function testOracleCanSetSkiplisted() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);
        vm.prank(oracle);
        referralGraph.register(user3, user2, testGroup);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user2, testGroup, true);

        assertTrue(referralGraph.isSkiplisted(user2, testGroup));
        address[] memory skiplisted = referralGraph.getSkiplisted(testGroup);
        assertEq(skiplisted.length, 1);
        assertEq(skiplisted[0], user2);

        address[] memory raw = referralGraph.getAncestors(user3, testGroup, 5);
        assertEq(raw.length, 2);
        assertEq(raw[0], user2);
        assertEq(raw[1], user1);

        address[] memory payoutAncestors = referralGraph.getPayoutAncestors(user3, testGroup, 5);
        assertEq(payoutAncestors.length, 1);
        assertEq(payoutAncestors[0], user1);

        address[] memory payoutChain = referralGraph.getPayoutChain(user3, testGroup, 10);
        assertEq(payoutChain.length, 2);
        assertEq(payoutChain[0], user3);
        assertEq(payoutChain[1], user1);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user2, testGroup, false);
        assertFalse(referralGraph.isSkiplisted(user2, testGroup));
        assertEq(referralGraph.getSkiplisted(testGroup).length, 0);
    }

    function testSkiplistedSeedOmittedFromPayoutChain() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user2, testGroup, true);

        address[] memory payoutChain = referralGraph.getPayoutChain(user2, testGroup, 10);
        assertEq(payoutChain.length, 1);
        assertEq(payoutChain[0], user1);
    }

    function testUnauthorizedCannotSetSkiplisted() public {
        vm.prank(user1);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.setSkiplisted(user2, testGroup, true);
    }

    function testCannotSkiplistZeroOrRoot() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
        referralGraph.setSkiplisted(address(0), testGroup, true);

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
        referralGraph.setSkiplisted(referralRoot, testGroup, true);
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
            assertEq(
                entries[i].topics[0], keccak256("UserRegistered(bytes32,address,address)"), "Event signature should match"
            );
            assertEq(entries[i].topics[1], testGroup, "Event should contain correct groupId");
            assertEq(address(uint160(uint256(entries[i].topics[2]))), users[i], "Event should contain correct user");
            assertEq(
                address(uint160(uint256(entries[i].topics[3]))),
                address(0x0000000000000000000000000000000000000001),
                "Event should contain correct referrer"
            );
        }

        assertEq(referralGraph.getReferrer(user1, testGroup), 0x0000000000000000000000000000000000000001);
        assertEq(referralGraph.getReferrer(user2, testGroup), 0x0000000000000000000000000000000000000001);
        assertEq(referralGraph.getReferrer(user3, testGroup), 0x0000000000000000000000000000000000000001);
        assertEq(referralGraph.getChildren(0x0000000000000000000000000000000000000001, testGroup).length, 3);
    }



    function testUserRegisteredIncludesGroupIdAndDoesNotCollide() public {
        bytes32 otherGroup = keccak256("other-group");
        address referralRoot = referralGraph.REFERRAL_ROOT();

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, otherGroup);

        vm.recordLogs();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, otherGroup);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);

        bytes32 topic0 = keccak256("UserRegistered(bytes32,address,address)");
        assertEq(entries[0].topics[0], topic0);
        assertEq(entries[0].topics[1], testGroup);
        assertEq(address(uint160(uint256(entries[0].topics[2]))), user1);
        assertEq(address(uint160(uint256(entries[0].topics[3]))), referralRoot);
        assertEq(entries[0].data, bytes(""), "all fields are indexed");

        assertEq(entries[1].topics[0], topic0);
        assertEq(entries[1].topics[1], otherGroup);
        assertEq(address(uint160(uint256(entries[1].topics[2]))), user1);
        assertEq(address(uint160(uint256(entries[1].topics[3]))), referralRoot);
        assertTrue(entries[0].topics[1] != entries[1].topics[1], "groupIds must not collide");
    }

    function testRegisteredCountIncrementsOnRegisterAndBatch() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();
        assertEq(referralGraph.registeredCount(testGroup), 0);

        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 1);

        address[] memory users = new address[](2);
        users[0] = user2;
        users[1] = user3;
        vm.prank(oracle);
        referralGraph.batchRegister(users, user1, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 3);
    }

    function testRegisteredCountDoesNotIncrementOnRevert() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();

        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 1);

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UserAlreadyRegistered.selector);
        referralGraph.register(user1, referralRoot, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 1);

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.SelfReferralNotAllowed.selector);
        referralGraph.register(user2, user2, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 1);

        address[] memory users = new address[](2);
        users[0] = user2;
        users[1] = user1;
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UserAlreadyRegistered.selector);
        referralGraph.batchRegister(users, referralRoot, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 1);
    }

    function testRegisteredCountIsPerGroupAndExcludesRoot() public {
        bytes32 otherGroup = keccak256("other-group");
        address referralRoot = referralGraph.REFERRAL_ROOT();

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, otherGroup);

        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, otherGroup);

        assertEq(referralGraph.registeredCount(testGroup), 1);
        assertEq(referralGraph.registeredCount(otherGroup), 1);

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
        referralGraph.register(referralRoot, user1, testGroup);
        assertEq(referralGraph.registeredCount(testGroup), 1);
    }

    function testSkiplistedCountTracksAddAndRemove() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        vm.prank(oracle);
        referralGraph.register(user2, user1, testGroup);

        assertEq(referralGraph.skiplistedCount(testGroup), 0);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user1, testGroup, true);
        assertEq(referralGraph.skiplistedCount(testGroup), 1);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user2, testGroup, true);
        assertEq(referralGraph.skiplistedCount(testGroup), 2);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user1, testGroup, true);
        assertEq(referralGraph.skiplistedCount(testGroup), 2, "re-skiplist is a no-op");

        vm.prank(oracle);
        referralGraph.setSkiplisted(user1, testGroup, false);
        assertEq(referralGraph.skiplistedCount(testGroup), 1);

        vm.prank(oracle);
        referralGraph.setSkiplisted(user3, testGroup, false);
        assertEq(referralGraph.skiplistedCount(testGroup), 1, "unskiplist of a non-listed address is a no-op");

        vm.prank(oracle);
        referralGraph.setSkiplisted(user2, testGroup, false);
        assertEq(referralGraph.skiplistedCount(testGroup), 0);
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
        referralGraph.authorizeOracle(newOracle, testGroup);
        
        assertTrue(referralGraph.isAuthorizedOracle(newOracle, testGroup));
        
        // New oracle can now register
        vm.prank(newOracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, testGroup);
        assertTrue(referralGraph.isRegistered(user1, testGroup));
    }

    function testUnauthorizeOracle() public {
        // Unauthorize the oracle
        vm.prank(owner);
        referralGraph.unauthorizeOracle(oracle, testGroup);
        
        assertFalse(referralGraph.isAuthorizedOracle(oracle, testGroup));
        
        // Oracle can no longer register
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.register(user1, root, testGroup);
    }

    function testGetAuthorizedOracles() public {
        address newOracle1 = address(8);
        address newOracle2 = address(9);
        
        vm.prank(owner);
        referralGraph.authorizeOracle(newOracle1, testGroup);
        
        vm.prank(owner);
        referralGraph.authorizeOracle(newOracle2, testGroup);
        
        address[] memory oracles = referralGraph.getAuthorizedOracles(testGroup);
        assertEq(oracles.length, 3); // oracle + newOracle1 + newOracle2
        assertTrue(oracles.length >= 3);
    }

    function testOnlyOwnerCanAuthorizeOracle() public {
        address newOracle = address(8);
        
        vm.prank(user1);
        vm.expectRevert();
        referralGraph.authorizeOracle(newOracle, testGroup);
    }

    function testOnlyOwnerCanUnauthorizeOracle() public {
        vm.prank(user1);
        vm.expectRevert();
        referralGraph.unauthorizeOracle(oracle, testGroup);
    }

    function testOracleNotAuthorizedForOtherGroup() public {
        bytes32 otherGroup = keccak256("other-group");

        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, otherGroup);

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, otherGroup);

        vm.prank(oracle);
        referralGraph.register(user1, 0x0000000000000000000000000000000000000001, otherGroup);
        assertTrue(referralGraph.isRegistered(user1, otherGroup));
    }

    function testConstructorWithInitialOracle() public {
        address initialOracle = address(10);

        vm.prank(owner);
        ReferralGraph newGraph = new ReferralGraph(owner, initialOracle, testGroup);

        assertTrue(newGraph.isAuthorizedOracle(initialOracle, testGroup));

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

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, groupId);

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

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, groupId);

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

        for (uint256 i = 1; i <= depth; i++) {
            chain[i] = address(uint160(uint256(keccak256(abi.encodePacked(groupId, i)))));
            vm.assume(chain[i] != address(0));
            vm.assume(chain[i] != referralGraph.REFERRAL_ROOT());
        }

        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, groupId);

        vm.startPrank(oracle);
        for (uint256 i = 1; i <= depth; i++) {
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
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, groupId);

        // Test that zero user address is rejected
        if (user == address(0)) {
            vm.prank(oracle);
            vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
            referralGraph.register(user, referrer, groupId);
            return;
        }

        // Test that REFERRAL_ROOT as user is rejected
        if (user == referralGraph.REFERRAL_ROOT()) {
            vm.prank(oracle);
            vm.expectRevert(IReferralGraph.InvalidUserAddress.selector);
            referralGraph.register(user, referrer == address(0) ? address(1) : referrer, groupId);
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

    /*//////////////////////////////////////////////////////////////
                        EIP-712 SETTLE HELPERS
    //////////////////////////////////////////////////////////////*/

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    bytes32 internal constant SETTLE_TYPEHASH = keccak256(
        "Settle(bytes32 groupId,bytes32 settlementId,address user,address token,uint256 totalAmount,address payer,uint256 deadline)"
    );

    /// @dev Independent re-implementation of the EIP-712 domain separator (spec check against the contract).
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ReferralGraph")),
                keccak256("1"),
                vm.getChainId(),
                address(referralGraph)
            )
        );
    }

    function _sign(
        uint256 pk,
        bytes32 groupId,
        bytes32 settlementId,
        address user,
        address token,
        uint256 amount,
        address payer,
        uint256 deadline
    ) internal view returns (Sig memory sig) {
        bytes32 structHash = keccak256(
            abi.encode(SETTLE_TYPEHASH, groupId, settlementId, user, token, amount, payer, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (sig.v, sig.r, sig.s) = vm.sign(pk, digest);
    }

    function _packed(Sig memory sig) internal pure returns (bytes memory) {
        return abi.encodePacked(sig.r, sig.s, sig.v);
    }

    /// @dev Submit an ECDSA signature claiming the default EOA `oracle` as signer.
    function _submit(
        address payer,
        bytes32 groupId,
        bytes32 settlementId,
        address user,
        address token,
        uint256 amount,
        uint256 deadline,
        Sig memory sig
    ) internal {
        _submitAs(payer, groupId, settlementId, user, token, amount, deadline, oracle, _packed(sig));
    }

    function _submitAs(
        address payer,
        bytes32 groupId,
        bytes32 settlementId,
        address user,
        address token,
        uint256 amount,
        uint256 deadline,
        address signer,
        bytes memory signature
    ) internal {
        vm.prank(payer);
        referralGraph.settle(groupId, settlementId, user, token, amount, deadline, signer, signature);
    }

    /// @dev Oracle signs for `payer`, `payer` submits.
    function _settleSigned(
        address payer,
        bytes32 groupId,
        bytes32 settlementId,
        address user,
        address token,
        uint256 amount
    ) internal {
        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, groupId, settlementId, user, token, amount, payer, deadline);
        _submit(payer, groupId, settlementId, user, token, amount, deadline, sig);
    }

    function testSettlePaysPayoutChain() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address referralRoot = referralGraph.REFERRAL_ROOT();

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));

        vm.startPrank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        referralGraph.register(user2, user1, testGroup);
        referralGraph.register(user3, user2, testGroup);
        vm.stopPrank();

        uint256 total = 1_000_000;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);

        address[] memory chain = referralGraph.getPayoutChain(user3, testGroup, 10);
        uint256[] memory amounts = calculator.calculateRewards(total, chain.length);
        bytes32 settlementId = keccak256("contest-1");

        vm.expectEmit(true, true, true, true, address(referralGraph));
        emit IReferralGraph.ReferralSettlement(testGroup, settlementId, user3, address(token), total, chain, amounts);

        _settleSigned(oracle, testGroup, settlementId, user3, address(token), total);

        assertEq(token.balanceOf(oracle), 0);
        uint256 paid;
        for (uint256 i = 0; i < chain.length; i++) {
            assertEq(token.balanceOf(chain[i]), amounts[i]);
            paid += amounts[i];
        }
        assertEq(paid, total);
        assertEq(token.balanceOf(address(referralGraph)), 0);
    }

    function testSettleRejectsNonOracleSigner() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(0xBAD, testGroup, bytes32("id"), user1, address(token), 1, user2, deadline);
        // Claiming its own (unauthorized) address
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(user2, testGroup, bytes32("id"), user1, address(token), 1, deadline, vm.addr(0xBAD), _packed(sig));
        // Claiming the authorized oracle's address
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(user2, testGroup, bytes32("id"), user1, address(token), 1, deadline, sig);
    }

    function testSettleValidSignatureFromArbitraryCaller() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address payer = address(0xBEEF);
        uint256 total = 1000;

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        token.mint(payer, total);
        vm.prank(payer);
        token.approve(address(referralGraph), total);

        assertFalse(referralGraph.isAuthorizedOracle(payer, testGroup));
        _settleSigned(payer, testGroup, bytes32("relayed"), user1, address(token), total);

        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(user1), total);
    }

    function testRegisterIgnoresAuthorizedOrigin() public {
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.expectRevert(IReferralGraph.UnauthorizedOracle.selector);
        vm.prank(user1, oracle);
        referralGraph.register(user2, referralRoot, testGroup);
    }

    function testSettleRejectsReplay() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        uint256 total = 1000;

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        token.mint(oracle, total * 2);
        vm.prank(oracle);
        token.approve(address(referralGraph), total * 2);

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("id"), user1, address(token), total, oracle, deadline);
        _submit(oracle, testGroup, bytes32("id"), user1, address(token), total, deadline, sig);

        // Same signature replayed
        vm.expectRevert(IReferralGraph.SettlementAlreadyUsed.selector);
        _submit(oracle, testGroup, bytes32("id"), user1, address(token), total, deadline, sig);

        // Fresh, valid signature for the same settlementId (different amount) is also rejected
        Sig memory sig2 = _sign(ORACLE_PK, testGroup, bytes32("id"), user1, address(token), total - 1, oracle, deadline);
        vm.expectRevert(IReferralGraph.SettlementAlreadyUsed.selector);
        _submit(oracle, testGroup, bytes32("id"), user1, address(token), total - 1, deadline, sig2);
    }

    function testSettleRejectsEmptyChain() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.startPrank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        referralGraph.setSkiplisted(user1, testGroup, true);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("id"), user1, address(token), 1000, oracle, deadline);
        vm.expectRevert(IReferralGraph.EmptyPayoutChain.selector);
        _submit(oracle, testGroup, bytes32("id"), user1, address(token), 1000, deadline, sig);
    }

    function testSettleOmitsSkiplisted() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address referralRoot = referralGraph.REFERRAL_ROOT();

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        vm.startPrank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        referralGraph.register(user2, user1, testGroup);
        referralGraph.register(user3, user2, testGroup);
        referralGraph.setSkiplisted(user2, testGroup, true);
        vm.stopPrank();

        uint256 total = 10_000;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);
        _settleSigned(oracle, testGroup, bytes32("id"), user3, address(token), total);

        assertEq(token.balanceOf(user2), 0);
        assertGt(token.balanceOf(user3), 0);
        assertGt(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user1) + token.balanceOf(user3), total);
    }

    function testOnlyOwnerCanSetProtocolFee() public {
        vm.prank(user1);
        vm.expectRevert("UNAUTHORIZED");
        referralGraph.setProtocolFee(100, user1);
    }

    function testSetProtocolFeeRejectsAboveMaxFeeBps() public {
        assertEq(referralGraph.MAX_FEE_BPS(), 1_000);

        vm.prank(owner);
        vm.expectRevert(IReferralGraph.FeeTooHigh.selector);
        referralGraph.setProtocolFee(1_001, user1);

        vm.prank(owner);
        vm.expectRevert(IReferralGraph.FeeTooHigh.selector);
        referralGraph.setProtocolFee(10_000, user1);

        vm.prank(owner);
        referralGraph.setProtocolFee(1_000, user1);
        assertEq(referralGraph.feeBps(), 1_000);
    }

    function testSetProtocolFeeRequiresRecipientWhenNonZero() public {
        vm.prank(owner);
        vm.expectRevert(IReferralGraph.InvalidFeeRecipient.selector);
        referralGraph.setProtocolFee(1, address(0));
    }

    function testSetProtocolFeeZeroAllowsZeroRecipient() public {
        vm.prank(owner);
        referralGraph.setProtocolFee(100, user1);
        assertEq(referralGraph.feeBps(), 100);
        assertEq(referralGraph.feeRecipient(), user1);

        vm.prank(owner);
        referralGraph.setProtocolFee(0, address(0));
        assertEq(referralGraph.feeBps(), 0);
        assertEq(referralGraph.feeRecipient(), address(0));
    }

    function testSettleDeductsProtocolFeeFromTotal() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address feeTo = address(9);
        uint16 feeBps = 250; // 2.5%
        uint256 total = 1_000_000;
        uint256 protocolFee = (total * feeBps) / 10_000;
        uint256 distributable = total - protocolFee;

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        vm.prank(owner);
        referralGraph.setProtocolFee(feeBps, feeTo);

        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        // Caller pays exactly `total` — fee comes out of that pot, not an extra pull.
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);

        bytes32 settlementId = keccak256("fee-1");
        address[] memory chain = referralGraph.getPayoutChain(user1, testGroup, 10);
        uint256[] memory amounts = calculator.calculateRewards(distributable, chain.length);

        vm.expectEmit(true, true, true, true, address(referralGraph));
        emit IReferralGraph.ProtocolFeeCharged(testGroup, settlementId, address(token), feeTo, protocolFee);
        vm.expectEmit(true, true, true, true, address(referralGraph));
        emit IReferralGraph.ReferralSettlement(
            testGroup, settlementId, user1, address(token), distributable, chain, amounts
        );

        _settleSigned(oracle, testGroup, settlementId, user1, address(token), total);

        assertEq(token.balanceOf(user1), distributable);
        assertEq(token.balanceOf(feeTo), protocolFee);
        assertEq(token.balanceOf(oracle), 0);
        assertEq(token.balanceOf(address(referralGraph)), 0);
    }

    function testSettleDoesNotChargeWhenFeeRoundsToZero() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address feeTo = address(9);

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        vm.prank(owner);
        referralGraph.setProtocolFee(1, feeTo);

        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        uint256 total = 1;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);

        _settleSigned(oracle, testGroup, bytes32("dust"), user1, address(token), total);

        assertEq(token.balanceOf(user1), total);
        assertEq(token.balanceOf(feeTo), 0);
        assertEq(token.balanceOf(address(referralGraph)), 0);
    }

    function testSettleSucceedsWithApprovalEqualToTotalWhenFeeSet() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address feeTo = address(9);
        uint256 total = 10_000;
        uint256 protocolFee = (total * 100) / 10_000;
        uint256 distributable = total - protocolFee;

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        vm.prank(owner);
        referralGraph.setProtocolFee(100, feeTo);

        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);

        _settleSigned(oracle, testGroup, bytes32("id"), user1, address(token), total);

        assertEq(token.balanceOf(user1), distributable);
        assertEq(token.balanceOf(feeTo), protocolFee);
        assertEq(token.balanceOf(oracle), 0);
    }

    function testSettleRevertsWhenApprovalLessThanTotalWithFee() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);
        address feeTo = address(9);
        uint256 total = 10_000;

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        vm.prank(owner);
        referralGraph.setProtocolFee(100, feeTo);

        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total - 1);

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("id"), user1, address(token), total, oracle, deadline);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        _submit(oracle, testGroup, bytes32("id"), user1, address(token), total, deadline, sig);
    }

    function testSettleUsesZeroFeeAfterFeeDisabled() public {
        RewardCalculator calculator = new RewardCalculator();
        MockERC20 token = new MockERC20("USD", "USD", 6);

        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));
        vm.prank(owner);
        referralGraph.setProtocolFee(500, address(9));
        vm.prank(owner);
        referralGraph.setProtocolFee(0, address(0));

        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.prank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);

        uint256 total = 1000;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);

        _settleSigned(oracle, testGroup, bytes32("id"), user1, address(token), total);

        assertEq(token.balanceOf(user1), total);
        assertEq(token.balanceOf(address(9)), 0);
        assertEq(token.balanceOf(oracle), 0);
    }
    /*//////////////////////////////////////////////////////////////
                    EIP-712 SIGNED SETTLE TESTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant SIG_TOTAL = 1_000_000;

    /// @dev Calculator + chain user3 -> user2 -> user1 -> root; `payer` funded and approved for `SIG_TOTAL`.
    function _fixture(address payer) internal returns (MockERC20 token) {
        RewardCalculator calculator = new RewardCalculator();
        token = new MockERC20("USD", "USD", 6);
        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));

        address referralRoot = referralGraph.REFERRAL_ROOT();
        vm.startPrank(oracle);
        referralGraph.register(user1, referralRoot, testGroup);
        referralGraph.register(user2, user1, testGroup);
        referralGraph.register(user3, user2, testGroup);
        vm.stopPrank();

        token.mint(payer, SIG_TOTAL);
        vm.prank(payer);
        token.approve(address(referralGraph), SIG_TOTAL);
    }

    function testDomainSeparatorAndTypehashMatchSpec() public view {
        assertEq(referralGraph.DOMAIN_SEPARATOR(), _domainSeparator());
        assertEq(referralGraph.SETTLE_TYPEHASH(), SETTLE_TYPEHASH);
    }

    function testSettleSignatureAcceptedAtExactDeadline() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        uint256 deadline = block.timestamp;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("edge"), user3, address(token), SIG_TOTAL, payer, deadline);
        _submit(payer, testGroup, bytes32("edge"), user3, address(token), SIG_TOTAL, deadline, sig);
        assertEq(token.balanceOf(payer), 0);
    }

    function testSettleRevertsWhenDeadlineExpired() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("late"), user3, address(token), SIG_TOTAL, payer, deadline);

        vm.warp(deadline + 1);
        vm.expectRevert(IReferralGraph.SignatureExpired.selector);
        _submit(payer, testGroup, bytes32("late"), user3, address(token), SIG_TOTAL, deadline, sig);
    }

    function testSettleRevertsForOracleOfDifferentGroup() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        (address otherOracle, uint256 otherPk) = makeAddrAndKey("otherGroupOracle");
        vm.prank(owner);
        referralGraph.authorizeOracle(otherOracle, keccak256("other-group"));

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(otherPk, testGroup, bytes32("x"), user3, address(token), SIG_TOTAL, payer, deadline);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("x"), user3, address(token), SIG_TOTAL, deadline, otherOracle, _packed(sig));
    }

    function testSettleRevertsAfterSignerUnauthorized() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("x"), user3, address(token), SIG_TOTAL, payer, deadline);

        vm.prank(owner);
        referralGraph.unauthorizeOracle(oracle, testGroup);

        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, bytes32("x"), user3, address(token), SIG_TOTAL, deadline, sig);
    }

    function testSettleRevertsOnTamperedPayload() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        MockERC20 otherToken = new MockERC20("X", "X", 6);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 id = bytes32("signed");
        Sig memory sig = _sign(ORACLE_PK, testGroup, id, user3, address(token), SIG_TOTAL, payer, deadline);

        // user
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, id, user2, address(token), SIG_TOTAL, deadline, sig);
        // token
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, id, user3, address(otherToken), SIG_TOTAL, deadline, sig);
        // amount
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, id, user3, address(token), SIG_TOTAL - 1, deadline, sig);
        // deadline
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, id, user3, address(token), SIG_TOTAL, deadline + 1, sig);
        // settlementId
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, bytes32("other"), user3, address(token), SIG_TOTAL, deadline, sig);
        // groupId (oracle is also authorized there, so only the signature binds it)
        bytes32 groupB = keccak256("group-b");
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, groupB);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, groupB, id, user3, address(token), SIG_TOTAL, deadline, sig);

        // untampered still works
        _submit(payer, testGroup, id, user3, address(token), SIG_TOTAL, deadline, sig);
        assertEq(token.balanceOf(payer), 0);
    }

    function testSettleSignatureBoundToPayer() public {
        address app = address(0xA99);
        address frontRunner = address(0xF00);
        MockERC20 token = _fixture(app);
        token.mint(frontRunner, SIG_TOTAL);
        vm.prank(frontRunner);
        token.approve(address(referralGraph), SIG_TOTAL);

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("bound"), user3, address(token), SIG_TOTAL, app, deadline);

        // Copying the signature from the mempool and submitting it from another account fails.
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(frontRunner, testGroup, bytes32("bound"), user3, address(token), SIG_TOTAL, deadline, sig);

        _submit(app, testGroup, bytes32("bound"), user3, address(token), SIG_TOTAL, deadline, sig);
        assertEq(token.balanceOf(app), 0);
        assertEq(token.balanceOf(frontRunner), SIG_TOTAL);
    }

    function testDomainSeparatorRecomputedOnChainFork() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        bytes32 original = referralGraph.DOMAIN_SEPARATOR();
        uint256 deadline = block.timestamp + 1 hours;
        Sig memory oldChainSig =
            _sign(ORACLE_PK, testGroup, bytes32("fork"), user3, address(token), SIG_TOTAL, payer, deadline);

        vm.chainId(vm.getChainId() + 1);
        bytes32 forked = referralGraph.DOMAIN_SEPARATOR();
        assertTrue(forked != original);
        assertEq(forked, _domainSeparator());

        // Signature made for the original chain does not verify on the fork
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, bytes32("fork"), user3, address(token), SIG_TOTAL, deadline, oldChainSig);

        // Signature made for the new chain id does
        Sig memory newChainSig =
            _sign(ORACLE_PK, testGroup, bytes32("fork"), user3, address(token), SIG_TOTAL, payer, deadline);
        _submit(payer, testGroup, bytes32("fork"), user3, address(token), SIG_TOTAL, deadline, newChainSig);
        assertEq(token.balanceOf(payer), 0);
    }

    function testSettleRevertsOnInvalidSignatureZeroRecovery() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        uint256 deadline = block.timestamp + 1 hours;

        // r = s = 0 and an invalid v both make ecrecover return address(0)
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, bytes32("z"), user3, address(token), SIG_TOTAL, deadline, Sig(27, 0, 0));

        Sig memory good = _sign(ORACLE_PK, testGroup, bytes32("z"), user3, address(token), SIG_TOTAL, payer, deadline);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submit(payer, testGroup, bytes32("z"), user3, address(token), SIG_TOTAL, deadline, Sig(0, good.r, good.s));
    }

    /// @dev Documents the solmate-matching choice: high-s twins recover the same signer, but the
    ///      settlementId nonce means a malleated signature can never replay a settlement.
    function testMalleatedSignatureCannotReplay() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        token.mint(payer, SIG_TOTAL);
        vm.prank(payer);
        token.approve(address(referralGraph), SIG_TOTAL * 2);

        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig = _sign(ORACLE_PK, testGroup, bytes32("m"), user3, address(token), SIG_TOTAL, payer, deadline);
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        Sig memory twin = Sig(sig.v == 27 ? 28 : 27, sig.r, bytes32(n - uint256(sig.s)));

        _submit(payer, testGroup, bytes32("m"), user3, address(token), SIG_TOTAL, deadline, sig);
        vm.expectRevert(IReferralGraph.SettlementAlreadyUsed.selector);
        _submit(payer, testGroup, bytes32("m"), user3, address(token), SIG_TOTAL, deadline, twin);
        assertEq(token.balanceOf(payer), SIG_TOTAL);
    }

    /// @dev Regression for audit H-1: a contract reached during an oracle-originated tx can no longer settle.
    function testTxOriginAttackNoLongerWorks() public {
        MockERC20 token = _fixture(oracle);
        bytes32 contestId = keccak256(abi.encode(uint256(42)));
        OriginAttacker attacker = new OriginAttacker(referralGraph, testGroup, contestId, user3);
        vm.deal(oracle, 1 ether);

        // Oracle EOA pays a "winner" contract; its receive() tries to settle as the oracle via tx.origin.
        vm.prank(oracle, oracle);
        (bool ok, bytes memory ret) = address(attacker).call{value: 1 wei}("");
        assertFalse(ok);
        assertEq(bytes4(ret), IReferralGraph.InvalidSigner.selector);

        // Direct call with tx.origin == oracle and no valid signature is rejected too.
        NoopToken junk = new NoopToken();
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        vm.prank(address(attacker), oracle);
        referralGraph.settle(testGroup, contestId, user3, address(junk), 1e30, type(uint256).max, oracle, new bytes(65));

        // The canonical settlementId is still available for the real payout.
        _settleSigned(oracle, testGroup, contestId, user3, address(token), SIG_TOTAL);
        assertEq(token.balanceOf(oracle), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    ERC-1271 / SIGNATURE FORMAT TESTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant WALLET_OWNER_PK = 0x5AFE;

    /// @dev ERC-1271 wallet (owned by WALLET_OWNER_PK) authorized as an oracle for testGroup.
    function _walletOracle() internal returns (MockERC1271Wallet wallet) {
        wallet = new MockERC1271Wallet(vm.addr(WALLET_OWNER_PK));
        vm.prank(owner);
        referralGraph.authorizeOracle(address(wallet), testGroup);
    }

    function testContractOracleValidSignatureSettles() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        MockERC1271Wallet wallet = _walletOracle();
        uint256 deadline = block.timestamp + 1 hours;
        Sig memory sig =
            _sign(WALLET_OWNER_PK, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, payer, deadline);

        _submitAs(
            payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), _packed(sig)
        );
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(user1) + token.balanceOf(user2) + token.balanceOf(user3), SIG_TOTAL);
    }

    function testContractOracleMisbehaviourRevertsInvalidSigner() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        MockERC1271Wallet wallet = _walletOracle();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig =
            _packed(_sign(WALLET_OWNER_PK, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, payer, deadline));

        MockERC1271Wallet.Mode[5] memory modes = [
            MockERC1271Wallet.Mode.WrongMagic,
            MockERC1271Wallet.Mode.DirtyMagic,
            MockERC1271Wallet.Mode.Revert,
            MockERC1271Wallet.Mode.Empty,
            MockERC1271Wallet.Mode.Short
        ];
        for (uint256 i = 0; i < modes.length; i++) {
            wallet.setMode(modes[i]);
            vm.expectRevert(IReferralGraph.InvalidSigner.selector);
            _submitAs(payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig);
        }

        // Same signature still works once the wallet behaves
        wallet.setMode(MockERC1271Wallet.Mode.Valid);
        _submitAs(payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig);
        assertEq(token.balanceOf(payer), 0);
    }

    function testContractOracleGasBurnRevertsInvalidSigner() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        MockERC1271Wallet wallet = _walletOracle();
        wallet.setMode(MockERC1271Wallet.Mode.GasBurn);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig =
            _packed(_sign(WALLET_OWNER_PK, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, payer, deadline));

        // The 1/64 gas retained after the burned staticcall is enough to revert cleanly.
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        vm.prank(payer);
        referralGraph.settle{gas: 5_000_000}(
            testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig
        );
    }

    function testContractNotAuthorizedAsOracleReverts() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        MockERC1271Wallet wallet = new MockERC1271Wallet(vm.addr(WALLET_OWNER_PK)); // valid wallet, not authorized
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig =
            _packed(_sign(WALLET_OWNER_PK, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, payer, deadline));

        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig);

        // Authorizing the wallet does not authorize its owner key as an EOA oracle either
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(
            payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, vm.addr(WALLET_OWNER_PK), sig
        );
    }

    function testContractOracleRejectsSignatureForDifferentPayload() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        MockERC1271Wallet wallet = _walletOracle();
        uint256 deadline = block.timestamp + 1 hours;
        // Wallet owner approved a settle of SIG_TOTAL / 2 for user2 ...
        bytes memory sig = _packed(
            _sign(WALLET_OWNER_PK, testGroup, bytes32("w"), user2, address(token), SIG_TOTAL / 2, payer, deadline)
        );

        // ... which cannot be used for a different payload (the graph asks the wallet about a different digest)
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig);
        // ... nor by a different payer
        address other = address(0xF00);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(other, testGroup, bytes32("w"), user2, address(token), SIG_TOTAL / 2, deadline, address(wallet), sig);
    }

    function testContractOracleReplayBlocked() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        token.mint(payer, SIG_TOTAL);
        vm.prank(payer);
        token.approve(address(referralGraph), SIG_TOTAL * 2);
        MockERC1271Wallet wallet = _walletOracle();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig =
            _packed(_sign(WALLET_OWNER_PK, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, payer, deadline));

        _submitAs(payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig);
        vm.expectRevert(IReferralGraph.SettlementAlreadyUsed.selector);
        _submitAs(payer, testGroup, bytes32("w"), user3, address(token), SIG_TOTAL, deadline, address(wallet), sig);
    }

    function testEoaOracleRejectsWrongLengthSignature() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig =
            _packed(_sign(ORACLE_PK, testGroup, bytes32("l"), user3, address(token), SIG_TOTAL, payer, deadline));

        bytes memory tooLong = abi.encodePacked(sig, uint8(0));
        bytes memory tooShort = new bytes(63);
        for (uint256 i = 0; i < 63; i++) {
            tooShort[i] = sig[i];
        }

        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("l"), user3, address(token), SIG_TOTAL, deadline, oracle, tooLong);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("l"), user3, address(token), SIG_TOTAL, deadline, oracle, tooShort);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("l"), user3, address(token), SIG_TOTAL, deadline, oracle, "");
    }

    function testEoaSignatureClaimingDifferentOracleReverts() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        (address oracle2, uint256 oracle2Pk) = makeAddrAndKey("oracle2");
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle2, testGroup);
        uint256 deadline = block.timestamp + 1 hours;
        // oracle2 signs but the submission claims the other authorized oracle
        bytes memory sig =
            _packed(_sign(oracle2Pk, testGroup, bytes32("c"), user3, address(token), SIG_TOTAL, payer, deadline));

        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        _submitAs(payer, testGroup, bytes32("c"), user3, address(token), SIG_TOTAL, deadline, oracle, sig);

        _submitAs(payer, testGroup, bytes32("c"), user3, address(token), SIG_TOTAL, deadline, oracle2, sig);
        assertEq(token.balanceOf(payer), 0);
    }

    function testEoaOracleAcceptsEip2098CompactSignature() public {
        address payer = address(0xBEEF);
        MockERC20 token = _fixture(payer);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(SETTLE_TYPEHASH, testGroup, bytes32("k"), user3, address(token), SIG_TOTAL, payer, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (bytes32 r, bytes32 vs) = vm.signCompact(ORACLE_PK, digest);

        _submitAs(
            payer, testGroup, bytes32("k"), user3, address(token), SIG_TOTAL, deadline, oracle, abi.encodePacked(r, vs)
        );
        assertEq(token.balanceOf(payer), 0);
    }
}
