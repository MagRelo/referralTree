// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {ReferralGraph} from "../src/core/ReferralGraph.sol";
import {RewardCalculator} from "../src/core/RewardCalculator.sol";

/**
 * @title Deploy
 * @notice Deploy ReferralGraph and RewardCalculator
 * @dev Owner then `authorizeOracle` on the graph for each project.
 *
 * Env:
 *   OWNER             Deployer/owner (defaults to the broadcast sender)
 *   INITIAL_ORACLE    Optional oracle authorized at graph construction
 *   INITIAL_GROUP_ID  Group for INITIAL_ORACLE (bytes32 hex)
 */
contract Deploy is Script {
    function run() external returns (ReferralGraph graph, RewardCalculator calculator) {
        address owner = vm.envOr("OWNER", msg.sender);
        address initialOracle = vm.envOr("INITIAL_ORACLE", address(0));
        bytes32 initialGroupId = vm.envOr("INITIAL_GROUP_ID", bytes32(0));

        vm.startBroadcast();
        graph = new ReferralGraph(owner, initialOracle, initialGroupId);
        calculator = new RewardCalculator();
        vm.stopBroadcast();

        console.log("ReferralGraph", address(graph));
        console.log("RewardCalculator", address(calculator));
        console.log("owner", owner);
    }
}
