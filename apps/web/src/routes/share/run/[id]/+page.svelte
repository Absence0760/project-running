<script lang="ts">
	import RunShareView from '$lib/components/RunShareView.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		buildRunShareDescription,
		buildRunShareTitle,
		formatKmStable,
		formatDateStable,
	} from '$lib/share_meta';

	let { data } = $props();

	let title = $derived(buildRunShareTitle(data.run, data.displayName));
	let description = $derived(buildRunShareDescription(data.run, data.displayName));

	let heroDistance = $derived(formatKmStable(data.run?.distance_m));
	let heroDate = $derived(formatDateStable(data.run?.started_at));
	let heroAthlete = $derived(data.displayName ?? '');
	let hasRun = $derived(!!data.run);
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:site_name" content="Run Onward" />
	<meta property="og:image" content="/og/run/{data.id}.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og/run/{data.id}.png" />
</svelte:head>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Run Onward</a>
	</header>

	{#if hasRun}
		<section class="hero">
			<p class="kicker">A run on Run Onward</p>
			<h1>
				{#if heroAthlete}{heroAthlete}'s run{:else}A public run{/if}
			</h1>
			<p class="subtitle">
				{#if heroDistance}{heroDistance}{/if}
				{#if heroDistance && heroDate}<span class="dot">&middot;</span>{/if}
				{#if heroDate}{heroDate}{/if}
			</p>
		</section>

		<main class="content">
			<RunShareView runId={data.id} headerless hideAnonCta />
		</main>
	{:else}
		<main class="content">
			<div class="notfound-card">
				<p class="kicker">Nothing to see here</p>
				<h1>Run not found.</h1>
				<p class="notfound-sub">
					This link may have expired, the run may have been deleted, or its owner may have made it
					private.
				</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">Sign in</a>
					<a class="btn btn-outline" href="/">Go to Run Onward</a>
				</div>
			</div>
		</main>
	{/if}

	{#if !auth.loggedIn && hasRun}
		<section class="signup-cta" aria-labelledby="signup-cta-heading">
			<p class="kicker">Track your own</p>
			<h2 id="signup-cta-heading">Sign up to track your own runs</h2>
			<p class="signup-sub">
				Free. Map, splits, elevation, kudos, training plans. No subscription needed for the basics.
			</p>
			<a class="btn btn-primary" href="/login?signup=1">Sign up for Free</a>
		</section>
	{/if}

	<footer class="share-footer">
		<a href="/">Run Onward home</a>
		<span class="dot">&middot;</span>
		<a href="/login">Sign in</a>
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
		.hero .subtitle {
			font-size: 1rem;
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
