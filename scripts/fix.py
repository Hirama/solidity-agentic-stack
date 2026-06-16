#!/usr/bin/env python3
"""
Fix agent: reads a meta-audit GitHub issue (filed by redteam.py), generates
one combined Solidity fix per affected file, verifies with forge, and opens
ONE PR addressing all findings.

Loop: red team finds N bugs → fix agent fixes all → forge confirms → red team
re-validates → human merges.

Usage:
    python scripts/fix.py --issue 42
    python scripts/fix.py --issue 42 --dry-run   # apply fix locally, skip PR

Requires:
    pip install anthropic
    ANTHROPIC_API_KEY env var
    GH_TOKEN / GITHUB_TOKEN env var
    forge on PATH
"""

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import anthropic

MAX_ATTEMPTS = 3

SYSTEM_PROMPT = """\
You are a senior smart contract security engineer. You receive one or more security
findings and the affected Solidity source file. Your job is to produce a minimal,
correct fix that addresses EVERY finding in a single revision of the file.

Rules:
- Address ALL findings provided. Do not skip any.
- Apply the minimal change that resolves each vulnerability.
- Preserve existing NatSpec, events, errors, and identifiers when reasonable.
- CEI (Checks-Effects-Interactions) must hold after your fix.
- Custom errors only — never use require() strings.
- Add new state variables, errors, modifiers, or events if a fix requires them.
- Output the COMPLETE fixed Solidity file — no diffs, no truncation, no placeholders.\
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
            "description": "Bullet list — one line per finding addressed.",
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
    ok, _ = run(["forge", "fmt", "--check"], cwd=repo_root)
    if not ok:
        run(["forge", "fmt"], cwd=repo_root)
    ok, out = run(["forge", "build"], cwd=repo_root)
    if not ok:
        return False, out
    return run(["forge", "test"], cwd=repo_root)


# ─── issue parsing ────────────────────────────────────────────────────────────


def fetch_issue(issue_number: int) -> dict:
    raw = gh("issue", "view", str(issue_number), "--json", "title,body,labels")
    return json.loads(raw)


def extract_findings_json(issue: dict) -> dict | None:
    """Parse the embedded JSON payload from the meta-audit issue body.

    Body contains a fenced ```json``` block with {"findings": [...], "pr_number": N}.
    """
    m = re.search(r"```json\s*\n(.+?)\n```", issue["body"], re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError as e:
        print(f"WARNING: could not parse findings JSON: {e}", file=sys.stderr)
        return None


def checkout_pr_branch(pr_number: int, repo_root: Path) -> str | None:
    """Checkout the head ref of a PR. Returns the branch name or None."""
    raw = subprocess.run(
        ["gh", "pr", "view", str(pr_number), "--json", "headRefName"],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if raw.returncode != 0:
        print(f"WARNING: could not fetch PR #{pr_number}: {raw.stderr.strip()}", file=sys.stderr)
        return None
    head_ref = json.loads(raw.stdout)["headRefName"]
    run(["git", "fetch", "origin", head_ref], cwd=repo_root)
    ok, _ = run(["git", "checkout", head_ref], cwd=repo_root)
    if not ok:
        run(["git", "checkout", "-b", head_ref, f"origin/{head_ref}"], cwd=repo_root)
    print(f"  Checked out PR #{pr_number} head: {head_ref}")
    return head_ref


def resolve_source_path(repo_root: Path, raw_path: str) -> Path | None:
    """Resolve a path that may be relative to repo root, or a bare filename
    under src/. Returns None if not found."""
    candidate = repo_root / raw_path
    if candidate.exists():
        return candidate
    filename = Path(raw_path).name
    matches = list((repo_root / "src").rglob(filename))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        print(f"WARNING: multiple matches for {filename}: {matches}", file=sys.stderr)
        return matches[0]
    return None


def group_findings_by_file(findings: list[dict], repo_root: Path) -> dict[Path, list[dict]]:
    """Group findings by the file they affect. Skips findings with no resolvable path."""
    grouped: dict[Path, list[dict]] = defaultdict(list)
    for f in findings:
        raw_path = f["location"].split(":")[0]
        abs_path = resolve_source_path(repo_root, raw_path)
        if abs_path is None:
            print(f"  WARNING: skipping {f['id']} — could not locate {raw_path}", file=sys.stderr)
            continue
        grouped[abs_path].append(f)
    return grouped


# ─── fix generation ───────────────────────────────────────────────────────────


def render_findings_for_prompt(findings: list[dict]) -> str:
    blocks = []
    for f in findings:
        blocks.append(
            f"### {f['id']} — [{f['severity']}] {f['class']}\n"
            f"Location: `{f['location']}`\n"
            f"Description: {f['description']}\n"
            f"PoC: {f['poc_outline']}\n"
            f"Recommendation: {f['recommendation']}\n"
        )
    return "\n".join(blocks)


def generate_fix(
    findings: list[dict],
    source_code: str,
    source_path: str,
    previous_error: str | None = None,
) -> dict:
    client = anthropic.Anthropic()

    retry_note = ""
    if previous_error:
        retry_note = (
            f"\n\nPrevious fix attempt failed with this error:\n```\n{previous_error}\n```\n"
            "Fix the error above AS WELL AS all the findings below."
        )

    user_text = f"""## Security Findings ({len(findings)} total) for `{source_path}`

