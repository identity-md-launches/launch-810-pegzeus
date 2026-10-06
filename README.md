# Pegzeus (PEGZEUS)

Pegzeus is a fixed-supply ERC-20. Every successful transfer credits the full
requested amount to the recipient. There are no transfer fees, taxes, burns,
rebases, trading restrictions, or special launch exemptions.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/Pegzeus.sol:Pegzeus` |
| Name | `Pegzeus` |
| Symbol | `PEGZEUS` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`, encoded as `0x`) |
| Deployment value | `0` |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, `200` runs |
| Bytecode metadata hash | `none` |

The constructor mints the entire supply once and emits the standard mint
`Transfer` event. Direct deployment assigns it to the deploying account; factory
deployment assigns it to the factory, never to `tx.origin`. No initialization
call is needed. There is no owner, admin, post-deployment mint or burn entrypoint,
pause, blacklist, seizure, upgrade, proxy, or rescue function.

## Build and check

With Foundry and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

All imported Solidity sources and their licenses are ordinary files in `lib/`:
OpenZeppelin Contracts **v5.1.0** (only ERC-20 and its transitive dependencies)
and forge-std **v1.9.7** (test utilities). Archive URLs and SHA-256 digests are
recorded in `lib/DEPENDENCIES.txt`. There are no submodules or package-install
steps. Once the pinned compiler and Foundry are installed, builds and tests need
no network. FFI and filesystem cheatcode permissions are disabled.

Tests cover metadata, mint events, CREATE2 deployment to a factory, exact
transfers, whole-supply transfers, zero/self transfers, contract recipients,
approval replacement and revocation, finite/unlimited allowance spending,
unauthorized spending, invalid addresses, and atomic rollback after failed
transfers. They also check common prohibited administrative entrypoints and
scan deployed bytecode for forbidden opcodes.

Fuzz tests cover transfer conservation, exact delegated transfers, zero-address
rejection, and excessive spending. A stateful invariant suite compares balances
and allowances against an independent four-holder model over mixed transfer,
approval, and delegated-transfer sequences (128 runs, depth 64). Tests use local
state only, without environment variables, forks, RPC calls, or files.

The launch-flow test checks full delivery from a factory to a distributor,
claimant, pool address, and requester, plus transfers into and out of the pool
address. Its 50% pool allocation is only a test fixture, not a deployment
parameter. It does not execute Uniswap swaps. The supplied protected harness
belongs to the launch infrastructure and additionally needs its factory/pool
contracts, manifest, and environment configuration; it is not part of the local
test run.

## Deployment handoff

The reviewed creation bytecode and ABI can be obtained without broadcasting:

```sh
forge inspect src/Pegzeus.sol:Pegzeus bytecode
forge inspect src/Pegzeus.sol:Pegzeus abi
```

The launch operator should use that creation bytecode with no appended arguments
and no ETH. The intended factory must execute CREATE or CREATE2 itself to
receive the full supply. For CREATE2, the operator supplies the factory and salt;
neither is embedded in this token's constructor. A helper that executes CREATE
would itself receive the tokens, so select the deployment path deliberately.

The token portion of a future launch manifest is:

```json
{
  "contract": "src/Pegzeus.sol:Pegzeus",
  "name": "Pegzeus",
  "symbol": "PEGZEUS",
  "decimals": 18,
  "constructorArgs": [],
  "totalSupply": "1000000000000000000000000000"
}
```

This is token metadata, not a complete launch manifest. Chain, factory, CREATE2
salt, paired currency, pool fee/ticks, initial price/cap, pool allocation, and
remainder recipient are outside this token's parameters and must be supplied
by the launch operator. No application contracts are required. The factory
handles the network's distribution and liquidity allocations after deployment;
the token constructor performs no allocations beyond minting to its caller.

The operator is responsible for choosing a Cancun-compatible chain, matching
the pinned build settings, checking deployed code and metadata, confirming the
factory initially owns exactly `10^27` units, performing the authorized
distribution, and publishing verified source. This project contains no wallet
keys and performs no broadcast transactions.

## Assumptions and operation

- Standard ERC-20 allowance semantics apply. `approve` replaces the allowance;
  zero revokes it. A maximum `uint256` allowance remains unchanged when spent.
  Prefer limited approvals; when replacing a live allowance, first revoke it
  and confirm that transaction to reduce the standard approval race risk.
- Successful `transfer`, `transferFrom`, and `approve` return `true`; invalid
  operations revert with OpenZeppelin's ERC-6093 errors. Zero-value transfers
  between nonzero addresses are valid and emit `Transfer`. Transfers and
  approvals to the zero address are rejected.
- Transfers emit `Transfer`, and direct approvals emit `Approval`. Following
  OpenZeppelin v5 behavior, spending an allowance does not emit `Approval`;
  indexers should query `allowance` when tracking its current value.
- Transfers perform no external callbacks. Recipients need to support holding
  and returning ERC-20 tokens; sending to an incompatible contract or the token
  contract itself can strand tokens. There is no recovery administrator.
- Holders are responsible for custody, recipient selection, and approvals.
  There is no ongoing privileged maintenance or emergency control. Despite
  its name, Pegzeus implements no price peg, collateral, or redemption promise.

Review against the supplied security reference focused on supply conservation,
authorization through allowances, invalid addresses, external calls, and
privileged capabilities. This token has no oracle, signature, randomness,
vault, or upgrade logic. Foundry build, unit/fuzz/invariant tests, and formatting
checks are the local validation; Slither and Mythril were not run. This is not
an independent security audit. The launch operator should arrange the separate
adversarial review before release.
