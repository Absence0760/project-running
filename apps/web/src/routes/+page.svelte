<nav class="landing-nav">
	<a href="/" class="landing-logo">
		<span class="logo-icon">&#9654;</span> Run
	</a>
	<a href="/login" class="nav-signin">Sign In</a>
</nav>

<main class="hero">
	<h1>Plan routes.<br />Track runs.<br />Analyse everything.</h1>
	<p class="hero-sub">
		Import a route. Record on your phone or watch.
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
		max-width: 32rem;
		margin-bottom: var(--space-2xl);
		position: relative;
		z-index: 1;
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

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	@media (max-width: 768px) {
		h1 { font-size: 2.5rem; }
		.features { grid-template-columns: repeat(2, 1fr); }
	}
</style>
