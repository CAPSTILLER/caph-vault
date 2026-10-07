// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {HighScoreRecords} from "../src/HighScoreRecords.sol";

contract HighScoreRecordsTest is Test {
    uint32 internal constant ARENA = 1;
    uint32 internal constant SUBSTRATE = 2;

    HighScoreRecords internal rec;
    address internal owner = makeAddr("owner");
    address internal arenaWriter = makeAddr("arenaWriter");
    address internal subWriter = makeAddr("subWriter");
    address internal wallet = makeAddr("wallet");
    address internal nft = makeAddr("caphetBotNFT");
    address internal attacker = makeAddr("attacker");

    event WriterSet(address indexed writer, uint32 indexed gameId);
    event WalletScore(
        uint32 indexed gameId, uint32 indexed mode, address indexed wallet, uint64 score, uint64 best, bool newBest, bytes32 ref
    );
    event BotScore(
        uint32 indexed gameId,
        address indexed nft,
        uint256 indexed tokenId,
        uint32 mode,
        uint64 score,
        uint64 best,
        bool newBest,
        bytes32 ref
    );

    function setUp() public {
        vm.warp(1_790_000_000);
        rec = new HighScoreRecords(owner);
        vm.startPrank(owner);
        rec.setWriter(arenaWriter, ARENA);
        rec.setWriter(subWriter, SUBSTRATE);
        vm.stopPrank();
    }

    function test_Constructor() public {
        assertEq(rec.owner(), owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new HighScoreRecords(address(0));
    }

    function test_SetWriter_OnlyOwnerEmitsAndRemoves() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        rec.setWriter(attacker, ARENA);
        vm.prank(owner);
        vm.expectRevert(HighScoreRecords.ZeroAddress.selector);
        rec.setWriter(address(0), ARENA);

        vm.expectEmit(true, true, true, true, address(rec));
        emit WriterSet(arenaWriter, 0);
        vm.prank(owner);
        rec.setWriter(arenaWriter, 0);
        assertEq(rec.writerGame(arenaWriter), 0);
        vm.prank(arenaWriter);
        vm.expectRevert(abi.encodeWithSelector(HighScoreRecords.NotWriter.selector, arenaWriter));
        rec.recordWalletScore(wallet, 0, 10, bytes32(0));
    }

    function test_UnauthorizedCannotWrite() public {
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSelector(HighScoreRecords.NotWriter.selector, attacker));
        rec.recordWalletScore(wallet, 0, 10, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(HighScoreRecords.NotWriter.selector, attacker));
        rec.recordBotScore(nft, 1, 0, 10, bytes32(0));
        vm.stopPrank();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(HighScoreRecords.NotWriter.selector, owner));
        rec.recordWalletScore(wallet, 0, 10, bytes32(0));
    }

    function test_ZeroTargetsRejected() public {
        vm.startPrank(arenaWriter);
        vm.expectRevert(HighScoreRecords.ZeroAddress.selector);
        rec.recordWalletScore(address(0), 0, 10, bytes32(0));
        vm.expectRevert(HighScoreRecords.ZeroAddress.selector);
        rec.recordBotScore(address(0), 1, 0, 10, bytes32(0));
        vm.stopPrank();
    }

    function test_WalletBestOnlyIncreases_LastAlwaysUpdates() public {
        uint256 t0 = block.timestamp;
        vm.expectEmit(true, true, true, true, address(rec));
        emit WalletScore(ARENA, 0, wallet, 50, 50, true, bytes32("r1"));
        vm.prank(arenaWriter);
        rec.recordWalletScore(wallet, 0, 50, bytes32("r1"));

        vm.warp(t0 + 100);
        vm.expectEmit(true, true, true, true, address(rec));
        emit WalletScore(ARENA, 0, wallet, 20, 50, false, bytes32("r2"));
        vm.prank(arenaWriter);
        rec.recordWalletScore(wallet, 0, 20, bytes32("r2"));

        HighScoreRecords.Record memory r = rec.walletRecord(wallet, ARENA, 0);
        assertEq(r.best, 50);
        assertEq(r.bestAt, t0);
        assertEq(r.last, 20);
        assertEq(r.lastAt, t0 + 100);

        // Equal score is not a new best.
        vm.warp(t0 + 200);
        vm.prank(arenaWriter);
        rec.recordWalletScore(wallet, 0, 50, bytes32("r3"));
        r = rec.walletRecord(wallet, ARENA, 0);
        assertEq(r.bestAt, t0);
        assertEq(r.lastAt, t0 + 200);

        vm.warp(t0 + 300);
        vm.prank(arenaWriter);
        rec.recordWalletScore(wallet, 0, 51, bytes32("r4"));
        r = rec.walletRecord(wallet, ARENA, 0);
        assertEq(r.best, 51);
        assertEq(r.bestAt, t0 + 300);
    }

    function test_FirstZeroScoreSetsTimestamps() public {
        vm.prank(arenaWriter);
        rec.recordWalletScore(wallet, 0, 0, bytes32(0));
        HighScoreRecords.Record memory r = rec.walletRecord(wallet, ARENA, 0);
        assertEq(r.best, 0);
        assertEq(r.bestAt, block.timestamp);
        assertEq(r.lastAt, block.timestamp);
    }

    function test_BotRecords_PerNftAndToken() public {
        address otherNft = makeAddr("otherNft");
        vm.expectEmit(true, true, true, true, address(rec));
        emit BotScore(SUBSTRATE, nft, 7, 3, 900, 900, true, bytes32("run"));
        vm.startPrank(subWriter);
        rec.recordBotScore(nft, 7, 3, 900, bytes32("run"));
        rec.recordBotScore(nft, 7, 3, 100, bytes32(0));
        rec.recordBotScore(nft, 8, 3, 5, bytes32(0));
        rec.recordBotScore(otherNft, 7, 3, 1, bytes32(0));
        vm.stopPrank();

        HighScoreRecords.Record memory r = rec.botRecord(nft, 7, SUBSTRATE, 3);
        assertEq(r.best, 900);
        assertEq(r.last, 100);
        assertEq(rec.botRecord(nft, 8, SUBSTRATE, 3).best, 5);
        assertEq(rec.botRecord(otherNft, 7, SUBSTRATE, 3).best, 1);
        assertEq(rec.botRecord(nft, 7, SUBSTRATE, 2).best, 0);
        assertEq(rec.botRecord(nft, 7, ARENA, 3).best, 0);
    }

    function test_WritersAreBoundToTheirGame() public {
        vm.prank(arenaWriter);
        rec.recordWalletScore(wallet, 1, 10, bytes32(0));
        vm.prank(subWriter);
        rec.recordWalletScore(wallet, 1, 99, bytes32(0));
        assertEq(rec.walletRecord(wallet, ARENA, 1).best, 10);
        assertEq(rec.walletRecord(wallet, SUBSTRATE, 1).best, 99);
    }

    function test_ModesAreSeparate() public {
        vm.startPrank(arenaWriter);
        rec.recordWalletScore(wallet, 0, 10, bytes32(0));
        rec.recordWalletScore(wallet, 2, 30, bytes32(0));
        vm.stopPrank();
        assertEq(rec.walletRecord(wallet, ARENA, 0).best, 10);
        assertEq(rec.walletRecord(wallet, ARENA, 1).best, 0);
        assertEq(rec.walletRecord(wallet, ARENA, 2).best, 30);
    }

    function test_Ownership_TwoStepAndRenounceDisabled() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        vm.expectRevert(HighScoreRecords.RenounceDisabled.selector);
        rec.renounceOwnership();
        vm.prank(owner);
        rec.transferOwnership(newOwner);
        assertEq(rec.owner(), owner);
        vm.prank(newOwner);
        rec.acceptOwnership();
        assertEq(rec.owner(), newOwner);
    }

    function testFuzz_BestIsMaxOfAllScores(uint64[12] memory scores) public {
        uint64 maxSeen;
        for (uint256 i = 0; i < scores.length; i++) {
            vm.warp(block.timestamp + 1);
            vm.prank(arenaWriter);
            rec.recordWalletScore(wallet, 0, scores[i], bytes32(i));
            vm.prank(arenaWriter);
            rec.recordBotScore(nft, 1, 0, scores[i], bytes32(i));
            if (scores[i] > maxSeen) maxSeen = scores[i];
            HighScoreRecords.Record memory r = rec.walletRecord(wallet, ARENA, 0);
            assertEq(r.best, maxSeen);
            assertEq(r.last, scores[i]);
            assertEq(r.lastAt, block.timestamp);
            assertGe(r.best, r.last);
            assertEq(rec.botRecord(nft, 1, ARENA, 0).best, maxSeen);
        }
    }
}
