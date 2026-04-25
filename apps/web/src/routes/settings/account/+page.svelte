<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { supabase } from '$lib/supabase';
	import { downloadFile } from '$lib/gpx';
	import { fetchRuns } from '$lib/data';
	import {
		createBackup,
		restoreBackup,
		type BackupProgress,
		type RestoreProgress,
		type RestoreResult,
	} from '$lib/backup';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		unsubscribeFromPush,
		getCurrentSubscription,
	} from '$lib/push';

	let displayName = $state(auth.user?.display_name ?? '');
	let parkrunNumber = $state(auth.user?.parkrun_number ?? '');
	let dateOfBirth = $state('');
	let restingHr = $state('');
	let maxHr = $state('');
	let saving = $state(false);
	let saved = $state(false);
	let exporting = $state(false);
	let exportingJson = $state(false);

	let backingUp = $state(false);
	let backupProgress = $state<BackupProgress | null>(null);
	let restoring = $state(false);
	let restoreProgress = $state<RestoreProgress | null>(null);
	let restoreResult = $state<RestoreResult | null>(null);
	let restoreError = $state<string | null>(null);
	let restoreFileInput: HTMLInputElement;
	let showRestoreConfirm = $state(false);
	let pendingRestoreFile = $state<File | null>(null);

	let newPassword = $state('');
	let confirmPassword = $state('');
	let passwordSaving = $state(false);
	let passwordStatus = $state<string | null>(null);
	let passwordError = $state<string | null>(null);

	let parkrunImporting = $state(false);

	/// Kick the existing `parkrun-import` Edge Function with the
	/// user's stashed athlete number. The function does the scrape +
	/// runs insert; we just surface a status toast with what came
	/// back. One-button import — no OAuth, no tokens to manage.
	async function handleParkrunImport() {
		if (!parkrunNumber || parkrunNumber.trim().length === 0 || parkrunImporting) return;
		parkrunImporting = true;
		try {
			const { data: { session } } = await supabase.auth.getSession();
			if (!session) throw new Error('Not signed in');
			const url = `${import.meta.env.VITE_SUPABASE_URL ?? import.meta.env.PUBLIC_SUPABASE_URL}/functions/v1/parkrun-import`;
			const resp = await fetch(url, {
				method: 'POST',
				headers: {
					Authorization: `Bearer ${session.access_token}`,
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({ athleteNumber: parkrunNumber.trim() }),
			});
			if (!resp.ok) {
				const body = await resp.json().catch(() => ({}));
				throw new Error(body.error ?? `HTTP ${resp.status}`);
			}
			const body = await resp.json().catch(() => ({}));
			const imported = (body.imported as number) ?? 0;
			showToast(
				imported > 0
					? `Imported ${imported} parkrun result${imported === 1 ? '' : 's'}.`
					: 'No new parkrun results since last import.',
				'success',
			);
		} catch (err) {
			showToast(`parkrun import failed: ${(err as Error).message}`, 'error');
		} finally {
			parkrunImporting = false;
		}
	}

	onMount(async () => {
		if (!auth.user) return;
		// Load settings bag for DOB / HR fields.
		const { data } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', auth.user.id)
			.maybeSingle();
		if (data?.prefs && typeof data.prefs === 'object') {
			const p = data.prefs as Record<string, unknown>;
			dateOfBirth = (p.date_of_birth as string) ?? '';
			restingHr = (p.resting_hr_bpm as number)?.toString() ?? '';
			maxHr = (p.max_hr_bpm as number)?.toString() ?? '';
		}
		await loadIdentities();
		await refreshPushState();
	});

	// --- Web push notifications ---

	let pushSubscribed = $state(false);
	let pushBusy = $state(false);
	let pushPermissionState = $state<NotificationPermission | 'unsupported'>('default');
	const pushSupported = isPushSupported();

	async function refreshPushState() {
		pushPermissionState = pushPermission();
		if (!pushSupported) return;
		pushSubscribed = !!(await getCurrentSubscription());
	}

	async function handleEnablePush() {
		pushBusy = true;
		try {
			await subscribeToPush();
			await refreshPushState();
			showToast('Notifications enabled on this device.', 'success');
		} catch (e) {
			showToast(`Could not enable notifications: ${(e as Error).message}`, 'error');
		} finally {
			pushBusy = false;
		}
	}

	async function handleDisablePush() {
		pushBusy = true;
		try {
			await unsubscribeFromPush();
			await refreshPushState();
			showToast('Notifications disabled on this device.', 'success');
		} finally {
			pushBusy = false;
		}
	}

	async function handleSave() {
		if (!auth.user) return;
		saving = true;
		saved = false;
		await supabase.from('user_profiles').update({
			display_name: displayName || null,
			parkrun_number: parkrunNumber || null,
		}).eq('id', auth.user.id);

		// Persist DOB + HR into user_settings.prefs.
		const prefs: Record<string, unknown> = {};
		if (dateOfBirth) prefs.date_of_birth = dateOfBirth;
		if (restingHr) prefs.resting_hr_bpm = parseInt(restingHr, 10) || null;
		if (maxHr) prefs.max_hr_bpm = parseInt(maxHr, 10) || null;
		if (Object.keys(prefs).length > 0) {
			const { data } = await supabase
				.from('user_settings')
				.select('prefs')
				.eq('user_id', auth.user.id)
				.maybeSingle();
			const merged = { ...((data?.prefs as Record<string, unknown>) ?? {}), ...prefs };
			await supabase.from('user_settings').upsert({
				user_id: auth.user.id,
				prefs: merged,
				updated_at: new Date().toISOString(),
			});
		}
		saved = true;
		saving = false;
		setTimeout(() => (saved = false), 2000);
	}

	async function handleSavePassword() {
		if (newPassword.length < 6) { passwordError = 'Password must be at least 6 characters.'; return; }
		if (newPassword !== confirmPassword) { passwordError = 'Passwords do not match.'; return; }
		passwordSaving = true; passwordError = null; passwordStatus = null;
		const { error } = await supabase.auth.updateUser({ password: newPassword });
		passwordSaving = false;
		if (error) { passwordError = error.message; }
		else {
			passwordStatus = 'Password saved. You can now sign in with your email on any device.';
			newPassword = ''; confirmPassword = '';
			setTimeout(() => (passwordStatus = null), 5000);
		}
	}

	async function handleExportCsv() {
		exporting = true;
		try {
			const runs = await fetchRuns();
			const header = 'date,distance_m,duration_s,pace_s_per_km,source\n';
			const rows = runs.map((r) => {
				const pace = r.distance_m > 0 ? Math.round(r.duration_s / (r.distance_m / 1000)) : 0;
				return `${r.started_at},${r.distance_m},${r.duration_s},${pace},${r.source}`;
			}).join('\n');
			downloadFile(header + rows, 'runs_export.csv', 'text/csv');
		} finally { exporting = false; }
	}

	/// Single-file `runs.json` download. Same row shape as the
	/// `runs.json` entry inside a Full backup ZIP (and Android's
	/// equivalent), so scripts that consume one consume the other.
	/// `user_id` is stripped so the file is re-homeable; tracks aren't
	/// included — use the Full backup for a lossless copy with GPS.
	async function handleExportJson() {
		const userId = auth.user?.id;
		if (!userId) return;
		exportingJson = true;
		try {
			const { data, error } = await supabase
				.from('runs')
				.select('*')
				.eq('user_id', userId)
				.order('started_at', { ascending: false });
			if (error) throw error;
			const runs = (data ?? []).map((r) => {
				const { user_id: _uid, ...rest } = r as Record<string, unknown>;
				return rest;
			});
			const ts = new Date().toISOString().replace(/[:.]/g, '-');
			downloadFile(JSON.stringify(runs, null, 2), `runs-${ts}.json`, 'application/json');
		} catch (e) {
			showToast(`Export failed: ${(e as Error).message}`, 'error');
		} finally {
			exportingJson = false;
		}
	}

	async function handleBackup() {
		backingUp = true; backupProgress = null;
		try {
			const blob = await createBackup((p) => (backupProgress = p));
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			const ts = new Date().toISOString().replace(/[:.]/g, '-');
			a.href = url; a.download = `run-app-backup-${ts}.zip`;
			document.body.appendChild(a); a.click(); a.remove();
			URL.revokeObjectURL(url);
		} catch (e) { showToast(`Backup failed: ${(e as Error).message}`, 'error'); }
		finally { backingUp = false; backupProgress = null; }
	}

	function handleRestoreFile(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0]; if (!file) return;
		pendingRestoreFile = file;
		showRestoreConfirm = true;
	}

	async function confirmRestore() {
		showRestoreConfirm = false;
		const file = pendingRestoreFile;
		pendingRestoreFile = null;
		if (!file) return;
		restoring = true; restoreProgress = null; restoreResult = null; restoreError = null;
		try {
			const res = await restoreBackup(file, { onProgress: (p) => (restoreProgress = p) });
			restoreResult = res;
		} catch (err) { restoreError = (err as Error).message; }
		finally { restoring = false; restoreProgress = null; restoreFileInput.value = ''; }
	}

	function cancelRestore() {
		showRestoreConfirm = false;
		pendingRestoreFile = null;
		restoreFileInput.value = '';
	}

	// ─── Sign-in methods (linked identities) ─────────────────────────────
	// Backed by Supabase Auth's identity-link API. `getUserIdentities()`
	// returns one row per provider attached to the user; `linkIdentity()`
	// kicks off an OAuth redirect identical to fresh sign-in; the API
	// blocks unlink of the last remaining identity, but we mirror that
	// rule client-side so the button can give a useful message.
	interface Identity {
		identity_id: string;
		id?: string;
		provider: string;
		identity_data?: Record<string, unknown>;
		created_at?: string;
		last_sign_in_at?: string;
	}
	const LINKABLE_PROVIDERS = ['google', 'apple'] as const;
	type LinkableProvider = (typeof LINKABLE_PROVIDERS)[number];
	const PROVIDER_LABEL: Record<string, string> = {
		email: 'Email & password',
		google: 'Google',
		apple: 'Apple',
	};
	let identities = $state<Identity[]>([]);
	let identitiesLoading = $state(true);
	let identityError = $state<string | null>(null);
	let linkingProvider = $state<string | null>(null);
	let unlinkingProvider = $state<string | null>(null);

	async function loadIdentities() {
		identitiesLoading = true;
		identityError = null;
		try {
			const { data, error } = await supabase.auth.getUserIdentities();
			if (error) throw error;
			identities = (data?.identities ?? []) as unknown as Identity[];
		} catch (e) {
			identityError = (e as Error).message ?? 'Failed to load sign-in methods.';
		} finally {
			identitiesLoading = false;
		}
	}

	async function linkProvider(provider: LinkableProvider) {
		linkingProvider = provider;
		try {
			const { error } = await supabase.auth.linkIdentity({
				provider,
				options: { redirectTo: `${window.location.origin}/auth/callback` },
			});
			if (error) throw error;
			// Successful path navigates away to the OAuth provider. If we
			// reach here without redirect, surface a generic failure.
		} catch (e) {
			identityError = (e as Error).message ?? `Could not link ${PROVIDER_LABEL[provider]}.`;
			linkingProvider = null;
		}
	}

	async function unlinkProvider(identity: Identity) {
		if (identities.length <= 1) {
			identityError = 'You need at least one sign-in method. Link another before unlinking this one.';
			return;
		}
		const label = PROVIDER_LABEL[identity.provider] ?? identity.provider;
		if (!confirm(`Unlink ${label}? You won't be able to sign in with this method until you link it again.`)) {
			return;
		}
		unlinkingProvider = identity.provider;
		identityError = null;
		try {
			// Supabase's typing wants the full identity row from
			// `getUserIdentities()`, but the JS SDK only reads
			// `identity_id`. Cast to the SDK's shape.
			const { error } = await supabase.auth.unlinkIdentity(
				identity as unknown as Parameters<typeof supabase.auth.unlinkIdentity>[0]
			);
			if (error) throw error;
			showToast(`${label} sign-in unlinked.`);
			await loadIdentities();
		} catch (e) {
			identityError = (e as Error).message ?? `Could not unlink ${label}.`;
		} finally {
			unlinkingProvider = null;
		}
	}

	let linkedProviderSet = $derived(new Set(identities.map((i) => i.provider)));
	let unlinkedProviders = $derived(LINKABLE_PROVIDERS.filter((p) => !linkedProviderSet.has(p)));

	let showDeleteAccount = $state(false);
	let deleting = $state(false);

	async function handleDeleteAccount() {
		showDeleteAccount = false;
		deleting = true;
		try {
			const { data: { session } } = await supabase.auth.getSession();
			if (!session) throw new Error('Not signed in');
			const resp = await fetch(
				`${import.meta.env.VITE_SUPABASE_URL ?? import.meta.env.PUBLIC_SUPABASE_URL}/functions/v1/delete-account`,
				{
					method: 'POST',
					headers: {
						Authorization: `Bearer ${session.access_token}`,
						'Content-Type': 'application/json',
					},
				},
			);
			if (!resp.ok) {
				const body = await resp.json().catch(() => ({}));
				throw new Error(body.error ?? `HTTP ${resp.status}`);
			}
			await auth.logout();
			goto('/login');
		} catch (e) {
			showToast(`Account deletion failed: ${(e as Error).message}`, 'error');
		} finally {
			deleting = false;
		}
	}
