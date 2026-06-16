# Agentic Stack for Solidity Development 2026

> Companion template for the article: [Agentic Stack for Solidity Development 2026](https://telegra.ph/Agentic-Stack-for-Solidity-Development-2026-06-09) — [@soliditypedia](https://t.me/soliditypedia)

One rule governs every design decision in this repo:

> **AGENTS WRITE. TOOLS VERIFY. HUMANS SIGN.**

---

## The 5 Layers

| Layer | Role | File(s) |
|-------|------|---------|
| **1 — Protocol** | The thing being built | `src/Vault.sol` |
| **2 — Verification** | Toolchain that declares correctness | `foundry.toml`, `slither.config.json`, `aderyn.toml` |
| **3 — Tests** | Constitution the protocol must satisfy | `test/Vault.t.sol`, `test/handlers/VaultHandler.sol`, `test/invariant/VaultInvariant.t.sol` |
| **4 — Agent contract** | What the agent can and cannot do | `CLAUDE.md` |
| **5 — CI gate** | Immutable verification pipeline | `.github/workflows/ci.yml`, `.github/workflows/redteam.yml` |
| **6 — Red team agent** | Autonomous attacker — finds bugs and files issues | `scripts/redteam.py` |

---

## Quick Start

```bash
# Install Foundry: https://getfoundry.sh
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and build
git clone <this-repo> && cd <this-repo>
forge install
forge build
forge test

# Run full CI gate locally
forge fmt --check && forge build && FOUNDRY_PROFILE=ci forge test && slither . && aderyn .
```

**Keys:** Never use `.env` for private keys. Import a keystore:
```bash
cast wallet import deployer --interactive
forge script script/Deploy.s.sol --account deployer --broadcast
```

**MCP (agent tooling):** Copy `.mcp.json.example` → `.mcp.json`, fill in your RPC URL. The agent can then read chain state without touching keys.

---

## Make It Yours

Replace this template in order — invariants first, always.

1. **Rewrite the invariants.** Open `test/invariant/VaultInvariant.t.sol`. Before touching `src/`, decide what must always be true about your protocol. Write those `invariant_*` functions. This is your constitution.

2. **Rewrite the handler.** Update `test/handlers/VaultHandler.sol` to drive your actors through your protocol's state machine.

3. **Replace the contract.** Delete `src/Vault.sol`, write your protocol. The invariant suite will break immediately — that's correct. Fix the implementation until the suite is green.

4. **Update the unit tests.** `test/Vault.t.sol` → your unit + fuzz tests for every external function.

5. **Update the deploy script.** `script/Deploy.s.sol` — constructor args, multi-contract deployments, etc.

6. **Re-run the gate.** `forge fmt --check && forge build && FOUNDRY_PROFILE=ci forge test && slither . && aderyn .`

---

## Red-Team Workflow

### Autonomous red team (CI)

`scripts/redteam.py` is an autonomous agent that runs on every PR touching `src/**`. It:

1. Reads all `src/**/*.sol` files
2. Calls `claude-opus-4-7` with adaptive thinking (security audit system prompt)
3. Returns structured findings (severity, class, location, description, PoC outline, recommendation)
4. Files a GitHub Issue for every Critical / High / Medium finding

**Setup:** add `ANTHROPIC_API_KEY` to your repo's GitHub Actions secrets.

**Run locally:**
```bash
pip install anthropic
python scripts/redteam.py --dry-run   # print findings, no issues filed
python scripts/redteam.py             # print findings + file GitHub Issues
```

### Manual red team (Claude Code session)

To engage the coding agent as an interactive auditor:

```
Act as a smart contract auditor. Assume Vault.sol is broken.
Prioritize: reentrancy, accounting drift, access control, oracle, donation, rounding, griefing.
For each finding: severity, description, PoC forge test added to test/.
```

The agent will:
- Produce findings with severity tags
- Write a PoC test that demonstrates the exploit
- Suggest a fix
- The PoC test becomes a permanent regression in the suite

---

## Repo Structure

```
.
├── src/
│   └── Vault.sol                    # Placeholder protocol (delete me)
├── test/
│   ├── Vault.t.sol                  # Unit + fuzz tests
│   ├── handlers/
│   │   └── VaultHandler.sol         # Invariant handler (multi-actor, ghost vars)
│   └── invariant/
│       └── VaultInvariant.t.sol     # Invariant suite (the constitution)
├── script/
│   └── Deploy.s.sol                 # Deploy script (no keys, keystore only)
├── lib/
│   └── forge-std/                   # Foundry standard library
├── .github/
│   └── workflows/
│       └── ci.yml                   # CI: fmt, build, test, coverage, slither, aderyn
├── CLAUDE.md                        # Agent contract: what it can/cannot do
├── foundry.toml                     # Foundry config (default + ci profiles)
├── remappings.txt                   # Import remappings
├── slither.config.json              # Slither config
├── aderyn.toml                      # Aderyn scope config
├── .env.example                     # Env template — no keys
├── .mcp.json.example                # MCP server config template
└── .gitignore
```

---

## Why This Stack

| Tool | Role |
|------|------|
| **Forge** | Build, unit tests, fuzz tests, invariant tests, coverage |
| **Slither** | Static analysis — catches reentrancy, shadowing, unsafe patterns |
| **Aderyn** | Rust-based AST analyzer — catches a different class of issues |
| **Blockscout MCP** | Agent reads chain state without touching keys |
| **cast wallet** | Human-held encrypted keystore — agent never touches it |

The agent is powerful at the keyboard. The human holds the key. The toolchain is the judge.
