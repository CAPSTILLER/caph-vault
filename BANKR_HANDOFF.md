# BANKR handoff: CAPHVault + HighScoreRecords (Base mainnet)

Two independent contracts. Deploy `CAPHVault` first, then `HighScoreRecords` (order does not matter, neither references the other). The deployer wallet gets **no rights** in either; the owner (Cap's Ledger `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca`) is set in the constructor, so Bankr can deploy from any funded wallet.

Do not send CAPH or ETH as part of deployment. Cap funds the vault himself afterwards. Plain ETH sends to either contract revert.

## Compiler settings (use exactly these to match verification)

| Setting | Value |
| --- | --- |
| Compiler | `solc 0.8.24` |
| Optimizer | enabled, `200` runs |
| EVM version | `cancun` |
| Metadata bytecode hash | `none` |
| License | MIT |

## 1. CAPHVault: constructor arguments, in order

| # | Name | Type | Value | Meaning |
| --- | --- | --- | --- | --- |
| 1 | `caph_` | address | `0x1D1bCD1459259429ACcde23e24E1782f83e97bA3` | $CAPH token on Base (18 decimals) |
| 2 | `initialOwner` | address | `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` | Cap's Ledger cold wallet (same owner as GearVault, used through Rabby) |
| 3 | `treasury_` | address | `0xCF1ac98565DA846E8263604b49C1276Ed78A0981` | Cap's GEAR treasury, receives fees (confirmed by Cap) |
| 4 | `globalDailyCap_` | uint256 | `500000000000000000000000` | 500,000 CAPH per UTC day, all games together |

One line, for tools that take a comma list:

```
0x1D1bCD1459259429ACcde23e24E1782f83e97bA3,0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca,0xCF1ac98565DA846E8263604b49C1276Ed78A0981,500000000000000000000000
```

ABI-encoded (append to creation bytecode, or paste into BaseScan "Constructor Arguments"):

```
0000000000000000000000001d1bcd1459259429accde23e24e1782f83e97ba3000000000000000000000000d8382719b8ff90ee3dd521b9d7c5dc23e8e4eaca000000000000000000000000cf1ac98565da846e8263604b49c1276ed78a09810000000000000000000000000000000000000000000069e10de76676d0800000
```

## 2. HighScoreRecords: constructor arguments, in order

| # | Name | Type | Value |
| --- | --- | --- | --- |
| 1 | `initialOwner` | address | `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` |

ABI-encoded:

```
000000000000000000000000d8382719b8ff90ee3dd521b9d7c5dc23e8e4eaca
```

## Source files to use

| Use | CAPHVault | HighScoreRecords |
| --- | --- | --- |
| Single file, no comments (deploy / verify from this) | `paste/CAPHVault.paste.sol` | `paste/HighScoreRecords.paste.sol` |
| Single file, full comments | `flat/CAPHVault.flat.sol` | `flat/HighScoreRecords.flat.sol` |
| BaseScan "Standard JSON input" verification | `verify/CAPHVault.standard-input.json` | `verify/HighScoreRecords.standard-input.json` |
| ABI | `abi/CAPHVault.json` | `abi/HighScoreRecords.json` |
| Short review copy (imports OpenZeppelin, not deployable alone) | `paste/CAPHVault.core.sol` | `paste/HighScoreRecords.core.sol` |

All single-file versions compile to the same runtime bytecode as `src/`. Contract names: `CAPHVault`, `HighScoreRecords`.

## Option A: deploy with Foundry (this repo)

```
git clone --recursive https://github.com/CAPSTILLER/caph-vault && cd caph-vault
forge test                                    # expect 73 passed, 1 skipped
export BASE_RPC_URL=https://mainnet.base.org
export BASESCAN_API_KEY=<your key>
# dry run, sends nothing:
forge script script/Deploy.s.sol --rpc-url base
# real deployment (only when Cap says go), with your own signer flags:
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify <--account ... | --ledger | ...>
```

A dry run on a Base fork (done before handoff) estimated about 2.86M gas for both contracts, roughly 0.00003 ETH at current Base fees. The script's defaults are the values above. Override with env vars `CAPH_TOKEN`, `OWNER_ADDRESS`, `TREASURY_ADDRESS`, `GLOBAL_DAILY_CAP` if Cap changes any of them.

## Option B: any other tool

Compile `paste/CAPHVault.paste.sol` and `paste/HighScoreRecords.paste.sol` with the settings above, deploy with the constructor arguments above, then verify on BaseScan with the matching Standard JSON input from `verify/` (or `forge verify-contract`).

## 3. After deploy: owner setup (signed from the Ledger via Rabby)

The owner is Cap's Ledger `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca`. Every owner call below (`setGame`, `setWriter`, and later `pause`, `setTreasury`, caps, `emergencyWithdraw`) must be signed by Cap from the Ledger through Rabby. Bankr's deployer wallet cannot make these calls. The `cast send` lines show the exact function and arguments to enter in Rabby (or run them with `--ledger` on a machine with the Ledger attached).

Game addresses are not known yet, so no game is approved at deploy. Payouts are impossible until the owner calls `setGame`. Cap provides each game's server signer address.

Suggested starting caps (**Cap to confirm**), amounts in wei:

| Game | Address | `dailyCap` | `maxPerPayout` |
| --- | --- | --- | --- |
| Caphet Arena server signer | `<ARENA_SIGNER>` | `400000000000000000000000` (400,000) | `10000000000000000000000` (10,000) |
| Substrate Matrix server signer | `<SUBSTRATE_SIGNER>` | `100000000000000000000000` (100,000) | `1000000000000000000000` (1,000) |
| Optional: NFT bot daily claims signer | `<NFT_CLAIM_SIGNER>` | `30000000000000000000000` (30,000) | `100000000000000000000` (100) |

```
# vault
cast send <VAULT> "setGame(address,uint256,uint256)" <ARENA_SIGNER> 400000000000000000000000 10000000000000000000000
cast send <VAULT> "setGame(address,uint256,uint256)" <SUBSTRATE_SIGNER> 100000000000000000000000 1000000000000000000000
# records (gameId 1 = Caphet Arena, 2 = Substrate Matrix)
cast send <RECORDS> "setWriter(address,uint32)" <ARENA_SIGNER> 1
cast send <RECORDS> "setWriter(address,uint32)" <SUBSTRATE_SIGNER> 2
```

Cap funds the vault (any wallet):

```
cast send 0x1D1bCD1459259429ACcde23e24E1782f83e97bA3 "approve(address,uint256)" <VAULT> <AMOUNT_WEI>
cast send <VAULT> "deposit(uint256,bytes32)" <AMOUNT_WEI> 0x0000000000000000000000000000000000000000000000000000000000000000
```

(A plain CAPH transfer to the vault address also works.)

## 4. Checks after deploy (send these back to Cap)

| Read | Expected |
| --- | --- |
| `CAPHVault.owner()` | `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` |
| `CAPHVault.caph()` | `0x1D1bCD1459259429ACcde23e24E1782f83e97bA3` |
| `CAPHVault.treasury()` | `0xCF1ac98565DA846E8263604b49C1276Ed78A0981` |
| `CAPHVault.globalDailyCap()` | `500000000000000000000000` |
| `CAPHVault.paused()` | `false` |
| `CAPHVault.pendingOwner()` | `0x0000000000000000000000000000000000000000` |
| `HighScoreRecords.owner()` | `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` |

Send back: both contract addresses, deploy transaction hashes, block numbers, and BaseScan verification links.

## What the owner can and cannot do (plain English)

**The owner CAN:**

- Approve a game address, change its daily cap and per-payout cap, or remove it.
- Change the global daily cap.
- Change the treasury address that receives fees.
- Pause and unpause. Pause stops all game payouts, fees, and ante pulls immediately. Deposits stay open.
- While paused, and only while paused, withdraw CAPH from the vault, and only to the owner wallet or the treasury. Every withdrawal emits `EmergencyWithdraw`.
- Return a non-CAPH token that someone sent to the vault by mistake (`rescueToken`).
- Hand ownership to a new wallet in two steps (`transferOwnership`, then the new wallet calls `acceptOwnership`).
- In HighScoreRecords: add, move, or remove score writers.

**The owner CANNOT:**

- Withdraw CAPH while the vault is running. It must pause first, which is public onchain. (In practice the owner can pause and withdraw back to back, so the owner key is still the master key. Protect it.)
- Send vault CAPH to any address other than the owner or treasury, except through an approved game's capped payouts.
- Pay players directly. Only approved games can, and only inside the caps.
- Mint, burn, upgrade, or self-destruct anything. There is no proxy and no hidden function.
- Renounce ownership (disabled, so the vault can never end up ownerless and unpausable).
- Lower a score in HighScoreRecords or write scores itself (unless it adds its own address as a writer, which emits `WriterSet`).

**An approved game CAN:** pay players, route fees to the treasury, and pull antes from players who approved the vault, each call within `maxPerPayout`, with payouts plus fees within its own daily cap and the global daily cap, each `ref` only once. **It CANNOT** change settings, withdraw, unpause, or exceed its caps.

## Decisions for Cap

1. **Owner wallet (decided).** Cap's Ledger `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` (a plain EOA onchain, same owner as GearVault) owns both contracts. All owner calls are signed from the Ledger via Rabby. Each game server signer stays a separate hot wallet, like the GearVault operator.
2. **Treasury (decided).** `0xCF1ac98565DA846E8263604b49C1276Ed78A0981`, kept as Cap confirmed. Changeable later by the owner with `setTreasury` (signed from the Ledger).
3. **Caps per game.** Suggested Arena 400,000/day with 10,000 per payout, Substrate 100,000/day with 1,000 per payout, inside the 500,000 global cap. Substrate numbers are placeholders until the game exists.
4. **NFT bot daily claims.** Recommend a separate signer registered as its own "game" with `maxPerPayout = 100 CAPH` (the mythic amount) and a daily cap near what 1,000 bots can claim (average about 23.5 CAPH per bot, so about 23,500/day; 30,000 suggested). Routing claims through the Arena signer would allow 10,000 per call instead of 100.
5. **Antes go into the vault** (matches the Arena ledger: `walletToVault`). Nothing is burned. If you want antes burned instead, say so; the vault has no burn by design.
6. **Fees count toward the daily caps** (the fall fee uses up part of the Arena daily budget). Fall fees are small (at most 6 CAPH at the 120-coin limit) so this barely matters, but it keeps the rule "a game can move at most X per day" simple.
7. **How antes arrive.** Either the game calls `pullFrom(player, ante, ref)` (player approves the vault first) or the player calls `deposit(ante, ref)` directly and the server watches the event. The second is safer for players because no standing allowance is left for a server key to misuse. If using `pullFrom`, the UI should approve only the round's ante.
8. **Per-wallet daily cap.** GearVault has an optional per-wallet daily cap; this vault does not (kept simple, and per-bot uniqueness is enforced with refs). Easy to add before deploy if you want it.
9. **Records overlap.** The caphet-arena repo already has `GameRecords` (per-round records, Arena only). `HighScoreRecords` is the shared best/last score book for both games and bot NFTs. Deploy both, or only this one if per-round records are not needed onchain.
10. **Token facts checked onchain:** CAPH is a Doppler ERC-20 clone (EIP-1167, not upgradeable), 18 decimals, supply 1e29 wei, no transfer fee, balance limit off. A Base fork test ran deposit, payout, and fee against the real token successfully.
