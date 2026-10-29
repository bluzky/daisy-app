import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { extractMetadata } from "./src/workspace-metadata.js"

const fixtures = JSON.parse(readFileSync(new URL("../../tests/fixtures/workspace-metadata/grammar.json", import.meta.url)))
for (const fixture of fixtures) {
  assert.deepEqual(extractMetadata(fixture.source), fixture.expected, fixture.name)
  assert.equal(fixture.source, fixture.source.slice(), `${fixture.name}: extraction is read-only`)
  console.log(`PASS  ${fixture.name}`)
}
