<script lang="ts">
	// Third-party runtime and build-time dependencies. Rebuild this list
	// when you add a new runtime dep — the point of the page is to be
	// honest about what's running in the user's browser.
	const deps = [
		{ name: 'SvelteKit', license: 'MIT', url: 'https://github.com/sveltejs/kit' },
		{ name: 'Svelte', license: 'MIT', url: 'https://github.com/sveltejs/svelte' },
		{ name: '@supabase/supabase-js', license: 'MIT', url: 'https://github.com/supabase/supabase-js' },
		{ name: '@supabase/ssr', license: 'MIT', url: 'https://github.com/supabase/auth-helpers' },
		{ name: 'MapLibre GL JS', license: 'BSD-3-Clause', url: 'https://github.com/maplibre/maplibre-gl-js' },
		{ name: 'Anthropic SDK', license: 'MIT', url: 'https://github.com/anthropics/anthropic-sdk-typescript' },
		{ name: 'JSZip', license: 'MIT / GPL-3.0', url: 'https://github.com/Stuk/jszip' },
		{ name: 'isomorphic-dompurify', license: 'MPL-2.0', url: 'https://github.com/kkomelin/isomorphic-dompurify' },
		{ name: 'mdsvex', license: 'MIT', url: 'https://github.com/pngwn/MDsveX' },
		{ name: 'normalize.css', license: 'MIT', url: 'https://github.com/necolas/normalize.css' },
		{ name: 'unplugin-icons', license: 'MIT', url: 'https://github.com/unplugin/unplugin-icons' },
		{ name: '@iconify-json/material-symbols', license: 'Apache-2.0', url: 'https://github.com/iconify/icon-sets' },
		{ name: 'MapTiler tiles', license: 'Commercial (MapTiler Cloud)', url: 'https://www.maptiler.com/' },
	];
</script>

<div class="page">
	<header class="page-header">
		<h1>Open-source licenses</h1>
		<p class="subtitle">
			Better Runner is built on a stack of open-source projects. Each one
			below ships under a permissive licence; follow the links to read the
			full text and source.
		</p>
	</header>

	<section class="card">
		<ul class="lic-list">
			{#each deps as d}
				<li>
					<a href={d.url} target="_blank" rel="noopener noreferrer">{d.name}</a>
					<span class="lic-badge">{d.license}</span>
				</li>
			{/each}
		</ul>
	</section>

	<section class="card">
		<h2>Map data</h2>
		<p>
			Map tiles courtesy of <a
				href="https://www.maptiler.com/"
				target="_blank"
				rel="noopener noreferrer">MapTiler</a
			>, built on
			<a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer"
				>OpenStreetMap</a
			>
			data © OpenStreetMap contributors (ODbL). Route snap-to-road / trail uses
			<a href="https://project-osrm.org/" target="_blank" rel="noopener noreferrer">OSRM</a>
			(BSD-2-Clause), also backed by OSM.
		</p>
	</section>

	<section class="card">
		<h2>This project</h2>
		<p>
			Better Runner itself is a closed-source application. The open-source
			components above are used under the terms of their respective licences;
			this page is our notice of attribution.
		</p>
	</section>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 42rem;
	}
	h1 {
		font-size: 1.6rem;
		font-weight: 800;
		margin: 0 0 var(--space-xs);
	}
	h2 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0 0 0.5rem;
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
		margin: 0 0 var(--space-xl);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.25rem 1.5rem;
		margin-bottom: var(--space-md);
	}
	.card p {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
		line-height: 1.55;
		margin: 0;
	}
	.card a {
		color: var(--color-primary);
	}
	.lic-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 0.4rem;
	}
	.lic-list li {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 0.8rem;
		padding: 0.35rem 0;
		border-bottom: 1px solid var(--color-border);
	}
	.lic-list li:last-child {
		border-bottom: none;
	}
	.lic-badge {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		white-space: nowrap;
	}
</style>
