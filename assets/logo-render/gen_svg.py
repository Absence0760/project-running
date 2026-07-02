#!/usr/bin/env python3
"""Generate the flat vector marks for the Threkir logo exploration.

Emits, for each mark, an app-icon SVG (gradient tile + white glyph), a
gradient-filled transparent mark, and a solid silhouette. The chosen production
mark is `thorn`; its shipped master is assets/icon.svg (see decisions.md §198).
The other three (stave / loop / ridge) are kept as the recorded alternates.

Run:  python3 assets/logo-render/gen_svg.py
Output: assets/logo-render/svg/*.svg (gitignored; regenerate on demand).
For raster export use Inkscape, e.g.:
  inkscape svg/thorn_icon.svg -w 512 -h 512 -o thorn_512.png
"""
import os

BASE = os.path.dirname(os.path.abspath(__file__))
SVG = os.path.join(BASE, "svg")
os.makedirs(SVG, exist_ok=True)

EMBER, MAGENTA = "#FE5932", "#A01E77"

# geometry (100x100 space), per-mark centre + icon scale (mark ~610px on 1024)
MARKS = {
    "thorn": dict(  # shipped mark — matches assets/icon.svg
        geom='<path fill-rule="evenodd" d="M30 10 H44 V90 H30 Z '
             'M44 29 H58 A21 21 0 0 1 58 71 H44 Z '
             'M44 42 H56 A8 8 0 0 1 56 58 H44 Z"/>',
        c=(54.5, 50), s=7.6),
    "stave": dict(
        geom='<path d="M33 8 H43 V92 H33 Z"/>'
             '<path d="M43 22 L78 41 L43 60 Z"/>',
        c=(55.5, 50), s=7.4),
    "loop": dict(
        geom='<path fill-rule="evenodd" d="M18 50 a32 32 0 1 0 64 0 a32 32 0 1 0 -64 0 '
             'M31 50 a19 19 0 1 0 38 0 a19 19 0 1 0 -38 0"/>'
             '<rect x="45" y="13" width="10" height="24" rx="2.5"/>',
        c=(50, 47.5), s=9.0),
    "ridge": dict(
        geom='<path d="M10 82 L10 60 L26 70 L40 44 L56 58 L72 28 L90 40 L90 82 Z"/>'
             '<circle cx="72" cy="16" r="6.5"/>',
        c=(50, 45.5), s=7.75),
}

def grad(gid, x2, y2):
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="{x2}" y2="{y2}" '
            f'gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{EMBER}"/>'
            f'<stop offset="0.58" stop-color="{EMBER}"/>'
            f'<stop offset="1" stop-color="{MAGENTA}"/></linearGradient>')

for name, m in MARKS.items():
    cx, cy = m["c"]; s = m["s"]
    tf = f"translate(512 512) scale({s}) translate({-cx} {-cy})"

    icon = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">'
            f'<defs>{grad("g", 1024, 1024)}</defs>'
            '<rect width="1024" height="1024" rx="224" fill="url(#g)"/>'
            f'<g fill="#ffffff" transform="{tf}">{m["geom"]}</g></svg>')
    open(os.path.join(SVG, f"{name}_icon.svg"), "w").write(icon)

    mark = ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
            'viewBox="0 0 100 100">'
            f'<defs>{grad("g", 100, 100)}</defs>'
            f'<g fill="url(#g)">{m["geom"]}</g></svg>')
    open(os.path.join(SVG, f"{name}_mark.svg"), "w").write(mark)

    solid = ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
             'viewBox="0 0 100 100">'
             f'<g fill="#000000">{m["geom"]}</g></svg>')
    open(os.path.join(SVG, f"{name}_solid.svg"), "w").write(solid)

print("wrote", len(MARKS) * 3, "svgs to", SVG)
