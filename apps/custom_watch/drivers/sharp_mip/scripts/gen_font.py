#!/usr/bin/env python3
"""Generate src/font.rs — the 8x16 text font for the Sharp MIP driver.

Transcribes printable ASCII (32..=126) from the pinned Spleen BDFs
vendored under `fonts/` (BSD 2-Clause — see `fonts/README.md` for the exact
upstream release, the SHA256s, and how to fetch them again): the 8x16 body
face into `src/font.rs`, and the 6x12 label face — the chrome size the
hero-label and status rows render at (decisions.md § 429) — into
`src/font_small.rs`.
Spleen is drawn pixel-by-pixel FOR 8x16 monochrome cells, which is why it
replaced the table this script used to rasterise from Source Code Pro:
thresholding a vector outline at this size leaves 1-px stems and ragged
diagonals — the '+'=='-' collision, the invisible '|', and the '!'-reads-
as-':' failure were all casualties of that pipeline (pinned from the other
side by `tests/font.rs`), and the survivors carried visibly uneven stroke
weights. A hand-designed bitmap has none of those failure modes, and the
generator becomes a pure bit transcription with NO rasteriser in the loop:
regeneration is reproducible by construction, not by pinning ImageMagick.

The numeral hero faces (`gen_bignum.py`) stay rasterised from Source Code
Pro Bold — at 32x48 and 16x32 the outline has whole pixels to land in and
the failure mode above does not exist.

Regenerate with:

    python3 scripts/gen_font.py   # from drivers/sharp_mip/

Bit convention (matches the framebuffer + the Sharp MIP wire format with
LSB-first SPI): bit 0 of each row byte is the LEFTMOST pixel, 1 = ink. BDF
bitmap rows put the leftmost pixel in the MSB, so each byte is bit-reversed
in transit.
"""

import pathlib
import re

from pinned_face import pinned_face

GLYPHS = "".join(chr(c) for c in range(32, 127))

HERE = pathlib.Path(__file__).resolve().parent

# (bdf, cell_w, cell_h, bbx y-offset, output file). Spleen's full-cell BBX is
# `w h 0 -descent`; the descent is asserted per glyph below.
TABLES = [
    ("spleen-8x16.bdf", 8, 16, -4, "font.rs"),
    ("spleen-6x12.bdf", 6, 12, -3, "font_small.rs"),
]


def parse_bdf(path: pathlib.Path, cell_w: int, cell_h: int, y_off: int) -> dict[str, list[int]]:
    """Printable-ASCII glyph rows, bit 0 = leftmost, straight off the BDF.

    Every Spleen glyph is a full-cell `BBX w h 0 -descent` bitmap, so
    transcription is row-for-row with no baseline arithmetic; that uniformity
    is asserted rather than assumed, because a glyph with a tighter bounding
    box would otherwise land shifted and the table would be wrong everywhere
    it is used.
    """
    glyphs: dict[str, list[int]] = {}
    encoding = None
    bbx = None
    rows: list[int] = []
    in_bitmap = False
    for line in path.read_text(encoding="ascii").splitlines():
        if line.startswith("ENCODING "):
            encoding = int(line.split()[1])
        elif line.startswith("BBX "):
            bbx = tuple(int(v) for v in line.split()[1:])
        elif line.startswith("BITMAP"):
            in_bitmap = True
            rows = []
        elif line.startswith("ENDCHAR"):
            if encoding is not None and 32 <= encoding <= 126:
                if bbx != (cell_w, cell_h, 0, y_off):
                    raise SystemExit(
                        f"glyph {encoding} has BBX {bbx}, not the full "
                        f"{cell_w}x{cell_h} cell — transcription would misplace it"
                    )
                if len(rows) != cell_h:
                    raise SystemExit(
                        f"glyph {encoding} carries {len(rows)} bitmap rows, "
                        f"expected {cell_h}"
                    )
                glyphs[chr(encoding)] = [reverse_bits(r) for r in rows]
            in_bitmap = False
            encoding = None
            bbx = None
        elif in_bitmap:
            if not re.fullmatch(r"[0-9A-Fa-f]{2}", line.strip()):
                raise SystemExit(f"unexpected bitmap row {line!r}")
            rows.append(int(line.strip(), 16))
    return glyphs


def reverse_bits(b: int) -> int:
    return int(f"{b:08b}"[::-1], 2)


def main() -> None:
    for bdf, cell_w, cell_h, y_off, out_name in TABLES:
        table = parse_bdf(pinned_face(bdf), cell_w, cell_h, y_off)
        missing = [ch for ch in GLYPHS if ch not in table]
        if missing:
            raise SystemExit(f"{bdf} lacks printable glyphs: {missing!r}")
        glyphs = [table[ch] for ch in GLYPHS]

        # No rasteriser means no collision-repair pass, but the invariant it
        # guarded still holds the gate: two distinct printable characters that
        # pack to the same pixels are indistinguishable on the panel. Space is
        # included so an all-blank glyph trips it too.
        seen: dict[tuple[int, ...], str] = {}
        for ch, rows in zip(GLYPHS, glyphs):
            key = tuple(rows)
            if key in seen:
                raise SystemExit(
                    f"{bdf}: glyphs {seen[key]!r} and {ch!r} are byte-identical "
                    "— they would be indistinguishable on the panel"
                )
            seen[key] = ch

        emit(glyphs, cell_w, cell_h, bdf, HERE.parent / "src" / out_name)


def emit(glyphs: list[list[int]], cell_w: int, cell_h: int, bdf: str, out: pathlib.Path) -> None:
    lines = [
        "// Generated by scripts/gen_font.py - do not hand-edit; regenerate instead.",
        f"// Glyphs transcribed from Spleen {cell_w}x{cell_h} (BSD 2-Clause).",
        "// Bit 0 of each row byte is the LEFTMOST pixel, 1 = ink.",
        "",
        f"pub const GLYPH_WIDTH: usize = {cell_w};",
        f"pub const GLYPH_HEIGHT: usize = {cell_h};",
        "pub const FIRST_CHAR: u8 = b' ';",
        "",
        f"/// One entry per printable ASCII char (32..=126), {cell_h} row bytes each.",
        f"pub const FONT: [[u8; GLYPH_HEIGHT]; {len(GLYPHS)}] = [",
    ]
    for ch, rows in zip(GLYPHS, glyphs):
        packed = ", ".join(f"0x{r:02X}" for r in rows)
        name = "space" if ch == " " else ch
        lines.append(f"    [{packed}], // {name}")
    lines.append("];")
    out.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"wrote {out} ({len(GLYPHS)} glyphs)")


if __name__ == "__main__":
    main()
