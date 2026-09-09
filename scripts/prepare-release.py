#!/usr/bin/env python3
"""Resolve and validate the next release version. Stdlib only.

Reads MARKETING_VERSION from the Xcode project (single source of truth),
compares it against published git tags and appcast.xml, and prints the
version and next build number. Exits non-zero with a message if the project
version is not strictly greater than everything published.

Usage:
    eval $(scripts/prepare-release.py)   # sets NEXT_VERSION and NEXT_BUILD
"""
# ponytail: regex over pbxproj is enough; xcodebuild -showBuildSettings when full resolution is needed.

import re
import subprocess
import sys
import xml.etree.ElementTree as ET

PBXPROJ = "Audio Analyzer.xcodeproj/project.pbxproj"
APPCAST = "appcast.xml"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def parse_tuple(version):
    return tuple(int(p) for p in version.split("."))


def main():
    with open(PBXPROJ, encoding="utf-8") as f:
        pbxproj = f.read()
    marketing = set(re.findall(r"MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+);", pbxproj))
    if len(marketing) != 1:
        fail(f"MARKETING_VERSION must be identical in all configs, found: {sorted(marketing)}")
    new = marketing.pop()
    project_builds = [int(b) for b in re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbxproj)]
    if not project_builds:
        fail("CURRENT_PROJECT_VERSION not found in project")

    tags = subprocess.run(
        ["git", "tag", "--list", "v*"], capture_output=True, text=True, check=True
    ).stdout.split()
    tag_versions = [t[1:] for t in tags if re.fullmatch(r"v\d+\.\d+\.\d+", t)]

    feed_versions, feed_builds = [], []
    try:
        root = ET.parse(APPCAST).getroot()
        for item in root.iter("item"):
            short = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
            build = item.find(f"{{{SPARKLE_NS}}}version")
            if short is not None and short.text:
                feed_versions.append(short.text.strip())
            if build is not None and build.text and build.text.strip().isdigit():
                feed_builds.append(int(build.text.strip()))
    except FileNotFoundError:
        pass

    new_tuple = parse_tuple(new)
    for published in tag_versions + feed_versions:
        if new_tuple <= parse_tuple(published):
            fail(
                f"MARKETING_VERSION ({new}) is not newer than published {published}; "
                "bump it in Xcode first"
            )

    if subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"v{new}"],
        capture_output=True,
    ).returncode == 0:
        fail(f"tag v{new} already exists")

    # Release builds always exceed any local build from the same source.
    build = max(feed_builds + project_builds) + 1
    print(f"NEXT_VERSION={new}")
    print(f"NEXT_BUILD={build}")


if __name__ == "__main__":
    main()
