// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

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
