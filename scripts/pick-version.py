#!/usr/bin/env python3
r"""Pick the newest version a manifest should be updated to.

Reads the response of a version source on stdin and prints the version on
stdout (nothing when there is no match). Used by
.gitea/workflows/auto-update.yml, which fetches the source with curl and hands
the body over.

Usage:
    pick-version.py [--tags|--text] <regex>

Modes:
    --tags  (default) The stdin is a GitHub releases list (JSON). The version
            is taken from the newest release whose tag the regex matches.
            Drafts are ignored; a prerelease is used only when the repository
            has no stable release at all. Without a regex the tag itself is
            the version, but only when it looks like one -- a rolling "latest"
            tag is skipped instead of becoming a version.
    --text  The stdin is a raw body (the response of checkver.url). The regex
            is applied to the body; the capture group is the version, the whole
            match when the regex has no group. When the regex matches several
            times, the HIGHEST version among the matches is taken: a list of
            refs is not ordered by version, and the first one is not always
            the newest (v0.1.9 sorts before v0.1.10).

The regex follows the Scoop checkver convention: it is applied to the release
TAG, its capture group holds the version, and it is .NET-flavoured (\d and
friends), which is why python's re is used instead of grep -E.
"""

import argparse
import json
import re
import sys

VERSION_LIKE = re.compile(r"^v?\d")


def _strip_v(version):
    """Normalise a tag to the bare version the manifests use."""
    return version[1:] if version.startswith("v") else version


def _from_tag(tag, regex):
    if regex:
        match = re.search(regex, tag)
        if not match:
            return ""
        # The capture group is the version, the whole match when there is none.
        return match.group(1) if match.groups() else match.group(0)
    # Without a regex the tag is the version -- but only when it looks like
    # one, so a rolling "latest" tag is skipped instead of becoming one.
    return tag if VERSION_LIKE.match(tag) else ""


def pick_from_releases(releases, regex):
    candidates = []
    for release in releases:
        if release.get("draft"):
            continue
        version = _from_tag(release.get("tag_name") or "", regex)
        if version:
            candidates.append((bool(release.get("prerelease")), version))

    stable = [version for prerelease, version in candidates if not prerelease]
    if stable:
        return _strip_v(stable[0])
    if candidates:
        return _strip_v(candidates[0][1])
    return ""


def _version_key(version):
    """Sort key that compares version parts as numbers, not as text."""
    parts = re.findall(r"\d+|\D+", version)
    return tuple((1, int(part)) if part.isdigit() else (0, part) for part in parts)


def pick_from_text(body, regex):
    if not regex:
        return ""
    found = [
        _strip_v(match.group(1) if match.groups() else match.group(0))
        for match in re.finditer(regex, body)
    ]
    versions = [version for version in found if VERSION_LIKE.match(version)]
    if not versions:
        return ""
    # The highest version, not the first match: the order of a list of refs
    # follows the git ref listing, not the version order.
    return max(versions, key=_version_key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tags", action="store_true", help="stdin is a GitHub releases list")
    parser.add_argument("--text", action="store_true", help="stdin is a raw body")
    parser.add_argument("regex", nargs="?", default="", help="checkver.regex (may be empty)")
    args = parser.parse_args()

    body = sys.stdin.read()
    try:
        if args.text:
            version = pick_from_text(body, args.regex)
        else:
            version = pick_from_releases(json.loads(body), args.regex)
    except (ValueError, TypeError, AttributeError) as error:
        print(f"pick-version: {error}", file=sys.stderr)
        return 1

    if version:
        print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
