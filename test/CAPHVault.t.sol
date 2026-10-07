// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CAPHVault} from "../src/CAPHVault.sol";
import {MockCAPH, FeeOnTransferToken, NoopTransferToken, ReentrantToken} from "./mocks/Mocks.sol";

contract CAPHVaultTest is Test {
    uint256 internal constant T = 1e18; // one whole CAPH
    uint256 internal constant GLOBAL_CAP = 500_000 * T;
    uint256 internal constant ARENA_DAILY = 400_000 * T;
    uint256 internal constant ARENA_MAX = 10_000 * T;
    uint256 internal constant SUB_DAILY = 100_000 * T;
    uint256 internal constant SUB_MAX = 1_000 * T;
    uint256 internal constant DAY0 = 20_368; // a UTC day number
    uint256 internal constant START = DAY0 * 1 days + 12 hours;

    MockCAPH internal caph;
    CAPHVault internal vault;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal arena = makeAddr("arenaServer");
    address internal substrate = makeAddr("substrateServer");
    address internal funder = makeAddr("funder");
    address internal player = makeAddr("player");
    address internal attacker = makeAddr("attacker");

    event Deposited(address indexed funder, uint256 amount, bytes32 indexed ref);
    event PulledFromPlayer(address indexed game, address indexed player, uint256 amount, bytes32 indexed ref);
    event Payout(address indexed game, address indexed to, uint256 amount, bytes32 indexed ref, uint256 day);
    event FeeToTreasury(address indexed game, address indexed treasury, uint256 amount, bytes32 indexed ref, uint256 day);
    event GameSet(address indexed game, uint256 dailyCap, uint256 maxPerPayout);
    event GameRemoved(address indexed game);
    event GlobalDailyCapSet(uint256 oldCap, uint256 newCap);
    event TreasurySet(address indexed oldTreasury, address indexed newTreasury);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        vm.warp(START);
        caph = new MockCAPH();
        vault = new CAPHVault(IERC20(address(caph)), owner, treasury, GLOBAL_CAP);
        vm.startPrank(owner);
        vault.setGame(arena, ARENA_DAILY, ARENA_MAX);
        vault.setGame(substrate, SUB_DAILY, SUB_MAX);
        vm.stopPrank();
        _fund(2_000_000 * T);
    }

    // ------------------------------------------------------------ helpers

    function _fund(uint256 amount) internal {
        caph.mint(funder, amount);
        vm.startPrank(funder);
        caph.approve(address(vault), amount);
        vault.deposit(amount, bytes32(0));
        vm.stopPrank();
    }

    function _ref(uint256 i) internal pure returns (bytes32) {
        return keccak256(abi.encode("ref", i));
    }

    function _pay(address game, address to, uint256 amount, uint256 i) internal {
        vm.prank(game);
        vault.payout(to, amount, _ref(i));
    }

    // ------------------------------------------------------------ constructor

    function test_Constructor_SetsState() public view {
        assertEq(address(vault.caph()), address(caph));
        assertEq(vault.owner(), owner);
        assertEq(vault.treasury(), treasury);
        assertEq(vault.globalDailyCap(), GLOBAL_CAP);
        assertEq(vault.pendingOwner(), address(0));
        assertFalse(vault.paused());
        (bool ok, uint256 daily, uint256 maxP) = vault.games(arena);
        assertTrue(ok);
        assertEq(daily, ARENA_DAILY);
        assertEq(maxP, ARENA_MAX);
        assertEq(vault.today(), DAY0);
    }

    function test_Constructor_DeployerHasNoRights() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.pause();
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        new CAPHVault(IERC20(address(0)), owner, treasury, GLOBAL_CAP);
    }

    function test_Constructor_RevertsOnZeroTreasury() public {
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        new CAPHVault(IERC20(address(caph)), owner, address(0), GLOBAL_CAP);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CAPHVault(IERC20(address(caph)), address(0), treasury, GLOBAL_CAP);
    }

    function test_Constructor_RevertsOnNonContractToken() public {
        address eoa = makeAddr("eoaToken");
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotContract.selector, eoa));
        new CAPHVault(IERC20(eoa), owner, treasury, GLOBAL_CAP);
    }

    // ------------------------------------------------------------ deposits

    function test_Deposit_RecordsAmountAndEmits() public {
        caph.mint(player, 123 * T);
        vm.startPrank(player);
        caph.approve(address(vault), 123 * T);
        vm.expectEmit(true, true, true, true, address(vault));
        emit Deposited(player, 123 * T, bytes32("x"));
        uint256 got = vault.deposit(123 * T, bytes32("x"));
        vm.stopPrank();
        assertEq(got, 123 * T);
        assertEq(vault.vaultBalance(), 2_000_123 * T);
    }

    function test_Deposit_MeasuresReceivedOnFeeOnTransferToken() public {
        FeeOnTransferToken fot = new FeeOnTransferToken();
        CAPHVault v = new CAPHVault(IERC20(address(fot)), owner, treasury, GLOBAL_CAP);
        fot.mint(funder, 1_000 * T);
        vm.startPrank(funder);
        fot.approve(address(v), 1_000 * T);
        vm.expectEmit(true, true, true, true, address(v));
        emit Deposited(funder, 990 * T, bytes32(0));
        uint256 got = v.deposit(1_000 * T, bytes32(0));
        vm.stopPrank();
        assertEq(got, 990 * T);
        assertEq(v.vaultBalance(), 990 * T);
    }

    function test_PullFrom_MeasuresReceivedOnFeeOnTransferToken() public {
        FeeOnTransferToken fot = new FeeOnTransferToken();
        CAPHVault v = new CAPHVault(IERC20(address(fot)), owner, treasury, GLOBAL_CAP);
        vm.prank(owner);
        v.setGame(arena, ARENA_DAILY, ARENA_MAX);
        fot.mint(player, 500 * T);
        vm.prank(player);
        fot.approve(address(v), 500 * T);
        vm.prank(arena);
        uint256 got = v.pullFrom(player, 500 * T, _ref(1));
        assertEq(got, 495 * T);
    }

    function test_Deposit_RevertsWhenNothingReceived() public {
        NoopTransferToken noop = new NoopTransferToken();
        CAPHVault v = new CAPHVault(IERC20(address(noop)), owner, treasury, GLOBAL_CAP);
        noop.mint(funder, 10 * T);
        vm.prank(funder);
        vm.expectRevert(CAPHVault.NothingReceived.selector);
        v.deposit(10 * T, bytes32(0));
    }

    function test_Deposit_RevertsOnZeroAmount() public {
        vm.prank(funder);
        vm.expectRevert(CAPHVault.ZeroAmount.selector);
        vault.deposit(0, bytes32(0));
    }

    function test_Deposit_RevertsWithoutApproval() public {
        caph.mint(player, 10 * T);
        vm.prank(player);
        vm.expectRevert();
        vault.deposit(10 * T, bytes32(0));
    }

    function test_Deposit_StaysOpenWhilePaused() public {
        vm.prank(owner);
        vault.pause();
        _fund(5 * T);
        assertEq(vault.vaultBalance(), 2_000_005 * T);
    }

    function test_PlainTransferAlsoFunds() public {
        caph.mint(funder, 7 * T);
        vm.prank(funder);
        caph.transfer(address(vault), 7 * T);
        assertEq(vault.vaultBalance(), 2_000_007 * T);
    }

    // ------------------------------------------------------------ payouts and caps

    function test_Payout_PaysAndEmits() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit Payout(arena, player, 250 * T, _ref(1), DAY0);
        _pay(arena, player, 250 * T, 1);
        assertEq(caph.balanceOf(player), 250 * T);
        assertEq(vault.gamePaidOnDay(arena, DAY0), 250 * T);
        assertEq(vault.paidOnDay(DAY0), 250 * T);
        assertTrue(vault.refUsed(arena, _ref(1)));
    }

    function test_Payout_RevertsForUnapprovedCaller() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotApprovedGame.selector, attacker));
        vault.payout(attacker, 1 * T, _ref(1));
    }

    function test_Payout_RevertsForOwnerUnlessApproved() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotApprovedGame.selector, owner));
        vault.payout(owner, 1 * T, _ref(1));
    }

    function test_Payout_PerPayoutCapExactAndAbove() public {
        _pay(arena, player, ARENA_MAX, 1);
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsPerPayoutCap.selector, ARENA_MAX + 1, ARENA_MAX));
        vault.payout(player, ARENA_MAX + 1, _ref(2));
    }

    function test_Payout_PerGamePerPayoutCapsAreIndependent() public {
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsPerPayoutCap.selector, 2_000 * T, SUB_MAX));
        vault.payout(player, 2_000 * T, _ref(1));
        _pay(arena, player, 2_000 * T, 1);
    }

    function test_Payout_GameDailyCap() public {
        // Substrate: 100,000/day at max 1,000 per payout = 100 payouts.
        for (uint256 i = 0; i < 100; i++) {
            _pay(substrate, player, SUB_MAX, i);
        }
        assertEq(vault.gameRemainingToday(substrate), 0);
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsGameDailyCap.selector, 1, 0));
        vault.payout(player, 1, _ref(1000));
        // Arena is unaffected.
        _pay(arena, player, 1 * T, 1);
    }

    function test_Payout_GameDailyCapReportsRemaining() public {
        vm.prank(owner);
        vault.setGame(substrate, uint256(1_500 * T), SUB_MAX);
        _pay(substrate, player, 1_000 * T, 1);
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsGameDailyCap.selector, 600 * T, 500 * T));
        vault.payout(player, 600 * T, _ref(2));
        _pay(substrate, player, 500 * T, 3);
    }

    function test_Payout_GlobalDailyCapAcrossGames() public {
        vm.prank(owner);
        vault.setGlobalDailyCap(15_000 * T);
        _pay(arena, player, 10_000 * T, 1);
        _pay(substrate, player, 1_000 * T, 1);
        _pay(arena, player, 4_000 * T, 2);
        assertEq(vault.globalRemainingToday(), 0);
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsGlobalDailyCap.selector, 1, 0));
        vault.payout(player, 1, _ref(2));
    }

    function test_Payout_FullDefaultCapsScenario() public {
        // Arena 400k + Substrate 100k = exactly the 500k global cap.
        for (uint256 i = 0; i < 40; i++) {
            _pay(arena, player, ARENA_MAX, i);
        }
        for (uint256 i = 0; i < 100; i++) {
            _pay(substrate, player, SUB_MAX, i);
        }
        assertEq(vault.paidOnDay(DAY0), GLOBAL_CAP);
        assertEq(vault.globalRemainingToday(), 0);
        assertEq(vault.maxPayoutNow(arena), 0);
    }

    function test_Payout_InsufficientBalance() public {
        CAPHVault v = new CAPHVault(IERC20(address(caph)), owner, treasury, GLOBAL_CAP);
        vm.prank(owner);
        v.setGame(arena, ARENA_DAILY, ARENA_MAX);
        caph.mint(address(v), 5 * T);
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.InsufficientBalance.selector, 6 * T, 5 * T));
        v.payout(player, 6 * T, _ref(1));
    }

    function test_Payout_RevertsOnZeroRecipientAmountOrRef() public {
        vm.startPrank(arena);
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        vault.payout(address(0), 1, _ref(1));
        vm.expectRevert(CAPHVault.ZeroAmount.selector);
        vault.payout(player, 0, _ref(1));
        vm.expectRevert(CAPHVault.EmptyRef.selector);
        vault.payout(player, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_Payout_RefCannotBeReused() public {
        _pay(arena, player, 10 * T, 1);
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.RefAlreadyUsed.selector, _ref(1)));
        vault.payout(player, 10 * T, _ref(1));
        // Reuse is blocked across payout, fee, and pull for the same game.
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.RefAlreadyUsed.selector, _ref(1)));
        vault.sendFeeToTreasury(1 * T, _ref(1));
    }

    function test_Payout_RefsAreNamespacedPerGame() public {
        _pay(arena, player, 10 * T, 1);
        _pay(substrate, player, 10 * T, 1);
        assertEq(caph.balanceOf(player), 20 * T);
    }

    function test_Payout_FailedCallDoesNotConsumeRefOrCap() public {
        vm.prank(arena);
        vm.expectRevert();
        vault.payout(player, ARENA_MAX + 1, _ref(1));
        assertFalse(vault.refUsed(arena, _ref(1)));
        assertEq(vault.paidOnDay(DAY0), 0);
        _pay(arena, player, 1 * T, 1);
    }

    function test_NftDailyClaimPattern_OneClaimPerBotPerDay() public {
        address bots = makeAddr("caphetBotNFT");
        uint256 tokenId = 42;
        bytes32 ref = keccak256(abi.encode(bots, tokenId, vault.today()));
        vm.prank(arena);
        vault.payout(player, 100 * T, ref);
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.RefAlreadyUsed.selector, ref));
        vault.payout(player, 100 * T, ref);
        vm.warp(block.timestamp + 1 days);
        bytes32 ref2 = keccak256(abi.encode(bots, tokenId, vault.today()));
        vm.prank(arena);
        vault.payout(player, 100 * T, ref2);
        assertEq(caph.balanceOf(player), 200 * T);
    }

    // ------------------------------------------------------------ day rollover

    function test_DayRollover_ResetsAtUtcMidnight() public {
        for (uint256 i = 0; i < 100; i++) {
            _pay(substrate, player, SUB_MAX, i);
        }
        // One second before midnight UTC: still the same day, still capped.
        vm.warp((DAY0 + 1) * 1 days - 1);
        assertEq(vault.today(), DAY0);
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsGameDailyCap.selector, SUB_MAX, 0));
        vault.payout(player, SUB_MAX, _ref(500));
        // Exactly midnight UTC: new day, full cap again.
        vm.warp((DAY0 + 1) * 1 days);
        assertEq(vault.today(), DAY0 + 1);
        assertEq(vault.gameRemainingToday(substrate), SUB_DAILY);
        assertEq(vault.globalRemainingToday(), GLOBAL_CAP);
        _pay(substrate, player, SUB_MAX, 500);
        assertEq(vault.gamePaidOnDay(substrate, DAY0), SUB_DAILY);
        assertEq(vault.gamePaidOnDay(substrate, DAY0 + 1), SUB_MAX);
    }

    function test_DayRollover_GlobalCap() public {
        vm.prank(owner);
        vault.setGlobalDailyCap(1_000 * T);
        _pay(arena, player, 1_000 * T, 1);
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsGlobalDailyCap.selector, 1, 0));
        vault.payout(player, 1, _ref(2));
        vm.warp((DAY0 + 1) * 1 days);
        _pay(arena, player, 1_000 * T, 2);
    }

    // ------------------------------------------------------------ fee routing

    function test_Fee_GoesToTreasuryAndCountsTowardCaps() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit FeeToTreasury(arena, treasury, 6 * T, _ref(1), DAY0);
        vm.prank(arena);
        vault.sendFeeToTreasury(6 * T, _ref(1));
        assertEq(caph.balanceOf(treasury), 6 * T);
        assertEq(vault.gamePaidOnDay(arena, DAY0), 6 * T);
        assertEq(vault.paidOnDay(DAY0), 6 * T);
    }

    function test_Fee_FollowsTreasuryChange() public {
        address newTreasury = makeAddr("newTreasury");
        vm.expectEmit(true, true, true, true, address(vault));
        emit TreasurySet(treasury, newTreasury);
        vm.prank(owner);
        vault.setTreasury(newTreasury);
        vm.prank(arena);
        vault.sendFeeToTreasury(5 * T, _ref(1));
        assertEq(caph.balanceOf(newTreasury), 5 * T);
        assertEq(caph.balanceOf(treasury), 0);
    }

    function test_Fee_RespectsCapsAndAuth() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotApprovedGame.selector, attacker));
        vault.sendFeeToTreasury(1 * T, _ref(1));
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsPerPayoutCap.selector, SUB_MAX + 1, SUB_MAX));
        vault.sendFeeToTreasury(SUB_MAX + 1, _ref(1));
        vm.prank(arena);
        vm.expectRevert(CAPHVault.ZeroAmount.selector);
        vault.sendFeeToTreasury(0, _ref(1));
    }

    function test_SetTreasury_Guards() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setTreasury(attacker);
        vm.startPrank(owner);
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        vault.setTreasury(address(0));
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.InvalidRecipient.selector, address(vault)));
        vault.setTreasury(address(vault));
        vm.stopPrank();
    }

    /// Arena round flow with the agreed rules: ante = min(best, 10,000); fall fee = ceil(5% of coins).
    function test_ArenaFlow_AnteCashOutAndFall() public {
        caph.mint(player, 20_000 * T);
        vm.prank(player);
        caph.approve(address(vault), type(uint256).max);

        // First play: ante 0, nothing pulled, cash out 37 -> vault pays 37.
        _pay(arena, player, 37 * T, 1);

        // Second play: best 37 -> ante 37 pulled, cash out 50 -> payout 50.
        vm.prank(arena);
        vault.pullFrom(player, 37 * T, keccak256("r2:ante"));
        vm.prank(arena);
        vault.payout(player, 50 * T, keccak256("r2:payout"));

        // Third play: best 50 -> ante 50 pulled, falls with 101 coins on table -> fee ceil(5.05) = 6.
        uint256 coins = 101;
        uint256 fee = (coins * 5 + 99) / 100;
        assertEq(fee, 6);
        vm.prank(arena);
        vault.pullFrom(player, 50 * T, keccak256("r3:ante"));
        vm.prank(arena);
        vault.sendFeeToTreasury(fee * T, keccak256("r3:fee"));

        assertEq(caph.balanceOf(player), (20_000 + 37 - 37 + 50 - 50) * T);
        assertEq(caph.balanceOf(treasury), 6 * T);
        assertEq(vault.vaultBalance(), 2_000_000 * T - 37 * T + 37 * T - 50 * T + 50 * T - 6 * T);
        assertEq(vault.paidOnDay(DAY0), (37 + 50 + 6) * T);
    }

    // ------------------------------------------------------------ pulls

    function test_PullFrom_PullsAndEmits() public {
        caph.mint(player, 1_000 * T);
        vm.prank(player);
        caph.approve(address(vault), 1_000 * T);
        vm.expectEmit(true, true, true, true, address(vault));
        emit PulledFromPlayer(arena, player, 400 * T, _ref(9));
        vm.prank(arena);
        uint256 got = vault.pullFrom(player, 400 * T, _ref(9));
        assertEq(got, 400 * T);
        assertEq(caph.balanceOf(player), 600 * T);
        // Pulls do not use up payout caps.
        assertEq(vault.paidOnDay(DAY0), 0);
    }

    function test_PullFrom_Guards() public {
        caph.mint(player, 100_000 * T);
        vm.prank(player);
        caph.approve(address(vault), 100_000 * T);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotApprovedGame.selector, attacker));
        vault.pullFrom(player, 1 * T, _ref(1));

        vm.startPrank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsPerPayoutCap.selector, ARENA_MAX + 1, ARENA_MAX));
        vault.pullFrom(player, ARENA_MAX + 1, _ref(1));
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        vault.pullFrom(address(0), 1 * T, _ref(1));
        vm.expectRevert(CAPHVault.EmptyRef.selector);
        vault.pullFrom(player, 1 * T, bytes32(0));
        vm.expectRevert(CAPHVault.ZeroAmount.selector);
        vault.pullFrom(player, 0, _ref(1));
        vault.pullFrom(player, 1 * T, _ref(1));
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.RefAlreadyUsed.selector, _ref(1)));
        vault.pullFrom(player, 1 * T, _ref(1));
        vm.stopPrank();
    }

    function test_PullFrom_NeedsPlayerApproval() public {
        caph.mint(player, 100 * T);
        vm.prank(arena);
        vm.expectRevert();
        vault.pullFrom(player, 100 * T, _ref(1));
    }

    // ------------------------------------------------------------ pause

    function test_Pause_BlocksGameCalls() public {
        caph.mint(player, 100 * T);
        vm.prank(player);
        caph.approve(address(vault), 100 * T);

        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());
        assertEq(vault.maxPayoutNow(arena), 0);

        vm.startPrank(arena);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.payout(player, 1 * T, _ref(1));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.sendFeeToTreasury(1 * T, _ref(2));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.pullFrom(player, 1 * T, _ref(3));
        vm.stopPrank();

        vm.prank(owner);
        vault.unpause();
        _pay(arena, player, 1 * T, 1);
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.pause();
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, arena));
        vault.pause();
        vm.prank(owner);
        vault.pause();
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.unpause();
    }

    function test_Pause_OwnerSettingsStillWork() public {
        vm.startPrank(owner);
        vault.pause();
        vault.setGame(arena, 1, 1);
        vault.setGlobalDailyCap(1);
        vault.setTreasury(makeAddr("t2"));
        vault.removeGame(substrate);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ emergency withdraw

    function test_EmergencyWithdraw_RevertsWhenNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vault.emergencyWithdraw(owner, 1 * T);
    }

    function test_EmergencyWithdraw_ToOwnerWhenPaused() public {
        vm.startPrank(owner);
        vault.pause();
        vm.expectEmit(true, true, true, true, address(vault));
        emit EmergencyWithdraw(owner, 2_000_000 * T);
        vault.emergencyWithdraw(owner, 2_000_000 * T);
        vm.stopPrank();
        assertEq(caph.balanceOf(owner), 2_000_000 * T);
        assertEq(vault.vaultBalance(), 0);
    }

    function test_EmergencyWithdraw_ToTreasuryWhenPaused() public {
        vm.startPrank(owner);
        vault.pause();
        vault.emergencyWithdraw(treasury, 1_000 * T);
        vm.stopPrank();
        assertEq(caph.balanceOf(treasury), 1_000 * T);
    }

    function test_EmergencyWithdraw_OnlyOwnerOrTreasuryRecipient() public {
        vm.startPrank(owner);
        vault.pause();
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.InvalidRecipient.selector, attacker));
        vault.emergencyWithdraw(attacker, 1 * T);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.InvalidRecipient.selector, arena));
        vault.emergencyWithdraw(arena, 1 * T);
        vm.expectRevert(CAPHVault.ZeroAmount.selector);
        vault.emergencyWithdraw(owner, 0);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.InsufficientBalance.selector, 2_000_001 * T, 2_000_000 * T));
        vault.emergencyWithdraw(owner, 2_000_001 * T);
        vm.stopPrank();
    }

    function test_EmergencyWithdraw_OnlyOwnerCaller() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, arena));
        vault.emergencyWithdraw(treasury, 1 * T);
        vm.prank(treasury);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, treasury));
        vault.emergencyWithdraw(treasury, 1 * T);
    }

    // ------------------------------------------------------------ games admin

    function test_SetGame_OnlyOwnerAndEmits() public {
        address g = makeAddr("newGame");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setGame(g, 1, 1);
        vm.prank(owner);
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        vault.setGame(address(0), 1, 1);
        vm.expectEmit(true, true, true, true, address(vault));
        emit GameSet(g, 5 * T, 2 * T);
        vm.prank(owner);
        vault.setGame(g, uint256(5 * T), uint256(2 * T));
        assertEq(vault.gameRemainingToday(g), 5 * T);
    }

    function test_RemoveGame_StopsPayouts() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit GameRemoved(substrate);
        vm.prank(owner);
        vault.removeGame(substrate);
        assertEq(vault.gameRemainingToday(substrate), 0);
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotApprovedGame.selector, substrate));
        vault.payout(player, 1, _ref(1));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.NotApprovedGame.selector, substrate));
        vault.removeGame(substrate);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.removeGame(arena);
    }

    function test_ReAddingGameSameDayKeepsUsage() public {
        _pay(substrate, player, SUB_MAX, 1);
        vm.startPrank(owner);
        vault.removeGame(substrate);
        vault.setGame(substrate, SUB_DAILY, SUB_MAX);
        vm.stopPrank();
        assertEq(vault.gameRemainingToday(substrate), SUB_DAILY - SUB_MAX);
        // Old refs stay used too.
        vm.prank(substrate);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.RefAlreadyUsed.selector, _ref(1)));
        vault.payout(player, 1, _ref(1));
    }

    function test_LoweringCapMidDayAppliesImmediately() public {
        _pay(arena, player, 5_000 * T, 1);
        vm.prank(owner);
        vault.setGame(arena, uint256(4_000 * T), ARENA_MAX);
        assertEq(vault.gameRemainingToday(arena), 0);
        vm.prank(arena);
        vm.expectRevert(abi.encodeWithSelector(CAPHVault.ExceedsGameDailyCap.selector, 1, 0));
        vault.payout(player, 1, _ref(2));
    }

    function test_SetGlobalDailyCap_OnlyOwnerAndEmits() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setGlobalDailyCap(1);
        vm.expectEmit(true, true, true, true, address(vault));
        emit GlobalDailyCapSet(GLOBAL_CAP, 7);
        vm.prank(owner);
        vault.setGlobalDailyCap(7);
        assertEq(vault.globalDailyCap(), 7);
    }

    // ------------------------------------------------------------ views

    function test_Views_RemainingAndMaxPayoutNow() public {
        assertEq(vault.globalRemainingToday(), GLOBAL_CAP);
        assertEq(vault.gameRemainingToday(arena), ARENA_DAILY);
        assertEq(vault.maxPayoutNow(arena), ARENA_MAX);
        assertEq(vault.maxPayoutNow(substrate), SUB_MAX);
        assertEq(vault.maxPayoutNow(attacker), 0);
        assertEq(vault.gameRemainingToday(attacker), 0);

        _pay(arena, player, 3_000 * T, 1);
        assertEq(vault.globalRemainingToday(), GLOBAL_CAP - 3_000 * T);
        assertEq(vault.gameRemainingToday(arena), ARENA_DAILY - 3_000 * T);

        // Limited by the global cap.
        vm.prank(owner);
        vault.setGlobalDailyCap(3_500 * T);
        assertEq(vault.maxPayoutNow(arena), 500 * T);
        // Global cap lowered below usage reports 0, not an underflow.
        vm.prank(owner);
        vault.setGlobalDailyCap(1_000 * T);
        assertEq(vault.globalRemainingToday(), 0);
    }

    function test_Views_MaxPayoutNowLimitedByBalance() public {
        CAPHVault v = new CAPHVault(IERC20(address(caph)), owner, treasury, GLOBAL_CAP);
        vm.prank(owner);
        v.setGame(arena, ARENA_DAILY, ARENA_MAX);
        caph.mint(address(v), 42 * T);
        assertEq(v.maxPayoutNow(arena), 42 * T);
    }

    // ------------------------------------------------------------ ownership

    function test_Ownership_TwoStep() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), newOwner);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.acceptOwnership();
        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_Ownership_RenounceDisabled() public {
        vm.prank(owner);
        vm.expectRevert(CAPHVault.RenounceDisabled.selector);
        vault.renounceOwnership();
        assertEq(vault.owner(), owner);
    }

    // ------------------------------------------------------------ rescue

    function test_RescueToken_OtherTokenOnly() public {
        MockCAPH other = new MockCAPH();
        other.mint(address(vault), 9 * T);
        vm.expectEmit(true, true, true, true, address(vault));
        emit TokenRescued(address(other), funder, 9 * T);
        vm.prank(owner);
        vault.rescueToken(IERC20(address(other)), funder, 9 * T);
        assertEq(other.balanceOf(funder), 9 * T);

        vm.prank(owner);
        vm.expectRevert(CAPHVault.CannotRescueCaph.selector);
        vault.rescueToken(IERC20(address(caph)), owner, 1);
        vm.prank(owner);
        vm.expectRevert(CAPHVault.ZeroAddress.selector);
        vault.rescueToken(IERC20(address(other)), address(0), 1);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.rescueToken(IERC20(address(other)), attacker, 1);
    }

    function test_RejectsPlainEth() public {
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // ------------------------------------------------------------ reentrancy

    function test_Reentrancy_PayoutCallbackBlocked() public {
        ReentrantToken re = new ReentrantToken();
        CAPHVault v = new CAPHVault(IERC20(address(re)), owner, treasury, GLOBAL_CAP);
        vm.startPrank(owner);
        v.setGame(arena, ARENA_DAILY, ARENA_MAX);
        v.setGame(address(re), ARENA_DAILY, ARENA_MAX); // worst case: token itself is an approved game
        vm.stopPrank();
        re.mint(address(v), 100_000 * T);
        re.arm(address(v), abi.encodeCall(CAPHVault.payout, (attacker, 1 * T, _ref(77))));
        vm.prank(arena);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        v.payout(player, 1 * T, _ref(1));
    }

    function test_Reentrancy_DepositCallbackBlocked() public {
        ReentrantToken re = new ReentrantToken();
        CAPHVault v = new CAPHVault(IERC20(address(re)), owner, treasury, GLOBAL_CAP);
        vm.prank(owner);
        v.setGame(address(re), ARENA_DAILY, ARENA_MAX);
        re.mint(address(v), 100_000 * T);
        re.mint(funder, 10 * T);
        vm.prank(funder);
        re.approve(address(v), 10 * T);
        re.arm(address(v), abi.encodeCall(CAPHVault.sendFeeToTreasury, (1 * T, _ref(1))));
        vm.prank(funder);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        v.deposit(10 * T, bytes32(0));
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_PaidNeverExceedsCaps(uint256[20] memory amounts, uint8[20] memory who) public {
        uint256 day = vault.today();
        for (uint256 i = 0; i < 20; i++) {
            address g = who[i] % 2 == 0 ? arena : substrate;
            uint256 amt = bound(amounts[i], 1, 12_000 * T);
            vm.prank(g);
            try vault.payout(player, amt, _ref(i)) {} catch {}
        }
        assertLe(vault.gamePaidOnDay(arena, day), ARENA_DAILY);
        assertLe(vault.gamePaidOnDay(substrate, day), SUB_DAILY);
        assertLe(vault.paidOnDay(day), GLOBAL_CAP);
        assertEq(vault.paidOnDay(day), vault.gamePaidOnDay(arena, day) + vault.gamePaidOnDay(substrate, day));
        assertEq(caph.balanceOf(player), vault.paidOnDay(day));
        assertEq(vault.vaultBalance(), 2_000_000 * T - vault.paidOnDay(day));
    }

    function testFuzz_DepositThenPayoutConservesTokens(uint96 dep, uint96 pay) public {
        uint256 d = bound(uint256(dep), 1, 1e11 * T);
        _fund(d);
        uint256 p = bound(uint256(pay), 1, ARENA_MAX);
        _pay(arena, player, p, 1);
        assertEq(vault.vaultBalance() + caph.balanceOf(player), 2_000_000 * T + d);
    }
}
