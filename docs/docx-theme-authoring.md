# Building a DOCX export theme

A DOCX theme is one JSON file that sets how Word exports look: fonts, sizes,
colors, borders, spacing, page margin and code colors. Design background and
rationale are in [docx-export-themes.md](docx-export-themes.md); this page is
the how-to.

Themes come from two places: the ones bundled with the app, and your own in
`~/.config/daisy/docx-themes/` (§2).

## 1. Add a theme

For yourself, no rebuild: put `docx-theme-<id>.json` in
`~/.config/daisy/docx-themes/` and reopen the Export ▸ Word… dialog. Daisy creates the
folder the first time the Export ▸ Word… dialog opens.
Same file rules as below. A file there with the id of a bundled theme (say
`serif`) replaces it; a new id adds a theme. The same folder holds
`keymap.json`, which the app already reads.

To ship one with the app:

1. Create `daisy/Resources/DocxThemes/docx-theme-<id>.json`.
2. Set `"id"` to the same `<id>` as in the file name. The id is 1–32 characters
   of `a–z`, `0–9` and `-`. A file whose id differs from its name is ignored.
3. Build. The `daisy` folder is a synchronized Xcode group, so the file is
   copied to the root of the app's `Contents/Resources` automatically; no
   project edit is needed. The Quick Look extension does not get it.
4. The theme appears in **File ▸ Export ▸ Word… ▸ Theme**, sorted by id.

To give it a localised name, add `"DocxTheme.<id>" = "…";` to each
`Localizable.strings`; otherwise the JSON `name` is shown.

Start from `docx-theme-serif.json` (a small theme) or `docx-theme-github.json`
(every value spelled out); copy one into the folder above to try it.

## 2. User themes

See §1. The folder is read each time the Export ▸ Word… dialog opens. A broken file is
skipped and the rest still load. There is nothing to configure and no
sandbox change: `~/.config/daisy/` is already open to the app for the keymap.

## 3. How a theme is read

Your file is laid over the built-in **GitHub** theme, field by field. Anything
you leave out keeps GitHub's value, so a theme can be a few lines:

```json
{
  "id": "mono",
  "name": "Mono",
  "global": { "font": "Arial" },
  "elements": { "heading1": { "color": "000000" } }
}
```

This changes the body font and Heading 1's color. Everything else, including
heading sizes and the Menlo code font, stays as in GitHub.

Two consequences:

- **Global values do not reach elements that already set their own.** GitHub's
  headings declare size, color and spacing, and code declares Menlo 10 pt.
  Changing `global.font` changes body text only; set `font` on `heading1`–`6`
  (and `codeBlock`, `inlineCode`) to change those.
- **You can replace a value but not remove one.** To get "no shading" use
  `"background": "FFFFFF"`; to get "no border" use `"style": "none"`.

Mistakes never break an export. An unknown key, a wrong-typed value, a bad
color or an out-of-range number is dropped and GitHub's value stays. A file
that is not valid JSON, or lacks `id`/`name`, is skipped, and if no theme
loads at all the app uses GitHub.

## 4. Units and values

| Kind | Format |
| --- | --- |
| Sizes, spacing, indents, border widths | points (`11`, `28.35`) |
| Colors | `RRGGBB` hex, with or without `#` |
| `lineHeight` | a multiple of the font size (`1.15`) |
| Booleans | `true` / `false` |

Ranges: `size` 1–400, spacing and indents 0–1000, `lineHeight` 0.5–5, border
`width` 0–12, border `space` 0–31, `cellPadding` 0–100, `page.margin` 0–300.

Fonts must be installed on the reader's machine; Word substitutes silently
otherwise. Stick to fonts that ship with Word on macOS and Windows: Calibri,
Cambria, Georgia, Consolas, Times New Roman, Arial. Font names are 1–64
characters and cannot contain `< > & " '`.

## 5. File layout

```json
{
  "id": "…", "name": "…",
  "global":   { … },
  "page":     { "margin": 72 },
  "elements": { "heading1": { … }, … },
  "syntax":   { "keyword": "9B2393", … }
}
```

Only `id` and `name` are required.

### `global`

| Key | Meaning |
| --- | --- |
| `font`, `size` | body font and size (also the default for everything) |
| `language` | proofing language, e.g. `en-US` |
| `lineHeight`, `spaceAfter` | default paragraph line spacing and space after |
| `color` | body text color. Leave it out for Word's automatic (black/white) |
| `palette` | named colors, see below |

### Palette

`global.palette` names colors so they are written once. Use `$name` anywhere a
color is expected:

