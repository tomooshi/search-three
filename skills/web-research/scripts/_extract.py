#!/usr/bin/env python3
"""HTML -> {title, markdown} JSON. Reads HTML on stdin, prints JSON on stdout.

Shared by fetch-page.sh fallback rungs (curl / playwright / wayback).
Pragmatic bs4 conversion: not trafilatura-quality, but preserves headings,
links, lists, and code blocks, and strips chrome (nav/footer/scripts/etc.).
"""
import json
import re
import sys

try:
    from bs4 import BeautifulSoup, NavigableString, Tag
except ImportError:
    sys.exit("beautifulsoup4 not installed (pip install beautifulsoup4, "
             "or point FETCH_PYTHON at a python that has it)")

STRIP = {"script", "style", "noscript", "template", "svg", "iframe", "form",
         "nav", "header", "footer", "aside", "button", "select", "input"}
BLOCK = {"p", "div", "section", "article", "main", "blockquote", "tr",
         "table", "ul", "ol", "figure", "figcaption", "dl", "dt", "dd"}


def render(node, out, depth=0):
    if isinstance(node, NavigableString):
        text = re.sub(r"\s+", " ", str(node))
        if text.strip():
            out.append(text)
        return
    if not isinstance(node, Tag) or node.name in STRIP:
        return
    name = node.name
    if name in ("h1", "h2", "h3", "h4", "h5", "h6"):
        out.append("\n\n" + "#" * int(name[1]) + " ")
        for child in node.children:
            render(child, out, depth)
        out.append("\n\n")
    elif name == "a" and node.get("href", "").startswith("http"):
        label = re.sub(r"\s+", " ", node.get_text()).strip()
        if label:
            out.append(f"[{label}]({node['href']})")
    elif name == "li":
        out.append("\n" + "  " * depth + "- ")
        for child in node.children:
            render(child, out, depth + 1)
    elif name == "pre":
        out.append("\n\n```\n" + node.get_text().strip("\n") + "\n```\n\n")
    elif name == "code":
        text = node.get_text()
        out.append(f"`{text}`" if "\n" not in text else text)
    elif name == "br":
        out.append("\n")
    elif name in ("img",):
        alt = node.get("alt", "").strip()
        if alt:
            out.append(f"[img: {alt}]")
    else:
        if name in BLOCK:
            out.append("\n\n")
        for child in node.children:
            render(child, out, depth)
        if name in BLOCK:
            out.append("\n\n")


def main():
    html = sys.stdin.read()
    soup = BeautifulSoup(html, "html.parser")
    title = (soup.title.get_text().strip() if soup.title else "")
    root = soup.find("main") or soup.find("article") or soup.body or soup
    out = []
    render(root, out)
    markdown = "".join(out)
    markdown = re.sub(r"[ \t]+\n", "\n", markdown)
    markdown = re.sub(r"\n{3,}", "\n\n", markdown).strip()
    print(json.dumps({"title": title, "markdown": markdown}))


if __name__ == "__main__":
    main()
