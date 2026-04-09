<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchIntegrations, connectIntegration, disconnectIntegration } from '$lib/data';

	interface IntegrationUI {
		provider: string;
		name: string;
		description: string;
		icon: string;
		connected: boolean;
		lastSync: string | null;
		loading: boolean;
	}

	const providers: Omit<IntegrationUI, 'connected' | 'lastSync' | 'loading'>[] = [
		{ provider: 'strava', name: 'Strava', description: 'Sync activities automatically via webhook', icon: '🟠' },
		{ provider: 'parkrun', name: 'parkrun', description: 'Import your complete parkrun history', icon: '🟣' },
		{ provider: 'garmin', name: 'Garmin Connect', description: 'Sync runs from Garmin devices', icon: '🔵' },
		{ provider: 'healthkit', name: 'Apple HealthKit', description: 'Synced on-device via the iOS app', icon: '❤️' },
	];

	let integrations = $state<IntegrationUI[]>(
		providers.map((p) => ({ ...p, connected: false, lastSync: null, loading: false }))
	);

	let pageLoading = $state(true);

	onMount(async () => {
		const saved = await fetchIntegrations();
		for (const s of saved) {
			const idx = integrations.findIndex((i) => i.provider === s.provider);
			if (idx >= 0) {
				integrations[idx].connected = true;
				integrations[idx].lastSync = s.last_sync_at;
			}
		}
		pageLoading = false;
	});

	async function toggle(index: number) {
		const item = integrations[index];
		item.loading = true;
		try {
			if (item.connected) {
				await disconnectIntegration(item.provider);
				item.connected = false;
				item.lastSync = null;
			} else {
				await connectIntegration(item.provider);
				item.connected = true;
			}
		} catch (err) {
			console.error('Integration toggle failed:', err);
		} finally {
			item.loading = false;
		}
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Integrations</h1>
		<p class="page-sub">Connect external services to sync your runs automatically.</p>
	</header>

	{#if pageLoading}
		<p class="loading-text">Loading integrations...</p>
	{:else}
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
						disabled={integration.loading}
						onclick={() => toggle(i)}
					>
						{#if integration.loading}
							...
						{:else}
							{integration.connected ? 'Disconnect' : 'Connect'}
						{/if}
					</button>
				</div>
			{/each}
		</div>
	{/if}
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

	.loading-text {
		text-align: center;
		color: var(--color-text-tertiary);
		padding: var(--space-2xl);
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

	.btn:disabled {
		opacity: 0.5;
	}

	.btn-connect {
		background: var(--color-primary);
		color: white;
		border: none;
	}

	.btn-connect:hover:not(:disabled) {
		background: var(--color-primary-hover);
	}

	.btn-disconnect {
		background: transparent;
		border: 1.5px solid var(--color-border);
		color: var(--color-text-secondary);
	}

	.btn-disconnect:hover:not(:disabled) {
		border-color: var(--color-danger);
		color: var(--color-danger);
	}
</style>
