<script lang="ts">
	import {
		COMPARE_SECTIONS,
		COMPARE_HEADLINE,
		type FeatureSupport,
	} from '$lib/compare_features';

	function cellLabel(v: FeatureSupport): string {
		return v === 'yes' ? 'Yes' : v === 'no' ? 'No' : 'Partial';
	}
</script>

<svelte:head>
	<title>How we compare to Strava — Run Onward</title>
	<meta
		name="description"
		content="Every Strava Pro feature, free. See the side-by-side."
	/>
</svelte:head>

<div class="page">
	<header class="hero">
		<p class="kicker">Pricing &amp; features</p>
		<h1>Everything Strava Pro has — free.</h1>
		<p class="tagline">
			Strava paywalls the features that make running data actually useful: heart-rate zones, pace heatmaps,
			best-effort detection, training-load curves, live tracking. We ship all of it for free, plus a couple
			of things even Strava Pro doesn’t do (readiness score, tiered KOM/QOM crowns).
		</p>

		<div class="price-cards">
			<div class="price-card us">
				<span class="price-label">Run Onward</span>
				<span class="price">{COMPARE_HEADLINE.usPrice}</span>
				<span class="price-sub">Forever</span>
			</div>
			<div class="price-card">
				<span class="price-label">Strava Free</span>
				<span class="price">{COMPARE_HEADLINE.stravaFreePrice}</span>
				<span class="price-sub">Most analysis features locked</span>
			</div>
			<div class="price-card">
				<span class="price-label">Strava Pro</span>
				<span class="price">{COMPARE_HEADLINE.stravaProPrice}</span>
				<span class="price-sub">Required to unlock the good stuff</span>
			</div>
		</div>
	</header>

	{#each COMPARE_SECTIONS as section (section.title)}
		<section class="cmp-section">
			<h2>{section.title}</h2>
			<table class="cmp-table">
				<thead>
					<tr>
						<th class="feature-col">Feature</th>
						<th>Run Onward</th>
						<th>Strava Free</th>
						<th>Strava Pro</th>
					</tr>
				</thead>
				<tbody>
					{#each section.rows as row (row.name)}
						<tr>
							<td class="feature-col">
								<div class="feature-name">{row.name}</div>
								{#if row.note}
									<div class="feature-note">{row.note}</div>
								{/if}
							</td>
							<td class="cell cell-{row.ours} ours" data-col="Run Onward">
								<span class="material-symbols">
									{row.ours === 'yes' ? 'check_circle' : row.ours === 'partial' ? 'change_history' : 'remove'}
								</span>
								<span class="sr-only">{cellLabel(row.ours)}</span>
								<span class="cell-mobile-label">{cellLabel(row.ours)}</span>
							</td>
							<td class="cell cell-{row.stravaFree}" data-col="Strava Free">
								<span class="material-symbols">
									{row.stravaFree === 'yes' ? 'check' : row.stravaFree === 'partial' ? 'change_history' : 'remove'}
								</span>
								<span class="sr-only">{cellLabel(row.stravaFree)}</span>
								<span class="cell-mobile-label">{cellLabel(row.stravaFree)}</span>
							</td>
							<td class="cell cell-{row.stravaPro}" data-col="Strava Pro">
								<span class="material-symbols">
									{row.stravaPro === 'yes' ? 'check' : row.stravaPro === 'partial' ? 'change_history' : 'remove'}
								</span>
								<span class="sr-only">{cellLabel(row.stravaPro)}</span>
								<span class="cell-mobile-label">{cellLabel(row.stravaPro)}</span>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</section>
	{/each}

	<footer class="cmp-footer">
		<p>
			Run Onward is free because the math is open-source, we’re indie, and the infrastructure runs on
			a shoestring. No ads, no upsell modals. If you want to support us, the
			<a href="/settings/upgrade">donate page</a> exists; it’s never required.
		</p>
		<p class="cmp-links">
			Explore the features:
			<a href="/coach">AI Coach</a>
			<span class="sep">&middot;</span>
			<a href="/plans">Training plans</a>
			<span class="sep">&middot;</span>
			<a href="/clubs">Clubs</a>
			<span class="sep">&middot;</span>
			<a
				href="https://www.strava.com/premium"
				target="_blank"
				rel="noopener noreferrer"
			>Strava Pro pricing</a>
		</p>
	</footer>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 72rem; margin: 0 auto; }
	.hero { text-align: center; padding: var(--space-2xl) 0 var(--space-xl); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}
	.hero h1 {
		font-size: 2.5rem;
		font-weight: 800;
		margin: 0 0 var(--space-md);
	}
	.tagline {
		max-width: 48rem;
		margin: 0 auto var(--space-xl);
		color: var(--color-text-secondary);
		font-size: 1.05rem;
		line-height: 1.5;
	}
	.price-cards {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	.price-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}
	.price-card.us {
		border-color: #2e7d32;
		background: color-mix(in srgb, #2e7d32 8%, var(--color-surface));
	}
	.price-label {
		font-size: 0.8rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
	}
	.price { font-size: 1.5rem; font-weight: 800; }
	.price-sub { font-size: 0.85rem; color: var(--color-text-tertiary); }

	.cmp-section { margin-bottom: var(--space-xl); }
	.cmp-section h2 {
		font-size: 0.9rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-sm);
	}
	.cmp-table {
		width: 100%;
		border-collapse: collapse;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}
	.cmp-table th {
		text-align: center;
		padding: var(--space-sm) var(--space-md);
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
		background: var(--color-bg-secondary);
	}
	.cmp-table th.feature-col { text-align: left; }
	.cmp-table tbody td {
		padding: var(--space-sm) var(--space-md);
		border-top: 1px solid var(--color-border);
		vertical-align: top;
	}
	.feature-col { width: 60%; }
	.feature-name { font-weight: 600; }
	.feature-note { font-size: 0.82rem; color: var(--color-text-tertiary); margin-top: 0.2rem; }
	.cell { text-align: center; font-size: 1.2rem; }
	.cell-mobile-label { display: none; font-size: 0.85rem; font-weight: 500; }
	.cell-yes { color: #2e7d32; }
	.cell-partial { color: #f59e0b; }
	.cell-no { color: var(--color-text-tertiary); }
	.cell.ours { background: color-mix(in srgb, #2e7d32 5%, transparent); }
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		border: 0;
	}
	.cmp-footer {
		text-align: center;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		padding: var(--space-xl) 0;
	}
	.cmp-footer a { color: var(--color-primary); }
	.cmp-links { margin-top: var(--space-sm); font-size: 0.85rem; }
	.cmp-links .sep { margin: 0 0.3rem; color: var(--color-text-tertiary); }

	/* Mobile collapse — at narrow widths the wide 4-col table is uncomfortable.
	   Switch to a card-per-row layout where each row stacks the feature name on
	   top and renders the three providers as labelled chips below. */
	@media (max-width: 640px) {
		.hero h1 { font-size: 1.9rem; }
		.cmp-table,
		.cmp-table thead,
		.cmp-table tbody,
		.cmp-table tr,
		.cmp-table td {
			display: block;
			width: 100%;
			box-sizing: border-box;
		}
		.cmp-table thead { display: none; }
		.cmp-table tbody tr {
			padding: 0.6rem 0.9rem;
			border-top: 1px solid var(--color-border);
		}
		.cmp-table tbody tr:first-child { border-top: none; }
		.cmp-table tbody td {
			border-top: none;
			padding: 0.2rem 0;
		}
		.cmp-table tbody td.feature-col {
			width: 100%;
			padding-bottom: 0.4rem;
		}
		.cmp-table tbody td.cell {
			display: flex;
			align-items: center;
			justify-content: flex-start;
			gap: 0.5rem;
			text-align: left;
			padding: 0.15rem 0;
		}
		.cmp-table tbody td.cell::before {
			content: attr(data-col);
			font-size: 0.75rem;
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.04em;
			color: var(--color-text-secondary);
			min-width: 6.5rem;
		}
		.cell-mobile-label { display: inline; }
	}

	/* Print — drop the dark surfaces, expand tables full-width, remove the
	   donate footer so the page fits on letter / A4 without a third blank
	   page. Used for marketing handouts + the occasional partner deck. */
	@media print {
		.page { padding: 0; max-width: none; }
		.price-cards { grid-template-columns: 1fr 1fr 1fr; gap: 0.5rem; }
		.price-card { padding: 0.5rem; box-shadow: none; background: white !important; border: 1px solid #ccc; }
		.price-card.us { background: #f6fbf6 !important; }
		.cmp-section { page-break-inside: avoid; margin-bottom: 1rem; }
		.cmp-table {
			background: white !important;
			border: 1px solid #ccc;
			box-shadow: none;
			page-break-inside: avoid;
		}
		.cmp-table th { background: #eee !important; color: #000 !important; }
		.cmp-table tbody td { border-top: 1px solid #ccc; }
		.cell-yes { color: #1b5e20 !important; }
		.cell-partial { color: #b26a00 !important; }
		.cell-no { color: #888 !important; }
		.cmp-footer { display: none; }
	}
</style>
