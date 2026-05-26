<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import {
		loadSettings,
		updateUniversal,
		effective,
		type LoadedSettings,
	} from '$lib/settings';
	import { applyTheme, loadTheme, type Theme } from '$lib/theme';
	import { setUnit } from '$lib/units.svelte';
	import { setMapStyle } from '$lib/map-style.svelte';
	import { PRIVACY_ZONES_KEY, type PrivacyZone } from '$lib/privacy';
	import PrivacyZonePicker from '$lib/components/PrivacyZonePicker.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { consent } from '$lib/consent.svelte';

	let settings = $state<LoadedSettings | null>(null);
	let loading = $state(true);
	let saving = $state(false);
	let saved = $state(false);

	// Universal settings from docs/settings.md
	let preferredUnit = $state<'km' | 'mi'>('km');
	let paceFormat = $state<'min_per_km' | 'min_per_mi' | 'kph' | 'mph'>('min_per_km');
	let defaultActivity = $state<'run' | 'walk' | 'hike' | 'cycle'>('run');
	let weekStartDay = $state<'monday' | 'sunday'>('monday');
	let mapStyle = $state<'streets' | 'satellite' | 'outdoors' | 'dark'>('streets');
	let privacyDefault = $state<'public' | 'followers' | 'private'>('followers');
	let autoPauseEnabled = $state(true);
	let autoPauseSpeed = $state('0.8');
	let weeklyMileageGoal = $state('');
	let coachPersonality = $state<'supportive' | 'drill_sergeant' | 'analytical'>('supportive');
	let stravaAutoShare = $state(false);
	let voiceFeedbackEnabled = $state(false);
	let voiceFeedbackIntervalKm = $state('1.0');

	// Theme — persisted to localStorage, not the cross-device settings
	// bag. Intentionally per-browser: a dark laptop + a light iPad is a
	// common setup and a bag-scoped preference would fight that.
	let theme = $state<Theme>('auto');

	function changeTheme(next: Theme) {
		theme = next;
		applyTheme(next);
	}

	// When the user picks a distance unit, snap the pace format to the
	// matching min-per-unit choice. Skip if they've explicitly chosen a
	// speed format (kph/mph) — that's a deliberate non-pace selection.
	function pickDistanceUnit(next: 'km' | 'mi') {
		preferredUnit = next;
		if (paceFormat === 'kph' || paceFormat === 'mph') return;
		paceFormat = next === 'mi' ? 'min_per_mi' : 'min_per_km';
	}

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

	// Privacy zones — geofences clipped from public track renders.
	let privacyZones = $state<PrivacyZone[]>([]);
	let showZonePicker = $state(false);

	onMount(async () => {
		// Theme is local-only so it's available even before the bag loads.
		theme = loadTheme();

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
			paceFormat = effective(settings, 'units_pace_format', 'min_per_km') ?? 'min_per_km';
			defaultActivity = effective(settings, 'default_activity_type', 'run') ?? 'run';
			weekStartDay = effective(settings, 'week_start_day', 'monday') ?? 'monday';
			mapStyle = effective(settings, 'map_style', 'streets') ?? 'streets';
			setMapStyle(mapStyle);
			privacyDefault = effective(settings, 'privacy_default', 'followers') ?? 'followers';
			autoPauseEnabled = effective(settings, 'auto_pause_enabled', true) ?? true;
			autoPauseSpeed = (effective<number>(settings, 'auto_pause_speed_mps', 0.8) ?? 0.8).toString();
			weeklyMileageGoal = (effective<number>(settings, 'weekly_mileage_goal_m') ?? '')?.toString() ?? '';
			coachPersonality = effective(settings, 'coach_personality', 'supportive') ?? 'supportive';
			stravaAutoShare = effective(settings, 'strava_auto_share', false) ?? false;
			voiceFeedbackEnabled = effective(settings, 'voice_feedback_enabled', false) ?? false;
			voiceFeedbackIntervalKm = (
				effective<number>(settings, 'voice_feedback_interval_km', 1.0) ?? 1.0
			).toString();

			const zones = effective<Record<string, number>>(settings, 'hr_zones');
			if (zones) {
				z1 = zones.z1?.toString() ?? '';
				z2 = zones.z2?.toString() ?? '';
				z3 = zones.z3?.toString() ?? '';
				z4 = zones.z4?.toString() ?? '';
				z5 = zones.z5?.toString() ?? '';
			}

			privacyZones = effective<PrivacyZone[]>(settings, PRIVACY_ZONES_KEY) ?? [];

			const { data: prof } = await supabase
				.from('user_profiles')
				.select('gender, date_of_birth, health_data_consent_at')
				.eq('id', auth.user.id)
				.maybeSingle();
			if (prof) {
				gender = (prof.gender as typeof gender) ?? '';
				dateOfBirth = prof.date_of_birth ?? '';
				healthDataConsentAt = (prof.health_data_consent_at as string | null) ?? null;
				// Default the checkbox to the persisted state. If the row
				// already carries a consent timestamp the user has
				// previously ticked the box — keep it ticked so they
				// can edit without re-consenting.
				healthDataConsent = healthDataConsentAt != null;
			}
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

	async function handleSave() {
		if (!auth.user) return;
		saving = true; saved = false;
		const changes: Record<string, unknown> = {
			preferred_unit: preferredUnit,
			units_pace_format: paceFormat,
			default_activity_type: defaultActivity,
			week_start_day: weekStartDay,
			map_style: mapStyle,
			privacy_default: privacyDefault,
			auto_pause_enabled: autoPauseEnabled,
			auto_pause_speed_mps: parseFloat(autoPauseSpeed) || 0.8,
			coach_personality: coachPersonality,
			strava_auto_share: stravaAutoShare,
			voice_feedback_enabled: voiceFeedbackEnabled,
			voice_feedback_interval_km: parseFloat(voiceFeedbackIntervalKm) || 1.0,
		};
		if (weeklyMileageGoal) {
			changes.weekly_mileage_goal_m = parseInt(weeklyMileageGoal, 10) || null;
		} else {
			changes.weekly_mileage_goal_m = null;
		}

		if (z1 || z2 || z3 || z4 || z5) {
			changes.hr_zones = {
				z1: parseInt(z1, 10) || 0,
				z2: parseInt(z2, 10) || 0,
				z3: parseInt(z3, 10) || 0,
				z4: parseInt(z4, 10) || 0,
				z5: parseInt(z5, 10) || 0,
			};
		} else {
			changes.hr_zones = null;
		}

		// Also dual-write preferred_unit to profile column for legacy readers.
		// Demographics live here too — RPCs that tier leaderboards by gender
		// and age band read from user_profiles directly. GDPR Art 9 explicit
		// consent gates whether gender + DOB persist at all; without it the
		// only legal action is to null them out.
		const hasDemographic = !!(gender || dateOfBirth);
		if (hasDemographic && !healthDataConsent) {
			// Fail the save loudly so the user sees the consent checkbox
			// requirement rather than us silently dropping their input.
			showToast(
				'To save gender or date of birth, tick the consent ' +
					'checkbox under Demographics.',
				'error',
			);
			return;
		}
		const consentNowIso = new Date().toISOString();
		const profileUpdate: Record<string, unknown> = {
			preferred_unit: preferredUnit,
			gender: (healthDataConsent && gender) ? gender : null,
			date_of_birth: (healthDataConsent && dateOfBirth) ? dateOfBirth : null,
		};
		if (healthDataConsent) {
			// Stamp consent timestamp on the first acceptance so the row
			// records the moment of the affirmative act. Idempotent on
			// subsequent saves — we only set it when it's still null.
			if (healthDataConsentAt == null) {
				profileUpdate.health_data_consent_at = consentNowIso;
				healthDataConsentAt = consentNowIso;
			}
		} else {
			// Withdrawal — null all three fields atomically per Art 7(3).
			profileUpdate.health_data_consent_at = null;
			healthDataConsentAt = null;
		}
		await supabase.from('user_profiles').update(profileUpdate).eq('id', auth.user.id);

		try {
			await updateUniversal(auth.user.id, changes);
			// Propagate to the app-wide unit signal so every view re-renders
			// with the new label without a full reload.
			setUnit(preferredUnit);
			setMapStyle(mapStyle);
			saved = true;
			showToast('Preferences saved.', 'success');
			setTimeout(() => (saved = false), 2000);
		} catch (e) {
			showToast(`Save failed: ${(e as Error).message}`, 'error');
		} finally {
			saving = false;
		}
	}
</script>

<div class="page">
	<header class="page-head">
		<p class="kicker">Settings</p>
		<h1>Preferences</h1>
		<p class="tagline">
			Units, defaults, privacy, and the knobs that shape how every run is recorded
			and shown. These sync across every device you sign into.
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
		<p class="sr-only" role="status">Loading preferences…</p>
	{:else}
		<!-- Units -->
		<section class="card">
			<h2>Units & Display</h2>
			<div class="form-grid">
				<div class="field">
					<span class="label-text">Distance Unit</span>
					<div class="toggle-row" role="group" aria-label="Distance Unit">
						<button class="toggle-btn" class:active={preferredUnit === 'km'} onclick={() => pickDistanceUnit('km')} type="button">Kilometres</button>
						<button class="toggle-btn" class:active={preferredUnit === 'mi'} onclick={() => pickDistanceUnit('mi')} type="button">Miles</button>
					</div>
				</div>
				<label>
					<span class="label-text">Pace Format</span>
					<select bind:value={paceFormat}>
						<option value="min_per_km">min/km</option>
						<option value="min_per_mi">min/mi</option>
						<option value="kph">km/h</option>
						<option value="mph">mph</option>
					</select>
				</label>
				<label>
					<span class="label-text">Map Style</span>
					<select bind:value={mapStyle}>
						<option value="streets">Streets</option>
						<option value="satellite">Satellite</option>
						<option value="outdoors">Outdoors</option>
						<option value="dark">Dark</option>
					</select>
				</label>
				<label>
					<span class="label-text">Week Starts On</span>
					<select bind:value={weekStartDay}>
						<option value="monday">Monday</option>
						<option value="sunday">Sunday</option>
					</select>
				</label>
				<div class="field">
					<span class="label-text">Theme</span>
					<div class="toggle-row" role="group" aria-label="Theme">
						<button
							class="toggle-btn"
							class:active={theme === 'auto'}
							onclick={() => changeTheme('auto')}
							type="button"
						>Auto</button>
						<button
							class="toggle-btn"
							class:active={theme === 'light'}
							onclick={() => changeTheme('light')}
							type="button"
						>Light</button>
						<button
							class="toggle-btn"
							class:active={theme === 'dark'}
							onclick={() => changeTheme('dark')}
							type="button"
						>Dark</button>
					</div>
				</div>
			</div>
		</section>

		<!-- Activity & Recording -->
		<section class="card">
			<h2>Activity & Recording</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">Default Activity</span>
					<select bind:value={defaultActivity}>
						<option value="run">Run</option>
						<option value="walk">Walk</option>
						<option value="hike">Hike</option>
						<option value="cycle">Cycle</option>
					</select>
				</label>
				<label class="checkbox-label">
					<input type="checkbox" bind:checked={autoPauseEnabled} />
					<span>Auto-pause when stationary</span>
				</label>
				{#if autoPauseEnabled}
					<label>
						<span class="label-text">Auto-pause speed (m/s)</span>
						<input type="number" bind:value={autoPauseSpeed} step="0.1" min="0.1" max="3" />
					</label>
				{/if}
				<label class="checkbox-label">
					<input type="checkbox" bind:checked={voiceFeedbackEnabled} />
					<span>Spoken split announcements (mobile + watch)</span>
				</label>
				{#if voiceFeedbackEnabled}
					<label>
						<span class="label-text">Split interval (km)</span>
						<input
							type="number"
							bind:value={voiceFeedbackIntervalKm}
							step="0.5"
							min="0.5"
							max="10"
						/>
					</label>
				{/if}
				<label id="weekly-mileage-goal">
					<span class="label-text">Weekly Mileage Goal (m)</span>
					<input type="number" bind:value={weeklyMileageGoal} placeholder="e.g. 40000 (40 km)" />
				</label>
			</div>
		</section>

		<!-- Heart Rate Zones -->
		<section class="card" id="heart-rate-zones">
			<h2>Heart Rate Zones</h2>
			<p class="section-desc">Upper bound in bpm for each zone. Leave blank if you don't know.</p>
			<div class="form-grid zones">
				<label><span class="label-text">Z1 (recovery)</span><input type="number" bind:value={z1} placeholder="130" /></label>
				<label><span class="label-text">Z2 (easy)</span><input type="number" bind:value={z2} placeholder="145" /></label>
				<label><span class="label-text">Z3 (tempo)</span><input type="number" bind:value={z3} placeholder="160" /></label>
				<label><span class="label-text">Z4 (threshold)</span><input type="number" bind:value={z4} placeholder="175" /></label>
				<label><span class="label-text">Z5 (max)</span><input type="number" bind:value={z5} placeholder="195" /></label>
			</div>
		</section>

		<!-- Privacy & Sharing -->
		<section class="card">
			<h2>Privacy & Sharing</h2>
			<div class="form-stack">
				<label class="field">
					<span class="label-text">Default Visibility for New Runs</span>
					<select bind:value={privacyDefault}>
						<option value="public">Public</option>
						<option value="followers">Followers only</option>
						<option value="private">Private</option>
					</select>
				</label>
				<label class="checkbox-row">
					<input type="checkbox" bind:checked={stravaAutoShare} />
					<span>Auto-push runs to Strava</span>
				</label>
			</div>
		</section>

		<!-- Demographics — gender + DOB power tiered segment leaderboards.
		     Combined they are special-category data under GDPR Art 9 so the
		     explicit-consent checkbox is the precondition for saving either. -->
		<section class="card">
			<h2>Demographics</h2>
			<p class="section-desc">
				Optional. Lets segment leaderboards filter by gender and 5-year age band — the same buckets
				Strava uses. Leave blank to stay out of those filtered views.
			</p>
			<p class="section-desc consent-notice">
				These fields are health-adjacent personal data under GDPR Art 9. We process
				them only with your explicit consent and only to power the
				gender + age-band views you see on segment leaderboards. See our
				<a href="/privacy">privacy policy</a> for the full purposes,
				retention, and your withdrawal rights.
			</p>
			<label class="consent-checkbox">
				<input type="checkbox" bind:checked={healthDataConsent} />
				<span>
					I consent to Threkir storing my gender and date of birth for the
					segment-leaderboard tiering described above (GDPR Art 9(2)(a)).
				</span>
			</label>
			<div class="form-grid">
				<label>
					<span class="label-text">Gender</span>
					<select bind:value={gender} disabled={!healthDataConsent}>
						<option value="">Prefer not to say</option>
						<option value="male">Male</option>
						<option value="female">Female</option>
						<option value="nonbinary">Nonbinary</option>
					</select>
				</label>
				<label>
					<span class="label-text">Date of birth</span>
					<input type="date" bind:value={dateOfBirth} disabled={!healthDataConsent} />
				</label>
			</div>
			{#if healthDataConsentAt}
				<p class="section-hint">
					Consent recorded on {new Date(healthDataConsentAt).toLocaleDateString()}.
					Unticking the checkbox above and saving will withdraw consent and
					clear both fields per Art 7(3).
				</p>
			{/if}
		</section>

		<!-- Privacy zones — clipped from the start and end of public tracks. -->
		<section class="card">
			<h2>Privacy zones</h2>
			<p class="section-hint">
				Hide a radius around home, work, or anywhere else from public run + route shares. The
				start and end of any track that falls inside a zone is clipped before the public sees
				it. Owner views always show the full track.
			</p>

			{#if privacyZones.length === 0}
				<div class="inline-empty">
					<span class="material-symbols" aria-hidden="true">my_location</span>
					<p>No privacy zones yet. Add one around your home or workplace to hide it from public shares.</p>
				</div>
			{:else}
				<ul class="zone-list">
					{#each privacyZones as zone, idx (idx)}
						<li class="zone-row">
							<div>
								<div class="zone-coords">
									{zone.lat.toFixed(5)}, {zone.lng.toFixed(5)}
								</div>
								<div class="zone-radius">{zone.radius_m} m radius</div>
							</div>
							<button class="btn btn-outline btn-sm" type="button" onclick={() => removeZone(idx)}>
								Remove
							</button>
						</li>
					{/each}
				</ul>
			{/if}

			<div>
				<button class="btn btn-primary" type="button" onclick={() => (showZonePicker = true)}>
					<span class="material-symbols">add</span>
					Add a zone
				</button>
			</div>
		</section>

		<!-- Telemetry consent (Sentry). Mirrors the cookie banner's
		     accept/reject choice so a returning user can withdraw their
		     earlier acceptance per GDPR Art 7(3) / Art 21. The hook in
		     hooks.server.ts + hooks.client.ts gates Sentry on this
		     state. See audit/gdpr (2026-05-25) High. -->
		<section class="card">
			<h2>Privacy & telemetry</h2>
			<p class="section-desc">
				When enabled, anonymised error reports (URL paths, stack
				traces, breadcrumbs without auth tokens) are sent to Sentry —
				a US-hosted sub-processor — so we can spot crashes and
				regressions. Disable to stop sending. Your withdrawal
				takes effect immediately on the next page load.
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
				<span>Send anonymised error reports to Sentry.</span>
			</label>
			{#if consent.timestamp}
				<p class="section-hint">
					Choice recorded on {new Date(consent.timestamp).toLocaleDateString()}.
				</p>
			{/if}
		</section>

		<!-- AI Coach -->
		<section class="card">
			<h2>AI Coach</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">Coach Personality</span>
					<select bind:value={coachPersonality}>
						<option value="supportive">Supportive</option>
						<option value="drill_sergeant">Drill Sergeant</option>
						<option value="analytical">Analytical</option>
					</select>
				</label>
			</div>
		</section>

		<button class="btn btn-primary btn-save" onclick={handleSave} disabled={saving}>
			{saving ? 'Saving...' : saved ? 'Saved!' : 'Save Preferences'}
		</button>
	{/if}
</div>

<Modal
	open={showZonePicker}
	title="Add a privacy zone"
	onclose={() => (showZonePicker = false)}
	wide
>
	<PrivacyZonePicker oncreated={addZone} oncancel={() => (showZonePicker = false)} />
</Modal>

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
	.checkbox-row { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; }
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
	.consent-notice { background: var(--color-bg-tertiary); border-left: 3px solid var(--color-primary); padding: var(--space-sm) var(--space-md); border-radius: var(--radius-sm); margin-top: var(--space-md); }
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
