/**
 * Canonical serialisation for a JSON-LD graph destined for a
 * `<script type="application/ld+json">` element.
 *
 * The escape is JSON's own `\uXXXX` form and deliberately NOT
 * `html_escape.ts`'s entity form: a `<script>` is a raw-text element, so the
 * HTML parser does not decode entity references inside it. `&lt;` would reach
 * the JSON parser as those four characters and land inside the value, which
 * corrupts the data without making it any safer. `<` is the one escape
 * both parsers agree on.
 *
 * `<` is the character that matters: it is what lets a value spelling
 * `</script>` terminate the element early, and what lets `<!--` switch the
 * tokenizer into the script-data-escaped state where the close tag is read
 * differently again. `>` and `&` are unreachable by either route once `<` is
 * gone; they are escaped anyway so the same payload stays inert in an XHTML
 * document, where script content is parsed as character data.
 *
 * Serialising and escaping are one function because they are one step. The
 * twelve call sites this replaced each spelled `escapeJsonLd(JSON.stringify(
 * graph))` over a private copy of the escape, and a thirteenth that
 * stringified and forgot would be an injection with no local sign of one.
 */
export function serialiseJsonLd(graph: Record<string, unknown>): string {
	return JSON.stringify(graph)
		.replace(/</g, '\\u003c')
		.replace(/>/g, '\\u003e')
		.replace(/&/g, '\\u0026');
}
