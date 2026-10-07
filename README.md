# CAPH Vault

Onchain token vault and score book for Cap's games on Base mainnet:

- **Caphet Arena** ([arena.gearup.wtf](https://arena.gearup.wtf), repo `CAPSTILLER/caphet-arena`)
- **Substrate Matrix** (agent high-score probe-and-claim game, not built yet)

Two contracts, Solidity 0.8.24, OpenZeppelin 5.7.0, Foundry. No proxies, no upgradeability, no mint, no burn.

| Contract | What it does |
| --- | --- |
| `src/CAPHVault.sol` | Holds $CAPH. Anyone can fund it. Approved game addresses pay players, route fees to the treasury, and pull player antes, inside per-game and global daily caps. Owner can pause, set caps, and (only while paused) pull funds to the owner or treasury. |
| `src/HighScoreRecords.sol` | Public score book. Authorized game servers write per-wallet and per-bot-NFT scores per game and mode. Best only goes up; last score and timestamp always update. Events for indexers and agents. |

Token: $CAPH (CAPhet) `0x1D1bCD1459259429ACcde23e24E1782f83e97bA3` on Base, 18 decimals, total supply 100,000,000,000 CAPH. All amounts in the contracts are in wei (1 CAPH = `1000000000000000000`).

**Deploying?** Read [`BANKR_HANDOFF.md`](BANKR_HANDOFF.md).

## Layout

```
src/                     contracts (the source of truth)
test/                    Foundry tests (unit, fuzz, Base fork test)
script/Deploy.s.sol      deploy script (defaults = Base mainnet values, env overrides)
flat/*.flat.sol          forge flatten output, full comments, single file per contract
paste/*.paste.sol        same single file with comments stripped (deploy or verify from this)
paste/*.core.sol         just the contract, comments stripped, imports OpenZeppelin (for reading in chat)
verify/*.json            Standard JSON input for BaseScan verification
abi/*.json               ABIs for game servers and indexers
scripts/make-paste.mjs   regenerates paste/ from flat/
```

`flat/` and `paste/` compile to byte-for-byte the same runtime bytecode as `src/` (checked with `bytecode_hash = "none"`).

## Build and test

```
forge install            # if lib/ is empty (git submodules)
forge build
forge test               # 73 tests; the fork test is skipped without an RPC
BASE_RPC_URL=https://mainnet.base.org forge test --match-contract Fork   # real CAPH on a Base fork
forge coverage --no-match-coverage "test|script"
```

Regenerate the single-file copies after any change:

```
forge flatten src/CAPHVault.sol -o flat/CAPHVault.flat.sol
forge flatten src/HighScoreRecords.sol -o flat/HighScoreRecords.flat.sol
node scripts/make-paste.mjs
```

## How the vault works

- **Day** = UTC day = `block.timestamp / 1 days`. Counters are stored per day number, so they reset at 00:00 UTC with no keeper.
- **Funding:** `deposit(amount, ref)` after approving the vault. The vault records the amount it actually received (balance before and after), so a fee-on-transfer token could never inflate it. A plain CAPH transfer to the vault also works, it just has no vault event. Deposits stay open while paused.
- **Games:** the owner calls `setGame(game, dailyCap, maxPerPayout)`. A game is any address: a server hot wallet or a game contract.
  - `payout(to, amount, ref)` pays a player.
  - `sendFeeToTreasury(amount, ref)` routes a fee (for example the Arena fall fee) from the vault to the treasury.
  - `pullFrom(player, amount, ref)` pulls an ante from a player who approved the vault.
- **Caps:** every payout and fee must fit the game's `maxPerPayout`, the game's `dailyCap`, the `globalDailyCap`, and the vault balance. Fees count toward the same caps as payouts. Pulls are capped by `maxPerPayout` and do not use up the daily payout caps.
- **Refs:** every game call carries a non-zero `ref` that can only be used once per game, so a retried transaction cannot pay or charge twice. Suggested refs: `keccak256("<roundId>:ante")`, `keccak256("<roundId>:payout")`, `keccak256("<roundId>:fee")`; for an NFT bot daily claim `keccak256(abi.encode(nftContract, tokenId, dayNumber))`, which also makes "one claim per bot per UTC day" an onchain rule.
- **Pause:** blocks `payout`, `sendFeeToTreasury`, and `pullFrom`. Deposits, owner settings, and `emergencyWithdraw` keep working.
- **Views:** `vaultBalance()`, `today()`, `globalRemainingToday()`, `gameRemainingToday(game)`, `maxPayoutNow(game)`, plus public `games`, `paidOnDay`, `gamePaidOnDay`, `refUsed`, `treasury`, `globalDailyCap`, `paused`, `owner`, `pendingOwner`.

## How the records work

- Owner calls `setWriter(writer, gameId)`; `gameId = 0` removes a writer. Suggested ids: `1` Caphet Arena, `2` Substrate Matrix. A writer can only write records for its own game.
- `recordWalletScore(wallet, mode, score, ref)` and `recordBotScore(nftContract, tokenId, mode, score, ref)`.
- Each record stores `best`, `last`, `bestAt`, `lastAt` (one storage slot). `best` never goes down.
- Events: `WalletScore(gameId, mode, wallet, score, best, newBest, ref)` and `BotScore(gameId, nft, tokenId, mode, score, best, newBest, ref)`.
- Reads: `walletRecord(wallet, gameId, mode)`, `botRecord(nft, tokenId, gameId, mode)`, `writerGame(writer)`.

## Arena rules this was built against

From the caphet-arena repo (`src/ledger.ts`, `src/fees.ts`, `src/nft/rules.ts`, `contracts/README_FOR_BANKR.md`):

- Ante = the wallet's best score, capped at 10,000 CAPH, paid wallet to vault at round start. First play per wallet is free (ante 0).
- Cash out: the vault pays the score, at most 10,000 CAPH per payout.
- Fall: the ante stays in the vault; fall fee = ceil(5% of all coins on the table) whole CAPH, paid vault to treasury.
- NFT bot daily payouts 10 / 20 / 50 / 100 CAPH by rarity, server-attested.
- Vault limits 500,000 CAPH per day and 10,000 CAPH per payout. Cap funds the vault himself.
- Results are server-signed with replays offchain; seeds are commit-reveal.

## Security notes

- Tests: 73 unit and fuzz tests plus one Base fork test against the real CAPH token. 100% line and function coverage on both contracts.
- Slither: no findings above informational except two "strict equality" and one "timestamp" notes, all intended (`received == 0` check and the first-record check in `_write`).
- Trust model: nothing proves onchain that a payout was earned. Each game key is trusted up to its caps; the owner can pause instantly and remove a game.
- A compromised game key can pull up to `maxPerPayout` per call from any player who left an allowance on the vault. Players (or the Arena UI) should approve only the ante for the round, or pay the ante themselves with `deposit(ante, ref)`.
