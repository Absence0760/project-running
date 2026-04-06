<main>
	<div class="hero">
		<h1>Run App</h1>
		<p>Plan routes. Track runs. Analyse performance.</p>
		<nav class="hero-actions">
			<a href="/dashboard" class="btn btn-primary">Dashboard</a>
			<a href="/routes/new" class="btn btn-outline">Plan a Route</a>
		</nav>
	</div>
</main>

<style>
	.hero {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: 2rem;
		text-align: center;
	}
	h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
	p { font-size: 1.125rem; color: #666; margin-bottom: 2rem; }
	.hero-actions { display: flex; gap: 1rem; }
	.btn {
		padding: 0.75rem 1.5rem;
		border-radius: 0.5rem;
		text-decoration: none;
		font-weight: 500;
	}
	.btn-primary { background: #1E88E5; color: white; }
	.btn-primary:hover { opacity: 0.9; }
	.btn-outline { border: 1px solid #1E88E5; color: #1E88E5; }
	.btn-outline:hover { background: rgba(30, 136, 229, 0.1); }
</style>
