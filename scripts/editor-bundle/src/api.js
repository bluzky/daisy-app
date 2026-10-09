import { EditorView, keymap, dropCursor } from "@codemirror/view"
import { Compartment, EditorState, Prec, Transaction } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap, indentLess } from "@codemirror/commands"
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete"
import { markdown, markdownKeymap, markdownLanguage } from "@codemirror/lang-markdown"
import { yamlFrontmatter } from "@codemirror/lang-yaml"
import { syntaxTree, syntaxTreeAvailable, syntaxHighlighting, indentUnit, languageDataProp } from "@codemirror/language"
import { tags as t } from "@lezer/highlight"
import { html } from "@codemirror/lang-html"
import { convertClipboardToMarkdown } from "../clipboard-markdown.mjs"
import { codeHighlight } from "./code-highlight.js"
import { autoCloseFence } from "./commands/fence-autoclose.js"
import { applyBlockStyle, applyListStyle, editableListLines, enclosingNode, insertLink, listPrefix, orderedList, setHeading, stylingContext, toggleBlockPrefix, toggleInlineMark } from "./commands/format.js"
import { indentMarkdownListItems } from "./commands/list-indent.js"
import { METRICS, directionLines } from "./decoration-parts.js"
import { editorModuleEnabled, editorModuleExtensions, editorModules } from "./extensions.js"
import { documentFind, findTheme, setFind } from "./find.js"
import { formattingState } from "./formatting-state.js"
import { codeLanguages } from "./languages.js"
import { alignInactiveHeadings, livePreview } from "./live-preview/plugins.js"
import { obsidianHighlight } from "./obsidian-highlight.js"
import { activeCodeBlock, anchoredPointerSelection, pointerPreview, stablePointerPreview } from "./pointer.js"
import { slashTemplatesChanged } from "./slash.js"
import { tableEditors } from "./table/editors.js"
import { escapedTableCell } from "./table/model.js"
import { captureTableSelection, prepareTableFormatting, restoreTableFormatting, tableCellSourceRange, tableFormattingCallbacks, tableFormattingSelection, tableFormattingTargets, tableInlineCommands } from "./table/selection.js"
import { continueTaskList } from "./task-list.js"
import { codeCopyHandlers, wrappedCodeBlocks } from "./widgets/code.js"

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

window.MDEditor = {
  create(parent, doc, callbacks) {
    const onDirty = callbacks && callbacks.onDirty
    const onPasteImage = callbacks && callbacks.onPasteImage
    // Live preview spacing tokens from the host stylesheet (MarkdownHTML
    // constants) — see METRICS for the headless defaults.
    Object.assign(METRICS, (callbacks && callbacks.spacing) || {})
    const moduleCompartments = new Map()
    const moduleEnabled = new Map()
    // Handed to every module: the callbacks the page gave this editor.
    const moduleHost = { callbacks: callbacks || {}, slashTemplates: [] }
    const moduleOptions = (id) => (callbacks && callbacks.extensionOptions && callbacks.extensionOptions[id]) || {}
    for (const module of editorModules.values()) {
      const enabled = editorModuleEnabled(callbacks && callbacks.extensionState, module.id)
      moduleCompartments.set(module.id, new Compartment())
      moduleEnabled.set(module.id, enabled)
    }
    const moduleExtensions = [...editorModules.values()].map((module) =>
      moduleCompartments.get(module.id).of(moduleEnabled.get(module.id) ? editorModuleExtensions(module, moduleOptions(module.id), moduleHost) : []))
    const view = new EditorView({
      parent,
      state: EditorState.create({
        doc,
        extensions: [
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
          wrappedCodeBlocks,
          pointerPreview,
          stablePointerPreview,
          anchoredPointerSelection,
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
          autoCloseFence,
          closeBrackets(),
          // paragraphReflow deliberately omitted: the preview renders
          // single newlines as hard breaks, so the
          // editor keeps them visible instead of joining lines.
          Prec.highest(keymap.of([{ key: "Enter", run: continueTaskList }])),
          keymap.of([
            { key: "Mod-b", run: toggleInlineMark("**") },
            { key: "Mod-i", run: toggleInlineMark("*") },
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
              callbacks.onSearchChange({ index: search.index + 1, total: search.matches.length })
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
              if (items.some((item) => String(item.type || "").toLowerCase().startsWith("image/"))) {
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
    let preservedSourcePosition = null
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
      bulletList: toggleBlockPrefix("- ", /^\s*[-*+]\s/),
      orderedList,
      taskList: toggleBlockPrefix("- [ ] ", /^\s*[-*+]\s+\[[ xX]\]\s/),
      link: insertLink,
    }
    if (callbacks?.onCopyCode) codeCopyHandlers.set(view, callbacks.onCopyCode)
    if (callbacks?.onFormattingChange) tableFormattingCallbacks.set(view, callbacks.onFormattingChange)
    callbacks?.onFormattingChange?.(formattingState(view.state))
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
        const styles = editableListLines(view.state).map(line => listPrefix(line.text).style)
        if (!styles.length) return 'none'
        return styles.every(style => style === styles[0]) ? styles[0] : 'mixed'
      },
      setListStyle: style => !tableFormattingTargets.has(view) && applyListStyle(view, style),
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
      find: (query, backwards = false, beginsWith = false) => {
        const previous = view.state.field(documentFind)
        const same = previous.query === query && previous.beginsWith === beginsWith
        let index = 0
        if (same && previous.matches.length) {
          index = (previous.index + (backwards ? -1 : 1) + previous.matches.length) % previous.matches.length
        } else if (backwards) {
          index = Number.MAX_SAFE_INTEGER
        }
        view.dispatch({ effects: setFind.of({ query, beginsWith, index }) })
        const search = view.state.field(documentFind)
        const match = search.matches[search.index]
        if (match) {
          preservedSourcePosition = null
          didUserScroll = true
          view.dispatch({ effects: EditorView.scrollIntoView(match.from, { y: "center" }) })
        }
        return { index: search.index + 1, total: search.matches.length }
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
