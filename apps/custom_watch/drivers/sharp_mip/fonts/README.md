# Pinned source faces for the generated glyph tables

`src/font.rs` (8x16 body text) and `src/font_small.rs` (6x12 — the chrome
size the hero-label and status rows render at, § 429) are transcribed from
the Spleen BDFs in this directory by `scripts/gen_font.py`; `src/bignum.rs`
(32x48 + 16x32 numerals) is rasterised from the two Source Code Pro OTFs by
`scripts/gen_bignum.py`.
The split is deliberate: at 8x16 a thresholded vector outline leaves 1-px
stems and ragged diagonals (the '+'=='-' collision and the invisible '|'
were casualties — `tests/font.rs`), so the text face is a bitmap font drawn
pixel-by-pixel FOR that cell size, while at 32x48/16x32 the outline has
whole pixels to land in and native rasterisation of a real bold face wins
(`docs/architecture/decisions.md` § 292/§ 339/§ 428).

The faces are vendored rather than looked up by fontconfig family name
because a family name resolves to whatever build the machine happens to have
installed: Homebrew ships only the *variable* Source Code Pro, whose default
instance is ExtraLight, and rasterising the numerals from it reshapes every
committed glyph into hairlines — a change that would read in review as one
new glyph and be twenty-six reshaped ones (§ 339). `scripts/pinned_face.py`
verifies each file's SHA256 before either generator reads a glyph, so a
substituted or truncated face fails loudly instead of silently reshaping a
table.

## Provenance

| File | SHA256 |
|---|---|
| `spleen-8x16.bdf` | `4a3d97ee61a8c86a7525d8c723cb8a14081f395cd2feb4227ba5e3baf0629bae` |
| `spleen-6x12.bdf` | `fc0743d164690f99b7e2e1b9d503180e4c719a9831ae03fd8f6da18c857dee27` |
| `LICENSE.spleen.txt` | `f33fe8679d5b2abecc4f1313ce6c6bfa58262964de5f7bca146596a7318047af` |
| `SourceCodePro-Regular.otf` | `9f9664e2edf6f045c11e774f9bd0be6993971f2544a39061a5ce478b96b051f8` |
| `SourceCodePro-Bold.otf` | `6f5a4a46a99ad1b92a8675e98f148272c8d2476fc0eb067247dd5eea6a3ad84c` |
| `LICENSE.md` | `7c940e28a5388e9bba866cf0e408edda45fe0899ba98665b8f6ab31dc5e4b8ff` |

### Spleen

- Upstream: <https://github.com/fcambus/spleen>
- Release tag: `2.2.0` (`spleen-8x16.bdf`, `spleen-6x12.bdf` and `LICENSE` at that tag)
- `SourceCodePro-Regular.otf` is retained only as the historical source of
  the pre-§ 428 text table; `gen_font.py` no longer reads it.

```sh
curl -fsSL -o spleen-8x16.bdf https://raw.githubusercontent.com/fcambus/spleen/2.2.0/spleen-8x16.bdf
curl -fsSL -o spleen-6x12.bdf https://raw.githubusercontent.com/fcambus/spleen/2.2.0/spleen-6x12.bdf
curl -fsSL -o LICENSE.spleen.txt https://raw.githubusercontent.com/fcambus/spleen/2.2.0/LICENSE
shasum -a 256 -c <<'EOF'
4a3d97ee61a8c86a7525d8c723cb8a14081f395cd2feb4227ba5e3baf0629bae  spleen-8x16.bdf
fc0743d164690f99b7e2e1b9d503180e4c719a9831ae03fd8f6da18c857dee27  spleen-6x12.bdf
f33fe8679d5b2abecc4f1313ce6c6bfa58262964de5f7bca146596a7318047af  LICENSE.spleen.txt
EOF
```

### Source Code Pro

- Upstream: <https://github.com/adobe-fonts/source-code-pro>
- Release tag: `2.042R-u/1.062R-i/1.026R-vf` (published 2023-04-12)
- Asset: `OTF-source-code-pro-2.042R-u_1.062R-i.zip`
  (SHA256 `754a2e3ebb945ae905d720ac5896b3b34acc9546dd6551ef9536869788629dae`),
  members `OTF/SourceCodePro-Regular.otf` and `OTF/SourceCodePro-Bold.otf`
- `LICENSE.md` is the repository's licence file at that same tag (the release
  zips carry no licence of their own)

```sh
curl -fsSL -o /tmp/scp-otf.zip \
  'https://github.com/adobe-fonts/source-code-pro/releases/download/2.042R-u%2F1.062R-i%2F1.026R-vf/OTF-source-code-pro-2.042R-u_1.062R-i.zip'
unzip -j -o -d . /tmp/scp-otf.zip OTF/SourceCodePro-Regular.otf OTF/SourceCodePro-Bold.otf
shasum -a 256 -c <<'EOF'
9f9664e2edf6f045c11e774f9bd0be6993971f2544a39061a5ce478b96b051f8  SourceCodePro-Regular.otf
6f5a4a46a99ad1b92a8675e98f148272c8d2476fc0eb067247dd5eea6a3ad84c  SourceCodePro-Bold.otf
EOF
```

The digests above are what `scripts/pinned_face.py` enforces, so a mismatch
here is the same failure the generators raise.

## Licence

Spleen is licensed under the BSD 2-Clause license — `LICENSE.spleen.txt` is
the upstream `LICENSE` at the pinned tag, retained as its clause 1 requires,
and the BDF additionally embeds the copyright in its own `COMMENT` header.
The transcribed Rust table is a redistribution in binary form, which clause 2
covers with the same retain-the-notice condition; this directory satisfies it.

Source Code Pro is licensed under the SIL Open Font License 1.1, whose clause 2
permits bundling and redistributing original or modified versions with any
software "provided that each copy contains the above copyright notice and this
license". `LICENSE.md` in this directory is that notice plus the full licence
text, taken from the upstream repository at the pinned tag; each vendored OTF
also carries the licence and its Adobe copyright in its own `name` table.

Neither face is modified here — the generators only rasterise them — and the
generated Rust tables are bitmaps embedded in firmware, which the same clause
covers under "use, study, copy, merge, embed". No reserved font name (`Source`)
is applied to anything in this repository.

## Rasteriser versions

The pin covers the *inputs*, not the rasteriser. `gen_font.py` has no
rasteriser at all since § 428 — the text table is a pure bit transcription of
the BDF, reproducible by construction on any machine. The rest applies to
`gen_bignum.py` only. The committed numeral tables were last confirmed to
regenerate byte-for-byte with:

- ImageMagick 7.1.2-26 Q16-HDRI (aarch64, macOS)
- Python 3.14

`src/icons.rs` has no font dependency — its inputs are the SVGs vendored under
`icons/` — but `scripts/gen_icons.py` additionally needs Inkscape on `PATH`, and
that rasteriser is *not* pinned. Treat an icon-table diff on a machine with a
different Inkscape the same way: review the pixels, don't assume the change was
the one you meant.