```json
"global": { "palette": { "ink": "14120B", "accent": "A0630F" } },
"elements": { "heading1": { "color": "$ink" }, "link": { "color": "$accent" } }
```

Palette keys are letters, digits and `_`, starting with a letter. Your palette
is merged over GitHub's (`muted`, `border`, `surface`). An unknown `$name` is
treated as unset. References only resolve in *your* file: GitHub's own values
are already concrete colors, so changing `muted` does not recolor Heading 6 or
quotes unless you set `"color": "$muted"` on them.

### `page`

`margin` is the margin on all four sides. Paper size is not themeable; it is A4,
or Letter in the US, Canada and Mexico.

### `elements`

Each key styles one part of the document:

| Element | Styles |
| --- | --- |
| `paragraph` | body text (Word's *Normal*) |
| `heading1` … `heading6` | headings |
| `link` | hyperlinks |
| `list` | bullet and numbered lists |
| `quote` | block quotes |
| `rule` | horizontal rules |
| `codeBlock` | fenced and indented code |
| `inlineCode` | `` `code` `` in text |
| `table` | table borders and cell padding |
| `tableHeader`, `tableBody` | header-row and body cells |

Which properties each element honours:

| Property | Elements |
| --- | --- |
| `font`, `size`, `color`, `bold`, `italic`, `underline`, `strike` | paragraph, headings, link, quote, codeBlock, inlineCode, tableHeader, tableBody |
| `background` | codeBlock (paragraph shading), inlineCode (run shading), tableHeader, tableBody (cell shading) |
| `border` | quote, rule, codeBlock, table |
| `indent` | list, quote, codeBlock |
| `indentRight` | codeBlock |
| `hanging` | list |
| `spaceBefore` | headings, quote, codeBlock |
| `spaceAfter` | headings, list, quote, codeBlock |
| `lineHeight` | codeBlock |
| `markerFont` | list (the bullet glyph's font) |
| `cellPadding` | table (`{ "vertical": 3, "horizontal": 5 }`) |

A property on an element that does not honour it is ignored. Body spacing and
line height are `global` only. Table cells take text properties and background
only; cell padding comes from `table.cellPadding`.

### Borders

```json
"border": {
  "all":  { "width": 0.5, "space": 4, "color": "$border", "style": "single" },
  "left": { "color": "$accent" }
}
```

Sides are `top`, `left`, `bottom`, `right`; `all` is shorthand for every side
(and, on `table`, the lines between cells). A specific side wins over `all`.
`space` is the gap between border and text. `style` is one of `single`,
`double`, `dotted`, `dashed`, `dotDash`, `thick`, `none`; anything else becomes
`single`. A side with no `width` draws nothing.

Border fields merge with GitHub's, so `"left": { "color": "$accent" }` on
`quote` changes only the bar's color.

### `syntax`

Colors for highlighted code, by token: `keyword`, `title`, `titleClass`,
`string`, `number`, `comment`, `doctag`, `type`, `builtIn`, `property`, `meta`,
`attribute`. For each token:

- left out → GitHub's color;
- `"RRGGBB"` → that color;
- `null` or `""` → no color (text uses the code block's color).

Use a light code background: the syntax palette is chosen for dark text on
light paper. Themes are light-only.

## 6. Check it

1. Build and open a Markdown file with headings, lists, a quote, code and a
   table; `tests/fixtures/docx/sample.md` covers all of them.
2. **File ▸ Export ▸ Word…**, pick your theme, open the result in Word.
   Check headings, nested lists, the quote and nested quote, the code box, table header and links.
3. For a bundled theme, add its id to the expected list in
   `tests/swift-tests/Tests/MarkdownHelpersTests/DocxThemeTests.swift`
   (`testEveryBundledThemeProducesWellFormedXML` and
   `testBundledThemesLoadFromFiles`). The first also checks that your theme
   yields well-formed XML for every part.
4. Run `swift test --package-path tests/swift-tests --filter DocxThemeTests`.

Leave `docx-theme-github.json` alone unless you mean to change the default
look: a test requires it to equal the built-in GitHub theme in code
(`DocxTheme.github`) and golden files in `tests/fixtures/docx/` pin its output.

## 7. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Theme missing from the popup | file name not `docx-theme-<id>.json`, `id` differs from the name, invalid JSON, wrong folder, or (bundled) the app was not rebuilt |
| A value has no effect | wrong type or out of range, the element does not honour it (§5), or an unknown `$name`; it silently fell back to GitHub's |
| Headings or code ignore `global.font` | they declare their own; set `font` on those elements |
| Body text is black despite a color | `global.color` unset, or invalid hex |
| Font looks wrong in Word | the font is not installed; Word substituted another |
