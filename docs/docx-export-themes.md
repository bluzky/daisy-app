# DOCX export themes

To write a theme, see [docx-theme-authoring.md](docx-theme-authoring.md).

Status: implemented. Covers `daisy/Rendering/DocxExporter.swift` and `daisy/Rendering/Docx/`.

## 1. Problem

The DOCX export has one fixed look. Every font, size, color, border and spacing
value is hardcoded across `DocxExporter.swift`:

| Where | What |
| --- | --- |
| `stylesXML` (~L533) | Calibri 11 pt body, heading sizes/colors/spacing, `ListParagraph`, `Quote`, `CodeBlock`, `InlineCode`, `Hyperlink` styles |
| `numberingXML()` (~L500) | bullet font (`Calibri`), list indents |
| `table(_:)` (~L227) | border color `BFC5CC`, header fill `F2F4F7`, cell margins |
| `block(_:_:)` thematic break (~L180) | rule color `BFC5CC`, width |
| `paragraph(...)` (~L315) | quote nesting indent (`567` twips), list continuation indent (`720`) |
| `CodeSyntaxColors.color(forClasses:)` (~L672) | one fixed light syntax palette |

Changing the look means editing Swift. Users cannot choose a look, and adding a
second look would mean duplicating the style sheet.

## 2. Goals and non-goals

Goals

- A theme is a data file, not code. One file per theme.
- A theme has **global** defaults plus **per-element** overrides, with
  inheritance, so a small theme can be a few lines.
- The built-in `github` theme generates a `styles.xml` **identical** to today's
  (same parts, same attributes, same order), so there is no visual change on
  upgrade. §3.3 defines the exact mapping that makes this achievable; anything
  that cannot map 1:1 is a model change, not a test exception.
- A broken or partial theme never breaks export, **and never produces malformed
  XML**: every theme string that reaches XML is validated and escaped (§4.1).

Non-goals (first version)

- User-supplied theme files (added later, see §14).
- Embedding custom fonts in the `.docx`.
- Dark documents. Word documents are paper; themes are light-only.
- Theming structure the exporter does not emit as separate Word constructs
  (images, footnotes, math, Mermaid).
- Reusing the app's preview themes (`daisy/Theme/ThemePreset.swift`). Those are
  Swift values with four colors and a font; the DOCX needs far more properties.

## 3. Theme file format

JSON, one file per theme, in
`daisy/Resources/DocxThemes/docx-theme-<id>.json`. Bundled files live at the
resource root, not in a `DocxThemes` subdirectory (§10). Units are
the ones a person would write: **points** for sizes and spacing, **hex
`RRGGBB`** (no `#`) for colors. Conversion to Word units (half-points, twips,
eighth-points) happens in one place, the style sheet writer.

```json
{
  "id": "github",
  "name": "GitHub",

  "global": {
    "font": "Calibri",
    "size": 11,
    "language": "en-US",
    "lineHeight": 1.15,
    "spaceAfter": 6,
    "palette": {
      "muted": "59636E",
      "border": "BFC5CC",
      "surface": "F6F8FA"
    }
  },

  "page": { "margin": 72 },

  "elements": {
    "paragraph":   {},

    "heading1":    { "size": 20, "bold": true, "spaceBefore": 18, "spaceAfter": 6, "color": "1F2328" },
    "heading2":    { "size": 16, "bold": true, "spaceBefore": 14, "spaceAfter": 6, "color": "1F2328" },
    "heading3":    { "size": 14, "bold": true, "spaceBefore": 14, "spaceAfter": 6, "color": "1F2328" },
    "heading4":    { "size": 12, "bold": true, "spaceBefore": 14, "spaceAfter": 6, "color": "1F2328" },
    "heading5":    { "size": 11, "bold": true, "spaceBefore": 14, "spaceAfter": 6, "color": "1F2328" },
    "heading6":    { "size": 11, "bold": true, "spaceBefore": 14, "spaceAfter": 6, "color": "$muted" },

    "link":        { "color": "0969DA", "underline": true },
    "list":        { "spaceAfter": 3, "indent": 36, "hanging": 18, "markerFont": "Calibri" },
    "quote":       { "color": "$muted", "indent": 28.35,
                     "border": { "left": { "width": 2.25, "space": 8, "color": "$border" } } },
    "rule":        { "border": { "bottom": { "width": 0.75, "space": 1, "color": "$border" } } },

    "codeBlock":   { "font": "Consolas", "size": 10, "background": "$surface",
                     "lineHeight": 1.0, "spaceBefore": 6, "spaceAfter": 0,
                     "indent": 5.65, "indentRight": 5.65,
                     "border": { "all": { "width": 0.5, "space": 4, "color": "E1E4E8" } } },
    "inlineCode":  { "font": "Consolas", "size": 10, "background": "EFF1F3" },

    "table":       { "border": { "all": { "width": 0.5, "color": "$border" } },
                     "cellPadding": { "vertical": 3, "horizontal": 5 } },
    "tableHeader": { "bold": true, "background": "F2F4F7" },
    "tableBody":   {}
  },

  "syntax": {
    "keyword": "9B2393", "title": "0F68A0", "titleClass": "0B4F79",
    "string": "C41A16", "number": "1C00CF", "comment": "5D6C79",
    "doctag": "4A5560", "type": "3900A0", "builtIn": "6C36A9",
    "property": "326D74", "meta": "643820", "attribute": "815F03"
  }
}
```

