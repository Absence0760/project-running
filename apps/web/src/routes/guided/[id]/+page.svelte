<script lang="ts">
	import { page } from '$app/stores';
	import { afterNavigate } from '$app/navigation';
	import { findGuidedRun } from '$lib/guided_runs';

	let id = $derived($page.params.id ?? '');
	let run = $derived(findGuidedRun(id));

	let cameFromCoach = $state(false);
	afterNavigate(({ from }) => {
		if (from?.url.pathname === '/coach' && !cameFromCoach) {
			cameFromCoach = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromCoach) {
			e.preventDefault();
			history.back();
		}
	}

	function fmtMmSs(seconds: number): string {
		const m = Math.floor(seconds / 60);
		const s = seconds % 60;
		return `${m}:${String(s).padStart(2, '0')}`;
	}

	function fmtMinutes(seconds: number): string {
		const m = Math.round(seconds / 60);
		return `${m} min`;
	}
</script>

<svelte:head>
	<title>{run?.title ?? 'Guided run'} — Run Onward</title>
</svelte:head>

<div class="page">
	{#if run == null}
		<a href="/guided" class="back-link" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			Back to library
		</a>
		<div class="empty">
			<p class="empty-eyebrow">Unknown guided run.</p>
			<p class="empty-sub">
				The link may be stale or the run id may have changed. Browse the library for the
				current set.
			</p>
			<a href="/guided" class="btn btn-primary">Back to library</a>
		</div>
	{:else}
		<a href="/guided" class="back-link" onclick={handleBack}>
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			Library
		</a>

		<header class="hero">
			<div class="hero-head">
				<p class="kicker">Guided run</p>
				<span class="duration">{fmtMinutes(run.duration_sec)}</span>
			</div>
			<h1>{run.title}</h1>
			<p class="subtitle">{run.subtitle}</p>
			<p class="desc">{run.description}</p>
			<p class="note">
				<span class="material-symbols" aria-hidden="true">phone_iphone</span>
				Open the mobile app to run this. Cues fire automatically as you go.
			</p>
		</header>

		<section class="script" aria-label="Cue script">
			<header class="script-head">
				<h2>The full script</h2>
				<span class="cue-count">{run.cues.length} cues</span>
			</header>
			<ol class="timeline">
				{#each run.cues as cue, i (cue.at_sec)}
					<li class="cue" class:cue-first={i === 0} class:cue-last={i === run.cues.length - 1}>
						<span class="cue-marker" aria-hidden="true"></span>
						<span class="at">{fmtMmSs(cue.at_sec)}</span>
						<span class="text">{cue.text}</span>
					</li>
				{/each}
			</ol>
		</section>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 48rem;
		margin: 0 auto;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		text-align: center;
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.empty-eyebrow {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 700;
		color: var(--color-text);
	}
	.empty-sub {
		margin: 0;
		max-width: 28rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}

	.hero {
		padding: var(--space-xl) 0 var(--space-lg);
		border-bottom: 1px solid var(--color-border);
		margin-bottom: var(--space-xl);
	}
	.hero-head {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin-bottom: var(--space-sm);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0;
	}
	.duration {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		padding: 0.2rem 0.7rem;
		border-radius: 999px;
		font-size: 0.78rem;
		font-weight: 700;
	}
	h1 {
		font-size: 2.2rem;
		font-weight: 800;
		line-height: 1.15;
		margin: 0 0 var(--space-sm);
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 1rem;
		margin: 0 0 var(--space-md);
	}
	.desc {
		color: var(--color-text);
		line-height: 1.55;
		margin: 0 0 var(--space-md);
		max-width: 36rem;
	}
	.note {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.35rem 0.85rem;
		background: var(--color-bg-secondary);
		border-radius: 999px;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0;
	}

	.script-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.script-head h2 {
		font-size: 0.85rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.cue-count {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}

	.timeline {
		list-style: none;
		padding: 0;
		margin: 0;
		position: relative;
	}
	.timeline::before {
		content: '';
		position: absolute;
		left: 1.15rem;
		top: 0.85rem;
		bottom: 0.85rem;
		width: 2px;
		background: var(--color-border);
	}
	.cue {
		display: grid;
		grid-template-columns: 2.3rem 4rem 1fr;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md) var(--space-sm) 0;
		position: relative;
	}
	.cue + .cue {
		margin-top: var(--space-xs);
	}
	.cue-marker {
		width: 0.75rem;
		height: 0.75rem;
		border-radius: 50%;
		background: var(--color-surface);
		border: 2px solid var(--color-primary);
		justify-self: center;
		position: relative;
		z-index: 1;
	}
	.cue-first .cue-marker,
	.cue-last .cue-marker {
		background: var(--color-primary);
	}
	.at {
		font-variant-numeric: tabular-nums;
		font-weight: 700;
		color: var(--color-primary);
		font-size: 0.95rem;
	}
	.text {
		line-height: 1.45;
		color: var(--color-text);
	}
</style>
