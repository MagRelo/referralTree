# Agent Instructions for Multi-Level Referral Reward System

This file contains instructions for AI agents working on the multi-level referral reward system codebase. Follow these guidelines to maintain code quality and consistency.

## Build and Test Commands

### Core Commands
```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with verbose output
forge test -vvv
```

### Running Specific Tests
```bash
# Run single test contract
forge test --match-contract ReferralGraphTest

# Run single test function
forge test --match-test testRegisterUser

# Run tests for specific file
forge test --match-path test/ReferralGraph.t.sol

# Run invariant tests only
forge test --match-contract "*Invariant*"

# Run fuzz tests only
forge test --match-test "testFuzz_*"
```

### Advanced Testing
```bash
# Run tests with coverage (requires forge coverage plugin)
forge coverage

# Run tests in parallel (if available)
forge test --threads 4

# Debug specific test
forge test --debug testRegisterUser

# Run tests with specific EVM version
forge test --evm-version cancun
```

### Deployment and Scripts
```bash
# Start local Anvil node
anvil

# Deploy contracts locally
forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast

# Verify deployment
forge verify-contract <address> src/core/ReferralGraph.sol:ReferralGraph --etherscan-api-key $ETHERSCAN_API_KEY
```

## Code Style Guidelines

### Solidity Style

#### File Structure
- Use `.sol` extension for all Solidity files
- Place contracts in `src/core/` directory
- Place interfaces in `src/interfaces/` directory
- Place tests in `test/` directory with `.t.sol` extension

#### Imports
```solidity
// Group imports by external libraries first, then local imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IReferralGraph} from "../interfaces/IReferralGraph.sol";

// Separate groups with blank lines
import {Test} from "forge-std/Test.sol";
```

#### Contract Structure
```solidity
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ContractName
 * @notice Brief description of contract purpose
 * @dev Detailed implementation notes
 */
contract ContractName is IInterface, Ownable {
    // State variables (private with public getters)
    mapping(address => uint256) private _balances;

    // Events
    event BalanceUpdated(address indexed user, uint256 newBalance);

    // Constructor
    constructor(address initialOwner) Ownable(initialOwner) {}

    // Public/external functions
    function updateBalance(address user, uint256 amount) external onlyOwner {
        _balances[user] = amount;
        emit BalanceUpdated(user, amount);
    }

    // View functions
    function balanceOf(address user) external view returns (uint256) {
        return _balances[user];
    }
}
```

#### Documentation
- Use comprehensive NatSpec comments for all public/external functions
- Include `@notice`, `@dev`, `@param`, and `@return` tags
- Document events and state variables
- Use `///` for single-line comments, `/** */` for multi-line

#### Naming Conventions
- **Contracts**: PascalCase (e.g., `ReferralGraph`, `RewardDistributor`)
- **Functions**: camelCase (e.g., `registerUser`, `getReferrer`)
- **Variables**: camelCase for local, _underscorePrefix for private state
- **Constants**: UPPER_SNAKE_CASE
- **Events**: PascalCase (e.g., `UserRegistered`, `RewardDistributed`)
- **Modifiers**: camelCase with underscore prefix if needed

#### Security Practices
- Use `private` for state variables with public getter functions
- Implement proper access controls with Ownable or custom modifiers
- Validate all inputs and handle edge cases
- Use SafeMath patterns (though unnecessary in Solidity 0.8+)
- Emit events for all state changes
- Use `require` with descriptive error messages

#### Error Handling
```solidity
require(amount > 0, "Amount must be greater than zero");
require(user != address(0), "Invalid user address");
require(isAuthorizedOracle(msg.sender), "Unauthorized oracle");
```

### Testing Patterns

#### Test Structure
```solidity
contract ContractTest is Test {
    Contract public contractUnderTest;
    address public owner = address(1);
    address public user = address(2);

    function setUp() public {
        vm.prank(owner);
        contractUnderTest = new Contract(owner);
    }

    function testFunctionName() public {
        // Arrange
        vm.prank(user);

        // Act
        contractUnderTest.someFunction();

        // Assert
        assertEq(result, expectedResult);
    }
}
```

