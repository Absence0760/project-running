#!/usr/bin/env python3
"""Generate src/bignum.rs — the designed numeral faces for the hero bands.

Transcribes the numeral glyph set (digits, colon, dash, dot, plus) from the
pinned Spleen BDFs vendored under `fonts/` (BSD 2-Clause — the same family
every other face on the panel is now transcribed from; see `fonts/README.md`
for the exact upstream release, the SHA256s, and how to fetch them again).
Two sizes share the set: the 32x48 face (the home clock hero and the 3-row
run glance heroes) and the 16x32 medium face (the 2-row run-view heroes).

The medium face is Spleen 16x32 taken whole — the cell matches. The big face
is Spleen 32x64's glyph band cropped to 48 rows: the numeral set has no
descenders, its ink stands 40 rows tall, and the crop window is anchored so
the big face's bottom ink margin EQUALS the medium face's — which is what
makes `draw_bignum_hero`'s shared baseline hold by construction rather than
by the coincidence of two rasterisations centring to the same margin. Both
choices are asserted, not assumed: a Spleen release that moved a glyph's ink
outside the window fails loudly here.

This generator replaced a rasterise-and-threshold pipeline over Source Code
Pro Bold (§ 431): a thresholded outline carries staircase edges on every
curve at any size, where a face drawn pixel-by-pixel has none — the same
reason § 428 moved the text face. No rasteriser, no ImageMagick: the tables
are a pure bit transcription, reproducible by construction. Regenerate with:

    python3 scripts/gen_bignum.py   # from drivers/sharp_mip/

Bit convention (matches font.rs and the Sharp MIP wire format with LSB-first
SPI): bit 0 of each row byte is the LEFTMOST pixel of its 8-px span, 1 = ink.
"""

import pathlib

from pinned_face import pinned_face

# `+` is appended rather than placed beside `-` so the existing glyphs keep
# their table indices and the regeneration diff stays purely additive.
GLYPHS = "0123456789:-.+"

# The bitmap each slot transcribes from. Spleen's `0` carries the slash that
# tells it apart from the letter O — a distinction a 14-glyph numeral face
# cannot need, and at clock size the slash busies the largest glyph on the
# panel. Spleen's own unslashed `O` sits on the identical ink band (asserted
# by the crop maths), so the zero slot takes that bitmap: the same designed
# shape, minus a mark with nothing to disambiguate.
SOURCE = {"0": "O"}

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "src" / "bignum.rs"


def parse_bdf(name: str) -> tuple[dict[str, list[int]], int, int]:
    """Glyph bitmap rows for the numeral set, plus the source cell size.

    Rows come back MSB-leftmost exactly as the BDF carries them; the packing
    step below converts to the wire's bit-0-leftmost bytes. Every glyph must
    be a full-cell bitmap (Spleen's are), because a tighter bounding box
    would land shifted.
    """
    path = pinned_face(name)
    glyphs: dict[str, list[int]] = {}
    cell_w = cell_h = None
    encoding = None
    rows: list[int] = []
    in_bitmap = False
    for line in path.read_text(encoding="ascii").splitlines():
        if line.startswith("FONTBOUNDINGBOX "):
            cell_w, cell_h = (int(v) for v in line.split()[1:3])
        elif line.startswith("ENCODING "):
            encoding = int(line.split()[1])
        elif line.startswith("BITMAP"):
            in_bitmap = True
            rows = []
        elif line.startswith("ENDCHAR"):
            wanted = encoding is not None and 0 <= encoding < 0x110000 and (
                chr(encoding) in GLYPHS or chr(encoding) in SOURCE.values()
            )
            if wanted:
                if len(rows) != cell_h:
                    raise SystemExit(
                        f"{name}: glyph {chr(encoding)!r} carries {len(rows)} "
                        f"rows, expected the full {cell_h}-row cell"
                    )
                glyphs[chr(encoding)] = rows
            in_bitmap = False
            encoding = None
        elif in_bitmap:
            rows.append(int(line.strip(), 16))
    for slot, src in SOURCE.items():
        glyphs[slot] = glyphs[src]
    missing = [ch for ch in GLYPHS if ch not in glyphs]
    if missing:
        raise SystemExit(f"{name} lacks numeral glyphs: {missing!r}")
    return glyphs, cell_w, cell_h


def ink_band(glyphs: dict[str, list[int]]) -> tuple[int, int]:
    """First and last row carrying ink across the whole glyph set."""
    rows = [y for g in glyphs.values() for y, bits in enumerate(g) if bits]
    return min(rows), max(rows)