The values above are today's hardcoded values, converted to points/hex, so
`docx-theme-github.json` doubles as the regression baseline. Note what is
deliberately **absent**: `global.color`. Today's `docDefaults` and `Normal` emit no
`w:color` (body text is Word's automatic color), and Heading1–5 carry their own
explicit `1F2328` (Heading6 uses `$muted`). Adding a global text color would change body text from
automatic to a fixed color, so `github` omits it. Other themes may set it; see
§4.

### 3.1 Element list

The element set is a closed enum. Unknown keys in a file are ignored, so older
builds tolerate newer theme files.

| Element | Emitted as | Notes |
| --- | --- | --- |
| `paragraph` | `Normal` paragraph style | Sparse overrides; Word's `basedOn` inheritance still applies — see §4 |
| `heading1`–`heading6` | `Heading1`–`Heading6` | Keep `keepNext`, `keepLines`, `outlineLvl` (structural, not themed) |
| `link` | `Hyperlink` character style | |
| `list` | `ListParagraph` + `numbering.xml` levels | `indent`/`hanging` replace the `720*(level+1)`/`360` literals; `markerFont` replaces the bullet `Calibri` |
| `quote` | `Quote` paragraph style | Nested quotes keep the `indent * depth` rule in `paragraph(...)` |
| `rule` | direct `pBdr` on the empty rule paragraph | Not a Word style today; could become a `HorizontalRule` style |
| `codeBlock` | `CodeBlock` paragraph style | |
| `inlineCode` | `InlineCode` character style | |
| `table` | `tblBorders` + `tblCellMar` in `tblPr` | |
| `tableHeader` | `shd` on `tcPr`, bold on runs | Direct formatting, see §6.4 |
| `tableBody` | run properties and cell shading in body cells | Currently empty; exists so themes can style body cells (e.g. zebra later) |

### 3.2 Property support matrix

Every element decodes into one `ElementStyle`, but **support is per element**.
A property marked "–" is ignored for that element, and the loader logs it in
debug builds. This is the contract; the exporter implements exactly this.

| Property | paragraph | heading1–6 | link | list | quote | rule | codeBlock | inlineCode | table | tableHeader / tableBody |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `font` | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | – | ✓ |
| `size` | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | – | ✓ |
| `color` | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | – | ✓ |
| `bold` / `italic` | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | – | ✓ |
| `underline` / `strike` | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | – | ✓ |
| `background` | – | – | – | – | – | – | ✓ (para shading) | ✓ (run shading) | – | ✓ (cell shading) |
| `border` | – | – | – | – | ✓ | ✓ | ✓ | – | ✓ | – |
| `indent` | – | – | – | ✓ | ✓ | – | ✓ | – | – | – |
| `indentRight` | – | – | – | – | – | – | ✓ | – | – | – |
| `hanging` | – | – | – | ✓ | – | – | – | – | – | – |
| `spaceBefore` | – | ✓ | – | – | ✓ | – | ✓ | – | – | – |
| `spaceAfter` | – | ✓ | – | ✓ | ✓ | – | ✓ | – | – | – |
| `lineHeight` | – | – | – | – | – | – | ✓ | – | – | – |
| `markerFont` | – | – | – | ✓ | – | – | – | – | – | – |
| `cellPadding` | – | – | – | – | – | – | – | – | ✓ | – |

Notes:

- `tableHeader` / `tableBody` are limited to **text properties and
  `background`**. They are applied as direct run formatting and cell shading
  (§6.4). Paragraph spacing, indent and line height inside cells are *not*
  themeable: cell paragraphs keep `spacing after=0`, and cell breathing room
  comes from `table.cellPadding`. Alignment still comes from the Markdown
  column alignment.
- The matrix describes **element overrides**, not inherited Word defaults.
  `elements.paragraph.spaceAfter` and `.lineHeight` are unsupported and ignored
  before merging. Set `global.spaceAfter` / `.lineHeight` instead; they feed
  `docDefaults`. `Normal` has no paragraph-spacing overrides, but may have
  supported text overrides. It stays empty for `github`.
- `indent` is the left indent; `indentRight` is new (today's `CodeBlock` has
  both `left=113` and `right=113`).

### 3.3 Exact XML mapping (what `github` must reproduce)

Only these become `<w:style>` parts. Everything else is direct formatting.

| Theme source | Output | Matches today |
| --- | --- | --- |
| `global.font` | `docDefaults/rPrDefault/rFonts` ascii, hAnsi, eastAsia, cs | L552 |
| `global.size` | `rPrDefault` `sz` + `szCs` (half-points) | L553 |
| `global.language` | `rPrDefault` `w:lang w:val` | L553 |
| `global.lineHeight`, `global.spaceAfter` | `pPrDefault` `spacing after`, `line`, `lineRule="auto"` | L554 |
| `global.color` (optional) | `rPrDefault` `w:color` — **omitted when unset** | none today |
| `paragraph` | `Normal` style, empty body | L556 |
| `heading1`–`heading6` | `Heading1`–`Heading6`: `basedOn`, `next`, `qFormat`, `pPr(keepNext, keepLines, spacing before/after, outlineLvl)`, `rPr(b, color, sz, szCs)` | L541–545 |
| `link` | `Hyperlink` character style: `color`, `u` | L573–574 |
| `list` | `ListParagraph` (`spacing after`) + `numbering.xml` level indents | L558–559, L506–507 |
| `quote` | `Quote`: left `pBdr`, `ind left`, `rPr color` | L560–562 |
| `codeBlock` | `CodeBlock`: four-side `pBdr`, `shd`, `spacing`, `ind left` **and `right`**, `rPr` font/size | L563–569 |
| `inlineCode` | `InlineCode` character style: font, size, `shd` | L570–572 |

Direct formatting, **no** `<w:style>`: `rule` (the `pBdr` on the rule
paragraph), `table` (`tblBorders`, `tblCellMar`), `tableHeader`, `tableBody`.
The style sheet generator emits exactly the parts above and nothing else, so
`table`, `tableHeader`, `tableBody` and `rule` never add styles.

### 3.3.1 Serialization of themed properties (custom themes)

§3.3 pins `github`. For any other value the generator follows these rules, so
every property marked supported in §3.2 has a defined output. Children are
written in **WordprocessingML schema order**, only when the **sparse element
property** is set after overlaying the theme on GitHub's element declarations
(§4). Never serialize global-inherited values from `ResolvedStyle` into a Word
style. For `github`, headings therefore have no `rFonts`, and `Quote` has no
`spacing`: Word supplies those values through `docDefaults` / `basedOn`.
The fixed order and sparse declarations preserve today's XML.

Run properties (`w:rPr`) of paragraph and character styles:

| Order | Property | XML |
| --- | --- | --- |
| 1 | `font` | `<w:rFonts w:ascii w:hAnsi w:cs/>` (`w:eastAsia` only in `docDefaults`) |
| 2 | `bold` | `<w:b/>` (`<w:b w:val="0"/>` when explicitly `false` and the parent is bold) |
| 3 | `italic` | `<w:i/>` (same rule) |
| 4 | `strike` | `<w:strike/>` |
| 5 | `color` | `<w:color w:val/>`, omitted when `nil` |
| 6 | `size` | `<w:sz/>` + `<w:szCs/>` (half-points) |
| 7 | `underline` | `<w:u w:val="single"/>` |
| 8 | `background` | `<w:shd w:val="clear" w:color="auto" w:fill/>` (character styles only) |

Paragraph properties (`w:pPr`) of paragraph styles:

| Order | Property | XML |
| --- | --- | --- |
| 1 | structural (headings) | `keepNext`, `keepLines` |
| 2 | `border` | `<w:pBdr>` sides in order top, left, bottom, right |
| 3 | `background` | `<w:shd .../>` |
| 4 | `spaceBefore`, `spaceAfter`, `lineHeight` | `<w:spacing w:before w:after w:line w:lineRule="auto"/>` |
| 5 | `indent`, `indentRight`, `hanging` | `<w:ind w:left w:right w:hanging/>` |
| 6 | structural (headings) | `outlineLvl` |

Consequences, e.g. `paragraph.bold = true` adds `<w:rPr><w:b/></w:rPr>` to
`Normal`; `heading1.font = "Georgia"` adds `rFonts` before `b` in `Heading1`'s
`rPr`; `link.size = 12` adds `sz`/`szCs` to `Hyperlink` between `color` and `u`.
`tableHeader`/`tableBody` text properties follow the same `rPr` order as direct
run formatting (§6.4).

### 3.4 Property set (reference)

All elements decode into one `ElementStyle` type; §3.2 says which properties
each element honours.

| Group | Properties |
| --- | --- |
| Text | `font`, `size`, `color`, `bold`, `italic`, `underline`, `strike` |
| Box | `background`, `border`, `indent`, `indentRight`, `hanging`, `spaceBefore`, `spaceAfter`, `lineHeight` |
| Table | `cellPadding` (only on `table`) |
| List | `markerFont` (only on `list`) |

`border` is `{ "top"|"left"|"bottom"|"right"|"all": { "width", "space", "color", "style" } }`.
`all` is shorthand; a specific side wins over `all`. `style` is one of the
allowlist in §4.1 and defaults to `single`.

`syntax` is a top-level block, not an element property, because it is keyed by
highlighter token, not by Markdown element (§7).

## 4. Inheritance and references

Keep two distinct representations:

1. **Sparse declarations for XML.** Validate and filter theme fields against
   §3.2, then overlay each element on the corresponding sparse GitHub element.
   Merge field by field, including border-side fields and cell padding, rather
   than replacing whole objects. Missing/invalid fields retain GitHub's field;
   fields absent in both remain absent. Do **not** fill gaps from `global` here.
   These declarations drive `styles.xml` and explicit run/cell overrides.
2. **Effective values for calculations and direct formatting.** Where an actual
   value is needed, resolve from the merged element, then merged global, then
   non-emitting metric/boolean defaults (zero/false where applicable). These
   values may drive numbering indents, nested quote indents, borders and layout,
   but must not be blindly serialized as style or run overrides (§6.4).

The effective field precedence is:

`theme.elements.E` → `github.elements.E` → `theme.global` → `github.global`.

Global and page fields are overlaid independently on GitHub's global/page
fields. A theme containing only `global.font: "Georgia"` changes body and
heading fonts, but code stays Consolas; `global.size: 12` changes body size,
not GitHub's six heading sizes or 10 pt code. To change those, explicitly set
an element override. `global.color` has no built-in value; automatic color
applies only when both the merged element and merged global omit color.
Heading1–5 still have GitHub's explicit `1F2328`.

Rules:

- There is no theme-file element-to-element merge (`heading2` never copies
  `heading1`). Word's own inheritance remains: paragraph styles retain
  `basedOn="Normal"`, so supported `paragraph` text overrides also affect
  properties those styles leave unset. Character styles inherit surrounding
  run/paragraph formatting for properties they leave unset. Do not flatten
  this context-dependent Word cascade into `ResolvedStyle`.
- **`$name` references** are valid in any color field. Merge the theme palette
  over GitHub's palette, then resolve references against that merged palette
  before applying each field override. An unknown/invalid reference is treated
  as absent, retaining the corresponding GitHub field if present.
- **Missing file / undecodable JSON** → that theme is dropped from the list; if
  nothing loads, the in-code `.github` fallback is used.

### 4.1 Validation and XML safety

Every theme value that is interpolated into XML is validated, and every string
attribute is escaped. Invalid fields are treated as unset, never as a load
failure, and never reach the XML as-is.

| Field | Rule |
| --- | --- |
| colors | `^[0-9A-Fa-f]{6}$`; a leading `#` is stripped; normalised to upper case |
| `font`, `markerFont`, `global.font` | trimmed, 1–64 chars, no control characters, no `<>&"'`; then passed through `xmlEscape` anyway. Restricting the charset is belt and braces: font names legitimately contain spaces, digits and hyphens, nothing else |
| `language` | BCP 47 shape `^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$` |
| `border.style` | **allowlist**: `single`, `double`, `dotted`, `dashed`, `dotDash`, `thick`, `none`. Anything else → `single` |
| sizes, spacing, indents, widths | finite, within per-property ranges (e.g. `size` 1–400, `border.width` 0–12, `lineHeight` 0.5–5); out of range → unset |
| `id` | `^[a-z0-9-]{1,32}$`; also used as the preference value and localisation key, never as a path |
| `$name` | must exist in `global.palette`, else unset |

Unit conversion rounds to integers (`w:sz`, twips) *after* validation, so no
`NaN`/`inf` can reach an attribute.

Guarantee, tested in §10: for any decodable theme, including a hostile one,
`DocxStyleSheet.xml(for:)` and the document parts are well-formed XML.

`global.palette` is deliberately free-form (`[String: String]`) so themes name
colors however they like. Palette keys are `^[A-Za-z][A-Za-z0-9_]{0,31}$`;
values go through the same color validation.

## 5. Swift model

New files (all under `daisy/Rendering/Docx/`, app-only like the exporter):

```
DocxTheme.swift        # Codable model, validation, inheritance resolver
DocxStyleSheet.swift   # Sparse element declarations -> word/styles.xml
DocxThemeStore.swift   # loads bundled JSON, in-code .github fallback
```

```swift
struct DocxTheme: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var global: GlobalStyle
    var page: PageStyle
    var elements: [Element: ElementStyle]
    var syntax: [SyntaxToken: SyntaxColor]   // absent key = inherit

    enum Element: String, Codable, CaseIterable, Sendable {
        case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
        case link, list, quote, rule, codeBlock, inlineCode
        case table, tableHeader, tableBody
    }
}

struct ElementStyle: Codable, Sendable {
    var font, color, background, markerFont: String?
    var size, lineHeight, indent, indentRight, hanging, spaceBefore, spaceAfter: Double?
    var bold, italic, underline, strike: Bool?
    var border: Borders?
    var cellPadding: CellPadding?
}

struct GlobalStyle: Codable, Sendable {
    var font: String
    var size: Double
    var language: String
    var lineHeight: Double
    var spaceAfter: Double
    var color: String?                        // nil = no w:color emitted
    var palette: [String: String]
}

/// Tri-state for syntax colors. A plain [String: String] cannot decode JSON
/// null; [String: String?] can, but yields a double optional that is easy to
/// misread and is lost on merge. The key being absent is the third state
/// (inherit), so it is the dictionary's absence, not a case.
enum SyntaxColor: Codable, Sendable, Equatable {
    case color(String)   // "9B2393"
    case none            // null or "" -> no color for this token
    // decode: null -> .none; "" -> .none; valid hex -> .color; invalid string
    // -> treated as absent (inherit) by the loader, not .none.
}

/// Validated element declarations overlaid on GitHub, without global fill.
/// Optional fields retain the distinction between absent and explicit values.
/// The style writer consumes these, NOT ResolvedStyle.
struct MergedElementStyle: Sendable {
    var properties: ElementStyle
}

/// Effective values for layout/direct-formatting decisions, in points/hex.
/// Not a complete model of Word's context-dependent style cascade and never
/// used as an unconditional XML emission list. Sparse declarations decide
/// which properties to emit; inline composition is specified in §6.4.
struct ResolvedStyle: Sendable {
    var font: String
    var size: Double
    var bold, italic, underline, strike: Bool
    var color: String?          // nil = automatic (no w:color)
    var background: String?
    var border: ResolvedBorders?
    // box metrics (indent, indentRight, hanging, spaceBefore, spaceAfter,
    // lineHeight) are non-optional with per-element defaults
}

extension DocxTheme {
    func declarations(_ element: Element) -> MergedElementStyle
    func resolved(_ element: Element) -> ResolvedStyle
    /// nil = emit no color on the run (SyntaxColor.none).
    func syntaxColor(_ token: SyntaxToken) -> String?
}
```

**Decoding is custom and lenient** (`DocxTheme.init(from:)`), because synthesised
`Codable` on `[Element: ElementStyle]` / `[SyntaxToken: SyntaxColor]` neither
guarantees JSON-object decoding for enum-keyed dictionaries nor skips unknown
keys, so a newer theme file would fail to load on an older build.

- `Element` and `SyntaxToken` are `String`-raw-value enums. `elements` and
  `syntax` are decoded through a `KeyedDecodingContainer<DynamicKey>`
  (`DynamicKey: CodingKey` with `stringValue`). For each key in `allKeys`:
  unknown name -> skipped; value that fails to decode (`try?`) -> skipped
  (= inherit). One bad element or token never drops the others, and a missing
  or non-object `elements`/`syntax` yields an empty map.
- `ElementStyle.init(from:)` uses `try? decodeIfPresent` per property, so a
  wrong-typed field (`"size": "big"`) is dropped alone, not the whole element.
- `SyntaxColor.init(from:)` uses `singleValueContainer`: `null` -> `.none`,
  `""` -> `.none`, valid hex -> `.color`, anything else (wrong type, bad hex)
  throws, which the keyed loop above turns into "skip = inherit".
- Top-level required fields are `id` and `name`; everything else is optional.
  Decode element fields sparsely, then overlay them as specified in §4. Missing
  global/page fields use their built-in defaults without filling element gaps.

Placement decision: app sources remain in `daisy/Rendering/Docx/`. The test
package consumes app sources through symlinks, confirmed by
`tests/swift-tests/Sources/MarkdownHelpers/ThemePreset.swift`. Symlink the model,
style writer and exporter dependencies into that target for §10's XML/export
tests; do not create divergent copies or move production sources into tests.
These files remain app-only with respect to Quick Look target membership.

## 6. Exporter changes

### 6.1 Entry point

```swift
enum DocxExporter {
    static func write(markdown: String, assetBaseURL: URL?,
                      theme: DocxTheme = .github, to url: URL) throws
}
```

`DocxBuilder` stores `theme`, sparse `[Element: MergedElementStyle]`
declarations, and effective `[Element: ResolvedStyle]` values for calculations.
`DocxStyleSheet` consumes the sparse declarations, not the effective values.

### 6.2 `styles.xml`

`stylesXML` (static string) becomes `DocxStyleSheet.xml(for: theme)`:

- `docDefaults` from `global` (font → `rFonts` ascii/hAnsi/eastAsia/cs, size →
  `sz`/`szCs` in half-points, `lineHeight` → `w:line = round(lh * 240)` with
  `lineRule="auto"`, `spaceAfter` → twips).
- One `<w:style>` per row of the §3.3 table **only**, in the same order as
  today (`Normal`, `Heading1`–`6`, `ListParagraph`, `Quote`, `CodeBlock`,
  `InlineCode`, `Hyperlink`). `rule`, `table`, `tableHeader` and `tableBody` are
  direct formatting and emit no style. Generated in a loop over a fixed
  `[(Element, StyleKind)]` list, replacing the hand-written heading loop and
  per-style strings. Emit only merged sparse element declarations; inherited
  global properties stay in `docDefaults`, not in each style.
- Unit conversion helpers: `halfPoints(pt)`, `twips(pt)`, `eighths(pt)` for
  `w:sz` on borders. Existing literals map exactly (e.g. `0.75 pt → sz=6`,
  `2.25 pt → sz=18`, `0.5 pt → sz=4`).

### 6.3 Removing hex from the body

| Current literal | Becomes |
| --- | --- |
| `BFC5CC` in the thematic-break `pBdr` | `rule` border |
| `BFC5CC` ×6 in `tblBorders` | `table.border` |
| `F2F4F7` in header `tcPr` | `tableHeader.background` |
| `w:top/bottom 60`, `left/right 100` in `tblCellMar` | `table.cellPadding` |
| `bold: header` in `RunStyle` for header cells | `tableHeader.bold` |
| `567` quote indent in `paragraph(...)` | `quote.indent` |
| `720 * (level + 1)` in `paragraph(...)` and `numberingXML()`; `360` hanging | `list.indent` / `list.hanging` |
| `Calibri` in the bullet `rPr` | merged `list.markerFont` (GitHub declares `Calibri`; changing it requires an element override) |

### 6.4 Table header and body

Word has no per-row paragraph style, so `tableHeader`/`tableBody` are applied
as direct formatting on the cells:

- Cell: `<w:shd>` from `background`.
- Runs: supported text fields (`font`, `size`, `color`, `bold`, `italic`,
  `underline`, `strike`) from the **sparse merged cell declarations**, not an
  unconditional dump of `ResolvedStyle`. Global-only values inherit through
  Word, so `github` still adds only bold to plain header text and no text
  properties to plain body cells.
- **Inline formatting wins over cell defaults.** Before writing a run, suppress
  each cell property that its active `InlineCode` or `Hyperlink` sparse style
  explicitly defines. Thus inline code keeps its own font/size, and links keep
  their own color/underline, even when the cell overrides those fields. Custom
  inline-style properties use the same rule. Cell bold/italic/strike remain
  where not overridden; explicit Markdown strong/emphasis/strikethrough takes
  precedence over cell defaults.
- `RunStyle` gains optional font/size/color/underline fields and retains cell
  defaults separately from Markdown inline state until final run serialization.
  `BlockContext.tableCellBold` becomes sparse cell text declarations. Write run
  properties in schema order (`rStyle`, `rFonts`, `b`, `i`, `strike`, `color`,
  `sz`, `szCs`, `u`).
- Not supported on cells (§3.2): paragraph spacing, indent, line height. Cell
  paragraphs keep `spacing after=0`; padding comes from `table.cellPadding`.
- Header row keeps `<w:tblHeader/>` (structural).

### 6.5 Structural XML that stays hardcoded

Not themed, because it works around Word behavior rather than styling:

- The spacer paragraph after each code block (stops Word fusing adjacent
  bordered paragraphs).
- The trailing paragraph after each table.
- `keepNext`/`keepLines`/`outlineLvl` on headings, `tblLayout fixed`, `tblHeader`.
- Page size choice (Letter vs A4 by region). Only the margin is themeable
  (`page.margin`, replacing the `1440` literals in `pgMar` and in `textWidth`).

## 7. Syntax colors

`CodeSyntaxColors.color(forClasses:insideMeta:)` currently returns literals.
Change it to return a **token**, and have the theme map token → color:

```swift
enum SyntaxToken: String { case keyword, title, titleClass, string, number,
                           comment, doctag, type, builtIn, property, meta, attribute }
```

Keep the class-to-token classification rules (`has("title")`,
`has("string","regexp")`, etc.), but **change the parser's context tracking**:

- The span stack holds `SyntaxToken?`, not colors. Push `.meta` for meta spans;
  keywords inside meta also classify as `.meta`.
- Compute `insideMeta` using `stack.contains { $0 == .meta }`, never color
  equality. Disabled meta coloring and identical keyword/meta colors must not
  change classification.
- At `flush()`, find the nearest non-nil token, then call
  `theme.syntaxColor(token)`. A recognized token mapped to `.none` suppresses
  coloring; do not fall back to an ancestor token's color. An unrecognized
  span (nil token) still inherits the nearest recognized ancestor.
- Segment coalescing may compare final colors, but only after classification;
  it must never affect the token stack.

Per token, three states (`SyntaxColor`, §5):

| JSON | State | Result |
| --- | --- | --- |
| key absent | inherit | built-in `github` value for that token |
| `"9B2393"` | color | that color |
| `null` or `""` | none | no `w:color` on the run; text uses `codeBlock.color`, else the style default |

So partial `syntax` blocks are fine, and a theme can switch highlighting off for
one token or for all of them.

The existing comment ("Always light…") stays true: themes are light-only, so the
code box background and syntax palette are a theme concern but the contrast
assumption (dark text on a light box) is the theme author's.

## 8. Built-in themes

| Id | Intent | Differences from `github` |
| --- | --- | --- |
| `github` | Default; today's output | — |
| `serif` | Long-form reading / print; built from the app's **Focus** reader theme | Palette from Focus (ink `14120B`, accent `A0630F`, code surface `F5F1E4`) applied to body text, links, quote bar and code/table shading; `Georgia` 11.5 pt (Word-safe stand-in for Focus's New York), `lineHeight` 1.3, headings in the same serif, no code border |
| `minimal` | Plain, ink-friendly | Black text, no shading on code/table header, thin rules, headings 18/14/12/11/11/11 |
| `document` | Business document; extracted from a real Word document (an incident report) | Calibri 11 pt, single spacing, navy `1F3864` headings (18 / 13 / 11.5 pt), navy table header with white bold text, light gray `CCCCCC` table grid with roomier cells, tighter list indents, 0.75 inch margins |

