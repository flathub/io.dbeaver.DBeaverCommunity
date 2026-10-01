#!/usr/bin/env python3
"""Fill empty <release> descriptions in the appdata from upstream GitHub release notes.

Usage:
  release_notes.py APPDATA         fill every release with an empty description (needs `gh`)
  release_notes.py APPDATA --check self-check: converter output for 26.0.3 must contain
                                   the same items as the hand-written entry
"""
import re
import subprocess
import sys
from html import escape

REPO = "dbeaver/dbeaver"
EMPTY = re.compile(
    r'(?P<head><release version="(?P<ver>[^"]+)"[^>]*>)\s*(?:<description\s*/>|<description>\s*</description>)'
    r'(?P<url>\s*<url>[^<]*</url>)?'
)


def fetch(ver):
    return subprocess.run(
        ["gh", "release", "view", ver, "-R", REPO, "--json", "body", "--jq", ".body"],
        check=True, capture_output=True, text=True,
    ).stdout


def parse(body):
    """Indented markdown bullets -> list of [text, children] trees; plain lines are leaves with children=None."""
    root = []
    stack = [(-1, root)]
    for raw in body.expandtabs(4).splitlines():
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip())
        m = re.match(r"[-*]\s+(.*)", raw.strip())
        if not m:
            root.append([raw.strip(), None])
            stack = [(-1, root)]
            continue
        while stack[-1][0] >= indent:
            stack.pop()
        node = [m.group(1).strip(), []]
        stack[-1][1].append(node)
        stack.append((indent, node[1]))
    return root


def render(items, out):
    # AppStream forbids nested lists: every bullet with children becomes a <p> heading.
    for text, children in items:
        t = escape(text, quote=False)
        if children is None:
            out.append(f"<p>{t}</p>")
        elif any(c[1] for c in children):
            out.append(f"<p>{t.rstrip(':')}</p>")
            render(children, out)
        elif children:
            out += [f"<p>{t}</p>", "<ul>"]
            out += [f"    <li>{escape(c[0], quote=False)}</li>" for c in children]
            out.append("</ul>")
        elif ": " in text:
            head, rest = text.split(": ", 1)
            out += [f"<p>{escape(head, quote=False)}:</p>", "<ul>", f"    <li>{escape(rest, quote=False)}</li>", "</ul>"]
        else:
            out += ["<ul>", f"    <li>{t}</li>", "</ul>"]
    return out


def description(body, indent=" " * 12):
    lines = render(parse(body), [])
    inner = "\n".join(indent + "    " + line for line in lines)
    return f"{indent}<description>\n{inner}\n{indent}</description>"


def fill(xml):
    def sub(m):
        ver = m["ver"]
        body = fetch(ver)
        if not body.strip():
            print(f"{ver}: upstream release notes empty, skipped", file=sys.stderr)
            return m[0]
        print(f"{ver}: filled", file=sys.stderr)
        return (f'{m["head"]}\n{description(body)}\n'
                f"            <url>https://github.com/{REPO}/releases/tag/{ver}</url>")
    return EMPTY.sub(sub, xml)


def items(xml_fragment):
    return {re.sub(r"\s+", " ", li).strip() for li in re.findall(r"<li>(.*?)</li>", xml_fragment, re.S)}


def check(xml):
    ver = "26.0.3"
    existing = re.search(rf'<release version="{ver}".*?</release>', xml, re.S)[0]
    got = description(fetch(ver))
    assert items(got) == items(existing), (items(got) ^ items(existing))
    assert re.search(r"<li>[^<]*<(ul|p)", got) is None  # no nesting
    print("ok")


if __name__ == "__main__":
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        xml = f.read()
    if "--check" in sys.argv:
        check(xml)
    else:
        new = fill(xml)
        if new != xml:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)