{render_findings_for_prompt(findings)}

## Current source of `{source_path}`
```solidity
{source_code}
```{retry_note}

Produce the complete fixed version of `{source_path}` addressing ALL findings.
"""

    response = client.messages.create(
        model="claude-opus-4-7",
        max_tokens=16000,
        thinking={"type": "adaptive"},
        output_config={
            "effort": "high",
            "format": {"type": "json_schema", "schema": FIX_SCHEMA},
        },
        system=[
            {"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}
        ],
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


def ensure_autofix_label() -> None:
    subprocess.run(
        [
            "gh", "label", "create", "auto-fix",
            "--color", "0e8a16",
            "--description", "Auto-generated by fix agent — redteam.yml skips these",
            "--force",
        ],
        capture_output=True,
    )


def create_combined_pr(
    issue_number: int,
    branch: str,
    file_summaries: list[tuple[str, str]],
    finding_count: int,
) -> str:
    pr_title = f"fix: address {finding_count} security finding(s) (closes #{issue_number})"

    summary_lines = "\n".join(
        f"### `{path}`\n{explanation}" for path, explanation in file_summaries
    )

    body = f"""## Fix for audit issue #{issue_number}

Addresses **{finding_count} finding(s)** across {len(file_summaries)} file(s).

{summary_lines}

### Verification
- `forge fmt --check` ✅
- `forge build` ✅
- `forge test` ✅

This PR is labeled `auto-fix` so the red team agent will **not** re-audit it.
Human review still required before merge.

Closes #{issue_number}
"""

    ensure_autofix_label()
    url = gh(
        "pr", "create",
        "--title", pr_title,
        "--body", body,
        "--head", branch,
        "--base", "main",
        "--label", "auto-fix",
    )
    return url


# ─── main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="Fix agent — combines all findings into one PR")
    parser.add_argument("--issue", type=int, required=True, help="Audit meta-issue number")
    parser.add_argument("--dry-run", action="store_true", help="Apply fix locally, skip PR")
    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent

    print(f"Fetching audit issue #{args.issue}...")
    issue = fetch_issue(args.issue)
    print(f"  Title: {issue['title']}")

    payload = extract_findings_json(issue)
    if not payload or not payload.get("findings"):
        print("ERROR: no findings JSON found in issue body.", file=sys.stderr)
        sys.exit(1)

    findings = payload["findings"]
    pr_number = payload.get("pr_number")
    print(f"  Parsed {len(findings)} finding(s); source PR: #{pr_number or 'n/a'}")

    if pr_number and not args.dry_run:
        print(f"  Switching to PR #{pr_number} head branch")
        checkout_pr_branch(int(pr_number), repo_root)

    grouped = group_findings_by_file(findings, repo_root)
    if not grouped:
        print("ERROR: no resolvable file paths in findings.", file=sys.stderr)
        sys.exit(1)

    # Create one fix branch off the current HEAD (which is PR head if applicable).
    fix_branch = f"fix/audit-{args.issue}"
    if not args.dry_run:
        ok, _ = run(["git", "checkout", "-b", fix_branch], cwd=repo_root)
        if not ok:
            run(["git", "checkout", fix_branch], cwd=repo_root)

    file_summaries: list[tuple[str, str]] = []

    for abs_path, file_findings in grouped.items():
        source_path = str(abs_path.relative_to(repo_root))
        print(f"\n→ Fixing {source_path} ({len(file_findings)} finding(s))")

        original_code = abs_path.read_text()
        previous_error: str | None = None
        explanation = ""

        for attempt in range(1, MAX_ATTEMPTS + 1):
            print(f"  Attempt {attempt}/{MAX_ATTEMPTS}: generating fix...")
            fix_result = generate_fix(file_findings, original_code, source_path, previous_error)
            explanation = fix_result["explanation"]

            print(f"  Explanation:\n{explanation[:300]}")
            abs_path.write_text(fix_result["fixed_code"])

            print("  Running forge fmt + build + test...")
            passed, output = forge_check(repo_root)
            if passed:
                print(f"  forge test PASSED ✅ for {source_path}")
                break

            print(f"  forge test FAILED ❌\n{output[:600]}")
            previous_error = output
            abs_path.write_text(original_code)
        else:
            print(
                f"\nFailed after {MAX_ATTEMPTS} attempts for {source_path}. Aborting.",
                file=sys.stderr,
            )
            abs_path.write_text(original_code)
            sys.exit(1)

        file_summaries.append((source_path, explanation))

    if args.dry_run:
        print("\n[dry-run] Combined fix applied locally. PR creation skipped.")
        return

    # Stage every modified file
    for abs_path in grouped:
        run(["git", "add", str(abs_path.relative_to(repo_root))], cwd=repo_root)

    commit_msg = f"fix: resolve audit issue #{args.issue} — {len(findings)} finding(s)"
    run(["git", "commit", "-m", commit_msg], cwd=repo_root)
    run(["git", "push", "-u", "origin", fix_branch], cwd=repo_root)

    print("\nCreating combined fix PR...")
    pr_url = create_combined_pr(args.issue, fix_branch, file_summaries, len(findings))
    print(f"  PR: {pr_url}")
    print("\nLabeled `auto-fix` — red team will NOT recurse on this PR.")
    print("Human review required before merge.")


if __name__ == "__main__":
    main()
