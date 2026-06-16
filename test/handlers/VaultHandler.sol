// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Vault} from "../../src/Vault.sol";

/// @notice Invariant handler for Vault. Drives multiple actors through deposit/withdraw.
contract VaultHandler is CommonBase, StdCheats, StdUtils {
    Vault internal vault;

    /*//////////////////////////////////////////////////////////////
                            ACTOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    address[] internal actors;
    address internal currentActor;

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            GHOST VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Total ETH deposited across all actors across all calls.
    uint256 public ghost_totalDeposited;

    /// @notice Total ETH withdrawn across all actors across all calls.
    uint256 public ghost_totalWithdrawn;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(Vault _vault) {
        vault = _vault;

        // Seed five deterministic actors with ETH.
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
            actors.push(actor);
            vm.deal(actor, 1000 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a bounded ETH amount as a random actor.
    function deposit(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        amount = bound(amount, 1, 10 ether);

        // Ensure actor has enough ETH (re-deal if spent).
        if (currentActor.balance < amount) vm.deal(currentActor, amount);

        vault.deposit{value: amount}();
        ghost_totalDeposited += amount;
    }

    /// @notice Withdraw a bounded amount (up to actor's balance) as a random actor.
    function withdraw(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        uint256 available = vault.balanceOf(currentActor);
        if (available == 0) return;

        amount = bound(amount, 1, available);
        vault.withdraw(amount);
        ghost_totalWithdrawn += amount;
    }
}
