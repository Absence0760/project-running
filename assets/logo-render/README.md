# Logo render tooling

Procedural generators for the Threkir brand mark. **This is not the app-icon
pipeline** — the packaged icons are flat and generated from
[`../icon.svg`](../icon.svg) via [`../gen-icons.sh`](../gen-icons.sh)
(decisions.md §193). These scripts produce the *exploration* and *marketing*
artefacts around that mark.

The chosen production mark is the **thorn (þ)** — see decisions.md §198 for the
rationale. `stave`, `loop`, and `ridge` are the recorded alternates from the
same exploration.

## Scripts

| Script | Tool | Produces |
|---|---|---|
| `gen_svg.py` | (pure Python) | Flat vector marks for all four directions — app-icon tile, gradient mark, solid silhouette. |
| `render.py` | Blender 5.x (Cycles/OptiX) | Dimensional, ray-traced 3D hero renders for store listings / press / web splash. |

Both are deterministic and self-contained (paths resolve relative to this
directory). Outputs land in gitignored subdirs (`svg/`, `out/`) — regenerate on
demand rather than committing large rasters.

## Run

```bash
# Flat SVG marks -> assets/logo-render/svg/
python3 assets/logo-render/gen_svg.py

# Raster a flat mark at any size (Inkscape)
inkscape assets/logo-render/svg/thorn_icon.svg -w 512 -h 512 -o thorn_512.png

# 3D hero renders -> assets/logo-render/out/<mark>_3d.png (needs a CUDA/OptiX GPU)
blender --background --python assets/logo-render/render.py
MARKS=thorn SAMPLES=300 RES=1600 blender -b --python assets/logo-render/render.py
```

`render.py` builds each mark as a mesh directly from its path geometry (Blender's
SVG-curve fill mishandles the thorn's counter hole), extrudes + bevels it, and
renders it with the brand ember→magenta gradient as an emissive material on a
transparent film. The thorn geometry and the warm gradient here mirror the
shipped `../icon.svg`, so a re-render matches the production mark.

Requires the opt-in asset tools (Inkscape, ImageMagick) plus Blender — see the
workstation "Design & graphics workflow" convention.
