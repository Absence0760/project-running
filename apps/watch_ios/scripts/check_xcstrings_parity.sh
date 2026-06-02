#!/usr/bin/env bash
# Parity check for the watchOS String Catalog. Runs WITHOUT Xcode — pure
# JSON parse — so CI on Linux (or a quick local sanity check) can catch a
# missing or empty translation before a Mac ever builds the app.
#
# Asserts every string entry in Localizable.xcstrings carries a non-empty
# translation for all six shipped locales (en + de/fr/es/ja/pt-BR). The
# source language (en) may be implicit — the key itself is the value — so
# en passes when no "en" localization is present. ja is exempt from the
# plural "one" category (Japanese has no singular/plural distinction; the
# catalog only declares "other" for ja plural entries).
#
# Referenced from apps/watch_ios/CLAUDE.md.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$DIR/WatchApp/Localizable.xcstrings"

python3 - "$CATALOG" <<'PY'
import json, sys

path = sys.argv[1]
LOCALES = ["en", "de", "fr", "es", "ja", "pt-BR"]
# Locales with no singular form — plural "one" is not required.
NO_SINGULAR = {"ja"}

with open(path, encoding="utf-8") as f:
    cat = json.load(f)

source = cat.get("sourceLanguage", "en")
strings = cat.get("strings", {})
errors = []

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

count = len(strings)
if errors:
    print(f"FAIL: {len(errors)} problem(s) across {count} string(s):", file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    sys.exit(1)

print(f"OK: {count} string(s) each translated for {', '.join(LOCALES)}")
PY
