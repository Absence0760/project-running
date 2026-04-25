<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { fetchIntegrations, connectIntegration, disconnectIntegration } from '$lib/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import {
		stravaAuthUrl,
		completeStravaOAuth,
		syncStrava,
		isStravaConfigured,
	} from '$lib/strava';
	import { importStravaZip, type StravaZipProgress } from '$lib/strava-zip';

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
		{ provider: 'strava', name: 'Strava', description: 'Sync activities automatically from your Strava account', icon: '🟠' },
		{ provider: 'parkrun', name: 'parkrun', description: 'Import your complete parkrun history', icon: '🟣' },
		{ provider: 'garmin', name: 'Garmin Connect', description: 'Sync runs from Garmin devices', icon: '🔵' },
		{ provider: 'healthkit', name: 'Apple HealthKit', description: 'Synced on-device via the iOS app', icon: '❤️' },
	];

	let integrations = $state<IntegrationUI[]>(
		providers.map((p) => ({ ...p, connected: false, lastSync: null, loading: false }))
	);

	let pageLoading = $state(true);

	async function refreshIntegrations() {
		const saved = await fetchIntegrations();
		for (const ui of integrations) {
			const match = saved.find((s) => s.provider === ui.provider);
			ui.connected = Boolean(match);
			ui.lastSync = match?.last_sync_at ?? null;
		}
	}

	onMount(async () => {
		await refreshIntegrations();

		// OAuth callback: Strava redirects back to this page with a
		// `code` in the URL. Exchange it for tokens, then strip the
		// params so a refresh doesn't replay a dead single-use code.
		const params = $page.url.searchParams;
		if (params.has('code') && params.has('scope')) {
			const strava = integrations.find((i) => i.provider === 'strava');
			if (strava) strava.loading = true;
			try {
				const result = await completeStravaOAuth(params);
				await refreshIntegrations();
				showToast(
					`Strava connected. ${result.imported} runs imported, ${result.skipped} already present.`,
					'success',
				);
			} catch (err) {
				showToast(`Strava connect failed: ${err instanceof Error ? err.message : err}`, 'error');
			} finally {
				if (strava) strava.loading = false;
				// Remove the OAuth params from history so a refresh is clean.
				goto('/settings/integrations', { replaceState: true, noScroll: true });
			}
		}

		pageLoading = false;
	});

	async function toggle(index: number) {
		const item = integrations[index];

		if (item.provider === 'strava') {
			if (item.connected) {
				item.loading = true;
				try {
					await disconnectIntegration('strava');
					item.connected = false;
					item.lastSync = null;
					showToast('Strava disconnected.', 'success');
				} finally {
					item.loading = false;
				}
				return;
			}
			if (!isStravaConfigured()) {
				showToast('Strava is not configured on this build (missing PUBLIC_STRAVA_CLIENT_ID).', 'error');
				return;
			}
			// Redirect the window directly — Strava's OAuth page doesn't
			// frame cleanly and the callback must come back to us.
			window.location.href = stravaAuthUrl(window.location.origin);
			return;
		}

		// Fallback for the non-OAuth providers (placeholder-connect).
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

	// --- Strava bulk-zip import ---

	let zipProgress = $state<StravaZipProgress | null>(null);
	let zipError = $state('');

	async function handleZipSelect(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		zipError = '';
		zipProgress = { total: 0, imported: 0, skipped: 0, failed: 0, currentName: 'Reading archive…' };
		try {
			const result = await importStravaZip(file, (p) => {
				zipProgress = { ...p };
			});
			showToast(
				`Strava zip import: ${result.imported} new, ${result.skipped} already present${result.failed ? `, ${result.failed} failed` : ''}.`,
				'success',
			);
		} catch (err) {
			zipError = err instanceof Error ? err.message : String(err);
		} finally {
			input.value = '';
			// Leave the final summary visible for a moment, then clear.
			setTimeout(() => (zipProgress = null), 4000);
		}
	}

	async function handleSyncStrava(index: number) {
		const item = integrations[index];
		item.loading = true;
		try {
			const result = await syncStrava();
			await refreshIntegrations();
			showToast(
				`Strava sync complete. ${result.imported} new, ${result.skipped} already present${result.failed ? `, ${result.failed} failed` : ''}.`,
				'success',
			);
		} catch (err) {
			showToast(`Strava sync failed: ${err instanceof Error ? err.message : err}`, 'error');
		} finally {
			item.loading = false;
		}
	}
</script>

<div class="page">
	<p class="page-sub">Connect external services to sync your runs automatically.</p>

	{#if pageLoading}
		<p class="loading-text">&nbsp;</p>
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
					<div class="btn-group">
						{#if integration.connected && integration.provider === 'strava'}
							<button
								class="btn btn-sync"
								disabled={integration.loading}
								onclick={() => handleSyncStrava(i)}
							>
								{integration.loading ? 'Syncing...' : 'Sync now'}
							</button>
						{/if}
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
				</div>
			{/each}
		</div>

		<section class="card bulk-import">
			<h2>Bulk import from a Strava export</h2>
			<p class="card-sub">
				Import your full Strava history in one go. Download your data from
				<a href="https://www.strava.com/athlete/delete_your_account" target="_blank" rel="noopener noreferrer"
					>Strava → Settings → My Account → Download Your Data</a
				>, then drop the zip here. Runs already imported from your connected
				Strava account are skipped.
			</p>
			<label class="zip-btn">
				Choose Strava export zip
				<input type="file" accept=".zip,application/zip" onchange={handleZipSelect} hidden />
			</label>
			{#if zipError}
				<p class="zip-error">{zipError}</p>
			{/if}
			{#if zipProgress}
				<div class="zip-progress">
					{#if zipProgress.total > 0}
						<div class="zip-bar">
							<div
								class="zip-bar-fill"
								style="width: {Math.min(
									100,
									Math.round(
										((zipProgress.imported + zipProgress.skipped + zipProgress.failed) /
											zipProgress.total) *
											100,
									),
								)}%"
							></div>
						</div>
					{/if}
					<p class="zip-status">
						{#if zipProgress.total === 0}
							{zipProgress.currentName ?? '…'}
						{:else}
							{zipProgress.imported + zipProgress.skipped + zipProgress.failed} /
							{zipProgress.total} · {zipProgress.imported} imported ·
							{zipProgress.skipped} skipped{zipProgress.failed
								? ` · ${zipProgress.failed} failed`
								: ''}
							{#if zipProgress.currentName}
								<br /><span class="zip-current">{zipProgress.currentName}</span>
							{/if}
						{/if}
					</p>
				</div>
			{/if}
		</section>
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
		margin-bottom: var(--space-lg);
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
	.btn-group {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		flex-shrink: 0;
	}
	.btn-sync {
		background: var(--color-secondary, var(--color-primary));
		color: white;
		border: none;
	}
	.btn-sync:hover:not(:disabled) {
		filter: brightness(1.08);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-top: var(--space-xl);
	}
	.card h2 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0 0 var(--space-xs);
	}
	.card-sub {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
		line-height: 1.45;
	}
	.card-sub a {
		color: var(--color-primary);
	}
	.zip-btn {
		display: inline-block;
		padding: 0.5rem 0.9rem;
		background: var(--color-primary);
		color: white;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}
	.zip-btn:hover { filter: brightness(1.05); }
	.zip-error {
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
		color: var(--color-danger, #e53935);
	}
	.zip-progress {
		margin-top: var(--space-md);
	}
	.zip-bar {
		width: 100%;
		height: 6px;
		background: var(--color-border);
		border-radius: 999px;
		overflow: hidden;
	}
	.zip-bar-fill {
		height: 100%;
		background: var(--color-primary);
		transition: width 150ms linear;
	}
	.zip-status {
		margin: 0.5rem 0 0;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.zip-current {
		color: var(--color-text-tertiary);
		font-size: 0.75rem;
	}
</style>
