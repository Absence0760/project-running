<nav class="landing-nav">
	<a href="/" class="landing-logo">
		<span class="logo-icon">&#9654;</span> Run
	</a>
	<a href="/login" class="nav-signin">Sign In</a>
</nav>

<main class="hero">
	<h1>Plan routes.<br />Track runs.<br />Analyse everything.</h1>
	<p class="hero-sub">
		Import from Google Maps. Record on your phone or watch.
		Review on a big screen. Free forever.
	</p>
	<div class="hero-actions">
		<a href="/dashboard" class="btn btn-primary btn-lg">Open Dashboard</a>
		<a href="/routes/new" class="btn btn-outline btn-lg">Plan a Route</a>
	</div>
</main>

<section class="features">
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

<style>
	.landing-nav {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
	}

	.landing-logo {
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}

	.nav-signin {
		font-weight: 500;
		color: var(--color-text-secondary);
		padding: var(--space-sm) var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		transition: all var(--transition-fast);
	}

	.nav-signin:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.hero {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 80vh;
		padding: var(--space-2xl);
		text-align: center;
		background: var(--color-bg);
	}

	h1 {
		font-size: 3.5rem;
		font-weight: 800;
		line-height: 1.1;
		letter-spacing: -0.02em;
		margin-bottom: var(--space-lg);
	}

	.hero-sub {
		font-size: 1.25rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin-bottom: var(--space-2xl);
	}

	.hero-actions {
		display: flex;
		gap: var(--space-md);
	}

	.btn {
		padding: 0.75rem 1.75rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 1rem;
		transition: all var(--transition-fast);
		display: inline-block;
	}

	.btn-lg {
		padding: 0.875rem 2rem;
		font-size: 1.05rem;
	}

	.btn-primary {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}

	.btn-outline {
		border: 1.5px solid var(--color-primary);
		color: var(--color-primary);
		background: transparent;
	}

	.btn-outline:hover {
		background: var(--color-primary-light);
	}

	.features {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-xl);
		padding: var(--space-2xl) var(--space-2xl) 4rem;
		max-width: 72rem;
		margin: 0 auto;
	}

	.feature {
		text-align: center;
		padding: var(--space-xl);
	}

	.feature-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 2.5rem;
		color: var(--color-primary);
		margin-bottom: var(--space-md);
		display: block;
	}

	.feature h3 {
		font-size: 1.1rem;
		font-weight: 700;
		margin-bottom: var(--space-sm);
	}

	.feature p {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.6;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	@media (max-width: 768px) {
		h1 { font-size: 2.25rem; }
		.features { grid-template-columns: repeat(2, 1fr); }
	}
</style>
