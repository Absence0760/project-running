#!/usr/bin/env python3
"""Generate src/font.rs — an 8x16 bitmap font table for the Sharp MIP driver.

Rasterises printable ASCII (32..=126) from the pinned Adobe Source Code Pro
vendored at `fonts/SourceCodePro-Regular.otf` (SIL OFL 1.1 — see
`fonts/README.md` for its exact upstream release, its SHA256, and how to fetch
it again) via ImageMagick into one 760x16 monochrome strip, then packs each
8x16 cell into the Rust table the driver's text renderer indexes. Regenerate
with:

    python3 scripts/gen_font.py   # from drivers/sharp_mip/

The face is verified by digest before anything is drawn (`pinned_face.py`): the
script used to name it by fontconfig family, which resolves to whatever build
the machine has installed, and the only Homebrew-installable Source Code Pro is
the variable font whose default instance is ExtraLight. The output file is
committed; rendering differences from an ImageMagick upgrade still show up as a
reviewable diff, not a silent change.

Bit convention (matches the framebuffer + the Sharp MIP wire format with
LSB-first SPI): bit 0 of each row byte is the LEFTMOST pixel, 1 = ink.
"""

import pathlib
import subprocess
import sys
import tempfile

from pinned_face import pinned_face

GLYPHS = "".join(chr(c) for c in range(32, 127))
CELL_W, CELL_H = 8, 16
# Source Code Pro's advance is 0.6 em -> a 13.333px em gives exactly 8px.
POINTSIZE = "13.3333"
FONT = pinned_face("SourceCodePro-Regular.otf")
# Supersampling factor for the collision-repair pass below. An integer multiple
# keeps the cell grid and the baseline window aligned with the 1x pass.
REPAIR_SCALE = 2

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "src" / "font.rs"


def render_strip(tmp: pathlib.Path, scale: int = 1) -> tuple[int, int, bytes]:
    glyph_file = tmp / f"glyphs{scale}.txt"
    glyph_file.write_text(GLYPHS, encoding="ascii")
    pbm = tmp / f"strip{scale}.pbm"
    # Antialias + a 50% threshold at 2x: the supersampled pass needs grey
    # coverage to average down, while the 1x pass stays bilevel so its output
    # is bit-identical to what it has always produced.
    aa = ["-antialias"] if scale > 1 else ["+antialias"]
    post = ["-threshold", "50%"] if scale > 1 else []
    subprocess.run(
        [
            "magick",
            "-background", "white",
            "-fill", "black",
            "-font", FONT,
            "-pointsize", str(float(POINTSIZE) * scale),
            "-kerning", "0",
            *aa,
            f"label:@{glyph_file}",
            *post,
            "-depth", "1",
            str(pbm),
        ],
        check=True,
    )
    data = pbm.read_bytes()
    # P4 header: magic, whitespace, width, height, single whitespace, bits.
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


def baseline_window(bits: bytes, width: int, height: int, ink_width: int, cell_h: int) -> int:
    """Top row of the `cell_h`-tall window that keeps every cap top and clips
    only the deepest descenders — one shared window so the baseline stays
    aligned across glyphs."""
    ink_rows = [
        y for y in range(height) if any(pixel(bits, width, x, y) for x in range(ink_width))
    ]
    if not ink_rows:
        raise SystemExit("no ink in rendered strip")
    top, bottom = ink_rows[0], ink_rows[-1]
    return min(top, max(0, bottom - (cell_h - 1)))


# Characters the 1x pass damages without producing a byte-collision, so
# `repair_collisions`'s equality test cannot see them: the glyph to re-rasterise
# paired with what it degenerates into on the panel. Kept explicit rather than
# inferred — see `repair_collisions` for the heuristic that was measured and
# rejected — and pinned from the other side by the driver's `tests/font.rs`, so
# a list that falls behind the font fails a test rather than shipping.
DAMAGED_GLYPHS = [("!", ":")]