def embolden(rows: list[int], px: int) -> list[int]:
    """Rightward dilation by `px` — the synthetic bold every bitmap terminal
    uses. Spleen ships the numeral sizes at regular weight (4 px stems on the
    32x64, 2 px on the 16x32), and a hero on a reflective panel wants the
    § 292 bold; dilating a face that is already pixel-designed keeps its
    smooth edges (a clean edge dilates to a clean edge) where re-rasterising
    a bold outline would bring the staircase back. Two steps on the big face
    and one on the medium is optical sizing, and both leave the counters
    wide open (12 px and 6 px natively); the distinctness gate below would
    catch a glyph that closed.
    """
    for _ in range(px):
        rows = [bits | bits >> 1 for bits in rows]
    return rows


def pack(rows: list[int], cell_w: int, bold_px: int) -> list[list[int]]:
    """One glyph's MSB-leftmost rows into bit-0-leftmost byte rows."""
    out = []
    for bits in embolden(rows, bold_px):
        row = [0] * (cell_w // 8)
        for x in range(cell_w):
            if bits >> (cell_w - 1 - x) & 1:
                row[x // 8] |= 1 << x % 8
        out.append(row)
    return out


def main() -> None:
    med_glyphs, med_w, med_h = parse_bdf("spleen-16x32.bdf")
    big_glyphs, big_w, big_h = parse_bdf("spleen-32x64.bdf")
    if (med_w, med_h) != (16, 32) or (big_w, big_h) != (32, 64):
        raise SystemExit("Spleen cell sizes moved — re-derive the crop")

    _, med_bottom = ink_band(med_glyphs)
    med_margin = med_h - 1 - med_bottom
    big_top, big_bottom = ink_band(big_glyphs)
    out_h = 48
    start = big_bottom + 1 + med_margin - out_h
    if start < 0 or start > big_top:
        raise SystemExit(
            f"the {out_h}-row crop (rows {start}..{start + out_h}) cannot hold "
            f"the big face's ink band ({big_top}..{big_bottom}) at the medium "
            f"face's {med_margin}-row bottom margin"
        )

    tables = [
        (
            "BIGNUM",
            32,
            out_h,
            {ch: pack(g[start : start + out_h], 32, 2) for ch, g in big_glyphs.items()},
        ),
        ("BIGNUM_MED", 16, 32, {ch: pack(g, 16, 1) for ch, g in med_glyphs.items()}),
    ]

    lines = [
        "// Generated by scripts/gen_bignum.py - do not hand-edit; regenerate instead.",
        "// Glyphs transcribed from Spleen 32x64 (cropped to 48 rows) and 16x32",
        "// (BSD 2-Clause).",
        "// Bit 0 of each row byte is the LEFTMOST pixel of its 8-px span, 1 = ink.",
        "",
    ]
    for name, cell_w, cell_h, _ in tables:
        lines += [
            f"pub const {name}_WIDTH: usize = {cell_w};",
            f"pub const {name}_HEIGHT: usize = {cell_h};",
            f"pub const {name}_ROW_BYTES: usize = {name}_WIDTH / 8;",
            "",
        ]
    lines += [
        "/// The numeral glyph set, in the order both tables share.",
        f'pub const BIGNUM_GLYPHS: &[u8; {len(GLYPHS)}] = b"{GLYPHS}";',
    ]
    for name, cell_w, cell_h, glyphs in tables:
        seen: dict[tuple, str] = {}
        for ch in GLYPHS:
            key = tuple(tuple(r) for r in glyphs[ch])
            if not any(any(r) for r in glyphs[ch]):
                raise SystemExit(f"{name} glyph {ch!r} transcribed blank")
            if key in seen:
                raise SystemExit(f"{name} glyphs {seen[key]!r} and {ch!r} are identical")
            seen[key] = ch
        lines += [
            "",
            f"/// One entry per [`BIGNUM_GLYPHS`] char, {cell_h} rows of "
            f"{cell_w // 8} bytes each.",
            f"pub const {name}: [[[u8; {name}_ROW_BYTES]; {name}_HEIGHT]; "
            f"{len(GLYPHS)}] = [",
        ]
        for ch in GLYPHS:
            lines.append("    [")
            for row in glyphs[ch]:
                packed = ", ".join(f"0x{b:02X}" for b in row)
                lines.append(f"        [{packed}],")
            lines.append(f"    ], // {ch}")
        lines.append("];")
    OUT.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