Fonts are limited to ones that ship with Word on macOS and Windows (Calibri,
Cambria, Georgia, Consolas, Times New Roman, Arial). If a font is missing on the
reader's machine Word substitutes silently; that is acceptable and documented.

## 9. Selecting a theme

- Preference key `DocxExportTheme` (theme id), default `github`, stored next to
  `DocumentExportFormat` in `MarkdownWebView+PDFExport.swift`.
- UI: a "Theme" popup row in `PrintSizeAccessoryController`, below the format
  row. **Constraint from the current code:** `loadView()` builds the rows once
  and fixes the container height and `preferredContentSize` from `rows.count`
  (L348–366); the format row's `onChange` only stores the format and fires the
  summary KVO (L332–338), it never adds or removes views. So the row cannot be
  "added when DOCX is chosen" without extra machinery.
  - **Chosen approach: always present, enabled only for DOCX.** The theme row is
    created in `loadView()` whenever the pane shows the format row (export
    mode), the container height is computed with it included, and nothing is
    resized later. The controller keeps a reference (`themeRow`) and, in the
    format row's `onChange`, sets `themeRow.isEnabled = (format == .docx)`.
    For other formats the popup is disabled and dimmed, which also tells the
    user the choice exists. Initial state is set from `exportFormat` in
    `loadView()`.
  - Rejected: hiding/showing the row (`isHidden` on an `NSStackView` arranged
    view collapses it, but the container's frame and `preferredContentSize` are
    fixed, and the print panel is not guaranteed to resize an accessory pane
    that is already on screen); and rebuilding the accessory controller on
    format change (replaces the view the format popup lives in mid-interaction).
  - If a hidden row is wanted later, it needs: a retained row, an explicit
    height-constraint update, a new `preferredContentSize`, and a manual check
    in the real print panel.
  - `ExportThemeRowView` mirrors `ExportFormatRowView` (label, spacer, popup,
    `AccessoryRowMetrics` height/insets). Its `onChange` writes `DocxExportTheme`
    directly; no controller callback is needed because the value is read at
    write time.
  - Summary items (`localizedSummaryItems`): add a "Theme" item only when
    `exportFormat == .docx`. The existing `willChangeValue`/`didChangeValue`
    around the format change already refreshes the summary, so no new KVO is
    needed beyond doing the same in the theme row's change handler.
  - Verification: switch PDF → HTML → DOCX → PNG in the real panel; the theme
    popup is enabled only for DOCX, the pane height never changes, and the
    summary lists Theme only for DOCX. The print-size row (shown only when
    `exportFormat == nil`, i.e. normal printing) must not gain a theme row.
