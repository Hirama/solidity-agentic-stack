// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";

contract VaultTest is Test {
    Vault internal vault;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vault = new Vault();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT — HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_deposit_updatesBalance() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        assertEq(vault.balanceOf(alice), 1 ether);
        assertEq(vault.totalDeposits(), 1 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_deposit_multipleUsers() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(bob);
        vault.deposit{value: 2 ether}();

        assertEq(vault.balanceOf(alice), 1 ether);
        assertEq(vault.balanceOf(bob), 2 ether);
        assertEq(vault.totalDeposits(), 3 ether);
    }

    function test_deposit_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Vault.Deposited(alice, 1 ether);

        vm.prank(alice);
        vault.deposit{value: 1 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT — REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_revertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroDeposit.selector);
        vault.deposit{value: 0}();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW — HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_withdraw_updatesBalance() public {
        vm.startPrank(alice);
        vault.deposit{value: 2 ether}();
        vault.withdraw(1 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 1 ether);
        assertEq(vault.totalDeposits(), 1 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_withdraw_fullBalance() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        vault.withdraw(1 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalDeposits(), 0);
        assertEq(address(vault).balance, 0);
    }

    function test_withdraw_emitsEvent() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();

        vm.expectEmit(true, false, false, true);
        emit Vault.Withdrawn(alice, 1 ether);
        vault.withdraw(1 ether);
        vm.stopPrank();
    }

    function test_withdraw_sendsEth() public {
        uint256 before = alice.balance;

        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        vault.withdraw(1 ether);
        vm.stopPrank();

        assertEq(alice.balance, before);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW — REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_withdraw_revertsIfInsufficientBalance() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 2 ether, 1 ether));
        vault.withdraw(2 ether);
    }

    function test_withdraw_revertsWithNoDeposit() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 1 ether, 0));
        vault.withdraw(1 ether);
    }

    function test_withdraw_cannotWithdrawOnBehalfOfOther() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 1 ether, 0));
        vault.withdraw(1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Depositing then withdrawing the same amount returns funds and zeroes balance.
    function testFuzz_depositWithdrawRoundtrip(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);
        vm.deal(alice, amount);

        vm.startPrank(alice);
        vault.deposit{value: amount}();
        vault.withdraw(amount);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalDeposits(), 0);
        assertEq(alice.balance, amount);
    }

    /// @notice Cannot withdraw more than deposited.
    function testFuzz_cannotWithdrawMoreThanDeposited(uint256 deposit, uint256 excess) public {
        deposit = bound(deposit, 1, 100 ether);
        excess = bound(excess, 1, type(uint128).max);
        vm.deal(alice, deposit);

        vm.prank(alice);
        vault.deposit{value: deposit}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, deposit + excess, deposit));
        vault.withdraw(deposit + excess);
    }

    /// @notice balanceOf and totalDeposits track partial withdrawals correctly.
    function testFuzz_partialWithdraw(uint256 deposit, uint256 withdrawAmt) public {
        deposit = bound(deposit, 2, 100 ether);
        withdrawAmt = bound(withdrawAmt, 1, deposit - 1);
        vm.deal(alice, deposit);

        vm.startPrank(alice);
        vault.deposit{value: deposit}();
        vault.withdraw(withdrawAmt);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), deposit - withdrawAmt);
        assertEq(vault.totalDeposits(), deposit - withdrawAmt);
    }
}
