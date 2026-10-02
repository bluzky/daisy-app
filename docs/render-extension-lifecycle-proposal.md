# Proposal: render extension lifecycle and hooks

Status: draft for discussion. No code changes accompany this document.
Scope: the compiled-in, toggleable render extensions (`docs/render-extensions.md`)
and the page runtime they run in. Third-party plugins stay a non-goal.

## 1. Why change anything

The registry shipped with two extensions and the lifecycle grew by patching.
Reviewing the collapsible-headings work exposed the same root cause three times:
the core needs to know something about extension behaviour that the interface
has no place to say.

| Symptom we hit | Underlying gap |
| --- | --- |
| Collapse state moved to the wrong section after an edit | State capture is a module-level variable plus a one-shot reset; no per-extension state contract, no document identity |
| Outline/fragment navigation into a collapsed section did nothing | Navigation is core, visibility is the extension's; the link between them is a global (`MdPreview.revealElement`) the extension assigns itself |
| First plain document with headings took the fast path and lost collapse CSS/JS | The loaded page's capabilities were a hand-written Bool struct (math, mermaid, code) that had to be extended per feature |
| `beforeUpdate` added just for collapse | Hooks are added one at a time, per need, with no phase model |
| New strings missing translations | Titles live in a `switch`; nothing ties registry entries to the locale files |

Other friction in the current design:

- **Two JS registries.** `registerReapplier` (used by `lazyRenderer` for Mermaid, KaTeX, highlight) and `registerRenderer` (`{ id, render, beforeUpdate }`) both exist; `renderAll` runs one after the other. Built-ins and extensions therefore follow different models.
- **Activation is evaluated twice.** `transform(...).active` runs in `applyRenderExtensions`, then `activeRenderExtensions` calls `transform` again against the full body (to catch headings only inside footnotes). Activation and transformation are one method with two jobs.
- **Assets are fixed at page load.** A fast-path body swap cannot add CSS or JS, so any document that needs an asset the page lacks must reload. The rule for "lacks" is implicit.
- **Manual per-extension chores.** Title switch, Quick Look target membership in `project.pbxproj`, the symlink under `tests/swift-tests/Sources/MarkdownHelpers/`.

## 2. Goals and non-goals

Goals

1. One lifecycle, named phases, each hook with a stated contract.
2. The core never mentions a specific extension; extensions never write to shared globals.
3. State that must survive an update is owned by the extension, handed back by the core, and scoped to a document.
4. Fast-path eligibility derived from data, not hand-extended per feature.
5. A new extension is one file plus one registry line; chores that can be checked by a test are.

Non-goals

- Installable or third-party extensions. Everything stays compiled in and trusted.
- Moving Mermaid, Math, Callout, or code highlighting into the registry in the first phase. They are in scope, but land last (section 7).
- Changing what the two shipped extensions look like to users.

## 3. Proposed model

Two halves, deliberately separate: a **Swift half** that runs at render time and decides what goes into the page, and a **page half** that runs inside the WKWebView and reacts to updates.

### 3.1 Swift half

`MarkdownRenderExtension` is split along its two jobs:

| Member | Role |
| --- | --- |
| `id` | Stable name. |
| `descriptor` | Static metadata: localized-title key, optional one-line description key, `defaultEnabled`, and `userToggleable`. Replaces the title `switch` and drives the Settings list. `defaultEnabled` applies only to toggleable extensions; non-toggleable built-ins are always enabled. |
| `isActive(in:)` | Pure predicate over article HTML after footnotes and earlier active transforms. Answers only "does this document need me?". Evaluated once, immediately before this extension's transform. |
| `transform(_:)` | Optional HTML rewrite. Defaults to identity. No longer returns `active`. |
| `assets(mode:)` | Static CSS and JS declaration. An active document emits both; the warmup shell emits only its CSS for every enabled extension. |
| `order` | Explicit ascending pipeline position. Orders must be unique; registry validation rejects duplicates. |

The render result reports a **script asset set**: identifiers of JavaScript capabilities the emitted page can run (`"math"`, `"mermaid"`, `"code"`, plus each active extension id). It replaces the separate Bool flags and `activeExtensionIDs`. CSS availability is tracked separately by the warmup-shell rule in section 6.

