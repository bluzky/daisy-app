#!/usr/bin/env python3
"""Check a Markdown document's Daisy widget blocks, cards and columns.

Usage: python3 check_widgets.py doc.md [more.md ...]

Reports what Daisy would quietly leave as plain text: a `stat`, `chart` or
`progress` block it can't read, a `{{sparkline: …}}`, `{{badge: …}}` or `{{shape: …}}`
shortcode it can't read (and arguments it ignores), a ```badge block, a bad
color, a card option it doesn't know, a card or column group that never
closes, a card that crosses a column break. Exit code 1 when any file has an
error.

The widget and card rules are shared with the slides skill's checker
(`check_deck.py`, next to this file), so both skills agree with the app.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_deck as rules  # noqa: E402

CARD_OPEN = re.compile(r"^card(?:\s|$)", re.I)


def check(path):
    report = rules.Report(path)
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    _, body_start = rules.split_frontmatter(lines)

    widgets = 0
    in_code, widget, widget_body, code_start = False, None, [], 0
    columns_open = None       # line of an open `<!-- columns -->`
    card_open = None          # (line, columns group it opened in, column index)
    column_index = 0
    for index in range(body_start, len(lines)):
        raw, line_no = lines[index], index + 1
        if rules.FENCE.match(raw):
            if not in_code:
                info = raw.strip().lstrip("`~").strip().lower().split()
                widget = info[0] if info and info[0] in rules.WIDGETS else None
                rules.check_fence_name(info[0] if info else "", line_no, report)
                in_code, widget_body, code_start = True, [], line_no
            else:
                if widget:
                    rules.check_widget(widget, widget_body, code_start, report)
                    widgets += 1
                in_code, widget = False, None
            continue
        if in_code:
            if widget:
                widget_body.append(raw)
            continue

        widgets += rules.check_shortcodes(raw, line_no, report)
        stripped = rules.CODE_SPAN.sub(lambda m: "x" * len(m.group(0)), raw).strip()
        if not (stripped.startswith("<!--") and stripped.endswith("-->")):
            continue
        in_list = bool(raw[:1].isspace()) and any(
            rules.LIST_ITEM.match(previous) for previous in lines[max(0, index - 6):index])
        for comment in rules.COMMENT.findall(stripped):
            text = comment.strip()
            lower = text.lower()
            if CARD_OPEN.match(lower) or lower == "end-card":
                rules.check_card(text, line_no, report, in_list)
                if in_list:
                    continue
                if lower == "end-card":
                    if card_open is None:
                        report.warn(line_no, "`<!-- end-card -->` without an open card does nothing")
                    card_open = None
                else:
                    if card_open is not None:
                        report.warn(card_open[0], "this card is still open when another opens below it; "
                                                  "cards don't nest, so it frames nothing")
                    card_open = (line_no, columns_open, column_index)
                continue
            if in_list or lower not in ("columns", "column", "end-columns"):
                continue
            if lower == "columns":
                if card_open is not None:
                    report.error(card_open[0], "columns can't go inside a card; this card frames nothing")
                    card_open = None
                if columns_open is not None:
                    report.error(line_no, "a column group opens inside another; groups don't nest")
                columns_open, column_index = line_no, 0
            elif lower == "column" and columns_open is not None:
                if card_open is not None and card_open[1] == columns_open:
                    report.error(card_open[0], "this card crosses a `<!-- column -->` break; "
                                               "close it in its own column, or it frames nothing")
                    card_open = None
                column_index += 1
            elif lower == "end-columns" and columns_open is not None:
                if card_open is not None and card_open[1] == columns_open:
                    report.error(card_open[0], "this card is still open at `<!-- end-columns -->`; "
                                               "it frames nothing")
                    card_open = None
                if column_index < 1:
                    report.warn(columns_open, "a column group needs `<!-- column -->` between two parts; "
                                              "with one column it stays plain")
                columns_open = None

    if card_open is not None:
        report.error(card_open[0], "this card has no `<!-- end-card -->`; it frames nothing")
    if columns_open is not None:
        report.error(columns_open, "this column group has no `<!-- end-columns -->`; it stays plain")
    return report, widgets


def main(paths):
    if not paths:
        print(__doc__.strip())
        return 2
    failed = False
    for path in paths:
        report, widgets = check(path)
        issues = sorted([(line, "error", text) for line, text in report.errors]
                        + [(line, "warning", text) for line, text in report.warnings])
        print(f"{path}: {widgets} widgets, {len(report.errors)} errors, {len(report.warnings)} warnings")
        for line, kind, text in issues:
            print(f"  {path}:{line}: {kind}: {text}")
        failed = failed or bool(report.errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
