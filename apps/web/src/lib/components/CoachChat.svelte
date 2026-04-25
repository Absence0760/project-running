<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { supabase } from '$lib/supabase';
	import { isLocked } from '$lib/features';
	import { fmtKm } from '$lib/units.svelte';
	import ProGate from '$lib/components/ProGate.svelte';

	interface Props {
		planId: string | null;
	}
	let { planId }: Props = $props();
	let locked = $derived(isLocked('ai_coach'));
	let hasPlan = $derived(planId != null);

	// User-configurable history window. Server clamps to [1, 100]; we keep
	// the UI options curated so people don't accidentally pick something
	// that blows past local-model context limits.
	const RUN_LIMIT_OPTIONS = [10, 20, 50, 100];
	let runsLimit = $state(20);

	interface Msg {
		role: 'user' | 'assistant';
		content: string;
	}

	let messages = $state<Msg[]>([]);
	let draft = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);
	let scrollEl: HTMLDivElement | null = $state(null);
	let lastCache = $state<{
		read: number;
		create: number;
		in: number;
		out: number;
	} | null>(null);

	const DAILY_LIMIT = 10;
	let usedToday = $state(0);
	let limitReached = $derived(usedToday >= DAILY_LIMIT);
	let remaining = $derived(Math.max(0, DAILY_LIMIT - usedToday));

	// Mirrors what `/api/coach/+server.ts buildContext()` actually pulls.
	// Probed client-side so the user can see the grounding *before* asking
	// — "what is the coach actually looking at?" was opaque otherwise.
	interface ContextSummary {
		planName: string | null;
		planWeeks: number | null;
		runCount: number;
		hrZonesLoaded: boolean;
		weeklyGoalMetres: number | null;
	}
	let contextSummary = $state<ContextSummary | null>(null);

	let cachedUserId = $state<string | null>(null);

	onMount(async () => {
		const { data: { session } } = await supabase.auth.getSession();
		if (!session) return;
		cachedUserId = session.user.id;
		const { data } = await supabase.rpc('get_coach_usage', {
			p_user_id: session.user.id,
		});
		if (typeof data === 'number') usedToday = data;

		await loadContextSummary(session.user.id);
	});

	// Re-probe the runs chip when the user changes the limit so the
	// "Last N runs" label tracks the value sent on the next request.
	$effect(() => {
		const _ = runsLimit;
		if (cachedUserId) loadContextSummary(cachedUserId);
	});

	async function loadContextSummary(userId: string) {
		// Plan: name + week count when planId is provided OR a single
		// active plan exists. Mirrors the server's "active or specified"
		// fallback so the strip matches what gets sent.
		let planName: string | null = null;
		let planWeeks: number | null = null;
		try {
			const planQuery = planId
				? supabase.from('training_plans').select('id, name').eq('id', planId).maybeSingle()
				: supabase
						.from('training_plans')
						.select('id, name')
						.eq('user_id', userId)
						.eq('status', 'active')
						.maybeSingle();
			const { data: plan } = await planQuery;
			if (plan) {
				planName = plan.name;
				const { count } = await supabase
					.from('plan_weeks')
					.select('id', { count: 'exact', head: true })
					.eq('plan_id', plan.id);
				planWeeks = count ?? null;
			}
		} catch (_) {
			// silent — strip just reads "No active plan"
		}

		// Recent runs — capped at the user-chosen limit so the chip
		// reflects exactly what gets sent.
		let runCount = 0;
		try {
			const { count } = await supabase
				.from('runs')
				.select('id', { count: 'exact', head: true })
				.eq('user_id', userId);
			runCount = Math.min(count ?? 0, runsLimit);
		} catch (_) {
			/* noop */
		}

		// HR zones + weekly goal from the settings bag.
		let hrZonesLoaded = false;
		let weeklyGoalMetres: number | null = null;
		try {
			const { data: row } = await supabase
				.from('user_settings')
				.select('prefs')
				.eq('user_id', userId)
				.maybeSingle();
			const prefs = (row?.prefs ?? {}) as Record<string, unknown>;
			const zones = prefs.hr_zones as Record<string, number> | undefined;
			if (zones && [zones.z1, zones.z2, zones.z3, zones.z4, zones.z5].every((z) => typeof z === 'number' && z > 0)) {
				hrZonesLoaded = true;
			}
			const goal = prefs.weekly_mileage_goal_m;
			if (typeof goal === 'number' && goal > 0) weeklyGoalMetres = goal;
		} catch (_) {
			/* noop */
		}

		contextSummary = { planName, planWeeks, runCount, hrZonesLoaded, weeklyGoalMetres };
	}

	const PLAN_SUGGESTIONS = [
		'Should I run tomorrow or take a rest day?',
		'Am I on track for my goal time?',
		"Why does this week's long run matter?",
		"What should I focus on for today's workout?"
	];
	const NO_PLAN_SUGGESTIONS = [
		'How was my last run?',
		'What pace should my easy runs be?',
		"I haven't run in a week — what should I do?",
		'What is a tempo run?'
	];
	let suggestions = $derived(hasPlan ? PLAN_SUGGESTIONS : NO_PLAN_SUGGESTIONS);

	async function send() {
		const body = draft.trim();
		if (!body || busy) return;
		const userMsg: Msg = { role: 'user', content: body };
		messages = [...messages, userMsg];
		draft = '';
		busy = true;
		error = null;
		await scrollToBottom();

		try {
			const {
				data: { session }
			} = await supabase.auth.getSession();
			const token = session?.access_token;
			if (!token) {
				error = 'Please sign in first.';
				busy = false;
				return;
			}

			const res = await fetch('/api/coach', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					messages,
					plan_id: planId,
					recent_runs_limit: runsLimit,
					access_token: token
				})
			});
			if (!res.ok) {
				if (res.status === 404) {
					error =
						'Coach runs as a server endpoint. This deploy uses the static adapter — switch to a server deploy (Vercel/Node) and set ANTHROPIC_API_KEY to enable chat.';
				} else if (res.status === 429) {
					const body = await res.json().catch(() => ({}));
					usedToday = body.used ?? DAILY_LIMIT;
					error = body.message ?? `Daily limit reached (${DAILY_LIMIT} messages). Come back tomorrow!`;
				} else {
					const body = await res.json().catch(() => ({}));
					error = body.error ?? `Coach error (${res.status})`;
				}
				return;
			}
			usedToday++;
			const body = await res.json();
			messages = [...messages, { role: 'assistant', content: body.reply }];
			lastCache = {
				read: body.cache?.cache_read_input_tokens ?? 0,
				create: body.cache?.cache_creation_input_tokens ?? 0,
				in: body.cache?.input_tokens ?? 0,
				out: body.cache?.output_tokens ?? 0
			};
			await scrollToBottom();
		} catch (e) {
			error = e instanceof Error ? e.message : 'network error';
		} finally {
			busy = false;
		}
	}

	async function scrollToBottom() {
		await tick();
		if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
	}

	function use(s: string) {
		draft = s;
	}
