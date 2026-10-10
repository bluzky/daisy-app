// Headless smoke test for the bundled editor: constructs the editor in
// jsdom and exercises it section by section (see ./smoke). Sections share one
// jsdom window and run strictly in order. Run with `node smoke-test.mjs`.
import { results } from "./smoke/harness.mjs"

for (const section of ["editor-basics", "tables", "extension-modules", "slash-commands", "inline-formatting", "lists-and-brackets", "live-preview", "code-blocks", "table-widget", "find", "block-exits", "code-fences"]) {
  await import(`./smoke/${section}.mjs`)
}

process.exit(results.failures ? 1 : 0)
