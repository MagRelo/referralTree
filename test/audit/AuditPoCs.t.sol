// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {ReferralGraph} from "../../src/core/ReferralGraph.sol";
import {IReferralGraph} from "../../src/interfaces/IReferralGraph.sol";
import {RewardCalculator} from "../../src/core/RewardCalculator.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Fee-on-transfer token that takes 1% on every transfer
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_BPS = 100; // 1%

    constructor() ERC20("FeeToken", "FEE", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * FEE_BPS) / 10_000;
        uint256 netAmount = amount - fee;
        
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        
        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += netAmount;
            balanceOf[address(this)] += fee; // Fee goes to token contract
        }
        
        emit Transfer(from, to, netAmount);
        return true;
    }
}

/// @notice Token without any code at the address
contract TokenWithoutCode {
    // Used to test behavior when token has no code
}

/// @notice Simple mock ERC20 for testing
contract SimpleMockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MOCK", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title AuditPoCs
/// @notice Proof of Concept tests for security audit findings
contract AuditPoCs is Test {
    ReferralGraph public referralGraph;
    RewardCalculator public calculator;
    address public owner = address(1);
    uint256 internal constant ORACLE_PK = 0x0AC1E;
    address public oracle = vm.addr(ORACLE_PK);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    bytes32 public testGroup = keccak256("test-group");

    bytes32 internal constant REWARD_ROOTS_TYPEHASH = keccak256(
        "RewardRoots(bytes32 groupId,bytes32 rewardId,address user,address token,uint256 totalAmount,address payer,uint256 deadline)"
    );

    function setUp() public {
        vm.prank(owner);
        referralGraph = new ReferralGraph(owner, oracle, testGroup);
        calculator = new RewardCalculator();
        vm.prank(owner);
        referralGraph.setRewardCalculator(address(calculator));

        address root = referralGraph.REFERRAL_ROOT();
        vm.startPrank(oracle);
        referralGraph.register(user1, root, testGroup);
        referralGraph.register(user2, user1, testGroup);
        referralGraph.register(user3, user2, testGroup);
        vm.stopPrank();
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ReferralGraph")),
                keccak256("1"),
                block.chainid,
                address(referralGraph)
            )
        );
    }

    function _signRoots(
        uint256 pk,
        bytes32 groupId,
        bytes32 rewardId,
        address user,
        address token,
        uint256 amount,
        address payer,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(REWARD_ROOTS_TYPEHASH, groupId, rewardId, user, token, amount, payer, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice L-01: Fee-on-transfer tokens cause accounting discrepancy
    /// @dev The contract assumes full amount is transferred, but fee-on-transfer tokens
    ///      deliver less. This causes recipients to receive less than the event indicates.
    function testL01_FeeOnTransferTokensNotSupported() public {
        FeeOnTransferToken token = new FeeOnTransferToken();
        uint256 total = 1_000_000;
        uint256 expectedFee = (total * 100) / 10_000; // 1% fee on transfer
        
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRoots(ORACLE_PK, testGroup, bytes32("fot"), user3, address(token), total, oracle, deadline);
        
        uint256 user2BalBefore = token.balanceOf(user2);
        uint256 user1BalBefore = token.balanceOf(user1);
        
        vm.prank(oracle);
        referralGraph.rewardRoots(testGroup, bytes32("fot"), user3, address(token), total, deadline, oracle, sig);
        
        // Due to fee-on-transfer, each recipient gets less than expected
        // The event will show full amounts but actual balances are lower
        uint256 user2BalAfter = token.balanceOf(user2);
        uint256 user1BalAfter = token.balanceOf(user1);
        
        // Verify that actual received amounts are less than what was calculated
        uint256[] memory expectedAmounts = calculator.calculateRewards(total, 2);
        uint256 actualReceived = (user2BalAfter - user2BalBefore) + (user1BalAfter - user1BalBefore);
        uint256 expectedReceived = expectedAmounts[0] + expectedAmounts[1];
        
        // Actual received is less due to transfer fees
        assertTrue(actualReceived < expectedReceived, "Fee-on-transfer reduces actual received amount");
    }

    /// @notice I-01: Protocol fee can round to zero for small amounts
    /// @dev With 1 bps fee and amount < 10000, fee rounds to zero
    function testI01_ProtocolFeeRoundsToZeroForSmallAmounts() public {
        SimpleMockERC20 token = new SimpleMockERC20();
        address feeTo = address(0xFEE);
        
        vm.prank(owner);
        referralGraph.setProtocolFee(1, feeTo); // 0.01% fee
        
        uint256 total = 9999; // Amount too small for 1 bps to register
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRoots(ORACLE_PK, testGroup, bytes32("small"), user3, address(token), total, oracle, deadline);
        
        vm.prank(oracle);
        referralGraph.rewardRoots(testGroup, bytes32("small"), user3, address(token), total, deadline, oracle, sig);
        
        // Fee recipient gets nothing because fee rounds to 0
        assertEq(token.balanceOf(feeTo), 0, "Fee rounds to zero for small amounts");
    }

    /// @notice I-02: Verify token existence check
    /// @dev The contract does not verify that the token address has code before calling transferFrom
    function testI02_TokenWithoutCodeBehavior() public {
        address fakeToken = address(0xDEADBEEF);
        uint256 total = 1000;
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRoots(ORACLE_PK, testGroup, bytes32("nocode"), user3, fakeToken, total, oracle, deadline);
        
        // This will revert because transferFrom call to non-contract returns no data
        // SafeTransferLib will revert with "TRANSFER_FROM_FAILED"
        vm.prank(oracle);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        referralGraph.rewardRoots(testGroup, bytes32("nocode"), user3, fakeToken, total, deadline, oracle, sig);
    }

    /// @notice I-03: Deauthorized oracle signature becomes invalid
    /// @dev A valid signature from an oracle that is later deauthorized cannot be used
    function testI03_DeauthorizedOracleSignatureInvalid() public {
        SimpleMockERC20 token = new SimpleMockERC20();
        uint256 total = 1000;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRoots(ORACLE_PK, testGroup, bytes32("deauth"), user3, address(token), total, oracle, deadline);
        
        // Deauthorize oracle before submission
        vm.prank(owner);
        referralGraph.unauthorizeOracle(oracle, testGroup);
        
        // Now the signature is invalid
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        referralGraph.rewardRoots(testGroup, bytes32("deauth"), user3, address(token), total, deadline, oracle, sig);
    }

    /// @notice G-01: Unbounded loop in batchRegister
    /// @dev Large batches can consume excessive gas
    function testG01_BatchRegisterGasConsumption() public {
        bytes32 newGroup = keccak256("gas-test");
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, newGroup);
        
        address root = referralGraph.REFERRAL_ROOT();
        
        // Create a large batch
        uint256 batchSize = 100;
        address[] memory users = new address[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            users[i] = address(uint160(0x1000 + i));
        }
        
        uint256 gasBefore = gasleft();
        vm.prank(oracle);
        referralGraph.batchRegister(users, root, newGroup);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas used per registration
        emit log_named_uint("Gas used for 100 registrations", gasUsed);
        emit log_named_uint("Gas per registration", gasUsed / batchSize);
        
        // Verify all registered
        for (uint256 i = 0; i < batchSize; i++) {
            assertTrue(referralGraph.isRegistered(users[i], newGroup));
        }
    }

    /// @notice G-02: getChildren and getSkiplisted return unbounded arrays
    /// @dev For groups with many children, these view functions could run out of gas
    function testG02_UnboundedArrayReturns() public {
        bytes32 newGroup = keccak256("children-test");
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, newGroup);
        
        address root = referralGraph.REFERRAL_ROOT();
        
        // Register many children under root
        uint256 numChildren = 50;
        address[] memory children = new address[](numChildren);
        for (uint256 i = 0; i < numChildren; i++) {
            children[i] = address(uint160(0x2000 + i));
        }
        
        vm.prank(oracle);
        referralGraph.batchRegister(children, root, newGroup);
        
        // getChildren returns all children in one call
        uint256 gasBefore = gasleft();
        address[] memory returnedChildren = referralGraph.getChildren(root, newGroup);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertEq(returnedChildren.length, numChildren);
        emit log_named_uint("Gas to get 50 children", gasUsed);
    }

    /// @notice I-04: Owner can instantly change fee settings
    /// @dev No timelock or governance on protocol fee changes
    function testI04_InstantFeeChangeByOwner() public {
        // Owner can set fee to max instantly
        vm.prank(owner);
        referralGraph.setProtocolFee(1000, owner); // 10% fee
        
        assertEq(referralGraph.feeBps(), 1000);
        assertEq(referralGraph.feeRecipient(), owner);
        
        // Can also disable instantly
        vm.prank(owner);
        referralGraph.setProtocolFee(0, address(0));
        
        assertEq(referralGraph.feeBps(), 0);
    }

    /// @notice I-05: REFERRAL_ROOT is hardcoded and cannot receive rewards
    /// @dev By design, address(1) is never paid in reward distributions
    function testI05_ReferralRootNeverPaid() public {
        SimpleMockERC20 token = new SimpleMockERC20();
        address root = referralGraph.REFERRAL_ROOT();
        
        // Create a chain where user1 is directly under root
        uint256 total = 1000;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);
        
        // user1 is directly under root, so rewardRoots(user1) has empty chain
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRoots(ORACLE_PK, testGroup, bytes32("root"), user1, address(token), total, oracle, deadline);
        
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.EmptyPayoutChain.selector);
        referralGraph.rewardRoots(testGroup, bytes32("root"), user1, address(token), total, deadline, oracle, sig);
        
        // Root never receives anything
        assertEq(token.balanceOf(root), 0);
    }

    /// @notice M-01: Cross-chain replay protection verified
    /// @dev Signatures are bound to chainId via domain separator
    function testM01_CrossChainReplayProtection() public {
        SimpleMockERC20 token = new SimpleMockERC20();
        uint256 total = 1000;
        token.mint(oracle, total);
        vm.prank(oracle);
        token.approve(address(referralGraph), total);
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRoots(ORACLE_PK, testGroup, bytes32("chain"), user3, address(token), total, oracle, deadline);
        
        // Get current domain separator
        bytes32 originalDomain = referralGraph.DOMAIN_SEPARATOR();
        
        // Fork to different chain
        vm.chainId(block.chainid + 1);
        
        // Domain separator changes
        bytes32 newDomain = referralGraph.DOMAIN_SEPARATOR();
        assertTrue(originalDomain != newDomain, "Domain separator changes on chain fork");
        
        // Original signature is invalid on new chain
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.InvalidSigner.selector);
        referralGraph.rewardRoots(testGroup, bytes32("chain"), user3, address(token), total, deadline, oracle, sig);
    }

    /// @notice I-06: Verify RewardCalculator geometric weights
    /// @dev Confirm 0.6^k decay with rounding dust to position 0
    function testI06_GeometricWeightsCorrectness() public {
        uint256 total = 1_000_000;
        
        for (uint256 recipients = 1; recipients <= 10; recipients++) {
            uint256[] memory amounts = calculator.calculateRewards(total, recipients);
            
            // Sum must equal total
            uint256 sum = 0;
            for (uint256 i = 0; i < amounts.length; i++) {
                sum += amounts[i];
            }
            assertEq(sum, total, "Sum must equal total");
            
            // Verify geometric decay (each subsequent amount is ~60% of previous)
            if (recipients > 1) {
                // First position gets remainder, so check from position 1
                for (uint256 i = 2; i < amounts.length; i++) {
                    // amounts[i] should be approximately 0.6 * amounts[i-1]
                    // Allow 2% tolerance for rounding
                    uint256 expected = (amounts[i-1] * 6) / 10;
                    uint256 diff = amounts[i] > expected ? amounts[i] - expected : expected - amounts[i];
                    assertTrue(diff < (expected / 50) + 1, "Geometric decay within tolerance");
                }
            }
        }
    }

    /// @notice I-07: Verify referral cycle prevention
    /// @dev Cycles are prevented by requiring referrers to be already in tree
    function testI07_CyclePrevention() public {
        // Try to create a cycle by re-registering user1 under user3
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.UserAlreadyRegistered.selector);
        referralGraph.register(user1, user3, testGroup);
        
        // Self-referral is also blocked
        address newUser = address(100);
        vm.prank(oracle);
        vm.expectRevert(IReferralGraph.SelfReferralNotAllowed.selector);
        referralGraph.register(newUser, newUser, testGroup);
    }

    /// @notice I-08: Verify depth cap in payout
    /// @dev MAX_PAYOUT_LEVELS caps the payout chain at 10
    function testI08_DepthCapInPayout() public {
        bytes32 deepGroup = keccak256("deep-group");
        vm.prank(owner);
        referralGraph.authorizeOracle(oracle, deepGroup);
        
        address root = referralGraph.REFERRAL_ROOT();
        
        // Create a chain of 15 users
        address[] memory chain = new address[](15);
        chain[0] = address(0x3000);
        
        vm.prank(oracle);
        referralGraph.register(chain[0], root, deepGroup);
        
        for (uint256 i = 1; i < 15; i++) {
            chain[i] = address(uint160(0x3000 + i));
            vm.prank(oracle);
            referralGraph.register(chain[i], chain[i-1], deepGroup);
        }
        
        // Get payout ancestors for the deepest user - should be capped at 10
        address[] memory ancestors = referralGraph.getPayoutAncestors(chain[14], deepGroup, 10);
        assertEq(ancestors.length, 10, "Payout chain capped at MAX_PAYOUT_LEVELS");
        
        // Verify first ancestor is the immediate referrer
        assertEq(ancestors[0], chain[13]);
    }
}
