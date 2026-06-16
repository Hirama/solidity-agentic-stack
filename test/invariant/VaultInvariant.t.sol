// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../src/Vault.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";

/// @notice Invariant test suite for Vault.
/// @dev INV-1 and INV-2 are the protocol constitution — never weaken them to make a test pass.
contract VaultInvariant is Test {
    Vault internal vault;
    VaultHandler internal handler;

    function setUp() public {
        vault = new Vault();
        handler = new VaultHandler(vault);
        targetContract(address(handler));
    }

    /// @notice INV-1: contract ETH balance always equals totalDeposits.
    function invariant_balanceEqualsTotalDeposits() public view {
        assertEq(address(vault).balance, vault.totalDeposits(), "INV-1: balance != totalDeposits");
    }

    /// @notice INV-2: ghost_totalDeposited - ghost_totalWithdrawn == totalDeposits.
    function invariant_depositedMinusWithdrawnEqualsTotalDeposits() public view {
        assertEq(
            handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn(),
            vault.totalDeposits(),
            "INV-2: deposited - withdrawn != totalDeposits"
        );
    }
}
