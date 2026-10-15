#!/usr/bin/env python3
"""Add or remove a release in a Sparkle appcast.xml.

Used by release.sh and rollback-release.sh so the appcast can live on
GitHub Pages without keeping every old DMG around for generate_appcast.

  appcast.py add    FEED --version V --build N --url URL --length BYTES \
                        --signature SIG --min-os 15.0 --notes-file FILE \
                        [--beta] [--title T] [--feed-title T] [--feed-link URL]
  appcast.py remove FEED --version V
"""
import argparse
import html
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)


def sp(name):
    return f"{{{SPARKLE}}}{name}"


def notes_to_html(notes):
    """Render the small Markdown subset used in CHANGELOG.md entries."""
    def inline(text):
        text = html.escape(text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        return re.sub(r"`(.+?)`", r"<code>\1</code>", text)

    out, in_list = [], False
    for line in notes.splitlines():
        stripped = line.strip()
        if stripped.startswith(("- ", "* ")):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(stripped[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if stripped.startswith("#"):
            out.append(f"<h4>{inline(stripped.lstrip('# '))}</h4>")
        elif stripped:
            out.append(f"<p>{inline(stripped)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def load(path, title, link):
    try:
        tree = ET.parse(path)
        return tree, tree.getroot().find("channel")
    except (FileNotFoundError, ET.ParseError):
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = title
        ET.SubElement(channel, "link").text = link
        ET.SubElement(channel, "description").text = f"Most recent changes to {title}"
        ET.SubElement(channel, "language").text = "en"
        return ET.ElementTree(root), channel


def item_version(item):
    node = item.find(sp("shortVersionString"))
    return node.text if node is not None else None


def write(tree, path):
    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


def add(args):
    tree, channel = load(args.feed, args.feed_title, args.feed_link)
    for old in [i for i in channel.findall("item") if item_version(i) == args.version]:
        channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.title or f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, sp("version")).text = args.build
    ET.SubElement(item, sp("shortVersionString")).text = args.version
    ET.SubElement(item, sp("minimumSystemVersion")).text = args.min_os
    if args.beta:
        ET.SubElement(item, sp("channel")).text = "beta"
    with open(args.notes_file, encoding="utf-8") as handle:
        ET.SubElement(item, "description").text = notes_to_html(handle.read())
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": args.length,
        "type": "application/octet-stream",
        sp("edSignature"): args.signature,
    })

    # Newest first: insert before the first existing <item>.
    children = list(channel)
    first = next((i for i, child in enumerate(children) if child.tag == "item"), len(children))
    channel.insert(first, item)
    write(tree, args.feed)


def remove(args):
    tree, channel = load(args.feed, "", "")
    matches = [i for i in channel.findall("item") if item_version(i) == args.version]
    if not matches:
        print(f"no appcast item for {args.version}", file=sys.stderr)
        return 1
    for item in matches:
        channel.remove(item)
    write(tree, args.feed)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    a = sub.add_parser("add")
    a.add_argument("feed")
    a.add_argument("--version", required=True)
    a.add_argument("--build", required=True)
    a.add_argument("--url", required=True)
    a.add_argument("--length", required=True)
    a.add_argument("--signature", required=True)
    a.add_argument("--min-os", required=True)
    a.add_argument("--notes-file", required=True)
    a.add_argument("--beta", action="store_true")
    a.add_argument("--title")
    a.add_argument("--feed-title", default="Daisy")
    a.add_argument("--feed-link", default="")

    r = sub.add_parser("remove")
    r.add_argument("feed")
    r.add_argument("--version", required=True)

    args = parser.parse_args()
    sys.exit(add(args) or 0 if args.command == "add" else remove(args))


if __name__ == "__main__":
    main()
