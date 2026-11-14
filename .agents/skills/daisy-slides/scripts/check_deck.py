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
import os
import re
import sys

DIRECTIVES = {"layout", "_class", "color", "_color", "step", "column", "end-columns",
              "space", "_paginate", "_header", "_footer", "_font_size"}
FONT_SIZE = re.compile(r"\d+(\.\d+)?(%|px)?", re.I)
MARP_GLOBALS = {"paginate", "header", "footer", "class", "theme", "backgroundcolor",
                "backgroundimage", "size"}
LAYOUTS = {"title", "section", "quote", "code", "math", "title-image", "split",
           "full-bleed", "columns", "title-content", "blank"}
CLASSES = {"center", "center-x", "center-y", "lead", "invert"}
BG_KEYWORDS = {"left", "right", "fit", "contain", "dim", "blur"}
THEMES = {"default", "light", "dark", "paper", "midnight", "pitch"}
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
    folder = os.path.expanduser("~/.config/daisy/slide-themes")
    names = set()
    if os.path.isdir(folder):
        for name in os.listdir(folder):
            stem, ext = os.path.splitext(name)
            if ext.lower() in (".yaml", ".yml"):
                names.add(stem.lower())
                with open(os.path.join(folder, name), encoding="utf-8") as handle:
                    for raw in handle:
                        match = re.match(r"^id\s*:\s*[\"']?([^\"'#]+)", raw)
                        if match:
                            names.add(match.group(1).strip().lower())
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
                        "~/.config/daisy/slide-themes/; Daisy falls back to `default`")
    if "font_size" in settings and not FONT_SIZE.fullmatch(settings["font_size"]):
        report.error(1, f"font_size `{settings['font_size']}` isn't a percentage (`120%`) or pixels (`36`); "
                        "Daisy ignores it")
    if "paginate" in settings and settings["paginate"].lower() not in ("true", "false"):
        report.warn(1, "paginate should be `true` or `false`")


def check_directive(key, value, line, report, in_list):
    if key in DIRECTIVES:
        if in_list and key in ("column", "end-columns", "space"):
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


def check_comment(text, line, report, in_list):
    for raw in text.splitlines() or [text]:
        raw = raw.strip()
        if not raw:
            continue
        key, _, value = raw.partition(":")
        check_directive(key.strip().lower(), value.strip().strip("\"'"), line, report, in_list)


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
    for index, (line_no, raw) in enumerate(lines):
        if FENCE.match(raw):
            if in_code and code_lines > MAX_CODE_LINES and not scales:
                report.warn(code_start, f"slide {number}: a {code_lines}-line code block will likely be cut off")
            if not in_code:
                scales = raw.strip().lstrip("`~").strip().lower().startswith(SCALING_FENCES)
            in_code, code_lines, code_start = not in_code, 0, line_no
            add()
            continue
        if in_code:
            code_lines += 1
            add(0 if scales else 1)
            continue
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
                    if key == "column" and not in_list and place != "after":
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
