<script lang="ts">
	import { GUIDED_RUN_LIBRARY } from '$lib/guided_runs';

	function fmtMinutes(seconds: number): string {
		const m = Math.round(seconds / 60);
		return `${m} min`;
	}
</script>

<svelte:head>
	<title>Guided runs</title>
	<meta
		name="description"
		content="Coach-voice scripted workouts — pace cues, form reminders, intervals."
	/>
</svelte:head>

<div class="page">
	<header class="hero">
		<p class="kicker">Guided runs</p>
		<h1>A coach in your ear, free.</h1>
		<p class="tagline">
			Scripted coach-voice workouts. Cues fire at the right moments through your phone's TTS — no
			subscription, no in-app purchase, and you don't need a fancy watch.
		</p>
		<p class="note">
			<span class="material-symbols">phone_iphone</span>
			Open these on the mobile app to run them. The library here is a preview.
		</p>
	</header>

	<section class="library">
		{#each GUIDED_RUN_LIBRARY as g (g.id)}
			<a class="card" href="/guided/{g.id}">
				<header>
					<span class="duration">{fmtMinutes(g.duration_sec)}</span>
					<h2>{g.title}</h2>
				</header>
				<p class="subtitle">{g.subtitle}</p>
				<p class="desc">{g.description}</p>
				<div class="cue-count">
					{g.cues.length} cues across the run
				</div>
			</a>
		{/each}
	</section>
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 64rem; margin: 0 auto; }
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
		max-width: 40rem;
		margin: 0 auto var(--space-md);
		color: var(--color-text-secondary);
	}
	.note {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.3rem 0.8rem;
		background: var(--color-bg-secondary);
		border-radius: 999px;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.library {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
		gap: var(--space-md);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		transition: transform 0.15s ease;
	}
	.card:hover { transform: translateY(-2px); border-color: var(--color-primary); }
	.card header { display: flex; align-items: center; justify-content: space-between; gap: var(--space-sm); }
	.duration {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		padding: 0.2rem 0.6rem;
		border-radius: 999px;
		font-size: 0.78rem;
		font-weight: 700;
	}
	.card h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 700;
	}
	.subtitle { color: var(--color-text-secondary); font-size: 0.9rem; margin: 0; }
	.desc { color: var(--color-text); font-size: 0.92rem; line-height: 1.5; margin: 0; }
	.cue-count {
		margin-top: auto;
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
</style>
