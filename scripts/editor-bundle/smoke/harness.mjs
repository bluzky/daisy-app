// Shared setup for the headless editor smoke tests: a jsdom window with the
// built editor bundle evaluated into it, plus the helpers every section uses.
import { JSDOM } from "jsdom"
import { readFileSync } from "node:fs"

export const dom = new JSDOM("<!doctype html><body><div id='editor'></div></body>", {
  pretendToBeVisual: true,
  url: "http://localhost/",
})
globalThis.window = dom.window
globalThis.document = dom.window.document
// Node 21+ exposes `navigator` as a getter-only global; plain assignment throws.
Object.defineProperty(globalThis, "navigator", {
  value: dom.window.navigator,
  configurable: true,
})
for (const key of ["MutationObserver", "ResizeObserver", "requestAnimationFrame",
                   "cancelAnimationFrame", "getComputedStyle", "Range", "Text", "Node",
                   "HTMLElement", "Element", "Document", "DOMParser", "Selection", "Window"]) {
  if (dom.window[key] && !globalThis[key]) globalThis[key] = dom.window[key]
}
if (!globalThis.ResizeObserver) {
  globalThis.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }
  dom.window.ResizeObserver = globalThis.ResizeObserver
}
if (!dom.window.Range.prototype.getClientRects) {
  dom.window.Range.prototype.getClientRects = () => []
}
if (!dom.window.Range.prototype.getBoundingClientRect) {
  dom.window.Range.prototype.getBoundingClientRect = () => ({
    left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0,
  })
}

const bundle = readFileSync(new URL("../../../daisy/Vendor/CodeMirror/mdedit.min.js", import.meta.url), "utf8")
dom.window.eval(bundle)

export const doc = readFileSync(new URL("../../../samples/full.md", import.meta.url), "utf8")

export const results = { failures: 0 }
export const check = (label, ok) => {
  console.log((ok ? "PASS" : "FAIL") + "  " + label)
  if (!ok) results.failures++
}

export const paste = (target, { html = "", text = "", types = [], items = [] } = {}) => {
  const event = new dom.window.Event("paste", { bubbles: true, cancelable: true })
  Object.defineProperty(event, "clipboardData", { value: {
    items,
    types,
    getData: (type) => type === "text/html" ? html : type === "text/plain" ? text : "",
  } })
  target.dispatchEvent(event)
  return event
}

export const enterIn = (host) => host.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))

export const pressKey = (host, key) => host.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }))

export const keyHost = () => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  return host
}
