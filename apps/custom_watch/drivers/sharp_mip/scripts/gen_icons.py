#!/usr/bin/env python3
"""Generate src/icons.rs - a 16x16 monochrome icon table for the Sharp MIP driver.

Rasterises each editable SVG under ../icons/ with Inkscape (vector authoring),
flattens + thresholds it to 1-bit with ImageMagick, then packs each 16x16 cell
(2 bytes per row) into the Rust table the framebuffer's `draw_icon` blits.
Regenerate with:

    python3 scripts/gen_icons.py   # from drivers/sharp_mip/

The SVG sources are the editable master; the generated icons.rs is committed
alongside them, so a rendering change from an Inkscape / ImageMagick upgrade or
an SVG edit shows up as a reviewable diff, not a silent change - same discipline
as scripts/gen_font.py.

Bit convention (matches the framebuffer + the Sharp MIP wire format with
LSB-first SPI): bit 0 of each row byte is the LEFTMOST pixel, 1 = ink (black).
"""

import pathlib
import subprocess
import tempfile

# Order here is the order of the generated `Icon` enum + table. Add a new icon
# by dropping a NAME.svg in ../icons/ and appending its stem here.
ICONS = [
    "stopwatch",
    "footsteps",
    "heart",
    "heart_small",
    "mountain",
    "vert",
    "satellite",
    "sat_search0",
    "sat_search1",
]
SIZE = 16
BYTES_PER_ROW = SIZE // 8

HERE = pathlib.Path(__file__).resolve().parent
SVG_DIR = HERE.parent / "icons"
OUT = HERE.parent / "src" / "icons.rs"


def render(name: str, tmp: pathlib.Path) -> list[list[int]]:
    """SVG -> 16x16 -> list of SIZE rows, each BYTES_PER_ROW bytes, bit0 = leftmost ink."""
    svg = SVG_DIR / f"{name}.svg"
    if not svg.exists():
        raise SystemExit(f"missing icon source: {svg}")
    png = tmp / f"{name}.png"
    subprocess.run(
        [
            "inkscape",
            str(svg),
            "--export-type=png",
            f"--export-width={SIZE}",
            f"--export-height={SIZE}",
            f"--export-filename={png}",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    pbm = tmp / f"{name}.pbm"
    # Flatten the transparent SVG onto white, drop the alpha, threshold to
    # pure black/white, and emit a raw (P4) PBM where a set bit is black ink.
    subprocess.run(
        [
            "magick",
            str(png),
            "-background", "white",
            "-alpha", "remove",
            "-alpha", "off",
            "-threshold", "50%",
            "-depth", "1",
            str(pbm),
        ],
        check=True,
    )
    return unpack_pbm(pbm.read_bytes())


def unpack_pbm(data: bytes) -> list[list[int]]:
    if not data.startswith(b"P4"):
        raise SystemExit(f"expected raw PBM, got {data[:2]!r}")
    # Parse the P4 header: magic, then width and height as ASCII ints, then a
    # single whitespace byte before the packed bits.
    fields, i = [], 2
    while len(fields) < 2:
        while data[i : i + 1].isspace():
            i += 1
        if data[i : i + 1] == b"#":
            while data[i : i + 1] not in (b"\n", b""):
                i += 1
            continue
        start = i
        while not data[i : i + 1].isspace():
            i += 1
        fields.append(int(data[start:i]))
    width, height = fields
    if (width, height) != (SIZE, SIZE):
        raise SystemExit(f"expected {SIZE}x{SIZE}, got {width}x{height}")
    i += 1  # the single whitespace terminating the header
    bits = data[i:]

    # PBM P4 packs each row MSB-first with 1 = black; the panel wants bit 0 =
    # leftmost pixel, so reverse each pixel's bit position within its byte.
    stride = (width + 7) // 8
    rows = []
    for y in range(height):
        row = []
        for bx in range(BYTES_PER_ROW):
            src = bits[y * stride + bx]
            out = 0
            for bit in range(8):
                if src & (0x80 >> bit):
                    out |= 1 << bit
            row.append(out)
        rows.append(row)
    return rows


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        glyphs = {name: render(name, tmp) for name in ICONS}

    variants = "".join(f"    {stem_to_variant(n)},\n" for n in ICONS)
    arms = "".join(
        f"            Icon::{stem_to_variant(n)} => &{n.upper()},\n" for n in ICONS
    )
    tables = "\n".join(render_table(n, glyphs[n]) for n in ICONS)

    body = f"""//! Generated 16x16 monochrome icon table - DO NOT EDIT BY HAND.
//!
//! Produced by `scripts/gen_icons.py` from the editable SVG sources under
//! `icons/`. Each icon is {SIZE}x{SIZE} pixels, {BYTES_PER_ROW} bytes per row,
//! bit 0 = leftmost pixel, 1 = ink - the same convention as the font and the
//! framebuffer. Blit with [`crate::Framebuffer::draw_icon`].

/// Width and height of every icon, in pixels.
pub const ICON_SIZE: usize = {SIZE};
/// Bytes per icon row.
pub const ICON_BYTES_PER_ROW: usize = {BYTES_PER_ROW};

/// One entry per SVG under `icons/`, in the order `scripts/gen_icons.py` lists.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Icon {{
{variants}}}

impl Icon {{
    /// The packed {SIZE}x{SIZE} bitmap for this icon.
    pub fn bitmap(self) -> &'static [[u8; ICON_BYTES_PER_ROW]; ICON_SIZE] {{
        match self {{
{arms}        }}
    }}
}}

{tables}"""

    OUT.write_text(body, encoding="ascii")
    print(f"wrote {OUT} ({len(ICONS)} icons)")


def stem_to_variant(stem: str) -> str:
    return "".join(part.capitalize() for part in stem.split("_"))


def render_table(name: str, rows: list[list[int]]) -> str:
    lines = "\n".join(
        "    [" + ", ".join(f"0x{b:02x}" for b in row) + "]," for row in rows
    )
    return (
        f"static {name.upper()}: [[u8; ICON_BYTES_PER_ROW]; ICON_SIZE] = [\n"
        f"{lines}\n];\n"
    )


if __name__ == "__main__":
    main()
