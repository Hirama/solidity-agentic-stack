#!/usr/bin/env python3
"""
Fix agent: reads a GitHub security issue, generates a Solidity fix,
verifies with forge, and opens a PR. Red team re-runs on the PR automatically.

Loop: red team finds bug → fix agent fixes → forge confirms → red team re-validates → human merges.

Usage:
    python scripts/fix.py --issue 42
    python scripts/fix.py --issue 42 --dry-run   # apply fix locally, skip PR

Requires:
    pip install anthropic
    ANTHROPIC_API_KEY env var
    GH_TOKEN / GITHUB_TOKEN env var (for PR creation)
    forge on PATH
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import anthropic

MAX_ATTEMPTS = 3

SYSTEM_PROMPT = """\
You are a senior smart contract security engineer. You will receive a security issue
report and the affected Solidity source file. Your job is to produce a minimal, correct fix.

Rules for your fix:
- Apply the minimal change that resolves the reported vulnerability.
- Preserve all existing NatSpec, events, errors, and variable names.
- Do NOT rewrite unrelated logic or add new features.
- CEI (Checks-Effects-Interactions) must hold after your fix.
- Custom errors only — never add require() strings.
- If the fix requires a new state variable or error, add it.
- Output the complete fixed Solidity file — no diffs, no omissions.\
"""

FIX_SCHEMA = {
    "type": "object",
    "properties": {
        "fixed_code": {
            "type": "string",
            "description": "Complete fixed Solidity file content.",
        },
        "explanation": {
            "type": "string",
            "description": "One-paragraph explanation of what was changed and why.",
        },
    },
    "required": ["fixed_code", "explanation"],
    "additionalProperties": False,
}


# ─── helpers ──────────────────────────────────────────────────────────────────


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"gh error: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def run(cmd: list[str], cwd: Path | None = None) -> tuple[bool, str]:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    output = (result.stdout + "\n" + result.stderr).strip()
    return result.returncode == 0, output


def forge_check(repo_root: Path) -> tuple[bool, str]:
    ok, out = run(["forge", "fmt", "--check"], cwd=repo_root)
    if not ok:
        # formatter issues → auto-fix, not a real error
        run(["forge", "fmt"], cwd=repo_root)
    ok, out = run(["forge", "build"], cwd=repo_root)
    if not ok:
        return False, out
    return run(["forge", "test"], cwd=repo_root)


# ─── issue parsing ────────────────────────────────────────────────────────────


def fetch_issue(issue_number: int) -> dict:
    raw = gh("issue", "view", str(issue_number), "--json", "title,body,labels")
    return json.loads(raw)


def extract_location(issue: dict) -> tuple[str, str]:
    """Return (rel_path, function_name) from issue body Location field."""
    body = issue["body"]
    m = re.search(r"\*\*Location:\*\*\s*`([^`]+)`", body)
    if not m:
        return "", ""
    loc = m.group(1)  # e.g. "src/Vault.sol:withdraw()"
    parts = loc.split(":")
    return parts[0], parts[1] if len(parts) > 1 else ""


# ─── fix generation ───────────────────────────────────────────────────────────


def generate_fix(
    issue: dict,
    source_code: str,
    source_path: str,
    previous_error: str | None = None,
) -> dict:
    client = anthropic.Anthropic()

    retry_note = ""
    if previous_error:
        retry_note = f"\n\nPrevious fix attempt failed with this error:\n```\n{previous_error}\n```\nFix the error above as well."

    user_text = f"""## Security Issue
**Title:** {issue['title']}

**Body:**
{issue['body']}

## Affected File: {source_path}
```solidity
{source_code}
```{retry_note}

