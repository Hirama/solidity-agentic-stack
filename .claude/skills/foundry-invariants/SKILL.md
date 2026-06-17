---
name: foundry-invariants
description: Design and write Foundry invariant tests — the protocol's constitution. Covers handler pattern, ghost variables, bound() inputs, targetContract/targetSelector, and the INV-1 / INV-2 style accounting checks used in this stack. Use when writing a new invariant suite, debugging an invariant break, or onboarding to this repo's `test/invariant/` directory.
---

# Foundry Invariants

Invariant tests assert properties that **must hold across any sequence of state transitions**. They are the protocol's constitution. If an invariant breaks, the protocol is broken — fix the implementation, never weaken the invariant.

## When to use this skill

- Writing a new invariant suite for a fresh protocol
- Adding an invariant to an existing suite
- Debugging an invariant break (e.g. INV-1 fails after 1024 calls)
- Designing a handler to drive multi-actor state
- Adding ghost variables to track cumulative state
- Onboarding to this repo's `test/invariant/VaultInvariant.t.sol`

## The contract — INV-1 and INV-2 in this stack

```
INV-1: address(vault).balance == vault.totalDeposits()
INV-2: ghost_totalDeposited - ghost_totalWithdrawn == vault.totalDeposits()
```

INV-1 is a **balance ↔ accounting** invariant — catches donation attacks, force-send drift, missing state updates.
INV-2 is a **flow conservation** invariant — catches accounting bugs by reconciling external observations (ghost vars in the handler) against on-chain state.

## Anatomy of an invariant suite

```
test/
├── handlers/
│   └── VaultHandler.sol      # drives actors through the state machine
└── invariant/
    └── VaultInvariant.t.sol  # the invariant_* functions
```

### Handler — drives randomized actions

```solidity
contract VaultHandler is Test {
    Vault public vault;
    address[] public actors;

    // Ghost variables — track cumulative state across calls
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor(Vault _vault) {
        vault = _vault;
        for (uint256 i; i < 5; i++) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
            vm.deal(actors[i], 1_000 ether);
        }
    }

    function deposit(uint256 actorSeed, uint256 amount) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        amount = bound(amount, 1, actor.balance);

        vm.prank(actor);
        vault.deposit{value: amount}();

        ghost_totalDeposited += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);

        vm.prank(actor);
        vault.withdraw(amount);

        ghost_totalWithdrawn += amount;
    }
}
```

### Invariant test — targets the handler

```solidity
contract VaultInvariant is StdInvariant, Test {
    Vault public vault;
    VaultHandler public handler;

    function setUp() public {
        vault = new Vault();
        handler = new VaultHandler(vault);

        targetContract(address(handler));   // only fuzz handler functions
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balanceEqualsTotalDeposits() public view {
        assertEq(address(vault).balance, vault.totalDeposits());
    }

    function invariant_depositedMinusWithdrawnEqualsTotalDeposits() public view {
        assertEq(
            handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn(),
            vault.totalDeposits()
        );
    }
}
```

## Patterns

### `bound(x, min, max)` over `vm.assume`

`bound` reshapes the input into the range; `vm.assume` discards runs. Always prefer `bound` for invariant inputs — assume kills throughput.

### Actor pool

Pre-create N actors in the handler constructor with `makeAddr` + `vm.deal`. Pick one per call via `bound(seed, 0, n-1)`. Single-actor invariants miss multi-user bugs.

### Ghost variables

Track anything the protocol doesn't expose: `ghost_totalDeposited`, `ghost_totalWithdrawn`, `ghost_actorsWithBalance`, per-actor cumulative flows. Then assert relationships between ghosts and on-chain state.

### Target functions only

By default, every external function on every contract is fuzzed — including forge-std internals. Use `targetContract` + `targetSelector` to narrow to handler functions only. Without this, you get noise.

### Skip silently, don't revert

If a precondition fails (e.g. actor has zero balance), return early in the handler. Reverts count against the `reverts:` metric and don't drive coverage.

### Pre/post hooks

```solidity
modifier countCall(bytes32 key) {
    calls[key]++;
    _;
}
```

Track call counts per action to make sure the fuzzer is actually exploring all branches.

## Running

```bash
forge test --match-contract VaultInvariant
FOUNDRY_PROFILE=ci forge test --match-contract VaultInvariant   # higher runs
```

`foundry.toml`:

```toml
[invariant]
runs = 256
depth = 128
fail_on_revert = false   # handler returns early on precondition fail

[profile.ci.invariant]
runs = 1024
depth = 512
```

## Debugging a break

When `forge test` prints:
```
[FAIL: invariant_balanceEqualsTotalDeposits()]
Sequence: ...
```

1. Read the call sequence printed under "Sequence". It's the minimal reproduction.
2. Copy it into a unit test in `test/Vault.t.sol` to lock the regression.
3. Trace through the implementation — the invariant is right, the code is wrong.
4. **Never** weaken the invariant. If the invariant is over-strict, the protocol design is over-strict; redesign instead.

## See also

- `[[foundry-cheatcodes]]` — `vm.prank`, `vm.deal`, `bound` come from `Test.sol`
- Foundry guide: https://getfoundry.sh/guides/invariant-testing
- StdInvariant: https://github.com/foundry-rs/forge-std/blob/master/src/StdInvariant.sol
