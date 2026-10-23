import { EditorView, keymap, dropCursor } from "@codemirror/view"
import { Compartment, EditorState, Prec, Transaction } from "@codemirror/state"
import { cursorDocEnd, cursorDocStart, cursorLineBoundaryBackward, cursorLineBoundaryLeft, cursorLineStart, defaultKeymap, history, historyKeymap, indentLess, selectDocEnd, selectDocStart, selectLineBoundaryBackward, selectLineBoundaryLeft, selectLineStart } from "@codemirror/commands"
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete"
import { markdown, markdownKeymap, markdownLanguage } from "@codemirror/lang-markdown"
import { yamlFrontmatter } from "@codemirror/lang-yaml"
import { syntaxTree, syntaxTreeAvailable, syntaxHighlighting, indentUnit, languageDataProp } from "@codemirror/language"
import { tags as t } from "@lezer/highlight"
import { html } from "@codemirror/lang-html"
import { convertClipboardToMarkdown } from "../clipboard-markdown.mjs"
import { codeHighlight } from "./code-highlight.js"
import { codeModeExtensions } from "./code-mode.js"
import { codeBackspace, codeDelete, exitCodeBlock, keepCaretOffFences, openCodeFence, pendingFence, settleCodeCaretPlugin } from "./commands/code-fence.js"
import { applyBlockStyle, enclosingNode, insertLink, setHeading, stylingContext, toggleBlockPrefix, toggleInlineMark } from "./commands/format.js"
import { indentMarkdownListItems } from "./commands/list-indent.js"
import { continueList, deleteListMarker, indentListItems, insertListContinuation, outdentListItems, paragraphAfterList, selectedListStyle, setListStyle, toggleListStyle } from "./commands/lists.js"
import { deleteTableBackward, deleteTableForward, openLineBelowTable } from "./commands/table-edges.js"
import { METRICS, directionLines } from "./decoration-parts.js"
import { editorModuleEnabled, editorModuleExtensions, editorModules } from "./extensions.js"
import { collectMatches, documentFind, expandReplacement, findTheme, sameSearch, setFind } from "./find.js"
import { formattingState } from "./formatting-state.js"
import { codeLanguages } from "./languages.js"
import { alignInactiveHeadings, keepCaretAfterListMarker, leaveListMarkerBackward, livePreview, stopAfterListMarker } from "./live-preview/plugins.js"
import { obsidianHighlight } from "./obsidian-highlight.js"
import { codeCardWidth } from "./code-card-width.js"
import { activeCodeBlock, anchoredPointerSelection, pointerPreview, stablePointerPreview } from "./pointer.js"
import { readWorkspaceCandidates, workspaceCandidatesChanged } from "./metadata-completion.js"
import { metadataLinksChanged } from "./metadata-links.js"
import { linkOpening, openLinkAt } from "./link-open.js"
import { slashTemplatesChanged } from "./slash.js"
import { tableEditors } from "./table/editors.js"
import { escapedTableCell } from "./table/model.js"
import { captureTableSelection, prepareTableFormatting, restoreTableFormatting, tableCellSourceRange, tableFormattingCallbacks, tableFormattingSelection, tableFormattingTargets, tableInlineCommands } from "./table/selection.js"
import { cycleListItemState } from "./task-list.js"
import { extractMetadata } from "./workspace-metadata.js"
import { codeCopyHandlers, unwrappedCodeBlocks } from "./widgets/code.js"

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