</script>

<div class="page">
	<!-- Profile -->
	<section class="card">
		<h2>Profile</h2>
		<div class="form-grid">
			<label>
				<span class="label-text">Display Name</span>
				<input type="text" bind:value={displayName} />
			</label>
			<label>
				<span class="label-text">Email</span>
				<input type="email" value={auth.user?.email ?? ''} disabled />
			</label>
			<label>
				<span class="label-text">parkrun Athlete Number</span>
				<input type="text" bind:value={parkrunNumber} placeholder="A123456" />
				{#if parkrunNumber && parkrunNumber.trim().length > 0}
					<button
						type="button"
						class="btn btn-outline btn-sm parkrun-import-btn"
						onclick={handleParkrunImport}
						disabled={parkrunImporting}
					>
						{parkrunImporting ? 'Importing…' : 'Pull latest parkrun results'}
					</button>
				{/if}
			</label>
			<label>
				<span class="label-text">Date of Birth</span>
				<input type="date" bind:value={dateOfBirth} />
			</label>
			<label>
				<span class="label-text">Resting HR (bpm)</span>
				<input type="number" bind:value={restingHr} placeholder="e.g. 52" min="30" max="120" />
			</label>
			<label>
				<span class="label-text">Max HR (bpm)</span>
				<input type="number" bind:value={maxHr} placeholder="e.g. 190 (or leave blank for 220-age)" min="100" max="230" />
			</label>
		</div>
		<button class="btn btn-primary btn-save" onclick={handleSave} disabled={saving}>
			{saving ? 'Saving...' : saved ? 'Saved!' : 'Save Profile'}
		</button>
	</section>

	<!-- Sign-in methods -->
	<section class="card">
		<h2>Sign-in Methods</h2>
		<p class="section-desc">
			Methods you can use to sign in to this account. Linking another method opens an OAuth
			redirect just like signing in. You need at least one method linked at all times.
		</p>

		{#if identitiesLoading}
			<p class="muted">Loading…</p>
		{:else}
			<ul class="identity-list">
				{#each identities as id (id.identity_id)}
					{@const label = PROVIDER_LABEL[id.provider] ?? id.provider}
					{@const email = (id.identity_data?.email as string) ?? ''}
					<li class="identity-row">
						<span class="provider-icon" data-provider={id.provider} aria-hidden="true">
							{#if id.provider === 'google'}
								<svg viewBox="0 0 24 24" width="20" height="20">
									<path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
									<path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
									<path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
									<path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
								</svg>
							{:else if id.provider === 'apple'}
								<svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
									<path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
								</svg>
							{:else}
								<span class="material-symbols">mail</span>
							{/if}
						</span>
						<div class="identity-info">
							<strong>{label}</strong>
							{#if email}<span class="identity-meta">{email}</span>{/if}
							{#if id.created_at}
								<span class="identity-meta">
									Linked {new Date(id.created_at).toLocaleDateString(undefined, {
										year: 'numeric', month: 'short', day: 'numeric',
									})}
								</span>
							{/if}
						</div>
						<button
							class="btn btn-outline btn-sm"
							onclick={() => unlinkProvider(id)}
							disabled={unlinkingProvider === id.provider || identities.length <= 1}
							title={identities.length <= 1
								? 'Link another method first — you need at least one to sign in.'
								: ''}
						>
							{unlinkingProvider === id.provider ? 'Unlinking…' : 'Unlink'}
						</button>
					</li>
				{/each}
			</ul>

			{#if unlinkedProviders.length > 0}
				<div class="link-buttons">
					{#each unlinkedProviders as provider}
						{@const label = PROVIDER_LABEL[provider]}
						{@const busy = linkingProvider === provider}
						<button
							class="btn btn-provider btn-{provider}"
							onclick={() => linkProvider(provider)}
							disabled={linkingProvider !== null}
						>
							{#if provider === 'google'}
								<svg class="oauth-icon" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
									<path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
									<path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
									<path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
									<path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
								</svg>
							{:else if provider === 'apple'}
								<svg class="oauth-icon" viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
									<path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
								</svg>
							{/if}
							<span>{busy ? `Linking ${label}…` : `Link ${label}`}</span>
						</button>
					{/each}
				</div>
			{/if}
		{/if}

		{#if identityError}<p class="error-text">{identityError}</p>{/if}
	</section>

	<!-- Password -->
	<section class="card">
		<h2>Sign-in Password</h2>
		<p class="section-desc">
			Set or change the password for signing in with your email. If you signed up via Google
			or Apple, set one here to enable email+password sign-in on devices that don't support
			social login (e.g. the Wear OS watch app).
		</p>
		<div class="form-grid">
			<label>
				<span class="label-text">New Password</span>
				<input type="password" autocomplete="new-password" bind:value={newPassword} placeholder="At least 6 characters" />
			</label>
			<label>
				<span class="label-text">Confirm Password</span>
				<input type="password" autocomplete="new-password" bind:value={confirmPassword} />
			</label>
		</div>
		{#if passwordError}<p class="error-text">{passwordError}</p>{/if}
		{#if passwordStatus}<p class="ok-text">{passwordStatus}</p>{/if}
		<button class="btn btn-primary btn-save" onclick={handleSavePassword} disabled={passwordSaving || !newPassword || !confirmPassword}>
			{passwordSaving ? 'Saving...' : 'Save Password'}
		</button>
	</section>

	<!-- Notifications -->
	<section class="card">
		<h2>Notifications</h2>
		{#if !pushSupported}
			<p class="section-desc">
				This browser doesn't support web push, or this build was deployed without
				a <code>PUBLIC_VAPID_PUBLIC_KEY</code>. Notifications are off.
			</p>
		{:else if pushPermissionState === 'denied'}
			<p class="section-desc">
				Notifications are blocked at the browser level. Re-enable them in your
				browser's site settings, then come back and toggle on.
			</p>
		{:else}
			<p class="section-desc">
				Get a system notification when a club event you're attending is starting,
				when a race goes live, or when an admin posts an update. Per-device — each
				browser / phone toggles independently.
			</p>
			<div class="btn-row">
				{#if pushSubscribed}
					<button class="btn btn-outline" onclick={handleDisablePush} disabled={pushBusy}>
						<span class="material-symbols">notifications_off</span>
						{pushBusy ? 'Updating...' : 'Disable notifications'}
					</button>
				{:else}
					<button class="btn btn-primary" onclick={handleEnablePush} disabled={pushBusy}>
						<span class="material-symbols">notifications_active</span>
						{pushBusy ? 'Enabling...' : 'Enable notifications'}
					</button>
				{/if}
			</div>
		{/if}
	</section>

	<!-- Backup & Restore -->
	<section class="card">
		<h2>Backup & Restore</h2>
		<p class="section-desc">
			Full backup includes every run with its GPS trace, your routes, profile, and preferences.
		</p>
		<div class="btn-row">
			<button class="btn btn-primary" onclick={handleBackup} disabled={backingUp || restoring}>
				<span class="material-symbols">archive</span>
				{backingUp ? (backupProgress ? `${backupProgress.stage}...` : 'Backing up...') : 'Download full backup'}
			</button>
			<button class="btn btn-outline" onclick={() => restoreFileInput.click()} disabled={backingUp || restoring}>
				<span class="material-symbols">unarchive</span>
				{restoring ? (restoreProgress ? `${restoreProgress.stage}...` : 'Restoring...') : 'Restore from backup'}
			</button>
			<input bind:this={restoreFileInput} type="file" accept=".zip" onchange={handleRestoreFile} style="display: none" />
		</div>
		{#if restoreResult}
			<p class="ok-text">
				Restored {restoreResult.runsImported} runs, {restoreResult.tracksUploaded} tracks, {restoreResult.routesImported} routes.
				{#if restoreResult.warnings.length > 0}<br /><small>{restoreResult.warnings.length} warnings (see console).</small>{/if}
			</p>
		{/if}
		{#if restoreError}<p class="error-text">Restore failed: {restoreError}</p>{/if}
	</section>

	<!-- Data Export -->
	<section class="card">
		<h2>Data Export</h2>
		<p class="section-desc">
			CSV for spreadsheet analysis, or a single <code>runs.json</code> for scripts —
			same row shape as the <code>runs.json</code> inside a Full backup. No GPS traces in either;
			use Full backup for a lossless copy.
		</p>
		<div class="btn-row">
			<button class="btn btn-outline" onclick={handleExportCsv} disabled={exporting || exportingJson}>
				<span class="material-symbols">download</span>
				{exporting ? 'Exporting...' : 'Export All Runs (CSV)'}
			</button>
			<button class="btn btn-outline" onclick={handleExportJson} disabled={exporting || exportingJson}>
				<span class="material-symbols">code</span>
				{exportingJson ? 'Exporting...' : 'Export All Runs (JSON)'}
			</button>
		</div>
	</section>

	<ConfirmDialog
		open={showRestoreConfirm}
		title="Restore from backup"
		message={`Restore from "${pendingRestoreFile?.name ?? ''}"? This adds or overwrites runs matching IDs in the backup.`}
		confirmLabel="Restore"
		onconfirm={confirmRestore}
		oncancel={cancelRestore}
		danger
	/>

	<!-- Danger zone -->
	<section class="card card-danger">
		<h2 class="danger-heading">Danger Zone</h2>
		<p class="section-desc">Permanently delete your account and all associated data. This cannot be undone.</p>
		<button class="btn btn-danger" onclick={() => (showDeleteAccount = true)} disabled={deleting}>
			{deleting ? 'Deleting...' : 'Delete Account'}
		</button>
	</section>
</div>

<ConfirmDialog
	open={showDeleteAccount}
	title="Delete your account?"
	message="This permanently deletes your account, all runs, routes, tracks, club memberships, and preferences. This cannot be undone. Download a backup first if you want to keep your data."
	confirmLabel="Delete my account"
	danger
	onconfirm={handleDeleteAccount}
	oncancel={() => (showDeleteAccount = false)}
/>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 64rem; }
	.page-header { margin-bottom: var(--space-xl); }
	h1 { font-size: 1.5rem; font-weight: 700; }
	h2 { font-size: 0.9rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: var(--space-lg); }
	.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); margin-bottom: var(--space-xl); }
	.card-danger { border-color: rgba(229, 57, 53, 0.3); }
	.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md); margin-bottom: var(--space-lg); }
	.label-text { display: block; font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary); margin-bottom: var(--space-xs); }
	input { width: 100%; padding: var(--space-sm) var(--space-md); border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.9rem; background: var(--color-bg); }
	input:focus { outline: none; border-color: var(--color-primary); }
	input:disabled { opacity: 0.6; cursor: not-allowed; }
	.section-desc { font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: var(--space-md); line-height: 1.5; }
	.btn-save { width: auto; }
	.btn-row { display: flex; gap: var(--space-sm); flex-wrap: wrap; }
	.error-text { color: #ef5350; font-size: 0.85rem; margin-top: var(--space-sm); }
	.ok-text { color: #66bb6a; font-size: 0.85rem; margin-top: var(--space-sm); }
	.danger-heading { color: var(--color-danger); }
	.material-symbols { font-family: 'Material Symbols Outlined'; font-size: 1.1rem; }
	.muted { color: var(--color-text-tertiary); font-size: 0.9rem; }
	.identity-list { list-style: none; padding: 0; margin: 0 0 var(--space-md); display: flex; flex-direction: column; gap: var(--space-sm); }
	.identity-row { display: flex; align-items: center; gap: var(--space-md); padding: var(--space-sm) var(--space-md); border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg); }
	.identity-info { flex: 1; display: flex; flex-direction: column; gap: 0.15rem; min-width: 0; }
	.identity-info strong { font-size: 0.95rem; }
	.identity-meta { font-size: 0.8rem; color: var(--color-text-secondary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.btn-sm { padding: 0.35rem 0.85rem; font-size: 0.8rem; }
	.link-buttons { display: flex; flex-wrap: wrap; gap: var(--space-sm); }
	.btn-provider {
		gap: 0.6rem;
		padding: var(--space-sm) var(--space-lg);
		border: 1.5px solid var(--color-border);
		font-weight: 600;
	}
	.btn-provider:disabled { opacity: 0.6; cursor: not-allowed; }
	.btn-google {
		background: var(--color-surface);
		color: var(--color-text);
	}
	.btn-google:hover:not(:disabled) {
		border-color: var(--color-text-secondary);
		box-shadow: var(--shadow-sm);
	}
	.btn-apple {
		background: #000;
		border-color: #000;
		color: #FFF;
	}
	.btn-apple:hover:not(:disabled) { background: #1a1a1a; }
	.oauth-icon { flex-shrink: 0; display: block; }
	.provider-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		flex-shrink: 0;
	}
	.provider-icon[data-provider="apple"] { background: #000; color: #FFF; border-color: #000; }
	.provider-icon[data-provider="email"] { background: var(--color-primary-light); color: var(--color-primary); border-color: transparent; }
</style>
