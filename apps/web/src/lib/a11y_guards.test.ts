// WCAG guards over the shell and the shared surfaces: the focus contract on
// the popovers, the accessible names on the canvas-rendered charts and
// maps, one h1 per page, the reduced-motion net, the skip link, the live
// regions a toast announces from, and the labels on the sign-in fields.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

function readFileSyncDeps(): { readdirSync: typeof readdirSync } {
	return { readdirSync };
}

const __dirname = dirname(fileURLToPath(import.meta.url));

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

function extractSvelteMarkup(src: string): string {
	const kept: string[] = [];
	let inBlock: 'script' | 'style' | null = null;
	for (const line of src.split('\n')) {
		const lower = line.toLowerCase();
		if (inBlock) {
			if (lower.includes(`</${inBlock}`)) inBlock = null;
			continue;
		}
		if (lower.includes('<script')) {
			if (!lower.includes('</script')) inBlock = 'script';
			continue;
		}
		if (lower.includes('<style')) {
			if (!lower.includes('</style')) inBlock = 'style';
			continue;
		}
		kept.push(line);
	}
	return kept.join('\n');
}

test('accessibility: sidebar profile popover has focus trap + ESC close + focus return', () => {
	// Reason: audit/accessibility High — WCAG 2.1.2 (No Keyboard
	// Trap, paradoxically — the prior version let Tab escape the
	// popover leaving the user stranded in the page behind it
	// without a keyboard close path) + 2.4.3 (Focus Order). Pin
	// the focus-management wiring.
	const src = read('src/routes/+layout.svelte');
	assert.match(
		src,
		/bind:this={popoverEl}/,
		'popover must bind a ref so the focus trap + first-focus logic ' +
			'can find its DOM node.',
	);
	assert.match(
		src,
		/bind:this={profileBtnEl}/,
		'profile-btn must bind a ref so focus can return on close.',
	);
	assert.match(
		src,
		/if\s*\(e\.key\s*===\s*['"]Escape['"]/,
		'popover effect must wire an Escape key handler.',
	);
	assert.match(
		src,
		/if\s*\(e\.key\s*!==\s*['"]Tab['"]/,
		'popover effect must wire a Tab-trap handler.',
	);
	assert.match(
		src,
		/aria-label=\{m\('shell\.accountMenu'\)\}/,
		'popover root must carry an aria-label (now via the i18n key ' +
			'shell.accountMenu) so screen readers announce the menu region.',
	);
	const en = read('src/lib/i18n/locales/en.ts');
	assert.match(
		en,
		/'shell\.accountMenu':\s*'Account menu'/,
		'shell.accountMenu copy must still name the account menu region.',
	);
});

test('accessibility: chart svgs + map canvas carry role + aria-label', () => {
	// Reason: audit/accessibility Medium — WCAG 1.1.1. Without
	// role + aria-label, screen readers traverse every SVG child
	// individually (rects on heatmap, paths on train-load chart)
	// and have no name for the maplibre canvas at all. Pin each
	// surface's labelled-landmark wrapper.
	const train = read('src/lib/components/TrainingLoadChart.svelte');
	const map = read('src/lib/components/RunMap.svelte');
	// TrainingLoadChart + RunMap had their accessible names extracted into
	// the i18n catalogue, so assert the labelled-landmark wiring (via the
	// m()/t() key) plus the English copy that names each. CalendarHeatmap
	// was the third surface here until round 11 deleted it — `/dashboard`
	// retired that card in favour of the Training intensity card, so the
	// component had no route and its only reader was this guard.
	const en = read('src/lib/i18n/locales/en.ts');
	assert.match(
		train,
		/<svg[^>]*role="img"[^>]*aria-label=\{t\('trainingLoad\.chartAriaLabel'\)\}/s,
		'TrainingLoadChart.svelte <svg> must carry role="img" + an ' +
			'aria-label that names the chart.',
	);
	assert.match(
		en,
		/"trainingLoad\.chartAriaLabel":\s*"Training load chart/,
		'trainingLoad.chartAriaLabel copy must name the training-load chart.',
	);
	// Read the wrapper's opening TAG and assert the two properties inside it,
	// rather than one canonical spelling of the whole line: the element gained
	// four `style:--map-*` bindings when map overlay paint began resolving off
	// the basemap, which split it across lines and broke a regex that had
	// pinned the formatting. A guard on a spelling fails on a reformat; a guard
	// on the property fails only when the property goes.
	const wrapperTag = map.match(/<div[^>]*class="run-map-wrapper"[^>]*>/);
	assert.ok(
		wrapperTag,
		'RunMap.svelte must wrap the map in a .run-map-wrapper element.',
	);
	assert.match(
		wrapperTag![0],
		/role="region"/,
		'RunMap.svelte wrapper must carry role="region" so AT users can skip past it or into it.',
	);
	assert.match(
		wrapperTag![0],
		/aria-label=\{m\('runMap\.regionLabel'\)\}/,
		'RunMap.svelte wrapper must carry aria-label={m(\'runMap.regionLabel\')}.',
	);
	assert.match(
		en,
		/"runMap\.regionLabel":\s*"Run map"/,
		'runMap.regionLabel copy must name the run map region.',
	);
});

test(
	'accessibility: every :focus{outline:none} SELECTOR pairs ' +
		':focus-visible (WCAG 2.4.7 + 2.4.11)',
	() => {
		// Reason: audit/accessibility High — bulk-removing the browser
		// focus ring without giving keyboard users a replacement
		// indicator violates WCAG 2.4.7 (Focus Visible) + 2.4.11
		// (Focus Appearance).
		//
		// Self-audit round 6 strengthens this from "file references
		// :focus-visible somewhere" to "every <sel>:focus{outline:none}
		// has a matching <sel>:focus-visible". The weaker form let
		// routes/+page.svelte ship with .search-input:focus suppressing
		// the outline while only OTHER selectors in the same file
		// (.star-btn, .toolbar-select) had companions.
		const { readdirSync } = readFileSyncDeps();
		const root = resolve(__dirname, '..', '..', 'src');
		const walk = (dir: string, out: string[] = []): string[] => {
			for (const ent of readdirSync(dir, { withFileTypes: true })) {
				const full = `${dir}/${ent.name}`;
				if (ent.isDirectory()) walk(full, out);
				else if (ent.name.endsWith('.svelte')) out.push(full);
			}
			return out;
		};
		const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '');
		const focusRule = /([^{}]+?:focus)\s*\{\s*[^}]*outline\s*:\s*none[^}]*\}/g;
		const fvRule = /([^{}]+?:focus-visible)\s*\{/g;
		const baseOf = (sel: string, suffix: string): string[] =>
			sel
				.split(',')
				.map((s) => s.trim())
				.filter((s) => s.endsWith(suffix))
				.map((s) => s.slice(0, -suffix.length).trim());
		const offenders: string[] = [];
		for (const f of walk(root)) {
			const body = stripComments(readFileSync(f, 'utf-8'));
			const focusSelectors = new Set<string>();
			let m: RegExpExecArray | null;
			focusRule.lastIndex = 0;
			while ((m = focusRule.exec(body)) !== null) {
				for (const b of baseOf(m[1], ':focus')) focusSelectors.add(b);
			}
			if (focusSelectors.size === 0) continue;
			const pairedSelectors = new Set<string>();
			fvRule.lastIndex = 0;
			while ((m = fvRule.exec(body)) !== null) {
				for (const b of baseOf(m[1], ':focus-visible'))
					pairedSelectors.add(b);
			}
			const unpaired = [...focusSelectors].filter((s) => !pairedSelectors.has(s));
			if (unpaired.length > 0) {
				const rel = f.replace(resolve(__dirname, '..', '..') + '/', '');
				offenders.push(`${rel}: ${unpaired.map((s) => `${s}:focus`).join(', ')}`);
			}
		}
		assert.deepEqual(
			offenders,
			[],
			'these selectors suppress :focus outline without a matching ' +
				':focus-visible companion:\n  ' +
				offenders.join('\n  '),
		);
	},
);

test('accessibility: every top-level page renders an h1 (WCAG 1.3.1 + 2.4.6)', () => {
	// Reason: audit/accessibility High — Dashboard / Runs / Coach
	// had no h1, so a screen-reader user navigating by headings
	// couldn't identify which route they were on. visually-hidden
	// h1s preserve the visual design while giving the heading-by-
	// headings flow an anchor.
	// The h1 text was extracted into the i18n catalogue, so assert each
	// page renders a visually-hidden h1 bound to its heading key AND the
	// English copy still names the route. Same heading-by-headings anchor.
	const en = read('src/lib/i18n/locales/en.ts');
	for (const [path, key, expectedText] of [
		['src/routes/dashboard/+page.svelte', 'dash.pageHeading', 'Dashboard'],
		// /history is the unified cross-modal timeline; the dedicated
		// run-list page moved to /runs in the §63-amendment restructure.
		['src/routes/history/+page.svelte', 'history.timelineHeading', 'History'],
		['src/routes/runs/+page.svelte', 'history.heading', 'Run history'],
		['src/routes/coach/+page.svelte', 'coachPage.h1', 'AI Coach'],
	] as const) {
		const src = read(path);
		assert.match(
			src,
			new RegExp(
				`<h1\\s+class="visually-hidden">\\{m\\('${key.replace('.', '\\.')}'\\)\\}</h1>`,
			),
			`${path} must render a visually-hidden h1 bound to m('${key}')`,
		);
		assert.match(
			en,
			new RegExp(`"${key.replace('.', '\\.')}":\\s*"${expectedText}"`),
			`${key} copy must name the route ("${expectedText}")`,
		);
	}
});

test('accessibility: app.css carries a prefers-reduced-motion safety net', () => {
	// Reason: audit/accessibility High — WCAG 2.3.3 / EU EAA. Page-
	// level components do their own reduced-motion handling, but a
	// global * { animation-duration: 0.01ms } catch-all covers
	// future animations the dev forgets to gate. Pin the rule so
	// it can't disappear in a refactor.
	const css = read('src/app.css');
	assert.match(
		css,
		/@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{[\s\S]*?\*[\s\S]*?animation-duration:\s*0\.01ms[\s\S]*?transition-duration:\s*0\.01ms/,
		'app.css must carry a global prefers-reduced-motion safety net ' +
			'that sets animation-duration + transition-duration to 0.01ms ' +
			'on the universal selector.',
	);
});

test('accessibility: web shell wires WCAG 2.4.1 skip link + #main-content target', () => {
	// Reason: audit/accessibility High (May 2026). Keyboard users
	// had to Tab through 5 sidebar items before reaching page
	// content on every load. Pin the skip-link wiring.
	const layout = read('src/routes/+layout.svelte');
	const css = read('src/app.css');
	assert.match(
		layout,
		/<a\s+href="#main-content"\s+class="skip-link">/,
		'+layout.svelte must render a `Skip to main content` link as the ' +
			'first element above the sidebar (WCAG 2.4.1).',
	);
	assert.match(
		layout,
		/<main\s+id="main-content"/,
		'+layout.svelte <main> must carry id="main-content" so the skip ' +
			"link's anchor resolves.",
	);
	assert.match(
		css,
		/\.skip-link\s*\{[\s\S]*?:focus[\s\S]*?translateY/,
		'app.css must style .skip-link as visually-hidden-until-focused ' +
			'(translateY transform on :focus).',
	);
});

// Keep only the lines OUTSIDE a component's script and style blocks, so a
// source guard reads the template and never script text. Deliberately a
// line-wise scan rather than a strip-the-tags replace: a Svelte 5 component may
// carry both `<script module>` and `<script>`, a closing tag may be written
// `</script >`, and the replace shape is a sanitiser CodeQL rightly refuses to
// believe is complete. Nothing here is sanitisation — the input is a file in
// this repo and the result is only ever matched against, never rendered.

test('accessibility: ToastContainer announces from permanently-mounted live regions', () => {
	// Reason: audit/accessibility High — toasts went unannounced because the
	// container had no aria-live region at all. The first fix added one, but
	// mounted it in the same `{#if}` as the toast: a live region only announces
	// changes made INSIDE it while it is already in the accessibility tree, so
	// region and text arriving in one mutation left the first toast of a burst
	// — one toast at a time, the ordinary case — announced by nothing.
	//
	// Both regions must therefore sit OUTSIDE every `{#if}`. They must also BE
	// the visible stacks rather than hidden mirrors of them: a mirror announces
	// correctly and puts the same sentence in the DOM twice, which makes every
	// `getByText('<toast text>')` in the e2e suite a strict-mode violation.
	const src = read('src/lib/components/ToastContainer.svelte');
	const markup = extractSvelteMarkup(src);

	for (const politeness of ['polite', 'assertive']) {
		assert.match(
			markup,
			new RegExp(`aria-live="${politeness}"`),
			`ToastContainer must carry an aria-live="${politeness}" region.`,
		);
	}

	const firstIf = markup.indexOf('{#if');
	if (firstIf >= 0) {
		for (const politeness of ['polite', 'assertive']) {
			assert.ok(
				markup.indexOf(`aria-live="${politeness}"`) < firstIf,
				`The aria-live="${politeness}" region must be mounted unconditionally — a region ` +
					'that appears together with its text announces nothing.',
			);
		}
	}

	// The message renders once. Two `{#each}` blocks over the toast list, one
	// per politeness, and no separate hidden copy of the text.
	assert.equal(
		(markup.match(/\{#each/g) ?? []).length,
		2,
		'ToastContainer must render each toast exactly once, in the stack matching ' +
			'its politeness — a second copy for the announcer duplicates the message.',
	);
	assert.doesNotMatch(
		markup,
		/aria-hidden/,
		'Nothing in ToastContainer may be aria-hidden: the announcing region IS the ' +
			'visible stack, so hiding it would silence the toast rather than de-duplicate it.',
	);
	assert.doesNotMatch(
		markup,
		/class="visually-hidden"/,
		'The announcer must not be a visually-hidden mirror of the visible stack — ' +
			'that duplicates the sentence in the DOM (see decisions.md § 736).',
	);
});

test('accessibility: login inputs carry programmatically associated labels', () => {
	// Reason: audit/accessibility High — the email + password inputs
	// used `placeholder` only, which disappears as the user types
	// and screen readers announce just "edit text". Visually-hidden
	// <label for> is the most-compatible WCAG 3.3.2 + 1.3.1 fix.
	const src = read('src/routes/login/+page.svelte');
	for (const id of ['login-email', 'login-password']) {
		assert.match(
			src,
			new RegExp(`<label\\s+for="${id}"[^>]*>`),
			`login page must declare a <label for="${id}"> so the input ` +
				'has a programmatically associated name.',
		);
		assert.match(
			src,
			new RegExp(`id="${id}"`),
			`login page input must carry id="${id}" matching its label.`,
		);
	}
});
