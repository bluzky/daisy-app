#!/usr/bin/env python3
"""Design-Before-Code PR check.

Run locally before opening a PR (Lucy's pr-prepare runs it). Not wired to CI.

Checks a PR description (and the repo) against the flow rules in docs/ai/rules/flow.md:

  FLOW-01  PR links a phase ticket and the Feature Spec
  FLOW-02  The phase ticket's design ticket (linked task) is "done" or "complete" (= spec approved)
  FLOW-04  ACs covered are listed, each has a test with its ID and evidence
  FLOW-05  "Differences from the spec" is filled in
  FLOW-06  Source branch is not mockup/*
  FLOW-07  The PR covers all and only the ACs of its phase's stories
  FLOW-10  The phase ticket has a [P<n>] tag and the implementation plan has that phase

The phase's stories come from the plan (docs/features/<slug>-plan.md, "### P<n>:" → "Stories:"),
and their ACs from the spec's §3.

Usage:
  check_pr.py --body pr_body.md --branch feature/x [--tracker clickup|github|none]
              [--light] [--local [--phase P<n>]] [--base <ref>]

Tracker (docs/ai/flow/tracker.md): --tracker, else env LUCY_TRACKER, else the "Lucy tracker: <x>" line
in AGENTS.md, else clickup.

  clickup  phase ticket and design ticket are ClickUp tasks (link in the PR); needs CLICKUP_API_TOKEN.
  github   phase ticket and design ticket are GitHub issues (#N in the PR); read with the `gh` CLI.
           Approved = the design issue is closed as completed.
  none     no tickets; the PR says "Phase: P<n>". Approved = the spec and the plan exist on --base.

  --local skips the tracker lookup; the phase is taken from --phase.

Env:
  LUCY_TRACKER                     clickup | github | none (overridden by --tracker).
  CLICKUP_API_TOKEN                Personal ClickUp API token (read-only). clickup mode, unless --local.
  DESIGN_APPROVED_STATUS           Comma-separated ClickUp design ticket statuses that mean approved (default "done,complete").
  TEST_GLOBS                       Comma-separated globs for test files.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

# TODO: adjust to the repo's stacks.
DEFAULT_TEST_GLOBS = (
    "**/test/**/*_test.exs,"   # Elixir
    "**/*.test.ts,**/*.test.tsx,**/*.spec.ts,**/*.spec.tsx,"  # TS / JS
    "**/test_*.py,**/*_test.py,"  # Python
    "**/*_test.go"  # Go
)

TASK_RE = re.compile(r"https://app\.clickup\.com/t/(?:\d+/)?([A-Za-z0-9_-]+)")
GH_ISSUE_RE = re.compile(r"(?:https://github\.com/[\w.-]+/[\w.-]+/issues/|(?<![\w/])#)(\d+)")
DESIGN_REF_RE = re.compile(r"Design(?: ticket)?:\s*(?:https://github\.com/[\w.-]+/[\w.-]+/issues/|#)(\d+)", re.IGNORECASE)
PHASE_LINE_RE = re.compile(r"Phase(?: ticket)?:\s*\[?P(\d+)\b", re.IGNORECASE)
TICKET_SECTIONS = ("ticket", "clickup", "github")
SPEC_RE = re.compile(r"https://app\.clickup\.com/\S*/v/dc/\S+|\bdocs/features/[\w./-]+\.md\b")
AC_RE = re.compile(r"\bAC-(\d+)\.(\d+)\b")
PHASE_TAG_RE = re.compile(r"\[P(\d+)\]")
SPEC_PATH_RE = re.compile(r"\bdocs/features/[\w./-]+?\.md\b")
PLACEHOLDER_RE = re.compile(r"^\s*(<.*>|TODO.*|-)?\s*$", re.IGNORECASE)


def sections(body: str) -> dict[str, str]:
    """Split the description into {heading: content} on '## ' headings."""
    out: dict[str, str] = {}
    current = None
    for line in body.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            current = m.group(1).strip().lower()
            out[current] = ""
        elif current is not None:
            out[current] += line + "\n"
    return out


def strip_comments(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def is_placeholder(text: str) -> bool:
    lines = [l for l in text.strip().splitlines() if l.strip()]
    return not lines or all(PLACEHOLDER_RE.match(l) for l in lines)


def acs_in(text: str) -> list[str]:
    return sorted({f"AC-{a}.{b}" for a, b in AC_RE.findall(text)},
                  key=lambda s: tuple(int(x) for x in s[3:].split(".")))


def evidence_rows(text: str) -> dict[str, str]:
    rows = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and AC_RE.fullmatch(cells[0] or ""):
            rows[cells[0]] = cells[1]
    return rows


def find_tests(acs: list[str], root: Path, globs: list[str]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {ac: [] for ac in acs}
    patterns = {
        ac: re.compile(rf"AC[-_]{ac[3:].split('.')[0]}[._]{ac[3:].split('.')[1]}(?!\d)")
        for ac in acs
    }
    seen: set[Path] = set()
    for g in globs:
        for path in root.glob(g.strip()):
            if path in seen or not path.is_file() or "node_modules" in path.parts:
                continue
            seen.add(path)
            try:
                text = path.read_text(errors="ignore")
            except OSError:
                continue
            for ac, pat in patterns.items():
                if pat.search(text):
                    found[ac].append(str(path.relative_to(root)))
    return found


def clickup_get(task_id: str, token: str) -> dict:
    req = urllib.request.Request(
        f"https://api.clickup.com/api/v2/task/{task_id}",
        headers={"Authorization": token},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def status_of(task: dict) -> str:
    return str((task.get("status") or {}).get("status", "")).strip().lower()


def design_candidates(story: dict) -> list[str]:
    """Design ticket = a linked task. The parent is the epic, whose status is not approval."""
    ids = []
    for link in story.get("linked_tasks", []) or []:
        for key in ("task_id", "link_id"):
            other = link.get(key)
            if other and other != story.get("id") and other not in ids:
                ids.append(other)
    return ids


def gh_issue(number: str) -> dict:
    """Read an issue with the gh CLI (uses the current repo and the user's gh login)."""
    out = subprocess.run(
        ["gh", "api", f"repos/{{owner}}/{{repo}}/issues/{number}"],
        capture_output=True, text=True, timeout=30,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "gh api failed")
    return json.loads(out.stdout)


def check_github(number: str) -> tuple[str | None, list[str], list[str]]:
    """GitHub mode: return (phase number, errors, notes) for a phase issue."""
    errors, notes = [], []
    issue = gh_issue(number)
    name = issue.get("title", f"#{number}")
    tag = PHASE_TAG_RE.search(name)
    if not tag:
        errors.append(f"FLOW-10: phase issue '{name}' has no [P<n>] tag in its title.")
    design_ref = DESIGN_REF_RE.search(issue.get("body") or "")
    if not design_ref:
        errors.append(f"FLOW-02: phase issue '{name}' has no 'Design: #<n>' line linking its design issue.")
    else:
        design = gh_issue(design_ref.group(1))
        if design.get("state") == "closed" and design.get("state_reason") != "not_planned":
            notes.append(f"spec approved: design issue #{design_ref.group(1)} '{design.get('title', '')}' is closed")
        else:
            errors.append(f"FLOW-02: design issue #{design_ref.group(1)} is not closed as completed (spec not approved yet).")
    return (tag.group(1) if tag else None), errors, notes


def git_has(ref: str, path: str, root: str) -> bool:
    return subprocess.run(["git", "-C", root, "cat-file", "-e", f"{ref}:{path}"], capture_output=True).returncode == 0


def default_base(root: str) -> str:
    out = subprocess.run(["git", "-C", root, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], capture_output=True, text=True)
    return out.stdout.strip() or "origin/main"


def detect_tracker(root: str) -> str:
    env = os.environ.get("LUCY_TRACKER", "").strip().lower()
    if env:
        return env
    try:
        text = (Path(root) / "AGENTS.md").read_text()
    except OSError:
        return "clickup"
    m = re.search(r"^\s*Lucy tracker:\s*(clickup|github|none)\b", text, re.IGNORECASE | re.MULTILINE)
    return m.group(1).lower() if m else "clickup"


def story_numbers(text: str) -> set[str]:
    return set(re.findall(r"US-(\d+)", text))


def phase_stories(plan: str, phase: str) -> set[str] | None:
    """Stories listed under '### P<n>:' in the plan, or None if the phase isn't there."""
    m = re.search(rf"^###\s+P{phase}\b.*?$(.*?)(?=^###\s|^##\s|\Z)", plan, re.MULTILINE | re.DOTALL)
    if not m:
        return None
    line = next((l for l in m.group(1).splitlines() if "stories:" in l.lower()), "")
    return story_numbers(line)


def spec_acs(spec: str, stories: set[str]) -> list[str]:
    """ACs of the given stories, from the spec (lines starting with '- AC-n.m')."""
    acs = {f"AC-{a}.{b}" for a, b in re.findall(r"^\s*-\s*AC-(\d+)\.(\d+)\b", spec, re.MULTILINE) if a in stories}
    removed = {f"AC-{a}.{b}" for a, b in re.findall(r"~~AC-(\d+)\.(\d+)", spec)}
    return sorted(acs - removed, key=lambda s: tuple(int(x) for x in s[3:].split(".")))


def check_story(task_id: str, token: str, approved_statuses: set[str]) -> tuple[str | None, list[str], list[str]]:
    """Return (phase number, errors, notes) for a phase ticket."""
    errors, notes = [], []
    story = clickup_get(task_id, token)
    name = story.get("name", task_id)
    tag = PHASE_TAG_RE.search(name)
    if not tag:
        errors.append(f"FLOW-10: phase ticket '{name}' has no [P<n>] tag in its title.")
    candidates = design_candidates(story)
    if not candidates:
        errors.append(f"FLOW-02: phase ticket '{name}' isn't linked to a design ticket (task link).")
    approved_by = None
    for cid in candidates:
        design = clickup_get(cid, token)
        if status_of(design) in approved_statuses:
            approved_by = design.get("name", cid)
            break
    if candidates and not approved_by:
        errors.append(f"FLOW-02: the design ticket of '{name}' is not {' or '.join(sorted(approved_statuses))} (spec not approved yet).")
    elif approved_by:
        notes.append(f"spec approved on design ticket '{approved_by}'")
    return (tag.group(1) if tag else None), errors, notes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--body", required=True, help="File with the PR description")
    ap.add_argument("--branch", default="", help="PR source branch")
    ap.add_argument("--light", action="store_true", help="flow:light mode")
    ap.add_argument("--local", action="store_true", help="Skip the tracker lookup")
    ap.add_argument("--tracker", default="", help="clickup | github | none (default: LUCY_TRACKER, AGENTS.md, clickup)")
    ap.add_argument("--base", default="", help="none mode: ref that holds the merged spec and plan")
    ap.add_argument("--root", default=".", help="Repo root")
    ap.add_argument("--phase", default="", help="P<n>, for --local runs")
    args = ap.parse_args()

    body = strip_comments(Path(args.body).read_text())
    sec = sections(body)
    errors: list[str] = []
    notes: list[str] = []

    # FLOW-06
    if args.branch.startswith("mockup/"):
        errors.append("FLOW-06: mockup/* branches must never be merged.")

    tracker = (args.tracker or detect_tracker(args.root)).lower()
    if tracker not in ("clickup", "github", "none"):
        errors.append(f"unknown tracker '{tracker}': use clickup, github or none.")
        tracker = "clickup"
    notes.append(f"tracker: {tracker}")

    ticket_text = next((sec[k] for k in TICKET_SECTIONS if k in sec), "")

    # FLOW-01: phase ticket link
    task = None
    phase_line = PHASE_LINE_RE.search(ticket_text or body)
    if tracker == "clickup":
        task = TASK_RE.search(ticket_text or body)
        if not task:
            errors.append("FLOW-01: no phase ticket link (https://app.clickup.com/t/<id>) under '## Ticket'.")
    elif tracker == "github":
        task = GH_ISSUE_RE.search(ticket_text or body)
        if not task:
            errors.append("FLOW-01: no phase issue (#<n> or issue URL) under '## Ticket'.")
    elif not phase_line and not args.phase:
        errors.append("FLOW-01: no 'Phase: P<n>' line under '## Ticket'.")

    if args.light:
        notes.append("flow:light mode: only the ticket link and branch checks ran.")
        return report(errors, notes)

    # FLOW-01: spec link
    if not SPEC_RE.search(ticket_text):
        errors.append("FLOW-01: no Feature Spec under '## Ticket' (docs/features/<feature-slug>.md).")

    # FLOW-02 / FLOW-10: phase ticket and spec approval
    phase = None
    if args.local:
        notes.append("--local: skipped the tracker phase ticket / design approval checks.")
        m = re.fullmatch(r"P?(\d+)", args.phase.strip(), re.IGNORECASE)
        phase = m.group(1) if m else (phase_line.group(1) if phase_line else None)
        if not phase:
            errors.append("FLOW-10: pass --phase P<n> with --local.")
    elif tracker == "clickup" and task:
        token = os.environ.get("CLICKUP_API_TOKEN", "")
        approved_statuses = {s.strip().lower() for s in os.environ.get("DESIGN_APPROVED_STATUS", "done,complete").split(",") if s.strip()}
        if not token:
            errors.append("FLOW-02: CLICKUP_API_TOKEN not set; can't check approval.")
        else:
            try:
                phase, errs, nts = check_story(task.group(1), token, approved_statuses)
                errors += errs
                notes += nts
            except Exception as exc:  # network / auth errors fail the gate
                errors.append(f"FLOW-02: ClickUp API check failed: {exc}")
    elif tracker == "github" and task:
        try:
            phase, errs, nts = check_github(task.group(1))
            errors += errs
            notes += nts
        except Exception as exc:  # gh missing, not logged in, no access
            errors.append(f"FLOW-02: GitHub issue check failed: {exc}")
    elif tracker == "none":
        m = re.fullmatch(r"P?(\d+)", args.phase.strip(), re.IGNORECASE)
        phase = m.group(1) if m else (phase_line.group(1) if phase_line else None)
        if not phase:
            errors.append("FLOW-10: no 'Phase: P<n>' line under '## Ticket' (or pass --phase).")
        spec_for_base = next((x for x in SPEC_PATH_RE.findall(ticket_text) if not x.endswith("-plan.md")), None)
        if spec_for_base:
            base = args.base or default_base(args.root)
            plan_for_base = spec_for_base[:-3] + "-plan.md"
            for label, path in (("spec", spec_for_base), ("plan", plan_for_base)):
                if git_has(base, path, args.root):
                    notes.append(f"{label} is on {base}: {path}")
                else:
                    errors.append(f"FLOW-02: the {label} {path} is not on {base}: it isn't approved and merged yet.")

    # FLOW-04: ACs covered
    scope = sec.get("scope", "")
    covered_line = next((l for l in scope.splitlines() if "acs covered" in l.lower()), "")
    acs = acs_in(covered_line)
    if not acs:
        errors.append("FLOW-04: no ACs listed in '## Scope' → 'ACs covered: AC-1.1, …'.")

    # FLOW-07 / FLOW-10: the PR covers all and only the ACs of its phase's stories
    spec_paths = [s for s in SPEC_PATH_RE.findall(ticket_text) if not s.endswith("-plan.md")]
    if phase and spec_paths:
        spec_path = Path(args.root) / spec_paths[0]
        plan_path = spec_path.with_name(spec_path.stem + "-plan.md")
        if not plan_path.is_file():
            errors.append(f"FLOW-10: no implementation plan at {plan_path.relative_to(args.root)}.")
        else:
            stories = phase_stories(plan_path.read_text(), phase)
            if not stories:
                errors.append(f"FLOW-10: the plan has no phase P{phase} with a 'Stories:' line.")
            else:
                foreign = [ac for ac in acs if ac[3:].split(".")[0] not in stories]
                if foreign:
                    errors.append(f"FLOW-07: {', '.join(foreign)} not in P{phase}'s stories. One PR = one phase.")
                if spec_path.is_file():
                    missing = [ac for ac in spec_acs(spec_path.read_text(), stories) if ac not in acs]
                    if missing:
                        errors.append(f"FLOW-07: P{phase} must cover all its ACs; missing {', '.join(missing)}.")
                else:
                    notes.append(f"spec not found at {spec_paths[0]}; couldn't check all ACs are covered.")
                notes.append(f"P{phase} stories: US-{', US-'.join(sorted(stories, key=int))}")
    elif phase:
        notes.append("no docs/features/<slug>.md spec path in the PR; couldn't check the phase's ACs.")

    # FLOW-04: evidence per AC
    rows = evidence_rows(sec.get("evidence", ""))
    for ac in acs:
        ev = rows.get(ac, "")
        if is_placeholder(ev):
            errors.append(f"FLOW-04: {ac} has no evidence in '## Evidence'.")

    # FLOW-04: test per AC
    globs = os.environ.get("TEST_GLOBS", DEFAULT_TEST_GLOBS).split(",")
    tests = find_tests(acs, Path(args.root), globs)
    for ac, files in tests.items():
        if not files:
            errors.append(f"FLOW-04: no test mentions {ac} (expected e.g. 'test_AC_{ac[3:].replace('.', '_')}_…').")
        else:
            notes.append(f"{ac}: tested in {', '.join(files[:3])}")

    # FLOW-05: differences from the spec
    if "differences from the spec" not in sec or is_placeholder(sec["differences from the spec"]):
        errors.append("FLOW-05: fill in '## Differences from the spec' (or write 'None').")

    return report(errors, notes)


def report(errors: list[str], notes: list[str]) -> int:
    for n in notes:
        print(f"  ok  {n}")
    for e in errors:
        print(f"FAIL  {e}")
    print("\nPR check: " + ("FAILED" if errors else "passed"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
