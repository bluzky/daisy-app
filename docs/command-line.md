# Command line

In Daisy, choose **Settings → General → Install…** under **Command line tools**. This installs `daisy` in a directory on your `PATH`.

## Open files and folders

```sh
daisy README.md
daisy .
daisy docs
```

## Export DOCX

```sh
daisy export report.md --format docx --output report.docx
```

DOCX is currently sole CLI export format.

```sh
# Select bundled Word theme
daisy export report.md -f docx -o report.docx --theme serif

# Use custom DOCX theme JSON
daisy export report.md -f docx -o report.docx --theme-file ./company-theme.json

# Keep Mermaid fences as code blocks
daisy export report.md -f docx -o report.docx --mermaid off
```

Options:

| Option | Meaning |
| --- | --- |
| `-f`, `--format docx` | Required format. Only `docx` supported. |
| `-o`, `--output PATH` | Required output path. |
| `--theme ID` | Bundled `document`, `github`, `minimal`, or `serif` theme. |
| `--theme-file PATH` | Custom DOCX theme file. Cannot combine with `--theme`. |
| `--mermaid auto\|off\|strict` | `auto` renders when possible; `off` preserves Mermaid as code; `strict` fails if any diagram cannot render. |

CLI DOCX uses same native Word exporter as **File → Export → Word…**. It preserves document structure: headings, lists, tables, links, local images, and syntax-colored code.

Raw HTML is omitted. Math remains source text. Remote images are not downloaded and export as links. Word and Pages may substitute fonts and paginate differently.

Errors go to stderr. Exit codes: `64` invalid usage, `66` unreadable input/theme, `69` rendering failure, `73` output write failure.
