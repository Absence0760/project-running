#!/usr/bin/env python3
"""Generate src/bignum.rs — the designed numeral faces for the hero bands.

Rasterises the numeral glyph set (digits, colon, dash, dot, plus) from the
pinned Adobe Source Code Pro Bold vendored at `fonts/SourceCodePro-Bold.otf`
(SIL OFL 1.1, the same family scripts/gen_font.py rasterises the 8x16 text
font from — see `fonts/README.md` for its exact upstream release, its SHA256,
and how to fetch it again) via ImageMagick into one monochrome strip per size,
then packs each cell into a Rust table. Two sizes share the set: the 32x48
face (the home clock hero and the 3-row run glance heroes) and the 16x32
medium face (the 2-row run-view heroes). Native-resolution rasterisation is
the whole point: the old heroes scaled the 8x16 text font 2x/3x, which blew
its 1-2 px strokes up into ragged blocks; a real rasterisation at the target
size gets the curves and the bold stroke weight right. Regenerate with:

    python3 scripts/gen_bignum.py   # from drivers/sharp_mip/

The face is verified by digest before anything is drawn (`pinned_face.py`), so
a machine without it fails loudly rather than reshaping all the glyphs from
whatever Source Code Pro build fontconfig resolves — the variable build's
default instance is ExtraLight, and that reshape would read in review as one
new glyph. The output file is committed; rendering differences from an
ImageMagick upgrade still show up as a reviewable diff.

Bit convention (matches font.rs and the Sharp MIP wire format with LSB-first
SPI): bit 0 of each row byte is the LEFTMOST pixel of its 8-px span, 1 = ink.
"""

import pathlib
import subprocess
import tempfile

from pinned_face import pinned_face

# `+` is appended rather than placed beside `-` so the existing glyphs keep
# their table indices and the regeneration diff stays purely additive.
GLYPHS = "0123456789:-.+"
# Source Code Pro's advance is 0.6 em -> the em that lands the advance exactly
# on the cell width: 53.333px em = 32px advance, 26.6667px em = 16px.
TABLES = [
    ("BIGNUM", 32, 48, "53.3333"),
    ("BIGNUM_MED", 16, 32, "26.6667"),
]
FONT = pinned_face("SourceCodePro-Bold.otf")

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "src" / "bignum.rs"


def render_strip(tmp: pathlib.Path, pointsize: str) -> tuple[int, int, bytes]:
    glyph_file = tmp / "glyphs.txt"
    glyph_file.write_text(GLYPHS, encoding="ascii")
    pbm = tmp / "strip.pbm"
    # Antialias + a 50% threshold: the grey coverage rounds curve edges onto
    # the pixel grid far better than a bilevel rasterisation.
    subprocess.run(
        [
            "magick",
            "-background", "white",
            "-fill", "black",
            "-font", FONT,
            "-pointsize", pointsize,
            "-kerning", "0",
            "-antialias",
            f"label:@{glyph_file}",
            "-threshold", "50%",
            "-depth", "1",
            str(pbm),
        ],
        check=True,
    )
    data = pbm.read_bytes()
    if not data.startswith(b"P4"):
        raise SystemExit(f"expected raw PBM, got {data[:2]!r}")
    fields, i = [], 2
    while len(fields) < 2:
        while data[i : i + 1].isspace():
            i += 1
        if data[i : i + 1] == b"#":
            while data[i : i + 1] != b"\n":
                i += 1
            continue
        start = i
        while not data[i : i + 1].isspace():
            i += 1
        fields.append(int(data[start:i]))
    i += 1
    return fields[0], fields[1], data[i:]


def pixel(bits: bytes, width: int, x: int, y: int) -> bool:
    row_bytes = (width + 7) // 8
    byte = bits[y * row_bytes + x // 8]
    return bool(byte >> (7 - x % 8) & 1)  # PBM: MSB is leftmost, 1 = black


def rasterise(name: str, cell_w: int, cell_h: int, pointsize: str) -> list:
    with tempfile.TemporaryDirectory() as tmpdir:
        width, height, bits = render_strip(pathlib.Path(tmpdir), pointsize)

    expected_w = cell_w * len(GLYPHS)
    if width < expected_w or width > expected_w + 4:
        raise SystemExit(
            f"{name} strip is {width}px wide, expected ~{expected_w} — "
            f"the font's advance no longer lands on exactly {cell_w}px; "
            "adjust the pointsize"
        )

    # The numeral set has no descenders, so instead of gen_font.py's baseline
    # window the whole shared ink band is centred in the cell — every glyph
    # shifts by the same offset, keeping the colon and dot aligned to the
    # digits.
    ink_rows = [
        y
        for y in range(height)
        if any(pixel(bits, width, x, y) for x in range(expected_w))
    ]
    if not ink_rows:
        raise SystemExit(f"no ink in {name} rendered strip")
    top, bottom = ink_rows[0], ink_rows[-1]
    ink_h = bottom - top + 1
    if ink_h > cell_h:
        raise SystemExit(f"{name} ink is {ink_h}px tall, exceeds the {cell_h}px cell")
    pad_top = (cell_h - ink_h) // 2

    glyphs = []
    for index in range(len(GLYPHS)):
        rows = [[0] * (cell_w // 8) for _ in range(cell_h)]
        for y in range(ink_h):
            for x in range(cell_w):
                if pixel(bits, width, index * cell_w + x, top + y):
                    rows[pad_top + y][x // 8] |= 1 << (x % 8)
        glyphs.append(rows)

    seen = {}
    for ch, rows in zip(GLYPHS, glyphs):
        key = tuple(tuple(r) for r in rows)
        if not any(any(r) for r in rows):
            raise SystemExit(f"{name} glyph {ch!r} rasterised blank")
        if key in seen:
            raise SystemExit(
                f"{name} glyphs {seen[key]!r} and {ch!r} rasterise identically"
            )
        seen[key] = ch

    print(f"{name}: {len(GLYPHS)} glyphs, ink {ink_h}px tall")
    return glyphs


def main() -> None:
    lines = [
        "// Generated by scripts/gen_bignum.py - do not hand-edit; regenerate instead.",
        "// Glyphs rasterised from Adobe Source Code Pro Bold (SIL OFL 1.1).",
        "// Bit 0 of each row byte is the LEFTMOST pixel of its 8-px span, 1 = ink.",
        "",
    ]
    for name, cell_w, cell_h, _ in TABLES:
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
    for name, cell_w, cell_h, pointsize in TABLES:
        glyphs = rasterise(name, cell_w, cell_h, pointsize)
        lines += [
            "",
            f"/// One entry per [`BIGNUM_GLYPHS`] char, {cell_h} rows of "
            f"{cell_w // 8} bytes each.",
            f"pub const {name}: [[[u8; {name}_ROW_BYTES]; {name}_HEIGHT]; "
            f"{len(GLYPHS)}] = [",
        ]
        for ch, rows in zip(GLYPHS, glyphs):
            lines.append("    [")
            for row in rows:
                packed = ", ".join(f"0x{b:02X}" for b in row)
                lines.append(f"        [{packed}],")
            lines.append(f"    ], // {ch}")
        lines.append("];")
    OUT.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
