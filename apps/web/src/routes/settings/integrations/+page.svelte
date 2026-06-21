<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchIntegrations,
		connectIntegration,
		disconnectIntegration,
		isRunSignUpConfigured,
		isChronoTrackConfigured,
	} from '$lib/core/data';
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
		icon: string;
		connected: boolean;
		lastSync: string | null;
		loading: boolean;
	}

	// Static shape only (brand name + icon). The translatable description is
	// NOT stored here — it's rendered reactively in the template via m() so it
	// tracks locale changes (storing it in the integrations $state below would
	// capture one locale at init).
	const providers: Omit<IntegrationUI, 'connected' | 'lastSync' | 'loading'>[] = [
		{ provider: 'strava', name: 'Strava', icon: 'directions_run' },
		{ provider: 'parkrun', name: 'parkrun', icon: 'emoji_events' },
		{ provider: 'garmin', name: 'Garmin Connect', icon: 'watch' },
		{ provider: 'healthkit', name: 'Apple HealthKit', icon: 'favorite' },
	];

	let integrations = $state<IntegrationUI[]>(
		providers.map((p) => ({ ...p, connected: false, lastSync: null, loading: false }))
	);

	let pageLoading = $state(true);
	let confirmingDisconnect = $state<number | null>(null);

	// RunSignUp race-results import runs through the race-results-import EF (no
	// stored integration row). The whole leg is gated on a server-side API key;
	// probe it once so the card can show the unavailable explainer fail-closed.
	let runSignUpAvailable = $state(false);

	// ChronoTrack race-results import runs through the same EF behind its own
	// CHRONOTRACK_* credential gate; probe it once for the same fail-closed card.
	let chronoTrackAvailable = $state(false);

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
		// strava connected per seed.
		await auth.ready();
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
					m('settingsIntegrations.stravaConnected', { imported: result.imported, skipped: result.skipped }),
					'success',
				);
			} catch (err) {
				showToast(m('settingsIntegrations.stravaConnectFailed', { error: err instanceof Error ? err.message : String(err) }), 'error');
			} finally {
				if (strava) strava.loading = false;
				// Remove the OAuth params from history so a refresh is clean.
				goto('/settings/integrations', { replaceState: true, noScroll: true });
			}
		}

		try {
			runSignUpAvailable = await isRunSignUpConfigured();
		} catch {
			runSignUpAvailable = false;
		}

		try {
			chronoTrackAvailable = await isChronoTrackConfigured();
		} catch {
			chronoTrackAvailable = false;
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
				showToast(m('settingsIntegrations.stravaNotConfigured'), 'error');
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
			showToast(
				m('settingsIntegrations.connectFailed', {
					error: err instanceof Error ? err.message : String(err)
				}),
				'error'
			);
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
				showToast(m('settingsIntegrations.stravaDisconnected'), 'success');
			}
		} catch (err) {
			showToast(
				m('settingsIntegrations.disconnectFailed', {
					error: err instanceof Error ? err.message : String(err)
				}),
				'error'
			);
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
		zipProgress = { total: 0, imported: 0, skipped: 0, failed: 0, currentName: m('settingsIntegrations.readingArchive') };
		try {
			const result = await importStravaZip(file, (p) => {
				zipProgress = { ...p };
			});
			showToast(
				result.failed
					? m('settingsIntegrations.stravaZipImportWithFailed', { imported: result.imported, skipped: result.skipped, failed: result.failed })
					: m('settingsIntegrations.stravaZipImport', { imported: result.imported, skipped: result.skipped }),
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
		garminProgress = { total: 0, imported: 0, skipped: 0, failed: 0, currentName: m('settingsIntegrations.readingFile') };
		try {
			const result = await importGarminBundle(file, (p) => {
				garminProgress = { ...p };
			});
			showToast(
				result.failed
					? m('settingsIntegrations.garminImportWithFailed', { imported: result.imported, skipped: result.skipped, failed: result.failed })
					: m('settingsIntegrations.garminImport', { imported: result.imported, skipped: result.skipped }),
				'success',
			);
			if (result.hrZonesImported) {
				showToast(m('settingsIntegrations.garminHrZonesImported'), 'success');
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
				result.failed
					? m('settingsIntegrations.stravaSyncCompleteWithFailed', { imported: result.imported, skipped: result.skipped, failed: result.failed })
					: m('settingsIntegrations.stravaSyncComplete', { imported: result.imported, skipped: result.skipped }),
				'success',
			);
		} catch (err) {
			showToast(m('settingsIntegrations.stravaSyncFailed', { error: err instanceof Error ? err.message : String(err) }), 'error');
		} finally {
			item.loading = false;
		}
	}
</script>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('shell.settings')}</p>
		<h1>{m('settingsIntegrations.title')}</h1>
		<p class="tagline">
			{m('settingsIntegrations.tagline')}
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
		<p class="sr-only" role="status">{m('settingsIntegrations.loading')}</p>
	{:else}
		{#if integrations.every((i) => !i.connected)}
			<section class="card empty-card">
				<span class="material-symbols empty-icon" aria-hidden="true">link</span>
				<h3>{m('settingsIntegrations.emptyTitle')}</h3>
				<p class="empty-text">
					{m('settingsIntegrations.emptyText')}
				</p>
			</section>
		{/if}
		<section class="provider-section">
			<h2>{m('settingsIntegrations.availableHeading')}</h2>
			<div class="integration-list">
			{#each integrations as integration, i}
				<div class="integration-card" class:connected={integration.connected}>
					<div class="integration-icon" data-provider={integration.provider} aria-hidden="true">
						<span class="material-symbols">{integration.icon}</span>
					</div>
					<div class="integration-info">
						<h3>{integration.name}</h3>
						<p>{m(`settingsIntegrations.${integration.provider}Description` as MessageKey)}</p>
						{#if integration.connected && integration.lastSync}
							<span class="last-sync">
								{m('settingsIntegrations.lastSynced', { date: new Date(integration.lastSync).toLocaleDateString(activeFormatLocale(), {
									day: 'numeric',
									month: 'short',
									hour: '2-digit',
									minute: '2-digit',
								}) })}
							</span>
						{/if}
						{#if integration.connected && integration.provider === 'strava'}
							<p class="sync-note">
								{m('settingsIntegrations.syncNotePrefix')}<strong>{m('settingsIntegrations.syncNoteBold')}</strong>{m('settingsIntegrations.syncNoteSuffix')}
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
								{integration.loading ? m('settingsIntegrations.syncing') : m('settingsIntegrations.syncNow')}
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
								{integration.connected ? m('settingsIntegrations.disconnect') : m('settingsIntegrations.connect')}
							{/if}
						</button>
					</div>
				</div>
			{/each}
			</div>
		</section>

		<section class="card bulk-import">
			<h2>{m('settingsIntegrations.stravaBulkHeading')}</h2>
			<p class="card-sub">
				{m('settingsIntegrations.stravaBulkPrefix')}<a href="https://www.strava.com/athlete/delete_your_account" target="_blank" rel="noopener noreferrer"
					>{m('settingsIntegrations.stravaBulkLink')}</a
				>{m('settingsIntegrations.stravaBulkSuffix')}
			</p>
			<label class="zip-btn">
				{m('settingsIntegrations.chooseStravaZip')}
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
							{m('settingsIntegrations.progressDone', { done: zipProgress.imported + zipProgress.skipped + zipProgress.failed, total: zipProgress.total })} · {m('settingsIntegrations.progressImported', { imported: zipProgress.imported })} ·
							{m('settingsIntegrations.progressSkipped', { skipped: zipProgress.skipped })}{zipProgress.failed
								? ` · ${m('settingsIntegrations.progressFailed', { failed: zipProgress.failed })}`
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
			<h2>{m('settingsIntegrations.garminBulkHeading')}</h2>
			<p class="card-sub">
				{m('settingsIntegrations.garminBulkFrag1')}<code>.fit</code>{m('settingsIntegrations.garminBulkFrag2')}<code>.zip</code>{m('settingsIntegrations.garminBulkFrag3')}<a href="https://www.garmin.com/account/datamanagement/exportdata/" target="_blank" rel="noopener noreferrer"
					>{m('settingsIntegrations.garminBulkLink')}</a
				>{m('settingsIntegrations.garminBulkFrag4')}<code>.fit</code>{m('settingsIntegrations.garminBulkFrag5')}<code>.gpx</code> /
				<code>.tcx</code>{m('settingsIntegrations.garminBulkFrag6')}
			</p>
			<label class="zip-btn">
				{m('settingsIntegrations.chooseGarminExport')}
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
							{m('settingsIntegrations.progressDone', { done: garminProgress.imported + garminProgress.skipped + garminProgress.failed, total: garminProgress.total })} · {m('settingsIntegrations.progressImported', { imported: garminProgress.imported })} ·
							{m('settingsIntegrations.progressSkipped', { skipped: garminProgress.skipped })}{garminProgress.failed
								? ` · ${m('settingsIntegrations.progressFailed', { failed: garminProgress.failed })}`
								: ''}
							{#if garminProgress.currentName}
								<br /><span class="zip-current">{garminProgress.currentName}</span>
							{/if}
						{/if}
					</p>
				</div>
			{/if}
		</section>

		<section class="card runsignup-card" data-testid="runsignup-card">
			<div class="integration-icon" data-provider="runsignup" aria-hidden="true">
				<span class="material-symbols">flag</span>
			</div>
			<div class="runsignup-body">
				<h2>{m('integrations.runsignup')}</h2>
				<p class="card-sub">{m('integrations.runsignupConnect')}</p>
				{#if runSignUpAvailable}
					<a class="btn btn-connect" href="/races" data-testid="runsignup-open">
						{m('integrations.runsignupOpen')}
					</a>
				{:else}
					<p class="runsignup-unavailable" data-testid="runsignup-unavailable" role="status">
						{m('integrations.runsignupUnavailable')}
					</p>
				{/if}
			</div>
		</section>

		<section class="card runsignup-card" data-testid="chronotrack-card">
			<div class="integration-icon" data-provider="chronotrack" aria-hidden="true">
				<span class="material-symbols">timer</span>
			</div>
			<div class="runsignup-body">
				<h2>{m('integrations.chronotrack')}</h2>
				<p class="card-sub">{m('integrations.chronotrackConnect')}</p>
				{#if chronoTrackAvailable}
					<a class="btn btn-connect" href="/races" data-testid="chronotrack-open">
						{m('integrations.chronotrackOpen')}
					</a>
				{:else}
					<p class="runsignup-unavailable" data-testid="chronotrack-unavailable" role="status">
						{m('integrations.chronotrackUnavailable')}
					</p>
				{/if}
			</div>
		</section>
	{/if}
</div>

<ConfirmDialog
	open={confirmingDisconnect !== null}
	title={m('settingsIntegrations.disconnectDialogTitle')}
	message={confirmingDisconnect !== null
		? m('settingsIntegrations.disconnectDialogMessage', { name: integrations[confirmingDisconnect].name })
		: ''}
	confirmLabel={m('settingsIntegrations.disconnect')}
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
	.integration-icon[data-provider="runsignup"] {
		background: rgba(217, 142, 207, 0.14);
		color: #b85aad;
	}
	.integration-icon[data-provider="chronotrack"] {
		background: rgba(56, 142, 142, 0.14);
		color: #2f7e7e;
	}

	.runsignup-card {
		display: flex;
		gap: var(--space-md);
		align-items: flex-start;
	}
	.runsignup-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		align-items: flex-start;
	}
	.runsignup-body h2 { margin: 0; }
	.runsignup-unavailable {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		margin: 0;
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
