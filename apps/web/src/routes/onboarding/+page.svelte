<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import { showToast } from '$lib/stores/toast.svelte';
	import { updateUniversal } from '$lib/settings';
	import { setUnit } from '$lib/units.svelte';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		getCurrentSubscription,
	} from '$lib/push';
	import {
		ONBOARDING_TOTAL_STEPS,
		PRIMARY_GOAL_KEY,
		PRIMARY_GOAL_LABELS,
		PRIMARY_GOAL_VALUES,
		type PrimaryGoal,
	} from '$lib/onboarding';

	/// Step state. Bounded 1..ONBOARDING_TOTAL_STEPS. Persona-hunt
	/// new-runner finding-area #1: a Garmin-style step-by-step is
	/// lower cognitive load than a single long form, especially for
	/// the new-runner persona who's overwhelmed by choice.
	let step = $state(1);

	// ── Step 1: display name ──────────────────────────────────
	let displayName = $state('');

	// ── Step 2: units ─────────────────────────────────────────
	let preferredUnit = $state<'km' | 'mi'>('km');

	// ── Step 3: primary goal ──────────────────────────────────
	let primaryGoal = $state<PrimaryGoal | null>(null);

	// ── Step 4: about you (gender + DOB + weight + Art 9 consent) ──
	// Identical shape to /settings/preferences so the same fields
	// land in the same columns. Consent gates persistence — if the
	// user doesn't tick the checkbox, gender + DOB are silently
	// dropped at save time. Weight isn't Art 9 (it's not health
	// data on its own), so it persists regardless.
	let gender = $state<'male' | 'female' | 'nonbinary' | ''>('');
	let dateOfBirth = $state('');
	let bodyWeightKg = $state('');
	let healthDataConsent = $state(false);

	// ── Step 5: privacy default ───────────────────────────────
	let privacyDefault = $state<'public' | 'followers' | 'private'>('followers');

	// ── Step 6: notifications ─────────────────────────────────
	const pushSupported = isPushSupported();
	let pushSubscribed = $state(false);
	let pushBusy = $state(false);

	let saving = $state(false);

	onMount(async () => {
		// Pre-fill display name from the auth row if the OAuth provider
		// returned one — the user can edit before continuing.
		if (auth.user?.display_name) displayName = auth.user.display_name;
		// Same for the unit prefiller — `auth.user.preferred_unit`
		// defaults to 'km' if never set.
		if (auth.user?.preferred_unit) preferredUnit = auth.user.preferred_unit;
		if (pushSupported) {
			pushSubscribed = !!(await getCurrentSubscription());
		}
	});

	function next() {
		if (step < ONBOARDING_TOTAL_STEPS) step += 1;
	}

	function back() {
		if (step > 1) step -= 1;
	}

	function skipStep() {
		// Per-step skip — keeps the wizard moving without forcing the
		// user to commit. The unset field falls back to its default
		// at save time, and the Settings nudge surfaces it later.
		next();
	}

	async function handleEnablePush() {
		if (!pushSupported || pushBusy) return;
		pushBusy = true;
		try {
			await subscribeToPush();
			pushSubscribed = true;
		} catch (e) {
			showToast(`Could not enable notifications: ${(e as Error).message}`, 'error');
		} finally {
			pushBusy = false;
		}
	}

	/// Persist every collected value + stamp `onboarded_at = now()`
	/// so the user is never re-onboarded. Called on either the
	/// Finish button (final step) or the "Skip onboarding" header
	/// link — same wire either way.
	async function finishAndExit() {
		if (!auth.user || saving) return;
		saving = true;
		try {
			// 1. Universal prefs bag (units + goal + weight + privacy).
			const bagChanges: Record<string, unknown> = {
				preferred_unit: preferredUnit,
				privacy_default: privacyDefault,
			};
			if (primaryGoal) bagChanges[PRIMARY_GOAL_KEY] = primaryGoal;
			if (bodyWeightKg) {
				const w = parseFloat(bodyWeightKg);
				if (Number.isFinite(w) && w > 0) bagChanges.body_weight_kg = w;
			}
			// DOB persists in the prefs bag too — same dual-storage
			// pattern as Settings → Preferences. Gender + DOB on the
			// user_profiles row need the explicit Art 9 consent.
			if (healthDataConsent && dateOfBirth) {
				bagChanges.date_of_birth = dateOfBirth;
			}
			await updateUniversal(auth.user.id, bagChanges);

			// 2. user_profiles columns: display_name, preferred_unit
			// (dual-write for the cross-user readable surfaces),
			// gender + DOB + health_data_consent_at (Art 9 gated),
			// onboarded_at.
			const profileUpdate: Record<string, unknown> = {
				preferred_unit: preferredUnit,
				onboarded_at: new Date().toISOString(),
			};
			if (displayName.trim()) profileUpdate.display_name = displayName.trim();
			if (healthDataConsent) {
				profileUpdate.gender = gender || null;
				profileUpdate.date_of_birth = dateOfBirth || null;
				profileUpdate.health_data_consent_at = new Date().toISOString();
			}
			const { error } = await supabase
				.from('user_profiles')
				.update(profileUpdate)
				.eq('id', auth.user.id);
			if (error) throw error;

			// 3. Refresh the auth store so the layout-level gate sees
			// `onboarded_at` populated + doesn't re-route us back.
			await auth.fetchUser();
			setUnit(preferredUnit);

			showToast('All set! Welcome aboard.', 'success');
			goto('/dashboard');
		} catch (e) {
			showToast(`Could not save: ${(e as Error).message}`, 'error');
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head>
	<title>Welcome — Threkir</title>
</svelte:head>

<div class="onboarding-shell">
	<header class="head">
		<div class="brand">Threkir</div>
		<button type="button" class="skip-all" onclick={finishAndExit} disabled={saving}>
			Skip onboarding
		</button>
	</header>

	<div class="progress" role="progressbar" aria-valuemin="1" aria-valuemax={ONBOARDING_TOTAL_STEPS} aria-valuenow={step}>
		{#each Array(ONBOARDING_TOTAL_STEPS) as _, i (i)}
			<span class="dot" class:active={i + 1 === step} class:done={i + 1 < step}></span>
		{/each}
	</div>

	<main class="card">
		{#if step === 1}
			<section aria-labelledby="step-1-title">
				<h1 id="step-1-title">What should we call you?</h1>
				<p class="hint">
					Your display name shows up on the runs + comments you share. You can change it any time in Settings.
				</p>
				<label class="field">
					<span class="label-text">Display name</span>
					<input
						type="text"
						bind:value={displayName}
						maxlength="60"
						placeholder="e.g. Alex Chen"
					/>
				</label>
			</section>
		{:else if step === 2}
			<section aria-labelledby="step-2-title">
				<h1 id="step-2-title">Kilometres or miles?</h1>
				<p class="hint">
					Drives every distance + pace label in the app. You can switch any time in Settings → Preferences.
				</p>
				<div class="unit-toggle" role="radiogroup">
					<button
						type="button"
						class="unit-option"
						class:selected={preferredUnit === 'km'}
						role="radio"
						aria-checked={preferredUnit === 'km'}
						onclick={() => (preferredUnit = 'km')}
					>
						<span class="unit-name">Kilometres</span>
						<span class="unit-sample">5.00 km · 5:30 /km</span>
					</button>
					<button
						type="button"
						class="unit-option"
						class:selected={preferredUnit === 'mi'}
						role="radio"
						aria-checked={preferredUnit === 'mi'}
						onclick={() => (preferredUnit = 'mi')}
					>
						<span class="unit-name">Miles</span>
						<span class="unit-sample">3.11 mi · 8:51 /mi</span>
					</button>
				</div>
			</section>
		{:else if step === 3}
			<section aria-labelledby="step-3-title">
				<h1 id="step-3-title">What's your main goal?</h1>
				<p class="hint">
					Helps us suggest the right kind of training plan later. Not a commitment — change it any time.
				</p>
				<div class="goal-grid" role="radiogroup">
					{#each PRIMARY_GOAL_VALUES as v}
						<button
							type="button"
							class="goal-option"
							class:selected={primaryGoal === v}
							role="radio"
							aria-checked={primaryGoal === v}
							onclick={() => (primaryGoal = v)}
						>
							{PRIMARY_GOAL_LABELS[v]}
						</button>
					{/each}
				</div>
			</section>
		{:else if step === 4}
			<section aria-labelledby="step-4-title">
				<h1 id="step-4-title">A bit about you</h1>
				<p class="hint">
					Helps us calibrate pace targets, heart-rate zones, and calorie estimates. Every field is optional + you can change them in Settings.
				</p>
				<label class="field">
					<span class="label-text">Gender (optional)</span>
					<select bind:value={gender}>
						<option value="">Prefer not to say</option>
						<option value="female">Female</option>
						<option value="male">Male</option>
						<option value="nonbinary">Non-binary</option>
					</select>
				</label>
				<label class="field">
					<span class="label-text">Date of birth (optional)</span>
					<input type="date" bind:value={dateOfBirth} max={new Date().toISOString().slice(0, 10)} />
				</label>
				<label class="field">
					<span class="label-text">Body weight (optional, kg)</span>
					<input type="number" inputmode="decimal" min="20" max="250" step="0.1" bind:value={bodyWeightKg} placeholder="e.g. 70" />
				</label>
				{#if gender || dateOfBirth}
					<label class="consent-row">
						<input type="checkbox" bind:checked={healthDataConsent} />
						<span>
							I consent to Threkir storing my gender and date of birth to power the gender + age-band segment leaderboards and the calibrated pace + calorie estimates (GDPR Art 9(2)(a)). I can withdraw consent in Settings any time.
						</span>
					</label>
				{/if}
			</section>
		{:else if step === 5}
			<section aria-labelledby="step-5-title">
				<h1 id="step-5-title">Who can see your runs?</h1>
				<p class="hint">
					Sets the default for every new run. You can override per-run before sharing, or change the default in Settings.
				</p>
				<div class="privacy-list" role="radiogroup">
					<button
						type="button"
						class="privacy-option"
						class:selected={privacyDefault === 'private'}
						role="radio"
						aria-checked={privacyDefault === 'private'}
						onclick={() => (privacyDefault = 'private')}
					>
						<strong>Private</strong>
						<span>Only you. Nothing in any feed, share page, or leaderboard.</span>
					</button>
					<button
						type="button"
						class="privacy-option"
						class:selected={privacyDefault === 'followers'}
						role="radio"
						aria-checked={privacyDefault === 'followers'}
						onclick={() => (privacyDefault = 'followers')}
					>
						<strong>Followers</strong>
						<span>People who follow you see new runs in their feed. Share links still work for anyone.</span>
					</button>
					<button
						type="button"
						class="privacy-option"
						class:selected={privacyDefault === 'public'}
						role="radio"
						aria-checked={privacyDefault === 'public'}
						onclick={() => (privacyDefault = 'public')}
					>
						<strong>Public</strong>
						<span>Anyone with the link can see. Eligible for segment leaderboards.</span>
					</button>
				</div>
			</section>
		{:else if step === 6}
			<section aria-labelledby="step-6-title">
				<h1 id="step-6-title">Notifications</h1>
				<p class="hint">
					Push lets you know when someone gives kudos, comments, or follows. Per-device — each browser / phone toggles independently.
				</p>
				{#if !pushSupported}
					<p class="not-available">
						This browser doesn't support web push, or this build wasn't deployed with a notification key. You can enable later from Settings if your browser supports it.
					</p>
				{:else if pushPermission() === 'denied'}
					<p class="not-available">
						Notifications are blocked at the browser level. Re-enable them in your browser's site settings, then come back + toggle on from Settings.
					</p>
				{:else if pushSubscribed}
					<p class="success-text">Notifications enabled on this device. You're all set.</p>
				{:else}
					<button
						type="button"
						class="btn btn-primary"
						onclick={handleEnablePush}
						disabled={pushBusy}
					>
						<span class="material-symbols">notifications_active</span>
						{pushBusy ? 'Enabling…' : 'Enable notifications'}
					</button>
				{/if}
			</section>
		{:else if step === 7}
			<section aria-labelledby="step-7-title">
				<h1 id="step-7-title">All set!</h1>
				<p class="hint">
					Your account is ready. Open the dashboard to record your first run, or browse the app — everything you just answered is editable in Settings.
				</p>
			</section>
		{/if}

		<div class="nav-row">
			{#if step > 1}
				<button type="button" class="btn btn-outline" onclick={back} disabled={saving}>
					Back
				</button>
			{:else}
				<span></span>
			{/if}
			<div class="nav-right">
				{#if step !== 7 && step !== 1 && step !== 5 && step !== 2}
					<button type="button" class="skip-step" onclick={skipStep} disabled={saving}>
						Skip
					</button>
				{/if}
				{#if step < ONBOARDING_TOTAL_STEPS}
					<button type="button" class="btn btn-primary" onclick={next} disabled={saving}>
						Continue
					</button>
				{:else}
					<button type="button" class="btn btn-primary" onclick={finishAndExit} disabled={saving}>
						{saving ? 'Saving…' : 'Open dashboard'}
					</button>
				{/if}
			</div>
		</div>
	</main>
</div>

<style>
	.onboarding-shell {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		background: var(--color-bg);
		padding: var(--space-lg);
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-xl);
	}
	.brand {
		font-size: 1.1rem;
		font-weight: 700;
		color: var(--color-primary);
	}
	.skip-all {
		background: none;
		border: none;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
		text-decoration: underline;
	}
	.skip-all:hover { color: var(--color-text); }
	.skip-all:disabled { opacity: 0.5; cursor: not-allowed; }

	.progress {
		display: flex;
		gap: 0.5rem;
		justify-content: center;
		margin-bottom: var(--space-xl);
	}
	.dot {
		width: 0.55rem;
		height: 0.55rem;
		border-radius: 50%;
		background: var(--color-bg-tertiary);
		transition: background var(--transition-fast);
	}
	.dot.done { background: color-mix(in srgb, var(--color-primary) 50%, transparent); }
	.dot.active { background: var(--color-primary); transform: scale(1.2); }

	.card {
		max-width: 36rem;
		width: 100%;
		margin: 0 auto;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-2xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	h1 {
		font-size: 1.5rem;
		font-weight: 700;
		margin: 0 0 var(--space-xs);
	}
	.hint {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		margin: 0 0 var(--space-lg);
	}
	section { display: flex; flex-direction: column; gap: var(--space-md); }

	.field { display: flex; flex-direction: column; gap: 0.35rem; }
	.label-text { font-size: 0.85rem; color: var(--color-text-secondary); font-weight: 500; }
	.field input, .field select {
		padding: 0.6rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
		font-size: 1rem;
	}
	.field input:focus, .field select:focus {
		outline: none;
		border-color: var(--color-primary);
	}
	/* Keyboard-only focus retains a visible indicator per
	   WCAG 2.4.7 (Focus Visible) + 2.4.11 (Focus Appearance).
	   Pointer / touch focus loses the ring (handled by the :focus
	   rule above) so the form looks clean during mouse use. The
	   security_guards.test.ts accessibility guard pins that every
	   `:focus { outline:none }` selector has a matching
	   `:focus-visible` companion. */
	.field input:focus-visible, .field select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.unit-toggle, .privacy-list { display: flex; flex-direction: column; gap: var(--space-sm); }
	@media (min-width: 32rem) {
		.unit-toggle { flex-direction: row; }
		.unit-option { flex: 1; }
	}
	.unit-option, .privacy-option, .goal-option {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		padding: var(--space-md);
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		text-align: left;
		color: var(--color-text);
		font-size: 0.95rem;
		cursor: pointer;
		transition: border-color var(--transition-fast), background var(--transition-fast);
	}
	.unit-option:hover, .privacy-option:hover, .goal-option:hover {
		border-color: var(--color-primary);
	}
	.unit-option.selected, .privacy-option.selected, .goal-option.selected {
		border-color: var(--color-primary);
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
	}
	.unit-name { font-weight: 600; }
	.unit-sample { font-size: 0.8rem; color: var(--color-text-secondary); font-variant-numeric: tabular-nums; }

	.goal-grid {
		display: grid;
		grid-template-columns: 1fr;
		gap: var(--space-sm);
	}
	@media (min-width: 32rem) {
		.goal-grid { grid-template-columns: 1fr 1fr; }
	}
	.goal-option { padding: 0.85rem var(--space-md); font-weight: 500; }

	.privacy-option strong { font-size: 0.95rem; font-weight: 600; }
	.privacy-option span { font-size: 0.82rem; color: var(--color-text-secondary); line-height: 1.45; }

	.consent-row {
		display: flex;
		gap: 0.55rem;
		align-items: flex-start;
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.consent-row input { margin-top: 0.2rem; flex-shrink: 0; }

	.not-available {
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		padding: var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		margin: 0;
	}
	.success-text {
		font-size: 0.92rem;
		color: var(--color-success, #1a7f37);
		margin: 0;
	}

	.nav-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		margin-top: var(--space-md);
	}
	.nav-right {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.skip-step {
		background: none;
		border: none;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		cursor: pointer;
		padding: 0.5rem 0.5rem;
	}
	.skip-step:hover { color: var(--color-text); }
	.skip-step:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
