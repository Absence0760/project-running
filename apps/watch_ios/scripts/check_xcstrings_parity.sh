#!/usr/bin/env bash
# Parity check for the watchOS String Catalog. Runs WITHOUT Xcode — pure
# JSON/text parse — so CI on Linux (or a quick local sanity check) can catch a
# missing or empty translation before a Mac ever builds the app.
#
# Three claims, in order:
#
#   1. The shipped locale set is DERIVED from the catalog, not restated here.
#      A hand-written list is a second place a locale has to be added, and the
#      one the loop below reads: a seventh locale added to the entries and
#      missed in the list would be skipped by the check that exists to see it.
#      That shape was found six times on the web/wrist side (decisions § 748 /
#      § 755) and once more here (§ 761). The set is every locale any entry
#      declares; an entry short of it is what fails.
#   2. Every entry carries a non-empty translation for every locale in that
#      set. The source language (en) may be implicit — the key itself is the
#      value — so en passes when no "en" localization is present. ja is exempt
#      from the plural "one" category (Japanese has no singular/plural
#      distinction; the catalog only declares "other" for ja plural entries).
#   3. Info.plist's CFBundleLocalizations and the Xcode project's
#      knownRegions declare exactly that set. A translated string the bundle
#      does not declare is never loaded at runtime: the app silently shows
#      English and nothing fails, which is precisely how a half-declared
#      locale ships.
#
# CI: the `watch-ios-locale-parity` job in .github/workflows/ci.yml.
# Referenced from apps/watch_ios/CLAUDE.md.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$DIR" <<'PY'
import json, re, sys, pathlib

root = pathlib.Path(sys.argv[1])
catalog = root / "WatchApp" / "Localizable.xcstrings"
plist = root / "WatchApp" / "Info.plist"
pbxproj = root / "WatchApp.xcodeproj" / "project.pbxproj"

# Locales with no singular form — plural "one" is not required.
NO_SINGULAR = {"ja"}

cat = json.loads(catalog.read_text(encoding="utf-8"))
source = cat.get("sourceLanguage", "en")
strings = cat.get("strings", {})
errors = []

if not strings:
    print(f"FAIL: no string entries parsed from {catalog}", file=sys.stderr)
    sys.exit(1)

# (1) Derive the set. The source language is always shipped even when every
# entry leaves it implicit, so it is in the set by construction.
locales = {source}
for entry in strings.values():
    locales.update(entry.get("localizations", {}))
LOCALES = sorted(locales)


def unit_ok(unit):
    return bool(unit.get("value", "").strip())


def check_localization(key, loc, block):
    # A localization is either a plain stringUnit or a variations/plural block.
    if "stringUnit" in block:
        if not unit_ok(block["stringUnit"]):
            errors.append(f"[{key}] {loc}: empty value")
        return
    variations = block.get("variations", {})
    plural = variations.get("plural")
    if plural is None:
        errors.append(f"[{key}] {loc}: no stringUnit and no plural variations")
        return
    required = ["other"] if loc in NO_SINGULAR else ["one", "other"]
    for cat_name in required:
        cat_block = plural.get(cat_name)
        if cat_block is None or "stringUnit" not in cat_block or not unit_ok(cat_block["stringUnit"]):
            errors.append(f"[{key}] {loc}: missing/empty plural '{cat_name}'")


# (2) Every entry covers every derived locale.
for key, entry in strings.items():
    locs = entry.get("localizations", {})
    for loc in LOCALES:
        if loc not in locs:
            # Source language may be implicit (key == value).
            if loc == source:
                continue
            errors.append(f"[{key}] {loc}: missing translation")
            continue
        check_localization(key, loc, locs[loc])

# (3) Both declaration sites agree with the derived set. Neither is parsed
# with a real plist/pbxproj reader on purpose: this has to run under a bare
# python3 on a Linux runner with nothing installed.
plist_text = plist.read_text(encoding="utf-8")
block = re.search(
    r"<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>",
    plist_text,
    re.S,
)
if block is None:
    errors.append("Info.plist declares no CFBundleLocalizations array")
else:
    declared = sorted(re.findall(r"<string>([^<]+)</string>", block.group(1)))
    if declared != LOCALES:
        errors.append(
            f"Info.plist CFBundleLocalizations is {declared}, catalog ships {LOCALES}"
        )

pbx_text = pbxproj.read_text(encoding="utf-8")
block = re.search(r"knownRegions = \((.*?)\);", pbx_text, re.S)
if block is None:
    errors.append("project.pbxproj declares no knownRegions")
else:
    regions = [r.strip().strip('",') for r in block.group(1).split("\n")]
    # `Base` is Xcode's own development-region marker, not a shipped locale.
    regions = sorted(r for r in regions if r and r != "Base")
    if regions != LOCALES:
        errors.append(
            f"project.pbxproj knownRegions is {regions}, catalog ships {LOCALES}"
        )

count = len(strings)
if errors:
    print(f"FAIL: {len(errors)} problem(s) across {count} string(s):", file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    sys.exit(1)

print(
    f"OK: {count} string(s) each translated for {', '.join(LOCALES)}; "
    "Info.plist and knownRegions declare the same set"
)
PY
