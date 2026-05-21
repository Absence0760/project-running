<script lang="ts">
	const deps = [
		{
			name: 'SvelteKit',
			license: 'MIT',
			url: 'https://github.com/sveltejs/kit',
			fullText:
				'The MIT License (MIT)\n\nCopyright (c) the Svelte project contributors.\n\n' +
				'Permission is hereby granted, free of charge, to any person obtaining a copy of ' +
				'this software and associated documentation files (the "Software"), to deal in the ' +
				'Software without restriction, including without limitation the rights to use, copy, ' +
				'modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, ' +
				'and to permit persons to whom the Software is furnished to do so, subject to the ' +
				'inclusion of the above copyright notice and this permission notice in all copies or ' +
				'substantial portions of the Software.',
		},
		{
			name: 'Svelte',
			license: 'MIT',
			url: 'https://github.com/sveltejs/svelte',
			fullText: 'MIT License. Copyright (c) the Svelte project contributors. See upstream repository for the full text.',
		},
		{
			name: '@supabase/supabase-js',
			license: 'MIT',
			url: 'https://github.com/supabase/supabase-js',
			fullText: 'MIT License. Copyright (c) Supabase. See upstream repository for the full text.',
		},
		{
			name: '@supabase/ssr',
			license: 'MIT',
			url: 'https://github.com/supabase/auth-helpers',
			fullText: 'MIT License. Copyright (c) Supabase. See upstream repository for the full text.',
		},
		{
			name: 'MapLibre GL JS',
			license: 'BSD-3-Clause',
			url: 'https://github.com/maplibre/maplibre-gl-js',
			fullText:
				'BSD 3-Clause License. Copyright (c) the MapLibre contributors. Redistribution and ' +
				'use in source and binary forms, with or without modification, are permitted provided ' +
				'that the conditions of the BSD-3-Clause are met. See upstream repository for the full text.',
		},
		{
			name: 'Anthropic SDK',
			license: 'MIT',
			url: 'https://github.com/anthropics/anthropic-sdk-typescript',
			fullText: 'MIT License. Copyright (c) Anthropic, PBC. See upstream repository for the full text.',
		},
		{
			name: 'JSZip',
			license: 'MIT / GPL-3.0',
			url: 'https://github.com/Stuk/jszip',
			fullText: 'Dual-licensed under MIT or GPL-3.0. See upstream repository for the full text of both licenses.',
		},
		{
			name: 'isomorphic-dompurify',
			license: 'MPL-2.0',
			url: 'https://github.com/kkomelin/isomorphic-dompurify',
			fullText: 'Mozilla Public License 2.0. See upstream repository for the full text.',
		},
		{
			name: 'mdsvex',
			license: 'MIT',
			url: 'https://github.com/pngwn/MDsveX',
			fullText: 'MIT License. See upstream repository for the full text.',
		},
		{
			name: 'normalize.css',
			license: 'MIT',
			url: 'https://github.com/necolas/normalize.css',
			fullText: 'MIT License. Copyright (c) Nicolas Gallagher and Jonathan Neal. See upstream repository for the full text.',
		},
		{
			name: 'unplugin-icons',
			license: 'MIT',
			url: 'https://github.com/unplugin/unplugin-icons',
			fullText: 'MIT License. See upstream repository for the full text.',
		},
		{
			name: '@iconify-json/material-symbols',
			license: 'Apache-2.0',
			url: 'https://github.com/iconify/icon-sets',
			fullText:
				'Apache License 2.0. Material Symbols are released by Google under Apache 2.0. ' +
				'See upstream repository for the full text.',
		},
		{
			name: 'MapTiler tiles',
			license: 'Commercial (MapTiler Cloud)',
			url: 'https://www.maptiler.com/',
			fullText: 'Commercial license. Tiles are subject to MapTiler Cloud terms; OSM data underneath is ODbL.',
		},
		{
			name: 'html-to-image',
			license: 'MIT',
			url: 'https://github.com/bubkoo/html-to-image',
			fullText: 'MIT License. See upstream repository for the full text.',
		},
	];

	let expanded = $state<Set<string>>(new Set());

	function toggle(name: string) {
		const next = new Set(expanded);
		if (next.has(name)) next.delete(name);
		else next.add(name);
		expanded = next;
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Open-source licenses</h1>
		<p class="subtitle">
			Threkir is built on a stack of open-source projects. Each one
			below ships under a permissive licence; follow the links to read the
			full text and source.
		</p>
	</header>

	<section class="card">
		<ul class="lic-list">
			{#each deps as d (d.name)}
				<li>
					<div class="lic-head">
						<a href={d.url} target="_blank" rel="noopener noreferrer">{d.name}</a>
						<span class="lic-badge">{d.license}</span>
						<button
							type="button"
							class="lic-toggle"
							aria-expanded={expanded.has(d.name)}
							aria-controls={`lic-text-${d.name.replace(/[^a-z0-9]/gi, '_')}`}
							onclick={() => toggle(d.name)}
						>
							{expanded.has(d.name) ? 'Hide license' : 'View license'}
						</button>
					</div>
					{#if expanded.has(d.name)}
						<pre
							class="lic-text"
							id={`lic-text-${d.name.replace(/[^a-z0-9]/gi, '_')}`}>{d.fullText}</pre>
					{/if}
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
			Threkir itself is a closed-source application. The open-source
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
		padding: 0.35rem 0;
		border-bottom: 1px solid var(--color-border);
	}
	.lic-list li:last-child {
		border-bottom: none;
	}
	.lic-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 0.8rem;
	}
	.lic-head a {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.lic-badge {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		white-space: nowrap;
	}
	.lic-toggle {
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-primary);
		border-radius: var(--radius-sm);
		padding: 0.2rem 0.6rem;
		font-size: 0.75rem;
		cursor: pointer;
		white-space: nowrap;
	}
	.lic-toggle:hover {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
	}
	.lic-text {
		margin: 0.5rem 0 0;
		padding: 0.6rem 0.8rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
		font-family: ui-monospace, monospace;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		white-space: pre-wrap;
		line-height: 1.45;
	}
</style>
