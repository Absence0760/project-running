<script lang="ts">
	import { browser } from '$app/environment';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';

	$effect(() => {
		if (browser && !auth.loading && auth.loggedIn) {
			goto('/dashboard', { replaceState: true });
		}
	});

	const showLanding = $derived(!browser || (!auth.loading && !auth.loggedIn));

	const apps = [
		{
			icon: 'android',
			name: 'Android',
			tagline: 'Flutter · Material 3',
			body: 'Record runs with live GPS, auto-pause, voice cues, and offline tile caching.'
		},
		{
			icon: 'phone_iphone',
			name: 'iOS',
			tagline: 'Flutter · Cupertino',
			body: 'HealthKit-friendly companion app with the same plans, routes, and history.'
		},
		{
			icon: 'watch',
			name: 'Apple Watch',
			tagline: 'Native SwiftUI',
			body: 'Standalone workouts. Leave your phone at home — splits, pace, and HR on the wrist.'
		},
		{
			icon: 'watch',
			name: 'Wear OS',
			tagline: 'Kotlin · Compose',
			body: 'First-class Pixel Watch and Galaxy Watch support with standalone GPS recording.'
		},
		{
			icon: 'desktop_windows',
			name: 'Web',
			tagline: 'SvelteKit',
			body: 'The review surface. Build routes, analyse splits, manage plans on a big screen.'
		}
	];
</script>

