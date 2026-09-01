<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onDestroy, onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import AiDisclosureNotice from '$lib/components/AiDisclosureNotice.svelte';
	import { supabase } from '$lib/core/supabase';
	import {
		AI_DISCLOSURE_CURRENT_VERSION,
		aiDisclosureFromProfileRow,
		checkAiDisclosure,
		type AiDisclosureRecord,
	} from '$lib/core/ai_disclosure';
	import { changePassword, type PasswordChangeReason } from '$lib/core/password_change';
	import { PASSWORD_MIN_LENGTH } from '$lib/core/auth_rules';
	import { TEXT_LIMITS } from '$lib/core/text_limits';
	import { lengthLimit } from '$lib/core/column_limits';
	import { TABLES } from '$lib/core/schema';
	import { PUBLIC_SUPABASE_URL } from '$env/static/public';
	import { downloadFile } from '$lib/routes/gpx';
	import { fetchRunsWithError, uploadAvatar, removeAvatar } from '$lib/core/data';
	import {
		createBackup,
		restoreBackup,
		type BackupProgress,
		type RestoreProgress,
		type RestoreResult,
	} from '$lib/backup/backup';
	import { transferStageKey } from '$lib/backup/stage_labels';
	import { backupShortfall as gradeBackupShortfall, type BackupShortfall } from '$lib/backup/shortfall';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		unsubscribeFromPush,
		getCurrentSubscription,
	} from '$lib/util/push';
	import { fetchCloudExportJob, startCloudExport } from '$lib/backup/cloud_export';
	import {
		type CloudExportFormat,
		type CloudExportJob,
		type CloudExportResponse,
		type CloudExportShortfall,
		cloudExportPollDelayMs,
		cloudExportShortfall,
		isCloudExportJobActive,
	} from '$lib/backup/cloud_export_helpers';
	import { m } from '$lib/i18n/store.svelte';
	import PasswordInput from '$lib/components/PasswordInput.svelte';
	import { isCyclePlansEnabled } from '$lib/training/cycle_plan_flag';
	import {
		MIN_CYCLE_LENGTH_DAYS,
		MAX_CYCLE_LENGTH_DAYS,
	} from '$lib/training/cycle_plan';

	let displayName = $state(auth.user?.display_name ?? '');
	// Public @handle (issue #465). Claimed / edited through the set_my_handle
	// RPC (the only owner write path) so uniqueness + format errors surface.
	let handle = $state('');
	let handleInitial = $state('');
	let handleSaving = $state(false);
	let handleSaved = $state(false);
	let handleError = $state<string | null>(null);
	let handleChanged = $derived(handle.trim().toLowerCase() !== handleInitial);
	let avatarUrl = $state<string | null>(auth.user?.avatar_url ?? null);
	let avatarBusy = $state(false);
	let avatarFileInput: HTMLInputElement;
	let parkrunNumber = $state(auth.user?.parkrun_number ?? '');
	let dateOfBirth = $state('');
	let restingHr = $state('');
	let maxHr = $state('');
	// Cycle/pregnancy-aware training inputs (persona runner-woman, decisions
	// §231). Art 9 reproductive-health data — persistence is gated on the
	// SAME health-data consent as DOB below, AND the whole section is hidden
	// unless the fail-closed PUBLIC_CYCLE_PLANS_ENABLED flag is on.
	const cyclePlansEnabled = isCyclePlansEnabled();
	let cycleMode = $state<'off' | 'cycle' | 'pregnancy'>('off');
	let cycleLengthDays = $state('28');
	let cycleLastPeriodStart = $state('');
	let pregnancyDueDate = $state('');
	// Date of birth is split across two stores with two rules, identical to
	// /settings/preferences and /onboarding (decisions § 718): the
	// `user_settings.prefs` mirror is the Art 9 HEALTH-USE copy the coach
	// context + HR-max derivation read, so it persists only under explicit
	// health-data consent and is nulled on withdrawal; the
	// `user_profiles.date_of_birth` column is the AGE RECORD backing the
	// under-18 discoverability floor, a child-protection purpose written
	// whenever the runner supplies a date.
	let healthDataConsent = $state(false);
	let healthDataConsentAt = $state<string | null>(null);
	// The versioned AI-processing consent record (decisions.md § 571). This
	// is the surface where a user who accepted an older disclosure reads the
	// widened one and accepts it — the AI route assistant refuses until they
	// do, and a stale acceptance is not something the Coach surface should
	// nag about (it covers the Coach fine).
	let aiDisclosure = $state<AiDisclosureRecord>({ version: null, acceptedAt: null });
	let aiConsentGranted = $derived(checkAiDisclosure(aiDisclosure, 1).ok);
	let aiConsentStale = $derived(
		aiConsentGranted && !checkAiDisclosure(aiDisclosure, AI_DISCLOSURE_CURRENT_VERSION).ok,
	);
	let coachConsentWithdrawing = $state(false);
	let aiConsentAccepting = $state(false);
	let saving = $state(false);
	let saved = $state(false);
	let exporting = $state(false);
	let exportingJson = $state(false);
	let exportingGpx = $state(false);
	let exportingArchive = $state(false);
	/// Last server-built export that came back short of the account's run
	/// history. Kept on the page rather than only toasted: a truncated
	/// Art. 20 export is a claim the runner has to be able to re-read
	/// after the toast has gone, and the archive itself only says so
	/// inside manifest.json.
	let exportShortfall = $state<CloudExportShortfall | null>(null);
	/// State of the subject's most recent QUEUED export (decisions.md
	/// § 717). The archive is built off a job now, so the page has to be
	/// able to say what is happening across a reload — the status
	/// endpoint answers for the latest export rather than by id, so
	/// nothing has to be persisted here to find the way back to it.
	/// Null on the legacy Edge Function transport, which still builds
	/// inline and has no job to watch.
	let exportJob = $state<CloudExportJob | null>(null);
	let exportStatusUnreadable = $state(false);
	let exportPollTimer: ReturnType<typeof setTimeout> | null = null;
	let exportPollFailures = 0;
	const exportJobBuilding = $derived(
		exportJob !== null && isCloudExportJobActive(exportJob.status),
	);

	let backingUp = $state(false);
	let backupProgress = $state<BackupProgress | null>(null);
	let backupShortfall = $state<BackupShortfall | null>(null);
	let restoring = $state(false);
	let restoreProgress = $state<RestoreProgress | null>(null);
	let restoreResult = $state<RestoreResult | null>(null);
	let restoreError = $state<string | null>(null);
	let restoreFileInput: HTMLInputElement;
	let showRestoreConfirm = $state(false);
	let pendingRestoreFile = $state<File | null>(null);

	let currentPassword = $state('');
	let newPassword = $state('');
	let confirmPassword = $state('');
	let passwordSaving = $state(false);
	let passwordStatus = $state<string | null>(null);
	let passwordError = $state<string | null>(null);
	let resetLinkSending = $state(false);

	// Change-email flow. `auth.updateUser({ email })` starts GoTrue's
	// secure double-confirmation: a link goes to BOTH the current and the
	// new address, and the account email only flips once both are
	// followed. Until then `auth.user.email` still reads the old address —
	// so we surface an explicit "confirmation pending" state rather than
	// optimistically showing the new one as if it had taken effect.
	let emailEditing = $state(false);
	let newEmail = $state('');
	let emailChanging = $state(false);
	let emailChangeError = $state<string | null>(null);
	let pendingEmail = $state<string | null>(null);
	// Snapshot the address at request time: `auth.updateUser` writes the
	// SDK's returned user back into the session store, so reading
	// `auth.user.email` afterwards is not a reliable "old address".
	let pendingOldEmail = $state('');

	// Loose email-shape check matching the browser's <input type="email">
	// semantics (one @ with non-space text either side); the server stays
	// the authority. Twin of mobile's looksLikeEmail (auth_validation.dart).
	function looksLikeEmail(value: string): boolean {
		return /^[^\s@]+@[^\s@]+$/.test(value.trim());
	}

	async function handleChangeEmail() {
		emailChangeError = null;
		const target = newEmail.trim();
		const current = auth.user?.email ?? '';
		if (!looksLikeEmail(target) || target.toLowerCase() === current.toLowerCase()) {
			emailChangeError = m('settingsAccount.emailChangeInvalid');
			return;
		}
		emailChanging = true;
		const { error } = await supabase.auth.updateUser(
			{ email: target },
			{ emailRedirectTo: `${window.location.origin}/auth/callback` },
		);
		emailChanging = false;
		if (error) {
			emailChangeError = m('settingsAccount.emailChangeFailed', { error: error.message });
			return;
		}
		pendingOldEmail = current;
		pendingEmail = target;
		emailEditing = false;
		newEmail = '';
	}

	function cancelEmailChange() {
		emailEditing = false;
		newEmail = '';
		emailChangeError = null;
	}

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
			// Legacy fallback only — the canonical age record read below wins.
			dateOfBirth = (p.date_of_birth as string) ?? '';
			restingHr = (p.resting_hr_bpm as number)?.toString() ?? '';
			maxHr = (p.max_hr_bpm as number)?.toString() ?? '';
			const mode = p.cycle_tracking_mode;
			cycleMode = mode === 'cycle' || mode === 'pregnancy' ? mode : 'off';
			cycleLengthDays = (p.cycle_length_days as number)?.toString() ?? '28';
			cycleLastPeriodStart = (p.cycle_last_period_start as string) ?? '';
			pregnancyDueDate = (p.pregnancy_due_date as string) ?? '';
		}
		// Self-read goes through the get_my_profile() SECURITY DEFINER RPC:
		// health_data_consent_at is deny-by-default for direct authenticated
		// SELECTs (column lockdown, 20260707_001) — a direct select 403s.
		const { data: prof } = await supabase.rpc('get_my_profile');
		// Sync the avatar from the freshly-read profile — the $state was seeded
		// from auth.user at component init, which may not have hydrated yet.
		avatarUrl = (prof?.avatar_url as string | null) ?? null;
		handleInitial = (prof?.handle as string | null) ?? '';
		handle = handleInitial;
		healthDataConsentAt = (prof?.health_data_consent_at as string | null) ?? null;
		// The age record is the source of truth for the field; the prefs bag
		// read above only covers a legacy account that never wrote the
		// column (§ 718). A withdrawal clears the mirror but not the record,
		// so reading the bag alone would blank a DOB that is still on file.
		dateOfBirth = (prof?.date_of_birth as string | null) ?? dateOfBirth;
		aiDisclosure = aiDisclosureFromProfileRow(prof);
		// Pre-tick the box if consent is already on record so a user can
		// edit DOB / HR without re-consenting on every visit.
		healthDataConsent = healthDataConsentAt != null;
		await loadIdentities();
		await refreshPushState();
		await resumeExportJob();
	});

	/// Pick up an export that was already building (or has since
	/// finished) when the page mounts. The whole point of the queued
	/// rail is that the subject can close the tab, so the page has to be
	/// able to find its way back with nothing stored locally — the
	/// status endpoint answers for their LATEST export, so this is the
	/// entire mechanism. A read that fails is silent here: a subject who
	/// never asked for an export must not be shown an error about one.
	async function resumeExportJob() {
		try {
			const job = await fetchCloudExportJob();
			if (job.status === 'none') return;
			exportJob = job;
			if (job.status === 'ready') exportShortfall = cloudExportShortfall(job);
			scheduleExportPoll(0);
		} catch {
			// Nothing to say. The subject learns of any real problem when
			// they ask for an export.
		}
	}

	async function withdrawCoachConsent() {
		if (coachConsentWithdrawing) return;
		coachConsentWithdrawing = true;
		try {
			// Sanctioned inverse of record_ai_disclosure_consent(): clears the
			// whole server-held record. Art 7(3) — there is one acceptance of
			// one disclosure, so withdrawal is all of it, and every AI
			// endpoint's 403 gate re-engages until the user consents again.
			const { error } = await supabase.rpc('withdraw_ai_disclosure_consent');
			if (error) throw new Error(error.message);
			aiDisclosure = { version: null, acceptedAt: null };
			showToast(m('settingsAccount.coachConsentWithdrawn'), 'success');
		} catch (e) {
			showToast(m('settingsAccount.saveFailed', { error: (e as Error).message }), 'error');
		} finally {
			coachConsentWithdrawing = false;
		}
	}

	async function acceptUpdatedAiDisclosure() {
		if (aiConsentAccepting) return;
		aiConsentAccepting = true;
		try {
			const { data, error } = await supabase
				.rpc('record_ai_disclosure_consent', { p_version: AI_DISCLOSURE_CURRENT_VERSION })
				.maybeSingle();
			if (error) throw new Error(error.message);
			// Take the server's word for what was recorded — a locally
			// synthesised version/timestamp would clear the "update
			// available" notice off a write that never landed (§ 560).
			const row = data as { version: number | null; accepted_at: string | null } | null;
			if (row?.version == null || !row.accepted_at) {
				throw new Error('consent not recorded');
			}
			aiDisclosure = { version: row.version, acceptedAt: row.accepted_at };
			showToast(m('settingsAccount.aiConsentUpdatedToast'), 'success');
		} catch (e) {
			showToast(m('settingsAccount.saveFailed', { error: (e as Error).message }), 'error');
		} finally {
			aiConsentAccepting = false;
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

	// The delete hits Storage and is not recoverable, and the button sits
	// immediately beside "Change photo" — mobile has confirmed this since it
	// shipped (settings_account_screen.dart).
	let showAvatarRemoveConfirm = $state(false);

	async function handleAvatarRemove() {
		showAvatarRemoveConfirm = false;
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

	async function saveHandle() {
		if (!auth.user || handleSaving) return;
		handleSaving = true;
		handleSaved = false;
		handleError = null;
		const next = handle.trim().toLowerCase();
		const { data, error } = await supabase.rpc('set_my_handle', { p_handle: next });
		if (error) {
			// The RPC raises a distinct message per failure so the copy is
			// specific; anything else falls back to a generic error.
			if (error.message.includes('handle_taken')) {
				handleError = m('settingsAccount.handleErrorTaken');
			} else if (error.message.includes('handle_invalid')) {
				handleError = m('settingsAccount.handleErrorInvalid');
			} else {
				handleError = m('settingsAccount.handleErrorGeneric', { error: error.message });
			}
			handleSaving = false;
			return;
		}
		handleInitial = (data as string | null) ?? '';
		handle = handleInitial;
		handleSaved = true;
		handleSaving = false;
	}

	async function handleSave() {
		if (!auth.user) return;
		saving = true;
		saved = false;

		// No DOB-without-consent abort. It used to refuse the whole save,
		// which both denied a non-consenting minor the age record the
		// discoverability floor keys off AND deadlocked the page: the DOB
		// input is populated from storage, so a runner who withdrew consent
		// elsewhere could not save their display name and could not clear
		// the DOB either. Consent gates the Art 9 mirror below, not the age
		// record (§ 718).
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

		if (!healthDataConsent && healthDataConsentAt != null) {
			// Withdrawal (Art 7(3)) — the SECURITY DEFINER RPC nulls the
			// consent stamp + gender + height and erases the weight series
			// atomically; insert-or-update server-side so a missing profile
			// row can't 0-row silent no-op (issue #233). Local state flips
			// only after the server confirms. The Art 9 DOB mirror is cleared
			// from prefs below; the age record is not this RPC's to touch
			// (§ 721), so nothing here has to put it back.
			const { error: withdrawError } = await supabase.rpc(
				'withdraw_health_data_consent',
			);
			if (withdrawError) {
				showToast(
					m('settingsAccount.saveFailed', { error: withdrawError.message }),
					'error',
				);
				saving = false;
				return;
			}
			healthDataConsentAt = null;
		}
		const profileUpdate: Record<string, unknown> = {
			display_name: displayName || null,
			parkrun_number: parkrunNumber || null,
			// The age record, carrying no consent term (§ 718) — ending the
			// Art 9 processing does not end the under-18 discoverability
			// floor, and since § 721 the withdrawal RPC leaves the column
			// alone rather than needing this write to undo it.
			date_of_birth: dateOfBirth || null,
		};
		// Row-count-verified: user_profiles rows are client-provisioned, so a
		// plain update against a missing row matches 0 rows and reports
		// success — the save would silently vanish (issue #233).
		const { data: updatedProfileRows, error: profileError } = await supabase
			.from('user_profiles')
			.update(profileUpdate)
			.eq('id', auth.user.id)
			.select('id');
		if (profileError) {
			showToast(m('settingsAccount.saveFailed', { error: profileError.message }), 'error');
			saving = false;
			return;
		}
		if (!updatedProfileRows?.length) {
			const { error: profileInsertError } = await supabase
				.from('user_profiles')
				.insert({ id: auth.user.id, ...profileUpdate });
			if (profileInsertError) {
				showToast(
					m('settingsAccount.saveFailed', { error: profileInsertError.message }),
					'error',
				);
				saving = false;
				return;
			}
		}

		// Persist DOB + HR into user_settings.prefs. DOB only when consented;
		// on withdrawal it is explicitly nulled so the stored value is cleared.
		const prefs: Record<string, unknown> = {};
		prefs.date_of_birth = healthDataConsent && dateOfBirth ? dateOfBirth : null;
		if (restingHr) prefs.resting_hr_bpm = parseInt(restingHr, 10) || null;
		if (maxHr) prefs.max_hr_bpm = parseInt(maxHr, 10) || null;
		// Cycle/pregnancy inputs are Art 9 reproductive-health data — write
		// them only when the flag is on AND consent is granted; on withdrawal
		// (or flag off) they are explicitly nulled so nothing lingers.
		if (cyclePlansEnabled && healthDataConsent) {
			prefs.cycle_tracking_mode = cycleMode === 'off' ? null : cycleMode;
			prefs.cycle_length_days =
				cycleMode === 'cycle' ? parseInt(cycleLengthDays, 10) || null : null;
			prefs.cycle_last_period_start =
				cycleMode === 'cycle' && cycleLastPeriodStart ? cycleLastPeriodStart : null;
			prefs.pregnancy_due_date =
				cycleMode === 'pregnancy' && pregnancyDueDate ? pregnancyDueDate : null;
		} else if (cyclePlansEnabled) {
			prefs.cycle_tracking_mode = null;
			prefs.cycle_length_days = null;
			prefs.cycle_last_period_start = null;
			prefs.pregnancy_due_date = null;
		}
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

	function passwordChangeMessage(reason: PasswordChangeReason, detail?: string): string {
		switch (reason) {
			case 'too_short':
				return m('settingsAccount.passwordTooShort', { min: PASSWORD_MIN_LENGTH });
			case 'mismatch':
				return m('settingsAccount.passwordsMismatch');
			case 'current_missing':
				return m('settingsAccount.currentPasswordRequired');
			case 'current_invalid':
				return m('settingsAccount.currentPasswordIncorrect');
			case 'update_failed':
				return detail ?? m('settingsAccount.passwordUpdateFailed');
		}
	}

	async function handleSavePassword() {
		passwordError = null; passwordStatus = null;
		passwordSaving = true;
		const result = await changePassword(
			{ currentPassword, newPassword, confirmPassword },
			{
				verifyCurrentPassword: async (current) => {
					const email = auth.user?.email ?? '';
					if (!email) return false;
					const { error } = await supabase.auth.signInWithPassword({ email, password: current });
					return !error;
				},
				updatePassword: async (password) => {
					const { error } = await supabase.auth.updateUser({ password });
					return { error: error?.message ?? null };
				},
			},
		);
		passwordSaving = false;
		if (!result.ok) {
			passwordError = passwordChangeMessage(result.reason, result.detail);
			return;
		}
		passwordStatus = m('settingsAccount.passwordSaved');
		currentPassword = ''; newPassword = ''; confirmPassword = '';
		setTimeout(() => (passwordStatus = null), 5000);
	}

	/// An account created through Google / Apple has no password to prove,
	/// so the step-up above can never pass for it. The mailed recovery
	/// token on /auth/reset is the equivalent proof, and it reaches the
	/// address on file rather than whoever holds the current session.
	async function handleSendResetLink() {
		const email = auth.user?.email ?? '';
		if (!email) return;
		resetLinkSending = true; passwordError = null; passwordStatus = null;
		const { error } = await supabase.auth.resetPasswordForEmail(email, {
			redirectTo: `${window.location.origin}/auth/reset`,
		});
		resetLinkSending = false;
		if (error) passwordError = error.message;
		else passwordStatus = m('settingsAccount.resetLinkSent');
	}

	/// Reads through `fetchRunsWithError`, not the plain `fetchRuns`: the
	/// latter returns `[]` on a read failure, which handed the user a
	/// header-only `runs_export.csv` and no hint that anything went
	/// wrong — a failed export is indistinguishable from an empty
	/// history. The sibling exports all surface the failure; so does this.
	async function handleExportCsv() {
		exporting = true;
		try {
			const { runs, error } = await fetchRunsWithError();
			if (error) throw new Error(error);
			const header = 'date,distance_m,duration_s,pace_s_per_km,source\n';
			const rows = runs.map((r) => {
				const pace = r.distance_m > 0 ? Math.round(r.duration_s / (r.distance_m / 1000)) : 0;
				return `${r.started_at},${r.distance_m},${r.duration_s},${pace},${r.source}`;
			}).join('\n');
			downloadFile(header + rows, 'runs_export.csv', 'text/csv');
		} catch (e) {
			showToast(m('settingsAccount.exportFailed', { error: (e as Error).message }), 'error');
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

	/// Report a finished server-built export. A whole archive gets the
	/// success toast it always got; a short one says so instead of
	/// claiming it is ready, and leaves the counts on the page.
	function announceExport(res: CloudExportResponse) {
		const short = cloudExportShortfall(res);
		exportShortfall = short;
		if (short) {
			showToast(
				m('settingsAccount.exportPartialReady', {
					count: short.count,
					total: short.total,
				}),
				'info',
			);
			return;
		}
		showToast(m('settingsAccount.exportReady', { count: res.count }), 'success');
	}

	/// Server-built GPX zip download. Enqueues a `data_export` job on
	/// the Go service (or calls the legacy `export-data` Edge Function
	/// when PUBLIC_EXPORT_HUB_URL is unset — the only synchronous
	/// export rail left, decisions §724). The server streams the zip —
	/// including GPX-with-HR-extensions per run — into Storage and the
	/// status read mints a 10-minute signed URL. Different from
	/// `handleBackup` (the in-page Full backup) in three ways: GPX
	/// format instead of raw row JSON + gz tracks; server-side build
	/// instead of client-heap; subject to the tiered rate limit
	/// (free 2/hour, pro 8/hour).
	async function handleCloudGpxExport() {
		exportingGpx = true;
		try {
			await requestCloudExport('gpx');
		} finally {
			exportingGpx = false;
		}
	}

	/// Comprehensive GDPR Art. 20 archive. Asks the server (the Go
	/// queued rail, or the legacy `export-data` EF) to build the
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
			await requestCloudExport('backup');
		} finally {
			exportingArchive = false;
		}
	}

	/// Ask for an export on whichever rail is configured.
	///
	/// The Go service enqueues and answers immediately, so nothing here
	/// waits for the archive — the page starts watching the job instead,
	/// and the subject may close the tab. The legacy Edge Function still
	/// builds inline, so its finished archive comes straight back and
	/// opens in a download tab exactly as before.
	async function requestCloudExport(format: CloudExportFormat) {
		try {
			const started = await startCloudExport(format);
			if (started.kind === 'ready') {
				// Trigger the download via the signed URL. `target=_blank`
				// preserves the user's settings tab — the browser swaps to
				// a download tab, then auto-closes after the GET completes.
				window.open(started.response.url, '_blank', 'noopener');
				announceExport(started.response);
				return;
			}
			exportStatusUnreadable = false;
			exportPollFailures = 0;
			exportJob = started.job;
			showToast(m('settingsAccount.exportQueued'), 'info');
			scheduleExportPoll(0);
		} catch (e) {
			showToast(m('settingsAccount.exportFailed', { error: (e as Error).message }), 'error');
		}
	}

	function clearExportPoll() {
		if (exportPollTimer !== null) {
			clearTimeout(exportPollTimer);
			exportPollTimer = null;
		}
	}

	/// One timer, two jobs. While the archive is building it backs off
	/// from 2s to 15s; once it is ready it re-reads at half the signed
	/// URL's lifetime, because the URL is minted per read and a download
	/// link left on the page would otherwise expire under the subject
	/// while they are looking at it.
	function scheduleExportPoll(attempt: number) {
		clearExportPoll();
		const job = exportJob;
		if (!job) return;
		let delay: number;
		if (isCloudExportJobActive(job.status)) {
			delay = cloudExportPollDelayMs(attempt);
		} else if (job.status === 'ready') {
			delay = Math.max(((job.expires_in ?? 600) * 1000) / 2, 30_000);
		} else {
			return;
		}
		exportPollTimer = setTimeout(() => {
			void readExportJob(attempt + 1);
		}, delay);
	}

	async function readExportJob(attempt: number) {
		exportPollTimer = null;
		let job: CloudExportJob;
		try {
			job = await fetchCloudExportJob();
		} catch {
			// A status read that failed is not an export that failed. Try
			// again a few times before saying anything, and never rewrite
			// the job the page is already showing on the strength of a
			// network blip.
			exportPollFailures += 1;
			if (exportPollFailures >= 5) {
				exportStatusUnreadable = true;
				return;
			}
			scheduleExportPoll(attempt);
			return;
		}
		exportPollFailures = 0;
		exportStatusUnreadable = false;
		const wasBuilding = exportJob !== null && isCloudExportJobActive(exportJob.status);
		exportJob = job;
		if (wasBuilding && job.status === 'ready') {
			// Deliberately no window.open: this runs on a timer, not a
			// user gesture, so a popup would be blocked. The subject gets
			// a real download link on the page instead, which also serves
			// the reload case identically.
			exportShortfall = cloudExportShortfall(job);
			if (exportShortfall) {
				showToast(
					m('settingsAccount.exportPartialReady', {
						count: exportShortfall.count,
						total: exportShortfall.total,
					}),
					'info',
				);
			} else {
				showToast(m('settingsAccount.exportReady', { count: job.count ?? 0 }), 'success');
			}
		}
		scheduleExportPoll(attempt);
	}

	onDestroy(clearExportPoll);

	async function handleBackup() {
		backingUp = true; backupProgress = null; backupShortfall = null;
		try {
			const archive = await createBackup((p) => (backupProgress = p));
			// A track whose download failed is skipped so one dead blob can't
			// sink the file, and a row read that died half-way ships flagged
			// rather than silently short. The archive's manifest says so, but
			// nobody reads a manifest before trusting a backup — so the
			// download surface says it too, and says WHICH of the two it was:
			// reporting a short `runs` read as a track count read as an
			// all-clear.
			backupShortfall = gradeBackupShortfall(archive);
			const url = URL.createObjectURL(archive.blob);
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
			identityError = m('settingsAccount.identitiesLoadFailed', { error: e instanceof Error ? e.message : String(e) });
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
			identityError = m('settingsAccount.linkFailed', { provider: PROVIDER_LABEL[provider], error: e instanceof Error ? e.message : String(e) });
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
			identityError = m('settingsAccount.unlinkFailed', { provider: label, error: e instanceof Error ? e.message : String(e) });
		} finally {
			unlinkingProvider = null;
		}
	}

	let linkedProviderSet = $derived(new Set(identities.map((i) => i.provider)));
	let unlinkedProviders = $derived(LINKABLE_PROVIDERS.filter((p) => !linkedProviderSet.has(p)));

	let showSignOutEverywhere = $state(false);
	let signingOutEverywhere = $state(false);

	async function handleSignOutEverywhere() {
		showSignOutEverywhere = false;
		signingOutEverywhere = true;
		try {
			await auth.logoutEverywhere();
			goto('/login');
		} catch (e) {
			// Fail closed: the local session is still live because the global
			// revocation didn't land, so keep the user here with an error to
			// retry rather than silently pretending they were signed out.
			showToast(m('settingsAccount.signoutEverywhereFailed', { error: (e as Error).message }), 'error');
		} finally {
			signingOutEverywhere = false;
		}
	}

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
						onclick={() => (showAvatarRemoveConfirm = true)}
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
				<input type="text" bind:value={displayName} maxlength={TEXT_LIMITS.displayName} />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.handleLabel')}</span>
				<div class="handle-row">
					<span class="handle-at" aria-hidden="true">@</span>
					<input
						type="text"
						class="handle-input"
						bind:value={handle}
						placeholder={m('settingsAccount.handlePlaceholder')}
						autocomplete="off"
						autocapitalize="none"
						spellcheck="false"
						maxlength="30"
						data-testid="handle-input"
						oninput={() => {
							handleSaved = false;
							handleError = null;
						}}
					/>
					<button
						type="button"
						class="btn btn-outline btn-sm handle-save-btn"
						onclick={saveHandle}
						disabled={handleSaving || !handleChanged}
						data-testid="handle-save"
					>
						{handleSaving
							? m('settingsAccount.handleSaving')
							: handleSaved
								? m('settingsAccount.handleSaved')
								: m('settingsAccount.handleSave')}
					</button>
				</div>
				<span class="handle-help">{m('settingsAccount.handleHelp')}</span>
				{#if handleError}<p class="error-text" role="alert" data-testid="handle-error">{handleError}</p>{/if}
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.email')}</span>
				<input type="email" value={auth.user?.email ?? ''} disabled />
				{#if !emailEditing}
					<button
						type="button"
						class="btn btn-outline btn-sm email-change-btn"
						onclick={() => {
							emailEditing = true;
							emailChangeError = null;
						}}
						data-testid="change-email"
					>
						{m('settingsAccount.changeEmail')}
					</button>
				{:else}
					<input
						type="email"
						bind:value={newEmail}
						placeholder={m('settingsAccount.newEmailPlaceholder')}
						autocomplete="email"
						data-testid="new-email-input"
					/>
					<div class="btn-row email-change-actions">
						<button
							type="button"
							class="btn btn-primary btn-sm"
							onclick={handleChangeEmail}
							disabled={emailChanging || !newEmail}
							data-testid="submit-email-change"
						>
							{emailChanging
								? m('settingsAccount.emailChangeSending')
								: m('settingsAccount.emailChangeSubmit')}
						</button>
						<button
							type="button"
							class="btn btn-outline btn-sm"
							onclick={cancelEmailChange}
							disabled={emailChanging}
						>
							{m('settingsAccount.emailChangeCancel')}
						</button>
					</div>
				{/if}
				{#if emailChangeError}<p class="error-text" role="alert">{emailChangeError}</p>{/if}
				{#if pendingEmail}
					<p class="ok-text" data-testid="email-change-pending">
						{m('settingsAccount.emailChangePending', {
							old: pendingOldEmail,
							new: pendingEmail,
						})}
					</p>
				{/if}
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.parkrunNumber')}</span>
				<input
					type="text"
					bind:value={parkrunNumber}
					maxlength={lengthLimit('user_profiles.parkrun_number')}
					placeholder="A123456"
				/>
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
				<!-- Not consent-disabled: the column it writes is the under-18
				     discoverability floor's age record (§ 718). Consent gates
				     the Art 9 prefs mirror, not the field. -->
				<input type="date" bind:value={dateOfBirth} max={new Date().toISOString().slice(0, 10)} data-testid="date-of-birth" />
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
		{#if cyclePlansEnabled}
			<div class="cycle-block" data-testid="cycle-plans-inputs">
				<h3 class="cycle-heading">{m('settingsAccount.cycleHeading')}</h3>
				<p class="section-desc">{m('settingsAccount.cycleDescription')}</p>
				<label>
					<span class="label-text">{m('settingsAccount.cycleMode')}</span>
					<select bind:value={cycleMode} disabled={!healthDataConsent}>
						<option value="off">{m('settingsAccount.cycleModeOff')}</option>
						<option value="cycle">{m('settingsAccount.cycleModeCycle')}</option>
						<option value="pregnancy">{m('settingsAccount.cycleModePregnancy')}</option>
					</select>
				</label>
				{#if cycleMode === 'cycle'}
					<label>
						<span class="label-text">{m('settingsAccount.cycleLength')}</span>
						<input
							type="number"
							bind:value={cycleLengthDays}
							disabled={!healthDataConsent}
							min={MIN_CYCLE_LENGTH_DAYS}
							max={MAX_CYCLE_LENGTH_DAYS}
						/>
					</label>
					<label>
						<span class="label-text">{m('settingsAccount.cycleLastPeriod')}</span>
						<input type="date" bind:value={cycleLastPeriodStart} disabled={!healthDataConsent} />
					</label>
				{:else if cycleMode === 'pregnancy'}
					<label>
						<span class="label-text">{m('settingsAccount.pregnancyDueDate')}</span>
						<input type="date" bind:value={pregnancyDueDate} disabled={!healthDataConsent} />
					</label>
					<p class="section-desc cycle-disclaimer" data-testid="pregnancy-disclaimer">
						{m('settingsAccount.pregnancyDisclaimer')}
					</p>
				{/if}
			</div>
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
				<span class="label-text">{m('settingsAccount.currentPassword')}</span>
				<PasswordInput autocomplete="current-password" bind:value={currentPassword} />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.newPassword')}</span>
				<PasswordInput autocomplete="new-password" bind:value={newPassword} placeholder={m('settingsAccount.newPasswordPlaceholder')} />
			</label>
			<label>
				<span class="label-text">{m('settingsAccount.confirmPassword')}</span>
				<PasswordInput autocomplete="new-password" bind:value={confirmPassword} />
			</label>
		</div>
		{#if passwordError}<p class="error-text" role="alert">{passwordError}</p>{/if}
		{#if passwordStatus}<p class="ok-text">{passwordStatus}</p>{/if}
		<div class="btn-row">
			<button class="btn btn-primary btn-save" onclick={handleSavePassword} disabled={passwordSaving || !currentPassword || !newPassword || !confirmPassword}>
				{passwordSaving ? m('settingsAccount.saving') : m('settingsAccount.savePassword')}
			</button>
			<button class="btn btn-secondary" onclick={handleSendResetLink} disabled={resetLinkSending}>
				{resetLinkSending ? m('settingsAccount.sendingResetLink') : m('settingsAccount.sendResetLink')}
			</button>
		</div>
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
				{backingUp
					? backupProgress
						? m(transferStageKey(backupProgress.stage))
						: m('settingsAccount.backingUp')
					: m('settingsAccount.downloadBackup')}
			</button>
			<button class="btn btn-outline" onclick={() => restoreFileInput.click()} disabled={backingUp || restoring}>
				<span class="material-symbols">unarchive</span>
				{restoring
					? restoreProgress
						? m(transferStageKey(restoreProgress.stage))
						: m('settingsAccount.restoring')
					: m('settingsAccount.restoreBackup')}
			</button>
			<input bind:this={restoreFileInput} type="file" accept=".zip" onchange={handleRestoreFile} style="display: none" />
		</div>
		{#if backupShortfall}
			<p class="warn-text" role="status" data-testid="backup-shortfall">
				{#if backupShortfall.missingTracks > 0}
					{m('settingsAccount.backupPartialNotice', {
						missing: backupShortfall.missingTracks,
						wanted: backupShortfall.wantedTracks,
					})}
				{/if}
				{#if backupShortfall.sections.length > 0}
					{m('settingsAccount.backupPartialSections', {
						sections: backupShortfall.sections.join(', '),
					})}
				{/if}
			</p>
		{/if}
		{#if restoreResult?.archiveIncomplete}
			<p class="warn-text" role="status" data-testid="restore-incomplete-archive">
				{restoreResult.archiveIncompleteSections.length > 0
					? m('settingsAccount.restoreArchiveIncomplete', {
							sections: restoreResult.archiveIncompleteSections.join(', '),
						})
					: m('settingsAccount.restoreArchiveIncompleteUnnamed')}
			</p>
		{/if}
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
			<button class="btn btn-outline" onclick={handleExportCsv} disabled={exporting || exportingJson || exportingGpx || exportingArchive || exportJobBuilding}>
				<span class="material-symbols">download</span>
				{exporting ? m('settingsAccount.exporting') : m('settingsAccount.exportCsv')}
			</button>
			<button class="btn btn-outline" onclick={handleExportJson} disabled={exporting || exportingJson || exportingGpx || exportingArchive || exportJobBuilding}>
				<span class="material-symbols">code</span>
				{exportingJson ? m('settingsAccount.exporting') : m('settingsAccount.exportJson')}
			</button>
			<button
				class="btn btn-outline"
				onclick={handleCloudGpxExport}
				disabled={exporting || exportingJson || exportingGpx || exportingArchive || exportJobBuilding}
				title={m('settingsAccount.cloudExportTitle')}
			>
				<span class="material-symbols">cloud_download</span>
				{exportingGpx || (exportJobBuilding && exportJob?.format === 'gpx')
					? m('settingsAccount.buildingZip')
					: m('settingsAccount.cloudExport')}
			</button>
		</div>
		<p class="section-desc" style="margin-top: 0.5rem; font-size: 0.85rem;">
			<strong>{m('settingsAccount.cloudExportFootnotePrefix')}</strong>{m('settingsAccount.cloudExportFootnoteSuffix')}
		</p>

		<div class="btn-row" style="margin-top: 0.75rem;">
			<button
				class="btn btn-outline"
				onclick={handleFullAccountArchive}
				disabled={exporting || exportingJson || exportingGpx || exportingArchive || exportJobBuilding}
				title={m('settingsAccount.fullArchiveTitle')}
				data-testid="full-account-archive"
			>
				<span class="material-symbols">database</span>
				{exportingArchive || (exportJobBuilding && exportJob?.format === 'backup')
					? m('settingsAccount.buildingZip')
					: m('settingsAccount.fullArchive')}
			</button>
		</div>
		<p class="section-desc" style="margin-top: 0.5rem; font-size: 0.85rem;">
			<strong>{m('settingsAccount.fullArchiveFootnotePrefix')}</strong>{m('settingsAccount.fullArchiveFootnoteSuffix')}
		</p>
		{#if exportJob && exportJob.status !== 'none'}
			<p class="section-desc" role="status" data-testid="export-job-state">
				{#if exportJob.status === 'queued' || exportJob.status === 'running'}
					{m('settingsAccount.exportBuildingNotice')}
				{:else if exportJob.status === 'ready' && exportJob.url}
					{m('settingsAccount.exportReadyNotice')}
					<a
						class="btn btn-outline"
						href={exportJob.url}
						target="_blank"
						rel="noopener"
						data-testid="export-job-download"
					>
						<span class="material-symbols">download</span>
						{m('settingsAccount.exportDownload')}
					</a>
				{:else if exportJob.status === 'expired'}
					{m('settingsAccount.exportExpiredNotice')}
				{:else if exportJob.status === 'stalled'}
					{m('settingsAccount.exportStalledNotice')}
				{:else}
					{m('settingsAccount.exportFailedNotice', { error: exportJob.error_code ?? 'unknown' })}
				{/if}
			</p>
		{/if}
		{#if exportStatusUnreadable}
			<p class="warn-text" role="status" data-testid="export-status-unreadable">
				{m('settingsAccount.exportStatusUnavailable')}
			</p>
		{/if}
		{#if exportShortfall}
			<p class="warn-text" role="status" data-testid="export-shortfall">
				{m('settingsAccount.exportPartialNotice', {
					count: exportShortfall.count,
					total: exportShortfall.total,
				})}
			</p>
		{/if}
	</section>

	<section class="card">
		<h2>{m('settingsAccount.coachConsentHeading')}</h2>
		{#if aiConsentGranted}
			<p class="section-desc">{m('settingsAccount.coachConsentActive')}</p>
			{#if aiConsentStale}
				<p class="section-desc" role="status">{m('settingsAccount.aiConsentUpdatedNotice')}</p>
				<AiDisclosureNotice />
			{/if}
			<div class="btn-row">
				{#if aiConsentStale}
					<button
						class="btn btn-primary"
						onclick={acceptUpdatedAiDisclosure}
						disabled={aiConsentAccepting}
					>
						<span class="material-symbols">verified_user</span>
						{aiConsentAccepting
							? m('settingsAccount.aiConsentAccepting')
							: m('settingsAccount.aiConsentAcceptUpdate')}
					</button>
				{/if}
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

	<!-- Sign out everywhere -->
	<section class="card" data-testid="signout-everywhere">
		<h2>{m('settingsAccount.signoutEverywhereHeading')}</h2>
		<p class="section-desc">{m('settingsAccount.signoutEverywhereDesc')}</p>
		<button
			class="btn btn-outline"
			onclick={() => (showSignOutEverywhere = true)}
			disabled={signingOutEverywhere}
			data-testid="signout-everywhere-btn"
		>
			<span class="material-symbols" aria-hidden="true">logout</span>
			{signingOutEverywhere
				? m('settingsAccount.signingOutEverywhere')
				: m('settingsAccount.signoutEverywhere')}
		</button>
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
	open={showAvatarRemoveConfirm}
	title={m('settingsAccount.avatarRemoveConfirmTitle')}
	message={m('settingsAccount.avatarRemoveConfirmMessage')}
	confirmLabel={m('settingsAccount.avatarRemove')}
	onconfirm={handleAvatarRemove}
	oncancel={() => (showAvatarRemoveConfirm = false)}
	danger
/>

<ConfirmDialog
	open={showSignOutEverywhere}
	title={m('settingsAccount.signoutEverywhereConfirmTitle')}
	message={m('settingsAccount.signoutEverywhereConfirmMessage')}
	confirmLabel={m('settingsAccount.signoutEverywhereConfirmLabel')}
	onconfirm={handleSignOutEverywhere}
	oncancel={() => (showSignOutEverywhere = false)}
/>

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
	.page { padding: var(--page-padding-y) var(--page-padding-x); max-width: 64rem; }
	.page-head { margin-bottom: var(--space-xl); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: var(--font-size-section-label);
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
	.form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(14rem, 100%), 1fr)); gap: var(--space-md); margin-bottom: var(--space-lg); }
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
	.email-change-btn { margin-top: var(--space-xs); align-self: flex-start; }
	.email-change-actions { margin-top: var(--space-xs); }
	.btn-row { display: flex; gap: var(--space-sm); flex-wrap: wrap; }
	.handle-row { display: flex; align-items: center; gap: var(--space-xs); }
	.handle-at { color: var(--color-text-tertiary); font-weight: 600; }
	.handle-input { flex: 1; min-width: 0; }
	.handle-save-btn { flex-shrink: 0; }
	.handle-help { display: block; font-size: 0.78rem; color: var(--color-text-tertiary); margin-top: var(--space-xs); }
	.error-text { color: var(--color-danger-text); font-size: 0.85rem; margin-top: var(--space-sm); }
	.ok-text { color: var(--color-success-text); font-size: 0.85rem; margin-top: var(--space-sm); }
	.warn-text { color: var(--color-warning-text); font-size: 0.85rem; margin-top: var(--space-sm); }
	.danger-heading { color: var(--color-danger-text); }
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
