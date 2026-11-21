# Columns

Put blocks side by side in any document with HTML comments, each on its own line:

```markdown
<!-- columns -->

Left column: any blocks, a list, an image, a table.

<!-- column -->

Right column.

<!-- end-columns -->
```

Type `/columns` to insert the three lines. The comments are invisible in other Markdown viewers, which show the content one block after another.

- `<!-- columns -->` opens a group and `<!-- end-columns -->` closes it. Both are required.
- `<!-- column -->` starts the next column. Without an opener, a lone `<!-- column -->` does nothing in a document (in a slide deck it still splits the slide).
- Two to four columns, equal width. A fifth or later break stays in the fourth column. Empty columns are dropped.
- A group with no closing comment, or with fewer than two columns, is left as plain content, so a typo never pulls the rest of the document into a column.
- Only top-level markers count. A marker inside a list, quote or another block is ignored. Groups cannot be nested; any number of groups can follow each other.
- Windows narrower than about 600 px stack the columns. A wide table or code block scrolls inside its column.
- Read mode, Quick Look and PDF export lay the columns out. The editor shows the comment lines and the blocks one under another. DOCX export lists them one after another.
- Comments, find and scroll sync work inside columns like anywhere else.

The same comments work in a [slide deck](slides.md#columns), where `<!-- columns -->` and `<!-- end-columns -->` are optional: the columns start at `<!-- columns -->` (or right after the heading without it), and everything above stays across the slide.
