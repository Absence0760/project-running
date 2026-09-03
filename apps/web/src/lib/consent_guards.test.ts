// Nothing reaches a third party before the viewer has said yes. Each guard
// here pins one outbound hop behind its gate: the map tiles and static
// maps behind cookie consent, the fonts and the geocoder behind having no
// uncontracted hop at all, the routing proxy behind the server, and the
// Anthropic fan-out behind the versioned AI disclosure.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('track-preview thumbnails gate the MapTiler static map on consent', () => {
	// Reason: both previews render on anon surfaces (public /clubs/[slug],
	// /u/[id], feed), and MapTiler's static-map endpoint logs the requester
	// IP per fetch — an ePrivacy/GDPR third-party request before consent.
	// The MapTiler `buildStaticMapUrl` branch must sit behind a
	// `consent.accepted ?` ternary (the self-hosted local override is
	// exempt). audit/cookie-consent. The run-detail page is in the list
	// because its off-screen share-card <img> lives in the DOM (fixed,
	// top:-9999px — not display:none), so the browser fetches it on
	// every run view, not only on the Share-as-image tap.
	for (const file of [
		'src/lib/components/RouteTrackPreview.svelte',
		'src/lib/components/RunTrackPreview.svelte',
		'src/routes/runs/[id]/+page.svelte',
	]) {
		const source = read(file);
		assert.match(
			source,
			/consent\.accepted\s*\?[\s\S]*buildStaticMapUrl/,
			`${file} must gate buildStaticMapUrl behind a consent.accepted ternary — otherwise it fires a MapTiler request (logging the visitor IP) before consent on anon surfaces.`,
		);
	}
});

test('event meet-point static map gates MapTiler on consent', () => {
	// Reason: audit/cookie-consent (2026-07-02) Medium — the meet-point
	// <img> on /clubs/[slug]/events/[id] fired a MapTiler static-map
	// request for any signed-in club member before (or against) their
	// cookie-banner choice. A session is not consent under ePrivacy
	// Art 5(3); the URL must only be built once consent is recorded or
	// the member taps the Load-map placeholder.
	const source = read('src/routes/clubs/[slug]/events/[id]/+page.svelte');
	assert.match(
		source,
		/\(consent\.accepted \|\| meetMapConsented\)[\s\S]{0,200}buildStaticMarkerMapUrl/,
		'the event page must gate buildStaticMarkerMapUrl behind consent.accepted or the explicit Load-map opt-in.',
	);
	assert.doesNotMatch(
		source,
		/meetMapConsented\s*=\s*\$state\(\s*true\s*\)/,
		'meetMapConsented must not default to true — the placeholder tap is the affirmative act.',
	);
});

test('interactive MapTiler maps gate maplibregl init on consent (authed surfaces too)', () => {
	// Reason: audit/gdpr (2026-05-31) High — RunMap + PersonalHeatmap
	// initialised MapTiler on authenticated surfaces (/runs/[id],
	// /routes/[id], /runs/heatmap) without checking consent, on the
	// theory that a signed-in session is "implicit consent". That is not
	// a lawful basis under ePrivacy Art 5(3). Both components must guard
	// `new maplibregl.Map` behind a `mapConsented` flag that is seeded
	// from `hasAcceptedConsent()`, not unconditionally true.
	for (const file of [
		'src/lib/components/RunMap.svelte',
		'src/lib/components/PersonalHeatmap.svelte',
	]) {
		const source = read(file);
		assert.match(
			source,
			/hasAcceptedConsent/,
			`${file} must import + consult hasAcceptedConsent() so the map does not auto-init before the cookie banner is accepted.`,
		);
		assert.doesNotMatch(
			source,
			/\$state\(\s*true\s*\)[^\n]*mapConsented|mapConsented\s*=\s*\$state\(\s*true\s*\)/,
			`${file} must not hard-code mapConsented to true — seed it from hasAcceptedConsent() instead.`,
		);
	}
});

