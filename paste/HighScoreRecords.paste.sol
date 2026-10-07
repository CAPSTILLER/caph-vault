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

contract HighScoreRecords is Ownable2Step {
    struct Record {
        uint64 best;
        uint64 last;
        uint64 bestAt;
        uint64 lastAt;
    }

    mapping(address writer => uint32 gameId) public writerGame;
    mapping(address wallet => mapping(uint32 gameId => mapping(uint32 mode => Record))) private _walletRecords;
    mapping(address nft => mapping(uint256 tokenId => mapping(uint32 gameId => mapping(uint32 mode => Record))))
        private _botRecords;

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

    error NotWriter(address caller);
    error ZeroAddress();
    error RenounceDisabled();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setWriter(address writer, uint32 gameId) external onlyOwner {
        if (writer == address(0)) revert ZeroAddress();
        writerGame[writer] = gameId;
        emit WriterSet(writer, gameId);
    }

    function recordWalletScore(address wallet, uint32 mode, uint64 score, bytes32 ref) external {
        uint32 gameId = _gameOf(msg.sender);
        if (wallet == address(0)) revert ZeroAddress();
        (uint64 best, bool newBest) = _write(_walletRecords[wallet][gameId][mode], score);
        emit WalletScore(gameId, mode, wallet, score, best, newBest, ref);
    }

    function recordBotScore(address nft, uint256 tokenId, uint32 mode, uint64 score, bytes32 ref) external {
        uint32 gameId = _gameOf(msg.sender);
        if (nft == address(0)) revert ZeroAddress();
        (uint64 best, bool newBest) = _write(_botRecords[nft][tokenId][gameId][mode], score);
        emit BotScore(gameId, nft, tokenId, mode, score, best, newBest, ref);
    }

    function walletRecord(address wallet, uint32 gameId, uint32 mode) external view returns (Record memory) {
        return _walletRecords[wallet][gameId][mode];
    }

    function botRecord(address nft, uint256 tokenId, uint32 gameId, uint32 mode) external view returns (Record memory) {
        return _botRecords[nft][tokenId][gameId][mode];
    }

    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    function _gameOf(address caller) private view returns (uint32 gameId) {
        gameId = writerGame[caller];
        if (gameId == 0) revert NotWriter(caller);
    }

    function _write(Record storage r, uint64 score) private returns (uint64 best, bool newBest) {

        uint64 nowTs = uint64(block.timestamp);
        r.last = score;
        r.lastAt = nowTs;

        newBest = score > r.best || r.bestAt == 0;
        if (newBest) {
            r.best = score;
            r.bestAt = nowTs;
        }
        best = r.best;
    }
}