</script>

{#if locked}
	<ProGate feature="ai_coach" />
{:else}
<div class="chat">
	<header>
		<h3>Coach</h3>
		<p class="sub">
			{#if hasPlan}
				Second opinion on your plan and runs. Not a replacement for a human
				coach — doesn't generate plans or give medical advice.
			{:else}
				Second opinion on your recent runs. Not a replacement for a human
				coach — doesn't generate plans or give medical advice.
			{/if}
		</p>
		{#if contextSummary}
			{@const c = contextSummary}
			<div class="context-strip" title="What the coach has loaded for this conversation">
				<span class="context-label">Grounded in:</span>
				{#if c.planName}
					<span class="chip">
						<span class="material-symbols">calendar_month</span>
						{c.planName}{#if c.planWeeks}<span class="chip-meta"> · {c.planWeeks} wk</span>{/if}
					</span>
				{:else}
					<span class="chip chip-muted">
						<span class="material-symbols">calendar_month</span>
						No active plan
					</span>
				{/if}
				<label class="chip chip-select" title="How many recent runs to feed the coach">
					<span class="material-symbols">directions_run</span>
					{#if c.runCount === 0}
						<span>No runs yet</span>
					{:else}
						<span>Last</span>
						<select
							class="chip-select-input"
							bind:value={runsLimit}
							aria-label="Recent runs to include"
						>
							{#each RUN_LIMIT_OPTIONS as n}
								<option value={n}>{n}</option>
							{/each}
						</select>
						<span>runs</span>
					{/if}
				</label>
				{#if c.hrZonesLoaded}
					<span class="chip">
						<span class="material-symbols">monitor_heart</span>
						HR zones
					</span>
				{:else}
					<span class="chip chip-muted">
						<span class="material-symbols">monitor_heart</span>
						HR zones not set
					</span>
				{/if}
				{#if c.weeklyGoalMetres}
					<span class="chip">
						<span class="material-symbols">flag</span>
						Goal {fmtKm(c.weeklyGoalMetres)}/wk
					</span>
				{/if}
			</div>
		{/if}
	</header>

	<div class="scroll" bind:this={scrollEl}>
		{#if messages.length === 0}
			<div class="primer">
				<p>
					{#if hasPlan}
						Ask about today's workout, your pace, or how recent runs compare to plan.
					{:else}
						Ask about your recent runs, easy-run pacing, or training basics.
					{/if}
				</p>
				<div class="suggestions">
					{#each suggestions as s}
						<button class="suggest" onclick={() => use(s)}>{s}</button>
					{/each}
				</div>
			</div>
		{/if}
		{#each messages as m}
			<div class="bubble" class:user={m.role === 'user'}>
				<span>{m.content}</span>
			</div>
		{/each}
		{#if busy}
			<div class="bubble"><span class="typing">Thinking…</span></div>
		{/if}
	</div>

	{#if error}
		<p class="error">{error}</p>
	{/if}

	{#if limitReached}
		<div class="limit-bar">
			<span class="material-symbols">schedule</span>
			You've used all {DAILY_LIMIT} messages for today. Come back tomorrow!
		</div>
	{:else}
		<form
			class="composer"
			onsubmit={(e) => {
				e.preventDefault();
				send();
			}}
		>
			<input
				type="text"
				placeholder="Ask about today, pace, adherence…"
				bind:value={draft}
				disabled={busy}
				maxlength="600"
			/>
			<button type="submit" class="btn-primary" disabled={busy || !draft.trim()}>
				{busy ? '…' : 'Send'}
			</button>
		</form>
	{/if}
	<div class="usage-bar">
		<span class="usage-count">{remaining} of {DAILY_LIMIT} messages remaining today</span>
		{#if lastCache && (lastCache.read > 0 || lastCache.create > 0)}
			<span class="cache-note">
				Cache: read {lastCache.read} · wrote {lastCache.create} · in {lastCache.in} · out {lastCache.out}
			</span>
		{/if}
	</div>
</div>
{/if}

<style>
	.chat {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		/* Default height for embedded uses (e.g. /plans/[id] historically).
		   When the parent gives the host a height (like /coach), the
		   wrapper overrides this to fill the viewport. */
		height: 36rem;
		min-height: 0;
	}
	header {
		padding: var(--space-md);
		border-bottom: 1px solid var(--color-border);
	}
	header h3 {
		font-size: 1.05rem;
		margin-bottom: 0.2rem;
	}
	header .sub {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.context-strip {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.4rem;
		margin-top: 0.6rem;
	}
	.context-label {
		font-size: 0.72rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin-right: 0.1rem;
	}
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.2rem 0.55rem;
		background: var(--color-primary-light);
		color: var(--color-primary);
		border-radius: 999px;
		font-size: 0.78rem;
		font-weight: 500;
		line-height: 1.2;
	}
	.chip-muted {
		background: var(--color-bg-tertiary);
		color: var(--color-text-tertiary);
	}
	.chip .material-symbols {
		font-size: 0.95rem;
		line-height: 1;
	}
	.chip-meta {
		color: inherit;
		opacity: 0.75;
		font-weight: 400;
	}
	.chip-select {
		cursor: pointer;
		padding-right: 0.4rem;
	}
	.chip-select-input {
		appearance: none;
		background: transparent;
		border: none;
		color: inherit;
		font: inherit;
		font-weight: 600;
		padding: 0 0.15rem;
		cursor: pointer;
	}
	.chip-select-input:focus {
		outline: 2px solid color-mix(in srgb, var(--color-primary) 35%, transparent);
		outline-offset: 1px;
		border-radius: 4px;
	}
	.chip-select-input option {
		background: var(--color-surface);
		color: var(--color-text);
	}
	.scroll {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}
	.bubble {
		max-width: 85%;
		padding: 0.55rem 0.8rem;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
		white-space: pre-wrap;
		align-self: flex-start;
	}
	.bubble.user {
		background: var(--color-primary-light);
		color: var(--color-primary);
		align-self: flex-end;
	}
	.typing {
		color: var(--color-text-tertiary);
		font-style: italic;
	}
	.primer {
		color: var(--color-text-secondary);
	}
	.suggestions {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		margin-top: 0.6rem;
	}
	.suggest {
		text-align: left;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		padding: 0.45rem 0.7rem;
		border-radius: var(--radius-md);
		color: inherit;
		font: inherit;
		cursor: pointer;
	}
	.suggest:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.composer {
		display: flex;
		gap: 0.5rem;
		padding: var(--space-sm);
		border-top: 1px solid var(--color-border);
	}
	.composer input {
		flex: 1;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.5rem 0.75rem;
		color: inherit;
		font: inherit;
	}
	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		margin: 0.6rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
	.usage-bar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-xs) var(--space-sm);
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
	}
	.usage-count {
		font-weight: 500;
	}
	.cache-note {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
	}
	.limit-bar {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.2);
		border-radius: var(--radius-md);
		margin: 0 var(--space-sm) var(--space-sm);
		font-size: 0.82rem;
		color: var(--color-text-secondary);
	}
	.limit-bar .material-symbols {
		font-size: 1.1rem;
		color: var(--color-danger);
	}
</style>
