// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

interface IERC165 {

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC20 {

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}

interface IERC20Metadata is IERC20 {

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);

    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract Pausable is Context {
    bool private _paused;

    event Paused(address account);

    event Unpaused(address account);

    error EnforcedPause();

    error ExpectedPause();

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

abstract contract ReentrancyGuard {
    using StorageSlot for bytes32;

    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
    }

    function _nonReentrantBefore() private {

        _nonReentrantBeforeView();

        _reentrancyGuardStorageSlot().getUint256Slot().value = ENTERED;
    }

    function _nonReentrantAfter() private {

        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardStorageSlot().getUint256Slot().value == ENTERED;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}

abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}

interface IERC1363 is IERC20, IERC165 {

    function transferAndCall(address to, uint256 value) external returns (bool);

    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    function approveAndCall(address spender, uint256 value) external returns (bool);

    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

library SafeERC20 {

    error SafeERC20FailedOperation(address token);

    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _safeTransfer(token, to, value, false);
    }

    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _safeTransferFrom(token, from, to, value, false);
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true)) revert SafeERC20FailedOperation(address(token));
            if (!_safeApprove(token, spender, value, true)) revert SafeERC20FailedOperation(address(token));
        }
    }

    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    function tryGetDecimals(IERC20 token) internal view returns (bool success, uint8 decimals) {
        bytes4 selector = IERC20Metadata.decimals.selector;
        assembly ("memory-safe") {
            mstore(0x00, selector)
            success := staticcall(gas(), token, 0x00, 4, 0x00, 0x20)
            success := and(and(success, gt(returndatasize(), 0x1f)), lt(mload(0x00), 0x100))
            decimals := mul(success, mload(0x00))
        }
    }

    function _safeTransfer(IERC20 token, address to, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = IERC20.transfer.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(to, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)

            if iszero(and(success, eq(mload(0x00), 1))) {

                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }

                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
        }
    }

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = IERC20.transferFrom.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(from, shr(96, not(0))))
            mstore(0x24, and(to, shr(96, not(0))))
            mstore(0x44, value)
            success := call(gas(), token, 0, 0x00, 0x64, 0x00, 0x20)

            if iszero(and(success, eq(mload(0x00), 1))) {

                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }

                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
            mstore(0x60, 0)
        }
    }

    function _safeApprove(IERC20 token, address spender, uint256 value, bool bubble) private returns (bool success) {
        bytes4 selector = IERC20.approve.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(spender, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)

            if iszero(and(success, eq(mload(0x00), 1))) {

                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }

                success := and(success, and(iszero(returndatasize()), gt(extcodesize(token), 0)))
            }
            mstore(0x40, fmp)
        }
    }
}

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
