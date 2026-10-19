// Workspace metadata smoke test: exercise generated standalone bundle, not
// editor's copy of source module.
import { readFileSync } from "node:fs"
import { check, dom } from "./harness.mjs"

const bundle = readFileSync(
  new URL("../../../daisy/Vendor/WorkspaceMetadata/workspace-metadata.min.js", import.meta.url), "utf8")
const fixtures = JSON.parse(readFileSync(
  new URL("../../../tests/fixtures/workspace-metadata.json", import.meta.url)))
dom.window.eval(bundle)

for (const fixture of fixtures) {
  const metadata = dom.window.WorkspaceMetadataExtractor.extractMetadata(fixture.source)
  check(`workspace metadata: ${fixture.name}`, JSON.stringify(metadata) === JSON.stringify(fixture.expected))
}
