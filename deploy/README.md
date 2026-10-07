# Pre-compiled deploy payloads for Bankr

Bankr's compile sandbox was down (`bankr-staging-cli-sandbox` missing). These files are the creation bytecode plus constructor args so `deploy_contract` can run without compiling.

## Compiler settings (must match verification)

| Setting | Value |
| --- | --- |
| Compiler | solc 0.8.24 |
| Optimizer | enabled, 200 runs |
| EVM version | cancun |
| Metadata bytecode hash | none |
| License | MIT |

Built with Foundry from `src/` (same bytecode as `paste/*.paste.sol`).

## Files

| File | Contents |
| --- | --- |
| `CAPHVault.creation.hex` | Creation bytecode only (no constructor args), `0x`-prefixed |
| `CAPHVault.constructor-args.hex` | ABI-encoded constructor args, `0x`-prefixed |
| `CAPHVault.deploy-data.hex` | Creation bytecode with args appended (full CREATE payload) |
| `CAPHVault.json` | Trimmed Foundry artifact: `abi`, `bytecode.object`, `deployedBytecode.object`, `metadata` |
| Same set for `HighScoreRecords` | |

## Constructor args (plain form)

### CAPHVault `(IERC20 caph_, address initialOwner, address treasury_, uint256 globalDailyCap_)`

| # | Name | Value |
| --- | --- | --- |
| 1 | `caph_` | `0x1D1bCD1459259429ACcde23e24E1782f83e97bA3` ($CAPH on Base) |
| 2 | `initialOwner` | `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` (Cap's Ledger) |
| 3 | `treasury_` | `0xCF1ac98565DA846E8263604b49C1276Ed78A0981` |
| 4 | `globalDailyCap_` | `500000000000000000000000` (500,000 CAPH, 18 decimals) |

### HighScoreRecords `(address initialOwner)`

| # | Name | Value |
| --- | --- | --- |
| 1 | `initialOwner` | `0xD8382719b8fF90eE3Dd521B9d7c5dc23E8e4EAca` (Cap's Ledger) |

## Deploy-data hashes (raw bytecode bytes, no trailing newline)

| File | Bytes | SHA-256 | Keccak-256 |
| --- | --- | --- | --- |
| `CAPHVault.deploy-data.hex` | 7379 | `d419a1554633048b30be9cfaa92dc1864f8c12cebd99de8fd4bc3b49e8f981c8` | `0x3f0cf5fcd306e8c9db17a4fdcca3b3df1da529f9316632bb0762c3546f6b4989` |
| `HighScoreRecords.deploy-data.hex` | 2819 | `c4e8b09a39990c60c7468554f9fd82e62ceb71f2c94db11aef964b195f1c34d3` | `0x1a032721eecb7846d88c997e3156eb8551beb12b68b4e6db97097f0ef943111d` |

## Note for Bankr

1. Deploy each `*.deploy-data.hex` as a plain contract creation (`CREATE`) from any funded deployer. Send **no value**. The constructor sets `owner` to Cap's Ledger, so the deployer gets no powers.
2. After deploy, verify on BaseScan with the Standard JSON inputs in `verify/CAPHVault.standard-input.json` and `verify/HighScoreRecords.standard-input.json`, using the constructor args above (or the `*.constructor-args.hex` files).
3. Raw GitHub URLs (after this commit lands on `main`):
   - `https://raw.githubusercontent.com/CAPSTILLER/caph-vault/main/deploy/CAPHVault.deploy-data.hex`
   - `https://raw.githubusercontent.com/CAPSTILLER/caph-vault/main/deploy/HighScoreRecords.deploy-data.hex`
