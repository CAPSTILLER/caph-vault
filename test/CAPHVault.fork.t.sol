// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CAPHVault} from "../src/CAPHVault.sol";

/// Runs against the real CAPH token on a Base mainnet fork. Skipped unless BASE_RPC_URL is set:
///   BASE_RPC_URL=https://mainnet.base.org forge test --match-contract Fork
contract CAPHVaultForkTest is Test {
    address internal constant CAPH = 0x1D1bCD1459259429ACcde23e24E1782f83e97bA3;
    address internal constant OWNER = 0x1a72f7314297B0b8f6808A9248969A8108F49890;
    address internal constant TREASURY = 0xCF1ac98565DA846E8263604b49C1276Ed78A0981;

    CAPHVault internal vault;
    bool internal live;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        live = true;
        vault = new CAPHVault(IERC20(CAPH), OWNER, TREASURY, 500_000e18);
    }

    function test_Fork_RealCaphDepositPayoutFee() public {
        if (!live) {
            vm.skip(true);
            return;
        }
        assertEq(IERC20Metadata(CAPH).decimals(), 18);
        assertEq(IERC20(CAPH).totalSupply(), 1e11 * 1e18);

        address funder = makeAddr("funder");
        address game = makeAddr("game");
        address player = makeAddr("player");
        deal(CAPH, funder, 50_000e18);

        vm.startPrank(funder);
        IERC20(CAPH).approve(address(vault), 50_000e18);
        assertEq(vault.deposit(50_000e18, bytes32(0)), 50_000e18, "CAPH is not fee-on-transfer");
        vm.stopPrank();

        vm.prank(OWNER);
        vault.setGame(game, 400_000e18, 10_000e18);
        vm.prank(game);
        vault.payout(player, 10_000e18, keccak256("p1"));
        uint256 tBefore = IERC20(CAPH).balanceOf(TREASURY);
        vm.prank(game);
        vault.sendFeeToTreasury(6e18, keccak256("f1"));

        assertEq(IERC20(CAPH).balanceOf(player), 10_000e18);
        assertEq(IERC20(CAPH).balanceOf(TREASURY) - tBefore, 6e18);
        assertEq(vault.vaultBalance(), 50_000e18 - 10_000e18 - 6e18);
    }
}