- `FileExportSource.writeDOCX(to:)` reads the stored id, looks it up in
  `DocxThemeStore`, falls back to `.github`, and passes the theme to
  `DocxExporter.write`.
- Localize theme `name` via `NSLocalizedString` keyed by `id`, falling back to
  the JSON `name`.

## 10. Packaging, project and tests

Packaging

- Source files: `daisy/Resources/DocxThemes/docx-theme-<id>.json`. The `daisy`
  folder uses `PBXFileSystemSynchronizedRootGroup`; a source directory does not
  establish a bundle subdirectory. **Chosen contract: copy individual prefixed
  JSON files to the app resource root.** Do not add a folder reference or rely
  on a `DocxThemes` subdirectory. The prefix avoids generic names such as
  `github.json` colliding with unrelated resources.
- Loader: enumerate `Bundle.main.urls(forResourcesWithExtension: "json",
  subdirectory: nil)`, then filter to direct children of `Bundle.main.resourceURL`
  whose basenames match `docx-theme-<id>.json`. Validate the decoded id and require
  it to match the filename suffix; sort deterministically by id. Do not load
  unrelated JSON or construct paths from unvalidated ids.
- Ensure the synchronized group includes these files in the app's resources,
  exactly once, and excludes them from `quick-look`. Per `AGENTS.md`, diff
  `project.pbxproj` before committing and revert any `DEVELOPMENT_TEAM` rewrite.
