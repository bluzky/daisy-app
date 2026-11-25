# Layout

Columns, cards and text alignment. Columns and cards are HTML comments on their own lines, so other Markdown viewers show the blocks one after another. See [Columns](../docs/columns.md) and [Cards](../docs/cards.md) for every option.

## Columns

Text before the group.

<!-- columns -->

#### Before

- Slow builds
- Manual releases

<!-- column -->

#### After

- Cached builds
- One-command releases

<!-- column -->

#### Later

| Step | Status |
| --- | --- |
| Plan | done |

<!-- end-columns -->

Text after the group runs the full width.

An unfinished group stays plain:

<!-- columns -->

Only one column here.

<!-- end-columns -->

## Cards

### Style presets

<!-- columns -->
<!-- card -->
**plain** (the default)
<!-- end-card -->
<!-- column -->
<!-- card style=outline -->
**outline**
<!-- end-card -->
<!-- column -->
<!-- card style=filled color=success -->
**filled**
<!-- end-card -->
<!-- end-columns -->

<!-- columns -->
<!-- card style=accent color=info -->
**accent**
<!-- end-card -->
<!-- column -->
<!-- card style=solid color=accent -->
**solid**
<!-- end-card -->
<!-- column -->
<!-- card style=none -->
**none**: no box, only padding
<!-- end-card -->
<!-- end-columns -->

### Fill, border and bar

An option beside `style` overrides the preset; without `style`, each part is set on its own.

<!-- columns -->
<!-- card style=accent bar=top color=success -->
`style=accent bar=top`
<!-- end-card -->
<!-- column -->
<!-- card fill=soft border=none color=warning -->
`fill=soft border=none`
<!-- end-card -->
<!-- column -->
<!-- card border=thick color=danger fill=none -->
`border=thick fill=none`
<!-- end-card -->
<!-- end-columns -->

<!-- columns -->
<!-- card style=solid color=#ffd60a ink=dark -->
`style=solid color=#ffd60a ink=dark`: dark text on a light color
<!-- end-card -->
<!-- column -->
<!-- card style=solid color=warning ink=light -->
`style=solid color=warning ink=light`: white text on warning
<!-- end-card -->
<!-- end-columns -->

### Shapes and solid cards

Card shapes, with `shape=` on the card:

<!-- columns -->
<!-- card shape=circle style=filled color=success -->
### 3,204
Active users
<!-- end-card -->
<!-- column -->
<!-- card shape=circle style=outline color=info -->
### 99.6%
Crash-free
<!-- end-card -->
<!-- column -->
<!-- card shape=pill style=filled color=warning -->
**Code freeze** Friday
<!-- end-card -->
<!-- card shape=square style=outline -->
**Release** in 9 days
<!-- end-card -->
<!-- end-columns -->

Solid, soft and bare cards, with `fill`, `border` and `bar` set one by one:

<!-- columns -->
<!-- card style=solid color=accent -->
### `{{shape: ✓ kind=hexagon style=tint}}` Ready to ship
All [release checks](#release-42) pass.
<!-- end-card -->
<!-- column -->
<!-- card fill=soft border=none bar=top color=warning -->
### Heads up
Docs are 4 pages behind.
<!-- end-card -->
<!-- column -->
<!-- card style=none align=center -->
`{{shape: 9 size=xl style=outline color=info}}`

**days** to release
<!-- end-card -->
<!-- end-columns -->

## Text alignment

Use **Settings → Reading → Text & layout → Text alignment** to try Automatic, Left, Center, Right, and Justified. Automatic keeps the existing document alignment. This sample includes paragraphs, quotes, lists, right-to-left text, code, tables, and explicit HTML alignment.

A long paragraph makes justification easier to inspect. With Justified selected, the words should extend to both edges of the text column, while the final line stays naturally aligned. Resize the window or change Content width to compare a narrow reading column with a wider page. Changing alignment should update this document immediately, without changing its Markdown source or the formatting of code and tables.

> This quotation follows the selected prose alignment. Its border and indentation remain in place while the words align within the quotation.

- A list item also follows the selected alignment.

  ```text
  Code nested inside a list keeps its spacing.
      This line is indented.
  ```

مرحبا بالعالم. هذه فقرة عربية لاختبار اتجاه القراءة والمحاذاة. في الوضع التلقائي تبقى محاذاة النص إلى اليمين.

| Left | Center | Right |
| :--- | :----: | ----: |
| One | Two | Three |

```swift
func greet() {
    print("Code keeps its indentation.")
}
```

<p align="center">This HTML paragraph stays centered.</p>

<center><p>This legacy HTML paragraph also stays centered.</p></center>

<div align="right"><p>This HTML paragraph stays right-aligned.</p></div>

### Source line breaks

This ordinary source newline
follows the Strict line breaks preference.

This explicit Markdown break stays visible.  
This is the next line.
