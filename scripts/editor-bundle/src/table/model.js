// ---------------------------------------------------------------------------
// Visual table editor
// ---------------------------------------------------------------------------

export function splitTableRow(source, includeRanges = false) {
  const cells = []
  let cell = ""
  let cellFrom = 0
  const appendCell = () => cells.push({
    text: cell.trim(),
    from: cellFrom + cell.length - cell.trimStart().length,
    to: cellFrom + cell.trimEnd().length,
  })
  let backslashes = 0
  let codeFenceLength = 0
  for (let index = 0; index < source.length;) {
    const character = source[index]
    if (character === "`" && backslashes % 2 === 0) {
      let end = index + 1
      while (end < source.length && source[end] === "`") end++
      const runLength = end - index
      if (codeFenceLength === 0) codeFenceLength = runLength
      else if (codeFenceLength === runLength) codeFenceLength = 0
      cell += source.slice(index, end)
      index = end
      backslashes = 0
      continue
    }
    if (character === "|" && backslashes % 2 === 0 && codeFenceLength === 0) {
      appendCell()
      cell = ""
      cellFrom = index + 1
    } else {
      cell += character
    }
    backslashes = character === "\\" ? backslashes + 1 : 0
    index++
  }
  appendCell()
  const trimmed = source.trim()
  if (trimmed.startsWith("|") && cells[0].text === "") cells.shift()
  if (trimmed.endsWith("|") && cells[cells.length - 1].text === "") cells.pop()
  return includeRanges ? cells : cells.map(cell => cell.text)
}

function parseTableAlignment(cell) {
  const token = cell.trim()
  const left = token.startsWith(":")
  const right = token.endsWith(":")
  const hyphens = token.replace(/^:/, "").replace(/:$/, "")
  if (!/^-{3,}$/.test(hyphens)) return null
  if (left && right) return "center"
  if (left) return "left"
  if (right) return "right"
  return "none"
}

export function parseTableSource(source) {
  const trailingNewline = source.endsWith("\n")
  const lines = source.replace(/\n$/, "").split("\n")
  if (lines.length < 2) return null
  const header = splitTableRow(lines[0])
  const alignments = splitTableRow(lines[1]).map(parseTableAlignment)
  if (!header.length || !alignments.length || alignments.some((item) => item == null)) return null
  const rows = [header, ...lines.slice(2).map(line => splitTableRow(line))]
  const columnCount = Math.max(alignments.length, ...rows.map((row) => row.length))
  while (alignments.length < columnCount) alignments.push("none")
  alignments.length = columnCount
  for (const row of rows) {
    while (row.length < columnCount) row.push("")
    row.length = columnCount
  }
  return { rows, alignments, trailingNewline }
}

export function escapedTableCell(source, positions = null) {
  const normalized = source.replace(/\n+/g, " ")
  const flattened = normalized.trim()
  const positionMap = positions ? [] : null
  let result = ""
  let backslashes = 0
  let codeFenceLength = 0
  for (let index = 0; index < flattened.length;) {
    if (positionMap) positionMap[index] = result.length
    const character = flattened[index]
    if (character === "`" && backslashes % 2 === 0) {
      let end = index + 1
      while (end < flattened.length && flattened[end] === "`") end++
      const runLength = end - index
      if (codeFenceLength === 0) codeFenceLength = runLength
      else if (codeFenceLength === runLength) codeFenceLength = 0
      if (positionMap) {
        for (let offset = index; offset < end; offset++) positionMap[offset] = result.length + offset - index
      }
      result += flattened.slice(index, end)
      index = end
      backslashes = 0
      continue
    }
    if (character === "|" && backslashes % 2 === 0 && codeFenceLength === 0) result += "\\"
    result += character
    backslashes = character === "\\" ? backslashes + 1 : 0
    index++
  }
  if (positionMap) {
    positionMap[flattened.length] = result.length
    const leading = normalized.length - normalized.trimStart().length
    positions.forEach((position, index) => {
      const normalizedOffset = source.slice(0, position).replace(/\n+/g, " ").length - leading
      positions[index] = positionMap[Math.max(0, Math.min(normalizedOffset, flattened.length))]
    })
  }
  return result
}

export function serializeTable(model) {
  const widths = model.alignments.map((_, column) => Math.max(
    3,
    ...model.rows.map((row) => Array.from(row[column] || "").length),
  ))
  const dataRow = (cells) => "| " + cells.map((cell, column) => {
    const escaped = escapedTableCell(cell)
    return escaped + " ".repeat(Math.max(0, widths[column] - Array.from(escaped).length))
  }).join(" | ") + " |"
  const delimiter = "| " + model.alignments.map((alignment, column) => {
    const width = widths[column]
    if (alignment === "left") return ":" + "-".repeat(Math.max(3, width - 1))
    if (alignment === "right") return "-".repeat(Math.max(3, width - 1)) + ":"
    if (alignment === "center") return ":" + "-".repeat(Math.max(3, width - 2)) + ":"
    return "-".repeat(width)
  }).join(" | ") + " |"
  const lines = [dataRow(model.rows[0]), delimiter, ...model.rows.slice(1).map(dataRow)]
  return lines.join("\n") + (model.trailingNewline ? "\n" : "")
}

// Rows of cells from clipboard text: tab-separated columns, one row per line
// (the format Excel, Numbers and Sheets write). Quoted fields may hold tabs,
// newlines and "" escapes. Returns null for empty input.
export function parseClipboardGrid(text) {
  const source = text.replace(/\r\n?/g, "\n").replace(/\n+$/, "")
  if (!source) return null
  const rows = [[]]
  let cell = ""
  let index = 0
  const endCell = () => { rows[rows.length - 1].push(cell); cell = "" }
  while (index < source.length) {
    const character = source[index]
    if (character === '"' && cell === "") {
      let end = index + 1
      let quoted = ""
      while (end < source.length) {
        if (source[end] === '"' && source[end + 1] === '"') { quoted += '"'; end += 2 }
        else if (source[end] === '"') break
        else quoted += source[end++]
      }
      if (end < source.length && (source[end + 1] === "\t" || source[end + 1] === "\n"
          || end + 1 === source.length)) {
        cell = quoted
        index = end + 1
        continue
      }
    }
    if (character === "\t") endCell()
    else if (character === "\n") { endCell(); rows.push([]) }
    else cell += character
    index++
  }
  endCell()
  return rows.map((row) => row.map((value) => value.replace(/\n+/g, " ")))
}
