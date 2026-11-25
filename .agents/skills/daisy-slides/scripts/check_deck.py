#!/usr/bin/env python3
"""Lint a Daisy slide deck for mistakes that render silently wrong.

Usage: python3 check_deck.py deck.md [more.md ...]

Daisy never errors on a deck: a misplaced marker just renders as text, a
heading or nothing. This script finds those cases, plus slides likely to be
cut off (Daisy does not shrink text to fit). It approximates Daisy's parser
(docs/slides.md); when it and Daisy disagree, Daisy's render wins.

Exit status is 1 when there are errors, else 0. Warnings don't fail.
"""

import difflib
import math
import os
import re
import sys

DIRECTIVES = {"layout", "_class", "color", "_color", "step", "columns", "column", "end-columns",
              "space", "_paginate", "_header", "_footer", "_font_size"}
FONT_SIZE = re.compile(r"\d+(\.\d+)?(%|px)?", re.I)
MARP_GLOBALS = {"paginate", "header", "footer", "class", "theme", "backgroundcolor",
                "backgroundimage", "size"}
LAYOUTS = {"title", "section", "quote", "code", "math", "title-image", "split",
           "full-bleed", "columns", "title-content", "blank"}
CLASSES = {"center", "center-x", "center-y", "lead", "invert"}
BG_KEYWORDS = {"left", "right", "fit", "contain", "dim", "blur"}
THEMES = {"default", "original", "quiet", "paper", "bold", "calm", "focus", "ember", "dusk", "midnight",
          "pitch", "paper-warm", "midnight-navy"}
