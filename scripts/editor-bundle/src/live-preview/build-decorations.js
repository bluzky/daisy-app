import { Decoration } from "@codemirror/view"
import { LanguageDescription } from "@codemirror/language"
import { highlightTree, tags as t } from "@lezer/highlight"
import { codeHighlight } from "../code-highlight.js"
import { HEADING_LINE, METRICS, SEPARATOR_BLOCKS, activeBulletDeco, activeOrderedDeco, blockGapLine, blockSeparatorLine, bulletDeco, codeLine, codeLineFirst, codeLineLast, codeScrollText, collapsedLine, completedTaskLine, emphasisMark, fenceMark, frontmatterDelim, frontmatterFirstLine, frontmatterLastLine, frontmatterLine, headingAfterBlankLine, headingMarker, headingPrefix, hiddenCodeFenceSource, hiddenHeadingSource, hide, highlightMark, hrDeco, imageLine, inactiveHeadingLine, linkMark, listContinuationLine, listDepthLine, listItemGapLine, listItemLine, markdownListMarker, orderedDeco, quoteLine, ruleLine, setextMarkerLine, setextSource, strikethroughMark, strongMark, tableLine, taskLine, urlMark } from "../decoration-parts.js"
import { fencedCodeDetails } from "../fenced-code.js"
import { currentFindTouches } from "../find.js"
import { codeLanguages } from "../languages.js"
import { pendingCoversFence, previewTree } from "../commands/code-fence.js"
import { activeCodeBlock, pointerPreview } from "../pointer.js"
import { TaskCheckboxWidget } from "../task-list.js"
import { ImageWidget } from "../widgets/basic.js"
import { CodeLanguageWidget, wrappedCodeBlocks } from "../widgets/code.js"

function detectedCodeHighlights(details, cache) {
  const cached = cache.get(details.sourceFrom)
  if (cached?.language === details.detectedLanguage
      && cached.source === details.source) {
    return cached.tokens
  }

  const tokens = []
  const language = LanguageDescription.matchLanguageName(
    codeLanguages, details.detectedLanguage, false
  )?.support?.language
  if (language) {
    highlightTree(language.parser.parse(details.source), codeHighlight,
      (from, to, classes) => {
        tokens.push({ from, to, mark: Decoration.mark({ class: classes }) })
      })
  }
  cache.set(details.sourceFrom, {
    language: details.detectedLanguage,
    source: details.source,
    tokens,
  })
  return tokens
}

