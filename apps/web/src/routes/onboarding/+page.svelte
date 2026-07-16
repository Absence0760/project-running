<script lang="ts">
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';
	import { m } from '$lib/i18n/store.svelte';
	import { defaultUnitForLocale } from '$lib/format/locale_defaults';
	import { parseWeightToKg, roundWeight, type WeightUnit } from '$lib/format/weight';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { showToast } from '$lib/stores/toast.svelte';
	import { updateUniversal } from '$lib/settings/settings';
	import {
		isPushSupported,
		pushPermission,
		subscribeToPush,
		getCurrentSubscription,
	} from '$lib/util/push';
	import {
		ONBOARDING_TOTAL_STEPS,
		PRIMARY_GOAL_KEY,
		PRIMARY_GOAL_VALUES,
		type PrimaryGoal,
	} from '$lib/settings/onboarding';

	/// Step state. Bounded 1..ONBOARDING_TOTAL_STEPS. Persona-hunt
	/// new-runner finding-area #1: a Garmin-style step-by-step is
	/// lower cognitive load than a single long form, especially for
	/// the new-runner persona who's overwhelmed by choice.
	let step = $state(1);

	// ── Step 1: display name ──────────────────────────────────
	let displayName = $state('');

	// ── Step 2: units ─────────────────────────────────────────
	// Seed from the visitor's locale (mi for US/GB/LR/MM, km otherwise)
	// instead of hard-coding km — the user can still flip it on this step.
	// audit-findings 2026-05-30 Medium [regional].
	let preferredUnit = $state<'km' | 'mi'>(
		browser ? defaultUnitForLocale(navigator.language) : 'km',
	);

	// ── Step 3: primary goal ──────────────────────────────────
	let primaryGoal = $state<PrimaryGoal | null>(null);

	// ── Step 4: about you (gender + DOB + weight + Art 9 consent) ──
	// Identical shape to /settings/preferences so the same fields
	// land in the same columns. Consent gates the health-data *use* —
	// gender, the prefs-bag mirror, and the consent timestamp are only
	// written when the box is ticked. The bare `date_of_birth` column,
	// however, writes unconditionally: it backs the under-18
	// minor-exclusion in people-search (a child-safety purpose, distinct
	// from consenting to use DOB for HR/leaderboards), so a declined
	// consent must not leave a NULL DOB that keeps the account
	// discoverable. Weight isn't Art 9, so it persists regardless.
	let gender = $state<'male' | 'female' | 'nonbinary' | ''>('');
	let dateOfBirth = $state('');
	// Body weight is entered in the unit implied by the distance choice in
	// step 2: a runner who picked miles (US/GB/LR/MM) thinks of their weight
	// in pounds, so asking for kg there both reads wrong beside an otherwise
	// imperial session and risks a lbs value being silently stored as kg —
	// which then inflates the TDEE / hydration math that consumes
	// body_weight_kg. Storage stays canonical kg; this only changes display +
	// parsing, exactly like preferred_unit for distance.
	let bodyWeight = $state('');
	const weightUnit = $derived<WeightUnit>(preferredUnit === 'mi' ? 'lbs' : 'kg');
	const weightMin = $derived(weightUnit === 'lbs' ? 44 : 20);
	const weightMax = $derived(weightUnit === 'lbs' ? 550 : 250);
	let healthDataConsent = $state(false);

	// ── Step 5: privacy default ───────────────────────────────
	// Defaults to `private` (privacy-by-default) so a new runner isn't
	// silently opted into a follower-visible feed, and so the value the
	// wizard writes to the bag matches the mobile onboarding default —
	// previously this 'followers' default propagated via SettingsSync and
	// overrode a mobile user's private choice. Persona-hunt new #56.
	let privacyDefault = $state<'public' | 'followers' | 'private'>('private');

	// ── Step 6: notifications ─────────────────────────────────
	const pushSupported = isPushSupported();
	let pushSubscribed = $state(false);
	let pushBusy = $state(false);

	let saving = $state(false);

	// Gates the wizard render until onMount has run (auth polled + fields
	// prefilled). The page is prerendered + hydrated, so without this the
	// interactive form paints before hydration attaches handlers — an early
	// click on Continue / Skip is silently dropped and the prefill clobbers
	// a value typed into the gap. Rendering the wizard only once `ready` is
	// true means it exists only client-side, post-hydration, fully wired.
	let ready = $state(false);

	onMount(async () => {
		// `auth.svelte.ts` flips loading=false before the async
		// fetchUser resolves, so a hard reload onto /onboarding can
		// mount with `auth.user` still null. Wait for the gate so the
		// pre-fill below sees the real row.
		await auth.ready();
		// Pre-fill display name from the auth row if the OAuth provider
		// returned one — the user can edit before continuing.
		if (auth.user?.display_name) displayName = auth.user.display_name;
		// Same for the unit prefiller — `auth.user.preferred_unit`
		// defaults to 'km' if never set.
		if (auth.user?.preferred_unit) preferredUnit = auth.user.preferred_unit;
		if (pushSupported) {
			pushSubscribed = !!(await getCurrentSubscription());
		}
		ready = true;
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
			showToast(m('onboarding.pushEnableError', { message: (e as Error).message }), 'error');
		} finally {
			pushBusy = false;
		}
	}

	/// Helper used by both the Skip-onboarding header link and the
	/// final Open-dashboard button. Resolves once `auth.user` has
	/// hydrated from the async `fetchUser` path so the caller can
	/// rely on `auth.user.id`. Returns false when the hydration
	/// never lands — caller bails out.
	async function ensureAuthUser(): Promise<boolean> {
		await auth.ready();
		return auth.user != null;
	}

	/// Row-count-verified profile write with an insert fallback (ADR 248).
	/// `user_profiles` rows are client-provisioned, so a plain update
	/// against a user whose row hasn't materialised yet (OAuth / email-
	/// confirmation timing) matches 0 rows and reports success — the
	/// wizard then navigated to /dashboard, the gate re-read a still-null
	/// `onboarded_at`, and bounced the user back to step 1 with every
	/// answer lost (issue #227). Throws so both callers surface the toast.
	async function stampProfile(profileUpdate: Record<string, unknown>): Promise<void> {
		const { data: updatedRows, error } = await supabase
			.from('user_profiles')
			.update(profileUpdate)
			.eq('id', auth.user!.id)
			.select('id');
		if (error) throw error;
		if (!updatedRows?.length) {
			const { error: insertError } = await supabase
				.from('user_profiles')
				.insert({ id: auth.user!.id, ...profileUpdate });
			if (insertError) throw insertError;
		}
	}

	/// Full page navigation rather than client-side `goto` so the
	/// layout's onboarding-gate $effect can't race the auth-store
	/// refresh — the next page load re-bootstraps auth from the
	/// cookie + the just-written onboarded_at column, so the gate
	/// trivially sees a non-null value and routes through to
	/// /dashboard.
	function navigateToDashboard(): void {
		window.location.href = '/dashboard';
	}

	/// Skip-onboarding header link. Stamps `onboarded_at = now()`
	/// on user_profiles — that's the minimum required for the
	/// layout gate to stop redirecting back here on future loads.
	/// Every other field stays at its existing value (the seed
	/// row's default, or whatever the runner already had); the
	/// Settings page surfaces a "Finish setting up" nudge for fields
	/// they may still want to fill in.
	///
	/// Why a single, narrow write: `event-race-control` style
	/// flakes aside, the previous shape (parallelised
	/// updateUniversal + profile update) was still consistently
	/// timing out under CI load (runs 26583136874 / 26584629824 /
	/// 26588671185 all failed here despite progressive timeout
	/// bumps). A single round-trip lands well inside any reasonable
	/// test budget.
	async function skipOnboarding(): Promise<void> {
		if (saving) return;
		if (!(await ensureAuthUser())) {
			// Never bail silently — a button that does nothing reads as a
			// broken exit and strands the user on the wizard (issue #227).
			showToast(m('onboarding.saveError', { message: m('onboarding.notSignedIn') }), 'error');
			return;
		}
		saving = true;
		try {
			await stampProfile({ onboarded_at: new Date().toISOString() });
			navigateToDashboard();
		} catch (e) {
			showToast(m('onboarding.saveError', { message: (e as Error).message }), 'error');
			saving = false;
		}
		// On success the navigation tears down the page; no need to
		// reset `saving = false` because the next page is a fresh
		// component instance.
	}

	/// Final "Open dashboard" button on Step 7. Persists everything
	/// the runner answered along the way: display name, units, goal,
	/// optional demographics (with GDPR Art 9 consent), privacy
	/// default. Stamps `onboarded_at` so the gate releases.
	async function finishAndExit(dest: string = '/dashboard'): Promise<void> {
		if (saving) return;
		if (!(await ensureAuthUser())) {
			// Same no-silent-bail contract as skipOnboarding (issue #227).
			showToast(m('onboarding.saveError', { message: m('onboarding.notSignedIn') }), 'error');
			return;
		}
		saving = true;
		try {
			// 1. Universal prefs bag (units + goal + weight + privacy).
			const bagChanges: Record<string, unknown> = {
				preferred_unit: preferredUnit,
				weight_unit: weightUnit,
				privacy_default: privacyDefault,
			};
			if (primaryGoal) bagChanges[PRIMARY_GOAL_KEY] = primaryGoal;
			// The typed value is in the display unit (kg or lbs); store canonical
			// kg. parseWeightToKg rejects empty / non-numeric / negative input.
			// `bind:value` on a type=number input coerces bodyWeight to a
			// number (or null when empty); parseWeightToKg takes the raw typed
			// string (it trims + tolerates a comma decimal), so stringify first.
			const weightKg = parseWeightToKg(String(bodyWeight ?? ''), weightUnit);
			if (weightKg != null && weightKg > 0) bagChanges.body_weight_kg = roundWeight(weightKg);
			// DOB mirrors into the prefs bag only under health consent —
			// the bag copy feeds the coach/leaderboard read paths, which
			// are Art 9 surfaces. The minor-exclusion floor reads the
			// user_profiles column written below, not the bag, so the
			// child-safety write doesn't depend on this mirror.
			if (healthDataConsent && dateOfBirth) {
				bagChanges.date_of_birth = dateOfBirth;
			}
			// 2. user_profiles columns: display_name, preferred_unit
			// (dual-write for the cross-user readable surfaces),
			// gender + DOB + health_data_consent_at, onboarded_at.
			const profileUpdate: Record<string, unknown> = {
				preferred_unit: preferredUnit,
				onboarded_at: new Date().toISOString(),
			};
			if (displayName.trim()) profileUpdate.display_name = displayName.trim();
			// DOB writes to user_profiles whenever supplied, NOT only under
			// Art 9 consent (persona round-5 family-club): the under-18
			// minor-exclusion floor in search_user_profiles keys off this
			// column, so consent-gating it left a child who declined the
			// health-data checkbox with a NULL DOB and fully discoverable.
			// Storing a date of birth to enforce a minor-safety
			// discoverability floor is a child-protection purpose distinct
			// from the Art 9(2)(a) explicit consent needed to USE that DOB
			// for health calibration + age-banded leaderboards — which
			// stays gated below via gender + health_data_consent_at.
			if (dateOfBirth) profileUpdate.date_of_birth = dateOfBirth;
			if (healthDataConsent) {
				profileUpdate.gender = gender || null;
				// health_data_consent_at is stamped server-side by the RPC
				// below (migration 20261118_001) — a direct write of it is
				// rejected by the lock trigger, so it's NOT in profileUpdate.
			}

			// Stamp Art 9 consent server-side first (first-stamp-wins), then
			// the bag + profile writes. The RPC is the only path that can
			// set health_data_consent_at to a non-null value.
			if (healthDataConsent) {
				const { error: consentErr } = await supabase.rpc('grant_health_data_consent');
				if (consentErr) throw consentErr;
			}

			// Issue both writes in parallel — the bag write doesn't
			// depend on the profile write and vice versa. stampProfile
			// throws on error AND on a 0-row update (issue #227), so a
			// stamp that never landed can't navigate.
			await Promise.all([
				updateUniversal(auth.user!.id, bagChanges),
				stampProfile(profileUpdate),
			]);

			showToast(m('onboarding.welcomeToast'), 'success');
			// Full page navigation (same rationale as navigateToDashboard) so the
			// layout onboarding-gate re-bootstraps from the freshly-written
			// onboarded_at. `dest` is /dashboard by default, or the goal-keyed
			// /plans/new deep-link from the "create my training plan" CTA.
			window.location.href = dest;
		} catch (e) {
			showToast(m('onboarding.saveError', { message: (e as Error).message }), 'error');
			saving = false;
		}
		// On success the navigation tears down the page; no need to
		// reset `saving = false`.
	}