- **Built-bundle verification is required, not assumed:** inspect the built
  app's `Contents/Resources` for all three prefixed files at the root, confirm
  none occur in the extension, and run the loader against that bundle. Assert
  ids `github`, `serif`, `minimal` load from files, not the in-code fallback.
  A fixture-bundle test alone does not verify Xcode resource copying.

Tests (`tests/swift-tests`, following `ThemePresetTests.swift`)

1. Overlay and effective precedence: theme element → GitHub element → theme
   global → GitHub global. A global-only Georgia/12 pt theme preserves Consolas
   10 pt code and GitHub heading sizes; explicit element overrides still win.
   Assert sparse declarations do not gain global-inherited fields.
2. `$palette` resolution, including an unknown reference.
3. Validation: bad hex, `#`-prefixed hex, out-of-range size, unknown element key,
   unknown JSON field — each yields a resolved style, never a throw.
4. `docx-theme-github.json` decodes and matches `DocxTheme.github` (in-code)
   in both sparse declarations and effective values. Heading1–5 explicitly
   declare `1F2328`; Heading6 resolves `$muted`.
5. Unit conversion: pt → half-points/twips/eighths against the current literals.
6. Style sheet golden test: capture today's `stylesXML` **before any refactor**
   (copy the string output into `tests/fixtures/docx/styles-github.xml`), then
   assert `DocxStyleSheet.xml(for: .github)` equals it. Possible only because
   §3.3 makes the mapping exact: no `global.color` in `github`; **with**
   `indentRight` and `language` (both present in `docx-theme-github.json` and
   emitted in the XML); no styles for direct-formatted elements. Assert headings
   have no `rFonts` and Quote has no `spacing`, despite effective global font
   and spacing values. Also check that a theme with `global.color` set produces
   a `w:color` in `rPrDefault`, while `github` does not.
