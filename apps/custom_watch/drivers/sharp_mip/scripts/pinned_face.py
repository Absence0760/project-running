#!/usr/bin/env python3
"""The pinned static faces the glyph-table generators rasterise from.

Both generators used to name their face by fontconfig family
("Source-Code-Pro", "Source-Code-Pro-Bold"), which resolves to whatever build
the machine has installed. That made the committed tables unreproducible: the
only Homebrew-installable Source Code Pro is the *variable* font, whose default
instance is ExtraLight, so a regeneration meant to add one glyph would reshape
every other glyph into hairlines under cover of the same diff (see
`docs/architecture/decisions.md` § 339). So the faces are vendored under
`../fonts/` and verified by digest here before either generator draws a pixel.

Provenance, the upstream release, and how to fetch the faces again are in
`../fonts/README.md`.
"""

import hashlib
import pathlib

FACES = {
    "SourceCodePro-Regular.otf": (
        "9f9664e2edf6f045c11e774f9bd0be6993971f2544a39061a5ce478b96b051f8"
    ),
    "SourceCodePro-Bold.otf": (
        "6f5a4a46a99ad1b92a8675e98f148272c8d2476fc0eb067247dd5eea6a3ad84c"
    ),
}

FONT_DIR = pathlib.Path(__file__).resolve().parent.parent / "fonts"


def pinned_face(name: str) -> pathlib.Path:
    """Path to a vendored face, after checking it is byte-for-byte the pinned
    one. Raises rather than returning a wrong font, because a wrong font does
    not fail — it silently produces a different table."""
    expected = FACES[name]
    path = FONT_DIR / name
    if not path.is_file():
        raise SystemExit(
            f"pinned face missing: {path}\n"
            f"Fetch it per {FONT_DIR / 'README.md'} — do NOT substitute a "
            "system-installed Source Code Pro; the variable build's default "
            "instance is ExtraLight and would reshape every glyph."
        )
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(
            f"pinned face digest mismatch for {path}\n"
            f"  expected {expected}\n"
            f"  actual   {actual}\n"
            f"Restore the pinned face per {FONT_DIR / 'README.md'}, or update "
            "FACES here deliberately and re-baseline the generated tables as "
            "their own reviewable commit."
        )
    return path
