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

	onMount(async () => {
		// Theme is local-only so it's available even before the bag loads.
		theme = loadTheme();

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
		} catch (e) {
			console.warn('Settings load failed', e);
		}
		loading = false;
	});

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
		await supabase.from('user_profiles').update({
			preferred_unit: preferredUnit,
		}).eq('id', auth.user.id);

		await updateUniversal(auth.user.id, changes);
		// Propagate to the app-wide unit signal so every view re-renders
		// with the new label without a full reload.
		setUnit(preferredUnit);
		setMapStyle(mapStyle);
		saving = false; saved = true;
		setTimeout(() => (saved = false), 2000);
	}
</script>

<div class="page">
	<p class="subtitle">Settings sync to every device you sign into.</p>

	{#if loading}
		<p class="muted">Loading...</p>
	{:else}
		<!-- Units -->
		<section class="card">
			<h2>Units & Display</h2>
			<div class="form-grid">
				<label>
					<span class="label-text">Distance Unit</span>
					<div class="toggle-row">
						<button class="toggle-btn" class:active={preferredUnit === 'km'} onclick={() => pickDistanceUnit('km')}>Kilometres</button>
						<button class="toggle-btn" class:active={preferredUnit === 'mi'} onclick={() => pickDistanceUnit('mi')}>Miles</button>
					</div>
				</label>
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
				<label>
					<span class="label-text">Theme</span>
					<div class="toggle-row">
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
				</label>
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
				<label>
					<span class="label-text">Weekly Mileage Goal (m)</span>
					<input type="number" bind:value={weeklyMileageGoal} placeholder="e.g. 40000 (40 km)" />
				</label>
			</div>
		</section>

		<!-- Heart Rate Zones -->
		<section class="card">
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

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 64rem; }
	.page-header { margin-bottom: var(--space-xl); }
	h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: var(--space-xs); }
	.subtitle { font-size: 0.88rem; color: var(--color-text-secondary); margin-bottom: var(--space-lg); }
	h2 { font-size: 0.9rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: var(--space-lg); }
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
	.toggle-row { display: flex; gap: var(--space-sm); }
	.toggle-btn { flex: 1; padding: var(--space-sm) var(--space-md); border: 1.5px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg); font-size: 0.85rem; font-weight: 500; color: var(--color-text-secondary); cursor: pointer; transition: all var(--transition-fast); }
	.toggle-btn:hover { border-color: var(--color-primary); }
	.toggle-btn.active { background: var(--color-primary-light); border-color: var(--color-primary); color: var(--color-primary); }
	.checkbox-label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; padding-top: 1.2rem; }
	.section-desc { font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: var(--space-md); line-height: 1.5; }
	.btn-save { width: auto; }
	.muted { color: var(--color-text-tertiary); }
</style>
