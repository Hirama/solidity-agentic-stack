# Agentic Stack for Solidity Development 2026

> Companion template for the article: [Agentic Stack for Solidity Development 2026](https://telegra.ph/Agentic-Stack-for-Solidity-Development-2026-06-09) — [@soliditypedia](https://t.me/soliditypedia)

> **AGENTS WRITE. TOOLS VERIFY. HUMANS SIGN.**

---

## The 6 Layers

| Layer | Role | File(s) |
|-------|------|---------|
| **1. Protocol** | The thing being built | `src/Vault.sol` |
| **2. Verification** | Toolchain that declares correctness | `foundry.toml`, `slither.config.json`, `aderyn.toml` |
| **3. Tests** | Constitution the protocol must satisfy | `test/` (unit, fuzz, invariants) |
| **4. Agent contract** | What the agent can and cannot do | `CLAUDE.md` |
| **5. CI gate** | Immutable verification pipeline | `.github/workflows/` |
| **6. Red team agent** | Autonomous attacker — finds bugs, files issues, dispatches fix | `scripts/redteam.py`, `scripts/fix.py` |

---

## Quick Start

```bash
# Install Foundry: https://getfoundry.sh
curl -L https://foundry.paradigm.xyz | bash && foundryup

git clone https://github.com/Hirama/solidity-agentic-stack.git && cd solidity-agentic-stack
forge install
forge test

# Full gate (definition of done)
forge fmt --check && forge build && FOUNDRY_PROFILE=ci forge test && slither . && aderyn .
```

**Keys never live in `.env`.** Use an encrypted keystore:

```bash
cast wallet import deployer --interactive
forge script script/Deploy.s.sol --account deployer --broadcast
```

**MCP:** copy `.mcp.json.example` → `.mcp.json`, fill RPC URL. Agent reads chain state, never touches keys.

---

## Make It Yours

Replace in order — invariants first.

1. Rewrite invariants in `test/invariant/VaultInvariant.t.sol` — your protocol's constitution.
2. Rewrite the handler in `test/handlers/VaultHandler.sol`.
3. Replace `src/Vault.sol` with your protocol. Fix until the invariant suite is green.
4. Update `test/Vault.t.sol` (unit + fuzz) and `script/Deploy.s.sol`.
5. Re-run the gate.

---

## Red-Team Loop

```
redteam.py finds bug → Issue
       ↓
fix.py --issue N → patch → forge test → PR
       ↓
redteam.yml re-runs on PR
       ↓ clean              ↓ new finding
HUMAN MERGES           loop continues
```

Runs on every PR touching `src/**`. Needs `ANTHROPIC_API_KEY` in GitHub Actions secrets.

```bash
python scripts/redteam.py --dry-run    # print findings
python scripts/fix.py --issue 42       # patch + test + PR
```

---

## Why This Stack

Forge tests it. Slither and Aderyn audit it. The red team agent attacks it. The human holds the key.

Agent at the keyboard. Toolchain as judge. Human as signer.