### 3.2 Page half

One registration call replaces both `registerReapplier` and `registerRenderer`:

```
MdPreview.registerExtension({
  id,
  setup?(host),
  render(root, { host, reason, snapshot }),
  beforeUpdate?(root, host) -> snapshot,
  reveal?(el, host) -> boolean,
  onThemeChange?(theme, host),
  dispose?(host)
})
```

`host` is a small, stable surface: the article element, `pushHeight`, the
document id, the current theme, and a performance logger. Extensions get
nothing else from the host. `render` receives its own `{ host, reason,
snapshot }` context; `snapshot` is only the result from the same extension's
immediately preceding `beforeUpdate` for the same document. `beforeUpdate` is
synchronous and returns plain data only.

### 3.3 Lifecycle

```
page load
  assets run -> registerExtension(...)  -> setup(host)           once per extension

initial / each update(articleHTML, { documentID, ... })
  if documentID changed:           discard every saved snapshot
  for each registered extension (ordered): snapshot = beforeUpdate(root, host)  capture live state
  core: morph or replace article
  for each registered extension (ordered): render(root, { host, reason, snapshot })  idempotent decorate
  core: discard snapshots after this cycle

theme change
  for each extension:             onThemeChange(theme, host)

navigation to an element (outline click, #fragment, find, scroll-to)
  core: revealElement(el) = any extension.reveal(el) returned true -> re-measure

page teardown / extension disabled (future)
  for each extension:             dispose(host)
```

`reason` is `initial`, `update`, or `reapply`, so an extension can skip work that does not apply. `theme` changes use `onThemeChange` and do not invoke `render`.

## 4. Hook contracts

| Hook | Called | Must | Must not |
| --- | --- | --- | --- |
| `setup` | Once, when extension registers | Read only `host`; install delegated listeners | Touch article content |
| `beforeUpdate` | Immediately before morph/replace, on live tree | Synchronously return plain serializable snapshot, or nothing | Mutate DOM |
| `render` | After every initial render and update | Be idempotent; use only own same-document snapshot; tolerate nodes preserved by morph; mark owned nodes | Assume fresh tree; throw |
| `reveal` | Before core measures navigation target | Make element measurable; return whether anything changed | Scroll |
| `onThemeChange` | After core applies theme | Restyle in place | Re-render article |
| `dispose` | Teardown | Remove listeners and owned nodes | Rely on being called on crash |

Cross-cutting rules:

- **Isolation.** Core wraps every hook in try/catch and logs with the extension id and hook name; one failure never blocks another.
- **Owned DOM.** Nodes an extension injects carry `data-mdp-ext="<id>"` so the morph configuration can preserve or skip them uniformly, instead of per-extension special cases.
- **Identity.** An extension that keeps per-node state supplies its own stable key. Collapsible headings would key by level, text, and repeat index inside its own `beforeUpdate`/`render`, not through a core-wide id scheme.
- **Determinism.** For fixed article and host context, an extension produces the same output; it creates no clocks, random ids, or network requests.

## 5. State and document identity

- `update()` gains a `documentID` supplied by the host (file URL, or a per-window token for untitled documents). Core keeps one snapshot slot per extension.
- Snapshots are **never** applied across a `documentID` change, which closes the "heading text matches in a different document" gap noted in review. Within a document they are consumed once per update cycle by core, so extensions no longer clear their own state.
- **Identity rule (decided).** File-backed documents use the file URL. Untitled documents, and Quick Look previews, use a random id generated once when the document or preview is created and kept stable for its lifetime. It must not change between updates of the same document, or snapshots would be dropped on every keystroke. Opening a different file in the same window changes the id, which is the intended reset.
- Across a full page reload nothing persists. Persisting collapse state per file (`UserDefaults` keyed by document and heading key) is possible later and is not part of this proposal.

## 6. Page capabilities and the fast path

