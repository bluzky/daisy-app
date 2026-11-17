# Coding Agent Setup

The harness works with any coding agent that can read files in the repo. Everything shared is plain Markdown:

| Shared part | Path | Used by |
| --- | --- | --- |
| Entrypoint and routing | `AGENTS.md` | Every tool |
| Rules, roles, checklists, templates | `docs/ai/` | Every tool, loaded on demand from `AGENTS.md` |
| Lucy (entry skill + workflows) | `.agents/skills/lucy/` | Every tool, only when Lucy is addressed by name: natively where supported, otherwise through `AGENTS.md` |
| PR check | `scripts/check_pr.py` | Runs locally, independent of the agent |

Tool-specific files are thin adapters that point to the shared parts. Never put rules in them.

## Per tool

TODO: check each row against the tool's current docs before rollout; tool features change often.

| Tool | Reads instructions from | Skills | ClickUp MCP config (else: ClickUp CLI) | Adapter in this repo |
| --- | --- | --- | --- | --- |
| Claude Code | `CLAUDE.md` (imports `AGENTS.md`) | Native `lucy` skill: `.claude/skills/lucy` → `.agents/skills/lucy` (link made by `install.py`) | `.mcp.json` | `CLAUDE.md`, `.claude/` |
| Codex | `AGENTS.md` | Native if supported (point it at `.agents/skills`), else via `AGENTS.md` | Codex config (`config.toml`) | None needed |
| Cursor | `AGENTS.md` | By name | `.cursor/mcp.json` | None needed |
| GitHub Copilot (agent mode) | `AGENTS.md` | By name | Editor MCP config (e.g. `.vscode/mcp.json`) | None needed |
| Gemini CLI | `GEMINI.md` by default; set it to read `AGENTS.md` | By name | Gemini settings | Optional `.gemini/settings.json` |
| Any other agent | Tell it: "Read `AGENTS.md` first" | By name | Tool-specific | None |

## Calling Lucy

Every tool accepts the same request, as long as it names Lucy:

```text
Hey Lucy, draft business spec for ticket 86abc123
```

`AGENTS.md` tells the agent to open `.agents/skills/lucy/SKILL.md`, which picks the workflow. Tools with native skills also accept `/lucy …`. Without "Lucy" in the message, the agent works normally and ignores the harness.

Only `lucy` is a native skill. Her workflows (`workflows/*.md`) are plain files, so tools that auto-load skills can't trigger a step without her name.

## Subagents

Some workflows say "if your tool supports subagents". Then the workflow runs a role (`docs/ai/roles/*.md`) in a separate context:

- Claude Code: `.claude/agents/po-agent.md`, `tech-design-agent.md`, `spec-reviewer-agent.md`, and the Gate 3 reviewers `review-business-agent.md`, `review-structure-agent.md`, `review-style-agent.md`, `review-workflow-json-agent.md` (run in parallel by `code-review`). In Claude Code the four reviewer agents are pinned to Sonnet (`model: sonnet` in their adapter files); other tools use their own default or choose a model in their own config.
- Other tools: use their own subagent/background-agent feature with the same role file, or skip it: the main agent follows the role directly.

Running `spec-check` in a fresh context (or a new session) gives a more independent review than reviewing in the session that drafted the spec.

## Tracker

Set `Lucy tracker: clickup | github | none` in the project's `AGENTS.md` (`docs/ai/flow/tracker.md`). GitHub needs only the `gh` CLI, logged in. The two sections below apply to ClickUp.

## ClickUp without MCP

If your tool has no ClickUp MCP server, install the team's **ClickUp CLI** (`brew install triptechtravel/tap/clickup`) and log in once with `clickup auth login` (`docs/ai/flow/clickup.md` → "ClickUp CLI"). Any agent that can run shell commands can use it; Lucy lists each write command she ran in her reply.

## Without any ClickUp access

If neither MCP nor the CLI works:

1. Paste the ticket (title, description, comments) into the chat when Lucy asks.
2. Drafting works the same: the spec is a repo file. `spec-publish` and `create-tickets` print what to create in ClickUp; do it by hand.
3. The tech lead still checks the design ticket is `done` or `complete` before merging.

## Adding a new tool

1. Make it read `AGENTS.md` (setting, or a one-line pointer file).
2. If it has native skills, point them at `.agents/skills/` (link or setting), never a copy. Only `lucy` should be visible as a skill.
3. If it has subagents, add thin adapters that point to `docs/ai/roles/*.md`.
4. Add a row to the table above.
