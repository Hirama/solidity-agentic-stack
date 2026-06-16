#!/usr/bin/env python3
"""
Red team agent: reads src/**/*.sol, calls Claude API to audit for vulnerabilities,
and files GitHub Issues for each Critical/High/Medium finding.

Usage:
    python scripts/redteam.py              # Audit and create GitHub Issues
    python scripts/redteam.py --dry-run   # Print findings without creating issues

Requires:
    pip install anthropic
    ANTHROPIC_API_KEY env var
    GH_TOKEN / GITHUB_TOKEN env var (for issue creation)
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import anthropic

SEVERITY_LABELS = {
    "Critical": "severity:critical",
    "High": "severity:high",
    "Medium": "severity:medium",
}

SYSTEM_PROMPT = """\
You are a senior smart contract security auditor with deep expertise in EVM, Solidity, and DeFi.

Audit the provided Solidity source files. Assume the code is broken until proven otherwise.

Prioritize vulnerability classes in this order:
1. Reentrancy (cross-function, cross-contract, read-only reentrancy)
2. Accounting drift (balance vs. state desync, donation / force-send attacks)
3. Access control gaps (missing modifiers, tx.origin auth, privilege escalation)
4. Oracle manipulation (price manipulation, flash loans, TWAP staleness)
5. Rounding and precision errors (integer truncation, fee calculation loss)
6. Griefing and DoS (unbounded loops, gas bombs, front-running, block stuffing)
7. Unsafe external calls (unchecked return values, arbitrary delegatecall)
8. Logic errors (off-by-one, incorrect accounting, broken state machine)

For every finding output exactly these fields:
- id: F-01, F-02, etc.
- severity: Critical | High | Medium | Low | Info
- class: the class name from the list above
- location: filename:function_name (or filename:line_number)
- description: what is broken and why it matters
- poc_outline: step-by-step attacker walkthrough
- recommendation: concrete fix

Report all severity levels including Info. The human reviewer triages.
If no issues exist, return an empty findings array.\
"""

FINDINGS_SCHEMA = {
    "type": "object",
    "properties": {
        "findings": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "severity": {"type": "string"},
                    "class": {"type": "string"},
                    "location": {"type": "string"},
                    "description": {"type": "string"},
                    "poc_outline": {"type": "string"},
                    "recommendation": {"type": "string"},
                },
                "required": [
                    "id",
                    "severity",
                    "class",
                    "location",
                    "description",
                    "poc_outline",
                    "recommendation",
                ],
                "additionalProperties": False,
            },
        }
    },
    "required": ["findings"],
    "additionalProperties": False,
}


def load_sources(src_dir: Path) -> dict[str, str]:
    sources = {}
    for path in sorted(src_dir.rglob("*.sol")):
        sources[str(path.relative_to(src_dir.parent))] = path.read_text()
    return sources


def build_user_message(sources: dict[str, str]) -> str:
    parts = ["Audit these Solidity contracts for security vulnerabilities.\n"]
    for filename, content in sources.items():
        parts.append(f"=== {filename} ===\n{content}\n")
    return "\n".join(parts)


def run_audit(sources: dict[str, str]) -> list[dict]:
    client = anthropic.Anthropic()

    response = client.messages.create(
        model="claude-opus-4-7",
        max_tokens=16000,
        thinking={"type": "adaptive"},
        output_config={
            "effort": "high",
            "format": {
                "type": "json_schema",
                "schema": FINDINGS_SCHEMA,
            },
        },
        system=[
            {
                "type": "text",
                "text": SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }
        ],
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": build_user_message(sources),
                        "cache_control": {"type": "ephemeral"},
                    }
                ],
            }
        ],
    )

    text_block = next((b for b in response.content if b.type == "text"), None)
    if not text_block:
        print("ERROR: no text block in API response", file=sys.stderr)
        return []

    try:
        data = json.loads(text_block.text)
    except json.JSONDecodeError as e:
        print(f"ERROR: could not parse JSON response: {e}", file=sys.stderr)
        print(f"Raw text: {text_block.text[:500]}", file=sys.stderr)
        return []

    cache_read = getattr(response.usage, "cache_read_input_tokens", 0)
    cache_write = getattr(response.usage, "cache_creation_input_tokens", 0)
    print(
        f"  tokens: {response.usage.input_tokens} in "
        f"(+{cache_read} cache hit, +{cache_write} cache write), "
        f"{response.usage.output_tokens} out"
    )

    return data.get("findings", [])


def print_findings(findings: list[dict]) -> None:
    if not findings:
        print("\nNo findings.")
        return
    for f in findings:
        print(f"\n{'─'*60}")
        print(f"[{f['severity']}] {f['id']} — {f['class']}")
        print(f"Location : {f['location']}")
        print(f"\nDescription:\n{f['description']}")
        print(f"\nPoC Outline:\n{f['poc_outline']}")
        print(f"\nRecommendation:\n{f['recommendation']}")
    print(f"\n{'─'*60}")
    print(f"Total findings: {len(findings)}")


def ensure_labels() -> None:
    label_defs = [
        ("security", "d73a4a", "Security vulnerability"),
        ("severity:critical", "b60205", "Critical severity"),
        ("severity:high", "e4534e", "High severity"),
        ("severity:medium", "e4a92a", "Medium severity"),
    ]
    for name, color, desc in label_defs:
        subprocess.run(
            ["gh", "label", "create", name, "--color", color, "--description", desc, "--force"],
            capture_output=True,
        )


def create_issue(finding: dict, pr_number: str | None) -> int | None:
    """Create a GitHub Issue and return its number, or None on failure."""
    severity = finding["severity"]
    labels = ["security"]
    if severity in SEVERITY_LABELS:
        labels.append(SEVERITY_LABELS[severity])

    title = f"[{severity}] {finding['class']}: {finding['location']}"
    pr_ref = f"\n\n**Detected on PR:** #{pr_number}" if pr_number else ""

    body = f"""## {finding["id"]} — {finding["class"]}

