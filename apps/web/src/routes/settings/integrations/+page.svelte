<script lang="ts">
	let integrations = $state([
		{
			name: 'Strava',
			description: 'Sync activities automatically via webhook',
			icon: '🟠',
			connected: false,
			lastSync: null as string | null,
		},
		{
			name: 'parkrun',
			description: 'Import your complete parkrun history',
			icon: '🟣',
			connected: true,
			lastSync: '2026-04-01T10:00:00Z',
		},
		{
			name: 'Garmin Connect',
			description: 'Sync runs from Garmin devices',
			icon: '🔵',
			connected: false,
			lastSync: null,
		},
		{
			name: 'Apple HealthKit',
			description: 'Synced on-device via the iOS app',
			icon: '❤️',
			connected: true,
			lastSync: '2026-04-05T08:00:00Z',
		},
	]);

	function toggleConnection(index: number) {
		integrations[index].connected = !integrations[index].connected;
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Integrations</h1>
		<p class="page-sub">Connect external services to sync your runs automatically.</p>
	</header>

	<div class="integration-list">
		{#each integrations as integration, i}
			<div class="integration-card" class:connected={integration.connected}>
				<div class="integration-icon">{integration.icon}</div>
				<div class="integration-info">
					<h3>{integration.name}</h3>
					<p>{integration.description}</p>
					{#if integration.connected && integration.lastSync}
						<span class="last-sync">
							Last synced {new Date(integration.lastSync).toLocaleDateString('en-GB', {
								day: 'numeric',
								month: 'short',
								hour: '2-digit',
								minute: '2-digit',
							})}
						</span>
					{/if}
				</div>
				<button
					class="btn"
					class:btn-disconnect={integration.connected}
					class:btn-connect={!integration.connected}
					onclick={() => toggleConnection(i)}
				>
					{integration.connected ? 'Disconnect' : 'Connect'}
				</button>
			</div>
		{/each}
	</div>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 44rem;
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin-bottom: var(--space-xs);
	}

	.page-sub {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}

	.integration-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.integration-card {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		transition: all var(--transition-fast);
	}

	.integration-card.connected {
		border-color: var(--color-secondary);
		border-left: 3px solid var(--color-secondary);
	}

	.integration-icon {
		font-size: 1.75rem;
		flex-shrink: 0;
	}

	.integration-info {
		flex: 1;
		min-width: 0;
	}

	h3 {
		font-size: 1rem;
		font-weight: 600;
		margin-bottom: 0.125rem;
	}

	p {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}

	.last-sync {
		display: block;
		font-size: 0.75rem;
		color: var(--color-secondary);
		margin-top: var(--space-xs);
	}

	.btn {
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-size: 0.8rem;
		font-weight: 600;
		flex-shrink: 0;
		transition: all var(--transition-fast);
	}

	.btn-connect {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-connect:hover {
		background: var(--color-primary-hover);
	}

	.btn-disconnect {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text-secondary);
	}

	.btn-disconnect:hover {
		border-color: var(--color-danger);
		color: var(--color-danger);
	}
</style>