export function buildDecorations(view, detectedCodeCache) {
  const ranges = []
  const { state } = view
  const pointer = state.field(pointerPreview)
  const sel = pointer?.selection ?? state.selection.main
  const activeFence = pointer ? pointer.fence : state.field(activeCodeBlock)
  const focused = pointer ? pointer.focused : view.hasFocus

  // CodeMirror always owns a selection at offset zero, even before the user
  // clicks the editor. Only reveal source syntax when the editor truly has
  // keyboard focus; otherwise the first block looks spuriously active.
  // Keep source syntax visible for an insertion caret and while an IME
  // composition owns a non-empty selection. Ordinary range selections stay
  // in live-preview form, so Cmd-A and drag selections do not reveal every
  // Markdown marker they span.
  const sourceCaret = focused && (sel.empty || view.compositionStarted)
    ? sel.head
    : null
  const touches = (from, to) => currentFindTouches(state, from, to)
    || (sourceCaret != null && sourceCaret >= from && sourceCaret <= to)
  const touchesLineOf = (pos) => {
    const line = state.doc.lineAt(pos)
    return touches(line.from, line.to)
  }
  const isActiveFence = (node) => currentFindTouches(state, node.from, node.to)
    || (activeFence != null && node.from <= activeFence.from && node.to >= activeFence.to)
  // Auto-closing brackets can form a valid task before the user types `]`.
  // Keep its source editable until the caret has left the brackets.
  const editingTaskMarker = (bracket) => sourceCaret != null
    && sourceCaret > bracket && sourceCaret < bracket + 3
  const decoratedLines = new Set()
  const listDepthPositions = new Set()
  const lineOnce = (pos, deco) => {
    const line = state.doc.lineAt(pos)
    const key = deco.spec.class + "@" + line.from
    if (decoratedLines.has(key)) return
    decoratedLines.add(key)
    ranges.push(deco.range(line.from))
  }
  const eachLine = (from, to, deco) => {
    let pos = from
    while (pos <= to) {
      const line = state.doc.lineAt(pos)
      lineOnce(line.from, deco)
      if (line.to >= to) break
      pos = line.to + 1
    }
  }
  const indentationColumns = (indentation) => {
    let columns = 0
    for (const character of indentation) {
      columns = character === "\t"
        ? columns + (4 - (columns % 4))
        : columns + 1
    }
    return columns
  }
  // Repeated Tab can move a list-looking source line beyond the indentation
  // depth that the CommonMark parser still recognizes as a ListItem. Keep the
  // editor geometry stable at that boundary: ordinary indented code is left
  // alone, while a line with an explicit list marker retains list styling.
  const decorateRawIndentedListLine = (line, match) => {
    const indentation = match[1]
    const marker = match[2]
    const separator = match[3]
    const markerFrom = line.from + indentation.length
    const markerTo = markerFrom + marker.length
    const depth = Math.floor(indentationColumns(indentation) / 4) + 1

    lineOnce(line.from, listItemLine)
    lineOnce(line.from, listDepthLine(depth))
    listDepthPositions.add(line.from)
    if (line.number > 1
        && markdownListMarker.test(state.doc.line(line.number - 1).text)) {
      lineOnce(line.from, listItemGapLine)
    }
    if (indentation.length > 0) {
      ranges.push(hide.range(line.from, markerFrom))
    }

    const isTask = /^[-+*]$/.test(marker)
      && /^\s*\[[ xX]\](\s|$)/.test(line.text.slice(markerTo - line.from))
    if (isTask) {
      const task = line.text.slice(markerTo - line.from).match(/^[ \t]*\[([ xX])\][ \t]?/)
      const bracket = markerTo + task[0].indexOf('[')
      if (editingTaskMarker(bracket)) return
      lineOnce(line.from, taskLine)
      if (task[1] !== ' ') lineOnce(line.from, completedTaskLine)
      ranges.push(Decoration.replace({ widget: new TaskCheckboxWidget(bracket + 1, task[1] !== ' ') })
        .range(markerFrom, markerTo + task[0].length))
    } else if (/^[-+*]$/.test(marker)) {
      if (touchesLineOf(markerFrom)) {
        ranges.push(activeBulletDeco.range(markerFrom, markerTo))
        if (separator.length > 0) {
          ranges.push(hide.range(markerTo, markerTo + separator.length))
        }
      } else {
        ranges.push(bulletDeco.range(
          markerFrom,
          markerTo + separator.length
        ))
      }
    }
  }
  // The renderer shrinks the final source blank line of a run to blankGap
  // before applying semantic block margins. Keep the editor's final blank
  // separator at blankGap plus those margins; earlier blank lines already
  // retain their normal CodeMirror line height.
  const blankRunBefore = (pos) => {
    const line = state.doc.lineAt(pos)
    let first = line.number
    // Only "one blank" vs "several" (plus the document-start case) changes
    // the emitted separator, so cap the walk against pathological runs.
    const stop = Math.max(first - 64, 1)
    while (first > stop && state.doc.line(first - 1).text.length === 0) first--
    return { line, first, count: line.number - first }
  }
  const blockMarginTop = (node) => {
    switch (node.name) {
      case "Blockquote": {
        // Alert blockquotes render as .markdown-alert; recognize the same
        // five kinds as EscapingHTMLFormatter.
        const firstLine = state.doc.lineAt(node.from)
        return /^ {0,3}> ?\[!(note|tip|important|warning|caution)\]/i.test(firstLine.text)
          ? METRICS.alert : METRICS.quote
      }
      case "Table": return METRICS.table
      case "HorizontalRule": return METRICS.hr
      case "FencedCode":
        // Mermaid fences render as .mermaid-figure (same margin as tables).
        return fencedCodeDetails(state, node).language === "mermaid"
          ? METRICS.table : METRICS.paragraph
      default: return METRICS.paragraph
    }
  }
  // Adjacent blocks: the preview gives the second block its margin-top even
  // without a blank line (a paragraph right under a heading, a fence right
  // after a paragraph). Put that gap on the previous block's last line.
  let frontmatterTo = -1
  const gapBeforeAdjacent = (node) => {
    const line = state.doc.lineAt(node.from)
    if (line.number === 1 || line.from <= frontmatterTo) return
    if (blankRunBefore(node.from).count !== 0) return
    lineOnce(state.doc.line(line.number - 1).from, blockGapLine(blockMarginTop(node)))
  }
  const separatorBlankBefore = (node) => {
    const run = blankRunBefore(node.from)
    if (run.count === 0) return
    const separator = state.doc.line(run.line.number - 1)
    if (run.first === 1) {
      lineOnce(
        separator.from,
        blockSeparatorLine(METRICS.blankGap + blockMarginTop(node))
      )
      return
    }
    const marginTop = blockMarginTop(node)
    const height = METRICS.blankGap + marginTop
    lineOnce(separator.from, blockSeparatorLine(height))
  }

  // yamlFrontmatter wraps the Markdown parser as Document(Document(...)), so
  // discover the inner content Document and treat its direct children as the
  // top-level Markdown blocks. Tracking depth (and a stack of enclosing
  // lists) answers parent/sibling questions positionally without
  // materializing a SyntaxNode per visited node.
  let depth = 0
  const listStack = []
  const quoteStack = []
  const quoteLines = new Map()

  for (const { from, to } of view.visibleRanges) {
    let contentDocumentDepth = null
    previewTree(state).iterate({
      from, to,
      enter: (node) => {
        depth++
        const name = node.name

        if (depth === 2 && name === "Document") contentDocumentDepth = depth

        // --- Block separators ------------------------------------------
        if (contentDocumentDepth != null && depth === contentDocumentDepth + 1) {
          if (SEPARATOR_BLOCKS.has(name)) {
            separatorBlankBefore(node)
            gapBeforeAdjacent(node)
          }
        }

        // --- Frontmatter ----------------------------------------------
        // Style the whole block as a quiet metadata card; keep the YAML
        // source editable, dimming only the `---` delimiters.
        if (name === "Frontmatter") {
          // The node's end includes the newline after the closing ---;
          // step back so the card never bleeds onto the first body line.
          const end = node.to > node.from && state.doc.lineAt(node.to).from === node.to
            ? node.to - 1 : node.to
          frontmatterTo = end
          eachLine(node.from, end, frontmatterLine)
          lineOnce(node.from, frontmatterFirstLine)
          lineOnce(state.doc.lineAt(end).from, frontmatterLastLine)
          return
        }
        if (name === "DashLine") {
          ranges.push(frontmatterDelim.range(node.from, node.to))
          return
        }

        // --- Headings ------------------------------------------------
        const atx = name.match(/^ATXHeading(\d)$/)
        if (atx) {
          lineOnce(node.from, HEADING_LINE[+atx[1]])
          if (blankRunBefore(node.from).count > 0) {
            lineOnce(node.from, headingAfterBlankLine)
          }
          if (!touchesLineOf(node.from)) lineOnce(node.from, inactiveHeadingLine)
          return
        }
        const setext = name.match(/^SetextHeading(\d)$/)
        if (setext) {
          lineOnce(node.from, HEADING_LINE[+setext[1]])
          if (blankRunBefore(node.from).count > 0) {
            lineOnce(node.from, headingAfterBlankLine)
          }
          return
        }
        if (name === "HeaderMark") {
          const parent = node.node.parent
          if (parent && /^ATXHeading/.test(parent.name)) {
            ranges.push(headingMarker.range(node.from, node.to))
            const after = state.doc.sliceString(node.to, node.to + 1)
            const markTo = node.to + (after === " " ? 1 : 0)
            const opening = node.from === parent.from
            const line = state.doc.lineAt(node.from)
            // ATX nodes start at '#', excluding up to three valid leading
            // spaces. Include that indentation in the measured prefix, but
            // never consume a surrounding list or blockquote marker.
            const prefixFrom = opening && /^ {0,3}$/.test(state.doc.sliceString(line.from, node.from))
              ? line.from : node.from
            if (opening) ranges.push(headingPrefix.range(prefixFrom, markTo))
            if (!touchesLineOf(node.from)) {
              // Keep the hidden source prefix measurable for alignment.
              // Pointer selection keeps its source anchor across activation.
              ranges.push(hiddenHeadingSource.range(prefixFrom, markTo))
            }
          } else if (parent && /^SetextHeading/.test(parent.name)) {
            lineOnce(node.from, setextMarkerLine)
            ranges.push(setextSource.range(node.from, node.to))
          }
          return
        }

        // --- Blockquotes ----------------------------------------------
        if (name === "Blockquote") {
          quoteStack.push(node.from)
          const quoteFirst = state.doc.lineAt(node.from)
          const parentQuote = node.node.parent?.name === "Blockquote"
          let previous = node.node.prevSibling
          while (previous?.name === "QuoteMark") previous = previous.prevSibling
          const nestedGap = parentQuote && previous ? METRICS.quote : 0
          let pos = node.from
          while (pos <= node.to) {
            const line = state.doc.lineAt(pos)
            const edges = quoteLines.get(line.from) || { depth: 0, starts: 0, ends: 0, gap: 0 }
            edges.depth = Math.max(edges.depth, quoteStack.length)
            // Match the preview's 0.4em padding once per quote boundary,
            // not once per source line (which may wrap or soft-join).
            if (line.from === quoteFirst.from) {
              edges.starts++
              edges.gap += nestedGap
            }
            if (line.to >= node.to) edges.ends++
            quoteLines.set(line.from, edges)
            if (line.to >= node.to) break
            pos = line.to + 1
          }
          return
        }
        if (name === "QuoteMark") {
          if (!touchesLineOf(node.from)) {
            const after = state.doc.sliceString(node.to, node.to + 1)
            ranges.push(hide.range(node.from, node.to + (after === " " ? 1 : 0)))
          }
          return
        }

        // Container paragraphs use their own semantic margin. Their blank
        // source lines are not top-level authored spacers in the preview.
        if (name === "Paragraph" && /^(Blockquote|ListItem)$/.test(node.node.parent?.name || "")) {
          const first = state.doc.lineAt(node.from)
          if (first.number > state.doc.lineAt(node.node.parent.from).number) {
            const previous = state.doc.line(first.number - 1)
            if (/^(?:[ >]*)$/.test(previous.text)) {
              lineOnce(previous.from, blockSeparatorLine(METRICS.paragraph))
            }
          }
        }

        // Escape markers disappear in live preview; the literal character
        // still belongs to the original editable source.
        if (name === "Escape" && !touches(node.from, node.to)) {
          ranges.push(hide.range(node.from, node.from + 1))
          return
        }

        // --- Emphasis family -------------------------------------------
        if (name === "StrongEmphasis") {
          ranges.push(strongMark.range(node.from, node.to))
          return
        }
        if (name === "Emphasis") {
          ranges.push(emphasisMark.range(node.from, node.to))
          return
        }
        if (name === "Strikethrough") {
          ranges.push(strikethroughMark.range(node.from, node.to))
          return
        }
        if (name === "Highlight") {
          const marks = []
          for (let child = node.node.firstChild; child; child = child.nextSibling) {
            if (child.name === "HighlightMark") marks.push(child)
          }
          const contentFrom = marks.length ? marks[0].to : node.from
          const contentTo = marks.length > 1 ? marks[marks.length - 1].from : node.to
          if (contentFrom < contentTo) {
            ranges.push(highlightMark.range(contentFrom, contentTo))
          }
          return
        }
        if (name === "HighlightMark") {
          const parent = node.node.parent
          if (parent && parent.name === "Highlight" && !touches(parent.from, parent.to)) {
            ranges.push(hide.range(node.from, node.to))
          }
          return
        }
        if (name === "EmphasisMark" || name === "StrikethroughMark") {
          const parent = node.node.parent
          if (parent && !touches(parent.from, parent.to)) {
            ranges.push(hide.range(node.from, node.to))
          }
          return
        }

        // --- Inline code ------------------------------------------------
        if (name === "InlineCode") {
          const marks = []
          for (let child = node.node.firstChild; child; child = child.nextSibling) {
            if (child.name === "CodeMark") marks.push(child)
          }
          const contentFrom = marks.length ? marks[0].to : node.from
          const contentTo = marks.length > 1 ? marks[marks.length - 1].from : node.to
          if (contentFrom < contentTo) {
            ranges.push(Decoration.mark({ class: "cm-md-inline-code" })
              .range(contentFrom, contentTo))
          }
          return
        }
        if (name === "CodeMark") {
          const parent = node.node.parent
          if (parent && parent.name === "InlineCode" && !touches(parent.from, parent.to)) {
            ranges.push(hide.range(node.from, node.to))
          } else if (parent && parent.name === "FencedCode"
              && !isActiveFence(parent)) {
            const line = state.doc.lineAt(node.from)
            // Hide the complete source line. Collapsing handles geometry;
            // this mark is also the fallback for fences without an interior
            // line and keeps the raw marker out of the visual code card.
            ranges.push(hiddenCodeFenceSource.range(line.from, line.to))
          }
          return
        }

        // --- Images -------------------------------------------------------
        // Render direct image destinations in place. Keeping the raw node
        // active under the caret makes the source editable without a second
        // editor surface; reference-style images stay as authored source.
        if (name === "Image") {
          // Pruning this node also skips Lezer's leave callback. Balance the
          // depth here so later top-level blocks still get paragraph spacing.
          depth--
          const urlNode = node.node.getChild("URL")
          if (!urlNode) return false
          const rawSource = state.doc.sliceString(urlNode.from, urlNode.to).trim()
          const source = rawSource.startsWith("<") && rawSource.endsWith(">")
            ? rawSource.slice(1, -1)
            : rawSource
          if (!source || source.startsWith("//")) return false

          let altEnd = node.from + 2
          for (let child = node.node.firstChild; child; child = child.nextSibling) {
            if (child.name === "LinkMark"
                && state.doc.sliceString(child.from, child.to) === "]") {
              altEnd = child.from
              break
            }
          }
          const alt = state.doc.sliceString(node.from + 2, altEnd)
          if (!touches(node.from, node.to)) {
            const line = state.doc.lineAt(node.from)
            if (line.text.trim() === state.doc.sliceString(node.from, node.to)) {
              lineOnce(line.from, imageLine)
            }
            ranges.push(Decoration.replace({
              widget: new ImageWidget(
                source,
                alt,
                state.doc.sliceString(node.from, node.to),
                node.from,
                node.to,
              ),
            }).range(node.from, node.to))
          }
          return false
        }

        // --- Links ------------------------------------------------------
        // Only real links (with a URL part) get link treatment. Footnote
        // references like [^first] also parse as Link nodes; leave their
        // brackets alone so they read as what they are.
        if (name === "Link") {
          if (node.node.getChild("URL")) {
            ranges.push(linkMark.range(node.from, node.to))
          }
          return
        }
        if (name === "LinkMark") {
          const parent = node.node.parent
          if (parent && parent.name === "Link" && parent.getChild("URL")
              && !touches(parent.from, parent.to)) {
            ranges.push(hide.range(node.from, node.to))
          }
          return
        }
        if (name === "URL") {
          const parent = node.node.parent
          if (parent && parent.name === "Link") {
            if (!touches(parent.from, parent.to)) {
              ranges.push(hide.range(node.from, node.to))
            } else {
              ranges.push(urlMark.range(node.from, node.to))
            }
          }
          return
        }

        // --- Lists --------------------------------------------------------
        if (name === "BulletList" || name === "OrderedList") {
          listStack.push(node.from)
          return
        }
        if (name === "ListItem") {
          // The first item of a top-level list carries no gap (preview:
          // li:first-child { margin-top: 0 }); a nested list's first item
          // inherits the li > ul margin instead, so it keeps the gap. A
          // list starts at its first item, so "first" is a position check.
          const isFirstItem = node.from === listStack[listStack.length - 1]
          const isNested = listStack.length > 1
          // Keep the separator while editing any line of an item so moving
          // to a continuation cannot pull the caret upward. Inactive loose lists use
          // the same compact item spacing as Read Mode.
          const itemLine = state.doc.lineAt(node.from)
          const preserveBlankBefore = touches(itemLine.from, node.to) && itemLine.number > 1
            && state.doc.line(itemLine.number - 1).text.trim() === ""
          if (!isFirstItem && !preserveBlankBefore) {
            let number = itemLine.number - 1
            while (number > 0 && state.doc.line(number).text.trim() === "") {
              lineOnce(state.doc.line(number).from, blockSeparatorLine(0))
              number--
            }
          }
          if ((!isFirstItem || isNested) && !preserveBlankBefore) lineOnce(node.from, listItemGapLine)
          eachLine(node.from, node.to, listItemLine)
          if (/^[ \t]*[-+*][ \t]+\[[xX]\](?:[ \t]|$)/.test(state.doc.sliceString(node.from, itemLine.to))) {
            // Nested lists own their completion state. Keep the parent's
            // continuation paragraphs styled, including those after a sublist.
            let from = node.from
            for (let child = node.node.firstChild; child; child = child.nextSibling) {
              if (child.name !== "BulletList" && child.name !== "OrderedList") continue
              eachLine(from, state.doc.lineAt(child.from).from - 1, completedTaskLine)
              from = state.doc.lineAt(child.to).to + 1
            }
            eachLine(from, node.to, completedTaskLine)
          }
          lineOnce(node.from, listDepthLine(listStack.length))
          listDepthPositions.add(state.doc.lineAt(node.from).from)
          // Continuation lines of this item (not nested markers, not blank)
          // sit at the item's text column with their indentation hidden.
          {
            const firstLine = state.doc.lineAt(node.from)
            let pos = firstLine.to + 1
            while (pos <= node.to) {
              const line = state.doc.lineAt(pos)
              const text = line.text
              if (text.length > 0 && !markdownListMarker.test(text)) {
                lineOnce(line.from, listContinuationLine)
                lineOnce(line.from, listDepthLine(listStack.length))
                const lead = text.match(/^[ \t]+/)
                if (lead) ranges.push(hide.range(line.from, line.from + lead[0].length))
              }
              if (line.to >= node.to) break
              pos = line.to + 1
            }
          }
          // Source indentation uses proportional-font space glyphs, which
          // does not equal the rendered list's 2.1em nesting step. Hide that
          // source-only prefix and let the semantic depth line own geometry.
          const line = state.doc.lineAt(node.from)
          const rawIndentedList = line.text.match(markdownListMarker)
          const indentation = rawIndentedList?.[1] ?? ""
          if (indentation.length > 0) {
            ranges.push(hide.range(line.from, line.from + indentation.length))
          }
          return
        }
        if (name === "ListMark") {
          const mark = state.doc.sliceString(node.from, node.to)
          const line = state.doc.lineAt(node.from)
          const isTask = /^\s*\[[ xX]\](\s|$)/.test(line.text.slice(node.to - line.from))
          if (isTask && /^[-+*]$/.test(mark)) {
            const task = line.text.slice(node.to - line.from).match(/^[ \t]*\[([ xX])\][ \t]?/)
            const bracket = node.to + task[0].indexOf('[')
            if (editingTaskMarker(bracket)) return
            lineOnce(line.from, taskLine)
            ranges.push(Decoration.replace({ widget: new TaskCheckboxWidget(bracket + 1, task[1] !== ' ') })
              .range(node.from, node.to + task[0].length))
          } else if ((mark === "-" || mark === "*" || mark === "+") && !isTask) {
            // Both forms occupy the same fixed-width hanging box. Keep the
            // active dash editable, but hide its source separator so the dash
            // can sit at the rendered bullet position without moving text.
            const after = state.doc.sliceString(node.to, node.to + 1)
            if (touchesLineOf(node.from)) {
              ranges.push(activeBulletDeco.range(node.from, node.to))
              if (after === " ") ranges.push(hide.range(node.to, node.to + 1))
            } else {
              ranges.push(bulletDeco.range(node.from, node.to + (after === " " ? 1 : 0)))
            }
          } else if (/^\d+[.)]$/.test(mark) && !isTask) {
            const after = state.doc.sliceString(node.to, node.to + 1)
            if (touchesLineOf(node.from)) {
              ranges.push(activeOrderedDeco.range(node.from, node.to))
              if (after === " ") ranges.push(hide.range(node.to, node.to + 1))
            } else {
              ranges.push(orderedDeco(mark).range(node.from, node.to + (after === " " ? 1 : 0)))
            }
          }
          return
        }

        // --- Code blocks ------------------------------------------------
        if (name === "FencedCode" || name === "CodeBlock") {
          const first = state.doc.lineAt(node.from)
          const last = state.doc.lineAt(node.to)
          // A lone opening fence is still being typed: it becomes a block when
          // Enter adds the closing fence, so leave it as plain text until then.
          if (name === "FencedCode" && first.number === last.number
              && node.node.getChildren("CodeMark").length < 2) return false
          // A fence being typed can pair with one further down; until Enter
          // gives it its own partner, show the affected lines as plain text.
          if (name === "FencedCode" && pendingCoversFence(state, node)) return false
          const closed = name === "FencedCode"
            && node.node.lastChild?.name === "CodeMark"
          const hasInterior = last.number - first.number >= (closed ? 2 : 1)
          // Parsed fence lines stay out of the visual code card even while
          // its content is active. The opening source is revealed only when
          // the caret is actually on that line, so newly authored fences and
          // manual language edits remain possible without polluting the code.
          const hidesOpeningFence = name === "FencedCode"
            && !touchesLineOf(first.from)
          const hidesClosingFence = closed && !touchesLineOf(last.from)
          const codeFirst = hidesOpeningFence && hasInterior
            ? state.doc.line(first.number + 1) : first
          const widgetLine = hasInterior ? codeFirst : first
          const codeLast = !hasInterior && name === "FencedCode"
            ? first
            : hidesClosingFence
              ? state.doc.line(last.number - 1)
              : last
          if (name === "FencedCode") {
            const details = fencedCodeDetails(state, node)
            if (details.detectedLanguage) {
              for (const token of detectedCodeHighlights(details, detectedCodeCache)) {
                ranges.push(token.mark.range(
                  details.sourceFrom + token.from,
                  details.sourceFrom + token.to,
                ))
              }
            }
            ranges.push(Decoration.widget({
              widget: new CodeLanguageWidget({
                wrapped: state.field(wrappedCodeBlocks).has(first.from),
                fenceFrom: node.from,
                language: details.language,
                detectedLanguage: details.detectedLanguage,
                rawInfo: details.rawInfo,
                infoFrom: details.infoFrom,
                infoTo: details.infoTo,
              }),
              side: -1,
            }).range(widgetLine.from))
          } else {
            ranges.push(Decoration.widget({
              widget: new CodeLanguageWidget({ fenceFrom: first.from, language: 'text',
                rawInfo: '', plain: true, wrapped: state.field(wrappedCodeBlocks).has(first.from) }),
              side: -1,
            }).range(widgetLine.from))
          }
          // An indented block hides its four-space marker; reveal it on every
          // line at once, or the caret's line sticks out by four columns.
          const revealsIndent = name === "CodeBlock" && touches(node.from, node.to)
          let pos = node.from
          while (pos <= node.to) {
            const line = state.doc.lineAt(pos)
            const rawIndentedList = name === "CodeBlock"
              && decoratedLines.has(`${listItemLine.spec.class}@${line.from}`)
              ? line.text.match(markdownListMarker)
              : null
            if (rawIndentedList) {
              decorateRawIndentedListLine(line, rawIndentedList)
              if (line.to >= node.to) break
              pos = line.to + 1
              continue
            }
            const isWidgetLine = name === "FencedCode"
              && line.from === widgetLine.from
            if (((hidesOpeningFence && line.from === first.from)
                || (hidesClosingFence && line.from === last.from))
                && !isWidgetLine) {
              lineOnce(line.from, collapsedLine)
            } else if (name === "FencedCode" && !hasInterior
                && line.from !== first.from && !isWidgetLine) {
              lineOnce(line.from, collapsedLine)
            } else {
              const isFirst = line.from === codeFirst.from
              const isLast = line.from === codeLast.from
              if (isFirst) lineOnce(line.from, codeLineFirst)
              if (isLast) lineOnce(line.from, codeLineLast)
              if (!isFirst && !isLast) lineOnce(line.from, codeLine)
              ranges.push(Decoration.line({ attributes: {
                'data-code-scroll-group': String(first.from),
                class: state.field(wrappedCodeBlocks).has(first.from) ? 'cm-md-code-wrapped' : '',
              } }).range(line.from))
              if (line.length) ranges.push(codeScrollText.range(line.from, line.to))
            }
            if (name === "CodeBlock" && !revealsIndent) {
              const indent = line.text.match(/^(?: {4}|\t)/)?.[0]
              if (indent) ranges.push(hide.range(line.from, line.from + indent.length))
            }
            if (line.to >= node.to) break
            pos = line.to + 1
          }
          return
        }
        if (name === "CodeInfo") {
          const parent = node.node.parent
          if (!parent) return
          if (touchesLineOf(parent.from)) ranges.push(fenceMark.range(node.from, node.to))
          return
        }

        // --- Tables -------------------------------------------------------
        if (name === "Table") {
          eachLine(node.from, node.to, tableLine)
          return
        }

        // --- Horizontal rule ----------------------------------------------
        if (name === "HorizontalRule") {
          if (!touchesLineOf(node.from)) {
            lineOnce(node.from, ruleLine)
            ranges.push(hrDeco.range(node.from, node.to))
          }
          return
        }
      },
      leave: (node) => {
        depth--
        const name = node.name
        if (name === "BulletList" || name === "OrderedList") listStack.pop()
        if (name === "Blockquote") quoteStack.pop()
      },
    })
    for (const [lineFrom, edges] of quoteLines) {
      lineOnce(lineFrom, quoteLine(edges.depth, edges.starts, edges.ends, edges.gap))
    }
    quoteLines.clear()
    // A deeply indented marker may be parsed as continuation content inside
    // its ancestor ListItem rather than as a standalone CodeBlock. The parent
    // already gives that line list typography; fill in the missing depth,
    // marker, and gap decorations so the third and later Tabs do not jump.
    let rawPos = from
    while (rawPos <= to) {
      const line = state.doc.lineAt(rawPos)
      const hasListTypography = decoratedLines.has(
        `${listItemLine.spec.class}@${line.from}`
      )
      if (hasListTypography && !listDepthPositions.has(line.from)) {
        const rawIndentedList = line.text.match(markdownListMarker)
        if (rawIndentedList) {
          decorateRawIndentedListLine(line, rawIndentedList)
        }
      }
      if (line.to >= to) break
      rawPos = line.to + 1
    }
  }
  return Decoration.set(ranges, true)
}