7. Syntax tri-state: absent -> built-in value; `"HEX"` -> that color; `null` and
   `""` -> no `w:color` on the run; invalid string -> treated as absent.
   Decoding a file containing `null` must not throw. Parse nested spans with
   `meta: null` and equal keyword/meta colors: only actual meta ancestry affects
   keyword classification. A disabled child token inside a colored parent
   emits no color, while an unrecognized child inherits the parent token.
8. XML safety: a hostile theme (font `"Evil\"/><w:x/>"`, `border.style`
   `"x\" w:y=\"z"`, color `"</w:style>"`, language with quotes, NaN/inf
   sizes) must yield `styles.xml`, `numbering.xml` and `document.xml` that parse
   with `XMLParser` without error, and the border style must be one of the
   allowlist. Run the same check over every bundled theme.
9. Support matrix: for each element, a property marked "-" in §3.2 has no
   effect on the output XML (e.g. `tableHeader.spaceAfter`, `heading1.markerFont`,
   `paragraph.spaceAfter`, `paragraph.lineHeight`). Global spacing/line height
   still changes `docDefaults`, without adding spacing to `Normal`.
10. Table cells: `tableHeader` with `font`, `size`, `color`, `underline`, `strike`
    produces the matching run properties in schema order on plain text. Cover
    body cells too. With cell font/size/color overrides, inline code retains
    its own font/size and links retain their own color/underline; custom inline
    styles and Markdown emphasis win over cell defaults. GitHub plain body
    cells acquire no redundant global font/size/color run properties.