#### Test Naming
- Use `test` prefix for unit tests
- Use `testFuzz_` prefix for fuzz tests
- Use descriptive names: `testCannotRegisterTwice`, `testOnlyOwnerCanConfigure`
- Use `Invariant` suffix for invariant test contracts

#### Fuzz Testing
```solidity
function testFuzz_RegisterWithRandomAddresses(
    address user,
    address referrer,
    bytes32 groupId
) public {
    // Filter invalid inputs
    vm.assume(user != address(0) && referrer != address(0));
    vm.assume(user != referrer);

    // Test logic
    vm.prank(oracle);
    referralGraph.register(user, referrer, groupId);

    assertEq(referralGraph.getReferrer(user, groupId), referrer);
}
```

#### Invariant Testing
```solidity
function invariant_NoCyclesInReferralTree() public {
    // Check that no user can be their own ancestor
    for (uint256 i = 0; i < registeredUsers[TEST_GROUP].length; i++) {
        address user = registeredUsers[TEST_GROUP][i];
        address[] memory ancestors = referralGraph.getAncestors(user, TEST_GROUP, 100);
        for (uint256 j = 0; j < ancestors.length; j++) {
            assertNotEq(ancestors[j], user, "Cycle detected in referral tree");
        }
    }
}
```

### Configuration Files

#### foundry.toml
- Use Solidity 0.8.26 with EVM version "cancun"
- Enable IR-based compilation (`via_ir = true`)
- Configure fuzzing: 256 runs, max 65536 test rejects
- Configure invariants: 256 runs, depth 15, no fail on revert
- Exclude test/certora/scripts directories from compilation

#### remappings.txt
```
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
forge-std/=lib/forge-std/src/
```

## Development Workflow

### When Adding New Features
1. Create/update interfaces first
2. Implement contract logic
3. Add comprehensive unit tests
4. Add fuzz tests for edge cases
5. Add invariant tests for structural properties
6. Update NatSpec documentation
7. Run full test suite: `forge test`

### When Fixing Bugs
1. Write failing test first (TDD approach)
2. Implement fix
3. Ensure all existing tests still pass
4. Add regression tests if needed

### Code Review Checklist
- [ ] All public functions have NatSpec documentation
- [ ] Proper access controls implemented
- [ ] Input validation on all external functions
- [ ] Events emitted for state changes
- [ ] Comprehensive test coverage
- [ ] Fuzz tests for complex logic
- [ ] Invariant tests for structural properties
- [ ] Gas optimization considerations
- [ ] Security best practices followed

## Common Patterns

### Oracle Authorization Pattern
```solidity
modifier onlyAuthorizedOracle() {
    require(isAuthorizedOracle(msg.sender), "Unauthorized oracle");
    _;
}

function authorizeOracle(address oracle) external onlyOwner {
    require(oracle != address(0), "Invalid oracle address");
    _authorizedOracles[oracle] = true;
    _authorizedOraclesList.push(oracle);
    emit OracleAuthorized(oracle);
}
```

### Referral Tree Traversal
```solidity
function getAncestors(address user, bytes32 groupId, uint256 maxLevels)
    external
    view
    returns (address[] memory)
{
    address[] memory ancestors = new address[](maxLevels);
    uint256 count = 0;
    address current = _referrers[groupId][user];

    while (current != address(0) && count < maxLevels) {
        ancestors[count] = current;
        current = _referrers[groupId][current];
        count++;
    }

    // Trim array to actual length
    assembly {
        mstore(ancestors, count)
    }

    return ancestors;
}
```

### Reward Distribution Logic
```solidity
function _calculateReward(uint256 totalAmount, uint256 level)
    internal
    view
    returns (uint256)
{
    if (level == 0) {
        return totalAmount * _originalUserPercentage / 10000;
    }

    uint256 reward = totalAmount * (10000 - _originalUserPercentage) / 10000;
    for (uint256 i = 0; i < level; i++) {
        reward = reward * _decayFactor / 10000;
        if (reward < _minReward) return 0;
    }
    return reward;
}
```

Follow these guidelines to maintain consistency and quality across the codebase.</content>
<parameter name="filePath">/Users/mattlovan/Projects/personal/qin/AGENTS.md