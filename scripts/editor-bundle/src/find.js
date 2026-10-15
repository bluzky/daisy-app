import { EditorView, Decoration } from "@codemirror/view"
import { StateEffect, StateField } from "@codemirror/state"

// Search the source buffer, including lines outside CodeMirror's mounted DOM.
// Decorations keep highlights visible while the native find bar owns focus.
//
// buildPattern must stay in step with SearchPatternScript.swift, which the
// rendered preview uses; tests/fixtures/find-parity.json pins both.
export const setFind = StateEffect.define()

// Highlighting thousands of matches stalls typing; the count reads "N+".
export const MATCH_LIMIT = 10000

const WORD = "[\\p{L}\\p{N}_]"
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

export function normalizeOptions(options) {
  const mode = options && (options.mode === "word" || options.mode === "regex") ? options.mode : "substring"
  return { mode, caseSensitive: !!(options && options.caseSensitive) }
}

// Throws a SyntaxError for an invalid regex.
export function buildPattern(query, options) {
  const { mode, caseSensitive } = normalizeOptions(options)
  const flags = "gmu" + (caseSensitive ? "" : "i")
  if (mode === "regex") return new RegExp(query, flags)
  const literal = escapeRegExp(query)
  return new RegExp(mode === "word" ? `(?<!${WORD})${literal}(?!${WORD})` : literal, flags)
}

// Every non-empty match, capped at `limit`. `error` is set for an invalid regex.
export function collectMatches(doc, query, options, limit = Infinity) {
  const result = { matches: [], capped: false, error: false }
  if (!query) return result
  let pattern
  try {
    pattern = buildPattern(query, options)
  } catch {
    result.error = true
    return result
  }
  for (const match of doc.toString().matchAll(pattern)) {
    if (!match[0]) continue
    if (result.matches.length >= limit) {
      result.capped = true
      break
    }
    result.matches.push({ from: match.index, to: match.index + match[0].length, match })
  }
  return result
}

// Regex replacements expand $1, $<name>, $&, $$ and \n \t \\; the other modes
// insert the replacement as typed.
export function expandReplacement(template, entry, options) {
  if (normalizeOptions(options).mode !== "regex") return template
  const { match } = entry
  const groupCount = match.length - 1
  return template.replace(/\\([nt\\])|\$(\$|&|<[^>]*>|\d{1,2})/g, (token, escape, ref) => {
    if (escape) return escape === "n" ? "\n" : escape === "t" ? "\t" : "\\"
    if (ref === "$") return "$"
    if (ref === "&") return match[0]
    if (ref[0] === "<") return match.groups?.[ref.slice(1, -1)] ?? ""
    let n = Number(ref)
    if (ref.length === 2 && (n > groupCount || n === 0)) {
      // "$12" with fewer than 12 groups reads as "$1" followed by "2".
      n = Number(ref[0])
      if (n >= 1 && n <= groupCount) return (match[n] ?? "") + ref[1]
      return token
    }
    return n >= 1 && n <= groupCount ? match[n] ?? "" : token
  })
}

function findState(doc, query, options, index = 0) {
  options = normalizeOptions(options)
  const { matches, capped, error } = collectMatches(doc, query, options, MATCH_LIMIT)
  index = matches.length ? Math.min(Math.max(index, 0), matches.length - 1) : -1
  const decorations = Decoration.set(matches.map((match, i) =>
    Decoration.mark({ class: i === index ? "cm-find-match cm-find-current" : "cm-find-match" })
      .range(match.from, match.to)))
  return { query, options, matches, index, decorations, capped, error }
}

export const sameSearch = (state, query, options) => {
  options = normalizeOptions(options)
  return state.query === query
    && state.options.mode === options.mode
    && state.options.caseSensitive === options.caseSensitive
}

export const documentFind = StateField.define({
  create: (state) => findState(state.doc, "", null),
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setFind)) {
        const { query, options, index } = effect.value
        return findState(tr.state.doc, query, options, index)
      }
    }
    return tr.docChanged
      ? findState(tr.state.doc, value.query, value.options, value.index)
      : value
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
})
export function currentFindTouches(state, from, to) {
  const search = state.field(documentFind)
  const match = search.matches[search.index]
  return !!match && match.from < to && match.to > from
}
export const findTheme = EditorView.baseTheme({
  ".cm-find-match": { backgroundColor: "#ffe58a", color: "#201800", borderRadius: "2px" },
  ".cm-find-current": { backgroundColor: "#ffad33", outline: "1px solid #9b5700" },
})