- A loaded page records its **script asset set** (section 3.1). A body swap is allowed only if the next document's required script set is a subset of it. This is the current fix, generalised: Bool flags disappear, and a future extension needs no change to `RendererFingerprint`.
- **Decided:** the warmup shell always emits the **CSS** of every enabled extension, even inactive ones. CSS is selector-scoped, small, and inert without matching markup, so only JS-bearing extensions can force a reload. Cost: a few extra KB of CSS in every page, and the shell is no longer style-neutral. The script asset set alone controls the fast-path rule; CSS is assumed present for enabled extensions, and a settings change still reloads.
- Settings changes keep using a full reload; live enable/disable via `dispose` is a possible later step, not assumed here.

## 7. Built-ins (decided: they join the registry)

Mermaid, Math (KaTeX), Callout, and highlight move behind `MarkdownRenderExtension`, so there is one model. Differences to preserve: they are not user-toggleable (the `descriptor` carries `userToggleable: false`, so they stay out of Settings → Extensions), and Mermaid, KaTeX, and highlight load large vendor bundles after first paint (`lazyAssets` replaces `MdPreviewLazy.lazyRenderer`, keeping the `.inline` and `.lazy` vendor modes and Quick Look self-containment).

Sequencing: the page half lands first with a compatibility shim that adapts today's `registerReapplier` callers into `render`-only extensions, so built-ins keep working while collapsible and colorful headings migrate. The built-ins then move one at a time, highlight first (smallest), Mermaid last (most Quick Look and performance sensitivity). Fingerprint Bools (`math`, `mermaid`, `code`) disappear once the last one moves.

## 8. Tooling and checks that should exist

- **Localization test.** Enumerate the registry; assert every `descriptor` title/description key exists in `en` and in every other shipped locale. This is the guard the P2 review comment wanted.
- **Quick Look membership test or script.** Fail if an extension file is missing from the Quick Look target or the test package symlinks.
- **Registry contract tests.** Orders are unique and stable; inactive documents emit no document JS; `isActive` runs once per extension against its pipeline input; hooks are isolated (throwing extension does not stop next).
- **Lifecycle tests in WebKit**, extending `MdPreviewUpdateTests`: snapshot round-trip, snapshot dropped on `documentID` change, `reveal` aggregation, theme hook delivery, and find selecting a match hidden by a collapsed section.

## 9. Migration plan

| Phase | Change | Risk |
| --- | --- | --- |
| 0 | Land this document; agree open questions | None |
| 1 | Page half: introduce `registerExtension` and shim; move collapsible headings onto `beforeUpdate` snapshots and `reveal`; make find select hidden extension content before reveal; remove `window.MdPreview.revealElement` assignment | Low; behaviour covered by existing tests |
| 2 | Swift half: split `isActive` from `transform`, add `descriptor`; single activation pass; script asset set replaces Bool fingerprint | Medium; touches `MarkdownWebView` fast path |
| 3 | `documentID` through `MarkdownWebView.display` and `update` | Medium; host API change |
| 4 | Tooling tests from section 8; update `docs/render-extensions.md` | Low |
| 5 | Built-ins onto the registry, one at a time: highlight, Callout, Math, Mermaid | Higher; vendor loading, performance, Quick Look |

Each phase is independently shippable and keeps `docs/render-extensions.md` truthful in the same commit, per the repository's documentation rule.

## 10. Decisions

Decided

1. The warmup shell always includes the CSS of every enabled extension.
2. Untitled documents and Quick Look use a random document id, generated once and stable for the document's lifetime. File-backed documents use the file URL.
3. Built-ins join the registry, sequenced last.

4. **Live enable/disable: not in this design.** Toggling an extension in Settings keeps today's behaviour (open previews reload). `dispose` stays in the interface so live toggling can be added later without redesign.
5. **Find: no new hook.** Find must include content hidden by extensions when collecting candidates, while excluding renderer-owned hidden mirrors through generic `data-mdp-search-exclude`. After choosing and marking match, find calls existing `reveal(el)` before measuring it. Collapsible headings therefore open around selected match.

## 11. Alternatives considered

- **Keep patching hook by hook.** Cheapest now; each new extension that hides or rewrites content adds another ad hoc global and another core special case.
- **Event bus** (`MdPreview.on('beforeUpdate', fn)`). Flexible, but unordered, harder to test, and hides the contract; named hooks on a registered object keep ordering and isolation explicit.
- **Server-side only** (do everything in Swift, no page hooks). Not possible for collapse, reveal, or anything reacting to live DOM state.
