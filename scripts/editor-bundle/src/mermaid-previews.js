import { fencePreviewField } from "./fence-previews.js"
import { MermaidWidget } from "./widgets/mermaid.js"

// Only an edit touching fence syntax or the language name can add or remove
// a diagram; other edits move the existing ones.
export const mermaidPreviews = fencePreviewField({
  languages: ["mermaid"],
  triggerPattern: /[`~]|mermaid/i,
  widget: (details) => new MermaidWidget(details.source),
})
