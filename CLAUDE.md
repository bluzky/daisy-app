# CLAUDE.md

<!-- lucy:start — managed by Lucy's install.py; edit the harness, not this block -->

Claude Code adapter. All shared rules and routing live in AGENTS.md.

@AGENTS.md

## Claude Code specifics

- Lucy: `.claude/skills/lucy` links to `.agents/skills/lucy` (created by the harness `install.py`), so the `lucy` skill loads natively. Call her by name ("Hey Lucy, …") or with `/lucy …`. Her step workflows aren't separate skills, so nothing triggers without her name.
- Subagents: `.claude/agents/` (`po-agent`, `tech-design-agent`, `spec-reviewer-agent`, and the four PR reviewers `review-business-agent`, `review-structure-agent`, `review-style-agent`, `review-workflow-json-agent`) point to `docs/ai/roles/`; Lucy's workflows use them when helpful. Gate 3 is `code-review`, which runs the four reviewers in parallel (`docs/ai/roles/pr-reviewer.md`). The reviewer agents run on Sonnet (`model: sonnet` in their frontmatter); the main session's model is the engineer's choice.
- ClickUp: add a ClickUp MCP server to the project's `.mcp.json` (the harness doesn't ship or install one), or use the ClickUp CLI. See `docs/ai/tools.md`.

<!-- lucy:end -->
