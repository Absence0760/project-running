#!/usr/bin/env python3
"""fontTools half of scripts/gen_web_icon_font.mjs. Two modes, one font.

`vocabulary` dumps every ligature TEXT the upstream Material Symbols font can
render, one per line. That list is the thing the Node side needs and the thing
no shipped metadata provides: the package's `index.d.ts` omits every alias whose
ligature resolves to a differently-named glyph (`terrain` -> `landscape`), so it
is short by the twelve names this app happens to use plus ~370 more.

Reading it means walking GSUB by hand for two reasons. The icon ligatures sit
under `rlig`/`rclt` inside Extension (type 7) lookups, so the subtables have to
be unwrapped; and a ligature's components are GLYPH names (`a`, `underscore`),
so the text is recovered through a reverse cmap that is deliberately restricted
to the ligature alphabet -- the font maps `A` and `a` to one glyph, and taking
whichever codepoint came first yields `EXPAND_MORE`.

`subset` pins the axes it is given, keeps the glyphs the named ligatures resolve
to, and re-checks the result: every requested name must still substitute in the
output, or the subset is rejected rather than shipped. Subsetting runs with
layout closure OFF because the closure is over-eager in exactly the wrong
direction here -- the ligature components are the lowercase alphabet, which is
retained, so every one of the 4271 ligatures would be pulled back in.
"""

import json
import os
import sys
import tempfile

from fontTools.ttLib import TTFont
from fontTools.subset import Options, Subsetter
from fontTools.varLib.instancer import instantiateVariableFont

LIGATURE_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789_"


def ligature_texts(font):
    """{ligature text: output glyph name} for every ligature in GSUB."""
    alphabet = {ord(c) for c in LIGATURE_ALPHABET}
    reverse = {}
    for codepoint, glyph in font.getBestCmap().items():
        if codepoint in alphabet:
            reverse[glyph] = codepoint

    out = {}

    def visit(subtable):
        extension = getattr(subtable, "ExtSubTable", None)
        if extension is not None:
            visit(extension)
            return
        ligatures = getattr(subtable, "ligatures", None)
        if not ligatures:
            return
        for first, entries in ligatures.items():
            for lig in entries:
                components = [first] + list(lig.Component)
                try:
                    text = "".join(chr(reverse[c]) for c in components)
                except KeyError:
                    continue
                out[text] = lig.LigGlyph

    for lookup in font["GSUB"].table.LookupList.Lookup:
        for subtable in lookup.SubTable:
            visit(subtable)
    return out


def main():
    mode = sys.argv[1]
    source = sys.argv[2]

    if mode == "vocabulary":
        font = TTFont(source)
        texts = ligature_texts(font)
        with open(sys.argv[3], "w", encoding="utf-8") as handle:
            handle.write("\n".join(sorted(texts)) + "\n")
        print(json.dumps({"count": len(texts)}))
        return

    if mode != "subset":
        raise SystemExit(f"unknown mode {mode!r}")

    out_path = sys.argv[3]
    request = json.loads(open(sys.argv[4], encoding="utf-8").read())
    names = request["icons"]
    pinned = request["pinnedAxes"]
    features = request["layoutFeatures"]

    # `recalcTimestamp` off on every load: fontTools stamps `head.modified`
    # with the current time on save, so the committed artifact would differ on
    # every regeneration and its digest could vouch for nothing.
    font = TTFont(source, recalcTimestamp=False)
    texts = ligature_texts(font)
    missing = [n for n in names if n not in texts]
    if missing:
        raise SystemExit(f"upstream font cannot render: {', '.join(missing)}")

    instantiateVariableFont(font, pinned, inplace=True, updateFontNames=False)
    # Round-tripped through a file rather than subset in place: the instanced
    # font still holds the source's lazily-decompiled `gvar`, whose per-glyph
    # dict raises rather than reporting absence for a glyph that never varied
    # (`j`), and the subsetter reads it as a plain mapping.
    with tempfile.TemporaryDirectory() as scratch:
        instanced = os.path.join(scratch, "instanced.ttf")
        font.flavor = None
        font.save(instanced)
        font = TTFont(instanced, recalcTimestamp=False)

        options = Options()
        options.layout_features = list(features)
        options.layout_closure = False
        options.notdef_outline = False
        subsetter = Subsetter(options=options)
        subsetter.populate(
            glyphs=sorted({texts[n] for n in names}),
            text=LIGATURE_ALPHABET,
        )
        subsetter.subset(font)
        font.flavor = "woff2"
        font.save(out_path)

    check = ligature_texts(TTFont(out_path))
    still_missing = [n for n in names if n not in check]
    if still_missing:
        raise SystemExit(f"subset dropped: {', '.join(still_missing)}")
    print(
        json.dumps(
            {
                "requested": len(names),
                "glyphs": len({texts[n] for n in names}),
                "ligaturesInSubset": len(check),
                "axes": [a.axisTag for a in font["fvar"].axes] if "fvar" in font else [],
            }
        )
    )


if __name__ == "__main__":
    main()
