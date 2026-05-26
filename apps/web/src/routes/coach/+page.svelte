<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import CoachChat from '$lib/components/CoachChat.svelte';
	import { fetchActivePlanOverview, fetchMyPlans } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/supabase';
	import { GUIDED_RUN_LIBRARY, type GuidedRun } from '$lib/guided_runs';
	import type { TrainingPlan } from '$lib/types';

	let plans = $state<TrainingPlan[]>([]);
	let planId = $state<string | null>(null);
	let loaded = $state(false);

	// GDPR Art 6(1)(a): the Coach forwards health-adjacent data (DOB,
	// HR zones, recent runs) to Anthropic, a US-based sub-processor.
	// Opening the page is not an affirmative consent act — gate the
	// chat behind a first-use disclosure until the user clicks accept,
	// at which point we stamp `coach_consent_at` on user_profiles.
	// See audit/gdpr (2026-05-25).
	let coachConsentAt = $state<string | null>(null);
	let coachConsentChecked = $state(false);
	let coachConsentSaving = $state(false);
	let coachConsentError = $state('');
	let coachConsentDecided = $derived(coachConsentChecked && coachConsentAt != null);

	// Read `?plan=<id>` from the URL on first load and whenever the param
	// changes (e.g. via the deep link from /plans/[id]). When absent, we
	// fall back to the user's active plan.
	let urlPlanParam = $derived($page.url.searchParams.get('plan'));

	onMount(async () => {
		// Wait for auth so the RLS-scoped fetches return the right rows.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		// Read the consent timestamp BEFORE anything that could fan out
		// to Anthropic. The chat component is render-gated on
		// `coachConsentDecided`, so a missing row keeps the disclosure
		// modal in front of the user until they accept.
		if (auth.user) {
			try {
				// user_profiles.coach_consent_at is not in the public-
				// safe column grant list (migration 20260707_001), so a
				// direct `.select('coach_consent_at')` returns null for
				// authenticated callers. Go through the SECURITY DEFINER
				// `get_my_profile()` RPC instead — same pattern as the
				// other self-row reads.
				// `.maybeSingle()` on a SetofOptions RPC return narrows to
				// `{}` in supabase-js v2.106's generated types — cast to
				// the shape we know `get_my_profile` produces.
				const { data: prof } = await supabase
					.rpc('get_my_profile')
					.maybeSingle();
				const row = prof as { coach_consent_at: string | null } | null;
				coachConsentAt = row?.coach_consent_at ?? null;
			} catch (_) {
				// Failed to read consent state — fail closed so we
				// never accidentally render the chat without an
				// affirmative grant.
				coachConsentAt = null;
			}
			coachConsentChecked = true;
		}
		try {
			plans = await fetchMyPlans();
		} catch (_) {
			plans = [];
		}
		await resolvePlanId();
		loaded = true;
	});

	async function acceptCoachConsent() {
		if (!auth.user || coachConsentSaving) return;
		coachConsentSaving = true;
		coachConsentError = '';
		const nowIso = new Date().toISOString();
		try {
			const { error } = await supabase
				.from('user_profiles')
				.update({ coach_consent_at: nowIso })
				.eq('id', auth.user.id);
			if (error) throw new Error(error.message);
			coachConsentAt = nowIso;
		} catch (e) {
			coachConsentError = (e as Error).message ?? 'Failed to record consent.';
		} finally {
			coachConsentSaving = false;
		}
	}

	function declineCoachConsent() {
		// Leaving the Coach surface without consent keeps the chat
		// component unmounted — no request can fire to Anthropic.
		goto('/dashboard');
	}

	$effect(() => {
		// Re-resolve when the query param changes (browser back/forward, or
		// the user picks a different plan in the switcher).
		if (loaded) resolvePlanId();
	});

	async function resolvePlanId() {
		const fromUrl = urlPlanParam;
		// Explicit "no plan" sentinel — user picked "No plan" in the
		// strip dropdown. Stay null; do NOT fall back to the active
		// plan or the user's first save reverts on the next load.
		if (fromUrl === 'none') {
			planId = null;
			return;
		}
		if (fromUrl && plans.some((p) => p.id === fromUrl)) {
			planId = fromUrl;
			return;
		}
		// No (or stale) query param — default to the user's active plan.
		try {
			const overview = await fetchActivePlanOverview();
			planId = overview?.plan.id ?? null;
		} catch (_) {
			planId = null;
		}
	}

	function pickPlan(next: string) {
		// Reflect the choice in the URL so refresh / share keeps the
		// context, and so $effect above re-runs `resolvePlanId`.
		// `next === ''` means the user picked the "No plan" option in
		// the strip dropdown; we encode that as `?plan=none` so a
		// reload re-reads the explicit choice instead of falling back
		// to the active plan.
		const params = new URLSearchParams($page.url.searchParams);
		if (next === '') params.set('plan', 'none');
		else params.set('plan', next);
		const qs = params.toString();
		goto(qs ? `/coach?${qs}` : '/coach', { replaceState: true, noScroll: true });
	}

	function fmtMinutes(seconds: number): string {
		const m = Math.round(seconds / 60);
		return `${m} min`;
	}

	// Intensity is implicit in title + subtitle wording — keep the data
	// model untouched (it mirrors mobile_android via shared-library-syncer)
	// and derive a hue locally for the rail's at-a-glance dot.
	function intensityFor(g: GuidedRun): { label: string; tone: 'easy' | 'tempo' | 'mixed' } {
		const s = (g.title + ' ' + g.subtitle).toLowerCase();
		if (s.includes('run/walk')) return { label: 'Run/walk', tone: 'mixed' };
		if (s.includes('tempo') || s.includes('interval')) return { label: 'Tempo', tone: 'tempo' };
		return { label: 'Easy', tone: 'easy' };
	}
