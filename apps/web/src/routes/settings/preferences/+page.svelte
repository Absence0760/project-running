<script lang="ts">
	import { onMount } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import {
		loadSettings,
		updateUniversal,
		effective,
		type LoadedSettings,
	} from '$lib/settings/settings';
	import { applyTheme, loadTheme, type Theme } from '$lib/settings/theme';
	import { m, currentLocale, setLocale } from '$lib/i18n/store.svelte';
	import { SUPPORTED_LOCALES, LOCALE_LABELS, type Locale } from '$lib/i18n/locale';
	import { setUnit, setWeightUnit } from '$lib/format/units.svelte';
	import { defaultWeekStartForLocale } from '$lib/format/locale_defaults';
	import { setMapStyle } from '$lib/routes/map-style.svelte';
	import { fetchLatestWeightKg, recordWeightKg, clearWeightHistory } from '$lib/core/data';
	import { kgToDisplay, displayToKg, roundWeight } from '$lib/format/weight';
	import {
		ACTIVITY_LEVELS,
		type ActivityLevel,
		type WeightGoal,
	} from '$lib/nutrition/nutrition_targets';
	import { PRIVACY_ZONES_KEY, type PrivacyZone } from '$lib/routes/privacy';
	import PrivacyZonePicker from '$lib/components/PrivacyZonePicker.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { consent } from '$lib/settings/consent.svelte';

	let settings = $state<LoadedSettings | null>(null);
	let loading = $state(true);
	// Auto-save status for the cross-device prefs. Each control persists on
	// change (no global Save button) — `saveStatus` drives a subtle inline
	// "Saving…/Saved" cue so the user knows it took. The health-data
	// demographics keep their own explicit, consent-gated save below.
	let saveStatus = $state<'idle' | 'saving' | 'saved'>('idle');
	let savedTimer: ReturnType<typeof setTimeout> | null = null;
	// Demographics card has its own explicit save (GDPR Art 9 consent gate).
	let savingDemographics = $state(false);
	let demographicsSaved = $state(false);

	// Universal settings from docs/backend/settings.md
	let preferredUnit = $state<'km' | 'mi'>('km');
	let weightUnit = $state<'kg' | 'lbs'>('kg');
	let paceFormat = $state<'min_per_km' | 'min_per_mi' | 'kph' | 'mph'>('min_per_km');
	let defaultActivity = $state<'run' | 'walk' | 'hike' | 'cycle' | 'stroller'>('run');
	let weekStartDay = $state<'monday' | 'sunday'>('monday');
	let mapStyle = $state<'streets' | 'satellite' | 'outdoors' | 'dark'>('streets');
	let privacyDefault = $state<'public' | 'followers' | 'private'>('followers');
	let weeklyMileageGoal = $state('');
	let coachPersonality = $state<'supportive' | 'drill_sergeant' | 'analytical'>('supportive');
	let emailNotifications = $state<'all' | 'important' | 'off'>('important');
	// Opt-IN consent for the weekly engagement digest (bulk/promotional mail).
	// Default off — marketing consent is never inferred from the transactional
	// email_notifications key, so it's a deliberately separate toggle.
	let emailWeeklyDigest = $state(false);
	let stravaAutoShare = $state(false);
	let voiceFeedbackEnabled = $state(false);
	// 'full' (default) speaks every cue; 'minimal' drops the chatty in-rep
	// progress + pace-drift nudges on the recording clients (round-5 older).
	let voiceFeedbackVerbosity = $state('full');
	// Canonical store is km (`voice_feedback_interval_km`); the field shows
	// + accepts the user's unit so a mi-user entering 1 gets 1-mile splits,
	// not 1 km. audit-findings 2026-05-30 Medium [regional].
	const KM_PER_MI = 1.609344;
	let voiceFeedbackIntervalKm = $state('1.0');
	// Persona-hunt Round 3 finding Woman #2. Default true for back-
	// compat — every existing account stays findable until they
	// actively opt out via this toggle. The `search_user_profiles`
	// RPC reads the same key.
	let discoverableInSearch = $state(true);
	// Opt-out: drop gym load from the run fitness/fatigue/form curve so the
	// dashboard readiness stays run-only. Default off (gym counts).
	let excludeGymFromReadiness = $state(false);

	// Theme — persisted to localStorage, not the cross-device settings
	// bag. Intentionally per-browser: a dark laptop + a light iPad is a
	// common setup and a bag-scoped preference would fight that.
	let theme = $state<Theme>('auto');

	function changeTheme(next: Theme) {
		theme = next;
		applyTheme(next);
	}

	// Language — per-browser like theme (localStorage, applied via the
	// i18n runtime which also updates <html lang/dir>). The UI locale stays
	// client-side detected (decisions §108); separately, the applied tag is
	// mirrored into the universal settings bag (`locale`) purely so the
	// server can localize email (decisions §120) — it's never read back to
	// drive the UI. Options show each language's own endonym so it's
	// findable in any current UI language.
	let language = $state<Locale>('en');

	async function changeLanguage(next: Locale) {
		await setLocale(next);
		// Reflect the locale that actually applied — if the chunk failed to
		// load, setLocale keeps the current locale and the select snaps back
		// rather than lying about a switch that didn't happen.
		language = currentLocale();
		// Mirror to the bag for server-sent email localization (§120).
		if (auth.user) autoSave({ locale: language });
	}

	// Auto-save path. Changes are COALESCED: rapid edits (e.g. blurring two HR
	// fields back-to-back) accumulate into one batched updateUniversal so
	// concurrent partial writes can't clobber each other on a stale bag
	// snapshot. updateUniversal is offline-first (write-through cache + pending
	// queue, decisions §79). A short debounce keeps it invisible; beforeNavigate
	// flushes anything still pending so leaving the page never drops a change.
	let pendingChanges: Record<string, unknown> = {};
	let flushTimer: ReturnType<typeof setTimeout> | null = null;

	function autoSave(changes: Record<string, unknown>) {
		if (!auth.user) return;
		Object.assign(pendingChanges, changes);
		saveStatus = 'saving';
		if (flushTimer) clearTimeout(flushTimer);
		flushTimer = setTimeout(() => void flushPending(), 350);
	}

	async function flushPending() {
		if (flushTimer) {
			clearTimeout(flushTimer);
			flushTimer = null;
		}
		const uid = auth.user?.id;
		if (!uid || Object.keys(pendingChanges).length === 0) return;
		const batch = pendingChanges;
		pendingChanges = {};
		try {
			await updateUniversal(uid, batch);
			saveStatus = 'saved';
			if (savedTimer) clearTimeout(savedTimer);
			savedTimer = setTimeout(() => (saveStatus = 'idle'), 1800);
		} catch (e) {
			// Re-merge the failed batch (newer pending edits win) so it isn't lost.
			pendingChanges = { ...batch, ...pendingChanges };
			saveStatus = 'idle';
			showToast(`Couldn't save: ${(e as Error).message}`, 'error');
		}
	}

	// Flush any debounced change before leaving so a quick change-then-navigate
	// doesn't drop it (the write-through cache captures it even if the network
	// leg is interrupted mid-navigation).
	beforeNavigate(() => {
		void flushPending();
	});

	// When the user picks a distance unit, snap the pace format to the
	// matching min-per-unit choice (unless they've chosen a speed format),
	// apply the app-wide unit signal, and persist — including the legacy
	// dual-write of preferred_unit onto the profile column that leaderboard
	// RPCs read.
	async function pickDistanceUnit(next: 'km' | 'mi') {
		preferredUnit = next;
		if (paceFormat !== 'kph' && paceFormat !== 'mph') {
			paceFormat = next === 'mi' ? 'min_per_mi' : 'min_per_km';
		}
		setUnit(next);
		// Dual-write the profile column the auth store + leaderboard RPCs read
		// on the next load. AWAIT it (not fire-and-forget) so the "Saved" cue —
		// and therefore a subsequent reload — reflects the change deterministically.
		if (auth.user) {
			const uid = auth.user.id;
			saveStatus = 'saving';
			try {
				const { error } = await supabase
					.from('user_profiles')
					.update({ preferred_unit: next })
					.eq('id', uid);
				if (error) throw error;
			} catch (e) {
				saveStatus = 'idle';
				showToast(`Couldn't save: ${(e as Error).message}`, 'error');
				return;
			}
		}
		await autoSave({ preferred_unit: next, units_pace_format: paceFormat });
	}

	// Weight unit (kg/lbs) is display + entry only — storage stays canonical
	// kg (gym_sets.weight_kg). Flip the app-wide weight signal so every gym
	// surface re-renders, then persist the universal bag key.
	async function pickWeightUnit(next: 'kg' | 'lbs') {
		weightUnit = next;
		setWeightUnit(next);
		await autoSave({ weight_unit: next });
	}

	// Measured resting + max HR. max_hr_bpm overrides the Tanaka
	// 208 − 0.7 × age estimate for HR-zone derivation — the reason a
	// beta-blocked runner whose formula HR-max is wrong needs to set it.
	let restingHr = $state('');
	let maxHr = $state('');

	// HR zones
	let z1 = $state('');
	let z2 = $state('');
	let z3 = $state('');
	let z4 = $state('');
	let z5 = $state('');

	// Demographics — live on user_profiles, not the cross-device prefs bag.
	// Used only by tiered segment leaderboards. Both fields are optional;
	// leaving them blank simply means the runner doesn't appear in
	// gender/age-band-filtered views. Gender + DOB combined are
	// special-category data under GDPR Art 9 (health-adjacent) —
	// `healthDataConsent` captures the explicit Art 9(2)(a) consent
	// timestamp. Withdrawing consent nulls both fields atomically.
	let gender = $state<'male' | 'female' | 'nonbinary' | ''>('');
	let dateOfBirth = $state('');
	let healthDataConsent = $state(false);
	let healthDataConsentAt = $state<string | null>(null);
	// Body metrics for the nutrition BMR target — also Art 9 health data, so
	// they share the demographics consent gate. Height lives on user_profiles;
	// weight is appended to the body_metrics time-series on save. Both are
	// shown in cm / the user's weight unit but stored canonically (cm, kg).
	// Bound to <input type="number">, so these hold a number (or null when
	// empty) — never call string methods on them.
	let heightCm = $state<number | null>(null);
	let weightInput = $state<number | null>(null); // in the user's weight unit
	let loadedWeightKg = $state<number | null>(null);
	// Activity level + goal are nutrition preferences (not special-category),
	// so they auto-save to the prefs bag like everything else above.
	let nutritionActivityLevel = $state<ActivityLevel>('moderate');
	let nutritionGoal = $state<WeightGoal>('maintain');

	// Privacy zones — geofences clipped from public track renders.
	let privacyZones = $state<PrivacyZone[]>([]);
	let showZonePicker = $state(false);

	onMount(async () => {
		// Theme is local-only so it's available even before the bag loads.
		theme = loadTheme();
		// Language was already negotiated + applied by the app shell's
		// initLocale on first mount; reflect the active value in the picker.
		language = currentLocale();

		// `auth.svelte.ts` flips loading=false before the async fetchUser
		// resolves, so a hard reload lands here with auth.user still
		// null. Poll briefly so the form actually renders — without
		// this the user sees "Loading..." forever and the entire
		// preferences page silently fails.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		try {
			settings = await loadSettings(auth.user.id);
			preferredUnit = effective(settings, 'preferred_unit', 'km') ?? 'km';
			setUnit(preferredUnit);
			weightUnit = effective(settings, 'weight_unit', 'kg') ?? 'kg';
			setWeightUnit(weightUnit);
			paceFormat = effective(settings, 'units_pace_format', 'min_per_km') ?? 'min_per_km';
			defaultActivity = effective(settings, 'default_activity_type', 'run') ?? 'run';
			// New users have no stored week_start_day — fall back to the
			// locale convention (Sunday-first for US/CA/…, Monday for ISO)
			// instead of hard-coding Monday. audit-findings 2026-05-30
			// Medium [regional].
			weekStartDay =
				effective(settings, 'week_start_day', defaultWeekStartForLocale(navigator.language)) ??
				'monday';
			mapStyle = effective(settings, 'map_style', 'streets') ?? 'streets';
			setMapStyle(mapStyle);
			privacyDefault = effective(settings, 'privacy_default', 'followers') ?? 'followers';
			weeklyMileageGoal = (effective<number>(settings, 'weekly_mileage_goal_m') ?? '')?.toString() ?? '';
			coachPersonality = effective(settings, 'coach_personality', 'supportive') ?? 'supportive';
			emailNotifications = effective(settings, 'email_notifications', 'important') ?? 'important';
			emailWeeklyDigest = effective<string>(settings, 'email_weekly_digest', 'off') === 'on';
			stravaAutoShare = effective(settings, 'strava_auto_share', false) ?? false;
			voiceFeedbackEnabled = effective(settings, 'voice_feedback_enabled', false) ?? false;
			voiceFeedbackVerbosity =
				effective<string>(settings, 'voice_feedback_verbosity', 'full') ?? 'full';
			voiceFeedbackIntervalKm = (
				effective<number>(settings, 'voice_feedback_interval_km', 1.0) ?? 1.0
			).toString();
			discoverableInSearch = effective(settings, 'discoverable_in_search', true) ?? true;
			excludeGymFromReadiness = effective<boolean>(settings, 'exclude_gym_from_readiness', false) === true;

			restingHr = (effective<number>(settings, 'resting_hr_bpm') ?? '')?.toString() ?? '';
			maxHr = (effective<number>(settings, 'max_hr_bpm') ?? '')?.toString() ?? '';

			const zones = effective<Record<string, number>>(settings, 'hr_zones');
			if (zones) {
				z1 = zones.z1?.toString() ?? '';
				z2 = zones.z2?.toString() ?? '';
				z3 = zones.z3?.toString() ?? '';
				z4 = zones.z4?.toString() ?? '';
				z5 = zones.z5?.toString() ?? '';
			}

			privacyZones = effective<PrivacyZone[]>(settings, PRIVACY_ZONES_KEY) ?? [];

			// Backfill the server-side email locale once for users who never
			// open the language picker, so their email still matches their
			// detected UI language (§120). Only writes when absent.
			if (auth.user && effective<string>(settings, 'locale') == null) {
				autoSave({ locale: currentLocale() });
			}

			// Self-read via get_my_profile(): gender / date_of_birth /
			// health_data_consent_at are deny-by-default for direct
			// authenticated SELECTs (column lockdown, 20260707_001).
			const { data: prof } = await supabase.rpc('get_my_profile');
			if (prof) {
				gender = (prof.gender as typeof gender) ?? '';
				dateOfBirth = prof.date_of_birth ?? '';
				heightCm = prof.height_cm ?? null;
				healthDataConsentAt = (prof.health_data_consent_at as string | null) ?? null;
				// Default the checkbox to the persisted state. If the row
				// already carries a consent timestamp the user has
				// previously ticked the box — keep it ticked so they
				// can edit without re-consenting.
				healthDataConsent = healthDataConsentAt != null;
			}

			nutritionActivityLevel =
				effective<ActivityLevel>(settings, 'nutrition_activity_level', 'moderate') ?? 'moderate';
			nutritionGoal = effective<WeightGoal>(settings, 'nutrition_goal', 'maintain') ?? 'maintain';

			// Latest weight is owner-only (body_metrics, no public read). Shown
			// in the user's weight unit; stored canonical kg.
			loadedWeightKg = await fetchLatestWeightKg();
			weightInput =
				loadedWeightKg != null ? roundWeight(kgToDisplay(loadedWeightKg, weightUnit)) : null;
		} catch (e) {
			console.warn('Settings load failed', e);
		}
		loading = false;
	});

	async function persistZones(next: PrivacyZone[]) {
		if (!auth.user) return;
		await updateUniversal(auth.user.id, { [PRIVACY_ZONES_KEY]: next });
		privacyZones = next;
	}

	async function addZone(zone: PrivacyZone) {
		showZonePicker = false;
		await persistZones([...privacyZones, zone]);
	}

	async function removeZone(idx: number) {
		await persistZones(privacyZones.filter((_, i) => i !== idx));
	}

	// HR zones are a single jsonb object — rebuild it from the five fields on
	// each blur and auto-save (null when all blank). Resting/max HR auto-save
	// independently. These are health-adjacent but not Art 9 special category,
	// and carry no consent gate today, so auto-saving keeps the existing
	// posture (see the consent-flow follow-up).
	function saveHrZones() {
		const z =
			z1 || z2 || z3 || z4 || z5
				? {
						z1: parseInt(z1, 10) || 0,
						z2: parseInt(z2, 10) || 0,
						z3: parseInt(z3, 10) || 0,
						z4: parseInt(z4, 10) || 0,
						z5: parseInt(z5, 10) || 0,
					}
				: null;
		void autoSave({ hr_zones: z });
	}

	// Demographics (gender + DOB) are special-category data under GDPR Art 9,
	// so they keep an EXPLICIT, consent-gated save rather than auto-saving —
	// the user must deliberately confirm. Grant stamps the consent timestamp
	// via a SECURITY DEFINER RPC (first-stamp-wins, lock-trigger enforced);
	// withdrawal nulls gender + DOB + the timestamp atomically per Art 7(3).
	// Withdrawing consent (Art 7(3)) erases the saved height + the entire
	// weight time-series — irreversible, so confirm before running the save.
	let showWithdrawConfirm = $state(false);
	function requestSaveDemographics() {
		if (!healthDataConsent && healthDataConsentAt != null) {
			showWithdrawConfirm = true;
			return;
		}
		saveDemographics();
	}

	async function saveDemographics() {
		if (!auth.user) return;
		const heightVal = heightCm != null && heightCm > 0 ? heightCm : null;
		const weightDisplay = weightInput != null && weightInput > 0 ? weightInput : null;
		const hasDemographic = !!(gender || dateOfBirth || heightVal != null || weightDisplay != null);
		if (hasDemographic && !healthDataConsent) {
			showToast(m('prefs.demographicsConsentRequired'), 'error');
			return;
		}
		savingDemographics = true;
		demographicsSaved = false;
		try {
			if (healthDataConsent && healthDataConsentAt == null) {
				const { data: stampedAt, error: consentErr } =
					await supabase.rpc('grant_health_data_consent');
				if (consentErr) {
					showToast(`Save failed: ${consentErr.message}`, 'error');
					return;
				}
				if (stampedAt) healthDataConsentAt = stampedAt as string;
			}
			const profileUpdate: Record<string, unknown> = {
				gender: healthDataConsent && gender ? gender : null,
				date_of_birth: healthDataConsent && dateOfBirth ? dateOfBirth : null,
				height_cm: healthDataConsent && heightVal != null ? heightVal : null,
			};
			if (!healthDataConsent) {
				profileUpdate.health_data_consent_at = null;
				healthDataConsentAt = null;
			}
			const { error } = await supabase
				.from('user_profiles')
				.update(profileUpdate)
				.eq('id', auth.user.id);
			if (error) throw error;

			if (!healthDataConsent) {
				// Art 7(3): withdrawing consent clears the special-category
				// series alongside the profile fields.
				await clearWeightHistory();
				loadedWeightKg = null;
				weightInput = null;
			} else if (weightDisplay != null && weightDisplay > 0) {
				// Append a new measurement only when the value changed, so
				// re-saving the card doesn't pad the time-series.
				const kg = roundWeight(displayToKg(weightDisplay, weightUnit));
				if (loadedWeightKg == null || Math.abs(kg - loadedWeightKg) > 0.01) {
					await recordWeightKg(kg);
					loadedWeightKg = kg;
				}
			}
			demographicsSaved = true;
			showToast(m('prefs.demographicsSavedToast'), 'success');
			setTimeout(() => (demographicsSaved = false), 2000);
		} catch (e) {
			showToast(`Save failed: ${(e as Error).message}`, 'error');
		} finally {
			savingDemographics = false;
		}
	}

	function saveNutritionPref(changes: Record<string, unknown>) {
		autoSave(changes);
	}
