#!/usr/bin/env python3
"""Vendor the guide pages of the Incursion wiki into the app's help window.

    Usage: tools/fetch_wiki_help.py            refresh every page
           tools/fetch_wiki_help.py --check    fail if a vendored page is stale
           tools/fetch_wiki_help.py <slug>...  refresh only these pages

    WHAT THIS TAKES, AND WHAT IT DOES NOT. The wiki holds two kinds of page.
One kind restates the game's own data -- every monster, every spell, every
item. The app does not take those: it generates that reference from the
module the player is actually running (`incursion -exporthelp`), so a wiki
copy could only ever be a second, staler answer to the same question. The
other kind is the writing the game has none of -- how to start, what to do
first, what kills new characters, which spells are worth a slot. That is
what PAGES below lists, and it is chosen for that reason.

    LICENSING. Wiki content is licensed CC BY-SA 3.0, as the footer of every
page states. Two obligations follow and both are met in machine-checkable
form. Attribution: each vendored file carries the page title, its URL, the
retrieval date and the licence, and the help window prints that under the
text where a reader sees it, not in a credits file nobody opens. ShareAlike:
the vendored files stay CC BY-SA 3.0 and say so; they are separate documents
that the app displays, not code mixed into the MIT-licensed engine, so the
project's own licence is unaffected. See docs/HELP-SYSTEM.md.

    The conversion is HTML to Markdown and nothing else -- no rewriting, no
summarising, no reordering. That matters for the licence (a derivative must
say what was changed) and for the reader (a guide edited by a third party is
no longer the guide the wiki vouches for).
"""

import datetime
import os
import re
import sys
import urllib.request
from html.parser import HTMLParser

BASE = "http://incursion.wikidot.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "macapp", "Resources", "Help", "wiki")

LICENSE = "CC BY-SA 3.0"
LICENSE_URL = "https://creativecommons.org/licenses/by-sa/3.0/"
ATTRIBUTION = "Incursion Wiki contributors"

# slug, title shown in the sidebar, sidebar order.
# Deliberately NOT here: "start" and "strategy-guide". Both looked promising
# and both turned out to be link indexes -- the wiki's own navigation, plus
# pointers to guides hosted elsewhere. Vendored, they would be a page of dead
# ends in an app that may be offline. The help window links to the wiki itself
# instead.
PAGES = [
    ("general-tips-for-survival",    "General Tips for Survival",    20),
    ("faq",                          "Frequently Asked Questions",   30),
    ("known-issues-and-workarounds", "Known Issues and Workarounds", 40),
    ("constant-dungeon-features",    "Constant Dungeon Features",    50),
    ("arcane-spell-guide-and-review", "Arcane Spell Guide",          60),
]

SKIP_CLASSES = {
    "page-tags", "page-options-bottom", "page-info", "footer",
    "licensetext", "wd-editor-toolbar-panel", "comments-box",
}


class ContentSlicer(HTMLParser):
    """Return the innards of <div id="page-content">, balanced by depth.

    A regex cannot do this: the block contains nested divs, and the naive
    non-greedy match stops at the first </div> -- which is how the first
    attempt at this silently produced empty pages.
    """

    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.depth = None
        self.parts = []

    def done(self):
        """True once the block has closed. Everything after it is the page's
        furniture -- the sidebar, the footer -- and taking it produced pages
        that were nothing but the site's own navigation."""
        return self.depth is not None and self.depth < 0

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if self.done():
            return
        if self.depth is None:
            if tag == "div" and d.get("id") == "page-content":
                self.depth = 0
            return
        if tag == "div":
            self.depth += 1
        self.parts.append(self.get_starttag_text())

    def handle_startendtag(self, tag, attrs):
        if self.depth is not None and not self.done():
            self.parts.append(self.get_starttag_text())

    def handle_endtag(self, tag):
        if self.depth is None or self.done():
            return
        if tag == "div":
            if self.depth == 0:
                self.depth = -1  # done; ignore everything after
                return
            self.depth -= 1
        if self.depth >= 0:
            self.parts.append("</%s>" % tag)

    def handle_data(self, data):
        if self.depth is not None and self.depth >= 0:
            self.parts.append(data)

    def handle_entityref(self, name):
        self.handle_data("&%s;" % name)

    def handle_charref(self, name):
        self.handle_data("&#%s;" % name)


