// SPDX-License-Identifier: MIT
pragma solidity =0.8.24 ^0.8.20;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
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

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol

// OpenZeppelin Contracts (last updated v5.1.0) (access/Ownable2Step.sol)

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This extension of the {Ownable} contract includes a two-step mechanism to transfer
 * ownership, where the new owner must call {acceptOwnership} in order to replace the
 * old one. This can help prevent common mistakes, such as transfers of ownership to
 * incorrect accounts, or to contracts that are unable to interact with the
 * permission system.
 *
 * The initial owner is specified at deployment time in the constructor for `Ownable`. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     *
     * Setting `newOwner` to the zero address is allowed; this can be used to cancel an initiated ownership transfer.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}

// src/HighScoreRecords.sol

/// @title HighScoreRecords
/// @notice Public onchain score book for Cap's games. Authorized game servers ("writers") record
///         scores per wallet and per bot NFT (nftContract, tokenId), per game and game mode.
///         Best scores only go up; the last score and its timestamp are always updated.
/// @dev    Each writer is bound to exactly one gameId (suggested: 1 = Caphet Arena,
///         2 = Substrate Matrix), so a game server can only write its own game's records.
///         Holds no tokens and pays nothing. No upgradeability.
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

    /// @notice Authorize `writer` for `gameId`, or remove it with gameId = 0.
    function setWriter(address writer, uint32 gameId) external onlyOwner {
        if (writer == address(0)) revert ZeroAddress();
        writerGame[writer] = gameId;
        emit WriterSet(writer, gameId);
    }

    /// @notice Record a wallet's score for the caller's game. `ref` is an optional round / run id.
    function recordWalletScore(address wallet, uint32 mode, uint64 score, bytes32 ref) external {
        uint32 gameId = _gameOf(msg.sender);
        if (wallet == address(0)) revert ZeroAddress();
        (uint64 best, bool newBest) = _write(_walletRecords[wallet][gameId][mode], score);
        emit WalletScore(gameId, mode, wallet, score, best, newBest, ref);
    }

    /// @notice Record a bot NFT's score for the caller's game.
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

    /// @notice Disabled: records must always have an owner who can rotate writers.
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    function _gameOf(address caller) private view returns (uint32 gameId) {
        gameId = writerGame[caller];
        if (gameId == 0) revert NotWriter(caller);
    }

    function _write(Record storage r, uint64 score) private returns (uint64 best, bool newBest) {
        // Safe: block.timestamp fits in uint64 for billions of years.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 nowTs = uint64(block.timestamp);
        r.last = score;
        r.lastAt = nowTs;
        // The first record always counts as a best, even a score of 0, so bestAt is set.
        newBest = score > r.best || r.bestAt == 0;
        if (newBest) {
            r.best = score;
            r.bestAt = nowTs;
        }
        best = r.best;
    }
}
