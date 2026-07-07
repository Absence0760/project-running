<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import { supabase } from '$lib/core/supabase';
	import { TABLES } from '$lib/core/schema';
	import { PUBLIC_SUPABASE_URL } from '$env/static/public';
	import { downloadFile } from '$lib/routes/gpx';
	import { fetchRuns, uploadAvatar, removeAvatar } from '$lib/core/data';
	import {
		createBackup,
		restoreBackup,
		type BackupProgress,
		type RestoreProgress,
		type RestoreResult,
	} from '$lib/backup/backup';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		unsubscribeFromPush,
		getCurrentSubscription,
	} from '$lib/util/push';
	import { cloudExport } from '$lib/backup/cloud_export';
	import { m } from '$lib/i18n/store.svelte';

	let displayName = $state(auth.user?.display_name ?? '');
	let avatarUrl = $state<string | null>(auth.user?.avatar_url ?? null);
	let avatarBusy = $state(false);
	let avatarFileInput: HTMLInputElement;
	let parkrunNumber = $state(auth.user?.parkrun_number ?? '');
	let dateOfBirth = $state('');
	let restingHr = $state('');
	let maxHr = $state('');
	// Date of birth is Art 9 demographic data — its persistence is gated
	// on explicit health-data consent, mirroring the Demographics section
	// of /settings/preferences. Without this, the account page was an
	// unguarded second write path for DOB into user_settings.prefs
	// (the DB lock trigger only protects user_profiles.health_data_consent_at).
	let healthDataConsent = $state(false);
	let healthDataConsentAt = $state<string | null>(null);
	let coachConsentAt = $state<string | null>(null);
	let coachConsentWithdrawing = $state(false);
	let saving = $state(false);
	let saved = $state(false);
	let exporting = $state(false);
	let exportingJson = $state(false);
	let exportingGpx = $state(false);
	let exportingArchive = $state(false);

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
			if (!session) throw new Error(m('settingsAccount.notSignedIn'));
			const url = `${PUBLIC_SUPABASE_URL}/functions/v1/parkrun-import`;
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
					? m('settingsAccount.parkrunImported', { n: imported })
					: m('settingsAccount.parkrunNoneNew'),
				'success',
			);
		} catch (err) {
			showToast(m('settingsAccount.parkrunImportFailed', { error: (err as Error).message }), 'error');
		} finally {
			parkrunImporting = false;
		}
	}

	onMount(async () => {
		// `auth.svelte.ts` flips loading=false before the async fetchUser
		// resolves, so a hard reload onto /settings/account can mount
		// with auth.user still null. The $state declarations above
		// initialised from `auth.user?.X ?? ''` at module-evaluate time
		// — empty if auth wasn't ready yet. Wait for the form to hydrate
		// with the saved profile values before the user can type into an
		// empty field and clobber them on save.
		await auth.ready();
		if (!auth.user) return;
		displayName = auth.user.display_name ?? '';
		parkrunNumber = auth.user.parkrun_number ?? '';
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
		// Self-read goes through the get_my_profile() SECURITY DEFINER RPC:
		// health_data_consent_at is deny-by-default for direct authenticated
		// SELECTs (column lockdown, 20260707_001) — a direct select 403s.
		const { data: prof } = await supabase.rpc('get_my_profile');
		// Sync the avatar from the freshly-read profile — the $state was seeded
		// from auth.user at component init, which may not have hydrated yet.
		avatarUrl = (prof?.avatar_url as string | null) ?? null;
		healthDataConsentAt = (prof?.health_data_consent_at as string | null) ?? null;
		coachConsentAt = (prof?.coach_consent_at as string | null) ?? null;
		// Pre-tick the box if consent is already on record so a user can
		// edit DOB / HR without re-consenting on every visit.
		healthDataConsent = healthDataConsentAt != null;
		await loadIdentities();
		await refreshPushState();
	});

	async function withdrawCoachConsent() {
		if (coachConsentWithdrawing) return;
		coachConsentWithdrawing = true;
		try {
			// Sanctioned inverse of record_coach_consent(): clears the
			// server-held stamp. The coach handler's 403 gate then re-blocks
			// the Coach until the user re-consents on the Coach surface.
			const { error } = await supabase.rpc('withdraw_coach_consent');
			if (error) throw new Error(error.message);
			coachConsentAt = null;
			showToast(m('settingsAccount.coachConsentWithdrawn'), 'success');
		} catch (e) {
			showToast(m('settingsAccount.saveFailed', { error: (e as Error).message }), 'error');
		} finally {
			coachConsentWithdrawing = false;
		}
	}

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
			showToast(m('settingsAccount.notificationsEnabled'), 'success');
		} catch (e) {
			showToast(m('settingsAccount.notificationsEnableFailed', { error: (e as Error).message }), 'error');
		} finally {
			pushBusy = false;
		}
	}

	async function handleDisablePush() {
		pushBusy = true;
		try {
			await unsubscribeFromPush();
			await refreshPushState();
			showToast(m('settingsAccount.notificationsDisabled'), 'success');
		} catch (e) {
			// Symmetrical to handleEnablePush above — surface failures
			// rather than letting them propagate uncaught. Pre-fix, a
			// network drop / Service Worker hiccup on disable left the
			// user looking at a non-changing toggle with no feedback.
			showToast(
				m('settingsAccount.notificationsDisableFailed', { error: (e as Error).message }),
				'error',
			);
		} finally {
			pushBusy = false;
		}
	}

	async function handleAvatarSelect(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = ''; // allow re-picking the same file after an error
		if (!file) return;
		avatarBusy = true;
		try {
			avatarUrl = await uploadAvatar(file);
			// Re-hydrate the auth store so the sidebar + feed avatars update too.
			await auth.fetchUser();
			showToast(m('settingsAccount.avatarSaved'), 'success');
		} catch (err) {
			showToast(
				m('settingsAccount.avatarFailed', {
					error: err instanceof Error ? err.message : String(err),
				}),
				'error',
			);
		} finally {
			avatarBusy = false;
		}
	}

	async function handleAvatarRemove() {
		avatarBusy = true;
		try {
			await removeAvatar();
			avatarUrl = null;
			await auth.fetchUser();
			showToast(m('settingsAccount.avatarRemoved'), 'success');
		} catch (err) {
			showToast(
				m('settingsAccount.avatarFailed', {
					error: err instanceof Error ? err.message : String(err),
				}),
				'error',
			);
		} finally {
			avatarBusy = false;
		}
	}

	async function handleSave() {
		if (!auth.user) return;
		saving = true;
		saved = false;

		// Date of birth is consent-gated. Fail loudly rather than silently
		// dropping it, mirroring /settings/preferences.
		if (dateOfBirth && !healthDataConsent) {
			showToast(
				m('settingsAccount.dobConsentRequired'),
				'error',
			);
			saving = false;
			return;
		}
		if (healthDataConsent && healthDataConsentAt == null) {
			// Grant — stamp the consent timestamp server-side via the
			// SECURITY DEFINER RPC (first-stamp-wins; a direct write of
			// health_data_consent_at is rejected by the lock trigger,
			// migration 20261118_001).
			const { data: stampedAt, error: consentErr } =
				await supabase.rpc('grant_health_data_consent');
			if (consentErr) {
				showToast(m('settingsAccount.saveFailed', { error: consentErr.message }), 'error');
				saving = false;
				return;
			}
			if (stampedAt) healthDataConsentAt = stampedAt as string;
		}

		const profileUpdate: Record<string, unknown> = {
			display_name: displayName || null,
			parkrun_number: parkrunNumber || null,
		};
		if (!healthDataConsent && healthDataConsentAt != null) {
			// Withdrawal — null the consent timestamp (the lock trigger
			// permits a direct null write); DOB is cleared from prefs below.
			profileUpdate.health_data_consent_at = null;
			healthDataConsentAt = null;
		}
		const { error: profileError } = await supabase.from('user_profiles')
			.update(profileUpdate).eq('id', auth.user.id);
		if (profileError) {
			showToast(m('settingsAccount.saveFailed', { error: profileError.message }), 'error');
			saving = false;
			return;
		}

		// Persist DOB + HR into user_settings.prefs. DOB only when consented;
		// on withdrawal it is explicitly nulled so the stored value is cleared.
		const prefs: Record<string, unknown> = {};
		prefs.date_of_birth = healthDataConsent && dateOfBirth ? dateOfBirth : null;
		if (restingHr) prefs.resting_hr_bpm = parseInt(restingHr, 10) || null;
		if (maxHr) prefs.max_hr_bpm = parseInt(maxHr, 10) || null;
		if (Object.keys(prefs).length > 0) {
			const { data } = await supabase
				.from('user_settings')
				.select('prefs')
				.eq('user_id', auth.user.id)
				.maybeSingle();
			const merged = { ...((data?.prefs as Record<string, unknown>) ?? {}), ...prefs };
			const { error: settingsError } = await supabase.from('user_settings').upsert({
				user_id: auth.user.id,
				prefs: merged,
				updated_at: new Date().toISOString(),
			});
			if (settingsError) {
				showToast(m('settingsAccount.saveFailed', { error: settingsError.message }), 'error');
				saving = false;
				return;
			}
		}
		saved = true;
		saving = false;
		showToast(m('settingsAccount.profileSaved'), 'success');
		setTimeout(() => (saved = false), 2000);
	}

	async function handleSavePassword() {
		if (newPassword.length < 6) { passwordError = m('settingsAccount.passwordTooShort'); return; }
		if (newPassword !== confirmPassword) { passwordError = m('settingsAccount.passwordsMismatch'); return; }
		passwordSaving = true; passwordError = null; passwordStatus = null;
		const { error } = await supabase.auth.updateUser({ password: newPassword });
		passwordSaving = false;
		if (error) { passwordError = error.message; }
		else {
			passwordStatus = m('settingsAccount.passwordSaved');
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
				.from(TABLES.runs)
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
			showToast(m('settingsAccount.exportFailed', { error: (e as Error).message }), 'error');
		} finally {
			exportingJson = false;
		}
	}

	/// Server-built GPX zip download. Calls /v1/export on the Go
	/// service (or the legacy `export-data` Edge Function when
	/// PUBLIC_EXPORT_HUB_URL is unset). The server builds the zip
	/// from up to 5,000 runs — including GPX-with-HR-extensions per
	/// run — uploads to Storage, and returns a 10-minute signed URL.
	/// Different from `handleBackup` (the in-page Full backup) in
	/// three ways: GPX format instead of raw row JSON + gz tracks;
	/// server-side memory budget instead of client-heap; subject to
	/// the tiered rate limit (free 2/hour, pro 8/hour).
	async function handleCloudGpxExport() {
		exportingGpx = true;
		try {
			const res = await cloudExport('gpx');
			// Trigger the download via the signed URL. `target=_blank`
			// preserves the user's settings tab — the browser swaps to
			// a download tab, then auto-closes after the GET completes.
			window.open(res.url, '_blank', 'noopener');
			showToast(
				m('settingsAccount.exportReady', { count: res.count }),
				'success',
			);
		} catch (e) {
			showToast(m('settingsAccount.exportFailed', { error: (e as Error).message }), 'error');
		} finally {
			exportingGpx = false;
		}
	}

	/// Comprehensive GDPR Art. 20 archive. Asks the server (Go
	/// `/v1/export` or the legacy `export-data` EF) to build the
	/// `run-app-backup` zip that bundles EVERY personal-data table —
	/// coach chat, direct messages, health / body metrics, the
	/// financial ledger, integrations, social graph — not just runs.
	/// This is the same `{format:'backup'}` path the mobile client
	/// (`backup_server_client.dart`) uses, and the canonical
	/// data-portability export (the in-page Full backup ZIP above is
	/// client-built and runs/routes/profile only). Opens the returned
	/// signed URL in a new tab to stream the download, mirroring the
	/// GPX cloud-export idiom.
	async function handleFullAccountArchive() {
		exportingArchive = true;
		try {
			const res = await cloudExport('backup');
			window.open(res.url, '_blank', 'noopener');
			showToast(
				m('settingsAccount.exportReady', { count: res.count }),
				'success',
			);
		} catch (e) {
			showToast(m('settingsAccount.exportFailed', { error: (e as Error).message }), 'error');
		} finally {
			exportingArchive = false;
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
		} catch (e) { showToast(m('settingsAccount.backupFailed', { error: (e as Error).message }), 'error'); }
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
		get email() { return m('settingsAccount.emailPasswordLabel'); },
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
			identityError = (e as Error).message ?? m('settingsAccount.identitiesLoadFailed');
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
			identityError = (e as Error).message ?? m('settingsAccount.linkFailed', { provider: PROVIDER_LABEL[provider] });
			linkingProvider = null;
		}
	}

	// Persona-hunt Round 2 finding Casual #3: pre-fix the unlink path
	// used a native window.confirm() while every other destructive
	// action on this page (Delete account, Restore from backup) uses
	// the in-app ConfirmDialog. Native confirm looks like a phishing
	// overlay on iOS Safari + violates the project's modal convention
	// (docs/architecture/conventions.md § Web modals). The async dialog state is
	// held in showUnlinkConfirm + pendingUnlink.
	let showUnlinkConfirm = $state(false);
	let pendingUnlink = $state<Identity | null>(null);

	function unlinkProvider(identity: Identity) {
		if (identities.length <= 1) {
			identityError = m('settingsAccount.needOneMethod');
			return;
		}
		pendingUnlink = identity;
		showUnlinkConfirm = true;
	}

	async function confirmUnlink() {
		const identity = pendingUnlink;
		showUnlinkConfirm = false;
		pendingUnlink = null;
		if (!identity) return;
		const label = PROVIDER_LABEL[identity.provider] ?? identity.provider;
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
			showToast(m('settingsAccount.unlinked', { provider: label }));
			await loadIdentities();
		} catch (e) {
			identityError = (e as Error).message ?? m('settingsAccount.unlinkFailed', { provider: label });
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
			if (!session) throw new Error(m('settingsAccount.notSignedIn'));
			const resp = await fetch(
				`${PUBLIC_SUPABASE_URL}/functions/v1/delete-account`,
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
			showToast(m('settingsAccount.deleteFailed', { error: (e as Error).message }), 'error');
		} finally {
			deleting = false;
		}
	}
