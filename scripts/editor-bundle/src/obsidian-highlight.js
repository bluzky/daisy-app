// ---------------------------------------------------------------------------
// Obsidian-style text highlights
// ---------------------------------------------------------------------------

const highlightDelimiter = { resolve: "Highlight", mark: "HighlightMark" }
const highlightPunctuation = /[\p{S}\p{P}]/u

function highlightWhitespace(value) {
  return !value || /\s/.test(value)
}

function highlightPunctuationAround(value) {
  return !!value && highlightPunctuation.test(value)
}

// Lezer's delimiter resolver then handles nesting with emphasis, links, and
// adjacent highlights. Keeping the parser extension here (rather than
// matching the DOM after parsing) also means code spans and fenced code are
// naturally excluded by the Markdown grammar.
export const obsidianHighlight = {
  defineNodes: ["Highlight", "HighlightMark"],
  parseInline: [{
    name: "Highlight",
    parse(cx, next, pos) {
      if (next !== 61 || cx.char(pos + 1) !== 61) return -1
      let runStart = pos
      while (runStart > cx.offset && cx.char(runStart - 1) === 61) runStart--
      let runEnd = pos + 2
      while (cx.char(runEnd) === 61) runEnd++
      const pairStart = runStart + ((runEnd - runStart) % 2)
      if (pos < pairStart || (pos - pairStart) % 2 !== 0) return -1
      let backslashes = 0
      for (let cursor = runStart - 1;
           cursor >= cx.offset && cx.char(cursor) === 92;
           cursor--) {
        backslashes++
      }
      if (backslashes % 2 !== 0) return -1
      const before = cx.slice(runStart - 1, runStart)
      const after = cx.slice(runEnd, runEnd + 1)
      const spaceBefore = highlightWhitespace(before)
      const spaceAfter = highlightWhitespace(after)
      const punctuationBefore = highlightPunctuationAround(before)
      const punctuationAfter = highlightPunctuationAround(after)
      const leftFlanking = !spaceAfter
        && (!punctuationAfter || spaceBefore || punctuationBefore)
      const rightFlanking = !spaceBefore
        && (!punctuationBefore || spaceAfter || punctuationAfter)
      return cx.addDelimiter(
        highlightDelimiter,
        pos,
        pos + 2,
        leftFlanking,
        rightFlanking,
      )
    },
    after: "Emphasis",
  }],
}
