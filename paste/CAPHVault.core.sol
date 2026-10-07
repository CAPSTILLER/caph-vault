// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CAPHVault is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Game {
        bool approved;
        uint256 dailyCap;
        uint256 maxPerPayout;
    }

    IERC20 public immutable caph;
    address public treasury;
    uint256 public globalDailyCap;

    mapping(address game => Game) public games;
    mapping(uint256 day => uint256 amount) public paidOnDay;
    mapping(address game => mapping(uint256 day => uint256 amount)) public gamePaidOnDay;
    mapping(address game => mapping(bytes32 ref => bool used)) public refUsed;

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

    error ZeroAddress();
    error ZeroAmount();
    error EmptyRef();
    error NotContract(address account);
    error NotApprovedGame(address caller);
    error RefAlreadyUsed(bytes32 ref);
    error ExceedsPerPayoutCap(uint256 amount, uint256 cap);
    error ExceedsGameDailyCap(uint256 amount, uint256 remaining);
    error ExceedsGlobalDailyCap(uint256 amount, uint256 remaining);
    error InsufficientBalance(uint256 amount, uint256 balance);
    error NothingReceived();
    error InvalidRecipient(address to);
    error CannotRescueCaph();
    error RenounceDisabled();

    modifier onlyGame() {
        if (!games[msg.sender].approved) revert NotApprovedGame(msg.sender);
        _;
    }

    constructor(IERC20 caph_, address initialOwner, address treasury_, uint256 globalDailyCap_)
        Ownable(initialOwner)
    {
        if (address(caph_) == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (address(caph_).code.length == 0) revert NotContract(address(caph_));
        caph = caph_;
        treasury = treasury_;
        globalDailyCap = globalDailyCap_;
        emit TreasurySet(address(0), treasury_);
        emit GlobalDailyCapSet(0, globalDailyCap_);
    }

    function deposit(uint256 amount, bytes32 ref) external nonReentrant returns (uint256 received) {
        received = _pullIn(msg.sender, amount);
        emit Deposited(msg.sender, received, ref);
    }

    function pullFrom(address player, uint256 amount, bytes32 ref)
        external
        nonReentrant
        whenNotPaused
        onlyGame
        returns (uint256 received)
    {
        if (player == address(0)) revert ZeroAddress();
        uint256 cap = games[msg.sender].maxPerPayout;
        if (amount > cap) revert ExceedsPerPayoutCap(amount, cap);
        _useRef(ref);
        received = _pullIn(player, amount);
        emit PulledFromPlayer(msg.sender, player, received, ref);
    }

    function payout(address to, uint256 amount, bytes32 ref) external nonReentrant whenNotPaused onlyGame {
        if (to == address(0)) revert ZeroAddress();
        uint256 day = _spend(amount, ref);
        caph.safeTransfer(to, amount);
        emit Payout(msg.sender, to, amount, ref, day);
    }

    function sendFeeToTreasury(uint256 amount, bytes32 ref) external nonReentrant whenNotPaused onlyGame {
        uint256 day = _spend(amount, ref);
        address t = treasury;
        caph.safeTransfer(t, amount);
        emit FeeToTreasury(msg.sender, t, amount, ref, day);
    }

    function setGame(address game, uint256 dailyCap, uint256 maxPerPayout) external onlyOwner {
        if (game == address(0)) revert ZeroAddress();
        games[game] = Game({approved: true, dailyCap: dailyCap, maxPerPayout: maxPerPayout});
        emit GameSet(game, dailyCap, maxPerPayout);
    }

    function removeGame(address game) external onlyOwner {
        if (!games[game].approved) revert NotApprovedGame(game);
        delete games[game];
        emit GameRemoved(game);
    }

    function setGlobalDailyCap(uint256 newCap) external onlyOwner {
        uint256 oldCap = globalDailyCap;
        globalDailyCap = newCap;
        emit GlobalDailyCapSet(oldCap, newCap);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        if (newTreasury == address(this)) revert InvalidRecipient(newTreasury);
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasurySet(oldTreasury, newTreasury);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address to, uint256 amount) external nonReentrant onlyOwner whenPaused {
        if (to != owner() && to != treasury) revert InvalidRecipient(to);
        if (amount == 0) revert ZeroAmount();
        uint256 bal = caph.balanceOf(address(this));
        if (amount > bal) revert InsufficientBalance(amount, bal);
        caph.safeTransfer(to, amount);
        emit EmergencyWithdraw(to, amount);
    }

    function rescueToken(IERC20 token, address to, uint256 amount) external nonReentrant onlyOwner {
        if (address(token) == address(caph)) revert CannotRescueCaph();
        if (to == address(0)) revert ZeroAddress();
        token.safeTransfer(to, amount);
        emit TokenRescued(address(token), to, amount);
    }

    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    function today() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function vaultBalance() public view returns (uint256) {
        return caph.balanceOf(address(this));
    }

    function globalRemainingToday() public view returns (uint256) {
        uint256 used = paidOnDay[today()];
        return used >= globalDailyCap ? 0 : globalDailyCap - used;
    }

    function gameRemainingToday(address game) public view returns (uint256) {
        Game memory g = games[game];
        if (!g.approved) return 0;
        uint256 used = gamePaidOnDay[game][today()];
        return used >= g.dailyCap ? 0 : g.dailyCap - used;
    }

    function maxPayoutNow(address game) external view returns (uint256 amount) {
        if (paused()) return 0;
        amount = gameRemainingToday(game);
        uint256 x = games[game].maxPerPayout;
        if (x < amount) amount = x;
        x = globalRemainingToday();
        if (x < amount) amount = x;
        x = vaultBalance();
        if (x < amount) amount = x;
    }

    function _useRef(bytes32 ref) private {
        if (ref == bytes32(0)) revert EmptyRef();
        if (refUsed[msg.sender][ref]) revert RefAlreadyUsed(ref);
        refUsed[msg.sender][ref] = true;
    }

    function _spend(uint256 amount, bytes32 ref) private returns (uint256 day) {
        if (amount == 0) revert ZeroAmount();
        Game memory g = games[msg.sender];
        if (amount > g.maxPerPayout) revert ExceedsPerPayoutCap(amount, g.maxPerPayout);

        day = block.timestamp / 1 days;
        uint256 used = gamePaidOnDay[msg.sender][day];
        if (used + amount > g.dailyCap) {
            revert ExceedsGameDailyCap(amount, used >= g.dailyCap ? 0 : g.dailyCap - used);
        }
        uint256 globalUsed = paidOnDay[day];
        if (globalUsed + amount > globalDailyCap) {
            revert ExceedsGlobalDailyCap(amount, globalUsed >= globalDailyCap ? 0 : globalDailyCap - globalUsed);
        }
        uint256 bal = caph.balanceOf(address(this));
        if (amount > bal) revert InsufficientBalance(amount, bal);

        _useRef(ref);
        gamePaidOnDay[msg.sender][day] = used + amount;
        paidOnDay[day] = globalUsed + amount;
    }

    function _pullIn(address from, uint256 amount) private returns (uint256 received) {
        if (amount == 0) revert ZeroAmount();
        uint256 before = caph.balanceOf(address(this));

        caph.safeTransferFrom(from, address(this), amount);
        received = caph.balanceOf(address(this)) - before;
        if (received == 0) revert NothingReceived();
    }
}
