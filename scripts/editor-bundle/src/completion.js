import { EditorView, keymap, ViewPlugin } from "@codemirror/view"
import { EditorSelection, EditorState, StateEffect, StateField } from "@codemirror/state"
import { addDays, addMonths, formatLocalDate, parseLocalDate } from "./dates.js"

// A completion menu that follows the caret: typing a trigger opens a session,
// the text after the trigger filters a list, and accepting a row hands it back
// to the provider to apply. The controller owns the session, the keyboard, the
// menu DOM and its placement; everything about what is listed and what a row
// does lives in the provider:
//
//   trigger(state)         The session at the caret, or null when nothing should
//                          open there (the provider's syntax guard). Returns
//                          `{ from, to, query, lineFrom, ... }`: `from..to` is the
//                          typed trigger plus query, `query` the text after the
//                          trigger. A session lasts while `lineFrom` maps to the
//                          same position (the start of the line for slash, the
//                          token's marker for one-token providers). Extra fields
//                          ride along to the hooks below.
//   items(level, query, session)
//                          The rows for a menu level, already ranked for `query`.
//                          The top level is "root"; an empty list closes the menu.
//                          Inside a submenu `query` is only what was typed since
//                          the submenu opened.
//   hasLevel(level, session)
//                          Optional. False sends an open submenu back to "root"
//                          (its source went away while it was showing).
//   parent(level)          Optional. Where Back goes from a submenu (default root).
//   apply(view, session, item)
//                          Perform the row. If the session still matches after
//                          that, it is dismissed, so an accepted row never leaves
//                          the menu open. A row with `submenu: "<level>"` opens
//                          that level instead and is never applied. Opening one
//                          clears the typed query unless the row says
//                          `keepQuery: true`, which leaves the document untouched
//                          so dismissing the menu changes nothing.
//                          `chevron: false` hides the row's `›` (for a row that
//                          opens a calendar rather than a list).
//
// Calendar levels, optional:
//
//   calendar(level, session)
//                          `{ initial, today, locale, describe(date) }` turns the
//                          level into a month grid instead of rows. Dates are
//                          `YYYY-MM-DD`; `describe` gives the footer text for the
//                          selected one. While it shows, typing is ignored.
//   applyDate(view, session, date)
//                          Accept the chosen date.
//
// Presentation, all optional except `classPrefix`:
//
//   classPrefix            CSS/data-attribute stem, e.g. "slash" gives
//                          `.cm-md-slash-menu`, `.cm-md-slash-item`,
//                          `[data-slash-index]` and `[data-slash-back]`.
//   label(item)            Row text (default `item.label`).
//   detail(item)           Secondary text at the end of the row.
//   icon(item)             Inner HTML of the row's icon cell.
//   group(item, session)   Group id the row sits under, or null for no header.
//   groupLabel(id)         Header text for a group id.
//   text(key, fallback)    Localized interface text ("previousMonth", "nextMonth").
//   levelLabel(level, session)
//                          Back-row text shown at the top of a submenu.
//   footer(level, session) Status text under the rows, or null for none. It is
//                          not a row: it cannot be selected or accepted.
export function completionExtensions(provider) {
  const prefix = `cm-md-${provider.classPrefix}`
  const dataKey = (name) => `${provider.classPrefix}${name}`
  const dataAttr = (name) => `data-${provider.classPrefix}-${name.toLowerCase()}`
  const indexKey = dataKey("Index")
  const indexAttr = dataAttr("Index")
  const label = provider.label || ((item) => item.label)
  const hasLevel = provider.hasLevel || (() => true)
  const parent = provider.parent || (() => "root")
  const text = provider.text || ((_key, fallback) => fallback)

  const move = StateEffect.define()
  const pick = StateEffect.define()
  const dismiss = StateEffect.define()
  const enter = StateEffect.define()
  const back = StateEffect.define()
  const moveDate = StateEffect.define()

  const field = StateField.define({
    create: () => null,
    update(value, tr) {
      const trigger = provider.trigger(tr.state)
      if (!trigger) return null
      const sameLine = value && tr.changes.mapPos(value.lineFrom, -1) === trigger.lineFrom
      // Open only from typing or deleting; a loaded document never pops it up,
      // and neither does a host edit that lands the caret on another trigger.
      if (!sameLine && !(tr.docChanged && (tr.isUserEvent("input") || tr.isUserEvent("delete")))) return null
      let level = sameLine ? value.level : "root"
      // The part of the query typed before the current submenu opened.
      let base = sameLine ? value.base : ""
      let navigated = false
      for (const effect of tr.effects) {
        if (effect.is(enter)) { level = effect.value; base = trigger.query; navigated = true }
        else if (effect.is(back)) {
          level = parent(level)
          base = level === "root" ? "" : trigger.query
          navigated = true
        }
      }
      // Deleting back into what opened the submenu leaves it.
      if (level !== "root" && (!trigger.query.startsWith(base) || !hasLevel(level, trigger))) {
        level = "root"
        base = ""
      }
      const query = trigger.query.slice(base.length)
      let dismissed = !!(sameLine && value.dismissed)
      for (const effect of tr.effects) if (effect.is(dismiss)) dismissed = true

      const calendar = provider.calendar ? provider.calendar(level, trigger) : null
      if (calendar) {
        let date = sameLine && !navigated && value.level === level && value.date ? value.date : calendar.initial
        for (const effect of tr.effects) {
          if (!effect.is(moveDate)) continue
          if (effect.value.date) date = effect.value.date
          if (effect.value.days) date = addDays(date, effect.value.days)
          if (effect.value.months) date = addMonths(date, effect.value.months)
        }
        return { ...trigger, items: [], index: 0, dismissed, level, base, filter: query, calendar, date }
      }

      const items = provider.items(level, query, trigger)
      if (!items.length) return null
      const sameList = sameLine && !navigated && value.level === level && value.query === trigger.query
      let index = sameList ? Math.min(value.index, items.length - 1) : 0
      for (const effect of tr.effects) {
        if (effect.is(move)) index = (index + effect.value + items.length) % items.length
        else if (effect.is(pick)) index = Math.max(0, Math.min(effect.value, items.length - 1))
      }
      const footer = provider.footer ? provider.footer(level, trigger) : null
      return { ...trigger, items, index, dismissed, level, base, filter: query, footer }
    },
  })

  const active = (view) => {
    // From compositionstart on, not only once composed text exists, so a key
    // that commits an IME candidate never picks a row.
    if (view.composing || view.compositionStarted) return null
    const state = view.state.field(field, false)
    return state && !state.dismissed ? state : null
  }
  // Opening a submenu clears the typed query (the trigger stays), so what is
  // typed next searches that level rather than the word that got here.
  const openSubmenu = (view, state, item) => {
    const queryFrom = state.to - state.query.length
    const clear = state.query && !item.keepQuery
    view.dispatch({
      changes: clear ? { from: queryFrom, to: state.to, insert: "" } : undefined,
      selection: clear ? EditorSelection.cursor(queryFrom) : undefined,
      effects: enter.of(item.submenu),
    })
  }
  // A submenu row opens its list; anything else is applied.
  const choose = (view, state, item) => {
    if (item.submenu) return openSubmenu(view, state, item)
    provider.apply(view, state, item)
    if (active(view)) view.dispatch({ effects: dismiss.of(null) })
  }
  const accept = (view) => {
    const state = active(view)
    if (!state) return false
    if (state.calendar) provider.applyDate(view, state, state.date)
    else choose(view, state, state.items[state.index])
    return true
  }
  const into = (view) => {
    const state = active(view)
    if (state && state.calendar) return shiftDate({ days: 1 })(view)
    const item = state && state.items[state.index]
    if (!item || !item.submenu) return false
    openSubmenu(view, state, item)
    return true
  }
  // Left always leaves a submenu; Backspace only once nothing is left to delete.
  const out = (onlyWhenEmpty) => (view) => {
    const state = active(view)
    if (state && state.calendar && !onlyWhenEmpty) return shiftDate({ days: -1 })(view)
    if (!state || state.level === "root" || (onlyWhenEmpty && state.filter)) return false
    view.dispatch({ effects: back.of(null) })
    return true
  }
  const step = (delta) => (view) => {
    const state = active(view)
    if (!state) return false
    if (state.calendar) return shiftDate({ days: delta * 7 })(view)
    view.dispatch({ effects: move.of(delta) })
    return true
  }
  const shiftDate = (by) => (view) => {
    const state = active(view)
    if (!state || !state.calendar) return false
    view.dispatch({ effects: moveDate.of(by) })
    return true
  }

  const menu = ViewPlugin.fromClass(class {
    constructor(view) {
      this.view = view
      this.key = null
      const doc = view.dom.ownerDocument
      this.dom = doc.createElement("div")
      this.dom.className = `${prefix}-menu`
      this.dom.setAttribute("role", "listbox")
      this.dom.hidden = true
      const closest = (event, name) => event.target.closest && event.target.closest(`[${dataAttr(name)}]`)
      // Keep focus in the editor: a click must never blur it.
      this.dom.addEventListener("mousedown", (event) => {
        event.preventDefault()
        const state = active(this.view)
        if (!state) return
        const row = closest(event, "Index")
        const day = closest(event, "Date")
        const month = closest(event, "Month")
        if (closest(event, "Back")) this.view.dispatch({ effects: back.of(null) })
        else if (day) provider.applyDate(this.view, state, day.dataset[dataKey("Date")])
        else if (month) this.view.dispatch({ effects: moveDate.of({ months: Number(month.dataset[dataKey("Month")]) }) })
        else if (row) choose(this.view, state, state.items[Number(row.dataset[indexKey])])
      })
      this.dom.addEventListener("mousemove", (event) => {
        const row = closest(event, "Index")
        const state = active(this.view)
        const index = row ? Number(row.dataset[indexKey]) : -1
        if (state && index >= 0 && index !== state.index) this.view.dispatch({ effects: pick.of(index) })
      })
      doc.body.appendChild(this.dom)
      this.sync()
    }

    update() { this.sync() }

    // The menu hides while an IME composes, and committing a candidate need
    // not change the document again, so show it once composition ends. IMEs
    // such as Vietnamese Telex compose every letter.
    compositionEnded() {
      setTimeout(() => { if (this.view.dom.isConnected) this.sync() }, 0)
    }

    sync() {
      const state = active(this.view)
      if (!state) {
        this.dom.hidden = true
        this.key = null
        return
      }
      const key = state.calendar
        ? `${state.level}|calendar|${state.date}`
        : `${state.level}|${state.query}|${state.items.map((item) => item.id).join(",")}|${state.footer || ""}`
      if (this.key !== key || this.dom.hidden) this.rebuild(state)
      this.key = key
      let selected = null
      for (const row of this.dom.querySelectorAll(`[${indexAttr}]`)) {
        const isSelected = Number(row.dataset[indexKey]) === state.index
        row.classList.toggle(`${prefix}-selected`, isSelected)
        row.setAttribute("aria-selected", String(isSelected))
        if (isSelected) selected = row
      }
      this.dom.hidden = false
      if (selected) {
        if (selected.offsetTop < this.dom.scrollTop) this.dom.scrollTop = selected.offsetTop
        else if (selected.offsetTop + selected.offsetHeight > this.dom.scrollTop + this.dom.clientHeight) {
          this.dom.scrollTop = selected.offsetTop + selected.offsetHeight - this.dom.clientHeight
        }
      }
      this.view.requestMeasure({
        key: this,
        read: (view) => {
          try { return view.coordsAtPos(state.to) } catch (_) { return null }
        },
        write: (coords) => this.place(coords),
      })
    }

    make(tag, className, text) {
      const element = this.dom.ownerDocument.createElement(tag)
      element.className = className
      if (text !== undefined) element.textContent = text
      return element
    }

    rebuild(state) {
      const make = (...args) => this.make(...args)
      this.dom.textContent = ""
      this.dom.classList.toggle(`${prefix}-calendar-menu`, !!state.calendar)
      // A calendar has no back row: Backspace still goes back.
      if (state.level !== "root" && !state.calendar) {
        const header = make("div", `${prefix}-back`)
        header.dataset[dataKey("Back")] = ""
        header.appendChild(make("span", `${prefix}-chevron`, "‹"))
        header.appendChild(make("span", `${prefix}-label`, provider.levelLabel ? provider.levelLabel(state.level, state) : ""))
        this.dom.appendChild(header)
      }
      if (state.calendar) {
        this.dom.setAttribute("role", "dialog")
        this.renderCalendar(state)
        this.dom.scrollTop = 0
        return
      }
      this.dom.setAttribute("role", "listbox")
      let group = null
      state.items.forEach((item, index) => {
        const itemGroup = provider.group ? provider.group(item, state) : null
        if (itemGroup != null && itemGroup !== group) {
          group = itemGroup
          this.dom.appendChild(make("div", `${prefix}-group`, provider.groupLabel(group)))
        }
        const row = make("div", `${prefix}-item`)
        row.setAttribute("role", "option")
        row.dataset[indexKey] = String(index)
        if (provider.icon) {
          const icon = make("span", `${prefix}-icon`)
          icon.innerHTML = provider.icon(item)
          row.appendChild(icon)
        }
        row.appendChild(make("span", `${prefix}-label`, label(item)))
        const detail = provider.detail ? provider.detail(item) : null
        if (detail) row.appendChild(make("span", `${prefix}-detail`, detail))
        if (item.submenu && item.chevron !== false) row.appendChild(make("span", `${prefix}-chevron`, "›"))
        this.dom.appendChild(row)
      })
      if (state.footer) {
        const footer = make("div", `${prefix}-footer`, state.footer)
        footer.setAttribute("role", "status")
        this.dom.appendChild(footer)
      }
      this.dom.scrollTop = 0
    }

    renderCalendar(state) {
      const make = (...args) => this.make(...args)
      const { calendar, date } = state
      const locale = calendar.locale || undefined
      const format = (options, value) => {
        try { return new Intl.DateTimeFormat(locale, options).format(value) }
        catch (_) { return new Intl.DateTimeFormat("en", options).format(value) }
      }
      const selected = parseLocalDate(date)
      const head = make("div", `${prefix}-calendar-head`)
      const monthButton = (delta, glyph, name) => {
        const button = make("span", `${prefix}-calendar-nav`, glyph)
        button.dataset[dataKey("Month")] = String(delta)
        button.setAttribute("role", "button")
        button.setAttribute("aria-label", name)
        return button
      }
      const title = make("span", `${prefix}-calendar-title`, format({ month: "long", year: "numeric" }, selected))
      title.setAttribute("aria-live", "polite")
      head.append(
        monthButton(-1, "‹", text("previousMonth", "Previous Month")),
        title,
        monthButton(1, "›", text("nextMonth", "Next Month")),
      )
      this.dom.appendChild(head)

      const grid = make("div", `${prefix}-calendar-grid`)
      grid.setAttribute("role", "grid")
      const firstDay = weekStart(locale)
      const monthStart = new Date(selected.getFullYear(), selected.getMonth(), 1)
      const offset = (monthStart.getDay() - firstDay + 7) % 7
      const gridStart = addDays(formatLocalDate(monthStart), -offset)
      for (let column = 0; column < 7; column++) {
        const weekday = parseLocalDate(addDays(gridStart, column))
        const cell = make("span", `${prefix}-weekday`, format({ weekday: "narrow" }, weekday))
        cell.setAttribute("role", "columnheader")
        cell.setAttribute("aria-label", format({ weekday: "long" }, weekday))
        grid.appendChild(cell)
      }
      for (let index = 0; index < 42; index++) {
        const value = addDays(gridStart, index)
        const day = parseLocalDate(value)
        const cell = make("span", `${prefix}-day`, String(day.getDate()))
        cell.dataset[dataKey("Date")] = value
        cell.setAttribute("role", "gridcell")
        cell.setAttribute("aria-label", format({ dateStyle: "full" }, day))
        cell.setAttribute("aria-selected", String(value === date))
        if (day.getMonth() !== selected.getMonth()) cell.classList.add(`${prefix}-day-outside`)
        if (value === calendar.today) cell.classList.add(`${prefix}-day-today`)
        if (value === date) cell.classList.add(`${prefix}-selected`)
        grid.appendChild(cell)
      }
      this.dom.appendChild(grid)

      // The date Enter would write, so the choice is visible before it is made.
      const footer = make("div", `${prefix}-calendar-footer`, calendar.describe ? calendar.describe(date) : date)
      footer.setAttribute("aria-live", "polite")
      this.dom.appendChild(footer)
    }

    place(coords) {
      if (!coords || this.dom.hidden) return
      const win = this.dom.ownerDocument.defaultView
      const width = this.dom.offsetWidth
      const height = this.dom.offsetHeight
      const below = win.innerHeight - coords.bottom
      const flip = height > below - 8 && coords.top > below
      const top = flip ? Math.max(8, coords.top - height - 4) : coords.bottom + 4
      const left = Math.max(8, Math.min(coords.left, win.innerWidth - width - 8))
      this.dom.style.top = `${top}px`
      this.dom.style.left = `${left}px`
    }

    destroy() { this.dom.remove() }
  }, {
    eventHandlers: { compositionend() { this.compositionEnded() } },
  })

  return [
    field,
    menu,
    // The calendar owns the keyboard: typed or deleted text is dropped until a
    // date is picked, Backspace goes back, or Escape closes it.
    EditorState.transactionFilter.of((tr) => {
      if (!tr.docChanged || !(tr.isUserEvent("input") || tr.isUserEvent("delete"))) return tr
      const state = tr.startState.field(field, false)
      return state && state.calendar && !state.dismissed ? [] : tr
    }),
    keymap.of([
      { key: "ArrowDown", run: step(1) },
      { key: "ArrowUp", run: step(-1) },
      { key: "ArrowRight", run: into },
      { key: "ArrowLeft", run: out(false) },
      { key: "PageDown", run: shiftDate({ months: 1 }) },
      { key: "PageUp", run: shiftDate({ months: -1 }) },
      { key: "Backspace", run: out(true) },
      { key: "Enter", run: accept },
      { key: "Tab", run: accept },
      { key: "Escape", run: (view) => {
        if (!active(view)) return false
        view.dispatch({ effects: dismiss.of(null) })
        return true
      } },
    ]),
    EditorView.domEventHandlers({
      blur(_event, view) {
        if (active(view)) view.dispatch({ effects: dismiss.of(null) })
      },
    }),
  ]
}

// First column of the month grid for a locale: 0 is Sunday. WebKit exposes
// `weekInfo` as a property, other engines as `getWeekInfo()`.
function weekStart(locale) {
  try {
    const info = new Intl.Locale(locale || "en-US")
    const week = typeof info.getWeekInfo === "function" ? info.getWeekInfo() : info.weekInfo
    if (week && week.firstDay) return week.firstDay % 7
  } catch (_) {}
  return 0
}
