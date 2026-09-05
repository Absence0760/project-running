/// The one strip-then-splice pipeline every share Lambda's `<head>` injector
/// composes. Four injectors used to carry their own copy of it -- three of them
/// byte-identical down to the comment wording -- which is why decisions § 1086
/// had to fix the same two parser bugs in the same regexes three separate
/// times, and why the fourth copy having drifted (share_recap strips two of the
/// four signals) was not detectable as drift at all.
///
/// Deliberately NOT one do-everything `injectHead`: the recap head emits no
/// JSON-LD block, and neither does the badge head that reuses the run
/// injector, so a pipeline that always stripped it would delete the shell's
/// own WebSite node from those pages and put nothing back. Each injector names
/// the signals its own head replaces, and strips exactly those -- which for
/// the run injector is a per-call answer, because `ShareRunMeta.jsonLd` is
/// optional.

export type HeadSignal = 'title' | 'social' | 'canonical' | 'jsonLd';

/// Applied in this order whatever order a caller names them in, so two
/// injectors selecting the same signals cannot produce different bytes.
const STRIP_ORDER: readonly HeadSignal[] = ['title', 'social', 'canonical', 'jsonLd'];

/// An end tag closes at `</script` followed by whitespace, `/` or `>`, then
/// junk up to the first `>` (js/bad-tag-filter): against `</script >` a
/// `<\/script>` close does not stop there, so the lazy body runs on to the NEXT
/// `</script>` in the document -- the SPA bundle's -- and takes `</head>`, the
/// mount div and the bundle tag with it, at which point the splice finds no
/// head and returns the wreckage unmeta'd. `</title>` and `</head>` are spelled
/// the same way for the same reason. The JSON-LD OPEN tag is any `<script>`
/// carrying the ld+json type rather than one exact attribute spelling, so a
/// nonce or a reordered attribute cannot leave a stale block standing.
const SOURCES: Readonly<Record<HeadSignal, string>> = {
	title: String.raw`<title(?=[\s/>])[^>]*>[\s\S]*?<\/title(?=[\s/>])[^>]*>`,
	social: String.raw`<meta\s+(?:property|name)="(?:og:[^"]+|twitter:[^"]+|description)"[^>]*>`,
	canonical: String.raw`<link\s+rel="canonical"[^>]*>`,
	jsonLd: String.raw`<script(?=[\s/>])[^>]*\stype="application\/ld\+json"[^>]*>[\s\S]*?<\/script(?=[\s/>])[^>]*>`,
};

const HEAD_CLOSE = /<\/head(?=[\s/>])[^>]*>/i;

function all(signal: HeadSignal): RegExp {
	return new RegExp(SOURCES[signal], 'gi');
}

export function stripStaleHeadSignals(html: string, signals: readonly HeadSignal[]): string {
	let out = html;
	for (const signal of STRIP_ORDER) {
		if (!signals.includes(signal)) continue;
		if (signal === 'title') {
			// The FIRST only: the injected head supplies the one that wins, and a
			// shell arriving with two is a defect to report rather than one to
			// absorb silently.
			out = out.replace(new RegExp(SOURCES.title, 'i'), '');
			continue;
		}
		// ONE global pass, never repeated to a fixpoint. A global replace already
		// consumes every leftmost non-overlapping match the input contains, so a
		// second pass can only match text that became adjacent when the first
		// deleted something -- a block the document never carried. The JSON-LD
		// strip did loop, to stop an overlapping `<script ...><script>` leaving a
		// residual; it never could, and the loop instead deleted `</head>`, the
		// mount div and the bundle tag out of a head holding `<scr` before a block
		// and `ipt type="application/ld+json">` after it. See decisions § 1192.
		out = out.replace(all(signal), '');
	}
	return out;
}

/// Returns the document unchanged when it carries no `</head>`. A malformed
/// shell is not somewhere to synthesise a head wrapper that might not match the
/// SvelteKit shape -- the caller's caching + monitoring catches that case, and
/// `notFoundShell` handles the one path where answering without the tags would
/// be worse than answering nothing at all.
export function spliceIntoHead(html: string, headTags: string): string {
	const insertedAt = html.search(HEAD_CLOSE);
	if (insertedAt === -1) return html;
	return html.slice(0, insertedAt) + headTags + '\n' + html.slice(insertedAt);
}

/// What a document actually carries, counted with the SAME patterns the strips
/// use. Shared rather than restated so the shell guard
/// (spa_shell_head_signals.test.ts) cannot measure something other than what
/// the injectors act on: a guard carrying its own second spelling of these
/// regexes would report a shell as clean while a strip still found work in it.
export function countHeadSignals(html: string): Record<HeadSignal, number> {
	const counts = {} as Record<HeadSignal, number>;
	for (const signal of STRIP_ORDER) counts[signal] = (html.match(all(signal)) ?? []).length;
	return counts;
}
