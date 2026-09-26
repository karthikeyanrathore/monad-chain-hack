// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {InferenceTruth} from "../src/InferenceTruth.sol";

contract InferenceTruthTest is Test {
    InferenceTruth it;

    address owner = address(this);
    address service = makeAddr("inferenceService");
    address verifier = makeAddr("verifier");
    address user = makeAddr("user");
    address machine1 = makeAddr("machine1");
    address machine2 = makeAddr("machine2");

    bytes32 constant M1B = bytes32("1B");
    bytes32 constant M3B = bytes32("3B");
    uint256 constant PRICE_1B = 0.01 ether;
    uint256 constant PRICE_3B = 0.02 ether;
    uint256 constant MIN_STAKE = 1 ether;
    uint64 constant WINDOW = 1 hours;
    bytes32 constant REQ = keccak256("req-1");
    bytes32 constant ANSWER = keccak256("answer");

    function setUp() public {
        bytes32[] memory models = new bytes32[](2);
        uint256[] memory prices = new uint256[](2);
        (models[0], prices[0]) = (M1B, PRICE_1B);
        (models[1], prices[1]) = (M3B, PRICE_3B);
        it = new InferenceTruth(service, verifier, MIN_STAKE, WINDOW, 1_000, 5_000, models, prices);

        vm.deal(user, 10 ether);
        vm.deal(machine1, 10 ether);
        vm.deal(machine2, 10 ether);

        vm.prank(user);
        it.deposit{value: 1 ether}();
        vm.prank(machine1);
        it.stake{value: 2 ether}(M1B);
        vm.prank(machine2);
        it.stake{value: 2 ether}(M3B);
    }

    function _record(bytes32 id, address provider, bytes32 model) internal {
        vm.prank(service);
        it.recordRequest(id, user, provider, model, ANSWER);
    }

    function _status(bytes32 id) internal view returns (InferenceTruth.Status s) {
        (,,,,, s,) = it.requests(id);
    }

    // ---------------------------------------------------------------- deposits

    function test_DepositAndWithdraw() public {
        uint256 before = user.balance;
        vm.prank(user);
        it.withdraw(0.4 ether);
        assertEq(it.balances(user), 0.6 ether);
        assertEq(user.balance, before + 0.4 ether);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        vm.prank(user);
        vm.expectRevert(InferenceTruth.InsufficientBalance.selector);
        it.withdraw(2 ether);
    }

    // ---------------------------------------------------------------- recordRequest

    function test_RecordRequestLocksPrice() public {
        _record(REQ, machine1, M1B);
        assertEq(it.balances(user), 1 ether - PRICE_1B);
        assertEq(it.pendingCount(machine1), 1);
        assertEq(uint8(_status(REQ)), uint8(InferenceTruth.Status.Pending));
    }

    function test_RevertWhen_NotInferenceService() public {
        vm.prank(user);
        vm.expectRevert(InferenceTruth.NotInferenceService.selector);
        it.recordRequest(REQ, user, machine1, M1B, ANSWER);
    }

    function test_RevertWhen_UserBalanceTooLow() public {
        address poor = makeAddr("poor");
        vm.prank(service);
        vm.expectRevert(InferenceTruth.InsufficientBalance.selector);
        it.recordRequest(REQ, poor, machine1, M1B, ANSWER);
    }

    function test_RevertWhen_ProviderServesOtherModel() public {
        vm.prank(service);
        vm.expectRevert(InferenceTruth.ProviderNotEligible.selector);
        it.recordRequest(REQ, user, machine1, M3B, ANSWER);
    }

    function test_RevertWhen_ProviderNotStaked() public {
        address unstaked = makeAddr("unstaked");
        vm.prank(service);
        vm.expectRevert(InferenceTruth.ProviderNotEligible.selector);
        it.recordRequest(REQ, user, unstaked, M1B, ANSWER);
    }

    function test_RevertWhen_RequestIdReused() public {
        _record(REQ, machine1, M1B);
        vm.prank(service);
        vm.expectRevert(InferenceTruth.RequestExists.selector);
        it.recordRequest(REQ, user, machine1, M1B, ANSWER);
    }

    // ---------------------------------------------------------------- verdicts

    function test_PassPaysProviderAndVerifierWalletsDirectly() public {
        _record(REQ, machine2, M3B);
        uint256 providerBefore = machine2.balance;
        uint256 verifierBefore = verifier.balance;
        vm.prank(verifier);
        it.submitVerdict(REQ, true);

        uint256 reward = PRICE_3B / 10;
        assertEq(machine2.balance, providerBefore + PRICE_3B - reward);
        assertEq(verifier.balance, verifierBefore + reward);
        assertEq(it.balances(machine2), 0);
        assertEq(it.balances(verifier), 0);
        assertEq(it.stakes(machine2), 2 ether);
        assertEq(it.pendingCount(machine2), 0);
        assertEq(uint8(_status(REQ)), uint8(InferenceTruth.Status.Passed));
    }

    function test_FailSlashesProviderAndRefundsUser() public {
        _record(REQ, machine2, M3B);
        vm.prank(verifier);
        it.submitVerdict(REQ, false);

        assertEq(it.balances(user), 1 ether);
        assertEq(it.stakes(machine2), 1 ether);
        assertEq(it.balances(owner), 1 ether);
        assertEq(it.balances(machine2), 0);
        assertEq(uint8(_status(REQ)), uint8(InferenceTruth.Status.Failed));
    }

    function test_RevertWhen_NotVerifier() public {
        _record(REQ, machine1, M1B);
        vm.prank(service);
        vm.expectRevert(InferenceTruth.NotVerifier.selector);
        it.submitVerdict(REQ, true);
    }

    function test_RevertWhen_VerdictSubmittedTwice() public {
        _record(REQ, machine1, M1B);
        vm.startPrank(verifier);
        it.submitVerdict(REQ, true);
        vm.expectRevert(InferenceTruth.NotPending.selector);
        it.submitVerdict(REQ, false);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- settle

    function test_SettleAfterWindowPaysFullPrice() public {
        _record(REQ, machine1, M1B);
        vm.expectRevert(InferenceTruth.WindowOpen.selector);
        it.settle(REQ);

        uint256 before = machine1.balance;
        vm.warp(block.timestamp + WINDOW);
        it.settle(REQ);
        assertEq(machine1.balance, before + PRICE_1B);
        assertEq(it.balances(machine1), 0);
        assertEq(uint8(_status(REQ)), uint8(InferenceTruth.Status.Settled));
    }

    function test_RevertWhen_VerdictAfterSettle() public {
        _record(REQ, machine1, M1B);
        vm.warp(block.timestamp + WINDOW);
        it.settle(REQ);
        vm.prank(verifier);
        vm.expectRevert(InferenceTruth.NotPending.selector);
        it.submitVerdict(REQ, false);
    }

    // ---------------------------------------------------------------- staking

    function test_UnstakeBlockedWhilePending() public {
        _record(REQ, machine1, M1B);
        vm.prank(machine1);
        vm.expectRevert(InferenceTruth.HasPendingRequests.selector);
        it.unstake();

        vm.prank(verifier);
        it.submitVerdict(REQ, true);
        uint256 before = machine1.balance;
        vm.prank(machine1);
        it.unstake();
        assertEq(machine1.balance, before + 2 ether);
        assertEq(it.stakes(machine1), 0);
    }

    function test_ProviderThatRejectsMonIsCreditedInstead() public {
        NoReceive provider = new NoReceive();
        vm.deal(address(provider), 1 ether);
        vm.prank(address(provider));
        it.stake{value: 1 ether}(M1B);
        _record(REQ, address(provider), M1B);

        vm.prank(verifier);
        it.submitVerdict(REQ, true); // must not revert
        assertEq(it.balances(address(provider)), PRICE_1B - PRICE_1B / 10);
        assertEq(address(provider).balance, 0);
    }

    function test_RevertWhen_StakeForUnknownModel() public {
        vm.prank(machine1);
        vm.expectRevert(InferenceTruth.UnknownModel.selector);
        it.stake{value: 1 ether}(bytes32("70B"));
    }

    function test_OnlyOwnerSetsPrice() public {
        vm.prank(user);
        vm.expectRevert();
        it.setModelPrice(M1B, 1);
    }
}

/// A provider that cannot receive MON, to test the credit fallback.
contract NoReceive {}