</script>

<svelte:head>
	<title>{m('onboarding.pageTitle')}</title>
</svelte:head>

<div class="onboarding-shell">
	<header class="head">
		<div class="brand">Threkir</div>
		<button type="button" class="skip-all" onclick={skipOnboarding} disabled={saving}>
			{m('onboarding.skipOnboarding')}
		</button>
	</header>

	<div class="progress" role="progressbar" aria-valuemin="1" aria-valuemax={ONBOARDING_TOTAL_STEPS} aria-valuenow={step}>
		{#each Array(ONBOARDING_TOTAL_STEPS) as _, i (i)}
			<span class="dot" class:active={i + 1 === step} class:done={i + 1 < step}></span>
		{/each}
	</div>

	<main class="card">
		{#if !ready}
			<p class="loading-hint">{m('shell.loading')}</p>
		{:else if step === 1}
			<section aria-labelledby="step-1-title">
				<h1 id="step-1-title">{m('onboarding.step1Title')}</h1>
				<p class="hint">
					{m('onboarding.step1Hint')}
				</p>
				<label class="field">
					<span class="label-text">{m('onboarding.displayNameLabel')}</span>
					<input
						type="text"
						bind:value={displayName}
						maxlength="60"
						placeholder={m('onboarding.displayNamePlaceholder')}
					/>
				</label>
			</section>
		{:else if step === 2}
			<section aria-labelledby="step-2-title">
				<h1 id="step-2-title">{m('onboarding.step2Title')}</h1>
				<p class="hint">
					{m('onboarding.step2Hint')}
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
						<span class="unit-name">{m('onboarding.unitKm')}</span>
						<span class="unit-sample">{m('onboarding.unitKmSample')}</span>
					</button>
					<button
						type="button"
						class="unit-option"
						class:selected={preferredUnit === 'mi'}
						role="radio"
						aria-checked={preferredUnit === 'mi'}
						onclick={() => (preferredUnit = 'mi')}
					>
						<span class="unit-name">{m('onboarding.unitMi')}</span>
						<span class="unit-sample">{m('onboarding.unitMiSample')}</span>
					</button>
				</div>
			</section>
		{:else if step === 3}
			<section aria-labelledby="step-3-title">
				<h1 id="step-3-title">{m('onboarding.step3Title')}</h1>
				<p class="hint">
					{m('onboarding.step3Hint')}
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
							{m(`onboarding.goal.${v}`)}
						</button>
					{/each}
				</div>
			</section>
		{:else if step === 4}
			<section aria-labelledby="step-4-title">
				<h1 id="step-4-title">{m('onboarding.step4Title')}</h1>
				<p class="hint">
					{m('onboarding.step4Hint')}
				</p>
				<label class="field">
					<span class="label-text">{m('onboarding.genderLabel')}</span>
					<select bind:value={gender}>
						<option value="">{m('onboarding.genderPreferNot')}</option>
						<option value="female">{m('onboarding.genderFemale')}</option>
						<option value="male">{m('onboarding.genderMale')}</option>
						<option value="nonbinary">{m('onboarding.genderNonbinary')}</option>
					</select>
				</label>
				<label class="field">
					<span class="label-text">{m('onboarding.dobLabel')}</span>
					<input type="date" bind:value={dateOfBirth} max={new Date().toISOString().slice(0, 10)} />
					<span class="field-note">
						{m('onboarding.dobNote')}
					</span>
				</label>
				<label class="field">
					<span class="label-text">{m('onboarding.weightLabel', { unit: weightUnit })}</span>
					<input type="number" inputmode="decimal" min={weightMin} max={weightMax} step="0.1" bind:value={bodyWeight} placeholder={m('onboarding.weightPlaceholder', { example: weightUnit === 'lbs' ? 155 : 70 })} />
				</label>
				{#if gender || dateOfBirth}
					<label class="consent-row">
						<input type="checkbox" bind:checked={healthDataConsent} />
						<span>
							{m('onboarding.healthConsent')}
						</span>
					</label>
				{/if}
			</section>
		{:else if step === 5}
			<section aria-labelledby="step-5-title">
				<h1 id="step-5-title">{m('onboarding.step5Title')}</h1>
				<p class="hint">
					{m('onboarding.step5Hint')}
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
						<strong>{m('onboarding.privacyPrivate')}</strong>
						<span>{m('onboarding.privacyPrivateDesc')}</span>
					</button>
					<button
						type="button"
						class="privacy-option"
						class:selected={privacyDefault === 'followers'}
						role="radio"
						aria-checked={privacyDefault === 'followers'}
						onclick={() => (privacyDefault = 'followers')}
					>
						<strong>{m('onboarding.privacyFollowers')}</strong>
						<span>{m('onboarding.privacyFollowersDesc')}</span>
					</button>
					<button
						type="button"
						class="privacy-option"
						class:selected={privacyDefault === 'public'}
						role="radio"
						aria-checked={privacyDefault === 'public'}
						onclick={() => (privacyDefault = 'public')}
					>
						<strong>{m('onboarding.privacyPublic')}</strong>
						<span>{m('onboarding.privacyPublicDesc')}</span>
					</button>
				</div>
			</section>
		{:else if step === 6}
			<section aria-labelledby="step-6-title">
				<h1 id="step-6-title">{m('onboarding.step6Title')}</h1>
				<p class="hint">
					{m('onboarding.step6Hint')}
				</p>
				{#if !pushSupported}
					<p class="not-available">
						{m('onboarding.pushUnsupported')}
					</p>
				{:else if pushPermission() === 'denied'}
					<p class="not-available">
						{m('onboarding.pushBlocked')}
					</p>
				{:else if pushSubscribed}
					<p class="success-text">{m('onboarding.pushEnabled')}</p>
				{:else}
					<button
						type="button"
						class="btn btn-primary"
						onclick={handleEnablePush}
						disabled={pushBusy}
					>
						<span class="material-symbols">notifications_active</span>
						{pushBusy ? m('onboarding.pushEnabling') : m('onboarding.pushEnable')}
					</button>
				{/if}
			</section>
		{:else if step === 7}
			<section aria-labelledby="step-7-title">
				<h1 id="step-7-title">{m('onboarding.step7Title')}</h1>
				<p class="hint">
					{m('onboarding.step7Hint')}
				</p>
				{#if primaryGoal}
					<button
						type="button"
						class="btn btn-primary create-plan-cta"
						onclick={() => finishAndExit(`/plans/new?type=training&goal=${primaryGoal}`)}
						disabled={saving}
					>
						{saving ? m('onboarding.saving') : m('onboarding.createPlanCta')}
					</button>
				{/if}
			</section>
		{/if}

		{#if ready}
		<div class="nav-row">
			{#if step > 1}
				<button type="button" class="btn btn-outline" onclick={back} disabled={saving}>
					{m('onboarding.back')}
				</button>
			{:else}
				<span></span>
			{/if}
			<div class="nav-right">
				{#if step !== 7 && step !== 1 && step !== 5 && step !== 2}
					<button type="button" class="skip-step" onclick={skipStep} disabled={saving}>
						{m('onboarding.skip')}
					</button>
				{/if}
				{#if step < ONBOARDING_TOTAL_STEPS}
					<button type="button" class="btn btn-primary" onclick={next} disabled={saving}>
						{m('onboarding.continue')}
					</button>
				{:else}
					<button
						type="button"
						class="btn {primaryGoal ? 'btn-outline' : 'btn-primary'}"
						onclick={() => finishAndExit()}
						disabled={saving}
					>
						{saving ? m('onboarding.saving') : m('onboarding.openDashboard')}
					</button>
				{/if}
			</div>
		</div>
		{/if}
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
	.create-plan-cta { align-self: flex-start; }

	.field { display: flex; flex-direction: column; gap: 0.35rem; }
	.label-text { font-size: 0.85rem; color: var(--color-text-secondary); font-weight: 500; }
	.field-note { font-size: 0.78rem; color: var(--color-text-tertiary); line-height: 1.45; }
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
		text-align: start;
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
