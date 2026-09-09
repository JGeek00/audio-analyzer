#!/usr/bin/env python3
"""Insert a new release <item> at the top of appcast.xml and sign the feed.

Uses Sparkle's `sign_update` for EdDSA signatures. Stdlib only.

Usage:
    scripts/update-appcast.py --dmg dist/AudioAnalyzer-1.1.0.dmg \\
        --version 1.1.0 --build 1 --notes-html notes.html \\
        --url https://github.com/JGeek00/audio-analyzer/releases/download/v1.1.0/AudioAnalyzer-1.1.0.dmg \\
        --appcast appcast.xml --sign-update /path/to/sign_update --key-file /path/to/key
"""
# ponytail: string-built item + minidom for CDATA. A feed library would be nicer when deltas/channels are needed.

import argparse
import os
import re
import subprocess
import sys
from email.utils import formatdate
from xml.dom import minidom

CHANNEL_SKELETON = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Audio Analyzer Updates</title>
    <link>https://github.com/JGeek00/audio-analyzer/releases</link>
    <description>Audio Analyzer for macOS</description>
    <language>en</language>
  </channel>
</rss>
"""

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"error: {' '.join(cmd)} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def sign_dmg(sign_update, key_args, dmg):
    out = run([sign_update, *key_args, "-p", dmg])
    signature = out.strip().splitlines()[-1]
    if not signature or " " in signature:
        print(f"error: unexpected sign_update output: {out!r}", file=sys.stderr)
        sys.exit(1)
    return signature


def load_or_create(appcast_path):
    if os.path.exists(appcast_path):
        return minidom.parse(appcast_path)
    doc = minidom.parseString(CHANNEL_SKELETON)
    with open(appcast_path, "w", encoding="utf-8") as f:
        f.write(CHANNEL_SKELETON)
    return doc


def existing_versions(doc):
    versions = set()
    for item in doc.getElementsByTagName("item"):
        for node in item.getElementsByTagName("sparkle:shortVersionString"):
            if node.firstChild:
                versions.add(node.firstChild.data.strip())
    return versions


def append_text(doc, parent, tag, text):
    element = doc.createElement(tag)
    element.appendChild(doc.createTextNode(text))
    parent.appendChild(element)
    return element


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dmg", required=True)
    parser.add_argument("--version", required=True, help="X.Y.Z")
    parser.add_argument("--build", required=True, help="monotonic integer (sparkle:version)")
    parser.add_argument("--notes-html", required=True, help="release notes as HTML file")
    parser.add_argument("--url", required=True, help="download URL of the DMG")
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--sign-update", required=True)
    key_group = parser.add_mutually_exclusive_group(required=True)
    key_group.add_argument("--key-file", help="private EdDSA key file")
    key_group.add_argument("--key-account", help="keychain account holding the private key")
    args = parser.parse_args()

    if not VERSION_RE.match(args.version):
        print(f"error: version must be X.Y.Z, got {args.version!r}", file=sys.stderr)
        sys.exit(1)
    if not args.build.isdigit():
        print(f"error: build must be an integer, got {args.build!r}", file=sys.stderr)
        sys.exit(1)
    for path in (args.dmg, args.notes_html):
        if not os.path.isfile(path):
            print(f"error: no such file: {path}", file=sys.stderr)
            sys.exit(1)

    key_args = ["-f", args.key_file] if args.key_file else ["--account", args.key_account]

    doc = load_or_create(args.appcast)
    if args.version in existing_versions(doc):
        print(f"error: version {args.version} already in {args.appcast}", file=sys.stderr)
        sys.exit(1)

    with open(args.notes_html, encoding="utf-8") as f:
        notes_html = f.read()
    length = os.path.getsize(args.dmg)
    signature = sign_dmg(args.sign_update, key_args, args.dmg)

    channel = doc.getElementsByTagName("channel")[0]
    item = doc.createElement("item")
    append_text(doc, item, "title", f"Version {args.version}")
    append_text(doc, item, "sparkle:version", args.build)
    append_text(doc, item, "sparkle:shortVersionString", args.version)
    append_text(doc, item, "pubDate", formatdate(usegmt=True))
    description = doc.createElement("description")
    description.appendChild(doc.createCDATASection(notes_html))
    item.appendChild(description)
    enclosure = doc.createElement("enclosure")
    enclosure.setAttribute("url", args.url)
    enclosure.setAttribute("length", str(length))
    enclosure.setAttribute("type", "application/octet-stream")
    enclosure.setAttribute("sparkle:version", args.build)
    enclosure.setAttribute("sparkle:shortVersionString", args.version)
    enclosure.setAttribute("sparkle:edSignature", signature)
    item.appendChild(enclosure)
    append_text(
        doc,
        item,
        "link",
        f"https://github.com/JGeek00/audio-analyzer/releases/tag/v{args.version}",
    )

    items = channel.getElementsByTagName("item")
    if items:
        channel.insertBefore(item, items[0])
    else:
        channel.appendChild(item)

    with open(args.appcast, "w", encoding="utf-8") as f:
        doc.writexml(f, encoding="utf-8", newl="\n", addindent="  ")

    # Embed the feed signature; must run last, after any feed edit.
    run([args.sign_update, *key_args, args.appcast])

    print(f"appcast updated: version={args.version} build={args.build} length={length}")
    print(f"edSignature={signature[:16]}…")


if __name__ == "__main__":
    main()
