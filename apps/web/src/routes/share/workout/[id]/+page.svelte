<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import SharePageShell from '$lib/components/SharePageShell.svelte';
	import { formatWeight } from '$lib/format/units.svelte';
	import { formatDateStable } from '$lib/share/share_meta';
	import {
		buildWorkoutJsonLd,
		buildWorkoutShareCanonical,
		buildWorkoutShareDescription,
		buildWorkoutShareTitle,
		distinctExerciseCount
	} from '$lib/share/share_workout_meta';
	import type { SharedWorkoutSet } from '$lib/share/share_workout_lookup';
	import { normaliseExerciseName } from '$lib/gym/gym_prs';

	let { data } = $props();

	let hasWorkout = $derived(!!data.workout);
	let athlete = $derived(data.displayName ?? '');
	let heroTitle = $derived((data.workout?.title ?? '').trim());
	let heroDate = $derived(formatDateStable(data.workout?.started_at));

	let title = $derived(buildWorkoutShareTitle(data.workout, data.displayName));
	let description = $derived(buildWorkoutShareDescription(data.workout, data.displayName));
	let canonicalUrl = $derived(buildWorkoutShareCanonical(data.siteUrl, data.id));
	let jsonLd = $derived(
		buildWorkoutJsonLd(data.workout, {
			id: data.id,
			base: data.siteUrl,
			displayName: data.displayName
		})
	);

	// Group the public sets into exercise blocks in set_index order — same
	// shape as the owner's /gym/[id] detail, minus the owner-only PR / edit
	// affordances. No notes / RPE are fetched, so nothing private leaks.
	let blocks = $derived.by(() => {
		const out: { name: string; key: string; sets: SharedWorkoutSet[] }[] = [];
		for (const s of data.workout?.sets ?? []) {
			const last = out[out.length - 1];
			const key = normaliseExerciseName(s.exercise_name);
			if (last && last.key === key) last.sets.push(s);
			else out.push({ name: s.exercise_name, key, sets: [s] });
		}
		return out;
	});

	let exerciseCount = $derived(distinctExerciseCount(data.workout?.sets ?? []));

	function setSummary(s: SharedWorkoutSet): string {
		const parts: string[] = [];
		if (s.reps != null) parts.push(`${s.reps}`);
		if (s.weight_kg != null) parts.push(formatWeight(s.weight_kg));
		const repWeight = parts.join(' × ');
		if (s.duration_s != null) {
			const dur = `${s.duration_s}s`;
			return repWeight ? `${repWeight} · ${dur}` : dur;
		}
		return repWeight || '—';
	}
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og-default.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og-default.png" />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<SharePageShell>
	{#if hasWorkout}
		<section class="hero">
			<p class="kicker">{m('shareWorkout.heroKicker')}</p>
			<h1>
				{#if heroTitle}{heroTitle}{:else if athlete}{m('shareWorkout.heroAthleteWorkout', { name: athlete })}{:else}{m('shareWorkout.heroPublicWorkout')}{/if}
			</h1>
			{#if heroDate}<p class="subtitle">{heroDate}</p>{/if}
		</section>

		<main class="content" id="main-content">
			<div class="summary-grid">
				<div class="summary-stat">
					<span class="summary-value">{exerciseCount}</span>
					<span class="summary-label">{m('shareWorkout.exercisesLabel')}</span>
				</div>
				<div class="summary-stat">
					<span class="summary-value">{data.workout!.set_count ?? blocks.reduce((n, b) => n + b.sets.length, 0)}</span>
					<span class="summary-label">{m('shareWorkout.setsLabel')}</span>
				</div>
				{#if (data.workout!.volume_kg ?? 0) > 0}
					<div class="summary-stat">
						<span class="summary-value">{formatWeight(data.workout!.volume_kg ?? 0)}</span>
						<span class="summary-label">{m('shareWorkout.volumeLabel')}</span>
					</div>
				{/if}
			</div>

			{#each blocks as block (block.name)}
				<section class="exercise-block">
					<h2>{block.name || '—'}</h2>
					<ol class="sets">
						{#each block.sets as s (s.set_index)}
							<li>
								<span class="set-n">{m('shareWorkout.setN', { n: s.set_index + 1 })}</span>
								<span class="set-val">{setSummary(s)}</span>
							</li>
						{/each}
					</ol>
				</section>
			{/each}
		</main>
	{:else}
		<main class="content" id="main-content">
			<div class="notfound-card">
				<p class="kicker">{m('shareWorkout.notFoundKicker')}</p>
				<h1>{m('shareWorkout.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareWorkout.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareWorkout.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareWorkout.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasWorkout}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">{m('shareWorkout.ctaKicker')}</p>
			<h2 id="signup-cta-heading">{m('shareWorkout.ctaHeading')}</h2>
			<p class="signup-sub">{m('shareWorkout.ctaSub')}</p>
			<a class="btn btn-primary" href="/login?signup=1">{m('shareWorkout.ctaButton')}</a>
		</section>
	{/if}
</SharePageShell>

<style>
	.hero {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md) var(--space-md);
		text-align: center;
	}

	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}

	.hero h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
	}

	.hero .subtitle {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		margin: 0;
	}

	.content {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
	}

	.summary-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(7rem, 100%), 1fr));
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
	}
	.summary-stat {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.summary-value {
		font-size: 1.35rem;
		font-weight: 700;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}
	.summary-label {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
	}

	.exercise-block {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-md);
	}
	.exercise-block h2 {
		margin: 0 0 var(--space-sm);
		font-size: 1.1rem;
		font-weight: 600;
	}
	.sets {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.sets li {
		display: grid;
		grid-template-columns: 4rem 1fr;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-xs) 0;
	}
	.sets li + li {
		border-top: 1px solid var(--color-border);
	}
	.set-n {
		font-size: 0.82rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		white-space: nowrap;
	}
	.set-val {
		font-variant-numeric: tabular-nums;
		font-weight: 500;
		color: var(--color-text);
	}

	.notfound-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl) var(--space-lg);
		margin-top: var(--space-xl);
		text-align: center;
	}
	.notfound-card h1 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.notfound-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 28rem;
		margin: 0 auto var(--space-lg);
		line-height: 1.5;
	}
	.notfound-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}

	.signup-cta {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-lg) var(--space-md) var(--space-xl);
		text-align: center;
	}
	.signup-cta h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.signup-cta .signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
	}

	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
		.signup-cta {
			padding: var(--space-xl) var(--space-xl) var(--space-2xl);
		}
		.signup-cta h2 {
			font-size: 1.6rem;
		}
	}
</style>