</script>

<svelte:head>
	<title>Coach — Threkir</title>
</svelte:head>

<div class="page">
	<!--
		audit/accessibility (May 2026) High — WCAG 1.3.1 + 2.4.6.
		Coach page is a chat surface; the heading bar inside
		CoachChat surfaces the plan name, not the page identity.
		Visually-hidden h1 so screen-reader users navigating by
		headings can identify the route.
	-->
	<h1 class="visually-hidden">AI Coach</h1>
	<div class="chat-host">
		{#if !coachConsentChecked || !loaded}
			<p class="muted">Loading…</p>
		{:else if !coachConsentDecided}
			<!--
				GDPR Art 6(1)(a) first-use disclosure. Render-gates the
				chat so no fetch fans out to Anthropic until the user
				clicks accept. Decline → /dashboard. See audit/gdpr
				(2026-05-25).
			-->
			<div class="coach-consent" role="dialog" tabindex="-1" aria-labelledby="coach-consent-heading">
				<h2 id="coach-consent-heading">Before you chat with Coach</h2>
				<p>
					To give you grounded advice, Coach forwards a slice of your training
					data to <strong>Anthropic</strong>, our AI model provider in the United
					States. That slice includes:
				</p>
				<ul>
					<li>Your date of birth, gender, and configured HR zones, if you've set them.</li>
					<li>A window of your most recent runs (distance, duration, pace, HR).</li>
					<li>The active training plan you have selected.</li>
					<li>The chat messages you type here.</li>
				</ul>
				<p>
					Anthropic processes the data on Threkir's behalf under their data-processing
					terms; they do not train their models on Threkir customer data by default.
					Full details — including transfer mechanism, retention, and your withdrawal
					rights — are on our <a href="/privacy">privacy policy</a>.
				</p>
				<p>
					Click <strong>I consent</strong> to continue. Click cancel to leave the page
					with no data sent.
				</p>
				{#if coachConsentError}
					<p class="coach-consent-error" role="alert">{coachConsentError}</p>
				{/if}
				<div class="coach-consent-actions">
					<button type="button" class="btn btn-secondary" onclick={declineCoachConsent}>
						Cancel
					</button>
					<button
						type="button"
						class="btn btn-primary"
						disabled={coachConsentSaving}
						onclick={acceptCoachConsent}
					>
						{coachConsentSaving ? 'Recording consent…' : 'I consent — start Coach'}
					</button>
				</div>
			</div>
		{:else}
			{#key planId}
				<CoachChat {planId} {plans} onPlanChange={pickPlan} />
			{/key}
		{/if}
	</div>

	<aside class="guided" aria-labelledby="guided-heading">
		<header class="guided-head">
			<p class="guided-eyebrow">Also for you</p>
			<h2 id="guided-heading">Guided runs</h2>
			<p class="guided-sub">Coach-voice scripted workouts — preview here, run on mobile.</p>
		</header>
		{#if GUIDED_RUN_LIBRARY.length === 0}
			<p class="guided-empty">No guided runs available yet. Check back soon.</p>
		{:else}
			<ul class="guided-list">
				{#each GUIDED_RUN_LIBRARY as g (g.id)}
					{@const intent = intensityFor(g)}
					<li>
						<a class="guided-card" href="/guided/{g.id}">
							<div class="guided-card-head">
								<span class="duration">{fmtMinutes(g.duration_sec)}</span>
								<span class="intensity" data-tone={intent.tone}>
									<span class="intensity-dot" aria-hidden="true"></span>
									{intent.label}
								</span>
							</div>
							<h3>{g.title}</h3>
							<p class="guided-card-sub">{g.subtitle}</p>
							<p class="guided-card-meta">{g.cues.length} cues</p>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
		<a class="guided-all" href="/guided">
			See the full library
			<span class="material-symbols">arrow_forward</span>
		</a>
		<div class="mobile-cta" aria-label="Run these on mobile">
			<span class="material-symbols mobile-cta-icon" aria-hidden="true">phone_iphone</span>
			<p class="mobile-cta-title">Run these on mobile</p>
			<p class="mobile-cta-sub">
				Cues fire through your phone's TTS as you run. Free — no subscription needed.
			</p>
		</div>
	</aside>
</div>

<style>
	.page {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 21rem;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		height: 100vh;
		min-height: 0;
	}
	.chat-host {
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
	}
	/* The CoachChat wrapper renamed from `.chat` to `.shell` when the
	   sidebar landed; the global selector mirrors that. */
	.chat-host > :global(.shell) {
		height: 100%;
	}
	.muted {
		color: var(--color-text-tertiary);
	}
	.coach-consent {
		max-width: 44rem;
		margin: var(--space-lg) auto;
		padding: var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		line-height: 1.55;
	}
	.coach-consent h2 {
		margin: 0 0 var(--space-md);
		font-size: 1.25rem;
	}
	.coach-consent p { margin: 0 0 var(--space-md); }
	.coach-consent ul { margin: 0 0 var(--space-md) 1.25rem; padding: 0; }
	.coach-consent li { margin-bottom: var(--space-xs); }
	.coach-consent-error {
		color: var(--color-error, #b71c1c);
		font-weight: 600;
	}
	.coach-consent-actions {
		display: flex;
		gap: var(--space-md);
		justify-content: flex-end;
		margin-top: var(--space-lg);
	}

	/* Right rail. Coach is the primary surface; the rail's hierarchy is
	   intentionally a step down from the chat header inside CoachChat. */
	.guided {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		overflow-y: auto;
		min-height: 0;
		scrollbar-gutter: stable;
	}
	.guided-head {
		margin-bottom: var(--space-sm);
	}
	.guided-eyebrow {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: 0.65rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	.guided-head h2 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.2;
	}
	.guided-sub {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		margin: var(--space-2xs) 0 0;
		line-height: 1.4;
	}
	.guided-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.guided-empty {
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}
	.guided-card {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		padding: 0.65rem 0.8rem;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		transition:
			border-color var(--transition-fast),
			background var(--transition-fast),
			transform var(--transition-fast);
	}
	.guided-card:hover {
		border-color: var(--color-primary);
		background: var(--color-surface);
		transform: translateY(-1px);
	}
	.guided-card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.duration {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 700;
	}
	.intensity {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.intensity-dot {
		width: 0.45rem;
		height: 0.45rem;
		border-radius: 50%;
		background: var(--color-text-tertiary);
	}
	.intensity[data-tone='easy'] .intensity-dot { background: var(--color-success); }
	.intensity[data-tone='tempo'] .intensity-dot { background: var(--color-accent-orange); }
	.intensity[data-tone='mixed'] .intensity-dot { background: var(--color-accent-cyan); }
	.guided-card h3 {
		margin: 0;
		font-size: 0.9rem;
		font-weight: 600;
		line-height: 1.3;
	}
	.guided-card-sub {
		font-size: 0.76rem;
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.35;
	}
	.guided-card-meta {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		margin: 0.15rem 0 0;
	}
	.guided-all {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		margin-top: var(--space-sm);
		padding: var(--space-xs) var(--space-sm);
		font-size: 0.78rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		border-radius: var(--radius-md);
		align-self: flex-start;
		transition: color var(--transition-fast), background var(--transition-fast);
	}
	.guided-all:hover {
		color: var(--color-primary);
		background: var(--color-bg-tertiary);
	}
	.guided-all .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 0.95rem;
	}

	/* Bottom CTA — closes the loop from "preview this" to "run this".
	   `margin-top: auto` pins it to the bottom so on tall viewports it
	   fills the empty rail space instead of floating against the cards. */
	.mobile-cta {
		margin-top: auto;
		padding: var(--space-md);
		background: color-mix(in srgb, var(--color-primary) 6%, var(--color-bg-secondary));
		border: 1px dashed color-mix(in srgb, var(--color-primary) 28%, var(--color-border));
		border-radius: var(--radius-md);
	}
	.mobile-cta-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 1.4rem;
		color: var(--color-primary);
		display: block;
		margin-bottom: var(--space-2xs);
	}
	.mobile-cta-title {
		font-size: 0.85rem;
		font-weight: 700;
		margin: 0 0 var(--space-2xs);
		color: var(--color-text);
	}
	.mobile-cta-sub {
		font-size: 0.74rem;
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.4;
	}

	/* Narrow viewports: stack the rail under the chat. The chat keeps
	   its full-height feel; the rail becomes a horizontally scrollable
	   strip below, and the mobile CTA gets out of the way — the user is
	   already on a small viewport, very likely a phone. */
	@media (max-width: 64rem) {
		.page {
			grid-template-columns: minmax(0, 1fr);
			grid-template-rows: minmax(0, 1fr) auto;
			height: auto;
			min-height: 100vh;
		}
		.chat-host {
			min-height: 36rem;
		}
		.guided {
			padding: var(--space-sm) var(--space-md);
		}
		.guided-list {
			flex-direction: row;
			overflow-x: auto;
			padding-bottom: var(--space-xs);
			scroll-snap-type: x mandatory;
		}
		.guided-list > li {
			flex: 0 0 16rem;
			scroll-snap-align: start;
		}
		.guided-all {
			align-self: flex-start;
		}
		.mobile-cta { display: none; }
	}
</style>
