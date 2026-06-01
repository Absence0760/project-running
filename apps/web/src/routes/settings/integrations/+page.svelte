<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchIntegrations, connectIntegration, disconnectIntegration } from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import {
		stravaAuthUrl,
		completeStravaOAuth,
		mintStravaOAuthState,
		storeStravaOAuthState,
		syncStrava,
		isStravaConfigured,
	} from '$lib/integrations/strava';
	import { importStravaZip, type StravaZipProgress } from '$lib/integrations/strava-zip';
	import { importGarminBundle, type GarminZipProgress } from '$lib/integrations/garmin-zip';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';

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
		{ provider: 'strava', name: 'Strava', description: 'Sync activities automatically from your Strava account', icon: 'directions_run' },
		{ provider: 'parkrun', name: 'parkrun', description: 'Import your complete parkrun history', icon: 'emoji_events' },
		{ provider: 'garmin', name: 'Garmin Connect', description: 'Bulk-import .fit files (single activity or full Account Data export). Live OAuth needs Garmin developer-program approval.', icon: 'watch' },
		{ provider: 'healthkit', name: 'Apple HealthKit', description: 'Will sync on-device once the iOS app ships (coming soon).', icon: 'favorite' },
	];

	let integrations = $state<IntegrationUI[]>(
		providers.map((p) => ({ ...p, connected: false, lastSync: null, loading: false }))
	);

	let pageLoading = $state(true);
	let confirmingDisconnect = $state<number | null>(null);

	async function refreshIntegrations() {
		const saved = await fetchIntegrations();
		for (const ui of integrations) {
			const match = saved.find((s) => s.provider === ui.provider);
			ui.connected = Boolean(match);
			ui.lastSync = match?.last_sync_at ?? null;
		}
	}

	onMount(async () => {
		// fetchIntegrations returns [] silently when auth.user is null,
		// so a hard reload during the auth race rendered every row as
		// "Connect" (unconnected) even for runner who has parkrun +
		// strava connected per seed. Same poll pattern as /settings/
		// preferences + /settings/devices + /settings/account.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await refreshIntegrations();

		// OAuth callback: Strava redirects back to this page with a
		// `code` in the URL. Exchange it for tokens, then strip the
		// params so a refresh doesn't replay a dead single-use code.
		const params = $page.url.searchParams;
		if (params.has('code') && params.has('scope')) {
			const strava = integrations.find((i) => i.provider === 'strava');
			if (strava) strava.loading = true;
			try {
				const result = await completeStravaOAuth(params, $page.url.origin);
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

		if (item.connected) {
			confirmingDisconnect = index;
			return;
		}

		if (item.provider === 'strava') {
			if (!isStravaConfigured()) {
				showToast('Strava is not configured on this build (missing PUBLIC_STRAVA_CLIENT_ID).', 'error');
				return;
			}
			// OAuth 2.0 CSRF state. Mint, stash, then forward to Strava.
			// The callback handler verifies + clears via consumeState.
			// /audit/strava May 2026 Critical #1.
			const state = mintStravaOAuthState();
			storeStravaOAuthState(state);
			// Redirect the window directly — Strava's OAuth page doesn't
			// frame cleanly and the callback must come back to us.
			window.location.href = stravaAuthUrl(window.location.origin, state);
			return;
		}

		// Placeholder-connect for the non-OAuth providers.
		item.loading = true;
		try {
			await connectIntegration(item.provider);
			item.connected = true;
		} catch (err) {
			console.error('Integration connect failed:', err);
		} finally {
			item.loading = false;
		}
	}

	async function performDisconnect() {
		const index = confirmingDisconnect;
		if (index == null) return;
		const item = integrations[index];
		confirmingDisconnect = null;
		item.loading = true;
		try {
			await disconnectIntegration(item.provider);
			item.connected = false;
			item.lastSync = null;
			if (item.provider === 'strava') {
				showToast('Strava disconnected.', 'success');
			}
		} catch (err) {
			console.error('Integration disconnect failed:', err);
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

	// --- Garmin bulk import (single .fit OR full Account Data .zip) ---

	let garminProgress = $state<GarminZipProgress | null>(null);
	let garminError = $state('');

	async function handleGarminSelect(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		garminError = '';
		garminProgress = { total: 0, imported: 0, skipped: 0, failed: 0, currentName: 'Reading file…' };
		try {
			const result = await importGarminBundle(file, (p) => {
				garminProgress = { ...p };
			});
			showToast(
				`Garmin import: ${result.imported} new, ${result.skipped} already present${result.failed ? `, ${result.failed} failed` : ''}.`,
				'success',
			);
			if (result.hrZonesImported) {
				showToast('Imported your heart-rate zones from Garmin.', 'success');
			}
		} catch (err) {
			garminError = err instanceof Error ? err.message : String(err);
		} finally {
			input.value = '';
			setTimeout(() => (garminProgress = null), 4000);
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
	<header class="page-head">
		<p class="kicker">Settings</p>
		<h1>Integrations</h1>
		<p class="tagline">
			Pull your runs in from Strava, parkrun, Garmin, and Apple HealthKit — or drop in
			a bulk export zip if you'd rather not connect an account.
		</p>
	</header>

	{#if pageLoading}
		<div class="skeleton-stack" aria-hidden="true">
			{#each Array(4) as _, i (i)}
				<div class="skel-row">
					<span class="skel skel-icon"></span>
					<div class="skel-info">
						<span class="skel skel-line skel-w-30"></span>
						<span class="skel skel-line skel-w-60"></span>
					</div>
					<span class="skel skel-btn"></span>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">Loading integrations…</p>
	{:else}
		{#if integrations.every((i) => !i.connected)}
			<section class="card empty-card">
				<span class="material-symbols empty-icon" aria-hidden="true">link</span>
				<h3>No integrations connected</h3>
				<p class="empty-text">
					Connect Strava, parkrun, or Garmin below to keep your runs flowing in
					automatically. Or use the bulk-import cards if you'd rather drop in a
					one-off export.
				</p>
			</section>
		{/if}
		<section class="provider-section">
			<h2>Available integrations</h2>
			<div class="integration-list">
			{#each integrations as integration, i}
				<div class="integration-card" class:connected={integration.connected}>
					<div class="integration-icon" data-provider={integration.provider} aria-hidden="true">
						<span class="material-symbols">{integration.icon}</span>
					</div>
					<div class="integration-info">
						<h3>{integration.name}</h3>
						<p>{integration.description}</p>
						{#if integration.connected && integration.lastSync}
							<span class="last-sync">
								Last synced {new Date(integration.lastSync).toLocaleDateString(activeFormatLocale(), {
									day: 'numeric',
									month: 'short',
									hour: '2-digit',
									minute: '2-digit',
								})}
							</span>
						{/if}
						{#if integration.connected && integration.provider === 'strava'}
							<p class="sync-note">
								Sync pulls the last 90 days from Strava. For your full
								back-catalogue, use <strong>Bulk import from a Strava export</strong>
								below — that's the only path that brings in older activities.
							</p>
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
		</section>

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
				<p class="zip-error" role="alert">{zipError}</p>
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

		<section class="card bulk-import">
			<h2>Bulk import from a Garmin export</h2>
			<p class="card-sub">
				Drop a single <code>.fit</code> file (Garmin Connect → activity → "Export Original")
				or the <code>.zip</code> from
				<a href="https://www.garmin.com/account/datamanagement/exportdata/" target="_blank" rel="noopener noreferrer"
					>Garmin → Account Management → Request Your Data</a
				>. We parse <code>.fit</code> and any user-uploaded <code>.gpx</code> /
				<code>.tcx</code> originals inside the bundle. Already-imported runs (matched on
				the FIT file id) are skipped.
			</p>
			<label class="zip-btn">
				Choose Garmin export
				<input type="file" accept=".fit,.zip,application/octet-stream,application/zip" onchange={handleGarminSelect} hidden />
			</label>
			{#if garminError}
				<p class="zip-error" role="alert">{garminError}</p>
			{/if}
			{#if garminProgress}
				<div class="zip-progress">
					{#if garminProgress.total > 0}
						<div class="zip-bar">
							<div
								class="zip-bar-fill"
								style="width: {Math.min(
									100,
									Math.round(
										((garminProgress.imported + garminProgress.skipped + garminProgress.failed) /
											garminProgress.total) *
											100,
									),
								)}%"
							></div>
						</div>
					{/if}
					<p class="zip-status">
						{#if garminProgress.total === 0}
							{garminProgress.currentName ?? '…'}
						{:else}
							{garminProgress.imported + garminProgress.skipped + garminProgress.failed} /
							{garminProgress.total} · {garminProgress.imported} imported ·
							{garminProgress.skipped} skipped{garminProgress.failed
								? ` · ${garminProgress.failed} failed`
								: ''}
							{#if garminProgress.currentName}
								<br /><span class="zip-current">{garminProgress.currentName}</span>
							{/if}
						{/if}
					</p>
				</div>
			{/if}
		</section>
	{/if}
</div>

<ConfirmDialog
	open={confirmingDisconnect !== null}
	title="Disconnect integration?"
	message={confirmingDisconnect !== null
		? `Disconnect ${integrations[confirmingDisconnect].name}? Stored tokens will be removed and automatic syncing will stop. You can reconnect at any time.`
		: ''}
	confirmLabel="Disconnect"
	danger
	onconfirm={performDisconnect}
	oncancel={() => (confirmingDisconnect = null)}
/>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 64rem;
	}

	.page-head { margin-bottom: var(--space-xl); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.7rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	h1 { font-size: 1.6rem; font-weight: 700; margin: 0 0 var(--space-xs); }
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
	}

	.provider-section { margin-bottom: var(--space-xl); }
	.provider-section > h2 {
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		margin: 0 0 var(--space-md);
	}

	/* Empty-state card — matches /u/[id]'s shape. */
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		text-align: center;
		margin-bottom: var(--space-xl);
	}
	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.empty-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}

	/* Skeletons */
	.skeleton-stack { display: flex; flex-direction: column; gap: var(--space-md); }
	.skel-row {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		pointer-events: none;
	}
	.skel-icon { width: 2rem; height: 2rem; border-radius: var(--radius-md); flex-shrink: 0; }
	.skel-info { flex: 1; display: flex; flex-direction: column; gap: 0.5rem; }
	.skel-btn { width: 6rem; height: 2.2rem; border-radius: var(--radius-md); flex-shrink: 0; }
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line { height: 0.85rem; }
	.skel-w-30 { width: 30%; }
	.skel-w-60 { width: 60%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
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
		border-inline-start: 3px solid var(--color-secondary);
	}

	.integration-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.75rem;
		height: 2.75rem;
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		flex-shrink: 0;
	}
	.integration-icon .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.4rem;
	}
	.integration-icon[data-provider="strava"] {
		background: rgba(252, 76, 2, 0.12);
		color: #fc4c02;
	}
	.integration-icon[data-provider="parkrun"] {
		background: rgba(217, 122, 84, 0.14);
		color: var(--color-secondary);
	}
	.integration-icon[data-provider="garmin"] {
		background: rgba(0, 119, 200, 0.12);
		color: #0077c8;
	}
	.integration-icon[data-provider="healthkit"] {
		background: rgba(252, 61, 90, 0.12);
		color: #fc3d5a;
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
	.sync-note {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		margin: var(--space-sm) 0 0;
		line-height: 1.4;
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