class Markdownifier(HTMLParser):
    """HTML to Markdown for the subset wikidot actually emits."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.list_stack = []       # 'ul' or ['ol', n]
        self.link = None
        self.skip_depth = 0
        self.in_pre = False
        self.row = None            # cells of the table row being built
        self.cell = None
        self.table_rows = None
        self.header_done = False

    # -- helpers ---------------------------------------------------------
    def emit(self, s):
        if self.skip_depth:
            return
        if self.cell is not None:
            self.cell.append(s)
        else:
            self.out.append(s)

    def block(self, s=""):
        self.emit("\n" + s)

    def text(self):
        t = "".join(self.out)
        # Wikidot's page furniture leaves two kinds of empty shell behind: a
        # link with no text (an anchor) and a table with no cells (a layout
        # rule). Both render as visible rubbish and neither carries meaning.
        t = re.sub(r"\[\]\([^)]*\)", "", t)
        # "Back to top" links belong to a long scrolling web page, not to a
        # window with a sidebar; other in-page anchors keep their text and
        # lose the link, which would go nowhere here.
        t = re.sub(r"\[\^?[^\]]*back to top[^\]]*\]\(#[^)]*\)", "", t, flags=re.I)
        t = re.sub(r"\[([^\]]*)\]\(#[^)]*\)", r"\1", t)
        t = re.sub(r"^\|[ |]*\|$\n(^\|[ -|]*\|$\n?)?", "", t, flags=re.M)
        t = re.sub(r"[ \t]+\n", "\n", t)
        t = re.sub(r"\n{3,}", "\n\n", t)
        return t.strip() + "\n"

    # -- tags ------------------------------------------------------------
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        cls = set((d.get("class") or "").split())
        if self.skip_depth or cls & SKIP_CLASSES or d.get("id") == "toc":
            self.skip_depth += 1
            return
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.block("\n" + "#" * int(tag[1]) + " ")
        elif tag == "p":
            self.block("\n")
        elif tag in ("ul", "ol"):
            self.list_stack.append([tag, 0])
            self.block()
        elif tag == "li":
            if self.list_stack:
                kind = self.list_stack[-1]
                indent = "  " * (len(self.list_stack) - 1)
                if kind[0] == "ol":
                    kind[1] += 1
                    self.emit("\n%s%d. " % (indent, kind[1]))
                else:
                    self.emit("\n%s- " % indent)
        elif tag in ("strong", "b"):
            self.emit("**")
        elif tag in ("em", "i"):
            self.emit("*")
        elif tag in ("code", "tt"):
            self.emit("`")
        elif tag == "pre":
            self.in_pre = True
            self.block("\n```\n")
        elif tag == "br":
            self.emit("  \n")
        elif tag == "hr":
            self.block("\n---\n")
        elif tag == "blockquote":
            self.block("\n> ")
        elif tag == "a":
            href = d.get("href", "")
            if href.startswith("javascript:") or "toc" in cls:
                self.skip_depth += 1
                return
            self.link = href
            self.emit("[")
        elif tag == "table":
            self.table_rows = []
            self.header_done = False
            self.block()
        elif tag == "tr" and self.table_rows is not None:
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.cell = []
        elif tag == "img":
            alt = d.get("alt") or "image"
            self.emit("(%s)" % alt)

    def handle_endtag(self, tag):
        if self.skip_depth:
            self.skip_depth -= 1
            return
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6", "p", "blockquote"):
            self.block()
        elif tag in ("ul", "ol"):
            if self.list_stack:
                self.list_stack.pop()
            self.block()
        elif tag in ("strong", "b"):
            self.emit("**")
        elif tag in ("em", "i"):
            self.emit("*")
        elif tag in ("code", "tt"):
            self.emit("`")
        elif tag == "pre":
            self.in_pre = False
            self.block("\n```\n")
        elif tag == "a" and self.link is not None:
            href = self.link or ""
            self.link = None
            if href.startswith("/"):
                href = BASE + href
            self.emit("](%s)" % href)
        elif tag in ("td", "th") and self.cell is not None:
            cell = " ".join("".join(self.cell).split())
            self.cell = None
            if self.row is not None:
                self.row.append(cell)
            elif cell:
                self.emit(cell)
        elif tag == "tr" and self.row is not None:
            self.table_rows.append(self.row)
            self.row = None
        elif tag == "table" and self.table_rows is not None:
            rows, self.table_rows = self.table_rows, None
            if rows:
                width = max(len(r) for r in rows)
                self.block()
                for n, r in enumerate(rows):
                    r = r + [""] * (width - len(r))
                    self.emit("\n| " + " | ".join(r) + " |")
                    if n == 0:
                        self.emit("\n|" + "|".join([" --- "] * width) + "|")
                self.block()

    def handle_data(self, data):
        if self.skip_depth:
            return
        if self.in_pre:
            self.emit(data)
            return
        data = data.replace("\r", " ").replace("\n", " ")
        if not data.strip() and self.out and self.out[-1].endswith((" ", "\n")):
            return
        self.emit(data)


def fetch(slug):
    url = "%s/%s" % (BASE, slug)
    req = urllib.request.Request(url, headers={"User-Agent": "incursion-help-vendor/1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read().decode("utf-8", "replace")
    slicer = ContentSlicer()
    slicer.feed(raw)
    body = "".join(slicer.parts)
    if not body.strip():
        raise SystemExit("no page-content in %s -- the wiki's markup changed" % url)
    md = Markdownifier()
    md.feed(body)
    return url, md.text()


def render(slug, title, order, url, body, retrieved):
    front = [
        "---",
        "title: %s" % title,
        "slug: %s" % slug,
        "order: %d" % order,
        "source: %s" % url,
        "attribution: %s" % ATTRIBUTION,
        "license: %s" % LICENSE,
        "license_url: %s" % LICENSE_URL,
        "retrieved: %s" % retrieved,
        "modifications: converted from the page's HTML to Markdown; text unchanged",
        "---",
        "",
    ]
    return "\n".join(front) + body


def existing_retrieved(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("retrieved: "):
                return line.split(": ", 1)[1].strip()
    return None


def main(argv):
    check = "--check" in argv
    wanted = [a for a in argv if not a.startswith("--")]
    os.makedirs(OUT, exist_ok=True)
    today = datetime.date.today().isoformat()
    failed = 0
    for slug, title, order in PAGES:
        if wanted and slug not in wanted:
            continue
        path = os.path.join(OUT, slug + ".md")
        if check:
            # Compare the live page against what is vendored, ignoring the
            # retrieval date -- that changes on every run and would report a
            # difference where there is none.
            url, body = fetch(slug)
            new = render(slug, title, order, url, body, existing_retrieved(path) or today)
            old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
            if new != old:
                print("STALE: %s differs from %s" % (path, url))
                failed += 1
            else:
                print("ok:    %s" % slug)
            continue
        url, body = fetch(slug)
        with open(path, "w", encoding="utf-8") as f:
            f.write(render(slug, title, order, url, body, today))
        print("wrote %s (%d bytes)" % (path, len(body)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