def repair_collisions(glyphs: list[list[int]], tmpdir: pathlib.Path) -> list[str]:
    """Re-rasterise any glyph the 1x pass rendered indistinguishable from
    another, by supersampling at [`REPAIR_SCALE`] and averaging back down.

    Two distinct printable characters that pack to the same pixels are always a
    rasterisation failure, not a font property: the reader cannot tell them
    apart on the panel. It happens when a stroke is thinner than one device
    pixel and its coverage falls under the threshold in every column — `+` at
    this cell size loses its vertical stem entirely and packs byte-identical to
    `-`, so every `+` on the watch (the VERT `+gain` row, the Pacer page's
    ahead/behind sign) rendered as a minus. Supersampling gives the stem whole
    pixels to land in.

    Byte-equality is not the whole of "indistinguishable", though, and reading
    the panel is what showed it: `!` kept its top serif and its dot but lost the
    stem between them, packing to two short marks — a colon with the upper dot
    raised a row. It never collided with `:`, so nothing here saw it, while on
    the panel every alert banner opened `: DRINK` instead of `! DRINK`, with the
    bang that marks the band as an *alert* rather than a label reading as
    punctuation. [`DAMAGED_GLYPHS`] names those, and they are repaired outright
    rather than run through the group machinery: [`_repair_group`] stops as soon
    as a group is pairwise distinct, and a near-miss like this already is.

    A glyph-wide heuristic was tried instead and rejected: "a stroke the 2x pass
    renders at more than twice the 1x length" flags 33 of 95 glyphs, because the
    2x pass puts most stems across two columns where 1x picks one. It measures
    sub-pixel placement, not damage.

    Only the glyphs that were actually broken are touched — see
    [`_repair_group`] — so the rest of the table stays bit-identical to the
    plain 1x rasterisation. Returns the repaired labels.
    """
    # Space participates so that a glyph the rasteriser blanked out entirely
    # collides with it and gets repaired — that is how '|' shipped invisible,
    # byte-identical to a space. Space itself is legitimately all-zero, so it
    # is never the glyph that gets re-rasterised.
    groups: dict[tuple[int, ...], list[int]] = {}
    for index, rows in enumerate(glyphs):
        groups.setdefault(tuple(rows), []).append(index)
    collided = [members for members in groups.values() if len(members) > 1]
    damaged = [GLYPHS.index(ch) for ch, _ in DAMAGED_GLYPHS]
    if not collided and not damaged:
        return []

    scale = REPAIR_SCALE
    width, height, bits = render_strip(tmpdir, scale)
    ink_width = CELL_W * scale * len(GLYPHS)
    if width < ink_width:
        raise SystemExit(f"{scale}x strip is {width}px wide, expected >= {ink_width}")
    y_off = baseline_window(bits, width, height, ink_width, CELL_H * scale)

    def resample(index: int) -> list[int]:
        rows = []
        for cy in range(CELL_H):
            row = 0
            for cx in range(CELL_W):
                # A target pixel is ink when at least half of the supersamples
                # it covers are ink.
                lit = sum(
                    1
                    for dy in range(scale)
                    for dx in range(scale)
                    if y_off + cy * scale + dy < height
                    and pixel(bits, width, index * CELL_W * scale + cx * scale + dx,
                              y_off + cy * scale + dy)
                )
                if lit * 2 >= scale * scale:
                    row |= 1 << cx
            rows.append(row)
        return rows

    repaired = []
    for members in collided:
        repaired += _repair_group(glyphs, members, resample)
    for index in damaged:
        if glyphs[index] != resample(index):
            glyphs[index] = resample(index)
            repaired.append(GLYPHS[index])
    return repaired


def _repair_group(
    glyphs: list[list[int]],
    members: list[int],
    resample,
) -> list[str]:
    """Repair the fewest glyphs in one colliding group that makes its members
    distinguishable again, worst-damaged first.

    A collision has exactly one guilty party: the glyph whose strokes the 1x
    rasteriser dropped. Re-rasterising the *innocent* member as well is
    gratuitous churn — it changes a glyph nobody reported as wrong, and at this
    cell size the 2x pass renders a hairline as two rows, so the innocent glyph
    comes back visibly heavier than its unaffected siblings. `-` is the worked
    example: repairing it alongside `+` thickened the hyphen to a two-row wedge
    while `=` and `_`, which never collided, stayed single-row bars — a
    user-visible weight mismatch introduced by a fix for a different glyph.

    So: rank candidates by how much detail the 1x pass cost them (the pixel
    distance between their 1x and supersampled forms — the glyph that lost a
    whole stem outranks one that merely thinned), repair them in that order,
    and stop the moment the group is pairwise distinct. Space is never a
    candidate: it is legitimately blank.
    """
    candidates = [i for i in members if GLYPHS[i] != " "]
    candidates.sort(
        key=lambda i: (
            -sum(bin(a ^ b).count("1") for a, b in zip(glyphs[i], resample(i))),
            i,
        )
    )
    repaired = []
    for index in candidates:
        if len({tuple(glyphs[i]) for i in members}) == len(members):
            break  # already distinguishable — leave the rest at 1x
        glyphs[index] = resample(index)
        repaired.append(GLYPHS[index])
    return repaired


