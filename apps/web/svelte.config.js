import adapter from "@sveltejs/adapter-static";
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";
import { mdsvex } from 'mdsvex';

export default defineConfig();

/** @type {() => import('@sveltejs/kit').Config} */
function defineConfig() {
	return {
		extensions: ['.svelte', '.md'],
		compilerOptions: {
			modernAst: true,
			warningFilter,
		},
		// Consult https://kit.svelte.dev/docs/integrations#preprocessors
		// for more information about preprocessors
		preprocess: [vitePreprocess(), mdsvex({ extensions: ['.md'] })],

		kit: {
			// See https://kit.svelte.dev/docs/adapters for more information about adapters.
			adapter: adapter({
				// The SPA shell, and deliberately NOT `index.html`.
				// adapter-static writes the prerendered pages first and then
				// generates the fallback, to whatever name it is given and
				// over whatever is already there -- so while this said
				// `index.html` the prerendered landing page (`+page.ts`,
				// `prerender = true`) was written to that path and then
				// replaced by a component-less shell carrying no title, no
				// canonical, no description and no JSON-LD. Measured: the
				// prerendered `/` is 14,875 bytes with all four, the shell
				// 5,784 with none.
				//
				// Three consumers name this file and all of them must name
				// THIS one, or the shell and the landing page get swapped:
				// the five share Lambdas' `build.mjs` embed it, and
				// CloudFront's 403 -> shell mapping
				// (`infra/modules/web-stack/main.tf`) serves it for every deep
				// link. `src/lib/seo/spa_shell_filename.test.ts` reads all
				// three rails and fails when they disagree. Changing the name
				// here is therefore a cross-tree change with a deploy order --
				// docs/features/seo.md § Deploying a change to the shell
				// filename. decisions § 1268, § 1269.
				fallback: "200.html",
			}),
			paths: {
				base: basePath(),
			},
			// Hash-based CSP for the one inline script SvelteKit emits (the
			// per-page hydration-data block). The site is fully prerendered
			// (adapter-static), so a nonce is impossible — a static file is
			// served byte-identical to every visitor, and a baked-in nonce
			// would be a constant, i.e. no protection. Hashes are the correct
			// mechanism for static inline scripts: SvelteKit computes the
			// SHA-256 of each inline script at build time and emits the policy
			// as a per-page `<meta http-equiv>` tag (there's no server to set a
			// header). This `<meta>` is enforced alongside the CloudFront
			// header CSP — a document must satisfy BOTH — so it is the binding
			// `script-src` layer that finally drops `'unsafe-inline'` for
			// scripts. An injected inline script has a hash absent from the
			// meta and is blocked, which is the second-layer defence
			// audit-xss M2 / decisions §70 wanted behind DOMPurify.
			//
			// Scoped to `script-src` only: `style-src` keeps `'unsafe-inline'`
			// (Svelte's `style=""` attributes can't be hash-covered, and style
			// injection is not script execution). `frame-ancestors`,
			// `object-src`, HSTS etc. stay on the CloudFront header — several
			// of those directives are ignored when delivered via `<meta>`.
			csp: {
				mode: 'hash',
				directives: {
					'script-src': ['self'],
					// MapLibre GL spawns its tile-processing Web Worker from a
					// blob: URL. Without an explicit worker-src the browser falls
					// back to script-src ('self' + hashes), blocking the blob
					// worker — every map (heatmap, run detail, route builder) then
					// renders blank. The CloudFront header CSP
					// (infra/modules/web-stack/main.tf) already allows this; the
					// <meta> CSP must match or the stricter of the two wins.
					'worker-src': ['self', 'blob:'],
				},
			},
			inlineStyleThreshold: 0,
			prerender: {
				// The per-entity share surfaces (/share/{run,route}/[id] +
				// /og/{run,route}/[id].png) are all prerender=false now — they
				// render at request time in the share-run / share-route Lambdas
				// (see decisions §104 + apps/web/lambda/share-route/README.md),
				// so the build-time prerender can never stale them. Any other
				// dynamic page reachable by crawling (e.g. /runs/[id],
				// /routes/[id], /u/[id]) has no entries() and falls through to
				// adapter-static's index.html SPA route at runtime; a hard
				// error on those unseen routes (@sveltejs/kit 2.60+) would be
				// wrong, so warn is the right severity here.
				handleUnseenRoutes: 'warn',
			},
		},
	};
}

/**
 * SvelteKit takes an empty base or one that starts with `/` and does not end
 * with one. Anything else is not rejected — it is concatenated into every URL
 * the app emits, so the whole site 404s with no error naming the cause.
 * @returns {'' | `/${string}`}
 */
function basePath() {
	const raw = (process.env.BASE_PATH ?? '').replace(/\/+$/, '');
	if (raw && !raw.startsWith('/')) {
		throw new Error(
			`BASE_PATH must be empty or start with "/" — got ${JSON.stringify(process.env.BASE_PATH)}`,
		);
	}
	return /** @type {'' | `/${string}`} */ (raw);
}

/**
 * Filter out noisy deprecation warnings from the compiled code.
 * Hopefully by svelte 5's release, this will no longer be needed.
 * @type {NonNullable<NonNullable<import('@sveltejs/kit').Config['compilerOptions']>['warningFilter']>}
 */
function warningFilter(warning) {
	const ignorePatterns = [/node_modules/, /\.svelte-kit/];
	const ignoredWarningCodes = [
		"svelte_component_deprecated",
		"slot_element_deprecated",
		"a11y_no_noninteractive_tabindex",
		"css_unused_selector",
	];
	if (
		ignorePatterns.some((pattern) => pattern.test(warning.filename ?? "")) &&
		ignoredWarningCodes.includes(warning.code)
	) {
		return false;
	}

	// Also ignore the specific warnings we're seeing
	if (ignoredWarningCodes.includes(warning.code)) {
		return false;
	}

	return true;
}