**Severity:** {severity}
**Location:** `{finding["location"]}`{pr_ref}

### Description
{finding["description"]}

### PoC Outline
{finding["poc_outline"]}

### Recommendation
{finding["recommendation"]}

---
*Filed by `scripts/redteam.py`. Fix agent will open a PR automatically.*
"""

    cmd = ["gh", "issue", "create", "--title", title, "--body", body]
    for label in labels:
        cmd += ["--label", label]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(
            f"  WARNING: could not create issue for {finding['id']}: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return None

    url = result.stdout.strip()
    print(f"  Issue created: {url}")
    # URL format: https://github.com/owner/repo/issues/42
    try:
        return int(url.rstrip("/").split("/")[-1])
    except ValueError:
        return None


def dispatch_fix(issue_number: int) -> None:
    """Trigger the fix workflow for a given issue number."""
    result = subprocess.run(
        ["gh", "workflow", "run", "fix.yml", "-f", f"issue_number={issue_number}"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        print(f"  Fix agent dispatched for issue #{issue_number}")
    else:
        print(
            f"  WARNING: could not dispatch fix.yml for #{issue_number}: {result.stderr.strip()}\n"
            "  (Run manually: python scripts/fix.py --issue {issue_number})",
            file=sys.stderr,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Red team agent — Solidity security audit")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print findings without creating GitHub Issues",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent
    src_dir = repo_root / "src"

    if not src_dir.exists():
        print(f"ERROR: src/ not found at {src_dir}", file=sys.stderr)
        sys.exit(1)

    sources = load_sources(src_dir)
    if not sources:
        print("No .sol files in src/ — nothing to audit.")
        sys.exit(0)

    print(f"Auditing {len(sources)} contract(s): {', '.join(sources.keys())}")
    print("Calling Claude API (claude-opus-4-7, adaptive thinking)...")

    findings = run_audit(sources)
    print_findings(findings)

    if args.dry_run:
        print("\n[dry-run] GitHub Issue creation skipped.")
        return

    actionable = [f for f in findings if f["severity"] in ("Critical", "High", "Medium")]
    if not actionable:
        print("\nNo Critical/High/Medium findings — no issues created.")
        return

    pr_number = os.environ.get("PR_NUMBER")
    print(f"\nCreating GitHub Issues for {len(actionable)} finding(s)...")
    ensure_labels()
    for finding in actionable:
        issue_number = create_issue(finding, pr_number)
        if issue_number:
            dispatch_fix(issue_number)


if __name__ == "__main__":
    main()
