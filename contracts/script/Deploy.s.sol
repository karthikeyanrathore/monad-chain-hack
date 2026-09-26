// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {InferenceTruth} from "../src/InferenceTruth.sol";

/// Deploys InferenceTruth with the 1B and 2B model prices in a single transaction.
/// Required env: INFERENCE_SERVICE, VERIFIER (addresses).
/// Optional env (defaults in brackets): MIN_STAKE [0.1 MON], CHALLENGE_WINDOW [600 s],
/// PRICE_1B [0.001 MON], PRICE_2B [0.002 MON], VERIFIER_REWARD_BPS [1000], SLASH_BPS [5000].
contract Deploy is Script {
    function run() external returns (InferenceTruth it) {
        address service = vm.envAddress("INFERENCE_SERVICE");
        address verifier = vm.envAddress("VERIFIER");

        bytes32[] memory models = new bytes32[](2);
        uint256[] memory prices = new uint256[](2);
        (models[0], prices[0]) = (bytes32("1B"), vm.envOr("PRICE_1B", uint256(0.001 ether)));
        (models[1], prices[1]) = (bytes32("2B"), vm.envOr("PRICE_2B", uint256(0.002 ether)));

        vm.startBroadcast();
        it = new InferenceTruth(
            service,
            verifier,
            vm.envOr("MIN_STAKE", uint256(0.1 ether)),
            uint64(vm.envOr("CHALLENGE_WINDOW", uint256(600))),
            uint16(vm.envOr("VERIFIER_REWARD_BPS", uint256(1_000))),
            uint16(vm.envOr("SLASH_BPS", uint256(5_000))),
            models,
            prices
        );
        vm.stopBroadcast();

        console.log("InferenceTruth deployed at", address(it));
    }
}