test('app.html + app.css do not load Google Fonts (audit/cookie-consent Critical)', () => {
	// Reason: audit/cookie-consent (May 2026) flagged that the prior
	// shape fetched the Material Symbols font from fonts.googleapis.com
	// / fonts.gstatic.com unconditionally on every page hit. EU IPs
	// reached a US sub-processor before the consent banner rendered —
	// ePrivacy Art 5(3) Critical. Self-hosted since, and since
	// decisions § 780 from a subset built by scripts/gen_web_icon_font.mjs
	// and @font-face'd by app.css against a repo-relative path — so what
	// this guard has to hold is that the src stays local, not that any
	// particular module imports any particular stylesheet.
	const stripRepeatedly = (s: string, re: RegExp): string => {
		let prev;
		let next = s;
		do {
			prev = next;
			next = prev.replace(re, '');
		} while (next !== prev);
		return next;
	};
	const stripHtmlComments = (s: string) => stripRepeatedly(s, /<!--[\s\S]*?-->/g);
	const stripCssComments = (s: string) => stripRepeatedly(s, /\/\*[\s\S]*?\*\//g);
	const layout = read('src/routes/+layout.svelte');
	const html = stripHtmlComments(read('src/app.html'));
	const css = stripCssComments(read('src/app.css'));
	for (const [name, surface] of [
		['app.html', html],
		['app.css', css],
	] as const) {
		// Extract the host of every absolute URL the file references and
		// compare with exact equality — the CodeQL-recommended shape for a
		// host check. A host-literal regex trips
		// js/regex/missing-regexp-anchor and a `.includes('host')` trips
		// js/incomplete-url-substring-sanitization; both warn about
		// *partial* host matching, which exact-equality on a parsed host
		// sidesteps entirely. The capture is a generic URL tokenizer (no
		// host literal), so it isn't itself a host-checking regex. We only
		// need to catch our own accidental authoring of an absolute Google
		// Fonts URL — protocol-relative `//host` is not a realistic
		// regression vector here.
		const hosts = new Set<string>();
		for (const m of surface.matchAll(/https?:\/\/([^/?#"'\s)]+)/gi)) {
			hosts.add(m[1].split(':')[0].toLowerCase());
		}
		assert.ok(
			!hosts.has('fonts.googleapis.com'),
			`${name} must not reference fonts.googleapis.com — ` +
				'the font is self-hosted via material-symbols (npm).',
		);
		assert.ok(
			!hosts.has('fonts.gstatic.com'),
			`${name} must not reference fonts.gstatic.com.`,
		);
	}
	assert.match(
		css,
		/@font-face\s*\{[^}]*src:\s*url\('\.\/lib\/assets\/material-symbols-subset\.woff2'\)/,
		'app.css must @font-face the self-hosted subset by a repo-relative path, so ' +
			'the .woff2 is emitted from our own origin and never fetched from a CDN.',
	);
	assert.doesNotMatch(
		layout,
		/from\s+['"]https?:/,
		'+layout.svelte must not pull the font from anywhere but the bundle.',
	);
});

test('/cookie-notice carries a Manage-cookie-preferences button wired to consent.reset', () => {
	// Reason: audit/cookie-consent (May 2026). Pre-fix the page told
	// users to use a "Cookie settings" link in the footer that did
	// not exist anywhere in the app. GDPR Art 7(3) requires withdrawal
	// to be as easy as giving consent; a missing UI is an illusory
	// right that a DPA audit would reject.
	const source = read('src/routes/cookie-notice/+page.svelte');
	assert.match(
		source,
		/consent\.reset\(\)/,
		'/cookie-notice must call consent.reset() to clear the stored choice',
	);
	assert.match(
		source,
		/data-testid="manage-cookie-preferences"/,
		'/cookie-notice must surface a manage-cookie-preferences button so ' +
			'the GDPR Art 7(3) withdrawal path has a discoverable test handle',
	);
	// Strip the <script> block so the doesNotMatch check fires on
	// rendered copy only — the comment in the script intentionally
	// references the old phrasing for history. Loop the replace + case-
	// insensitive flag so nested or upper-case <SCRIPT> tags can't slip
	// rendered copy past the guard (CodeQL js/bad-tag-filter +
	// js/incomplete-multi-character-sanitization).
	let renderedOnly = source;
	let prev;
	const scriptRe = /<script\b[\s\S]*?<\/script\s*>/gi;
	do {
		prev = renderedOnly;
		renderedOnly = prev.replace(scriptRe, '');
	} while (renderedOnly !== prev);
	assert.doesNotMatch(
		renderedOnly,
		/"Cookie settings" link in the footer/,
		"/cookie-notice rendered copy must not point users at a footer " +
			"'Cookie settings' link that does not exist " +
			'(audit/cookie-consent pre-fix wording)',
	);
});

test('route-builder OSRM traffic goes through the server-side proxy, never browser-direct', () => {
	// Reason: issue #198 (persona-hunt route-builder review, 2026-07). Pre-fix,
	// routing.ts + RouteBuilder.svelte fetched the OSRM host straight from the
	// browser over PUBLIC_OSRM_URL, so a user's pin coordinates (routinely
	// their home) left the client with no server boundary — the exact exposure
	// the GraphHopper hop closed on the generate path. The OSRM base is now
	// server-only (`OSRM_URL`), and every client call rides the
	// /api/routes/osrm proxy via osrmProxyFetch.
	const source = read('src/lib/routes/routing.ts');
	assert.doesNotMatch(
		source,
		/PUBLIC_OSRM_URL|\$env\/dynamic\/public|router\.project-osrm\.org/,
		'routing.ts must not read a PUBLIC_ OSRM env or reference the OSRM ' +
			'host/demo — the browser only ever talks to /api/routes/osrm.',
	);
	assert.match(
		source,
		/OSRM_PROXY_BASE = '\/api\/routes\/osrm'/,
		'routing.ts must route through the /api/routes/osrm proxy base.',
	);
	for (const fn of ['snapToRoad', 'fetchRoute', 'fetchFullRoute']) {
		const body = source.match(
			new RegExp(`async function ${fn}\\b[\\s\\S]*?\\n\\}`),
		)?.[0];
		assert.ok(body, `routing.ts missing function ${fn}`);
		assert.match(
			body!,
			/osrmProxyFetch\(/,
			`${fn} must issue its OSRM call through osrmProxyFetch — a bare ` +
				'fetch() here reopens the browser-direct coordinate leak.',
		);
	}

	// RouteBuilder.svelte builds OSRM paths inline (custom retry + batching +
	// radius / version cancellation) instead of going through the helper
	// functions — both inline call sites (snapWaypointsToRoads +
	// recalculateRoute's fetchSegment) must ride the proxy too.
	const rb = read('src/lib/components/RouteBuilder.svelte');
	assert.doesNotMatch(
		rb,
		/OSRM_BASE_URL|PUBLIC_OSRM_URL|router\.project-osrm\.org/,
		'RouteBuilder.svelte must not reference the OSRM host directly.',
	);
	const rbMatches = rb.match(/osrmProxyFetch\(/g) ?? [];
	assert.ok(
		rbMatches.length >= 2,
		'RouteBuilder.svelte must call osrmProxyFetch() at each OSRM-fetch ' +
			'entry point (snapWaypointsToRoads + recalculateRoute). Found ' +
			rbMatches.length +
			' call sites.',
	);

	// The demo fallback now lives server-side and is dev-only: the proxy core
	// must gate it on allowDemoFallback, and the production Lambda must pin
	// that gate to false so an unset OSRM_URL can never ship waypoints to the
	// uncontracted community endpoint (GDPR Art 28 — no DPA).
	const handler = read('src/lib/routes/osrm_proxy/handler.ts');
	assert.match(
		handler,
		/config\.allowDemoFallback \? OSRM_DEMO_URL : undefined/,
		'osrm_proxy handler must only use the demo URL behind allowDemoFallback.',
	);
	const lambda = read('lambda/osrm-proxy/src/index.ts');
	assert.match(
		lambda,
		/allowDemoFallback: false/,
		'The osrm-proxy Lambda must hard-code allowDemoFallback: false.',
	);
});

test('MapTiler tile fetches on anon public pages are gated on consent', () => {
	// Reason: audit/cookie-consent (2026-05-25). MapTiler logs the
	// requester IP per tile fetch. /live/[id], /share/route/[id], and
	// /share/run/[id] are anon-accessible — the visitor's IP must
	// not reach MapTiler until they have either accepted the cookie
	// banner or tapped "Load map" on the placeholder.
	const liveSrc = read('src/routes/live/[id]/+page.svelte');
	assert.match(
		liveSrc,
		/hasAcceptedConsent\(\)/,
		'/live/[id] must consult hasAcceptedConsent() before auto-mounting the map.',
	);
	assert.match(
		liveSrc,
		/{#if mapConsented}/,
		'/live/[id] must conditionally render the map container so the ' +
			'MapTiler init only fires after consent.',
	);
	assert.match(
		liveSrc,
		/onclick={loadMapNow}/,
		'/live/[id] must offer a "Load map" button that flips mapConsented.',
	);

	const runMapSrc = read('src/lib/components/RunMap.svelte');
	assert.match(
		runMapSrc,
		/requireExplicitConsent\?:\s*boolean/,
		'RunMap must expose requireExplicitConsent so anon callers can gate map init.',
	);
	assert.match(
		runMapSrc,
		/if \(!mapConsented\) return;/,
		'RunMap.onMount must short-circuit when consent is pending — no maplibregl.Map() until the user opts in.',
	);

	// The two share surfaces must pass the consent-required prop.
	const routeShareSrc = read('src/routes/share/route/[id]/+page.svelte');
	assert.match(
		routeShareSrc,
		/<RunMap[^>]*requireExplicitConsent/,
		'/share/route/[id] must pass requireExplicitConsent to RunMap.',
	);
	const runShareSrc = read('src/lib/components/RunShareView.svelte');
	assert.match(
		runShareSrc,
		/<RunMap[\s\S]*?requireExplicitConsent[\s\S]*?\/>/,
		'RunShareView (used by /share/run/[id]) must pass requireExplicitConsent.',
	);
});

test('Coach handler gates the Anthropic fan-out behind the versioned AI disclosure', () => {
	// Reason: audit/gdpr (2026-05-25), re-scoped by issue #734. Coach
	// forwards health-adjacent data to Anthropic (US sub-processor). Art
	// 6(1)(a) requires an affirmative consent act before the first dispatch
	// — opening /coach is not affirmative. The handler must read the
	// consent record (via the get_my_profile RPC, since neither column is
	// in the public-safe grant list — migration 20260707_001) and grade it
	// against the Coach minimum before the provider stream runs.
	const source = read('src/lib/coach/handler.ts');
	assert.match(
		source,
		/\.rpc\('get_my_profile'\)/,
		'handler.ts must call get_my_profile() to load the self row including the consent record.',
	);
	assert.match(
		source,
		/checkAiDisclosure\([\s\S]*?AI_DISCLOSURE_VERSION_COACH/,
		'handler.ts must grade the record with checkAiDisclosure at the Coach minimum version.',
	);
	assert.match(
		source,
		/return jsonError\(\s*403,\s*'Coach consent required[\s\S]*?\)/,
		'handler.ts must return 403 when the disclosure check fails — failing closed.',
	);
	// The gate must sit BEFORE any provider stream invocation. We
	// assert ordering by checking that the consent lookup appears
	// before the first `tier ===` reference (which is the start of
	// the rate-limit / provider-dispatch block).
	const consentIdx = source.indexOf("rpc('get_my_profile')");
	const tierIdx = source.indexOf('tier === ');
	assert.ok(
		consentIdx > 0 && consentIdx < tierIdx,
		'the consent lookup must precede the tier / provider dispatch.',
	);
});

test('the AI route endpoints gate on the widened disclosure, above the Coach version', () => {
	// Reason: issue #734. /api/coach/route-describe and
	// /api/coach/route-request shipped with no consent gate at all — a Pro
	// user who never accepted (or who withdrew) the AI disclosure still had
	// their typed request and location label sent to Anthropic. They must
	// require AI_DISCLOSURE_VERSION_ROUTE_AI, which is strictly above the
	// Coach version, so an old Coach-only acceptance does not satisfy them.
	const gate = read('src/lib/core/ai_disclosure.ts');
	assert.match(
		gate,
		/AI_DISCLOSURE_VERSION_ROUTE_AI\s*=\s*2/,
		'the route-AI minimum must stay above the Coach minimum.',
	);
	for (const file of [
		'src/lib/routes/route_describe/handler.ts',
		'src/lib/routes/route_request/handler.ts',
	]) {
		const source = read(file);
		assert.match(
			source,
			/gateAiDisclosure\([\s\S]*?AI_DISCLOSURE_VERSION_ROUTE_AI/,
			`${file} must gate on the widened AI disclosure before calling Anthropic.`,
		);
		// Ordering: the gate must precede the Anthropic client construction.
		const gateIdx = source.indexOf('gateAiDisclosure(');
		const anthropicIdx = source.indexOf('new Anthropic(');
		assert.ok(
			gateIdx > 0 && gateIdx < anthropicIdx,
			`${file} must run the consent gate before constructing the Anthropic client.`,
		);
		// The dev paywall bypass must not reach into the consent branch —
		// BYPASS_PAYWALL skips a billing check, not a lawful basis.
		const bypassInGate = source
			.slice(gateIdx, source.indexOf('Paywall gate', gateIdx))
			.includes('bypassPaywallEnabled');
		assert.ok(!bypassInGate, `${file} must not let bypassPaywallEnabled skip the consent gate.`);
	}
});

test('the AI route clients tell a consent gap apart from the Pro paywall', () => {
	// Reason: issue #734. Both gates answer 403 on these endpoints. A client
	// that reads the status alone shows the Pro upsell to someone whose
	// actual problem is a missing consent record — selling them something
	// that would not unlock the feature. The body's `code` is the
	// discriminator, so each client must read it.
	for (const file of [
		'src/lib/routes/route_request_client.ts',
		'src/lib/routes/route_describe_client.ts',
	]) {
		const source = read(file);
		assert.match(
			source,
			/AI_DISCLOSURE_ERROR/,
			`${file} must branch on the AI-disclosure code, not on the 403 status alone.`,
		);
	}
	// The pages must then render the consent-specific copy rather than the
	// generic failure banner.
	assert.match(
		read('src/routes/routes/new/+page.svelte'),
		/kind === 'consent'[\s\S]{0,120}aiRequestConsentRequired/,
		'/routes/new must render the consent copy for a consent denial.',
	);
	assert.match(
		read('src/routes/routes/[id]/+page.svelte'),
		/AI_DISCLOSURE_ERROR[\s\S]{0,160}describeConsentRequired/,
		'/routes/[id] must render the consent copy for a consent denial.',
	);
});

test('Nominatim fallback uses a reachable contact email (no protomaps placeholder)', () => {
	// Reason: audit/third-party-data-flows (2026-05-25). The
	// Nominatim `email=` parameter is the usage-policy contact path
	// — OSM Foundation requires a reachable address so they can
	// reach the operator on abuse / takedown. The previous value
	// (`protomaps-dev@localhost`) was a placeholder copied from a
	// different project and violates the policy.
	const source = read('src/lib/routes/geocoding_math.ts');
	assert.ok(
		!source.includes('protomaps-dev@localhost'),
		'geocoding_math.ts must not retain the protomaps-dev placeholder email.',
	);
	assert.match(
		source,
		/email:\s*'privacy@threkir\.com'/,
		'Nominatim fallback must declare privacy@threkir.com (the operator-' +
			'reachable contact alias) per OSM usage policy.',
	);
});