ASPECTS = {"16:9", "16:10", "4:3"}
BREAK = re.compile(r"^ {0,3}(?:-{3,}|\*{3,}|_{3,})\s*$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
COMMENT = re.compile(r"<!--(.*?)-->", re.S)
STEP = re.compile(r"<!--\s*step\s*(?::\s*\d+\s*)?-->")
IMAGE = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s")
CODE_SPAN = re.compile(r"(`+)(?:(?!\1).)+\1")
# Fenced blocks that scale down to fit the slide instead of being cut off.
SCALING_FENCES = ("mermaid",)

# Widgets: fenced blocks the page draws as tiles,
# charts and progress bars. A block Daisy can't read stays plain code,
# silently, so the rules below mirror the page script's.
WIDGETS = {"stat", "chart", "progress"}
# Inline widgets: shortcodes written as inline code, `{{name: arguments}}`.
INLINE_WIDGETS = {"sparkline", "badge", "progress", "shape"}
SHORTCODE = re.compile(r"^\{\{\s*([a-z][a-z0-9-]*):(.*)\}\}$", re.S)
# A shortcode missing its colon (`{{badge Done}}`) is ordinary code.
NEAR_SHORTCODE = re.compile(r"^\{\{\s*([A-Za-z][\w-]*)\b(?!:)")
OPTION_KEY = re.compile(r"^[a-z][a-z0-9-]*$")
# The options each shortcode reads; any other is ignored.
INLINE_OPTIONS = {"sparkline": {"color", "type"}, "badge": {"color", "style", "kind", "size", "ink"},
                  "progress": {"color", "striped", "text"},
                  "shape": {"color", "kind", "style", "size", "ink"}}
# `{{badge: …}}`: each option's values; the first is the default (`ink` has none).
BADGE_OPTIONS = {"style": ("tint", "solid", "outline"), "kind": ("pill", "rounded", "square"),
                 "size": ("sm", "md", "lg"), "ink": ("light", "dark")}
# `{{shape: …}}`: each option's values; the first is the default (`ink` has none).
SHAPE_OPTIONS = {"kind": ("circle", "rounded", "square", "pill", "hexagon", "diamond"),
                 "style": ("solid", "tint", "outline"),
                 "size": ("sm", "md", "lg", "xl"), "ink": ("light", "dark")}
SPARK_TYPES = ("line", "bar")
CHART_TYPES = {"bar", "line", "pie", "donut"}
CHART_LEGENDS = {"top", "bottom", "left", "right", "none"}
CHART_GROUPS = {"legend", "x-axis", "y-axis"}
TRENDS = {"up", "down", "flat"}
# `color:` on a stat, progress bar or card, `color=` on a sparkline or badge, and each of a chart's
# `colors`: one of these names or a #RGB / #RRGGBB hex.
# `neutral` is another name for `default`.
COLOR_NAMES = ("default", "neutral", "accent", "success", "info", "warning", "danger")
COLOR_HINT = "default (or neutral), accent, success, info, warning, danger or a hex like `#6366F1`"


def is_color(value):
    value = (value or "").strip().lower()
    return value in COLOR_NAMES or re.fullmatch(r"#(?:[0-9a-f]{3}|[0-9a-f]{6})", value) is not None
# ExternalLinkPolicy.blockedSchemes: a stat link with one of these is refused.
BLOCKED_SCHEMES = {"javascript", "vbscript", "data", "file", "about", "blob", "filesystem", "md-asset"}
WIDGET_KEY = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$")
NUMBER = re.compile(r"^[-+]?(\d+\.?\d*|\.\d+)$")
# Slide lines a widget takes, roughly: a stat row is a short tile, a progress
# item one line (label, bar, value). A bar or line chart is
# half as tall as the slide is wide, nearly the whole slide; a pie is smaller.
STAT_LINES, PROGRESS_ROW_LINES = 3, 1
# A row of rings: the ring and its label.
RING_LINES = 5
CHART_LINES, PIE_LINES = 10, 7

# Rough capacity of a 16:9 slide at Daisy's slide text size.
MAX_LINES = 12
MAX_BULLETS = 7
MAX_CODE_LINES = 14


class Report:
    def __init__(self, path):
        self.path, self.errors, self.warnings = path, [], []

    def error(self, line, text):
        self.errors.append((line, text))

    def warn(self, line, text):
        self.warnings.append((line, text))


def split_frontmatter(lines):
    """(settings dict, index of the first body line)."""
    if not lines or lines[0].strip() not in ("---", "+++"):
        return {}, 0
    fence = lines[0].strip()
    for index in range(1, len(lines)):
        if lines[index].strip() == fence:
            settings = {}
            for raw in lines[1:index]:
                match = re.match(r"^([A-Za-z_][\w-]*)\s*[:=]\s*(.*)$", raw)
                if match and not raw.startswith((" ", "\t")):
                    settings[match.group(1).lower()] = match.group(2).strip().strip("\"'")
            return settings, index + 1
    return {}, 0


def user_themes():
    folder = os.path.expanduser("~/.config/daisy/themes")
    names = set()
    if os.path.isdir(folder):
        for name in os.listdir(folder):
            stem, ext = os.path.splitext(name)
            if ext.lower() == ".css":
                names.add(stem.lower())
    return names


def check_settings(settings, report):
    if settings.get("slides", "").lower() != "true":
        report.warn(1, "no `slides: true` in the frontmatter: Read Mode shows this as a document "
                       "(View → Present still shows it as slides)")
    if "aspect" in settings and settings["aspect"] not in ASPECTS:
        report.error(1, f"aspect `{settings['aspect']}` isn't one of {', '.join(sorted(ASPECTS))}; "
                        "Daisy falls back to 16:9")
    if "theme" in settings and settings["theme"].lower() not in THEMES | user_themes():
        report.error(1, f"theme `{settings['theme']}` is neither built in nor in "
                        "~/.config/daisy/themes/; Daisy uses the reading theme")
    if "font_size" in settings and not FONT_SIZE.fullmatch(settings["font_size"]):
        report.error(1, f"font_size `{settings['font_size']}` isn't a percentage (`120%`) or pixels (`36`); "
                        "Daisy ignores it")
    if "paginate" in settings and settings["paginate"].lower() not in ("true", "false"):
        report.warn(1, "paginate should be `true` or `false`")


def check_directive(key, value, line, report, in_list):
    if key in DIRECTIVES:
        if in_list and key in ("columns", "column", "end-columns", "space"):
            report.error(line, f"`<!-- {key} -->` inside a list is ignored; put it at the top level")
        if key == "layout" and value.lower() not in LAYOUTS:
            report.error(line, f"unknown layout `{value}`; it is ignored")
        if key == "_class":
            for name in value.split():
                if name not in CLASSES:
                    report.warn(line, f"class `{name}` has no built-in styling "
                                      f"(built in: {', '.join(sorted(CLASSES))})")
        if key == "space" and value and not (value.isdigit() and 1 <= int(value) <= 10):
            report.error(line, "`<!-- space: n -->` takes a whole number from 1 to 10")
        if key == "_font_size" and not FONT_SIZE.fullmatch(value):
            report.error(line, f"font size `{value}` isn't a percentage (`120%`) or pixels (`36`); it is ignored")
        if key in ("color", "_color") and value.startswith("#") and not re.fullmatch(r"#[0-9a-fA-F]{3,8}", value):
            report.error(line, f"color `{value}` isn't a hex color; it is ignored")
        return
    if key in MARP_GLOBALS:
        report.warn(line, f"`{key}` without `_` is a Marp global directive Daisy doesn't read: "
                          f"put it in the frontmatter, or use `_{key}` for this slide")
        return
    close = difflib.get_close_matches(key, DIRECTIVES, n=1, cutoff=0.75)
    if close:
        report.error(line, f"`{key}` isn't a directive; did you mean `{close[0]}`?")


CARD_OPTIONS = {
    "style": {"plain", "outline", "filled", "accent", "solid", "none"},
    "fill": {"none", "surface", "soft", "tint", "solid"},
    "border": {"none", "thin", "thick"},
    "bar": {"none", "left", "top"},
    "color": set(COLOR_NAMES),
    "padding": {"none", "compact", "normal", "roomy"},
    "align": {"start", "center"},
    "shape": {"rounded", "square", "pill", "circle"},
    "ink": {"light", "dark"},
}
# Card options that were renamed before cards shipped.
CARD_RENAMED = {"tint": "`fill=soft`", "edge": "`bar=left` or `bar=top`"}


def check_card(raw, line, report, in_list):
    """Checks `<!-- card key=value … -->` / `<!-- end-card -->`; False when `raw` is neither."""
    lower = raw.lower()
    if lower != "end-card" and lower != "card" and not re.match(r"card\s", lower):
        return False
    if in_list:
        report.error(line, f"`<!-- {raw} -->` inside a list is ignored; put it at the top level")
    seen = set()
    for token in raw.split()[1:] if lower != "end-card" else []:
        key, equals, value = token.partition("=")
        key, value = key.lower(), value.strip("\"'").lower()
        if not equals or not value:
            report.error(line, f"card option `{token}` isn't `key=value`; the card frames nothing")
        elif key in seen:
            report.error(line, f"card option `{key}` appears twice; the card frames nothing")
        elif key in CARD_RENAMED:
            report.error(line, f"card option `{key}` is gone; write {CARD_RENAMED[key]} instead; "
                               "the card frames nothing")
        elif key not in CARD_OPTIONS:
            report.error(line, f"`{key}` isn't a card option ({', '.join(sorted(CARD_OPTIONS))}); "
                               "the card frames nothing")
        elif key == "color" and re.fullmatch(r"#(?:[0-9a-f]{3}|[0-9a-f]{6})", value):
            pass
        elif value not in CARD_OPTIONS[key]:
            report.error(line, f"card `{key}={value}` isn't one of {', '.join(sorted(CARD_OPTIONS[key]))}"
                               + (" or a hex color" if key == "color" else "") + "; the card frames nothing")
        seen.add(key)
    return True


def check_comment(text, line, report, in_list):
    for raw in text.splitlines() or [text]:
        raw = raw.strip()
        if not raw:
            continue
        if check_card(raw, line, report, in_list):
            continue
        key, _, value = raw.partition(":")
        check_directive(key.strip().lower(), value.strip().strip("\"'"), line, report, in_list)


def parse_widget(kind, body, line, report):
    """The block's items, or None after reporting why it stays plain."""
    items = [{}]
    for raw in body:
        text = raw.strip()
        if not text:
            continue
        if re.fullmatch(r"-{3,}", text):
            if items[-1]:
                items.append({})
            continue
        match = WIDGET_KEY.match(text)
        if not match:
            report.error(line, f"`{kind}` block: `{text}` isn't a `key: value` line; the block stays plain code")
            return None
        key = match.group(1).lower()
        if key in items[-1]:
            report.error(line, f"`{kind}` block: `{key}` appears twice in one item; the block stays plain code")
            return None
        items[-1][key] = match.group(2).strip()
    if not items[-1]:
        items.pop()
    if not items:
        report.error(line, f"`{kind}` block is empty; it stays plain code")
        return None
    return items


def table_cells(row):
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|"):
        row = row[:-1]
    return [cell.strip() for cell in row.split("|")]


def check_chart(body, line, report):
    """Reports what would leave a chart as plain code; returns its slide lines."""
    def plain(text):
        report.error(line, f"`chart` block: {text}; the block stays plain code")
        return len(body) + 2

    # A group key with no value (`legend:`) takes the indented lines under it.
    options, rows, group = {}, [], None
    for raw in body:
        text = raw.strip()
        if not text:
            continue
        if text.startswith("|"):
            rows.append(text)
            continue
        if rows:
            return plain(f"`{text}` comes after the table; put every `key: value` line before it")
        match = WIDGET_KEY.match(text)
        if not match:
            return plain(f"`{text}` isn't a `key: value` line or a table row")
        key, value = match.group(1).lower(), match.group(2).strip()
        if raw[:1].isspace():
            if group is None:
                return plain(f"`{text}` is indented but not under `legend:`, `x-axis:` or `y-axis:`")
            if key in group:
                return plain(f"`{key}` appears twice")
            group[key] = value
            continue
        if key in options:
            return plain(f"`{key}` appears twice")
        group = None
        if not value and key in CHART_GROUPS:
            group = options[key] = {}
        else:
            options[key] = value

    kind = options.get("type", "").lower()
    if kind not in CHART_TYPES:
        return plain("`type` must be bar, line, pie or donut")
    legend = options.get("legend", "bottom")
    if isinstance(legend, dict):
        if legend.get("position", "bottom").lower() not in CHART_LEGENDS - {"none"}:
            return plain(f"legend `position: {legend['position']}` isn't top, bottom, left or right")
        if legend.get("visible", "true").lower() not in ("true", "false"):
            return plain(f"legend `visible: {legend['visible']}` isn't true or false")
    elif legend.lower() not in CHART_LEGENDS:
        return plain(f"`legend: {legend}` isn't top, bottom, left, right or none")
    for axis in ("x-axis", "y-axis"):
        if axis not in options:
            continue
        if not isinstance(options[axis], dict):
            return plain(f"`{axis}` takes indented options, like `visible: false` on the next line")
        if options[axis].get("visible", "true").lower() not in ("true", "false"):
            return plain(f"{axis} `visible: {options[axis]['visible']}` isn't true or false")
    if options.get("values", "true").lower() not in ("true", "false"):
        return plain(f"`values: {options['values']}` isn't true or false")
    stacked = options.get("stacked", "false").lower()
    if stacked not in ("true", "false"):
        return plain(f"`stacked: {options['stacked']}` isn't true or false")
    direction = options.get("direction", "vertical").lower()
    if direction not in ("vertical", "horizontal"):
        return plain(f"`direction: {options['direction']}` isn't vertical or horizontal")
    if "colors" in options:
        colors = options["colors"].split(",")
        if len(colors) > 8 or not all(is_color(c) for c in colors):
            return plain(f"`colors` must be up to eight of {COLOR_HINT}, separated by commas")
    if options.get("grid", "true").lower() not in ("true", "false"):
        return plain(f"`grid: {options['grid']}` isn't true or false")
    height = None
    if "height" in options:
        raw_height = re.sub(r"px$", "", options["height"], flags=re.IGNORECASE)
        if not NUMBER.match(raw_height) or not 80 <= float(raw_height) <= 1200:
            return plain(f"`height: {options['height']}` isn't a number of pixels from 80 to 1200")
        height = float(raw_height)
    if len(rows) < 3:
        return plain("it needs a table: a header row, a `| --- |` row and at least one data row")
    header = table_cells(rows[0])
    rule = table_cells(rows[1])
    if len(header) < 2 or len(rule) != len(header) or not all(re.fullmatch(r":?-+:?", cell) for cell in rule):
        return plain("the table needs a label column, at least one number column and a `| --- |` row under the header")
    values = []
    for row in rows[2:]:
        cells = table_cells(row)
        if len(cells) != len(header):
            return plain(f"the row `{row}` has {len(cells)} cells, the header {len(header)}")
        for cell in cells[1:]:
            if not NUMBER.match(cell.replace(",", "")):
                return plain(f"`{cell}` isn't a plain number (put units in the title or header)")
            values.append(float(cell.replace(",", "")))
    if kind in ("pie", "donut"):
        if len(header) != 2:
            return plain(f"a {kind} takes exactly one number column")
        if any(value < 0 for value in values) or sum(values) <= 0:
            return plain(f"a {kind}'s values must be zero or more, with a total above zero")
        return PIE_LINES if height is None else math.ceil(height / 30)
    if height is not None:
        # About 30px a line, plus the axis labels.
        return math.ceil((height + 30) / 30)
    if kind == "bar" and direction == "horizontal":
        # Grows per row, like the page's bar renderer: about 30px a line.
        per_band = 1 if stacked == "true" else len(header) - 1
        band = max(28, per_band * 14 + 12)
        return math.ceil((50 + (len(rows) - 2) * band) / 30)
    return CHART_LINES


def check_widget(kind, body, line, report):
    """Reports what would leave a widget as plain code; returns its slide lines."""
    if kind == "chart":
        return check_chart(body, line, report)
    items = parse_widget(kind, body, line, report)
    if items is None:
        return len(body) + 2

    def plain(text):
        report.error(line, f"`{kind}` block: {text}; the block stays plain code")
        return len(body) + 2

    if kind == "stat":
        for item in items:
            if not item.get("label") or not item.get("value"):
                return plain("every tile needs `label` and `value`")
            if item.get("trend") and item["trend"].lower() not in TRENDS:
                return plain(f"`trend: {item['trend']}` isn't up, down or flat")
            if item.get("good") and item["good"].lower() not in ("up", "down"):
                return plain(f"`good: {item['good']}` isn't up or down")
            if "color" in item and not is_color(item["color"]):
                return plain(f"`color: {item['color']}` isn't {COLOR_HINT}")
            if "link" in item:
                href = item["link"]
                scheme = re.match(r"^([a-z][a-z0-9+.-]*):", href, re.I)
                if not href or re.search(r"\s", href) or (scheme and scheme.group(1).lower() in BLOCKED_SCHEMES):
                    return plain(f"`link: {href}` isn't a link Daisy follows")
        return STAT_LINES + (1 if any(item.get("note") for item in items) else 0)

    # progress
    shape = (items[0].get("shape") or "bar").lower()
    if shape not in ("bar", "ring"):
        return plain(f"`shape: {items[0]['shape']}` isn't bar or ring")
    if any("shape" in item for item in items[1:]):
        return plain("`shape` goes on the first item only; it sets the whole block")
    for item in items:
        value = (item.get("value") or "").replace(",", "")
        maximum = (item.get("max") or "").replace(",", "")
        if not item.get("label") or not NUMBER.match(value) or not NUMBER.match(maximum):
            return plain("every bar needs `label`, and numbers for `value` and `max`")
        if float(value) < 0 or float(maximum) <= 0:
            return plain("`value` must be zero or more and `max` above zero")
        if "color" in item and not is_color(item["color"]):
            return plain(f"a bar's `color` isn't {COLOR_HINT}")
        if (item.get("striped") or "false").lower() not in ("true", "false"):
            return plain("a bar's `striped` must be true or false")
        if shape == "ring" and (item.get("striped") or "false").lower() == "true":
            return plain("a ring takes no `striped`")
        if "text" in item:
            for placeholder in re.findall(r"\{([^}]*)\}", item["text"]):
                if placeholder not in ("value", "max", "percent"):
                    report.warn(line, f"`{{{placeholder}}}` in `text` isn't a placeholder "
                                      "({value}, {max}, {percent}); it shows as typed")
            if shape == "ring" and item["text"].lower() != "none":
                number = lambda raw: f"{float(raw.replace(',', '')):,.2f}".rstrip("0").rstrip(".")
                percent = f"{round(min(float(value) / float(maximum), 1) * 100)}%"
                shown = (item["text"].replace("{value}", number(value)).replace("{max}", number(maximum))
                         .replace("{percent}", percent))
                if len(shown) > 8:
                    report.warn(line, f"ring text `{item['text']}` is long; it shrinks and may be cut off")
    if shape == "ring":
        return RING_LINES
    return math.ceil(len(items) * PROGRESS_ROW_LINES)


def check_fence_name(word, line, report):
    """A ```badge block is no longer drawn: badges are inline shortcodes."""
    if word == "badge":
        report.error(line, "a ```badge block isn't drawn any more; write the badge inline as "
                           "`{{badge: \"text\" color=success}}`")


def tokenize(text):
    """Shortcode arguments as (positional, options), or None when Daisy can't read them.

    Mirrors the page script: values split on spaces; "…" or '…' quote a value
    with spaces (no escapes); a value ending in a comma continues into the next;
    `key=value` is an option. An unclosed quote or an empty, malformed or
    repeated key makes the shortcode unreadable.
    """
    positional, options = [], {}
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            break
        token, key_end, quoted, trailing_comma = "", -1, False, False
        while True:
            if i >= n or text[i].isspace():
                if not trailing_comma:
                    break
                while i < n and text[i].isspace():
                    i += 1
                if i >= n:
                    break
            ch = text[i]
            if ch in "\"'":
                end = text.find(ch, i + 1)
                if end < 0:
                    return None
                token += text[i + 1:end]
                quoted, trailing_comma, i = True, False, end + 1
                continue
            if ch == "=" and key_end < 0 and not quoted:
                key_end = len(token)
            token += ch
            trailing_comma = ch == ","
            i += 1
        if key_end < 0:
            positional.append(token)
            continue
        key = token[:key_end]
        if not OPTION_KEY.match(key) or key in options:
            return None
        options[key] = token[key_end + 1:]
    return positional, options


def check_shortcodes(raw, line, report):
    """Reports shortcodes in a line's code spans that Daisy leaves as code; returns how many it draws."""
    drawn = 0
    for span in CODE_SPAN.finditer(raw):
        fence = len(span.group(1))
        code = span.group(0)[fence:-fence]
        if len(code) > 2 and code.startswith(" ") and code.endswith(" ") and code.strip():
            code = code[1:-1]
        match = SHORTCODE.match(code)
        if not match:
            near = NEAR_SHORTCODE.match(code)
            if near and near.group(1).lower() in INLINE_WIDGETS:
                report.error(line, f"`{code}` needs a colon after the name (`{{{{{near.group(1).lower()}: …}}}}`); "
                                   "it stays inline code")
            continue
        name = match.group(1)
        if name not in INLINE_WIDGETS:
            hint = difflib.get_close_matches(name, sorted(INLINE_WIDGETS), n=1)
            if hint or name in WIDGETS:
                suggestion = f"; did you mean `{hint[0]}`?" if hint else f"; `{name}` is a fenced block, not a shortcode"
                report.error(line, f"`{code}`: `{name}` isn't a shortcode{suggestion}")
            continue
        args = tokenize(match.group(2))
        if args is None:
            report.error(line, f"`{code}`: an unclosed quote, or a key that's empty, malformed or repeated; "
                               "it stays inline code")
            continue
        positional, options = args

        def plain(text):
            report.error(line, f"`{code}`: {text}; it stays inline code")

        if "color" in options and not is_color(options["color"]):
            plain(f"`color={options['color']}` isn't {COLOR_HINT}")
            continue
        if name == "sparkline":
            values = positional[0].split(",") if positional else []
            if not positional or any(not NUMBER.match(v.strip()) for v in values):
                plain("a sparkline needs a comma list of numbers, like `3,5,2,8`")
                continue
            if len(values) < 2:
                plain("a sparkline needs at least two numbers")
                continue
            if "type" in options and options["type"].lower() not in SPARK_TYPES:
                plain(f"`type={options['type']}` isn't line or bar")
                continue
            if len(positional) > 1:
                report.warn(line, f"`{code}`: only the first list is drawn; `{' '.join(positional[1:])}` is ignored")
        elif name == "progress":
            written = positional[0].strip() if positional else ""
            parts = written.split("/")
            if len(parts) == 2:
                value, maximum = (NUMBER.match(p.strip().replace(",", "")) and float(p.strip().replace(",", ""))
                                  for p in parts)
            elif written.endswith("%") and NUMBER.match(written[:-1].strip()):
                value, maximum = float(written[:-1].strip()), 100.0
            else:
                value = maximum = None
            if value is None or maximum is None or value is False or maximum is False \
                    or value < 0 or maximum <= 0:
                plain("inline progress is a fraction like `7/12` or a percentage like `58%` "
                      "(value 0 or more, maximum above 0)")
                continue
            if options.get("striped", "false").lower() not in ("true", "false"):
                plain(f"`striped={options['striped']}` isn't true or false")
                continue
            if len(positional) > 1:
                report.warn(line, f"`{code}`: only `{written}` is read; `{' '.join(positional[1:])}` is ignored "
                                  "(put words in `text=\"…\"`)")
        elif name == "shape":
            text = positional[0].strip() if positional else ""
            if options.get("style", "").lower() == "filled":
                plain("`style=filled` is now `style=solid`")
                continue
            pill = options.get("kind", "").lower() == "pill"
            if not 1 <= len(text) <= (12 if pill else 3):
                plain("a pill shape takes 1 to 12 characters" if pill else
                      "a shape needs one to three characters, like `1`, `A` or `98%` (`kind=pill` takes up to 12)")
                continue
            bad = next((key for key, values in SHAPE_OPTIONS.items()
                        if key in options and options[key].lower() not in values), None)
            if bad:
                plain(f"`{bad}={options[bad]}` isn't {' or '.join(SHAPE_OPTIONS[bad])}")
                continue
            if len(positional) > 1:
                report.warn(line, f"`{code}`: the shape shows only `{positional[0]}`; "
                                  f"`{' '.join(positional[1:])}` is ignored")
        else:
            if not positional or not positional[0].strip():
                plain("a badge needs its text")
                continue
            bad = next((key for key, values in BADGE_OPTIONS.items()
                        if key in options and options[key].lower() not in values), None)
            if bad:
                plain(f"`{bad}={options[bad]}` isn't {' or '.join(BADGE_OPTIONS[bad])}")
                continue
            if len(positional) > 1:
                report.warn(line, f"`{code}`: the badge shows only `{positional[0]}`; quote text with spaces, "
                                  f"like `\"{' '.join(positional)}\"`")
        for key in options:
            if key not in INLINE_OPTIONS[name]:
                report.warn(line, f"`{code}`: `{key}` isn't a {name} option; it's ignored")
        drawn += 1
    return drawn


def check_slide(slide, number, report, deck_dir):
    lines = slide["lines"]
    bullets, backgrounds, column_breaks = 0, 0, 0
    # Content lines per stretch of the slide: before the columns, each
    # column, and after `end-columns`. Columns sit side by side, so only
    # the tallest one adds to the slide's height.
    before, columns, after, place = 0, [], 0, "before"

    def add(count=1):
        nonlocal before, after
        if place == "before":
            before += count
        elif place == "columns":
            columns[-1] += count
        else:
            after += count
    in_code, code_lines, code_start, scales = False, 0, 0, False
    widget, widget_body = None, []
    for index, (line_no, raw) in enumerate(lines):
        if FENCE.match(raw):
            if not in_code:
                info = raw.strip().lstrip("`~").strip().lower()
                words = info.split()
                scales = info.startswith(SCALING_FENCES)
                widget = words[0] if words and words[0] in WIDGETS else None
                check_fence_name(words[0] if words else "", line_no, report)
                widget_body = []
                in_code, code_lines, code_start = True, 0, line_no
                if not widget:
                    add()
            elif widget:
                # A widget takes its drawn height, not one line per source line.
                add(check_widget(widget, widget_body, code_start, report))
                in_code, widget = False, None
            else:
                if code_lines > MAX_CODE_LINES and not scales:
                    report.warn(code_start, f"slide {number}: a {code_lines}-line code block will likely be cut off")
                in_code = False
                add()
            continue
        if in_code:
            if widget:
                widget_body.append(raw)
                continue
            code_lines += 1
            add(0 if scales else 1)
            continue
        check_shortcodes(raw, line_no, report)
        # Text in `code spans` is literal: an example, never a marker.
        raw = CODE_SPAN.sub(lambda match: "x" * len(match.group(0)), raw)
        stripped = raw.strip()
        if not stripped:
            continue
        if stripped == "|||":
            report.error(line_no, "`|||` isn't a column break in Daisy; use `<!-- column -->` on its own line")
            continue
        in_list = bool(raw[:1].isspace()) and any(LIST_ITEM.match(previous)
                                                   for _, previous in lines[max(0, index - 6):index])
        comments = COMMENT.findall(raw)
        if stripped.startswith("<!--") and stripped.endswith("-->") and COMMENT.sub("", stripped).strip() == "":
            for comment in comments:
                check_comment(comment, line_no, report, in_list)
                for key in (raw.split(":")[0].strip().lower() for raw in comment.splitlines()):
                    if key == "columns" and not in_list and place == "before":
                        # Everything so far stays above the columns; the
                        # first column starts here.
                        columns.append(0)
                        place = "columns"
                    elif key == "column" and not in_list and place != "after":
                        column_breaks += 1
                        if place == "before":
                            # The opening heading stays above; the rest so
                            # far is the first column.
                            columns.append(max(before - 1, 0))
                            before = min(before, 1)
                        columns.append(0)
                        place = "columns"
                    elif key == "end-columns" and place == "columns":
                        place = "after"
            continue
        for match in STEP.finditer(raw):
            if raw[match.end():].strip():
                report.error(line_no, "`<!-- step -->` must be the last thing on its line; "
                                      "in the middle of text it is ignored")
        add()
        if LIST_ITEM.match(raw):
            bullets += 1
        for image in IMAGE.finditer(raw):
            alt, source = image.group(1), image.group(2)
            words = alt.lower().split()
            if words[:1] == ["bg"]:
                backgrounds += 1
                alone = IMAGE.sub("", raw).strip() == ""
                if not alone or LIST_ITEM.match(raw):
                    report.error(line_no, "a `bg` image must be alone in its own paragraph; "
                                          "this one renders as an ordinary image")
                for word in words[1:]:
                    if word not in BG_KEYWORDS:
                        report.warn(line_no, f"background keyword `{word}` is ignored "
                                             f"(known: {', '.join(sorted(BG_KEYWORDS))})")
            if not re.match(r"^(?:[a-z]+:|#)", source, re.I):
                path = os.path.normpath(os.path.join(deck_dir, source))
                if not os.path.exists(path):
                    report.warn(line_no, f"image `{source}` not found next to the deck")
        if stripped.startswith("!caption") and not re.fullmatch(r"!caption\[.*\]", stripped):
            report.error(line_no, "a caption is `!caption[text]` alone on its line")
    if backgrounds > 1:
        report.warn(slide["start"], f"slide {number}: {backgrounds} backgrounds; only the first is used")
    if column_breaks > 3:
        report.warn(slide["start"], f"slide {number}: {column_breaks + 1} columns; at most 4 are shown")
    content = before + max(columns, default=0) + after
    if content - backgrounds > MAX_LINES:
        report.warn(slide["start"], f"slide {number}: {content} lines of content may be cut off "
                                    "(Daisy doesn't shrink text): check it in Slide Preview (⌘9), "
                                    "or split it or move detail to `???` notes")
    elif bullets > MAX_BULLETS:
        report.warn(slide["start"], f"slide {number}: {bullets} bullets is a lot for one slide")


def check(path):
    report = Report(path)
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    settings, body_start = split_frontmatter(lines)
    check_settings(settings, report)

    slides, current, notes = [], {"start": body_start + 1, "lines": []}, False
    in_code = False
    previous = ""
    for index in range(body_start, len(lines)):
        raw, line_no = lines[index], index + 1
        if FENCE.match(raw):
            in_code = not in_code
        if not in_code and BREAK.match(raw):
            text_above = previous.strip() and not LIST_ITEM.match(previous) \
                and not previous.lstrip().startswith((">", "<!--", "|", "#"))
            if raw.strip().startswith("-") and text_above:
                report.error(line_no, "this `---` sits right under a line of text, which makes that "
                                      "text a heading; put a blank line above it to start a slide")
            elif not raw[:1].isspace():
                slides.append(current)
                current, notes = {"start": line_no, "lines": []}, False
                previous = raw
                continue
        if not in_code and raw.strip() == "???" and not raw[:1].isspace():
            notes = True
        elif not in_code and raw.strip().startswith("???") and not notes:
            report.error(line_no, "`???` must be alone on its line to start speaker notes")
        if not notes:
            current["lines"].append((line_no, raw))
        previous = raw
    slides.append(current)
    slides = [slide for i, slide in enumerate(slides)
              if any(text.strip() for _, text in slide["lines"]) or 0 < i < len(slides) - 1]

    deck_dir = os.path.dirname(os.path.abspath(path))
    for number, slide in enumerate(slides, start=1):
        check_slide(slide, number, report, deck_dir)
    return report, len(slides)


def main(paths):
    if not paths:
        print(__doc__.strip())
        return 2
    failed = False
    for path in paths:
        report, count = check(path)
        issues = sorted([(line, "error", text) for line, text in report.errors]
                        + [(line, "warning", text) for line, text in report.warnings])
        print(f"{path}: {count} slides, {len(report.errors)} errors, {len(report.warnings)} warnings")
        for line, kind, text in issues:
            print(f"  {path}:{line}: {kind}: {text}")
        failed = failed or bool(report.errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
