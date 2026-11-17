# Project guides: finding and following them

The harness carries no project rules. Whenever Lucy writes or reviews code, she follows the guides **the repository itself has** (coding conventions, style guides, architecture and review guides, lint configs), found like this. Used by the implementer (`implement-phase`, `mockup`) and by every code reviewer (`code-review`). Do it once per task, before writing or reviewing, and keep the result.

**1. Split the work into parts** by what you will change or review, and use each part's own guides:

| Part | Files |
| --- | --- |
| Backend | Server code, migrations, backend tests and configs (e.g. `.ex`, `.exs`, `.py`, `.go`, `.java`, `.rb`, `.php`, SQL) |
| Frontend | UI code, components, styles, frontend tests and configs (e.g. `.ts`, `.tsx`, `.js`, `.jsx`, `.vue`, `.svelte`, `.css`, `.scss`) |
| Workflow JSON | Workflow or flow definitions (see `docs/ai/roles/review-workflow-json.md`) |
| Other | Docs, CI, infra: check only what the angle needs |

Never apply a backend guide to frontend code, or the reverse.

**2. Search the repo** (read-only, e.g. `git ls-files` piped through `grep -iE`):

| Look for | Examples |
| --- | --- |
| Entry docs that link guides | `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, the `README.md` of the backend or frontend folder |
| Guide files, in `docs/`, `doc/`, `.github/`, `.claude/`, `.agents/`, or beside the code | File names matching `style`, `convention`, `guideline`, `standard`, `review`, `architecture`, `contributing` (any case, any separator: `STYLEGUIDE.md`, `CODING_CONVENTION.md`, `REVIEW-GUIDE.md`, `review-guide/`) |
| Tool configs (they define what is enforced) | `.formatter.exs`, `.credo.exs`, `.eslintrc*`, `eslint.config.*`, `.prettierrc*`, `biome.json`, `stylelint*`, `tsconfig.json`, `.editorconfig`, `pyproject.toml`, `ruff.toml` |
| A project PR-review skill or command | `.claude/skills/*review*`, `.claude/commands/*`, `.pi/skills/*`: use it for how to post comments (language, format) |
| Guides for the specific thing changed | Workflow, action, API, database or testing guides, when the diff touches that |

**3. Pick the guides that apply to each part.**
- A guide inside a part's folder (`backend/…`, `frontend/…`, `web/…`) applies to that part; one at the repo root applies to all parts.
- The guide nearest to the changed file wins over a farther one. If two guides disagree, follow the nearer one and mention the conflict.
- Read a long guide's table of contents first, then only the sections the diff needs.

**4. Precedence:** project guide, then tool config, then general practice for the language. A finding from general practice is marked `(general practice)` and is never a `blocker`. Never invent a rule and attribute it to a guide.

**5. Say which guides you used**, per part, and which part had none: in the reviewers' report header, or in the implementer's handoff. Cite the guide file and section when you rely on one (CORE-05).

**Checks to run** come from the same search: the format and lint commands in the guide or configs. Reviewers run them in **check mode only** (no auto-fix, no writes); the implementer may run the formatter on the files it changed. Examples: `mix format --check-formatted`, `mix credo`, `eslint`, `prettier --check`, `tsc --noEmit`. If a command needs setup you don't have, say it wasn't run.

**Implementing:** the implementer follows both the **coding conventions** (structure, layering, naming, error handling, tests) and the **review guide** (the checklist reviewers will apply to the PR) while writing, not only at review. Reading the review guide first means the self-review and Gate 3 find less. Follow them for: naming, layering, module placement, error handling, test conventions and the formatter's output. If a guide conflicts with the spec or plan, the spec wins on behaviour and the guide on form; flag the conflict. If the engineer asks for something the guide forbids, say so before doing it (CORE-06).
