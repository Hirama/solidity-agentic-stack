---
name: foundry-cheatcodes
description: Reference for Foundry `vm.*` cheatcodes — environment manipulation, pranks, mocks, expectations, fork control, storage manipulation, env/JSON I/O. Use when writing or debugging Forge tests that need to set block state, fake callers, mock external calls, expect reverts/events, or fork mainnet.
---

# Foundry Cheatcodes

`vm.*` cheatcodes are how Forge tests manipulate EVM state and assert behavior. They live in `forge-std/Test.sol` (`Vm` interface). Full reference: https://getfoundry.sh/reference/cheatcodes/overview

## When to use this skill

- Writing a test that needs to fake `msg.sender` (`prank`)
- Asserting a revert (`expectRevert`)
- Asserting an event was emitted (`expectEmit`)
- Mocking an external contract call (`mockCall`)
- Manipulating block context (`warp`, `roll`, `fee`)
- Setting balances or storage directly (`deal`, `store`, `etch`)
- Forking mainnet for integration tests (`createFork`, `selectFork`)
- Reading env vars or JSON in tests/scripts (`envUint`, `parseJson`)

## Cheat sheet — most common

### Block & time

| Cheat | Use |
|-------|-----|
| `vm.warp(uint256)` | Set `block.timestamp` |
| `vm.roll(uint256)` | Set `block.number` |
| `vm.fee(uint256)` | Set `block.basefee` |
| `vm.chainId(uint256)` | Set `block.chainid` |
| `vm.prevrandao(bytes32)` | Set `block.prevrandao` (post-merge) |
| `vm.txGasPrice(uint256)` | Set `tx.gasprice` |

### Caller / pranks

| Cheat | Use |
|-------|-----|
| `vm.prank(addr)` | Next call uses `addr` as `msg.sender` |
| `vm.prank(addr, origin)` | Also set `tx.origin` |
| `vm.startPrank(addr)` | All calls until `stopPrank` |
| `vm.stopPrank()` | End an active prank |
| `vm.readCallers()` | Inspect current prank mode |

### Account state

| Cheat | Use |
|-------|-----|
| `vm.deal(addr, uint256)` | Set ETH balance |
| `vm.store(addr, slot, value)` | Write a storage slot |
| `vm.load(addr, slot)` | Read a storage slot |
| `vm.etch(addr, bytecode)` | Replace bytecode at `addr` |
| `vm.setNonce(addr, uint64)` / `vm.getNonce(addr)` | Nonce control |

### Expectations

| Cheat | Use |
|-------|-----|
| `vm.expectRevert()` | Next call must revert (any reason) |
| `vm.expectRevert(bytes selector)` | Must revert w/ that selector (custom errors) |
| `vm.expectRevert(bytes message)` | Must revert w/ that bytes/string |
| `vm.expectEmit(true, true, true, true)` | Next emit must match |
| `vm.expectCall(addr, calldata)` | A specific external call must happen |

### Mocking

| Cheat | Use |
|-------|-----|
| `vm.mockCall(addr, calldata, return)` | Mock a call to return fixed data |
| `vm.mockCalls(addr, calldata, [returns])` | Different return each time |
| `vm.mockCallRevert(addr, calldata, revertData)` | Force a revert |
| `vm.clearMockedCalls()` | Remove all mocks |

### Forking

| Cheat | Use |
|-------|-----|
| `vm.createFork(rpcUrl)` | Create fork, returns id |
| `vm.createSelectFork(rpcUrl)` | Create + activate |
| `vm.selectFork(id)` | Switch active fork |
| `vm.rollFork(uint256)` | Set block on active fork |
| `vm.makePersistent(addr)` | Address survives fork switches |

### Events & state recording

| Cheat | Use |
|-------|-----|
| `vm.recordLogs()` | Start capturing emitted events |
| `vm.getRecordedLogs()` | Drain captured events |
| `vm.record()` / `vm.accesses(addr)` | Capture storage reads/writes |
| `vm.startStateDiffRecording()` / `vm.stopAndReturnStateDiff()` | Diff state changes |

### Env / JSON / FS (script-friendly)

| Cheat | Use |
|-------|-----|
| `vm.envUint("KEY")` / `envAddress` / `envString` / `envBytes32` | Read env vars |
| `vm.envOr("KEY", default)` | Env w/ fallback |
| `vm.parseJson(json, ".path")` | Extract value |
| `vm.writeJson(serialized, path)` | Write |
| `vm.ffi(string[] cmd)` | Shell out (needs `ffi = true`) |

### Snapshots (gas + state)

| Cheat | Use |
|-------|-----|
| `vm.snapshotState()` / `vm.revertToState(id)` | Save & restore EVM state |
| `vm.snapshotGas(name)` | Capture gas to file |

## Idiomatic patterns

### Revert assertion w/ custom error

```solidity
error Unauthorized();

vm.expectRevert(Unauthorized.selector);
target.restrictedCall();
```

### Pranked deposit

```solidity
address user = makeAddr("user");
vm.deal(user, 10 ether);

vm.prank(user);
vault.deposit{value: 1 ether}();
```

### Mock an oracle

```solidity
vm.mockCall(
    address(oracle),
    abi.encodeWithSelector(IOracle.latestPrice.selector),
    abi.encode(uint256(2000e8))
);
```

### Event emission

```solidity
vm.expectEmit(true, true, false, true, address(vault));
emit Deposited(user, 1 ether);
vault.deposit{value: 1 ether}();
```

### Fork test (mainnet integration)

```solidity
uint256 fork = vm.createSelectFork(vm.envString("RPC_MAINNET"));
vm.rollFork(20_000_000);
// now interact with deployed contracts at that block
```

### Storage write (force a state)

```solidity
// Slot 0 of Vault.totalDeposits
vm.store(address(vault), bytes32(uint256(0)), bytes32(uint256(100 ether)));
```

## Gotchas

- `expectRevert` only checks the **next external call**, not internal reverts inside the same frame.
- `prank` does NOT survive across external calls that re-enter your test. Use `startPrank` for sustained context.
- `mockCall` matches calldata *prefix* — partial matches are possible. Use exact `abi.encodeCall` to avoid surprises.
- `vm.deal` does not adjust `vault.totalDeposits()` — it only changes ETH balance. Mixing the two can break INV-1.
- `ffi` must be enabled in `foundry.toml` (`ffi = true`); off by default for safety.
- `expectEmit` flags: `(checkTopic1, checkTopic2, checkTopic3, checkData [, emitter])` — get the booleans wrong and silent passes happen.

## See also

- `[[foundry-invariants]]` — invariant testing patterns w/ handler + ghost vars
- `[[foundry-cast]]` — CLI counterparts (`cast call`, `cast storage`, `cast send`)
- Full cheatcode reference: https://getfoundry.sh/reference/cheatcodes/overview
- Forge std assertions: https://getfoundry.sh/reference/forge-std/std-assertions
