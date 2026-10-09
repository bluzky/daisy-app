import { WidgetType } from "@codemirror/view"
import { redo, undo } from "@codemirror/commands"
import { toggleInlineMark } from "../commands/format.js"
import { renderTableCell, tableRenderedTextOffsets } from "./cell-render.js"
import { parseClipboardGrid, parseTableSource, serializeTable } from "./model.js"
import { captureTableSelection, prepareTableFormatting, restoreTableFormatting, tableCellCommit, tableCellSourceRange, tableFormattingTargets } from "./selection.js"

// True when the caret is collapsed at the very start (or end) of the cell.
function caretAtCellEdge(editor, atStart) {
  const selection = window.getSelection()
  if (!selection || !selection.isCollapsed || !selection.anchorNode
      || !editor.contains(selection.anchorNode)) return false
  const range = document.createRange()
  range.selectNodeContents(editor)
  if (atStart) range.setEnd(selection.anchorNode, selection.anchorOffset)
  else range.setStart(selection.anchorNode, selection.anchorOffset)
  return range.toString().length === 0
}

// Character offset of the caret from the start of the cell's text.
function caretOffset(editor) {
  const selection = window.getSelection()
  if (!selection || !selection.anchorNode || !editor.contains(selection.anchorNode)) return 0
  const range = document.createRange()
  range.selectNodeContents(editor)
  range.setEnd(selection.anchorNode, selection.anchorOffset)
  return range.toString().length
}

// True when the collapsed caret sits on the cell's first (or last) visual
// line. Without layout (empty cell, no caret box) the cell counts as one line.
function caretOnEdgeLine(editor, atTop, extending = false) {
  const selection = window.getSelection()
  if (!selection || !selection.rangeCount || !selection.anchorNode
      || !editor.contains(selection.anchorNode)) return false
  if (!extending && !selection.isCollapsed) return false
  // While extending a selection the moving end is the focus, not the start.
  const range = document.createRange()
  if (extending) {
    if (!selection.focusNode || !editor.contains(selection.focusNode)) return false
    range.setStart(selection.focusNode, selection.focusOffset)
  } else {
    range.setStart(selection.anchorNode, selection.anchorOffset)
  }
  range.collapse(true)
  const caret = range.getClientRects()[0] ?? range.getBoundingClientRect?.()
  if (!caret || !caret.height) return true
  const box = editor.getBoundingClientRect()
  const style = window.getComputedStyle(editor)
  const half = caret.height / 2
  return atTop
    ? caret.top - (box.top + (parseFloat(style.paddingTop) || 0)) < half
    : (box.bottom - (parseFloat(style.paddingBottom) || 0)) - caret.bottom < half
}

// Shift+arrow must not carry the native selection past the cell's text:
// WebKit would highlight the empty space after it. Returns true when the key
// was handled here (the caller prevents the default).
function keepSelectionInCell(editor, key) {
  const selection = window.getSelection()
  const text = editor.firstChild
  if (!selection || !selection.anchorNode || !selection.focusNode
      || !editor.contains(selection.anchorNode) || !editor.contains(selection.focusNode)) {
    return false
  }
  if (!text) return true
  const offsetOf = (node, offset) => {
    const range = document.createRange()
    range.selectNodeContents(editor)
    range.setEnd(node, offset)
    return range.toString().length
  }
  const focus = offsetOf(selection.focusNode, selection.focusOffset)
  if (key === "ArrowLeft") return focus === 0
  if (key === "ArrowRight") return focus >= editor.textContent.length
  const up = key === "ArrowUp"
  if (!caretOnEdgeLine(editor, up, true)) return false
  selection.setBaseAndExtent(
    selection.anchorNode, selection.anchorOffset,
    text, up ? 0 : (text.length ?? editor.textContent.length))
  return true
}

export class TableEditorWidget extends WidgetType {
  constructor(source, from) {
    super()
    this.source = source
    this.from = from
  }

  eq(other) { return other.source === this.source && other.from === this.from }

