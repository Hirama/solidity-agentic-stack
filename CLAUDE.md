# Agentic Stack for Solidity — CLAUDE.md

## The Rule

> **Agents write. Tools verify. Humans sign.**

- The agent may propose and write code. It never declares code correct — only the toolchain can.
- The toolchain (forge, slither, aderyn) is the authority. A green suite is the definition of done.
- The agent never broadcasts a transaction, never touches a private key, and never edits `.env`.

---

## Commands

```bash
# Build
forge build

# Format (check only — CI gate)
forge fmt --check

# Format (auto-fix)
forge fmt

# Unit + fuzz tests (default profile)
forge test

# Invariant tests only
forge test --match-contract VaultInvariant

# CI profile (higher fuzz/invariant runs)
FOUNDRY_PROFILE=ci forge test

# Coverage
forge coverage --report lcov

# Slither static analysis
slither .

# Aderyn static analysis
aderyn .

# Full definition-of-done gate
forge fmt --check && forge build && FOUNDRY_PROFILE=ci forge test && slither . && aderyn .

# Red team agent (requires ANTHROPIC_API_KEY)
python scripts/redteam.py --dry-run   # print findings, no GitHub Issues
python scripts/redteam.py             # print findings + file GitHub Issues

# Fix agent — patch a specific security issue (requires ANTHROPIC_API_KEY)
python scripts/fix.py --issue 42 --dry-run   # apply fix locally, skip PR
python scripts/fix.py --issue 42             # fix + forge test + open PR
```

---

## Invariants — The Constitution

These invariants MUST hold at all times. Never weaken an invariant to make a test pass.
If an invariant breaks, the protocol is broken — fix the code, not the test.

| ID    | Statement |
|-------|-----------|
| INV-1 | `address(vault).balance == vault.totalDeposits()` |
| INV-2 | `ghost_totalDeposited - ghost_totalWithdrawn == vault.totalDeposits()` |

---

## Hard Rules

### Code quality
- **CEI everywhere.** Checks → Effects → Interactions. No exceptions.
- **Custom errors only.** No `require` strings. Never revert with a bare string.
- **Named imports.** `import {Foo} from "bar/Foo.sol"` — no wildcard imports.
- **Full NatSpec** on every public/external function and error.
- **No `tx.origin` auth**, no `block.timestamp` as randomness, no unbounded loops.

### Testing
- Every external function needs: a unit test (happy path) + every revert path + at least one fuzz test.
- **Never modify a test to make it pass.** Fix the implementation.
- **Never weaken CI gates** (coverage floor, slither fail-on level, etc.).

### Deployment & keys
- **Never broadcast** without explicit human instruction.
- **Never handle private keys.** Use `cast wallet import <name> --interactive` for keystores.
- **Never write to `.env`**. Keys are not stored in environment files — ever.
- Dependencies added only via pinned `forge install <org/repo>@<tag>`. No `npm install` for Solidity.

---

## Definition of Done

The following command must pass — all four tools, no skips, reporting real output not a summary:

```bash
forge fmt --check && forge build && FOUNDRY_PROFILE=ci forge test && slither . && aderyn .
```

Do not declare a task complete until this gate is green.

---

## Security Review Mode

When asked to act as attacker or auditor:

1. Assume the code is broken until proven otherwise.
2. Prioritize these vulnerability classes in order:
   - Reentrancy
   - Accounting drift (balance vs. state desync)
   - Access control gaps
   - Oracle manipulation
   - Donation / force-send attacks
   - Rounding / precision errors
   - Griefing (DoS, gas bombs)
3. For each finding, produce:
   - Severity: Critical / High / Medium / Low / Info
   - Description: what breaks and why
   - PoC: a forge test added to `test/` that demonstrates the exploit and acts as a regression
4. Never suggest "just add a check" without showing the full fix and a passing PoC.
