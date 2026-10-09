// Typora-style live-preview markdown editor for Daisy.app.
// Bundled with esbuild into a single self-contained IIFE exposing
// window.MDEditor. The document buffer IS the markdown source — saving
// is byte-faithful. Formatting syntax is styled live and marks hide
// themselves unless the cursor is inside the construct.
//
// The editor lives in ./src; build.mjs bundles from this entry point.

// Editor modules self-register on import; the order below is the order they
// appear in the editor's extension list.
import "./src/extensions.js"
import "./src/slash.js"
import "./src/api.js"
