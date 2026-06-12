<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { expandSessionSteps, type SessionStep } from '$lib/social/session_steps';

	let { data } = $props();

	let hasSession = $derived(!!data.session);
	let athlete = $derived(data.displayName ?? '');
	let heroTitle = $derived((data.session?.title ?? '').trim());

	let title = $derived(
		heroTitle
			? `${heroTitle} — Threkir`
			: athlete
				? `${m('shareSession.heroAthleteSession', { name: athlete })} — Threkir`
				: `${m('shareSession.heroPublicSession')} — Threkir`
	);

	// Expand blocks → items into ordered steps (per-side split into L/R) via the
	// shared parity helper, exactly as the owner's /sessions/[id] read view does.
	let expanded = $derived.by(() => {
		if (!data.session) return { steps: [] as SessionStep[], totalS: 0 };
		return expandSessionSteps({
			blocks: data.session.blocks.map((b) => ({ id: b.id, position: b.position, name: b.name })),
			items: data.session.items.map((it) => ({
				id: it.id,
				block_id: it.block_id,
				position: it.position,
				movement_name: it.movement_name,
				kind: it.kind,
				duration_s: it.duration_s,
				reps: it.reps,
				per_side: it.per_side,
				tempo: it.tempo,
				cue: it.cue
			}))
		});
	});

	let estMinutes = $derived(
		data.session?.est_duration_min ?? Math.round(expanded.totalS / 60)
	);

	let description = $derived(
		hasSession
			? `${data.session!.items.length} movements${
					estMinutes > 0 ? ` · ${m('session.estDuration', { minutes: estMinutes })}` : ''
				}`
			: m('shareSession.notFoundSub')
	);

	function stepName(step: SessionStep): string {
		if (step.side === 'left') return m('session.sideLeft', { name: step.movementName });
		if (step.side === 'right') return m('session.sideRight', { name: step.movementName });
		return step.movementName;
	}

	function stepLabel(step: SessionStep): string {
		const name = stepName(step);
		if (step.kind === 'reps') return m('session.stepReps', { name, reps: step.reps ?? 0 });
		if (step.kind === 'flow') return m('session.stepFlow', { name, seconds: step.durationS ?? 0 });
		return m('session.stepHold', { name, seconds: step.durationS ?? 0 });
	}
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:site_name" content="Threkir" />
	<meta name="twitter:card" content="summary" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
	</header>

	{#if hasSession}
		<section class="hero">
			<p class="kicker">{m('shareSession.heroKicker')}</p>
			<h1>
				{#if heroTitle}{heroTitle}{:else if athlete}{m('shareSession.heroAthleteSession', { name: athlete })}{:else}{m('shareSession.heroPublicSession')}{/if}
			</h1>
			<p class="subtitle">
				{#if data.session!.discipline}{data.session!.discipline}{/if}
				{#if data.session!.equipment}· {data.session!.equipment}{/if}
				{#if estMinutes > 0}· {m('session.estDuration', { minutes: estMinutes })}{/if}
			</p>
		</section>

		<main class="content">
			<div class="summary-grid">
				<div class="summary-stat">
					<span class="summary-value">{data.session!.items.length}</span>
					<span class="summary-label">{m('shareSession.movementsLabel')}</span>
				</div>
				{#if estMinutes > 0}
					<div class="summary-stat">
						<span class="summary-value">{estMinutes}</span>
						<span class="summary-label">{m('shareSession.minutesLabel')}</span>
					</div>
				{/if}
			</div>

			<section class="sequence">
				<h2>{m('session.steps')}</h2>
				<ol class="steps" data-testid="session-steps">
					{#each expanded.steps as step (step.itemId + (step.side ?? ''))}
						<li>
							<span class="step-label">{stepLabel(step)}</span>
							{#if step.cue}<span class="step-cue">{step.cue}</span>{/if}
						</li>
					{/each}
				</ol>
			</section>
		</main>
	{:else}
		<main class="content">
			<div class="notfound-card">
				<p class="kicker">{m('shareSession.notFoundKicker')}</p>
				<h1>{m('shareSession.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareSession.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareSession.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareSession.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasSession}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">{m('shareSession.ctaKicker')}</p>
			<h2 id="signup-cta-heading">{m('shareSession.ctaHeading')}</h2>
			<p class="signup-sub">{m('shareSession.ctaSub')}</p>
			<a class="btn btn-primary" href="/login?signup=1">{m('shareSession.ctaButton')}</a>
		</section>
	{/if}

	<footer class="share-footer">
		<a href="/">{m('shareSession.footerHome')}</a>
		<span class="dot">&middot;</span>
		<a href="/login">{m('shareSession.signIn')}</a>
	</footer>
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.share-header {
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.share-logo {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-primary);
		text-decoration: none;
	}

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

	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}

	.content {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
	}

	.summary-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr));
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

	.sequence {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md) var(--space-lg);
	}
	.sequence h2 {
		margin: 0 0 var(--space-sm);
		font-size: 1.1rem;
		font-weight: 600;
	}
	.steps {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.steps li {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding: var(--space-xs) 0;
	}
	.steps li + li {
		border-top: 1px solid var(--color-border);
	}
	.step-label {
		font-weight: 500;
		color: var(--color-text);
	}
	.step-cue {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
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

	.share-footer {
		margin-top: auto;
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		background: var(--color-surface);
	}
	.share-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}
	.share-footer a:hover {
		color: var(--color-primary);
	}

	@media (min-width: 48rem) {
		.share-header {
			padding: var(--space-md) var(--space-xl);
		}
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
