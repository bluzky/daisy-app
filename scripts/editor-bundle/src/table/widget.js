import { WidgetType } from "@codemirror/view"
import { toggleInlineMark } from "../commands/format.js"
import { tableContext } from "./context.js"
import { renderTableCell, tableRenderedTextOffsets } from "./cell-render.js"
import { parseTableSource, serializeTable } from "./model.js"
import { captureTableSelection, prepareTableFormatting, restoreTableFormatting, tableCellCommit, tableCellSourceRange, tableFormattingTargets } from "./selection.js"

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

    const focusCellAfterUpdate = (row, column) => {
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const replacement = view.dom.querySelector(
          `.cm-md-table-widget[data-table-from="${this.from}"]`
        )
        const cell = replacement && replacement.querySelector(
          `[data-table-row="${row}"][data-table-column="${column}"]`
        )
        cell?.focus()
      }))
    }

    const applyModel = (focusTarget = null, commitsCell = false) => {
      const source = serializeTable(model)
      if (source === this.source) {
        if (focusTarget) {
          root.querySelector(
            `[data-table-row="${focusTarget.row}"][data-table-column="${focusTarget.column}"]`
          )?.focus()
        }
        return
      }
      active = null
      view.dispatch({
        changes: { from: this.from, to: this.from + this.source.length, insert: source },
        annotations: commitsCell ? tableCellCommit.of(true) : [],
        userEvent: "input",
      })
      if (focusTarget) focusCellAfterUpdate(focusTarget.row, focusTarget.column)
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
        const number = kind === "row" ? anchor.row : anchor.column + 1
        root.setAttribute(
          "aria-label",
          `Selected ${kind} ${number}. Press Delete to remove it.`
        )
      }
      root.focus()
    }

    const selectTablePart = (kind, row, column) => {
      const bounds = kind === "row"
        ? { top: row, right: model.alignments.length - 1, bottom: row, left: 0 }
        : { top: 0, right: column, bottom: model.rows.length - 1, left: column }
      applyTableSelection(kind, bounds, { row, column })
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
      if (action === "selectRow" && row > 0) {
        selectTablePart("row", row, column)
      } else if (action === "selectColumn" && model.alignments.length > 1) {
        selectTablePart("column", row, column)
      } else if (action === "insertRowBefore" && row > 0) {
        model.rows.splice(row, 0, Array(model.alignments.length).fill(""))
        applyModel({ row, column })
      } else if (action === "insertRowAfter") {
        model.rows.splice(row + 1, 0, Array(model.alignments.length).fill(""))
        applyModel({ row: row + 1, column })
      } else if (action === "duplicateRow" && row > 0) {
        model.rows.splice(row + 1, 0, [...model.rows[row]])
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
          clearPartSelection()
          if (editor.textContent !== model.rows[row][column] || editor.childElementCount) {
            editor.textContent = model.rows[row][column]
          }
          editor.dataset.tableEditing = 'true'
          tableFormattingTargets.set(view, { tableFrom: this.from, row, column, element: editor, anchor: 0, head: 0 })
          active = { row, column, element: editor }
        })
        editor.addEventListener("contextmenu", (event) => {
          event.preventDefault()
          editor.focus()
          active = { row, column, element: editor }
          const token = String(tableContext.nextToken++)
          tableContext.pending = {
            token,
            perform: (action) => performAction(action, row, column),
          }
          window.__mdRequestTableContextMenu?.({
            token,
            canInsertRowAbove: row > 0,
            canDuplicateRow: row > 0,
            canDeleteRow: row > 0,
            canDeleteColumn: model.alignments.length > 1,
            showsDuplicateRow: true,
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
      const cell = event.target.closest?.(".cm-md-table-cell")
      if (!cell) return
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
      cell.focus({ preventScroll: true })
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
        const head = hitTarget?.closest?.(".cm-md-table-cell")
          || moveEvent.target.closest?.(".cm-md-table-cell")
        if (!head || !root.contains(head)) return
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
    root.addEventListener("click", (event) => {
      if (!suppressNextTableClick) return
      suppressNextTableClick = false
      event.preventDefault()
      event.stopPropagation()
    }, true)
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
      const selection = selectedPart
      clearPartSelection()
      performAction(
        selection.kind === "row" ? "deleteRow" : "deleteColumn",
        selection.row,
        selection.column
      )
    })
    return root
  }

  ignoreEvent() { return true }
}
