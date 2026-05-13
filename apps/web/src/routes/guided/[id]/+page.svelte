<script lang="ts">
	import { page } from '$app/stores';
	import { findGuidedRun } from '$lib/guided_runs';

	let id = $derived($page.params.id ?? '');
	let run = $derived(findGuidedRun(id));

	function fmtMmSs(seconds: number): string {
		const m = Math.floor(seconds / 60);
		const s = seconds % 60;
		return `${m}:${String(s).padStart(2, '0')}`;
	}
</script>

<svelte:head>
	<title>{run?.title ?? 'Guided run'}</title>
</svelte:head>

<div class="page">
	{#if run == null}
		<p class="muted">Unknown guided run.</p>
		<p><a href="/guided">← Back to library</a></p>
	{:else}
		<header class="hero">
			<a href="/guided" class="back">← Library</a>
			<h1>{run.title}</h1>
			<p class="subtitle">{run.subtitle}</p>
			<p class="desc">{run.description}</p>
			<p class="note">
				<span class="material-symbols">phone_iphone</span>
				Open the mobile app to run this. Cues fire automatically as you go.
			</p>
		</header>

		<section class="script">
			<h2>The full script</h2>
			<ol>
				{#each run.cues as cue (cue.at_sec)}
					<li>
						<span class="at">{fmtMmSs(cue.at_sec)}</span>
						<span class="text">{cue.text}</span>
					</li>
				{/each}
			</ol>
		</section>
	{/if}
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 48rem; margin: 0 auto; }
	.muted { color: var(--color-text-secondary); }
	.back { font-size: 0.85rem; color: var(--color-text-secondary); text-decoration: none; }
	.back:hover { color: var(--color-primary); }
	h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: var(--space-sm) 0 var(--space-sm);
	}
	.subtitle { color: var(--color-text-secondary); margin: 0 0 var(--space-md); }
	.desc { color: var(--color-text); line-height: 1.5; margin: 0 0 var(--space-md); }
	.note {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.3rem 0.8rem;
		background: var(--color-bg-secondary);
		border-radius: 999px;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xl);
	}
	.script h2 {
		font-size: 0.9rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
	}
	.script ol {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.script li {
		display: grid;
		grid-template-columns: 4rem 1fr;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.at {
		font-variant-numeric: tabular-nums;
		font-weight: 700;
		color: var(--color-primary);
	}
	.text { line-height: 1.4; }
</style>