</script>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('shell.settings')}</p>
		<h1>{m('settingsAccount.title')}</h1>
		<p class="tagline">
			{m('settingsAccount.tagline')}
		</p>
	</header>

	<!-- Profile -->
	<section class="card">
		<h2>{m('settingsAccount.profileHeading')}</h2>
		<div class="avatar-row">
			<Avatar url={avatarUrl} name={displayName} size="4rem" font="1.5rem" />
			<div class="avatar-actions">
				<input
					bind:this={avatarFileInput}
					type="file"
					accept="image/jpeg,image/png,image/webp"
					onchange={handleAvatarSelect}
					style="display: none"
					data-testid="avatar-file-input"
				/>
				<button
					type="button"
					class="btn btn-outline btn-sm"
					onclick={() => avatarFileInput.click()}
					disabled={avatarBusy}
					data-testid="avatar-change"
				>
					{avatarBusy ? m('settingsAccount.avatarUploading') : m('settingsAccount.avatarChange')}
				</button>
				{#if avatarUrl}
					<button
						type="button"
						class="btn btn-outline btn-sm"
						onclick={handleAvatarRemove}
						disabled={avatarBusy}
						data-testid="avatar-remove"
					>
						{m('settingsAccount.avatarRemove')}
					</button>
				{/if}
				<p class="section-desc avatar-hint">{m('settingsAccount.avatarHint')}</p>
			</div>
		</div>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('settingsAccount.displayName')}</span>
				<input type="text" bind:value={displayName} />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.email')}</span>
				<input type="email" value={auth.user?.email ?? ''} disabled />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.parkrunNumber')}</span>
				<input type="text" bind:value={parkrunNumber} placeholder="A123456" />
				{#if parkrunNumber && parkrunNumber.trim().length > 0}
					<button
						type="button"
						class="btn btn-outline btn-sm parkrun-import-btn"
						onclick={handleParkrunImport}
						disabled={parkrunImporting}
					>
						{parkrunImporting ? m('settingsAccount.importing') : m('settingsAccount.pullParkrun')}
					</button>
				{/if}
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.dateOfBirth')}</span>
				<input type="date" bind:value={dateOfBirth} disabled={!healthDataConsent} />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.restingHr')}</span>
				<input type="number" bind:value={restingHr} placeholder={m('settingsAccount.restingHrPlaceholder')} min="30" max="120" />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.maxHr')}</span>
				<input type="number" bind:value={maxHr} placeholder={m('settingsAccount.maxHrPlaceholder')} min="100" max="230" />
			</label>
		</div>
		<label class="consent-checkbox">
			<input type="checkbox" bind:checked={healthDataConsent} />
			<span>
				{m('settingsAccount.healthConsentLabel')}
			</span>
		</label>
		{#if healthDataConsentAt}
			<p class="section-desc consent-recorded">
				{m('settingsAccount.consentRecorded', { date: new Date(healthDataConsentAt).toLocaleDateString() })}
			</p>
		{/if}
		<button class="btn btn-primary btn-save" onclick={handleSave} disabled={saving}>
			{saving ? m('settingsAccount.saving') : saved ? m('settingsAccount.savedDone') : m('settingsAccount.saveProfile')}
		</button>
	</section>

	<!-- Sign-in methods -->
	<section class="card">
		<h2>{m('settingsAccount.signinMethodsHeading')}</h2>
		<p class="section-desc">
			{m('settingsAccount.signinMethodsDesc')}
		</p>

		{#if identitiesLoading}
			<p class="muted">{m('shell.loading')}</p>
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
									{m('settingsAccount.linkedOn', { date: new Date(id.created_at).toLocaleDateString(activeFormatLocale(), {
										year: 'numeric', month: 'short', day: 'numeric',
									}) })}
								</span>
							{/if}
						</div>
						<button
							class="btn btn-outline btn-sm"
							onclick={() => unlinkProvider(id)}
							disabled={unlinkingProvider === id.provider || identities.length <= 1}
							title={identities.length <= 1
								? m('settingsAccount.unlinkBlockedTitle')
								: ''}
						>
							{unlinkingProvider === id.provider ? m('settingsAccount.unlinking') : m('settingsAccount.unlink')}
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
							<span>{busy ? m('settingsAccount.linkingProvider', { provider: label }) : m('settingsAccount.linkProvider', { provider: label })}</span>
						</button>
					{/each}
				</div>
			{/if}
		{/if}

		{#if identityError}<p class="error-text" role="alert">{identityError}</p>{/if}
	</section>

	<!-- Password -->
	<section class="card">
		<h2>{m('settingsAccount.passwordHeading')}</h2>
		<p class="section-desc">
			{m('settingsAccount.passwordDesc')}
		</p>
		<div class="form-grid">
			<label>
				<span class="label-text">{m('settingsAccount.newPassword')}</span>
				<input type="password" autocomplete="new-password" bind:value={newPassword} placeholder={m('settingsAccount.newPasswordPlaceholder')} />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.confirmPassword')}</span>
				<input type="password" autocomplete="new-password" bind:value={confirmPassword} />
			</label>
		</div>
		{#if passwordError}<p class="error-text" role="alert">{passwordError}</p>{/if}
		{#if passwordStatus}<p class="ok-text">{passwordStatus}</p>{/if}
		<button class="btn btn-primary btn-save" onclick={handleSavePassword} disabled={passwordSaving || !newPassword || !confirmPassword}>
			{passwordSaving ? m('settingsAccount.saving') : m('settingsAccount.savePassword')}
		</button>
	</section>

	<!-- Safety — points at the real, double-opt-in safety-contacts surface.
	     The old inline editor here persisted a trusted_contacts prefs list
	     that nothing ever read (persona-woman CRITICAL: two conflated
	     Safety surfaces, one inert) — replaced per docs/features/safety.md. -->
	<section class="card" data-testid="account-safety-pointer">
		<h2>{m('settingsAccount.safetyHeading')}</h2>
		<p class="section-desc">
			{m('settingsAccount.safetyPointerDesc')}
		</p>
		<a class="btn btn-outline" href="/settings/safety">
			<span class="material-symbols" aria-hidden="true">health_and_safety</span>
			{m('settingsAccount.safetyPointerCta')}
		</a>
	</section>

	<!-- Notifications -->
	<section class="card">
		<h2>{m('settingsAccount.notificationsHeading')}</h2>
		{#if !pushSupported}
			<p class="section-desc">
				{m('settingsAccount.pushUnsupportedPrefix')}<code>PUBLIC_VAPID_PUBLIC_KEY</code>{m('settingsAccount.pushUnsupportedSuffix')}
			</p>
		{:else if pushPermissionState === 'denied'}
			<p class="section-desc">
				{m('settingsAccount.pushBlocked')}
			</p>
		{:else}
			<p class="section-desc">
				{m('settingsAccount.pushDesc')}
			</p>
			<div class="btn-row">
				{#if pushSubscribed}
					<button class="btn btn-outline" onclick={handleDisablePush} disabled={pushBusy}>
						<span class="material-symbols">notifications_off</span>
						{pushBusy ? m('settingsAccount.updating') : m('settingsAccount.disableNotifications')}
					</button>
				{:else}
					<button class="btn btn-primary" onclick={handleEnablePush} disabled={pushBusy}>
						<span class="material-symbols">notifications_active</span>
						{pushBusy ? m('settingsAccount.enabling') : m('settingsAccount.enableNotifications')}
					</button>
				{/if}
			</div>
		{/if}
	</section>

	<!-- Backup & Restore -->
	<section class="card">
		<h2>{m('settingsAccount.backupHeading')}</h2>
		<p class="section-desc">
			{m('settingsAccount.backupDesc')}
		</p>
		<div class="btn-row">
			<button class="btn btn-primary" onclick={handleBackup} disabled={backingUp || restoring}>
				<span class="material-symbols">archive</span>
				{backingUp ? (backupProgress ? `${backupProgress.stage}...` : m('settingsAccount.backingUp')) : m('settingsAccount.downloadBackup')}
			</button>
			<button class="btn btn-outline" onclick={() => restoreFileInput.click()} disabled={backingUp || restoring}>
				<span class="material-symbols">unarchive</span>
				{restoring ? (restoreProgress ? `${restoreProgress.stage}...` : m('settingsAccount.restoring')) : m('settingsAccount.restoreBackup')}
			</button>
			<input bind:this={restoreFileInput} type="file" accept=".zip" onchange={handleRestoreFile} style="display: none" />
		</div>
		{#if restoreResult}
			<p class="ok-text">
				{m('settingsAccount.restoreResult', { runs: restoreResult.runsImported, tracks: restoreResult.tracksUploaded, routes: restoreResult.routesImported })}
				{#if restoreResult.warnings.length > 0}<br /><small>{m('settingsAccount.restoreWarnings', { n: restoreResult.warnings.length })}</small>{/if}
			</p>
		{/if}
		{#if restoreError}<p class="error-text" role="alert">{m('settingsAccount.restoreFailed', { error: restoreError })}</p>{/if}
	</section>

	<!-- Data Export -->
	<section class="card">
		<h2>{m('settingsAccount.dataExportHeading')}</h2>
		<p class="section-desc">
			{m('settingsAccount.dataExportDescPrefix')}<code>runs.json</code>{m('settingsAccount.dataExportDescBetween')}<code>runs.json</code>{m('settingsAccount.dataExportDescSuffix')}
		</p>
		<div class="btn-row">
			<button class="btn btn-outline" onclick={handleExportCsv} disabled={exporting || exportingJson || exportingGpx || exportingArchive}>
				<span class="material-symbols">download</span>
				{exporting ? m('settingsAccount.exporting') : m('settingsAccount.exportCsv')}
			</button>
			<button class="btn btn-outline" onclick={handleExportJson} disabled={exporting || exportingJson || exportingGpx || exportingArchive}>
				<span class="material-symbols">code</span>
				{exportingJson ? m('settingsAccount.exporting') : m('settingsAccount.exportJson')}
			</button>
			<button
				class="btn btn-outline"
				onclick={handleCloudGpxExport}
				disabled={exporting || exportingJson || exportingGpx || exportingArchive}
				title={m('settingsAccount.cloudExportTitle')}
			>
				<span class="material-symbols">cloud_download</span>
				{exportingGpx ? m('settingsAccount.buildingZip') : m('settingsAccount.cloudExport')}
			</button>
		</div>
		<p class="section-desc" style="margin-top: 0.5rem; font-size: 0.85rem;">
			<strong>{m('settingsAccount.cloudExportFootnotePrefix')}</strong>{m('settingsAccount.cloudExportFootnoteSuffix')}
		</p>

		<div class="btn-row" style="margin-top: 0.75rem;">
			<button
				class="btn btn-outline"
				onclick={handleFullAccountArchive}
				disabled={exporting || exportingJson || exportingGpx || exportingArchive}
				title={m('settingsAccount.fullArchiveTitle')}
				data-testid="full-account-archive"
			>
				<span class="material-symbols">database</span>
				{exportingArchive ? m('settingsAccount.buildingZip') : m('settingsAccount.fullArchive')}
			</button>
		</div>
		<p class="section-desc" style="margin-top: 0.5rem; font-size: 0.85rem;">
			<strong>{m('settingsAccount.fullArchiveFootnotePrefix')}</strong>{m('settingsAccount.fullArchiveFootnoteSuffix')}
		</p>
	</section>

	<section class="card">
		<h2>{m('settingsAccount.coachConsentHeading')}</h2>
		{#if coachConsentAt}
			<p class="section-desc">{m('settingsAccount.coachConsentActive')}</p>
			<div class="btn-row">
				<button
					class="btn btn-outline"
					onclick={withdrawCoachConsent}
					disabled={coachConsentWithdrawing}
				>
					<span class="material-symbols">block</span>
					{coachConsentWithdrawing
						? m('settingsAccount.coachConsentWithdrawing')
						: m('settingsAccount.coachConsentWithdraw')}
				</button>
			</div>
		{:else}
			<p class="section-desc">{m('settingsAccount.coachConsentInactive')}</p>
		{/if}
	</section>

	<ConfirmDialog
		open={showRestoreConfirm}
		title={m('settingsAccount.restoreConfirmTitle')}
		message={m('settingsAccount.restoreConfirmMessage', { file: pendingRestoreFile?.name ?? '' })}
		confirmLabel={m('settingsAccount.restoreConfirmLabel')}
		onconfirm={confirmRestore}
		oncancel={cancelRestore}
		danger
	/>

	<!-- Danger zone -->
	<section class="card card-danger">
		<h2 class="danger-heading">{m('settingsAccount.dangerZoneHeading')}</h2>
		<p class="section-desc">{m('settingsAccount.dangerZoneDesc')}</p>
		<button class="btn btn-danger" onclick={() => (showDeleteAccount = true)} disabled={deleting}>
			{deleting ? m('settingsAccount.deleting') : m('settingsAccount.deleteAccount')}
		</button>
	</section>
</div>

<ConfirmDialog
	open={showDeleteAccount}
	title={m('settingsAccount.deleteConfirmTitle')}
	message={m('settingsAccount.deleteConfirmMessage')}
	confirmLabel={m('settingsAccount.deleteConfirmLabel')}
	danger
	requireText={auth.user?.email ?? 'DELETE'}
	requireTextLabel={m('settingsAccount.deleteRequireTextLabel', { email: auth.user?.email ?? 'DELETE' })}
	onconfirm={handleDeleteAccount}
	oncancel={() => (showDeleteAccount = false)}
/>

<ConfirmDialog
	open={showUnlinkConfirm}
	title={m('settingsAccount.unlinkConfirmTitle', { provider: pendingUnlink ? (PROVIDER_LABEL[pendingUnlink.provider] ?? pendingUnlink.provider) : '' })}
	message={m('settingsAccount.unlinkConfirmMessage')}
	confirmLabel={m('settingsAccount.unlink')}
	danger
	onconfirm={confirmUnlink}
	oncancel={() => {
		showUnlinkConfirm = false;
		pendingUnlink = null;
	}}
/>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 64rem; }
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
	h2 { font-size: 0.9rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: var(--space-lg); }
	.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); margin-bottom: var(--space-xl); }
	.card-danger { border-color: rgba(229, 57, 53, 0.3); }
	.avatar-row { display: flex; align-items: flex-start; gap: var(--space-md); margin-bottom: var(--space-lg); }
	.avatar-actions { display: flex; flex-wrap: wrap; align-items: center; gap: var(--space-sm); }
	.avatar-hint { flex-basis: 100%; margin-bottom: 0; }
	.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md); margin-bottom: var(--space-lg); }
	.label-text { display: block; font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary); margin-bottom: var(--space-xs); }
	input { width: 100%; padding: var(--space-sm) var(--space-md); border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.9rem; background: var(--color-bg); }
	input:focus { outline: none; border-color: var(--color-primary); }
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	input:disabled { opacity: 0.6; cursor: not-allowed; }
	.section-desc { font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: var(--space-md); line-height: 1.5; }
	.consent-checkbox { display: flex; gap: var(--space-sm); align-items: flex-start; font-size: 0.9rem; line-height: 1.45; margin-bottom: var(--space-md); }
	.consent-checkbox input { margin-top: 0.2rem; flex-shrink: 0; width: auto; }
	.consent-recorded { font-size: 0.8rem; }
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