</script>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('prefs.kicker')}</p>
		<h1>{m('prefs.heading')}</h1>
		<p class="tagline">
			{m('prefs.tagline')}
		</p>
		<p class="save-status" role="status" aria-live="polite" data-testid="save-status">
			{#if saveStatus === 'saving'}
				<span class="material-symbols spin" aria-hidden="true">progress_activity</span> {m('prefs.saving')}
			{:else if saveStatus === 'saved'}
				<span class="material-symbols" aria-hidden="true">check_circle</span> {m('prefs.saved')}
			{/if}
		</p>
	</header>

	{#if loading}
		<div class="skeleton-stack" aria-hidden="true">
			{#each Array(4) as _, i (i)}
				<div class="skel-card">
					<span class="skel skel-line skel-w-30"></span>
					<div class="skel-grid">
						<span class="skel skel-field"></span>
						<span class="skel skel-field"></span>
						<span class="skel skel-field"></span>
						<span class="skel skel-field"></span>
					</div>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{m('prefs.loading')}</p>
	{:else}
		<!-- Units -->
		<section class="card">
			<h2>{m('prefs.unitsDisplayHeading')}</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.language')}</span>
					<select
						value={language}
						onchange={(e) => changeLanguage(e.currentTarget.value as Locale)}
						data-testid="language-select"
					>
						{#each SUPPORTED_LOCALES as loc}
							<option value={loc}>{LOCALE_LABELS[loc]}</option>
						{/each}
					</select>
				</label>
				<div class="field">
					<span class="label-text">{m('prefs.distanceUnit')}</span>
					<div class="toggle-row" role="group" aria-label={m('prefs.distanceUnit')}>
						<button class="toggle-btn" class:active={preferredUnit === 'km'} onclick={() => pickDistanceUnit('km')} type="button">{m('prefs.kilometres')}</button>
						<button class="toggle-btn" class:active={preferredUnit === 'mi'} onclick={() => pickDistanceUnit('mi')} type="button">{m('prefs.miles')}</button>
					</div>
				</div>
				<div class="field">
					<span class="label-text">{m('prefs.weightUnit')}</span>
					<div class="toggle-row" role="group" aria-label={m('prefs.weightUnit')}>
						<button class="toggle-btn" class:active={weightUnit === 'kg'} onclick={() => pickWeightUnit('kg')} type="button">{m('prefs.kilograms')}</button>
						<button class="toggle-btn" class:active={weightUnit === 'lbs'} onclick={() => pickWeightUnit('lbs')} type="button">{m('prefs.pounds')}</button>
					</div>
				</div>
				<label>
					<span class="label-text">{m('prefs.paceFormat')}</span>
					<select bind:value={paceFormat} onchange={() => autoSave({ units_pace_format: paceFormat })}>
						<option value="min_per_km">min/km</option>
						<option value="min_per_mi">min/mi</option>
						<option value="kph">km/h</option>
						<option value="mph">mph</option>
					</select>
				</label>
				<label>
					<span class="label-text">{m('prefs.mapStyle')}</span>
					<select
						bind:value={mapStyle}
						onchange={() => {
							setMapStyle(mapStyle);
							autoSave({ map_style: mapStyle });
						}}
					>
						<option value="streets">{m('prefs.mapStyleStreets')}</option>
						<option value="satellite">{m('prefs.mapStyleSatellite')}</option>
						<option value="outdoors">{m('prefs.mapStyleOutdoors')}</option>
						<option value="dark">{m('prefs.mapStyleDark')}</option>
					</select>
				</label>
				<label>
					<span class="label-text">{m('prefs.weekStartsOn')}</span>
					<select bind:value={weekStartDay} onchange={() => autoSave({ week_start_day: weekStartDay })}>
						<option value="monday">{m('prefs.monday')}</option>
						<option value="sunday">{m('prefs.sunday')}</option>
					</select>
				</label>
				<div class="field">
					<span class="label-text">{m('prefs.theme')}</span>
					<div class="toggle-row" role="group" aria-label={m('prefs.theme')}>
						<button
							class="toggle-btn"
							class:active={theme === 'auto'}
							onclick={() => changeTheme('auto')}
							type="button"
						>{m('prefs.themeAuto')}</button>
						<button
							class="toggle-btn"
							class:active={theme === 'light'}
							onclick={() => changeTheme('light')}
							type="button"
						>{m('prefs.themeLight')}</button>
						<button
							class="toggle-btn"
							class:active={theme === 'dark'}
							onclick={() => changeTheme('dark')}
							type="button"
						>{m('prefs.themeDark')}</button>
					</div>
				</div>
			</div>
		</section>

		<!-- Activity & Recording -->
		<section class="card">
			<h2>{m('prefs.activityRecordingHeading')}</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.defaultActivity')}</span>
					<select bind:value={defaultActivity} onchange={() => autoSave({ default_activity_type: defaultActivity })}>
						<option value="run">{m('prefs.activityRun')}</option>
						<option value="walk">{m('prefs.activityWalk')}</option>
						<option value="hike">{m('prefs.activityHike')}</option>
						<option value="cycle">{m('prefs.activityCycle')}</option>
					</select>
				</label>
				<label class="checkbox-label">
					<input type="checkbox" bind:checked={voiceFeedbackEnabled} onchange={() => autoSave({ voice_feedback_enabled: voiceFeedbackEnabled })} />
					<span>{m('prefs.spokenSplits')}</span>
				</label>
				{#if voiceFeedbackEnabled}
					<label>
						<span class="label-text">{m('prefs.cueDetail')}</span>
						<select bind:value={voiceFeedbackVerbosity} onchange={() => autoSave({ voice_feedback_verbosity: voiceFeedbackVerbosity })}>
							<option value="full">{m('prefs.cueDetailFull')}</option>
							<option value="minimal">{m('prefs.cueDetailMinimal')}</option>
						</select>
					</label>
					<label>
						<span class="label-text">{m('prefs.splitInterval', { unit: preferredUnit })}</span>
						<!-- min/max/step are in the displayed unit by design — a
						     0.5–10 range reads as round numbers whether the user
						     thinks in km or mi (a mi-user gets 0.5–10 mile splits,
						     stored as the equivalent km). -->
						<input
							type="number"
							value={preferredUnit === 'mi'
								? (parseFloat(voiceFeedbackIntervalKm) / KM_PER_MI).toFixed(1)
								: voiceFeedbackIntervalKm}
							oninput={(e) => {
								const n = parseFloat(e.currentTarget.value);
								if (Number.isFinite(n)) {
									voiceFeedbackIntervalKm = (
										preferredUnit === 'mi' ? n * KM_PER_MI : n
									).toString();
								}
							}}
							step="0.5"
							min="0.5"
							max="10"
							onblur={() => autoSave({ voice_feedback_interval_km: parseFloat(voiceFeedbackIntervalKm) || 1.0 })}
						/>
					</label>
				{/if}
				<label id="weekly-mileage-goal">
					<span class="label-text">{m('prefs.weeklyMileageGoal')}</span>
					<input
						type="number"
						bind:value={weeklyMileageGoal}
						placeholder={m('prefs.weeklyMileageGoalPlaceholder')}
						onblur={() => autoSave({ weekly_mileage_goal_m: weeklyMileageGoal ? parseInt(weeklyMileageGoal, 10) || null : null })}
					/>
				</label>
			</div>
		</section>

		<!-- Heart Rate Zones -->
		<section class="card" id="heart-rate-zones">
			<h2>{m('prefs.heartRateZonesHeading')}</h2>
			<p class="section-desc">
				{m('prefs.heartRateZonesDesc')}
			</p>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.restingHr')}</span>
					<input type="number" bind:value={restingHr} min="30" max="120" placeholder={m('prefs.restingHrPlaceholder')} onblur={() => autoSave({ resting_hr_bpm: restingHr ? parseInt(restingHr, 10) || null : null })} />
				</label>
				<label>
					<span class="label-text">{m('prefs.maxHr')}</span>
					<input type="number" bind:value={maxHr} min="100" max="230" placeholder={m('prefs.maxHrPlaceholder')} onblur={() => autoSave({ max_hr_bpm: maxHr ? parseInt(maxHr, 10) || null : null })} />
				</label>
			</div>
			<p class="section-desc">{m('prefs.zonesUpperBoundDesc')}</p>
			<div class="form-grid zones">
				<label><span class="label-text">{m('prefs.zone1Recovery')}</span><input type="number" bind:value={z1} placeholder="130" onblur={saveHrZones} /></label>
				<label><span class="label-text">{m('prefs.zone2Easy')}</span><input type="number" bind:value={z2} placeholder="145" onblur={saveHrZones} /></label>
				<label><span class="label-text">{m('prefs.zone3Tempo')}</span><input type="number" bind:value={z3} placeholder="160" onblur={saveHrZones} /></label>
				<label><span class="label-text">{m('prefs.zone4Threshold')}</span><input type="number" bind:value={z4} placeholder="175" onblur={saveHrZones} /></label>
				<label><span class="label-text">{m('prefs.zone5Max')}</span><input type="number" bind:value={z5} placeholder="195" onblur={saveHrZones} /></label>
			</div>
			<label class="checkbox-row">
				<input type="checkbox" bind:checked={excludeGymFromReadiness} onchange={() => autoSave({ exclude_gym_from_readiness: excludeGymFromReadiness })} />
				<span>
					{m('prefs.excludeGymFromReadiness')}
					<span class="hint">{m('prefs.excludeGymFromReadinessHint')}</span>
				</span>
			</label>
		</section>

		<!-- Privacy & Sharing -->
		<section class="card">
			<h2>{m('prefs.privacySharingHeading')}</h2>
			<div class="form-stack">
				<label class="field">
					<span class="label-text">{m('prefs.defaultVisibility')}</span>
					<select bind:value={privacyDefault} onchange={() => autoSave({ privacy_default: privacyDefault })}>
						<option value="public">{m('prefs.visibilityPublic')}</option>
						<option value="followers">{m('prefs.visibilityFollowers')}</option>
						<option value="private">{m('prefs.visibilityPrivate')}</option>
					</select>
				</label>
				<label class="checkbox-row">
					<input type="checkbox" bind:checked={stravaAutoShare} onchange={() => autoSave({ strava_auto_share: stravaAutoShare })} />
					<span>{m('prefs.autoPushStrava')}</span>
				</label>
				<label class="checkbox-row">
					<input type="checkbox" bind:checked={discoverableInSearch} onchange={() => autoSave({ discoverable_in_search: discoverableInSearch })} />
					<span>
						{m('prefs.showInSearch')}
						<span class="hint">
							{m('prefs.showInSearchHint')}
						</span>
					</span>
				</label>
			</div>
		</section>

		<!-- Demographics — gender + DOB power tiered segment leaderboards.
		     Combined they are special-category data under GDPR Art 9 so the
		     explicit-consent checkbox is the precondition for saving either. -->
		<section class="card">
			<h2>{m('prefs.demographicsHeading')}</h2>
			<p class="section-desc">
				{m('prefs.demographicsDesc')}
			</p>
			<p class="section-desc consent-notice">
				{m('prefs.demographicsConsentNotice')}
				<a href="/privacy">{m('prefs.privacyPolicyLink')}</a>{m('prefs.demographicsConsentNoticeTail')}
			</p>
			<label class="consent-checkbox">
				<input type="checkbox" bind:checked={healthDataConsent} />
				<span>
					{m('prefs.demographicsConsent')}
				</span>
			</label>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.gender')}</span>
					<select bind:value={gender} disabled={!healthDataConsent}>
						<option value="">{m('prefs.genderPreferNotToSay')}</option>
						<option value="male">{m('prefs.genderMale')}</option>
						<option value="female">{m('prefs.genderFemale')}</option>
						<option value="nonbinary">{m('prefs.genderNonbinary')}</option>
					</select>
				</label>
				<label>
					<span class="label-text">{m('prefs.dateOfBirth')}</span>
					<input type="date" bind:value={dateOfBirth} disabled={!healthDataConsent} />
				</label>
				<label>
					<span class="label-text">{m('prefs.heightCm')}</span>
					<input
						type="number"
						min="0"
						max="300"
						inputmode="numeric"
						bind:value={heightCm}
						disabled={!healthDataConsent}
						data-testid="height-cm"
					/>
				</label>
				<label>
					<span class="label-text">{m('prefs.weight')} ({weightUnit})</span>
					<input
						type="number"
						min="0"
						inputmode="decimal"
						bind:value={weightInput}
						disabled={!healthDataConsent}
						data-testid="weight"
					/>
				</label>
			</div>
			{#if healthDataConsentAt}
				<p class="section-hint">
					{m('prefs.consentRecordedOn', { date: new Date(healthDataConsentAt).toLocaleDateString() })}
				</p>
			{/if}
			<!-- Unlike the rest of the page, demographics do NOT auto-save:
			     they are Art 9 special-category data, so persisting them is a
			     deliberate, consent-gated action behind this button. -->
			<button
				class="btn btn-primary btn-save"
				type="button"
				onclick={requestSaveDemographics}
				disabled={savingDemographics}
				data-testid="save-demographics"
			>
				{savingDemographics ? m('prefs.saving') : demographicsSaved ? m('prefs.demographicsSavedBtn') : m('prefs.saveDemographics')}
			</button>

			<!-- Nutrition target inputs — activity level + weight goal feed the
			     Mifflin-St Jeor target on /nutrition. Effort labels, not body
			     measurements, so they auto-save and aren't consent-gated. -->
			<div class="form-grid nutrition-targets-grid">
				<label>
					<span class="label-text">{m('prefs.activityLevel')}</span>
					<select
						bind:value={nutritionActivityLevel}
						onchange={() => saveNutritionPref({ nutrition_activity_level: nutritionActivityLevel })}
						data-testid="activity-level"
					>
						{#each ACTIVITY_LEVELS as lvl (lvl.key)}
							<option value={lvl.key}>{m(`prefs.activity_${lvl.key}`)}</option>
						{/each}
					</select>
				</label>
				<label>
					<span class="label-text">{m('prefs.weightGoal')}</span>
					<select
						bind:value={nutritionGoal}
						onchange={() => saveNutritionPref({ nutrition_goal: nutritionGoal })}
						data-testid="weight-goal"
					>
						<option value="lose">{m('prefs.goalLose')}</option>
						<option value="maintain">{m('prefs.goalMaintain')}</option>
						<option value="gain">{m('prefs.goalGain')}</option>
					</select>
				</label>
			</div>
			<p class="section-hint">{m('prefs.nutritionTargetsHint')}</p>
		</section>

		<!-- Privacy zones — clipped from the start and end of public tracks. -->
		<section class="card">
			<h2>{m('prefs.privacyZonesHeading')}</h2>
			<p class="section-hint">
				{m('prefs.privacyZonesDesc')}
			</p>

			{#if privacyZones.length === 0}
				<div class="inline-empty">
					<span class="material-symbols" aria-hidden="true">my_location</span>
					<p>{m('prefs.privacyZonesEmpty')}</p>
				</div>
			{:else}
				<ul class="zone-list">
					{#each privacyZones as zone, idx (idx)}
						<li class="zone-row">
							<div>
								<div class="zone-coords">
									{zone.lat.toFixed(5)}, {zone.lng.toFixed(5)}
								</div>
								<div class="zone-radius">{m('prefs.zoneRadius', { radius: String(zone.radius_m) })}</div>
							</div>
							<button class="btn btn-outline btn-sm" type="button" onclick={() => removeZone(idx)}>
								{m('prefs.removeZone')}
							</button>
						</li>
					{/each}
				</ul>
			{/if}

			<div>
				<button class="btn btn-primary" type="button" onclick={() => (showZonePicker = true)}>
					<span class="material-symbols">add</span>
					{m('prefs.addZone')}
				</button>
			</div>
		</section>

		<!-- Telemetry consent (Sentry). Mirrors the cookie banner's
		     accept/reject choice so a returning user can withdraw their
		     earlier acceptance per GDPR Art 7(3) / Art 21. The hook in
		     hooks.server.ts + hooks.client.ts gates Sentry on this
		     state. See audit/gdpr (2026-05-25) High. -->
		<section class="card">
			<h2>{m('prefs.telemetryHeading')}</h2>
			<p class="section-desc">
				{m('prefs.telemetryDesc')}
			</p>
			<label class="consent-checkbox">
				<input
					type="checkbox"
					checked={consent.choice === 'accepted'}
					onchange={(e) => {
						const enabled = (e.currentTarget as HTMLInputElement).checked;
						consent.set(enabled ? 'accepted' : 'rejected');
						showToast(
							enabled
								? 'Error reporting enabled.'
								: 'Error reporting disabled. Reload to apply.',
							'success',
						);
					}}
				/>
				<span>{m('prefs.telemetryConsent')}</span>
			</label>
			{#if consent.timestamp}
				<p class="section-hint">
					{m('prefs.choiceRecordedOn', { date: new Date(consent.timestamp).toLocaleDateString() })}
				</p>
			{/if}
		</section>

		<!-- AI Coach -->
		<section class="card">
			<h2>{m('prefs.aiCoachHeading')}</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.coachPersonality')}</span>
					<select bind:value={coachPersonality} onchange={() => autoSave({ coach_personality: coachPersonality })}>
						<option value="supportive">{m('prefs.coachSupportive')}</option>
						<option value="drill_sergeant">{m('prefs.coachDrillSergeant')}</option>
						<option value="analytical">{m('prefs.coachAnalytical')}</option>
					</select>
				</label>
			</div>
		</section>

		<!-- Notifications -->
		<section class="card">
			<h2>{m('prefs.notificationsHeading')}</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">{m('prefs.emailNotifications')}</span>
					<select
						bind:value={emailNotifications}
						onchange={() => autoSave({ email_notifications: emailNotifications })}
					>
						<option value="important">{m('prefs.emailNotifImportant')}</option>
						<option value="all">{m('prefs.emailNotifAll')}</option>
						<option value="off">{m('prefs.emailNotifOff')}</option>
					</select>
				</label>
				<p class="section-hint">{m('prefs.emailNotifHint')}</p>
			</div>
			<label class="checkbox-row">
				<input
					type="checkbox"
					bind:checked={emailWeeklyDigest}
					onchange={() => autoSave({ email_weekly_digest: emailWeeklyDigest ? 'on' : 'off' })}
					data-testid="email-weekly-digest"
				/>
				<span>
					{m('prefs.emailWeeklyDigest')}
					<span class="hint">{m('prefs.emailWeeklyDigestHint')}</span>
				</span>
			</label>
		</section>
	{/if}
</div>

<Modal
	open={showZonePicker}
	title={m('prefs.addZoneModalTitle')}
	onclose={() => (showZonePicker = false)}
	wide
>
	<PrivacyZonePicker oncreated={addZone} oncancel={() => (showZonePicker = false)} />
</Modal>

<ConfirmDialog
	open={showWithdrawConfirm}
	title={m('prefs.withdrawConsentTitle')}
	message={m('prefs.withdrawConsentMessage')}
	confirmLabel={m('prefs.withdrawConsentConfirm')}
	onconfirm={() => {
		showWithdrawConfirm = false;
		saveDemographics();
	}}
	oncancel={() => (showWithdrawConfirm = false)}
	danger
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
	.save-status {
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		min-height: 1.25rem;
		margin: var(--space-xs) 0 0;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-success, #2e7d32);
	}
	.save-status .material-symbols {
		font-size: 1rem;
	}
	.save-status .spin {
		animation: prefs-spin 0.8s linear infinite;
	}
	@keyframes prefs-spin {
		to {
			transform: rotate(360deg);
		}
	}
	h2 { font-size: 0.9rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: var(--space-lg); }
	.inline-empty {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-md);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-md);
	}
	.inline-empty .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.4rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.inline-empty p {
		margin: 0;
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.4;
	}

	/* Skeletons — same shape language as /u/[id], /runs, /clubs. */
	.skeleton-stack { display: flex; flex-direction: column; gap: var(--space-xl); }
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		pointer-events: none;
	}
	.skel-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-md);
	}
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
	.skel-field { height: 2.4rem; border-radius: var(--radius-md); }
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
	.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); margin-bottom: var(--space-xl); }
	.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md); margin-bottom: var(--space-lg); }
	.form-grid.zones { grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr)); }
	.form-stack { display: flex; flex-direction: column; gap: var(--space-md); margin-bottom: var(--space-lg); }
	.field { display: flex; flex-direction: column; }
	.checkbox-row { display: flex; align-items: flex-start; gap: 0.5rem; font-size: 0.9rem; }
	.checkbox-row .hint {
		display: block;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		line-height: 1.45;
		margin-top: 0.2rem;
	}
	.label-text { display: block; font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary); margin-bottom: var(--space-xs); }
	input, select { width: 100%; padding: var(--space-sm) var(--space-md); border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.9rem; background: var(--color-bg); }
	input[type="checkbox"] { width: auto; padding: 0; flex-shrink: 0; }
	input:focus, select:focus { outline: none; border-color: var(--color-primary); }
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	input:focus-visible, select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.toggle-row { display: flex; gap: var(--space-sm); }
	.toggle-btn { flex: 1; padding: var(--space-sm) var(--space-md); border: 1.5px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg); font-size: 0.85rem; font-weight: 500; color: var(--color-text-secondary); cursor: pointer; transition: all var(--transition-fast); }
	.toggle-btn:hover { border-color: var(--color-primary); }
	.toggle-btn.active { background: var(--color-primary-light); border-color: var(--color-primary); color: var(--color-primary); }
	.checkbox-label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; padding-top: 1.2rem; }
	.section-desc { font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: var(--space-md); line-height: 1.5; }
	.consent-notice { background: var(--color-bg-tertiary); border-inline-start: 3px solid var(--color-primary); padding: var(--space-sm) var(--space-md); border-radius: var(--radius-sm); margin-top: var(--space-md); }
	.consent-checkbox { display: flex; gap: var(--space-sm); align-items: flex-start; font-size: 0.9rem; line-height: 1.45; margin-bottom: var(--space-md); padding: var(--space-sm) 0; }
	.consent-checkbox input { margin-top: 0.2rem; flex-shrink: 0; }
	.btn-save { width: auto; }
	.muted { color: var(--color-text-tertiary); }
	.section-hint { color: var(--color-text-secondary); font-size: 0.9rem; line-height: 1.5; margin: 0 0 var(--space-md) 0; }
	.zone-list { list-style: none; padding: 0; margin: 0 0 var(--space-md) 0; display: flex; flex-direction: column; gap: var(--space-sm); }
	.zone-row { display: flex; align-items: center; justify-content: space-between; gap: var(--space-md); padding: var(--space-sm) var(--space-md); background: var(--color-bg-tertiary); border-radius: var(--radius-md); }
	.zone-coords { font-variant-numeric: tabular-nums; font-weight: 600; }
	.zone-radius { font-size: 0.85rem; color: var(--color-text-secondary); }
</style>