Produce the complete fixed version of `{source_path}`.
"""

    response = client.messages.create(
        model="claude-opus-4-7",
        max_tokens=16000,
        thinking={"type": "adaptive"},
        output_config={
            "effort": "high",
            "format": {
                "type": "json_schema",
                "schema": FIX_SCHEMA,
            },
        },
        system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
        messages=[{"role": "user", "content": user_text}],
    )

    text_block = next((b for b in response.content if b.type == "text"), None)
    if not text_block:
        print("ERROR: no text block in response", file=sys.stderr)
        sys.exit(1)

    return json.loads(text_block.text)


# ─── PR creation ──────────────────────────────────────────────────────────────


def slugify(text: str) -> str:
    text = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return text[:40]


def create_pr(issue_number: int, issue: dict, branch: str, explanation: str) -> str:
    title_match = re.search(r"\[(\w+)\]\s+(.*?):", issue["title"])
    severity = title_match.group(1) if title_match else "Security"
    issue_class = title_match.group(2) if title_match else "fix"

    pr_title = f"fix: [{severity}] {issue_class} (closes #{issue_number})"

    body = f"""## Fix for #{issue_number}

{explanation}

### Verification
- `forge fmt --check` ✅
- `forge build` ✅
- `forge test` ✅

The red team agent will re-run on this PR automatically.
If it finds no new Critical/High/Medium issues, this PR is ready for human review.

Closes #{issue_number}
"""

    url = gh(
        "pr",
        "create",
        "--title",
        pr_title,
        "--body",
        body,
        "--head",
        branch,
        "--base",
        "main",
    )
    return url


# ─── main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="Fix agent — auto-patches security issues")
    parser.add_argument("--issue", type=int, required=True, help="GitHub Issue number to fix")
    parser.add_argument("--dry-run", action="store_true", help="Apply fix locally, skip PR")
    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent

    print(f"Fetching issue #{args.issue}...")
    issue = fetch_issue(args.issue)
    print(f"  Title: {issue['title']}")

    source_path, location = extract_location(issue)
    if not source_path:
        print("ERROR: could not parse Location from issue body.", file=sys.stderr)
        print("Expected format: **Location:** `src/Foo.sol:function_name`", file=sys.stderr)
        sys.exit(1)

    abs_path = repo_root / source_path
    if not abs_path.exists():
        print(f"ERROR: {abs_path} not found.", file=sys.stderr)
        sys.exit(1)

    original_code = abs_path.read_text()
    print(f"  File: {source_path} ({len(original_code)} chars)")

    branch = f"fix/issue-{args.issue}-{slugify(location or source_path)}"
    if not args.dry_run:
        ok, out = run(["git", "checkout", "-b", branch], cwd=repo_root)
        if not ok:
            # branch may already exist from a previous attempt
            run(["git", "checkout", branch], cwd=repo_root)

    previous_error: str | None = None
    fix_result: dict | None = None

    for attempt in range(1, MAX_ATTEMPTS + 1):
        print(f"\nAttempt {attempt}/{MAX_ATTEMPTS}: generating fix...")
        fix_result = generate_fix(issue, original_code, source_path, previous_error)

        print(f"  Explanation: {fix_result['explanation'][:120]}...")
        abs_path.write_text(fix_result["fixed_code"])

        print("  Running forge fmt + build + test...")
        passed, output = forge_check(repo_root)

        if passed:
            print("  forge test PASSED ✅")
            break

        print(f"  forge test FAILED ❌\n{output[:600]}")
        previous_error = output
        # restore original for next attempt so we don't stack bad fixes
        abs_path.write_text(original_code)
    else:
        print(
            f"\nFailed after {MAX_ATTEMPTS} attempts. Manual fix needed.",
            file=sys.stderr,
        )
        abs_path.write_text(original_code)
        sys.exit(1)

    if args.dry_run:
        print("\n[dry-run] Fix applied locally. PR creation skipped.")
        return

    # commit and push
    run(["git", "add", source_path], cwd=repo_root)
    commit_msg = f"fix: resolve issue #{args.issue} — {issue['title'][:60]}"
    run(["git", "commit", "-m", commit_msg], cwd=repo_root)
    run(["git", "push", "-u", "origin", branch], cwd=repo_root)

    print("\nCreating PR...")
    pr_url = create_pr(args.issue, issue, branch, fix_result["explanation"])
    print(f"  PR: {pr_url}")
    print(f"\nRed team agent will re-run automatically on the PR.")
    print("If it passes, the PR is ready for human review and merge.")


if __name__ == "__main__":
    main()