def main() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = pathlib.Path(tmpdir)
        width, height, bits = render_strip(tmpdir)
        glyphs = extract(width, height, bits)
        repaired = repair_collisions(glyphs, tmpdir)
    if repaired:
        print(f"note: supersampled {len(repaired)} colliding glyph(s): {' '.join(repaired)}",
              file=sys.stderr)
    # Guard the invariant the repair exists for: after it, no two distinct
    # printable glyphs may still pack to the same pixels. Space is included,
    # so a glyph the rasteriser blanked out entirely trips this too rather
    # than shipping invisible.
    seen: dict[tuple[int, ...], str] = {}
    for ch, rows in zip(GLYPHS, glyphs):
        key = tuple(rows)
        if key in seen:
            raise SystemExit(
                f"glyphs {seen[key]!r} and {ch!r} still rasterise identically — "
                "they would be indistinguishable on the panel; raise REPAIR_SCALE"
            )
        seen[key] = ch

    emit(glyphs)


def extract(width: int, height: int, bits: bytes) -> list[list[int]]:
    expected_w = CELL_W * len(GLYPHS)
    # label: pads a constant pixel or two on the right; per-glyph advance is
    # verified exact by the ink check below, so only under-width is fatal.
    if width < expected_w or width > expected_w + 4:
        raise SystemExit(
            f"strip is {width}px wide, expected ~{expected_w} — "
            "the font's advance no longer lands on exactly 8px; adjust POINTSIZE"
        )

    # Vertical window: the line box (ascent+descent) can exceed CELL_H. Pick
    # the 16-row window that keeps every cap top and clips only the deepest
    # descender rows — one shared window so the baseline stays aligned.
    y_off = baseline_window(bits, width, height, expected_w, CELL_H)
    ink_rows = [
        y
        for y in range(height)
        if any(pixel(bits, width, x, y) for x in range(expected_w))
    ]
    clipped = max(0, ink_rows[-1] - (y_off + CELL_H - 1))
    if clipped:
        print(f"note: clipping {clipped} descender row(s)", file=sys.stderr)

    glyphs = []
    for index in range(len(GLYPHS)):
        rows = []
        for y in range(y_off, min(height, y_off + CELL_H)):
            row = 0
            for x in range(CELL_W):
                if pixel(bits, width, index * CELL_W + x, y):
                    row |= 1 << x  # bit 0 = leftmost, per the wire format
            rows.append(row)
        rows.extend([0] * (CELL_H - len(rows)))
        glyphs.append(rows)
    return glyphs


def emit(glyphs: list[list[int]]) -> None:
    lines = [
        "// Generated by scripts/gen_font.py - do not hand-edit; regenerate instead.",
        "// Glyphs rasterised from Adobe Source Code Pro (SIL OFL 1.1).",
        "// Bit 0 of each row byte is the LEFTMOST pixel, 1 = ink.",
        "",
        "pub const GLYPH_WIDTH: usize = 8;",
        "pub const GLYPH_HEIGHT: usize = 16;",
        "pub const FIRST_CHAR: u8 = b' ';",
        "",
        "/// One entry per printable ASCII char (32..=126), 16 row bytes each.",
        f"pub const FONT: [[u8; GLYPH_HEIGHT]; {len(GLYPHS)}] = [",
    ]
    for ch, rows in zip(GLYPHS, glyphs):
        packed = ", ".join(f"0x{r:02X}" for r in rows)
        name = "space" if ch == " " else ch
        lines.append(f"    [{packed}], // {name}")
    lines.append("];")
    OUT.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"wrote {OUT} ({len(GLYPHS)} glyphs)")


if __name__ == "__main__":
    main()