{#if !showLanding}
	<div class="landing-loading">
		<span>Loading...</span>
	</div>
{:else}
<nav class="landing-nav">
	<a href="/" class="landing-logo">
		<span class="logo-icon">&#9654;</span> Run
	</a>
	<div class="nav-links">
		<a href="#apps" class="nav-link">Apps</a>
		<a href="#features" class="nav-link">Features</a>
		<a href="/login" class="nav-signin">Sign In</a>
	</div>
</nav>

<main class="hero">
	<h1>Plan routes.<br />Track runs.<br />Analyse everything.</h1>
	<p class="hero-sub">
		Record on your phone or watch. Review on a big screen.
		One account across Android, iOS, Apple Watch, Wear OS, and the web. Free forever.
	</p>
	<div class="hero-actions">
		<a href="/login" class="btn btn-primary btn-lg">Get Started</a>
		<a href="#apps" class="btn btn-outline btn-lg">See the Apps</a>
	</div>
</main>

<section id="features" class="features">
	<div class="feature">
		<span class="feature-icon material-symbols">route</span>
		<h3>Route Builder</h3>
		<p>Click-to-place waypoints with road and trail snapping. Free — no paywall.</p>
	</div>
	<div class="feature">
		<span class="feature-icon material-symbols">watch</span>
		<h3>Watch Parity</h3>
		<p>Apple Watch and Wear OS are first-class. Standalone GPS, no phone needed.</p>
	</div>
	<div class="feature">
		<span class="feature-icon material-symbols">sync</span>
		<h3>Sync Everything</h3>
		<p>Strava, Garmin, HealthKit, parkrun — all your runs in one place.</p>
	</div>
	<div class="feature">
		<span class="feature-icon material-symbols">analytics</span>
		<h3>Deep Analysis</h3>
		<p>Splits, HR zones, elevation, personal records — better on a big screen.</p>
	</div>
</section>

<section id="apps" class="apps-section">
	<div class="section-head">
		<h2>Available on every device you run with</h2>
		<p>Native experiences on each platform. One account syncs them all.</p>
	</div>
	<div class="apps-grid">
		{#each apps as app}
			<article class="app-card">
				<span class="app-icon material-symbols">{app.icon}</span>
				<h3>{app.name}</h3>
				<span class="app-tagline">{app.tagline}</span>
				<p>{app.body}</p>
			</article>
		{/each}
	</div>
</section>

<section class="closing-cta">
	<h2>Ready to log your next run?</h2>
	<p>Create a free account — no credit card, no paywall.</p>
	<a href="/login" class="btn btn-primary btn-lg">Sign in to continue</a>
</section>

<footer class="landing-footer">
	<span>&copy; Run — track anywhere, review everywhere.</span>
	<div class="footer-links">
		<a href="/login">Sign In</a>
		<a href="#apps">Apps</a>
		<a href="#features">Features</a>
	</div>
</footer>
{/if}

<style>
	.landing-loading {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		color: var(--color-text-tertiary);
		background: var(--color-bg);
	}

	.landing-nav {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		z-index: 10;
	}

	.landing-logo {
		font-weight: 700;
		font-size: 1.25rem;
		color: #ffffff;
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.nav-links {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
	}

	.nav-link {
		color: rgba(255, 255, 255, 0.72);
		font-size: 0.9rem;
		font-weight: 500;
		transition: color var(--transition-fast);
	}

	.nav-link:hover {
		color: #ffffff;
	}

	.nav-signin {
		font-weight: 500;
		color: rgba(255, 255, 255, 0.8);
		padding: var(--space-sm) var(--space-lg);
		border: 1px solid rgba(255, 255, 255, 0.25);
		border-radius: var(--radius-md);
		transition: all var(--transition-fast);
		backdrop-filter: blur(8px);
	}

	.nav-signin:hover {
		border-color: rgba(255, 255, 255, 0.6);
		color: #ffffff;
		background: rgba(255, 255, 255, 0.1);
	}

	.hero {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 85vh;
		padding: var(--space-2xl);
		text-align: center;
		background: linear-gradient(150deg, #0F172A 0%, #1E1B4B 35%, #4F46E5 70%, #7C3AED 100%);
		position: relative;
		overflow: hidden;
	}

	.hero::before {
		content: '';
		position: absolute;
		top: -50%;
		right: -20%;
		width: 60%;
		height: 200%;
		background: radial-gradient(ellipse, rgba(236, 72, 153, 0.15) 0%, transparent 70%);
		pointer-events: none;
	}

	.hero::after {
		content: '';
		position: absolute;
		bottom: -30%;
		left: -10%;
		width: 50%;
		height: 150%;
		background: radial-gradient(ellipse, rgba(6, 182, 212, 0.1) 0%, transparent 70%);
		pointer-events: none;
	}

	h1 {
		font-size: 4rem;
		font-weight: 800;
		line-height: 1.08;
		letter-spacing: -0.03em;
		margin-bottom: var(--space-lg);
		color: #ffffff;
		position: relative;
		z-index: 1;
	}

	.hero-sub {
		font-size: 1.25rem;
		color: rgba(255, 255, 255, 0.65);
		max-width: 34rem;
		margin-bottom: var(--space-2xl);
		position: relative;
		z-index: 1;
		line-height: 1.55;
	}

	.hero-actions {
		display: flex;
		gap: var(--space-md);
		position: relative;
		z-index: 1;
	}

	.btn {
		padding: 0.75rem 1.75rem;
		border-radius: var(--radius-lg);
		font-weight: 600;
		font-size: 1rem;
		transition: all var(--transition-base);
		display: inline-block;
	}

	.btn-lg {
		padding: 0.875rem 2.25rem;
		font-size: 1.05rem;
	}

	.btn-primary {
		background: #ffffff;
		color: #4F46E5;
		border: none;
		box-shadow: 0 4px 14px rgba(0, 0, 0, 0.15);
	}

	.btn-primary:hover {
		background: #F0EFFF;
		transform: translateY(-1px);
		box-shadow: 0 6px 20px rgba(0, 0, 0, 0.2);
	}

	.btn-outline {
		border: 1.5px solid rgba(255, 255, 255, 0.35);
		color: #ffffff;
		background: rgba(255, 255, 255, 0.08);
		backdrop-filter: blur(8px);
	}

	.btn-outline:hover {
		border-color: rgba(255, 255, 255, 0.6);
		background: rgba(255, 255, 255, 0.15);
		transform: translateY(-1px);
	}

	.features {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-lg);
		padding: 4rem var(--space-2xl) 5rem;
		max-width: 72rem;
		margin: 0 auto;
	}

	.feature {
		text-align: center;
		padding: var(--space-xl);
		border-radius: var(--radius-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-sm);
		transition: all var(--transition-base);
	}

	.feature:hover {
		transform: translateY(-4px);
		box-shadow: var(--shadow-lg);
		border-color: transparent;
	}

	.feature-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 2rem;
		margin-bottom: var(--space-md);
		display: flex;
		align-items: center;
		justify-content: center;
		width: 3.5rem;
		height: 3.5rem;
		border-radius: var(--radius-lg);
		margin-left: auto;
		margin-right: auto;
	}

	.feature:nth-child(1) .feature-icon {
		background: rgba(79, 70, 229, 0.1);
		color: #4F46E5;
	}
	.feature:nth-child(2) .feature-icon {
		background: rgba(236, 72, 153, 0.1);
		color: #EC4899;
	}
	.feature:nth-child(3) .feature-icon {
		background: rgba(16, 185, 129, 0.1);
		color: #10B981;
	}
	.feature:nth-child(4) .feature-icon {
		background: rgba(249, 115, 22, 0.1);
		color: #F97316;
	}

	.feature h3 {
		font-size: 1.05rem;
		font-weight: 700;
		margin-bottom: var(--space-sm);
	}

	.feature p {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
		line-height: 1.6;
	}

	.apps-section {
		padding: 5rem var(--space-2xl) 6rem;
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
	}

	.section-head {
		max-width: 44rem;
		margin: 0 auto var(--space-2xl);
		text-align: center;
	}

	.section-head h2 {
		font-size: 2.25rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-md);
	}

	.section-head p {
		color: var(--color-text-secondary);
		font-size: 1.05rem;
	}

	.apps-grid {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: var(--space-lg);
		max-width: 80rem;
		margin: 0 auto;
	}

	.app-card {
		padding: var(--space-xl);
		border-radius: var(--radius-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		box-shadow: var(--shadow-sm);
		transition: all var(--transition-base);
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}

	.app-card:hover {
		transform: translateY(-4px);
		box-shadow: var(--shadow-lg);
	}

	.app-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 1.75rem;
		width: 3rem;
		height: 3rem;
		border-radius: var(--radius-md);
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-primary-light);
		color: var(--color-primary);
		margin-bottom: var(--space-sm);
	}

	.app-card h3 {
		font-size: 1.05rem;
		font-weight: 700;
	}

	.app-tagline {
		font-size: 0.75rem;
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
	}

	.app-card p {
		margin-top: var(--space-sm);
		font-size: 0.88rem;
		line-height: 1.55;
		color: var(--color-text-secondary);
	}

	.closing-cta {
		padding: 5rem var(--space-2xl);
		text-align: center;
		background: linear-gradient(135deg, #1E1B4B 0%, #4F46E5 100%);
		color: #ffffff;
	}

	.closing-cta h2 {
		font-size: 2rem;
		font-weight: 800;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-sm);
	}

	.closing-cta p {
		color: rgba(255, 255, 255, 0.75);
		margin-bottom: var(--space-xl);
		font-size: 1.05rem;
	}

	.landing-footer {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		background: var(--color-bg);
		border-top: 1px solid var(--color-border);
	}

	.footer-links {
		display: flex;
		gap: var(--space-lg);
	}

	.footer-links a {
		color: var(--color-text-secondary);
		transition: color var(--transition-fast);
	}

	.footer-links a:hover {
		color: var(--color-text);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	@media (max-width: 960px) {
		.features { grid-template-columns: repeat(2, 1fr); }
		.apps-grid { grid-template-columns: repeat(2, 1fr); }
	}

	@media (max-width: 768px) {
		h1 { font-size: 2.5rem; }
		.nav-link { display: none; }
		.section-head h2 { font-size: 1.75rem; }
		.apps-grid { grid-template-columns: 1fr; }
		.landing-footer { flex-direction: column; gap: var(--space-sm); }
	}
</style>
