import { JSDOM } from "jsdom"
import { convertClipboardToMarkdown } from "./clipboard-markdown.mjs"

const dom = new JSDOM("<!doctype html>")
const convert = (clipboard) => convertClipboardToMarkdown(clipboard, {
  DOMParser: dom.window.DOMParser,
})

let failures = 0
const check = (label, actual, expected) => {
  const passed = typeof expected === "function" ? expected(actual) : actual === expected
  console.log((passed ? "PASS" : "FAIL") + "  " + label)
  if (!passed) {
    console.log("       got: " + JSON.stringify(actual))
    failures++
  }
}

const web = convert({ html: [
  "<h2>Plan</h2>",
  "<p><strong>Ship</strong> <em>soon</em> <del>old</del> ",
  "<a href='https://example.com/docs'>docs</a><br><code>x = 1</code></p>",
  "<blockquote>quoted</blockquote><ol><li>first</li><li>second</li></ol>",
  "<pre>let ready = true</pre>",
].join("") })
check("web formatting converts common Markdown", web, (markdown) =>
  markdown?.includes("## Plan")
    && markdown.includes("**Ship** *soon* ~~old~~ [docs](https://example.com/docs)")
    && markdown.includes("[docs](https://example.com/docs)  \n`x = 1`")
    && markdown.includes("`x = 1`")
    && markdown.includes("> quoted")
    && markdown.includes("1. first\n2. second")
    && markdown.includes("```\nlet ready = true\n```"))

check("HTML table wins over TSV", convert({
  html: "<table><tr><th>Name</th><th>Note</th></tr><tr><td>A|B</td><td><strong>ok</strong></td></tr></table>",
  text: "wrong\tdata\nignored\tvalue",
  types: ["text/html", "text/tab-separated-values"],
}), "| Name | Note |\n| --- | --- |\n| A\\|B | **ok** |")

check("table cells drop stray breaks and blank lines", convert({
  html: "<table><tr><th><p>Name</p></th></tr><tr><td><p>Intro:</p><p>a</p><p>b</p><br></td></tr></table>",
}), "| Name |\n| --- |\n| Intro:<br>a<br>b |")

check("snake_case stays unescaped in table cells", convert({
  html: "<table><tr><th>Name</th></tr><tr><td>page_size and _x_</td></tr></table>",
}), "| Name |\n| --- |\n| page_size and \\_x\\_ |")

check("TSV makes GFM table", convert({ text: "Name\tScore\nAda\t10" }),
  "| Name | Score |\n| --- | --- |\n| Ada | 10 |")
check("single tabbed plain-text row stays plain text", convert({ text: "const x\t= 1" }), null)
check("ordinary plain text stays CodeMirror-owned", convert({ text: "paste me" }), null)

const unsafe = convert({ html: [
  "<script>alert('no')</script><a href='javascript:alert(1)'>bad link</a>",
  "<img src='https://example.com/image.png' alt='diagram'><svg><text>hidden</text></svg>",
].join("") })
check("unsafe HTML is dropped and https image becomes Markdown", unsafe, (markdown) =>
  markdown === "bad link![diagram](https://example.com/image.png)" && !/javascript|hidden/.test(markdown))

check("linked image, data URI and relative image", convert({ html: [
  "<a href='https://example.com'><img src='https://example.com/a (1).png' alt='logo'></a>",
  "<img src='data:image/png;base64,AAAA' alt='inline'><img src='/rel.png' alt='rel'>",
].join("") }), "[![logo](https://example.com/a%20%281%29.png)](https://example.com)inlinerel")

process.exitCode = failures ? 1 : 0
