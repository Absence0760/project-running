<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { supabase } from '$lib/supabase';
	import { isLocked } from '$lib/features';
	import { fmtKm } from '$lib/units.svelte';
	import ProGate from '$lib/components/ProGate.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';

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
	let showArchiveConfirm = $state(false);
	let showHistory = $state(false);
	// When non-null, the user is viewing an archived thread (read-only) —
	// `messages` holds that archive's contents and the composer is hidden.
	let viewingArchiveAt = $state<string | null>(null);

	interface ArchiveSummary {
		archived_at: string;
		first_user_message: string | null;
		message_count: number;
	}
	let archives = $state<ArchiveSummary[]>([]);

	// localStorage key used by the previous (per-device) persistence. Kept
	// only so we can migrate any pre-existing thread into Supabase the
	// first time a user lands on this build.
	function legacyStorageKey(userId: string, plan: string | null): string {
		return `coach_chat:${userId}:${plan ?? 'no_plan'}`;
	}

	function planFilter<T>(q: T): T {
		// Supabase query builder mutates in place + returns itself, so this
		// is safe and lets the same chain be reused across active /
		// archived / per-archive queries that all need the (user, plan)
		// scoping with plan_id IS NULL handled correctly.
		const builder = q as unknown as { eq: (k: string, v: string) => T; is: (k: string, v: null) => T };
		return planId ? builder.eq('plan_id', planId) : builder.is('plan_id', null);
	}

	async function loadThread(userId: string) {
		const { data, error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.select('role, content')
				.eq('user_id', userId)
				.is('archived_at', null)
				.order('created_at', { ascending: true }),
		);
		if (err) {
			console.error('[coach] load thread failed', err);
			return;
		}
		const rows = (data ?? []) as Msg[];
		if (rows.length > 0) {
			messages = rows;
			return;
		}
		// DB is empty for this (user × plan). If the previous build had a
		// localStorage thread, migrate it once and never look at
		// localStorage again. Insert as a single batch — RLS gates on
		// user_id so this can only ever land rows in the caller's own
		// account.
		try {
			const raw = localStorage.getItem(legacyStorageKey(userId, planId));
			if (!raw) return;
			const parsed = JSON.parse(raw) as { messages?: Msg[] };
			const legacy = (parsed?.messages ?? []).filter(
				(m) =>
					m &&
					(m.role === 'user' || m.role === 'assistant') &&
					typeof m.content === 'string',
			);
			if (legacy.length === 0) {
				localStorage.removeItem(legacyStorageKey(userId, planId));
				return;
			}
			const { error: insertErr } = await supabase.from('coach_messages').insert(
				legacy.map((m) => ({
					user_id: userId,
					plan_id: planId,
					role: m.role,
					content: m.content,
				})),
			);
			if (!insertErr) {
				messages = legacy;
				localStorage.removeItem(legacyStorageKey(userId, planId));
			}
		} catch (_) {
			/* localStorage unavailable / parse error — nothing to migrate */
		}
	}

	// Archives currently active rows under a single archived_at timestamp,
	// so they group as one historical thread, then resets the live view
	// to a blank slate. This is what the "Start new conversation" button
	// does — the previous Clear button DELETE'd, losing the thread.
	async function archiveCurrentThread() {
		showArchiveConfirm = false;
		if (!cachedUserId) return;
		const ts = new Date().toISOString();
		const { error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.update({ archived_at: ts })
				.eq('user_id', cachedUserId)
				.is('archived_at', null),
		);
		if (err) {
			console.error('[coach] archive failed', err);
			error = 'Could not start a new conversation — please try again.';
			return;
		}
		messages = [];
		await loadArchives();
	}

	async function loadArchives() {
		if (!cachedUserId) return;
		// One row per (archived_at, role, content). We pull all archived
		// rows then group client-side for `first_user_message` + count —
		// counts are fine on a per-user scale (a heavy user has a few
		// hundred rows max). A SQL function would be tidier but adds a
		// migration; revisit if it ever gets slow.
		const { data, error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.select('archived_at, role, content, created_at')
				.eq('user_id', cachedUserId)
				.not('archived_at', 'is', null)
				.order('created_at', { ascending: true }),
		);
		if (err) {
			console.error('[coach] load archives failed', err);
			return;
		}
		const groups = new Map<string, { count: number; firstUser: string | null }>();
		for (const row of (data ?? []) as { archived_at: string; role: 'user' | 'assistant'; content: string }[]) {
			const g = groups.get(row.archived_at) ?? { count: 0, firstUser: null };
			g.count += 1;
			if (g.firstUser == null && row.role === 'user') g.firstUser = row.content;
			groups.set(row.archived_at, g);
		}
		archives = [...groups.entries()]
			.map(([archived_at, g]) => ({ archived_at, first_user_message: g.firstUser, message_count: g.count }))
			.sort((a, b) => b.archived_at.localeCompare(a.archived_at));
	}

	async function viewArchive(archivedAt: string) {
		if (!cachedUserId) return;
		const { data, error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.select('role, content')
				.eq('user_id', cachedUserId)
				.eq('archived_at', archivedAt)
				.order('created_at', { ascending: true }),
		);
		if (err) {
			console.error('[coach] view archive failed', err);
			return;
		}
		messages = (data ?? []) as Msg[];
		viewingArchiveAt = archivedAt;
		showHistory = false;
		await scrollToBottom();
	}

	async function backToActive() {
		viewingArchiveAt = null;
		messages = [];
		if (cachedUserId) await loadThread(cachedUserId);
		await scrollToBottom();
	}

	async function deleteArchive(archivedAt: string) {
		if (!cachedUserId) return;
		const { error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.delete()
				.eq('user_id', cachedUserId)
				.eq('archived_at', archivedAt),
		);
		if (err) {
			console.error('[coach] delete archive failed', err);
			return;
		}
		archives = archives.filter((a) => a.archived_at !== archivedAt);
		if (viewingArchiveAt === archivedAt) await backToActive();
	}

	function formatArchiveDate(iso: string): string {
		const d = new Date(iso);
		return d.toLocaleString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric',
			hour: 'numeric',
			minute: '2-digit',
		});
	}
	let lastCache = $state<{
		read: number;
		create: number;
		in: number;
		out: number;
	} | null>(null);

	// Tier + daily limit are echoed back in the response (`tier`,
	// `limits.daily_limit`); we hold optimistic defaults until the
	// first round-trip confirms them. `null` daily_limit means
	// unlimited (Pro / bypass).
	const DEFAULT_DAILY_LIMIT = 10;
	let tier = $state<'free' | 'pro' | null>(null);
	let dailyLimit = $state<number | null>(DEFAULT_DAILY_LIMIT);
	let usedToday = $state(0);
	let isUnlimited = $derived(dailyLimit === null);
	let limitReached = $derived(!isUnlimited && usedToday >= (dailyLimit ?? 0));
	let remaining = $derived(
		isUnlimited ? Infinity : Math.max(0, (dailyLimit ?? 0) - usedToday),
	);

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
		// Pull the persisted thread for this (user × plan) from Supabase.
		// Server is the source of truth — no localStorage save effect.
		await loadThread(session.user.id);
		await loadArchives();
		// Fetch usage + tier in parallel so the footer shows the right
		// shape (free / pro, daily-cap or unlimited) before the user
		// even sends the first message.
		const [{ data: usage }, { data: isPro }] = await Promise.all([
			supabase.rpc('get_coach_usage', { p_user_id: session.user.id }),
			supabase.rpc('is_user_pro', { p_user_id: session.user.id }),
		]);
		if (typeof usage === 'number') usedToday = usage;
		if (isPro === true) {
			tier = 'pro';
			dailyLimit = null;
		} else {
			tier = 'free';
			dailyLimit = DEFAULT_DAILY_LIMIT;
		}

		await loadContextSummary(session.user.id);
		await scrollToBottom();
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
				headers: {
					'content-type': 'application/json',
					'Authorization': `Bearer ${token}`,
				},
				body: JSON.stringify({
					messages,
					plan_id: planId,
					recent_runs_limit: runsLimit,
				})
			});
			if (!res.ok) {
				if (res.status === 404) {
					error =
						'Coach runs as a server endpoint. This deploy uses the static adapter — switch to a server deploy (Vercel/Node) and set ANTHROPIC_API_KEY to enable chat.';
				} else if (res.status === 429) {
					const body = await res.json().catch(() => ({}));
					usedToday = body.used ?? (dailyLimit ?? DEFAULT_DAILY_LIMIT);
					if (typeof body.tier === 'string') tier = body.tier as 'free' | 'pro';
					if (typeof body.limit === 'number') dailyLimit = body.limit;
					error =
						body.message ??
						`Daily limit reached (${dailyLimit ?? DEFAULT_DAILY_LIMIT} messages). Come back tomorrow!`;
				} else {
					const body = await res.json().catch(() => ({}));
					error = body.error ?? `Coach error (${res.status})`;
				}
				return;
			}
			usedToday++;
			const body = await res.json();
			messages = [...messages, { role: 'assistant', content: body.reply }];
			// Server is the source of truth for tier + limits. Adopt
			// what it returns so the footer matches actual budget after
			// every round-trip (e.g. mid-session tier upgrade).
			if (typeof body.tier === 'string') tier = body.tier as 'free' | 'pro';
			if (body.limits) {
				dailyLimit = body.limits.daily_limit ?? null;
			}
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
		<div class="header-row">
			<h3>Coach</h3>
			<div class="header-actions">
				{#if archives.length > 0}
					<button
						type="button"
						class="header-btn"
						title="Past conversations for this {hasPlan ? 'plan' : 'no-plan'} thread"
						aria-expanded={showHistory}
						onclick={() => (showHistory = !showHistory)}
					>
						<span class="material-symbols">history</span>
						History
						<span class="badge">{archives.length}</span>
					</button>
				{/if}
				{#if messages.length > 0 && viewingArchiveAt == null}
					<button
						type="button"
						class="header-btn"
						title="Archive this conversation and start a fresh one. The current thread stays in History."
						onclick={() => (showArchiveConfirm = true)}
					>
						<span class="material-symbols">edit_square</span>
						Start new
					</button>
				{/if}
			</div>
		</div>

		{#if showHistory}
			<div class="history-panel" role="region" aria-label="Past conversations">
				{#if archives.length === 0}
					<p class="muted">No past conversations yet.</p>
				{:else}
					{#each archives as a (a.archived_at)}
						<div class="archive-row" class:current={a.archived_at === viewingArchiveAt}>
							<button
								type="button"
								class="archive-link"
								onclick={() => viewArchive(a.archived_at)}
							>
								<span class="archive-date">{formatArchiveDate(a.archived_at)}</span>
								<span class="archive-preview">
									{a.first_user_message ?? '(no user messages)'}
								</span>
								<span class="archive-meta">{a.message_count} message{a.message_count === 1 ? '' : 's'}</span>
							</button>
							<button
								type="button"
								class="archive-delete"
								title="Delete this conversation forever"
								aria-label="Delete archive from {formatArchiveDate(a.archived_at)}"
								onclick={() => deleteArchive(a.archived_at)}
							>
								<span class="material-symbols">close</span>
							</button>
						</div>
					{/each}
				{/if}
			</div>
		{/if}

		{#if viewingArchiveAt}
			<div class="archive-banner">
				<span class="material-symbols">history</span>
				<span>
					Viewing archive · {formatArchiveDate(viewingArchiveAt)} · read-only
				</span>
				<button type="button" class="header-btn" onclick={backToActive}>
					<span class="material-symbols">arrow_back</span>
					Back to active
				</button>
			</div>
		{/if}
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

	{#if viewingArchiveAt}
		<!-- Composer suppressed in archive view; the banner above offers
		     "Back to active" to return to the live thread. -->
	{:else if limitReached}
		<div class="limit-bar">
			<span class="material-symbols">schedule</span>
			You've used all {dailyLimit ?? DEFAULT_DAILY_LIMIT} messages for today. Come back tomorrow!
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
		<span class="usage-count">
			{#if isUnlimited}
				<span class="tier-badge tier-pro">Pro</span>
				Unlimited messages · priority context window
			{:else}
				{#if tier === 'free'}<span class="tier-badge tier-free">Free</span>{/if}
				{remaining} of {dailyLimit ?? DEFAULT_DAILY_LIMIT} messages remaining today
			{/if}
		</span>
		{#if lastCache && (lastCache.read > 0 || lastCache.create > 0)}
			<span class="cache-note">
				Cache: read {lastCache.read} · wrote {lastCache.create} · in {lastCache.in} · out {lastCache.out}
			</span>
		{:else if messages.length > 0}
			<span class="cache-note" title="Saved to your account and synced across devices. Per plan — switching plans shows a different thread.">
				<span class="material-symbols save-icon">cloud_done</span>
				Synced
			</span>
		{/if}
	</div>

	<ConfirmDialog
		open={showArchiveConfirm}
		title="Start a new conversation?"
		message="Your current chat will be moved to History so you can view it later. The composer resets to a fresh thread."
		confirmLabel="Start new"
		onconfirm={archiveCurrentThread}
		oncancel={() => (showArchiveConfirm = false)}
	/>
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
	.header-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		margin-bottom: 0.2rem;
	}
	header h3 {
		font-size: 1.05rem;
		margin: 0;
	}
	header .sub {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.header-actions {
		display: inline-flex;
		gap: 0.3rem;
	}
	.header-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		background: transparent;
		border: 1px solid var(--color-border);
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		font-weight: 500;
		padding: 0.25rem 0.55rem;
		border-radius: 9999px;
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.header-btn:hover {
		color: var(--color-primary);
		border-color: var(--color-primary);
	}
	.header-btn .material-symbols {
		font-size: 0.95rem;
		line-height: 1;
	}
	.header-btn .badge {
		display: inline-block;
		min-width: 1.2rem;
		padding: 0 0.35rem;
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
		border-radius: 9999px;
		font-size: 0.7rem;
		font-weight: 700;
		text-align: center;
		line-height: 1.4;
	}
	.history-panel {
		margin-top: 0.6rem;
		padding: 0.5rem;
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		max-height: 14rem;
		overflow-y: auto;
	}
	.history-panel .muted {
		color: var(--color-text-tertiary);
		margin: 0;
		padding: 0.35rem 0.5rem;
		font-size: 0.85rem;
	}
	.archive-row {
		display: flex;
		align-items: stretch;
		gap: 0.3rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.archive-row.current {
		border-color: var(--color-primary);
	}
	.archive-link {
		flex: 1;
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: 0.15rem;
		padding: 0.45rem 0.6rem;
		background: transparent;
		border: none;
		text-align: left;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}
	.archive-link:hover {
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
	}
	.archive-date {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		font-weight: 600;
	}
	.archive-preview {
		font-size: 0.88rem;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
	}
	.archive-meta {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
	}
	.archive-delete {
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		padding: 0 0.5rem;
		cursor: pointer;
		border-radius: var(--radius-md);
	}
	.archive-delete:hover {
		color: var(--color-danger);
		background: color-mix(in srgb, var(--color-danger) 10%, transparent);
	}
	.archive-delete .material-symbols {
		font-size: 1rem;
		line-height: 1;
	}
	.archive-banner {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem 0.8rem;
		margin: 0 var(--space-sm);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 25%, var(--color-border));
		border-radius: var(--radius-md);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.archive-banner > span:nth-child(2) {
		flex: 1;
	}
	.archive-banner .material-symbols {
		font-size: 1rem;
		color: var(--color-primary);
	}
	.save-icon {
		font-size: 0.85rem;
		line-height: 1;
		vertical-align: -2px;
		margin-right: 0.15rem;
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
		overflow-wrap: anywhere;
		word-break: break-word;
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
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.tier-badge {
		font-size: 0.65rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		padding: 0.1rem 0.4rem;
		border-radius: 9999px;
	}
	.tier-pro {
		background: rgba(79, 70, 229, 0.12);
		color: var(--color-primary);
	}
	.tier-free {
		background: var(--color-bg-tertiary);
		color: var(--color-text-secondary);
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