  toDOM(view) {
    const model = parseTableSource(this.source)
    const root = document.createElement("div")
    root.className = "cm-md-table-widget"
    root.dataset.tableFrom = String(this.from)
    if (!model) {
      root.textContent = this.source
      return root
    }

    let active = null
    let selectedPart = null
    let cellDrag = null
    let suppressNextTableClick = false
    const scroll = document.createElement("div")
    scroll.className = "cm-md-table-scroll"
    root.appendChild(scroll)
    const table = document.createElement("table")
    table.className = "cm-md-table-grid"
    scroll.appendChild(table)

    // A cell's editable box is only as tall as its text, while its <td> grows
    // to the row height. Treat the <td>'s empty space as part of the cell.
    const cellFor = (target) => {
      const element = target?.closest?.(".cm-md-table-cell")
        ?? target?.closest?.("td, th")?.querySelector(":scope > .cm-md-table-cell")
      return element && root.contains(element) ? element : null
    }

    const focusCell = (cell, caret) => {
      cell?.focus()
      if (!cell || caret == null) return
      const selection = window.getSelection()
      if (typeof caret === "number") {
        // Keep the horizontal position when moving up or down a column.
        const text = cell.firstChild
        if (text) {
          const offset = Math.min(caret, text.length ?? 0)
          selection?.setBaseAndExtent(text, offset, text, offset)
          return
        }
      }
      selection?.selectAllChildren(cell)
      if (caret === "end") selection?.collapseToEnd()
      else selection?.collapseToStart()
    }

    const focusCellAfterUpdate = (row, column, caret) => {
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const replacement = view.dom.querySelector(
          `.cm-md-table-widget[data-table-from="${this.from}"]`
        )
        focusCell(replacement && replacement.querySelector(
          `[data-table-row="${row}"][data-table-column="${column}"]`
        ), caret)
      }))
    }

    const applyModel = (focusTarget = null, commitsCell = false) => {
      const source = serializeTable(model)
      if (source === this.source) {
        if (focusTarget) {
          focusCell(root.querySelector(
            `[data-table-row="${focusTarget.row}"][data-table-column="${focusTarget.column}"]`
          ), focusTarget.caret)
        }
        return
      }
      active = null
      // History restores the selection from before an edit. While focus was
      // in a cell the editor selection stayed wherever it was (often the top
      // of the document), so Undo would scroll there. Park it on the table.
      const head = view.state.selection.main.head
      if (head < this.from || head > this.from + this.source.length) {
        view.dispatch({ selection: { anchor: this.from } })
      }
      view.dispatch({
        changes: { from: this.from, to: this.from + this.source.length, insert: source },
        annotations: commitsCell ? tableCellCommit.of(true) : [],
        userEvent: "input",
      })
      if (focusTarget) focusCellAfterUpdate(focusTarget.row, focusTarget.column, focusTarget.caret)
    }

    const captureActiveValue = () => {
      if (!active || active.element.dataset.tableEditing !== 'true') return
      model.rows[active.row][active.column] = active.element.innerText || ""
    }

    const clearPartSelection = () => {
      root.querySelectorAll(".is-table-part-selected").forEach((cell) => {
        cell.classList.remove("is-table-part-selected")
      })
      root.classList.remove(
        "is-table-row-selected",
        "is-table-column-selected",
        "is-table-range-selected",
      )
      root.removeAttribute("aria-label")
      selectedPart = null
    }

    const applyTableSelection = (kind, bounds, anchor) => {
      captureActiveValue()
      clearPartSelection()
      const cells = Array.from(root.querySelectorAll(".cm-md-table-cell")).filter((cell) => {
        const row = Number(cell.dataset.tableRow)
        const column = Number(cell.dataset.tableColumn)
        return row >= bounds.top && row <= bounds.bottom
          && column >= bounds.left && column <= bounds.right
      })
      cells.forEach((cell) => {
        cell.classList.add("is-table-part-selected")
      })
      root.classList.add(
        kind === "row"
          ? "is-table-row-selected"
          : kind === "column"
            ? "is-table-column-selected"
            : "is-table-range-selected",
      )
      window.getSelection()?.removeAllRanges()
      selectedPart = { kind, row: anchor.row, column: anchor.column, bounds }
      tableFormattingTargets.delete(view)
      root.tabIndex = 0
      if (kind === "range") {
        const rowCount = bounds.bottom - bounds.top + 1
        const columnCount = bounds.right - bounds.left + 1
        root.setAttribute("aria-label", `Selected ${rowCount} rows by ${columnCount} columns.`)
      } else {
        const first = kind === "row" ? bounds.top : bounds.left + 1
        const last = kind === "row" ? bounds.bottom : bounds.right + 1
        root.setAttribute(
          "aria-label",
          first === last
            ? `Selected ${kind} ${first}. Press Delete to remove it.`
            : `Selected ${kind}s ${first} to ${last}. Press Delete to remove them.`
        )
      }
      // Focusing the root must not scroll the (possibly tall) table into view.
      root.focus({ preventScroll: true })
    }

    const selectTablePart = (kind, row, column, extend = false) => {
      // Shift-click grows from the anchor of the current selection of this
      // kind (or the focused cell), keeping the anchor fixed.
      const from = selectedPart?.kind === kind ? selectedPart : active
      const anchor = extend && from ? { row: from.row, column: from.column } : { row, column }
      const bounds = kind === "row"
        ? {
            top: Math.max(1, Math.min(anchor.row, row)),
            right: model.alignments.length - 1,
            bottom: Math.max(anchor.row, row),
            left: 0,
          }
        : {
            top: 0,
            right: Math.max(anchor.column, column),
            bottom: model.rows.length - 1,
            left: Math.min(anchor.column, column),
          }
      applyTableSelection(kind, bounds, anchor)
    }

    const selectTableRange = (anchorRow, anchorColumn, headRow, headColumn) => {
      applyTableSelection("range", {
        top: Math.min(anchorRow, headRow),
        right: Math.max(anchorColumn, headColumn),
        bottom: Math.max(anchorRow, headRow),
        left: Math.min(anchorColumn, headColumn),
      }, { row: anchorRow, column: anchorColumn })
    }

    const performAction = (action, row, column) => {
      captureActiveValue()
      if (action === "insertRowAfter") {
        model.rows.splice(row + 1, 0, Array(model.alignments.length).fill(""))
        applyModel({ row: row + 1, column })
      } else if (action === "deleteRow" && row > 0) {
        model.rows.splice(row, 1)
        applyModel({ row: Math.min(row, model.rows.length - 1), column })
      } else if (action === "insertColumnBefore") {
        for (const cells of model.rows) cells.splice(column, 0, "")
        model.alignments.splice(column, 0, "none")
        applyModel({ row, column })
      } else if (action === "insertColumnAfter") {
        for (const cells of model.rows) cells.splice(column + 1, 0, "")
        model.alignments.splice(column + 1, 0, "none")
        applyModel({ row, column: column + 1 })
      } else if (action === "deleteColumn" && model.alignments.length > 1) {
        for (const cells of model.rows) cells.splice(column, 1)
        model.alignments.splice(column, 1)
        applyModel({ row, column: Math.min(column, model.alignments.length - 1) })
      }
    }

    model.rows.forEach((cells, row) => {
      const tr = document.createElement("tr")
      table.appendChild(tr)
      cells.forEach((value, column) => {
        const container = document.createElement(row === 0 ? "th" : "td")
        const editor = document.createElement("div")
        editor.className = "cm-md-table-cell"
        editor.contentEditable = "plaintext-only"
        editor.spellcheck = true
        renderTableCell(editor, value)
        editor.dataset.tableRow = String(row)
        editor.dataset.tableColumn = String(column)
        if (row === 0) {
          const placeholder = `Column ${column + 1}`
          editor.dataset.placeholder = placeholder
          const updateAccessibilityLabel = () => {
            if ((editor.innerText || "").trim()) editor.removeAttribute("aria-label")
            else editor.setAttribute("aria-label", placeholder)
          }
          updateAccessibilityLabel()
          editor.addEventListener("input", updateAccessibilityLabel)
        }
        if (model.alignments[column] !== "none") editor.style.textAlign = model.alignments[column]
        editor.addEventListener("focus", () => {
          // Native selection can hop into a neighbouring cell mid-drag; that
          // must not drop the range being dragged out.
          if (cellDrag?.active) return
          clearPartSelection()
          if (editor.textContent !== model.rows[row][column] || editor.childElementCount) {
            editor.textContent = model.rows[row][column]
          }
          editor.dataset.tableEditing = 'true'
          tableFormattingTargets.set(view, { tableFrom: this.from, row, column, element: editor, anchor: 0, head: 0 })
          active = { row, column, element: editor }
        })
        // Pasted tabular text (Excel, Sheets, several lines) fills cells from
        // this one, adding rows and columns as needed.
        editor.addEventListener("paste", (event) => {
          const grid = parseClipboardGrid(event.clipboardData?.getData("text/plain") ?? "")
          if (!grid) return
          event.preventDefault()
          event.stopPropagation()
          if (grid.length === 1 && grid[0].length === 1) {
            document.execCommand?.("insertText", false, grid[0][0])
            return
          }
          captureActiveValue()
          const width = Math.max(...grid.map((cells) => cells.length))
          while (model.alignments.length < column + width) {
            model.alignments.push("none")
            for (const cells of model.rows) cells.push("")
          }
          while (model.rows.length < row + grid.length) {
            model.rows.push(Array(model.alignments.length).fill(""))
          }
          grid.forEach((cells, i) => cells.forEach((value, j) => {
            model.rows[row + i][column + j] = value
          }))
          applyModel({
            row: row + grid.length - 1,
            column: column + grid[grid.length - 1].length - 1,
            caret: "end",
          })
        })
        editor.addEventListener("blur", () => {
          captureTableSelection(view)
          if (!active || active.element !== editor) return
          const value = editor.innerText || ""
          const changed = value !== model.rows[row][column]
            || !tableCellSourceRange(view, { tableFrom: this.from, row, column })
          model.rows[row][column] = value
          active = null
          delete editor.dataset.tableEditing
          renderTableCell(editor, model.rows[row][column])
          if (changed) applyModel(null, true)
        })
        editor.addEventListener("keydown", (event) => {
          // With nothing typed in this cell, Undo/Redo belong to the document
          // history, not the cell's own (empty) native undo stack.
          if ((event.metaKey || event.ctrlKey) && !event.altKey && !event.isComposing
              && event.key.toLowerCase() === "z"
              && (editor.innerText || "") === model.rows[row][column]) {
            event.preventDefault()
            ;(event.shiftKey ? redo : undo)(view)
            return
          }
          if ((event.metaKey || event.ctrlKey) && ['b', 'i'].includes(event.key.toLowerCase())) {
            event.preventDefault()
            const target = prepareTableFormatting(view)
            if (!target) return
            toggleInlineMark(event.key.toLowerCase() === 'b' ? '**' : '*')(view)
            if (target) restoreTableFormatting(view, target)
            return
          }
          if (event.key === "Escape") {
            event.preventDefault()
            active = null
            editor.blur()
            delete editor.dataset.tableEditing
            renderTableCell(editor, model.rows[row][column])
            tableFormattingTargets.delete(view)
            view.focus()
            return
          }
          if (event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey
              && !event.isComposing
              && ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) {
            if (keepSelectionInCell(editor, event.key)) event.preventDefault()
            return
          }
          if ((event.key === "ArrowLeft" || event.key === "ArrowRight")
              && !event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey
              && !event.isComposing) {
            // Only at the cell's edge; elsewhere the arrow moves the caret.
            const backwards = event.key === "ArrowLeft"
            if (!caretAtCellEdge(editor, backwards)) return
            let nextRow = row
            let nextColumn = column + (backwards ? -1 : 1)
            if (nextColumn < 0) {
              nextRow--
              nextColumn = model.alignments.length - 1
            } else if (nextColumn >= model.alignments.length) {
              nextRow++
              nextColumn = 0
            }
            if (nextRow < 0 || nextRow >= model.rows.length) return
            event.preventDefault()
            model.rows[row][column] = editor.innerText || ""
            applyModel({ row: nextRow, column: nextColumn, caret: backwards ? "end" : "start" })
            return
          }
          if ((event.key === "ArrowUp" || event.key === "ArrowDown")
              && !event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey
              && !event.isComposing) {
            // Inside a wrapped cell the arrow moves between its lines; only
            // from the topmost (bottommost) line does it change cell.
            const up = event.key === "ArrowUp"
            if (!caretOnEdgeLine(editor, up)) return
            const nextRow = row + (up ? -1 : 1)
            if (nextRow < 0 || nextRow >= model.rows.length) return
            event.preventDefault()
            model.rows[row][column] = editor.innerText || ""
            applyModel({ row: nextRow, column, caret: caretOffset(editor) })
            return
          }
          if (event.key !== "Tab" && event.key !== "Enter") return
          event.preventDefault()
          model.rows[row][column] = editor.innerText || ""
          const backwards = event.key === "Tab" && event.shiftKey
          let nextRow = row
          let nextColumn = column + (backwards ? -1 : 1)
          if (nextColumn < 0) {
            nextRow--
            nextColumn = model.alignments.length - 1
          } else if (nextColumn >= model.alignments.length) {
            nextRow++
            nextColumn = 0
          }
          if (nextRow < 0) {
            nextRow = 0
            nextColumn = 0
          } else if (nextRow >= model.rows.length) {
            model.rows.push(Array(model.alignments.length).fill(""))
          }
          applyModel({ row: nextRow, column: nextColumn })
        })
        container.appendChild(editor)
        tr.appendChild(container)
      })
    })
    root.addEventListener("mousedown", (event) => {
      if (event.button !== 0) return
      const cell = cellFor(event.target)
      if (!cell) return
      const fromEmptySpace = !event.target.closest?.(".cm-md-table-cell")
      const row = Number(cell.dataset.tableRow)
      const column = Number(cell.dataset.tableColumn)
      if (!Number.isInteger(row) || row < 0 || !Number.isInteger(column)) return
      // Anchor a plain click in rendered text before revealing its Markdown,
      // just like anchoredPointerSelection does for ordinary editor text.
      event.stopPropagation()
      let sourceAnchor = null
      if (cell.dataset.tableEditing !== 'true' && event.detail === 1
          && !event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey
          && cell.textContent !== model.rows[row][column]) {
        const hit = document.caretRangeFromPoint?.(event.clientX, event.clientY)
        const from = hit && tableRenderedTextOffsets.get(hit.startContainer)
        if (from != null && cell.contains(hit.startContainer)) {
          sourceAnchor = from + hit.startOffset
          event.preventDefault()
        }
      }
      if (fromEmptySpace) event.preventDefault()
      cell.focus({ preventScroll: true })
      if (fromEmptySpace) {
        // Below the text: put the caret at the end of the cell's source.
        const selection = window.getSelection()
        selection?.selectAllChildren(cell)
        selection?.collapseToEnd()
      }
      const selectSource = (head) => {
        const text = cell.firstChild
        if (!text) return
        window.getSelection()?.setBaseAndExtent(text, sourceAnchor, text, head)
      }
      if (sourceAnchor != null) selectSource(sourceAnchor)
      cellDrag = { cell, row, column, head: cell, active: false, dragged: false }

      const finishCellDrag = (finishEvent) => {
        document.removeEventListener("mousemove", moveCellDrag, true)
        document.removeEventListener("mouseup", finishCellDrag, true)
        const finishedDrag = cellDrag
        if (finishedDrag?.active) {
          finishEvent.preventDefault()
          window.getSelection()?.removeAllRanges()
          suppressNextTableClick = true
        } else {
          captureTableSelection(view)
        }
        cellDrag = null
      }
      const moveCellDrag = (moveEvent) => {
        if (!cellDrag) return
        const hitTarget = document.elementFromPoint?.(
          moveEvent.clientX,
          moveEvent.clientY,
        )
        const head = cellFor(hitTarget) || cellFor(moveEvent.target)
        if (!head) return
        if (head === cellDrag.cell && !cellDrag.active) {
          if (sourceAnchor != null) {
            moveEvent.preventDefault()
            cellDrag.dragged ||= Math.hypot(moveEvent.clientX - event.clientX,
              moveEvent.clientY - event.clientY) > 3
            if (cellDrag.dragged) {
              const hit = document.caretRangeFromPoint?.(moveEvent.clientX, moveEvent.clientY)
              if (hit?.startContainer === cell.firstChild) selectSource(hit.startOffset)
            }
          }
          return
        }
        if (head === cellDrag.head) return
        moveEvent.preventDefault()
        cellDrag.active = true
        cellDrag.head = head
        selectTableRange(
          cellDrag.row,
          cellDrag.column,
          Number(head.dataset.tableRow),
          Number(head.dataset.tableColumn),
        )
      }
      document.addEventListener("mousemove", moveCellDrag, true)
      document.addEventListener("mouseup", finishCellDrag, true)
    }, true)
    // Once a drag spans cells the range is ours; stop the browser from
    // extending (and re-focusing) a native selection underneath it.
    const blockNativeSelectionDuringDrag = (event) => {
      if (!root.isConnected) {
        document.removeEventListener("selectstart", blockNativeSelectionDuringDrag, true)
      } else if (cellDrag?.active && root.contains(event.target)) {
        event.preventDefault()
      }
    }
    document.addEventListener("selectstart", blockNativeSelectionDuringDrag, true)
    root.addEventListener("click", (event) => {
      if (!suppressNextTableClick) return
      suppressNextTableClick = false
      event.preventDefault()
      event.stopPropagation()
    }, true)
    // A click anywhere but a grip drops a row/column/range selection.
    const clearOnOutsideMouseDown = (event) => {
      if (!root.isConnected) {
        document.removeEventListener("mousedown", clearOnOutsideMouseDown, true)
        return
      }
      if (!selectedPart || event.target.closest?.(".cm-md-table-grip")) return
      clearPartSelection()
    }
    document.addEventListener("mousedown", clearOnOutsideMouseDown, true)
    // Cmd-C on a selected row, column or cell range copies it as a Markdown
    // table. A selection that skips the header row keeps the header of the
    // selected columns so the result is still a valid table.
    root.addEventListener("copy", (event) => {
      if (!selectedPart || !event.clipboardData) return
      const { top, bottom, left, right } = selectedPart.bounds
      const pick = (cells) => cells.slice(left, right + 1)
      const copied = {
        alignments: pick(model.alignments),
        rows: [model.rows[0], ...model.rows.slice(Math.max(top, 1), bottom + 1)].map(pick),
        trailingNewline: false,
      }
      event.clipboardData.setData("text/plain", serializeTable(copied))
      event.preventDefault()
    })
    root.addEventListener("keydown", (event) => {
      if (!selectedPart) return
      if (event.key === "Escape") {
        event.preventDefault()
        clearPartSelection()
        view.focus()
        return
      }
      if (event.key !== "Backspace" && event.key !== "Delete") return
      if (selectedPart.kind === "range") {
        event.preventDefault()
        return
      }
      event.preventDefault()
      const { kind, row, column, bounds } = selectedPart
      clearPartSelection()
      if (kind === "row" && bounds.bottom > bounds.top) {
        captureActiveValue()
        model.rows.splice(bounds.top, bounds.bottom - bounds.top + 1)
        applyModel({ row: Math.min(bounds.top, model.rows.length - 1), column })
      } else if (kind === "column" && bounds.right > bounds.left) {
        // A table keeps at least one column.
        if (bounds.right - bounds.left + 1 >= model.alignments.length) return
        captureActiveValue()
        const count = bounds.right - bounds.left + 1
        for (const cells of model.rows) cells.splice(bounds.left, count)
        model.alignments.splice(bounds.left, count)
        applyModel({ row, column: Math.min(bounds.left, model.alignments.length - 1) })
      } else {
        performAction(kind === "row" ? "deleteRow" : "deleteColumn", row, column)
      }
    })
    // Icons are inline SVG so strokes stay crisp at any zoom level.
    const controlIcon = (viewBox, path) => {
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
      svg.setAttribute("viewBox", viewBox)
      svg.setAttribute("aria-hidden", "true")
      const shape = document.createElementNS("http://www.w3.org/2000/svg", "path")
      shape.setAttribute("d", path)
      shape.setAttribute("fill", "none")
      shape.setAttribute("stroke", "currentColor")
      shape.setAttribute("stroke-width", "1.5")
      shape.setAttribute("stroke-linecap", "round")
      svg.append(shape)
      return svg
    }
    // Hover "+" controls: the left edge offers the nearest row boundary, the
    // top edge the nearest column boundary, each with a guide line across
    // the table. Clicking inserts there.
    const addControl = (kind, label) => {
      const line = document.createElement("div")
      line.className = `cm-md-table-add-line cm-md-table-add-line-${kind}`
      const button = document.createElement("button")
      button.type = "button"
      button.className = `cm-md-table-add cm-md-table-add-${kind}`
      button.tabIndex = -1
      button.setAttribute("aria-label", label)
      button.append(controlIcon("0 0 16 16", "M4 8H12M8 4V12"))
      line.hidden = true
      button.hidden = true
      // Keep focus (and the active cell's caret) where it is.
      button.addEventListener("mousedown", (event) => {
        event.preventDefault()
        event.stopPropagation()
      })
      root.append(line, button)
      return { line, button, boundary: null }
    }
    const addRow = addControl("row", "Add row")
    const addColumn = addControl("column", "Add column")
    // Grips select the hovered cell's row or column. They straddle the
    // table's left and top edges, centered on that row/column.
    const addGrip = (kind, label) => {
      const grip = document.createElement("button")
      grip.type = "button"
      grip.className = `cm-md-table-grip cm-md-table-grip-${kind}`
      grip.tabIndex = -1
      grip.hidden = true
      grip.setAttribute("aria-label", label)
      grip.append(kind === "row"
        ? controlIcon("0 0 12 22", "M4 7V15M8 7V15")
        : controlIcon("0 0 22 12", "M7 4H15M7 8H15"))
      grip.addEventListener("mousedown", (event) => {
        event.preventDefault()
        event.stopPropagation()
      })
      root.append(grip)
      return { grip, index: null }
    }
    const rowGrip = addGrip("row", "Select row")
    const columnGrip = addGrip("column", "Select column")
    let gripDrag = null
    let suppressGripClick = false
    rowGrip.grip.addEventListener("click", (event) => {
      if (suppressGripClick) return
      if (rowGrip.index == null) return
      captureActiveValue()
      selectTablePart("row", rowGrip.index, 0, event.shiftKey)
    })
    columnGrip.grip.addEventListener("click", (event) => {
      if (suppressGripClick) return
      if (columnGrip.index == null) return
      captureActiveValue()
      selectTablePart("column", 0, columnGrip.index, event.shiftKey)
    })
    const hideGrips = () => {
      if (gripDrag) return
      for (const control of [rowGrip, columnGrip]) {
        control.grip.hidden = true
        control.index = null
      }
    }
    const hideAddControls = () => {
      for (const control of [addRow, addColumn]) {
        control.line.hidden = true
        control.button.hidden = true
        control.boundary = null
      }
      hideGrips()
    }
    // Dragging a grip moves its row/column (or the whole selected range) to
    // the boundary under the pointer, shown as a drop line.
    const dropLines = {}
    for (const kind of ["row", "column"]) {
      const line = document.createElement("div")
      line.className = `cm-md-table-add-line cm-md-table-add-line-${kind}`
      line.hidden = true
      root.append(line)
      dropLines[kind] = line
    }
    const dragBoundary = (kind, event) => {
      if (kind === "row") {
        const rows = Array.from(table.rows)
        let boundary = rows.length
        for (let index = 1; index < rows.length; index++) {
          const box = rows[index].getBoundingClientRect()
          if (event.clientY < (box.top + box.bottom) / 2) {
            boundary = index
            break
          }
        }
        return boundary
      }
      const cells = Array.from(table.rows[0]?.cells || [])
      let boundary = cells.length
      for (let index = 0; index < cells.length; index++) {
        const box = cells[index].getBoundingClientRect()
        if (event.clientX < (box.left + box.right) / 2) {
          boundary = index
          break
        }
      }
      return boundary
    }
    const showDropLine = (kind, boundary) => {
      const rootRect = root.getBoundingClientRect()
      const scrollRect = scroll.getBoundingClientRect()
      const line = dropLines[kind]
      line.hidden = false
      if (kind === "row") {
        const rows = Array.from(table.rows)
        const y = boundary < rows.length
          ? rows[boundary].getBoundingClientRect().top
          : rows[rows.length - 1].getBoundingClientRect().bottom
        line.style.left = `${scrollRect.left - rootRect.left}px`
        line.style.top = `${y - rootRect.top}px`
        line.style.width = `${scrollRect.width}px`
      } else {
        const cells = Array.from(table.rows[0].cells)
        const x = boundary < cells.length
          ? cells[boundary].getBoundingClientRect().left
          : cells[cells.length - 1].getBoundingClientRect().right
        line.style.left = `${x - rootRect.left}px`
        line.style.top = `${scrollRect.top - rootRect.top}px`
        line.style.height = `${table.getBoundingClientRect().height}px`
      }
    }
    const moveTablePart = (kind, bounds, boundary) => {
      captureActiveValue()
      const first = kind === "row" ? bounds.top : bounds.left
      const last = kind === "row" ? bounds.bottom : bounds.right
      if (boundary >= first && boundary <= last + 1) return
      const count = last - first + 1
      const to = boundary > last ? boundary - count : boundary
      const reorder = (list) => list.splice(to, 0, ...list.splice(first, count))
      if (kind === "row") reorder(model.rows)
      else {
        for (const cells of model.rows) reorder(cells)
        reorder(model.alignments)
      }
      clearPartSelection()
      applyModel()
      // Keep keyboard focus with the document so Cmd-Z undoes the move,
      // without opening a cell for editing.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        view.contentDOM.focus({ preventScroll: true })
      }))
    }
    const startGripDrag = (control, kind, mouseDown) => {
      if (mouseDown.button !== 0 || control.index == null) return
      suppressGripClick = false
      const index = control.index
      gripDrag = { active: false, boundary: null }
      const move = (event) => {
        if (!gripDrag.active) {
          if (Math.hypot(event.clientX - mouseDown.clientX,
            event.clientY - mouseDown.clientY) < 4) return
          gripDrag.active = true
          // Drag the selected range when grabbing inside it, else just this one.
          const inside = selectedPart?.kind === kind
            && (kind === "row" ? index >= selectedPart.bounds.top && index <= selectedPart.bounds.bottom
              : index >= selectedPart.bounds.left && index <= selectedPart.bounds.right)
          if (!inside) selectTablePart(kind, kind === "row" ? index : 0, kind === "row" ? 0 : index)
          gripDrag.bounds = { ...selectedPart.bounds }
          root.classList.add("is-table-dragging")
        }
        event.preventDefault()
        gripDrag.boundary = dragBoundary(kind, event)
        showDropLine(kind, gripDrag.boundary)
      }
      const finish = () => {
        document.removeEventListener("mousemove", move, true)
        document.removeEventListener("mouseup", finish, true)
        const drag = gripDrag
        gripDrag = null
        dropLines.row.hidden = true
        dropLines.column.hidden = true
        root.classList.remove("is-table-dragging")
        if (!drag.active) return
        suppressGripClick = true
        if (drag.boundary != null) moveTablePart(kind, drag.bounds, drag.boundary)
      }
      document.addEventListener("mousemove", move, true)
      document.addEventListener("mouseup", finish, true)
    }
    rowGrip.grip.addEventListener("mousedown", (event) => startGripDrag(rowGrip, "row", event))
    columnGrip.grip.addEventListener("mousedown", (event) => startGripDrag(columnGrip, "column", event))
    const GRIP_CLEARANCE = 20
    const updateGrips = (event) => {
      if (gripDrag) return
      if (event.buttons !== 0 || cellDrag) return hideGrips()
      // Moving onto a grip keeps it (and its row/column) as is.
      if (event.target.closest?.(".cm-md-table-grip")) return
      const cell = cellFor(event.target)
      if (!cell) return hideGrips()
      const row = Number(cell.dataset.tableRow)
      const column = Number(cell.dataset.tableColumn)
      const rootRect = root.getBoundingClientRect()
      const scrollRect = scroll.getBoundingClientRect()
      const box = cell.closest("td, th").getBoundingClientRect()
      // Header rows can't be selected as a row; a "+" nearby takes the spot.
      // The grip yields only when a "+" sits right on top of it.
      const clear = (control, center) => control.boundary == null
        || Math.abs(control.at - center) > GRIP_CLEARANCE
      const showRow = row > 0 && clear(addRow, (box.top + box.bottom) / 2)
      const showColumn = model.alignments.length > 1
        && clear(addColumn, (box.left + box.right) / 2)
        && box.left >= scrollRect.left - 1 && box.right <= scrollRect.right + 1
      rowGrip.index = showRow ? row : null
      rowGrip.grip.hidden = !showRow
      columnGrip.index = showColumn ? column : null
      columnGrip.grip.hidden = !showColumn
      rowGrip.grip.style.left = `${scrollRect.left - rootRect.left}px`
      rowGrip.grip.style.top = `${(box.top + box.bottom) / 2 - rootRect.top}px`
      columnGrip.grip.style.left = `${(box.left + box.right) / 2 - rootRect.left}px`
      columnGrip.grip.style.top = `${scrollRect.top - rootRect.top}px`
      rowGrip.grip.classList.toggle("is-selected",
        selectedPart?.kind === "row" && selectedPart.row === row)
      columnGrip.grip.classList.toggle("is-selected",
        selectedPart?.kind === "column" && selectedPart.column === column)
    }
    addRow.button.addEventListener("click", () => {
      if (addRow.boundary == null) return
      performAction("insertRowAfter", addRow.boundary, 0)
    })
    addColumn.button.addEventListener("click", () => {
      if (addColumn.boundary == null) return
      const last = model.alignments.length - 1
      if (addColumn.boundary > last) performAction("insertColumnAfter", 0, last)
      else performAction("insertColumnBefore", 0, addColumn.boundary)
    })
    const ADD_BAND = 22
    const ADD_REACH = 9
    const updateAddControls = (event) => {
      if (event.buttons !== 0 || cellDrag) {
        hideAddControls()
        return
      }
      const rootRect = root.getBoundingClientRect()
      const scrollRect = scroll.getBoundingClientRect()
      const place = (control, boundary, x, y, length) => {
        control.boundary = boundary
        control.at = control === addRow ? y : x
        control.button.hidden = false
        control.line.hidden = false
        control.button.style.left = `${x - rootRect.left}px`
        control.button.style.top = `${y - rootRect.top}px`
        control.line.style.left = `${x - rootRect.left}px`
        control.line.style.top = `${y - rootRect.top}px`
        control.line.style[control === addRow ? "width" : "height"] = `${length}px`
      }
      let rowHit = null
      if (event.clientX >= scrollRect.left - ADD_BAND / 2
          && event.clientX <= scrollRect.left + ADD_BAND) {
        let best = ADD_REACH + 1
        Array.from(table.rows).forEach((tr, index) => {
          const distance = Math.abs(event.clientY - tr.getBoundingClientRect().bottom)
          if (distance < best) {
            best = distance
            rowHit = { boundary: index, y: tr.getBoundingClientRect().bottom }
          }
        })
      }
      if (rowHit) place(addRow, rowHit.boundary, scrollRect.left, rowHit.y, scrollRect.width)
      else {
        addRow.line.hidden = true
        addRow.button.hidden = true
        addRow.boundary = null
      }
      let columnHit = null
      if (event.clientY >= scrollRect.top - ADD_BAND / 2
          && event.clientY <= scrollRect.top + ADD_BAND) {
        const headerCells = Array.from(table.rows[0]?.cells || [])
        let best = ADD_REACH + 1
        for (let boundary = 0; boundary <= headerCells.length; boundary++) {
          const x = boundary < headerCells.length
            ? headerCells[boundary].getBoundingClientRect().left
            : headerCells[boundary - 1].getBoundingClientRect().right
          if (x < scrollRect.left - 1 || x > scrollRect.right + 1) continue
          const distance = Math.abs(event.clientX - x)
          if (distance < best) {
            best = distance
            columnHit = { boundary, x }
          }
        }
      }
      if (columnHit) {
        place(addColumn, columnHit.boundary, columnHit.x, scrollRect.top,
          table.getBoundingClientRect().height)
      } else {
        addColumn.line.hidden = true
        addColumn.button.hidden = true
        addColumn.boundary = null
      }
    }
    root.addEventListener("mousemove", (event) => {
      updateAddControls(event)
      updateGrips(event)
    })
    root.addEventListener("mouseleave", hideAddControls)
    return root
  }

  ignoreEvent() { return true }
}
