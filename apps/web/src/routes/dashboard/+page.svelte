<main class="dashboard">
	<h1>Dashboard</h1>

	<!-- Stat cards -->
	<section class="stat-grid">
		<!-- TODO: Total distance this week -->
		<!-- TODO: Total runs this month -->
		<!-- TODO: Longest run ever -->
		<!-- TODO: Current weekly streak -->
	</section>

	<!-- Mileage chart -->
	<section class="section">
		<h2>Weekly Mileage</h2>
		<!-- TODO: 12-week bar chart -->
	</section>

	<!-- Calendar heatmap -->
	<section class="section">
		<h2>Activity</h2>
		<!-- TODO: GitHub-style contribution heatmap -->
	</section>

	<!-- Personal records -->
	<section class="section">
		<h2>Personal Records</h2>
		<!-- TODO: PR table for 5k, 10k, half, full -->
	</section>

	<!-- Recent runs -->
	<section class="section">
		<h2>Recent Runs</h2>
		<!-- TODO: Last 10 runs list -->
	</section>
</main>

<style>
	.dashboard { max-width: 72rem; margin: 0 auto; padding: 2rem; }
	h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: 2rem; }
	h2 { font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem; }
	.stat-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-bottom: 2rem; }
	.section { margin-bottom: 2rem; }
</style>
