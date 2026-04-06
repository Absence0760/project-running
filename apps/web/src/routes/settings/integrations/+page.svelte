<script lang="ts">
	const integrations = [
		{ name: 'Strava', description: 'Sync activities automatically', connected: false },
		{ name: 'parkrun', description: 'Import your parkrun history', connected: false },
		{ name: 'Garmin Connect', description: 'Sync from Garmin devices', connected: false },
	];
</script>

<main class="integrations-page">
	<h1>Integrations</h1>

	<div class="integration-list">
		{#each integrations as integration}
			<div class="integration-card">
				<div>
					<h3>{integration.name}</h3>
					<p>{integration.description}</p>
				</div>
				<button class:connected={integration.connected}>
					{integration.connected ? 'Disconnect' : 'Connect'}
				</button>
			</div>
		{/each}
	</div>
</main>

<style>
	.integrations-page { max-width: 40rem; margin: 0 auto; padding: 2rem; }
	h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: 2rem; }
	.integration-list { display: flex; flex-direction: column; gap: 1rem; }
	.integration-card {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 1rem;
		border: 1px solid #e5e5e5;
		border-radius: 0.5rem;
	}
	h3 { font-weight: 600; margin: 0; }
	p { font-size: 0.875rem; color: #888; margin: 0.25rem 0 0; }
	button {
		padding: 0.5rem 1rem;
		border-radius: 0.5rem;
		font-size: 0.875rem;
		cursor: pointer;
		background: #1E88E5;
		color: white;
		border: none;
	}
	button.connected { background: white; border: 1px solid #e5e5e5; color: #dc2626; }
</style>