window.MDEditor = {
  extractWorkspaceMetadata: extractMetadata,
  create(parent, doc, callbacks) {
    let jumpToDocEdge = () => false
    const onDirty = callbacks && callbacks.onDirty
    const onPasteImage = callbacks && callbacks.onPasteImage
    // Live preview spacing tokens from the host stylesheet (MarkdownHTML
    // constants) — see METRICS for the headless defaults.
    Object.assign(METRICS, (callbacks && callbacks.spacing) || {})
    const moduleCompartments = new Map()
    const moduleEnabled = new Map()
    // Handed to every module: the callbacks the page gave this editor.
    const moduleHost = { callbacks: callbacks || {}, slashTemplates: [], workspaceCandidates: null, metadataLinks: false }
    const moduleOptions = (id) => (callbacks && callbacks.extensionOptions && callbacks.extensionOptions[id]) || {}
    for (const module of editorModules.values()) {
      const enabled = editorModuleEnabled(callbacks && callbacks.extensionState, module.id)
      moduleCompartments.set(module.id, new Compartment())
      moduleEnabled.set(module.id, enabled)
    }
    const moduleExtensions = [...editorModules.values()].map((module) =>
      moduleCompartments.get(module.id).of(moduleEnabled.get(module.id) ? editorModuleExtensions(module, moduleOptions(module.id), moduleHost) : []))
    // A string selects code-only editing (see code-mode.js); "" is plain text.
    const codeLanguage = typeof (callbacks && callbacks.codeLanguage) === "string" ? callbacks.codeLanguage : null
    const view = new EditorView({
      parent,
      state: EditorState.create({
        doc,
        extensions: codeLanguage !== null ? [
          ...codeModeExtensions(codeLanguage),
          EditorView.updateListener.of((update) => {
            if (update.docChanged && callbacks?.onSearchChange) {
              callbacks.onSearchChange(searchResult(update.state.field(documentFind)))
            }
            if (update.docChanged && onDirty
                && !update.transactions.some((transaction) => transaction.isUserEvent("rename"))) {
              onDirty()
            }
          }),
        ] : [
          history(),
          documentFind,
          findTheme,
          // Native selection, not drawSelection(): the selection layer paints
          // every selected line edge to edge, while WebKit's own selection
          // follows the text once the host styles .cm-content as a flex
          // column (see EditorViewController). CodeMirror re-syncs the DOM
          // selection to the rendered viewport as the document virtualizes.
          dropCursor(),
          EditorView.lineWrapping,
          EditorView.perLineTextDirection.of(true),
          indentUnit.of("    "),
          directionLines,
          // Parse a leading `---` block as YAML frontmatter so its lines
          // never surface as a thematic break plus setext heading.
          yamlFrontmatter({
            content: markdown({
              base: markdownLanguage,
              codeLanguages,
              extensions: obsidianHighlight,
            }),
          }),
          activeCodeBlock,
          unwrappedCodeBlocks,
          pointerPreview,
          stablePointerPreview,
          codeCardWidth,
          anchoredPointerSelection,
          linkOpening(callbacks),
          ...moduleExtensions,
          tableEditors,
          tableFormattingSelection,
          // Markdown punctuation also carries processingInstruction tags.
          // Keep code colors inside embedded languages, not Markdown markers.
          syntaxHighlighting({
            style: codeHighlight.style,
            scope: (type) => type.prop(languageDataProp) !== markdownLanguage.data,
          }),
          Prec.lowest(livePreview),
          alignInactiveHeadings,
          pendingFence,
          keepCaretOffFences,
          keepCaretAfterListMarker,
          settleCodeCaretPlugin,
          paragraphAfterList,
          closeBrackets(),
          // paragraphReflow deliberately omitted: the preview renders
          // single newlines as hard breaks, so the
          // editor keeps them visible instead of joining lines.
          Prec.highest(keymap.of([
            { key: "Mod-Enter", run: cycleListItemState },
            { key: "Enter", run: exitCodeBlock },
            { key: "Enter", run: openCodeFence },
            { key: "Enter", run: openLineBelowTable },
            { key: "Enter", run: continueList, shift: insertListContinuation },
            { key: "ArrowDown", run: openLineBelowTable },
            { key: "ArrowRight", run: openLineBelowTable },
            { key: "Backspace", run: deleteTableBackward },
            { key: "Backspace", run: codeBackspace },
            { key: "Backspace", run: deleteListMarker },
            { key: "Mod-ArrowUp", run: (v) => jumpToDocEdge(v, cursorDocStart, false), shift: (v) => jumpToDocEdge(v, selectDocStart, false) },
            { key: "Mod-ArrowDown", run: (v) => jumpToDocEdge(v, cursorDocEnd, true), shift: (v) => jumpToDocEdge(v, selectDocEnd, true) },
            { key: "Delete", run: deleteTableForward },
            { key: "Delete", run: codeDelete },
            { key: "ArrowLeft", run: leaveListMarkerBackward(false), shift: leaveListMarkerBackward(true) },
            { mac: "Cmd-ArrowLeft", run: stopAfterListMarker(cursorLineBoundaryLeft), shift: stopAfterListMarker(selectLineBoundaryLeft), preventDefault: true },
            { key: "Home", run: stopAfterListMarker(cursorLineBoundaryBackward), shift: stopAfterListMarker(selectLineBoundaryBackward), preventDefault: true },
            { mac: "Ctrl-a", run: stopAfterListMarker(cursorLineStart), shift: stopAfterListMarker(selectLineStart) },
          ])),
          keymap.of([
            { key: "Mod-b", run: toggleInlineMark("**") },
            { key: "Mod-i", run: toggleInlineMark("*") },
            { key: "Tab", run: indentListItems, shift: outdentListItems },
            { key: "Tab", run: indentMarkdownListItems, shift: indentLess },
            ...closeBracketsKeymap,
            ...markdownKeymap,
            ...defaultKeymap,
            ...historyKeymap,
          ]),
          // Fires on every change; the host debounces for autosave.
          EditorView.updateListener.of((update) => {
            if (callbacks?.onFormattingChange && (update.selectionSet || update.docChanged
                || update.focusChanged || syntaxTree(update.startState) !== syntaxTree(update.state))) {
              if (tableFormattingTargets.has(view)) captureTableSelection(view)
              else callbacks.onFormattingChange(formattingState(update.state))
            }
            if (update.docChanged && callbacks?.onSearchChange) {
              const search = update.state.field(documentFind)
              callbacks.onSearchChange(searchResult(search))
            }
            if (update.docChanged && onDirty
                && !update.transactions.some((transaction) => transaction.isUserEvent("rename"))) {
              onDirty()
            }
          }),
          EditorView.domEventHandlers({
            paste(event, view) {
              if (event.target instanceof Element
                  && event.target.closest(".cm-md-table-cell")) return false
              // Code takes the clipboard verbatim: converting rich text would
              // wrap a <pre> in fences that close the block being pasted into.
              if (enclosingNode(view.state, view.state.selection.main.from, ["FencedCode", "CodeBlock"])) return false
              const clipboard = event.clipboardData
              const items = Array.from(clipboard?.items || [])
              const clipboardText = typeof clipboard?.getData === "function"
                ? (type) => clipboard.getData(type)
                : () => ""
              const html = clipboardText("text/html")
              const text = clipboardText("text/plain")
              const types = clipboard?.types
              const markdown = convertClipboardToMarkdown({ html, text, types })
              // Excel also puts a bitmap preview on the pasteboard. A table is
              // more useful than that preview, so let explicit tabular data
              // beat an image while ordinary image pastes stay native.
              const hasTabularData = /<table\b/i.test(html)
                || Array.from(types || []).some((type) =>
                  /^text\/tab-separated-values(?:;|$)/.test(String(type).toLowerCase()))
                || text.split(/\r?\n/).filter((row) => row.includes("\t")).length >= 2
              const insertMarkdown = () => {
                if (!markdown) return false
                event.preventDefault()
                const selection = view.state.selection.main
                view.dispatch({
                  changes: { from: selection.from, to: selection.to, insert: markdown },
                  selection: { anchor: selection.from + markdown.length },
                  userEvent: "input.paste",
                  scrollIntoView: true,
                })
                return true
              }
              if (hasTabularData && insertMarkdown()) return true
              // Images and files (Finder's Copy) go to the native asset flow,
              // which copies them beside the document and links them.
              const hasFiles = Array.from(types || []).includes("Files")
                || items.some((item) => item.kind === "file")
              if (hasFiles || items.some((item) => String(item.type || "").toLowerCase().startsWith("image/"))) {
                if (typeof onPasteImage !== "function") return false
                event.preventDefault()
                const selection = view.state.selection.main
                onPasteImage(selection.from, selection.to)
                return true
              }
              return insertMarkdown()
            },
          }),
        ],
      }),
    })
    // On macOS 26+ WebKit scrolls the page and owns the chrome backdrop.
    // Other hosts retain CodeMirror's internal scroll container.
    const pageScrolling = !!(callbacks && callbacks.pageScrolling)
    const scroller = pageScrolling ? document.scrollingElement : view.scrollDOM
    const scrollEvents = pageScrolling ? window : scroller
    // CodeMirror estimates the height of lines it has not drawn, so a single
    // scrollIntoView toward the document end stops short. After moving the
    // caret, keep scrolling to the real edge until the scroll height settles.
    jumpToDocEdge = (v, move, toEnd) => {
      move(v)
      let lastHeight = -1, stableFrames = 0, frames = 0
      const settle = () => {
        scroller.scrollTop = toEnd ? scroller.scrollHeight : 0
        stableFrames = scroller.scrollHeight === lastHeight ? stableFrames + 1 : 0
        lastHeight = scroller.scrollHeight
        if (stableFrames < 4 && ++frames < 60) requestAnimationFrame(settle)
      }
      requestAnimationFrame(settle)
      return true
    }
    let preservedSourcePosition = null
    const searchResult = (search) => ({
      index: search.index + 1,
      total: search.matches.length,
      capped: search.capped,
      error: search.error,
    })
    // Brings the highlighted search state in line with the bar's query and
    // options without moving the current match when nothing changed.
    const syncSearch = (query, options) => {
      if (!query) return false
      if (!sameSearch(view.state.field(documentFind), query, options)) {
        view.dispatch({ effects: setFind.of({ query, options, index: 0 }) })
      }
      return true
    }
    const revealCurrentMatch = (search) => {
      const match = search.matches[search.index]
      if (!match) return
      preservedSourcePosition = null
      didUserScroll = true
      view.dispatch({ effects: EditorView.scrollIntoView(match.from, { y: "center" }) })
      // A jump far from the mounted lines can leave the new viewport blank
      // until the next scroll event; setScrollPosition nudges it the same way.
      requestAnimationFrame(() => {
        scrollEvents.dispatchEvent(new Event("scroll"))
        view.requestMeasure()
      })
    }
    let preservedSourceGap = 0
    let preservedScrollTop = null
    // CodeMirror block heights start at the first line, after content padding.
    // Scroll offsets start at the scroll container's origin instead. Convert
    // both ways so page padding is preserved during read/edit hand-offs.
    const documentScrollOrigin = () => view.documentTop + scroller.scrollTop
      - (pageScrolling ? 0 : scroller.getBoundingClientRect().top)
    const lineContentBlock = (position) => {
      const block = view.lineBlockAt(position)
      let paddingTop = 0
      let paddingBottom = 0
      try {
        const dom = view.domAtPos(position).node
        const element = dom.nodeType === Node.ELEMENT_NODE ? dom : dom.parentElement
        const line = element && element.closest(".cm-line")
        if (line) {
          const style = getComputedStyle(line)
          paddingTop = parseFloat(style.paddingTop) || 0
          paddingBottom = parseFloat(style.paddingBottom) || 0
        }
      } catch (_) {
        // A distant virtualized line may not have DOM until scrollIntoView
        // runs. The second animation frame measures it precisely.
      }
      return {
        top: block.top + paddingTop,
        height: Math.max(block.height - paddingTop - paddingBottom, 1),
        sourceStart: view.state.doc.lineAt(block.from).number,
        sourceEnd: view.state.doc.lineAt(block.to).number + 1,
      }
    }
    const commands = {
      bold: toggleInlineMark("**"),
      italic: toggleInlineMark("*"),
      strikethrough: toggleInlineMark("~~"),
      highlight: toggleInlineMark("=="),
      code: toggleInlineMark("`"),
      h0: setHeading(0),
      h1: setHeading(1),
      h2: setHeading(2),
      h3: setHeading(3),
      h4: setHeading(4),
      h5: setHeading(5),
      h6: setHeading(6),
      quote: toggleBlockPrefix("> ", /^>\s?/),
      bulletList: toggleListStyle("bullet"),
      orderedList: toggleListStyle("ordered"),
      taskList: toggleListStyle("task"),
      link: insertLink,
    }
    if (callbacks?.onCopyCode) codeCopyHandlers.set(view, callbacks.onCopyCode)
    if (callbacks?.onFormattingChange) tableFormattingCallbacks.set(view, callbacks.onFormattingChange)
    if (codeLanguage === null) callbacks?.onFormattingChange?.(formattingState(view.state))
    return {
      getMarkdown: () => view.state.doc.toString(),
      getBlockStyle: () => tableFormattingTargets.has(view) ? 'table' : stylingContext(view.state).style,
      setBlockStyle: (style, language) => {
        if (tableFormattingTargets.has(view)) {
          if (style !== 'code') return false
          const target = prepareTableFormatting(view)
          if (!target) return false
          toggleInlineMark('`')(view)
          restoreTableFormatting(view, target)
          return true
        }
        return applyBlockStyle(view, style, language)
      },
      getListStyle: () => {
        if (tableFormattingTargets.has(view)) return 'none'
        return selectedListStyle(view.state)
      },
      setListStyle: (style) => {
        if (tableFormattingTargets.has(view)) return false
        const applied = setListStyle(view, style)
        view.focus()
        return applied
      },
      getLinkSelection: (expandLink = false) => {
        if (tableFormattingTargets.has(view) && !prepareTableFormatting(view)) {
          return null
        }
        const { from, to } = view.state.selection.main
        const link = enclosingNode(view.state, from, ['Link'])
        if (expandLink && link && to <= link.to) {
          const marks = link.getChildren('LinkMark')
          return { from: link.from, to: link.to,
            text: view.state.sliceDoc(marks[0].to, marks[1].from) }
        }
        return { from, to, text: view.state.sliceDoc(from, to) }
      },
      insertLinkFromPopover: (text, url, from, to) => {
        const destination = String(url).trim()
        if (!destination || /[\r\n]/.test(destination)
            || from < 0 || to < from || to > view.state.doc.length) return false
        const link = enclosingNode(view.state, from, ['Link'])
        if (link && (from > link.from || to < link.to)) return false
        const endLink = to > from ? enclosingNode(view.state, to - 1, ['Link']) : null
        if (endLink && (from > endLink.from || to < endLink.to)) return false
        const label = (String(text) || destination).replace(/\\/g, '\\\\').replace(/([\[\]])/g, '\\$1').replace(/[\r\n]+/g, ' ')
        const target = destination.replace(/[\s<>\\()]/g, character =>
          /[()]/.test(character) ? '%' + character.charCodeAt(0).toString(16).toUpperCase() : encodeURIComponent(character))
        const tableTarget = tableFormattingTargets.get(view)
        if (tableTarget) {
          const range = tableCellSourceRange(view, tableTarget)
          if (!range || from < range.from || to > range.to) return false
        }
        const linkMarkdown = `[${label}](${target})`
        const insert = tableTarget ? escapedTableCell(linkMarkdown) : linkMarkdown
        view.dispatch({ changes: { from, to, insert }, selection: { anchor: from + insert.length }, userEvent: 'input' })
        if (tableTarget) restoreTableFormatting(view, tableTarget)
        else view.focus()
        return true
      },
      getHeadingLevel: () => {
        if (tableFormattingTargets.has(view)) return 0
        for (let node = syntaxTree(view.state).resolveInner(view.state.selection.main.head, 1); node; node = node.parent) {
          const heading = /^(?:ATX|Setext)Heading([1-6])$/.exec(node.name)
          if (heading) return Number(heading[1])
        }
        return 0
      },
      find: (query, backwards = false, options = null) => {
        const previous = view.state.field(documentFind)
        const same = sameSearch(previous, query, options)
        let index = 0
        if (same && previous.matches.length) {
          index = (previous.index + (backwards ? -1 : 1) + previous.matches.length) % previous.matches.length
        } else if (backwards) {
          index = Number.MAX_SAFE_INTEGER
        }
        view.dispatch({ effects: setFind.of({ query, options, index }) })
        const search = view.state.field(documentFind)
        revealCurrentMatch(search)
        return searchResult(search)
      },
      replaceCurrent: (replacement, query, options = null) => {
        if (!syncSearch(query, options)) return searchResult(view.state.field(documentFind))
        const search = view.state.field(documentFind)
        const entry = search.matches[search.index]
        if (!entry) return searchResult(search)
        const insert = expandReplacement(String(replacement ?? ""), entry, options)
        view.dispatch({
          changes: { from: entry.from, to: entry.to, insert },
          selection: { anchor: entry.from + insert.length },
          userEvent: "input.replace",
        })
        // Advance by position, so a replacement that contains the query does
        // not land on its own output.
        const after = view.state.field(documentFind)
        const resume = entry.from + insert.length
        let next = after.matches.findIndex((match) => match.from >= resume)
        if (next < 0) next = 0
        view.dispatch({ effects: setFind.of({ query, options, index: next }) })
        const result = view.state.field(documentFind)
        revealCurrentMatch(result)
        return { ...searchResult(result), replaced: 1 }
      },
      replaceAll: (replacement, query, options = null) => {
        // Bring the highlights and the reported counts to this query first,
        // as replaceCurrent does, so they never describe a stale one.
        if (!syncSearch(query, options)) return { ...searchResult(view.state.field(documentFind)), replaced: 0 }
        // Not the capped list the highlights use: a limit must never leave
        // matches behind.
        const { matches, error } = collectMatches(view.state.doc, query, options)
        if (error || !matches.length) return { ...searchResult(view.state.field(documentFind)), replaced: 0 }
        const text = String(replacement ?? "")
        view.dispatch({
          changes: matches.map((entry) => ({
            from: entry.from,
            to: entry.to,
            insert: expandReplacement(text, entry, options),
          })),
          userEvent: "input.replace",
        })
        return { ...searchResult(view.state.field(documentFind)), replaced: matches.length }
      },
      isSyntaxReady: () => syntaxTreeAvailable(view.state, view.state.doc.length),
      replaceMarkdown: (markdown) => {
        const text = String(markdown || "")
        const length = text.length
        const selection = view.state.selection.main
        const anchor = Math.min(selection.anchor, length)
        const head = Math.min(selection.head, length)
        const scrollTop = scroller.scrollTop
        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: text },
          selection: { anchor, head },
          userEvent: "rename",
          annotations: Transaction.addToHistory.of(false),
        })
        requestAnimationFrame(() => {
          scroller.scrollTop = scrollTop
          view.requestMeasure()
        })
      },
      insertTextAt: (text, from, to) => {
        const length = view.state.doc.length
        const start = Math.max(0, Math.min(Number(from) || 0, length))
        const end = Math.max(start, Math.min(Number(to) || start, length))
        view.dispatch({
          changes: { from: start, to: end, insert: String(text || "") },
          selection: { anchor: start + String(text || "").length },
          userEvent: "input",
          scrollIntoView: true,
        })
        view.focus()
      },
      focus: () => view.focus(),
      getScrollAnchor: () => {
        // Native WebKit/scrollbar scrolling need not deliver a DOM wheel or
        // pointer event. Reuse the incoming anchor only at its actual offset.
        if (Number.isFinite(preservedSourcePosition)
            && Math.abs(scroller.scrollTop - preservedScrollTop) <= 0.5) {
          return { position: preservedSourcePosition, gap: preservedSourceGap || 0 }
        }
        const viewportY = scroller.scrollTop - documentScrollOrigin()
        const visibleLine = view.lineBlockAtHeight(viewportY)
        const line = view.state.doc.lineAt(visibleLine.from)
        const sourceLineBlock = lineContentBlock(line.from)
        const progress = sourceLineBlock.height > 0
          ? Math.min(Math.max((viewportY - sourceLineBlock.top) / sourceLineBlock.height, 0), 1)
          : 0
        // Near the document top the viewport can sit above the first line
        // (inside the page padding), which the fractional position cannot
        // express. Carry that remaining pixel gap so the other surface can
        // reproduce the exact viewport, not just the line.
        const gap = Math.max(sourceLineBlock.top - viewportY, 0)
        return {
          position: sourceLineBlock.sourceStart
            + progress * (sourceLineBlock.sourceEnd - sourceLineBlock.sourceStart),
          gap,
        }
      },
      setScrollPosition: (progress, sourcePosition, sourceGap) => new Promise((resolve) => {
        const maximum = Math.max(scroller.scrollHeight - scroller.clientHeight, 0)
        let target = maximum * Math.min(Math.max(Number(progress) || 0, 0), 1)
        let linePosition = null
        const gap = Number.isFinite(sourceGap) ? Math.max(sourceGap, 0) : 0

        if (Number.isFinite(sourcePosition) && sourcePosition >= 1) {
          const sourceLine = Math.min(Math.floor(sourcePosition), view.state.doc.lines)
          linePosition = view.state.doc.line(sourceLine).from
          if (linePosition != null) {
            const block = lineContentBlock(linePosition)
            const fraction = (sourcePosition - block.sourceStart) / (block.sourceEnd - block.sourceStart)
            target = documentScrollOrigin() + block.top + block.height * fraction - gap
            // Let CodeMirror create the viewport around the target before
            // applying the precise within-block offset. Directly assigning a
            // distant scrollTop can briefly leave its virtualized DOM empty.
            view.dispatch({
              effects: EditorView.scrollIntoView(linePosition, { y: "start" }),
            })
          }
        }

        requestAnimationFrame(() => {
          const measuredMaximum = Math.max(scroller.scrollHeight - scroller.clientHeight, 0)
          if (linePosition != null) {
            const block = lineContentBlock(linePosition)
            const fraction = (sourcePosition - block.sourceStart) / (block.sourceEnd - block.sourceStart)
            target = documentScrollOrigin() + block.top + block.height * fraction - gap
          } else {
            target = measuredMaximum * Math.min(Math.max(Number(progress) || 0, 0), 1)
          }
          scroller.scrollTop = Math.min(Math.max(target, 0), measuredMaximum)
          scrollEvents.dispatchEvent(new Event("scroll"))
          view.requestMeasure()
          requestAnimationFrame(() => {
            preservedSourcePosition = Number.isFinite(sourcePosition) ? sourcePosition : null
            preservedSourceGap = Number.isFinite(sourcePosition) ? gap : 0
            preservedScrollTop = scroller.scrollTop
            resolve(true)
          })
        })
      }),
      // Used by hosts that map an external pointer target into the source.
      // Mark it as a pointer selection so fenced blocks enter source mode.
      select: (anchor, head = anchor) => {
        tableFormattingTargets.delete(view)
        view.dispatch({ selection: { anchor, head }, userEvent: "select.pointer" })
      },
      insert: (text) => {
        const range = view.state.selection.main
        const handled = view.state.facet(EditorView.inputHandler)
          .some((handler) => handler(view, range.from, range.to, text))
        if (handled) return
        view.dispatch({
          changes: { from: range.from, to: range.to, insert: text },
          selection: { anchor: range.from + text.length },
          userEvent: "input",
        })
      },
      exec: (name) => {
        const command = commands[name]
        if (!command) return false
        if (tableFormattingTargets.has(view)) {
          if (!tableInlineCommands.has(name)) return false
          const target = prepareTableFormatting(view)
          if (!target) return false
          command(view)
          restoreTableFormatting(view, target)
          return true
        }
        command(view)
        view.focus()
        return true
      },
      // The host's template file as `[{ name, body }]`; the slash menu shows
      // them under Templates. Safe to call at any time, with the module off too.
      setSlashTemplates: (templates) => {
        moduleHost.slashTemplates = (Array.isArray(templates) ? templates : []).filter(
          (template) => template && typeof template.name === "string" && typeof template.body === "string")
        view.dispatch({ effects: slashTemplatesChanged.of(null) })
      },
      // Workspace names for `#`, `@` and `+` suggestions, as
      // `{ version, indexing, truncated, tags, contexts, projects }` with
      // `[{ name, count }]` per kind (names without their marker). `indexing`
      // and `truncated` add a note under the suggestions. A snapshot older
      // than the one held is ignored; returns whether this one was taken.
      setWorkspaceCandidates: (snapshot) => {
        const next = readWorkspaceCandidates(snapshot, moduleHost.workspaceCandidates)
        if (!next) return false
        moduleHost.workspaceCandidates = next
        view.dispatch({ effects: workspaceCandidatesChanged.of(null) })
        return true
      },
      // Checks or unchecks one task for the Tasks sidebar, as one undoable
      // edit of its marker. `line` is the indexed line; `text` the indexed
      // label. The line is used when it still holds that task, otherwise the
      // one task with that text. Returns `{ line, changed, markdown }`, or
      // null when the task cannot be found unambiguously.
      setTaskChecked: (line, checked, text) => {
        const source = view.state.doc.toString()
        const tasks = extractMetadata(source).tasks
        const matches = (task) => typeof text !== "string" || task.text === text
        let task = tasks.find((candidate) => candidate.line === line && matches(candidate))
        if (!task && typeof text === "string") {
          const same = tasks.filter((candidate) => candidate.text === text)
          if (same.length === 1) task = same[0]
        }
        if (!task || task.line > view.state.doc.lines) return null
        const docLine = view.state.doc.line(task.line)
        // Same pattern as Swift's `TaskCheckboxSource`, which flips the
        // marker for the Read Mode and on-disk paths: change both together.
        const marker = /^(\s*(?:>\s*)*(?:[-+*]|\d+[.)])\s+\[)([ xX])\]/u.exec(docLine.text)
        if (!marker) return null
        const changed = (marker[2] !== " ") !== (checked === true)
        if (changed) {
          const from = docLine.from + marker[1].length
          view.dispatch({ changes: { from, to: from + 1, insert: checked ? "x" : " " }, userEvent: "input.task" })
        }
        return { line: task.line, changed, markdown: view.state.doc.toString() }
      },
      // Whether `#tag`, `@context` and `+project` read as links and open
      // their page on Cmd+click: true in a workspace window.
      // What Cmd+click at `pos` does: sends the link there to `onOpenLink`
      // and returns it, or returns null.
      openLinkAt: (pos) => openLinkAt(view, pos, callbacks),
      setMetadataLinks: (enabled) => {
        moduleHost.metadataLinks = enabled === true
        view.dispatch({ effects: metadataLinksChanged.of(moduleHost.metadataLinks) })
      },
      setExtensionState: (state) => {
        const effects = []
        for (const module of editorModules.values()) {
          const enabled = editorModuleEnabled(state, module.id)
          if (enabled === moduleEnabled.get(module.id)) continue
          moduleEnabled.set(module.id, enabled)
          effects.push(moduleCompartments.get(module.id).reconfigure(
            enabled ? editorModuleExtensions(module, moduleOptions(module.id), moduleHost) : []))
        }
        if (effects.length) view.dispatch({ effects })
      },
      destroy: () => {
        view.destroy()
      },
    }
  },
}
