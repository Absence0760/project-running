<script lang="ts">
	/// Reusable `<svelte:head>` block for the public, indexable surfaces
	/// (landing + marketing pages). Centralises the title / description /
	/// canonical / Open Graph / Twitter-card / JSON-LD shape that was
	/// previously hand-rolled per page — which is how the landing page
	/// drifted to title-only. Per-entity share pages keep their own
	/// inline heads because their production path is a Lambda that
	/// injects the same tags server-side (share_run_meta.ts et al.); this
	/// component is for the prerendered pages that render their head in
	/// the browser only.
	///
	/// `jsonLd` entries must already be escaped for the script-element
	/// context (use the builders in site_meta.ts / share_meta.ts, which
	/// run escapeJsonLd) — they're injected via {@html} because a literal
	/// <script> in Svelte markup would be hoisted and compiled away.

	interface Props {
		title: string;
		description: string;
		/// Absolute canonical URL. Omit only on a page that genuinely has
		/// no single canonical home (rare) — every indexable page should
		/// set one so the www/apex duplicate can't split ranking signal.
		canonical?: string;
		/// og:image / twitter:image. Absolute or root-relative (crawlers
		/// resolve root-relative against the request origin). Defaults to
		/// the 1200x630 branded card.
		image?: string;
		ogType?: 'website' | 'article' | 'profile';
		/// One or more pre-escaped JSON-LD payload strings.
		jsonLd?: string | string[];
	}

	let {
		title,
		description,
		canonical,
		image = '/og-default.png',
		ogType = 'website',
		jsonLd,
	}: Props = $props();

	const jsonLdList = $derived(
		jsonLd == null ? [] : Array.isArray(jsonLd) ? jsonLd : [jsonLd],
	);
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	{#if canonical}
		<link rel="canonical" href={canonical} />
	{/if}
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content={ogType} />
	{#if canonical}
		<meta property="og:url" content={canonical} />
	{/if}
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content={image} />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content={image} />
	{#each jsonLdList as payload}
		{@html `<script type="application/ld+json">${payload}</script>`}
	{/each}
</svelte:head>