11. Positive serialization (§3.3.1), asserting the exact XML fragment and child
    order for custom themes: `paragraph.bold` -> `Normal` gets `w:b`;
    `heading1.font` -> `Heading1` `rPr` has `rFonts` before `b`; `link.size` ->
    `Hyperlink` `rPr` has `color`, `sz`, `szCs`, `u` in that order;
    `codeBlock.indentRight`; `quote.border.left`; `inlineCode.background`;
    `list.markerFont` in `numbering.xml`. One test per supported cell of the
    §3.2 matrix that `github` does not already exercise.
12. Lenient decoding (§5): a file with an unknown element key, an unknown
    syntax token, a wrong-typed property, and an invalid syntax value still
    loads; the other elements/tokens are intact.
13. Automatic color: where both merged global and merged element omit color
    (e.g. GitHub paragraph/codeBlock, not headings), `ResolvedStyle.color == nil`
    and no `w:color` is emitted. A `.none` syntax token yields runs with no
    `w:color` that inherit from `CodeBlock`.
14. Resource loading: a fixture bundle with root-level prefixed themes and an
    unrelated JSON file loads only themes; a mismatched filename/id is rejected.
    Missing/invalid files use the documented fallback. Also perform the actual
    built-app/extension inspection above before shipping.

Runtime verification (visible change, per `AGENTS.md`)

