import { LanguageDescription, LanguageSupport, StreamLanguage } from "@codemirror/language"
import { javascript } from "@codemirror/lang-javascript"
import { python } from "@codemirror/lang-python"
import { json } from "@codemirror/lang-json"
import { css } from "@codemirror/lang-css"
import { html } from "@codemirror/lang-html"
import { swift } from "@codemirror/legacy-modes/mode/swift"
import { shell } from "@codemirror/legacy-modes/mode/shell"
import { yaml } from "@codemirror/legacy-modes/mode/yaml"
import { go } from "@codemirror/legacy-modes/mode/go"
import { ruby } from "@codemirror/legacy-modes/mode/ruby"
import { rust } from "@codemirror/legacy-modes/mode/rust"
import { c, cpp, java, kotlin, objectiveC, csharp } from "@codemirror/legacy-modes/mode/clike"
import { sql } from "@codemirror/legacy-modes/mode/sql"
import { toml } from "@codemirror/legacy-modes/mode/toml"
import { hcl } from "codemirror-lang-hcl"

// ---------------------------------------------------------------------------
// Fenced-code languages
// ---------------------------------------------------------------------------

// Keep automatic detection conservative. Explicit info-string languages
// always remain the source of truth.
export function detectLanguage(source) {
  const text = source.trim()
  if (!text) return ""
  if (/^#!.*\b(?:ba)?sh\b|^\s*\$\s+/.test(text)) return "bash"
  if ((text.startsWith("{") && text.endsWith("}"))
      || (text.startsWith("[") && text.endsWith("]"))) {
    try { JSON.parse(text); return "json" } catch (_) {}
  }
  if (/^\s*(?:<!DOCTYPE\s+html|<html\b|<(?:div|span|section|article)\b)/i.test(text)) return "html"
  if (/\b(?:resource|data|provider|variable|module)\s+["'][\w-]+["'](?:\s+["'][\w-]+["'])?\s*\{|\bterraform\s*\{/.test(text)) return "hcl"
  if (/\b(?:import\s+Foundation|func\s+\w+\s*\(|@main)\b|\b(?:let|var)\s+\w+\s*:\s*(?:String|Int|Bool|Double|Float)\b/.test(text)) return "swift"
  if (/^\s*(?:#\s*include\s*<iostream>|(?:using\s+namespace\s+std|std::\w+|(?:cout|cin)\s*(?:<<|>>))\b)/m.test(text)) return "cpp"
  if (/^\s*(?:#\s*include\s*[<"](?:assert|ctype|errno|float|inttypes|limits|math|setjmp|signal|stdarg|stdbool|stddef|stdint|stdio|stdlib|string|time)\.h[>"]|(?:int|void)\s+main\s*\([^)]*\)\s*\{)/m.test(text)) return "c"
  if (/^\s*(?:async\s+)?def\s+\w+\s*\(|^\s*from\s+\w+[\w.]*\s+import\b|^\s*class\s+\w+\s*[:(]/m.test(text)) return "python"
  if (/\b(?:SELECT|INSERT|UPDATE|DELETE|CREATE\s+(?:TABLE|VIEW|INDEX)|WITH)\b[\s\S]*\b(?:FROM|INTO|WHERE|AS)\b/i.test(text)) return "sql"
  if (/(?:^|\n)\s*(?:[#.]?[A-Za-z][\w-]*)\s*\{[\s\S]*:[\s\S]*\}/.test(text)
      || /@(?:media|keyframes|supports)\b/.test(text)) return "css"
  if (/^\s*(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*(?::[^=\n]+)?\s*=/m.test(text)
      || /\b(?:function\s+\w+\s*\(|console\.(?:log|error|warn)|=>)/.test(text)) return "javascript"
  if (/^\s*(?:[-A-Za-z_][\w-]*):\s*(?:[^:#\n]|$)/m.test(text)
      && !/[{};]/.test(text)) return "yaml"
  if (/^\s*(?:echo|printf|export|source|cd|mkdir|rm|cp|mv)\s+/m.test(text)) return "bash"
  return ""
}

// Every parser is already part of this offline bundle, so register support
// synchronously. Lazy Promise loaders only delayed highlighting on the first
// fenced block without reducing the shipped JavaScript.
const legacy = (name, alias, parser) =>
  LanguageDescription.of({
    name,
    alias,
    support: new LanguageSupport(StreamLanguage.define(parser)),
  })

export const codeLanguages = [
  LanguageDescription.of({
    name: "javascript",
    alias: ["js", "jsx", "ts", "tsx", "typescript", "node"],
    support: javascript({ jsx: true, typescript: true }),
  }),
  LanguageDescription.of({ name: "python", alias: ["py"], support: python() }),
  LanguageDescription.of({ name: "json", alias: ["jsonc"], support: json() }),
  LanguageDescription.of({ name: "css", alias: ["scss"], support: css() }),
  LanguageDescription.of({ name: "html", alias: ["htm", "xml"], support: html() }),
  LanguageDescription.of({ name: "hcl", alias: ["terraform", "tf"], support: hcl() }),
  legacy("swift", [], swift),
  legacy("shell", ["sh", "bash", "zsh", "console"], shell),
  legacy("yaml", ["yml"], yaml),
  legacy("go", ["golang"], go),
  legacy("ruby", ["rb"], ruby),
  legacy("rust", ["rs"], rust),
  legacy("c", ["h"], c),
  legacy("cpp", ["c++", "cc", "hpp"], cpp),
  legacy("java", [], java),
  legacy("kotlin", ["kt"], kotlin),
  legacy("objective-c", ["objc", "objectivec"], objectiveC),
  legacy("csharp", ["cs", "c#"], csharp),
  legacy("sql", [], sql({})),
  legacy("toml", [], toml),
]
