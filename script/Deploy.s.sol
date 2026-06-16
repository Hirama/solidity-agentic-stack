// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";

/// @notice Deploy Vault.
/// @dev Keys are NEVER stored in .env or passed as PRIVATE_KEY.
///      Use `cast wallet import <name> --interactive` to create an encrypted keystore,
///      then deploy with `forge script script/Deploy.s.sol --account <name> --broadcast`.
contract Deploy is Script {
    function run() external returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault();
        vm.stopBroadcast();
    }
}
