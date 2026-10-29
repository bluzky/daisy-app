import { build } from "esbuild"
import { mkdir, writeFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"

const bundles = [
  {
    entry: "entry-cm.js",
    output: "../../daisy/Vendor/CodeMirror/mdedit.min.js",
  },
  {
    entry: "src/workspace-metadata.js",
    output: "../../daisy/Vendor/WorkspaceMetadata/workspace-metadata.min.js",
    globalName: "WorkspaceMetadataExtractor",
  },
]

for (const bundle of bundles) {
  const outputURL = new URL(bundle.output, import.meta.url)
  const result = await build({
    entryPoints: [fileURLToPath(new URL(bundle.entry, import.meta.url))],
    bundle: true,
    minify: true,
    format: "iife",
    globalName: bundle.globalName,
    write: false,
  })
  // Some dependency completion snippets contain whitespace-only physical lines.
  // Normalize line endings so checked-in bundles stay reproducible.
  const output = result.outputFiles[0].text.replace(/[ \t]+$/gm, "")
  await mkdir(new URL(".", outputURL), { recursive: true })
  await writeFile(outputURL, output)
}