- Export `tests/fixtures/docx/sample.md` with each theme and open in Word (or Pages /
  Quick Look) to check headings, lists, quote nesting, code box, table header.
- Confirm default export is unchanged vs. a pre-change export of the same file.

## 11. Documentation to update with the change

Per the "documentation that describes behaviour" rule in `AGENTS.md`, in the same
commit:

- The header comment of `DocxExporter.swift` (it states "a fixed style sheet" and
  lists Calibri/Consolas sizes) — rewrite to describe themes.
- `README.md` export section: mention DOCX themes and where they live.
- `samples/docx-export.md` (and regenerate `.docx`/`.html` siblings): exercise
  every element so each theme can be eyeballed.
- `CHANGELOG.md` entry when this ships.

```bash
grep -rn -i "docx\|word document" README.md samples/ tests/fixtures/ docs/
```

## 12. Implementation plan

1. `DocxTheme` model, validation, sparse overlays and effective resolver,
   `.github` in code; unit tests (§10 1–5, 12–13). No behavior change.
2. `DocxStyleSheet` generator from sparse declarations; golden test against
   current `stylesXML` (§10 6), support and serialization tests (9, 11).
   Swap `stylesXML` for it. Output still identical.
3. Move table/rule/quote/list/page literals to the theme (§6.3, §6.4), with
   inline-over-cell precedence and XML safety tests (§10 8, 10).
4. Syntax token stack and flush-time color lookup (§7); test 7.
5. `docx-theme-github.json` + `DocxThemeStore` + prefixed root resource packaging;
   assert JSON == in-code and test loading (§10 14).
6. Add `serif` and `minimal`; verify all three load from the built app bundle
   and no theme resources ship in Quick Look (§10).
7. Preference + export-panel popup (§9).
8. Docs, sample, changelog (§11).

Steps 1–5 land with zero visible change and can be one PR; 6–8 are the
user-visible part and can be a second PR.

## 13. Open questions

1. **User theme files.** Allow `~/Library/Application Support/Daisy/DocxThemes/`
   (or a user-picked folder via a security-scoped bookmark)? Needs a sandbox
   decision. Default proposal: no, bundle-only in v1.
2. **Per-theme page settings.** Only `margin` is proposed. Paper size stays
   region-driven. Add orientation/size later if asked.
3. **`$name` scope.** Palette references are only in `global.palette`. Allow
   referencing other theme-level values (e.g. `$global.size`)? Proposal: no.
4. **Zebra / banded tables, task-list checkbox glyphs, image captions.** Out of
   scope; `tableBody` is a hook for the first.
5. **Preview-theme link.** Should a DOCX theme be able to say "match the current
   preview theme"? Proposal: no; the two models are too different.

Source placement is resolved (§5): app-owned files, symlinked into the Swift
package for testing, excluded from the Quick Look target.

## 14. Implementation notes

Where the code differs from the text above:

- `SyntaxColor.none` is named `SyntaxColor.disabled`: `.none` is ambiguous with
  `Optional.none` in `switch` over an optional.
- `DocxTheme` and its parts are `Decodable` only (nothing encodes themes), and
  stay `nonisolated`, matching the app's default-MainActor setting.
- A theme's `border.all` is expanded when decoding, onto the four sides and
  onto `inside` (the lines between table cells; only `table` uses it). A
  specific side then wins over `all`, and a theme's `all` overlays GitHub's
  sides individually.
- A theme file cannot remove a GitHub property, only replace it. The bundled
  `minimal` theme therefore uses white (`FFFFFF`) for "no shading" and
  `border.style: "none"` for "no border" in `serif`.
- The exporter stays at `daisy/Rendering/DocxExporter.swift`; the theme model,
  style sheet writer, syntax parser and store are in `daisy/Rendering/Docx/`.
  Tests: `tests/swift-tests/Tests/MarkdownHelpersTests/DocxThemeTests.swift`,
  golden output in `tests/fixtures/docx/` (`sample.md` is the input).
- The `CHANGELOG.md` entry is written with the release PR, as for other features.
- **User themes** load from `~/.config/daisy/docx-themes/docx-theme-<id>.json`
  (answers open question 1). The sandbox already grants read-write to
  `~/.config/daisy/` for `keymap.json`, so no entitlement changed. A user theme
  replaces a bundled one with the same id.
- No `samples/` files were added; `tests/fixtures/docx/sample.md` is the file to
  export when eyeballing a theme.
