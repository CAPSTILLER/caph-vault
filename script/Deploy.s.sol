// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CAPHVault} from "../src/CAPHVault.sol";
import {HighScoreRecords} from "../src/HighScoreRecords.sol";

/// Deploys CAPHVault and HighScoreRecords. Defaults are the Base mainnet values in BANKR_HANDOFF.md;
/// override any of them with env vars. No keys live in this file.
///   forge script script/Deploy.s.sol --rpc-url base                  (dry run)
///   forge script script/Deploy.s.sol --rpc-url base --broadcast ...  (real, only when Cap says go)
contract Deploy is Script {
    address internal constant CAPH = 0x1D1bCD1459259429ACcde23e24E1782f83e97bA3;
    address internal constant OWNER = 0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca;
    address internal constant TREASURY = 0xCF1ac98565DA846E8263604b49C1276Ed78A0981;
    uint256 internal constant GLOBAL_DAILY_CAP = 500_000e18;

    function run() external returns (CAPHVault vault, HighScoreRecords records) {
        address caph = vm.envOr("CAPH_TOKEN", CAPH);
        address owner = vm.envOr("OWNER_ADDRESS", OWNER);
        address treasury = vm.envOr("TREASURY_ADDRESS", TREASURY);
        uint256 cap = vm.envOr("GLOBAL_DAILY_CAP", GLOBAL_DAILY_CAP);

        vm.startBroadcast();
        vault = new CAPHVault(IERC20(caph), owner, treasury, cap);
        records = new HighScoreRecords(owner);
        vm.stopBroadcast();

        console2.log("CAPHVault", address(vault));
        console2.log("HighScoreRecords", address(records));
        console2.log("owner", owner);
        console2.log("treasury", treasury);
        console2.log("globalDailyCap (wei)", cap);
    }
}
