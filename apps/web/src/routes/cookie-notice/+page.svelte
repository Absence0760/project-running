<script lang="ts">
	const lastUpdated = '2026-05-15';
</script>

<svelte:head>
	<title>Cookie Notice — Run Onward</title>
	<meta name="description" content="What cookies and similar technologies Run Onward uses and why." />
</svelte:head>

<div class="legal-page">
	<div class="draft-banner">
		<strong>Draft.</strong> This Cookie Notice is published as a placeholder. The list below is
		generated from the codebase and is accurate at the date stamped on the page, but the legal
		wording has not been reviewed by counsel.
	</div>

	<h1>Cookie Notice</h1>
	<p class="lead">
		Run Onward uses a small number of cookies and similar technologies. Most are strictly
		necessary; the rest are off by default and load only after you opt in.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Strictly necessary</h2>
	<p>
		These load unconditionally because the site cannot function without them. They do not
		require consent under EU ePrivacy.
	</p>
	<table>
		<thead>
			<tr><th>Name</th><th>Provider</th><th>Purpose</th><th>Lifetime</th></tr>
		</thead>
		<tbody>
			<tr><td>sb-access-token / sb-refresh-token</td><td>Supabase Auth</td><td>Authentication session</td><td>1 hour / 30 days</td></tr>
			<tr><td>theme</td><td>Run Onward (localStorage)</td><td>Light/dark mode preference</td><td>Persistent</td></tr>
			<tr><td>sidebar_collapsed</td><td>Run Onward (localStorage)</td><td>Sidebar collapse state</td><td>Persistent</td></tr>
		</tbody>
	</table>

	<h2>2. Functional, on consent</h2>
	<p>These load only after you accept them via the consent banner.</p>
	<table>
		<thead>
			<tr><th>Name</th><th>Provider</th><th>Purpose</th><th>Lifetime</th></tr>
		</thead>
		<tbody>
			<tr><td>sentry-trace, baggage</td><td>Sentry</td><td>Error monitoring + performance traces</td><td>Per-request</td></tr>
			<tr><td>cookie_consent</td><td>Run Onward (localStorage)</td><td>Remembers your consent choice</td><td>12 months</td></tr>
		</tbody>
	</table>

	<h2>3. Third-party services that load on-page</h2>
	<p>
		The following third-party services may set their own cookies or log your IP address when the
		page makes a request to them. We disclose them here even though they're not all "cookies" in
		the strict sense:
	</p>
	<ul>
		<li>
			<strong>MapTiler</strong> — every map tile fetch logs the requesting IP. We treat tile
			fetches as strictly necessary on map screens (run detail, route detail, route builder,
			live spectator); the map cannot render without them.
		</li>
		<li>
			<strong>Anthropic / OpenAI</strong> — only fires when you open the AI Coach. The
			request includes prompt text + recent training data.
		</li>
		<li>
			<strong>Supabase Storage (signed URLs)</strong> — every track preview or photo fetch
			generates a short-TTL signed URL. The TTL is short enough that the URL is not a
			persistent identifier.
		</li>
	</ul>

	<h2>4. Your choices</h2>
	<ul>
		<li>
			<strong>Manage consent.</strong> Use the "Cookie settings" link in the footer to change
			your choices at any time.
		</li>
		<li>
			<strong>Block cookies in your browser.</strong> Most browsers let you reject cookies
			from a specific site. Strictly-necessary cookies cannot be blocked without breaking
			authentication.
		</li>
		<li>
			<strong>Browser-level "Do Not Track".</strong> We do not currently honour DNT because it
			has no consistent meaning across browsers. Use the consent banner instead.
		</li>
	</ul>

	<h2>5. Contact</h2>
	<p>
		Privacy questions: <a href="mailto:privacy@runonward.com">privacy@runonward.com</a>.
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		line-height: 1.6;
	}
	.draft-banner {
		background: var(--color-warning-bg, #fff3cd);
		color: var(--color-warning-text, #664d03);
		border: 1px solid var(--color-warning-border, #ffecb5);
		border-radius: var(--radius-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-2xl);
	}
	h1 {
		margin-top: 0;
	}
	h2 {
		margin-top: var(--space-2xl);
		font-size: 1.25rem;
	}
	.lead {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.meta {
		color: var(--color-text-tertiary);
		font-size: 0.875rem;
		margin-bottom: var(--space-2xl);
	}
	ul {
		padding-inline-start: 1.25rem;
	}
	li {
		margin-bottom: var(--space-xs);
	}
	table {
		width: 100%;
		border-collapse: collapse;
		margin: var(--space-md) 0;
	}
	th,
	td {
		text-align: start;
		padding: var(--space-xs) var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	th {
		background: var(--color-bg-elev-1);
		font-weight: 600;
	}
</style>
