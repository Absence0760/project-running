<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';
	import { marked } from 'marked';
	import DOMPurify from 'isomorphic-dompurify';
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

	const RUN_LIMIT_OPTIONS = [10, 20, 50, 100];
	let runsLimit = $state(20);

	interface Msg {
		// `id` is null for the streaming-in-flight assistant bubble or
		// optimistic user bubbles before the meta event lands. Once the
		// server returns the row id, we stitch it in so bubble actions
		// (regenerate / edit / react) can anchor on it.
		id: string | null;
		role: 'user' | 'assistant';
		content: string;
		reaction?: 'up' | 'down' | null;
	}

	let messages = $state<Msg[]>([]);
	let draft = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);
	let scrollEl: HTMLDivElement | null = $state(null);
	let composerEl: HTMLTextAreaElement | null = $state(null);
	let showArchiveConfirm = $state(false);
	let viewingArchiveAt = $state<string | null>(null);
	// id of the user message currently being edited (if any). The bubble
	// renders an inline textarea instead of its content while set.
	let editingId = $state<string | null>(null);
	let editingDraft = $state('');

	interface ArchiveSummary {
		archived_at: string;
		title: string;
		message_count: number;
	}
	let archives = $state<ArchiveSummary[]>([]);

	function legacyStorageKey(userId: string, plan: string | null): string {
		return `coach_chat:${userId}:${plan ?? 'no_plan'}`;
	}

	function planFilter<T>(q: T): T {
		const builder = q as unknown as { eq: (k: string, v: string) => T; is: (k: string, v: null) => T };
		return planId ? builder.eq('plan_id', planId) : builder.is('plan_id', null);
	}

	async function loadThread(userId: string) {
		const { data, error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.select('id, role, content, reaction')
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
		// One-time migration from the previous localStorage build.
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
				await loadThread(userId);
				localStorage.removeItem(legacyStorageKey(userId, planId));
			}
		} catch (_) {
			/* noop */
		}
	}

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
		viewingArchiveAt = null;
		await loadArchives();
	}

	async function loadArchives() {
		if (!cachedUserId) return;
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
			.map(([archived_at, g]) => ({
				archived_at,
				title: titleFromMessage(g.firstUser),
				message_count: g.count,
			}))
			.sort((a, b) => b.archived_at.localeCompare(a.archived_at));
	}

	function titleFromMessage(content: string | null): string {
		if (!content) return 'Untitled';
		const trimmed = content.replace(/\s+/g, ' ').trim();
		if (trimmed.length <= 48) return trimmed;
		return trimmed.slice(0, 47).trimEnd() + '…';
	}

	let activeThreadTitle = $derived.by(() => {
		const firstUser = messages.find((m) => m.role === 'user');
		return firstUser ? titleFromMessage(firstUser.content) : 'New conversation';
	});

	async function viewArchive(archivedAt: string) {
		if (!cachedUserId) return;
		const { data, error: err } = await planFilter(
			supabase
				.from('coach_messages')
				.select('id, role, content, reaction')
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
		await scrollToBottom();
	}

	async function backToActive() {
		viewingArchiveAt = null;
		messages = [];
		if (cachedUserId) await loadThread(cachedUserId);
		await scrollToBottom();
	}

	async function deleteArchive(archivedAt: string, ev: Event) {
		ev.stopPropagation();
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
		const now = new Date();
		const diffMs = now.getTime() - d.getTime();
		const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
		if (diffDays === 0) return 'Today';
		if (diffDays === 1) return 'Yesterday';
		if (diffDays < 7) return `${diffDays} days ago`;
		return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
	}

	let lastCache = $state<{ read: number; create: number; in: number; out: number } | null>(null);

	const DEFAULT_DAILY_LIMIT = 10;
	let tier = $state<'free' | 'pro' | null>(null);
	let dailyLimit = $state<number | null>(DEFAULT_DAILY_LIMIT);
	let usedToday = $state(0);
	let isUnlimited = $derived(dailyLimit === null);
	let limitReached = $derived(!isUnlimited && usedToday >= (dailyLimit ?? 0));
	let remaining = $derived(
		isUnlimited ? Infinity : Math.max(0, (dailyLimit ?? 0) - usedToday),
	);

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
		await loadThread(session.user.id);
		await loadArchives();
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
		subscribeToThread();
		await scrollToBottom();
	});

	$effect(() => {
		const _ = runsLimit;
		if (cachedUserId) loadContextSummary(cachedUserId);
	});

	async function loadContextSummary(userId: string) {
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
		} catch (_) { /* noop */ }

		let runCount = 0;
		try {
			const { count } = await supabase
				.from('runs')
				.select('id', { count: 'exact', head: true })
				.eq('user_id', userId);
			runCount = Math.min(count ?? 0, runsLimit);
		} catch (_) { /* noop */ }

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
		} catch (_) { /* noop */ }

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

	// ─────────────────────── Markdown rendering ───────────────────────

	marked.setOptions({ breaks: true, gfm: true });

	function renderMarkdown(content: string): string {
		const raw = marked.parse(content, { async: false }) as string;
		// DOMPurify drops anything that could execute (script, on*
		// handlers, javascript: URLs). We still get the formatting we want
		// from marked: paragraphs, lists, code blocks, **bold**.
		return DOMPurify.sanitize(raw);
	}

	// ─────────────────────── Send / regenerate / edit ───────────────────────

	type CoachMode = 'send' | 'regenerate' | 'edit';

	async function send() {
		const text = draft.trim();
		if (!text || busy) return;
		await runTurn({ mode: 'send', userText: text });
		draft = '';
	}

	async function regenerate(assistantId: string) {
		if (busy) return;
		const idx = messages.findIndex((m) => m.id === assistantId);
		if (idx === -1) return;
		// Lop off the assistant bubble and any trailing messages locally;
		// the server will mirror this with a delete and re-stream.
		messages = messages.slice(0, idx);
		await runTurn({ mode: 'regenerate', anchorId: assistantId });
	}

	function startEdit(userId: string, currentContent: string) {
		editingId = userId;
		editingDraft = currentContent;
	}

	function cancelEdit() {
		editingId = null;
		editingDraft = '';
	}

	async function commitEdit() {
		const newText = editingDraft.trim();
		const id = editingId;
		if (!id || !newText || busy) return;
		const idx = messages.findIndex((m) => m.id === id);
		if (idx === -1) return;
		// Replace this user message + drop everything after, mirroring
		// the server's truncate-and-rerun.
		const trimmed = messages.slice(0, idx);
		messages = trimmed;
		editingId = null;
		editingDraft = '';
		await runTurn({ mode: 'edit', userText: newText, anchorId: id });
	}

	async function runTurn(opts: { mode: CoachMode; userText?: string; anchorId?: string }) {
		busy = true;
		error = null;

		if (opts.userText) {
			messages = [...messages, { id: null, role: 'user', content: opts.userText }];
		}
		// Placeholder assistant bubble that streamed tokens flow into.
		messages = [...messages, { id: null, role: 'assistant', content: '' }];
		const assistantIdx = messages.length - 1;
		await scrollToBottom();

		try {
			const { data: { session } } = await supabase.auth.getSession();
			const token = session?.access_token;
			if (!token) {
				error = 'Please sign in first.';
				return;
			}

			// Send the conversation *up to but not including* the assistant
			// placeholder we just added.
			const payloadMessages = messages.slice(0, assistantIdx).map((m) => ({
				role: m.role,
				content: m.content,
			}));

			const res = await fetch('/api/coach', {
				method: 'POST',
				headers: {
					'content-type': 'application/json',
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					messages: payloadMessages,
					plan_id: planId,
					recent_runs_limit: runsLimit,
					mode: opts.mode,
					anchor_message_id: opts.anchorId ?? null,
				}),
			});

			const ct = res.headers.get('content-type') ?? '';
			if (!res.ok || !ct.includes('event-stream')) {
				const j = await res.json().catch(() => ({}));
				if (res.status === 404) {
					error = 'Coach runs as a server endpoint. This deploy uses the static adapter — switch to a server deploy (Vercel/Node) and set ANTHROPIC_API_KEY to enable chat.';
				} else if (res.status === 429) {
					usedToday = j.used ?? (dailyLimit ?? DEFAULT_DAILY_LIMIT);
					if (typeof j.tier === 'string') tier = j.tier;
					if (typeof j.limit === 'number') dailyLimit = j.limit;
					error = j.message ?? `Daily limit reached (${dailyLimit ?? DEFAULT_DAILY_LIMIT} messages). Come back tomorrow!`;
				} else {
					error = j.error ?? `Coach error (${res.status})`;
				}
				// Roll back the placeholders.
				messages = messages.slice(0, opts.userText ? assistantIdx - 1 : assistantIdx);
				return;
			}

			usedToday++;
			await readSse(res, assistantIdx);
		} catch (e) {
			error = e instanceof Error ? e.message : 'network error';
			messages = messages.slice(0, opts.userText ? assistantIdx - 1 : assistantIdx);
		} finally {
			busy = false;
			await loadArchives();
		}
	}

	async function readSse(res: Response, assistantIdx: number) {
		if (!res.body) return;
		const reader = res.body.getReader();
		const decoder = new TextDecoder();
		let buffer = '';
		while (true) {
			const { value, done } = await reader.read();
			if (done) break;
			buffer += decoder.decode(value, { stream: true });
			let breakIdx: number;
			while ((breakIdx = buffer.indexOf('\n\n')) !== -1) {
				const eventBlock = buffer.slice(0, breakIdx);
				buffer = buffer.slice(breakIdx + 2);
				handleSseEvent(eventBlock, assistantIdx);
			}
		}
	}

	function handleSseEvent(block: string, assistantIdx: number) {
		const lines = block.split('\n');
		let event = 'message';
		let data = '';
		for (const line of lines) {
			if (line.startsWith('event:')) event = line.slice(6).trim();
			else if (line.startsWith('data:')) data += line.slice(5).trim();
		}
		if (!data) return;
		let parsed: Record<string, unknown> = {};
		try {
			parsed = JSON.parse(data);
		} catch {
			return;
		}
		if (event === 'meta') {
			const userMessageId = parsed.user_message_id as string | null;
			if (userMessageId) {
				// Stitch the new user-message id onto the most recent
				// non-id'd user bubble (assistant precedes it in messages
				// because we pushed it last).
				const userIdx = assistantIdx - 1;
				const m = messages[userIdx];
				if (m && m.role === 'user' && !m.id) {
					messages[userIdx] = { ...m, id: userMessageId };
				}
			}
			if (typeof parsed.tier === 'string') tier = parsed.tier as 'free' | 'pro';
			const limits = parsed.limits as { daily_limit: number | null } | undefined;
			if (limits && 'daily_limit' in limits) dailyLimit = limits.daily_limit;
		} else if (event === 'token') {
			const text = (parsed.text as string) ?? '';
			const cur = messages[assistantIdx];
			if (cur) {
				messages[assistantIdx] = { ...cur, content: cur.content + text };
			}
			scrollToBottom();
		} else if (event === 'done') {
			const id = parsed.assistant_message_id as string | null;
			if (id) {
				const cur = messages[assistantIdx];
				if (cur) messages[assistantIdx] = { ...cur, id };
			}
			const cache = parsed.cache as Record<string, number> | undefined;
			if (cache) {
				lastCache = {
					read: cache.cache_read_input_tokens ?? 0,
					create: cache.cache_creation_input_tokens ?? 0,
					in: cache.input_tokens ?? 0,
					out: cache.output_tokens ?? 0,
				};
			}
		} else if (event === 'error') {
			error = (parsed.message as string) ?? 'stream failed';
		}
	}

	// ─────────────────────── Bubble actions ───────────────────────

	async function copyMessage(content: string) {
		try {
			await navigator.clipboard.writeText(content);
		} catch (e) {
			console.error('[coach] copy failed', e);
		}
	}

	async function reactTo(messageId: string, reaction: 'up' | 'down') {
		const idx = messages.findIndex((m) => m.id === messageId);
		if (idx === -1) return;
		const cur = messages[idx];
		// Toggle off if pressing the same reaction; otherwise set the new one.
		const next: 'up' | 'down' | null = cur.reaction === reaction ? null : reaction;
		messages[idx] = { ...cur, reaction: next };
		const { error: err } = await supabase
			.from('coach_messages')
			.update({ reaction: next })
			.eq('id', messageId);
		if (err) {
			console.error('[coach] react failed', err);
			messages[idx] = cur; // rollback
		}
	}

	// ─────────────────────── Composer helpers ───────────────────────

	async function scrollToBottom() {
		await tick();
		if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
	}

	const COMPOSER_MAX_PX = 160;

	function autoGrowComposer() {
		if (!composerEl) return;
		composerEl.style.height = 'auto';
		composerEl.style.height = `${Math.min(composerEl.scrollHeight, COMPOSER_MAX_PX)}px`;
	}

	function onComposerKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
			e.preventDefault();
			send();
		}
	}

	$effect(() => {
		if (draft === '') {
			tick().then(() => {
				if (composerEl) composerEl.style.height = '';
			});
		}
	});

	function use(s: string) {
		draft = s;
		tick().then(autoGrowComposer);
	}

	// Sidebar collapses by default — most conversations are single-thread
	// and the chat surface is the priority. Toggle persists through the
	// session via state, not localStorage (per-session is enough).
	let sidebarOpen = $state(false);

	// True when this tab is *itself* mid-request (busy) OR when the
	// persisted thread ends in a user message with no assistant follow-up.
	// The second case happens when the runner reloads mid-stream — the
	// in-flight server request is still running and will write the
	// assistant row when it completes; until then we show the typing
	// indicator and let the realtime subscription pick the reply up.
	let awaitingAssistant = $derived.by(() => {
		if (busy) return true;
		if (viewingArchiveAt != null) return false;
		const last = messages[messages.length - 1];
		return last?.role === 'user' && last.id != null;
	});

	// Realtime subscription — fires when a row is inserted into
	// coach_messages for the active thread (RLS scopes to the caller).
	// Cleared on unmount so we don't leak channels across navigations.
	type SupabaseChannel = { unsubscribe: () => Promise<unknown> };
	let realtimeChannel: SupabaseChannel | null = null;

	function subscribeToThread() {
		if (!cachedUserId) return;
		const channel = supabase
			.channel(`coach_messages:${cachedUserId}:${planId ?? 'no_plan'}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'coach_messages',
					filter: `user_id=eq.${cachedUserId}`,
				},
				(payload: { new: Record<string, unknown> }) => {
					const row = payload.new as {
						id: string;
						role: 'user' | 'assistant';
						content: string;
						reaction: 'up' | 'down' | null;
						plan_id: string | null;
						archived_at: string | null;
					};
					// Filter to the active thread for the current plan-scope.
					if (row.archived_at != null) return;
					const expectedPlan = planId ?? null;
					if ((row.plan_id ?? null) !== expectedPlan) return;
					// Skip rows we already have (the same tab inserted them).
					if (messages.some((m) => m.id === row.id)) return;
					messages = [
						...messages,
						{ id: row.id, role: row.role, content: row.content, reaction: row.reaction },
					];
					scrollToBottom();
				},
			)
			.subscribe();
		realtimeChannel = channel as unknown as SupabaseChannel;
	}

	onDestroy(() => {
		if (realtimeChannel) {
			realtimeChannel.unsubscribe();
			realtimeChannel = null;
		}
	});
</script>

{#if locked}
	<ProGate feature="ai_coach" />
{:else}
<div class="shell">
	<aside class="sidebar" class:collapsed={!sidebarOpen} aria-hidden={!sidebarOpen}>
		<div class="sidebar-header">
			<button
				type="button"
				class="header-btn primary-btn"
				onclick={() => (messages.length > 0 && viewingArchiveAt == null) ? (showArchiveConfirm = true) : (viewingArchiveAt && backToActive())}
				disabled={messages.length === 0 && viewingArchiveAt == null}
				title="Archive the current conversation and start a fresh one"
			>
				<span class="material-symbols">add</span>
				New chat
			</button>
		</div>

		<nav class="thread-list" aria-label="Conversations">
			<button
				type="button"
				class="thread-row"
				class:active={viewingArchiveAt == null}
				onclick={() => viewingArchiveAt && backToActive()}
			>
				<span class="thread-title">{activeThreadTitle}</span>
				<span class="thread-meta">Active{messages.length > 0 ? ` · ${messages.length}` : ''}</span>
			</button>
			{#each archives as a (a.archived_at)}
				<div
					class="thread-row archive-row"
					class:active={a.archived_at === viewingArchiveAt}
					role="button"
					tabindex="0"
					onclick={() => viewArchive(a.archived_at)}
					onkeydown={(e) => { if (e.key === 'Enter') viewArchive(a.archived_at); }}
				>
					<span class="thread-title">{a.title}</span>
					<span class="thread-meta">{formatArchiveDate(a.archived_at)} · {a.message_count}</span>
					<button
						type="button"
						class="thread-delete"
						title="Delete forever"
						aria-label="Delete archive"
						onclick={(e) => deleteArchive(a.archived_at, e)}
					>
						<span class="material-symbols">close</span>
					</button>
				</div>
			{/each}
		</nav>
	</aside>

	<div class="chat">
		<header>
			<div class="header-row">
				<h3>
					<button
						type="button"
						class="sidebar-toggle"
						onclick={() => (sidebarOpen = !sidebarOpen)}
						title={sidebarOpen ? 'Hide conversations' : 'Show conversations'}
						aria-label={sidebarOpen ? 'Hide conversations' : 'Show conversations'}
						aria-expanded={sidebarOpen}
					>
						<span class="material-symbols">{sidebarOpen ? 'menu_open' : 'menu'}</span>
						{#if archives.length > 0 && !sidebarOpen}
							<span class="sidebar-toggle-count">{archives.length + 1}</span>
						{/if}
					</button>
					Coach
					<span class="sub">
						· Second opinion on your {hasPlan ? 'plan and runs' : 'recent runs'}. Not medical advice.
					</span>
				</h3>
				{#if contextSummary}
					{@const c = contextSummary}
					<div class="context-strip" title="What the coach has loaded for this conversation">
						{#if c.planName}
							<span class="chip">
								<span class="material-symbols">calendar_month</span>
								{c.planName}{#if c.planWeeks}<span class="chip-meta"> · {c.planWeeks}w</span>{/if}
							</span>
						{:else}
							<span class="chip chip-muted">
								<span class="material-symbols">calendar_month</span>
								No plan
							</span>
						{/if}
						<label class="chip chip-select" title="How many recent runs to feed the coach">
							<span class="material-symbols">directions_run</span>
							{#if c.runCount === 0}
								<span>No runs</span>
							{:else}
								<span>Last</span>
								<select class="chip-select-input" bind:value={runsLimit} aria-label="Recent runs to include">
									{#each RUN_LIMIT_OPTIONS as n}
										<option value={n}>{n}</option>
									{/each}
								</select>
							{/if}
						</label>
						{#if c.hrZonesLoaded}
							<span class="chip" title="HR zones loaded from your settings">
								<span class="material-symbols">monitor_heart</span>
							</span>
						{/if}
						{#if c.weeklyGoalMetres}
							<span class="chip" title="Weekly mileage goal">
								<span class="material-symbols">flag</span>
								{fmtKm(c.weeklyGoalMetres)}
							</span>
						{/if}
					</div>
				{/if}
			</div>
		</header>

		{#if viewingArchiveAt}
			<div class="archive-banner">
				<span class="material-symbols">history</span>
				<span>Viewing archive · {formatArchiveDate(viewingArchiveAt)} · read-only</span>
				<button type="button" class="header-btn" onclick={backToActive}>
					<span class="material-symbols">arrow_back</span>
					Back to active
				</button>
			</div>
		{/if}

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
			{#each messages as m, i (i)}
				<div class="bubble" class:user={m.role === 'user'}>
					{#if m.role === 'user' && editingId === m.id && m.id != null}
						<div class="edit-form">
							<textarea bind:value={editingDraft} rows="3"></textarea>
							<div class="edit-actions">
								<button type="button" class="btn-primary" onclick={commitEdit} disabled={!editingDraft.trim()}>
									Save & resend
								</button>
								<button type="button" class="header-btn" onclick={cancelEdit}>Cancel</button>
							</div>
						</div>
					{:else if m.role === 'assistant'}
						{#if !m.content && awaitingAssistant && i === messages.length - 1}
							<div class="typing-dots" aria-label="Coach is thinking">
								<span></span><span></span><span></span>
							</div>
						{:else}
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<div class="md">{@html renderMarkdown(m.content)}</div>
						{/if}
					{:else}
						<span>{m.content}</span>
					{/if}
					{#if !viewingArchiveAt && m.id && !(awaitingAssistant && i === messages.length - 1)}
						<div class="bubble-actions">
							<button
								type="button"
								class="bubble-action"
								title="Copy to clipboard"
								aria-label="Copy"
								onclick={() => copyMessage(m.content)}
							>
								<span class="material-symbols">content_copy</span>
							</button>
							{#if m.role === 'assistant'}
								<button
									type="button"
									class="bubble-action"
									title="Regenerate this reply"
									aria-label="Regenerate"
									onclick={() => regenerate(m.id!)}
								>
									<span class="material-symbols">refresh</span>
								</button>
								<button
									type="button"
									class="bubble-action"
									class:active={m.reaction === 'up'}
									title="Helpful"
									aria-label="Thumbs up"
									aria-pressed={m.reaction === 'up'}
									onclick={() => reactTo(m.id!, 'up')}
								>
									<span class="material-symbols">thumb_up</span>
								</button>
								<button
									type="button"
									class="bubble-action"
									class:active={m.reaction === 'down'}
									title="Not useful"
									aria-label="Thumbs down"
									aria-pressed={m.reaction === 'down'}
									onclick={() => reactTo(m.id!, 'down')}
								>
									<span class="material-symbols">thumb_down</span>
								</button>
							{:else}
								<button
									type="button"
									class="bubble-action"
									title="Edit and resend"
									aria-label="Edit"
									onclick={() => startEdit(m.id!, m.content)}
								>
									<span class="material-symbols">edit</span>
								</button>
							{/if}
						</div>
					{/if}
				</div>
			{/each}
			{#if awaitingAssistant && messages[messages.length - 1]?.role === 'user'}
				<div class="bubble">
					<div class="typing-dots" aria-label="Coach is thinking">
						<span></span><span></span><span></span>
					</div>
				</div>
			{/if}
		</div>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		{#if viewingArchiveAt}
			<!-- Composer suppressed in archive view. -->
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
				<textarea
					bind:this={composerEl}
					placeholder={busy ? 'Type your next question while the coach replies…' : 'Ask about today, pace, adherence… (Shift+Enter for newline)'}
					bind:value={draft}
					oninput={autoGrowComposer}
					onkeydown={onComposerKeydown}
					rows="1"
					maxlength="600"
				></textarea>
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
				<span class="cache-note" title="Saved to your account and synced across devices.">
					<span class="material-symbols save-icon">cloud_done</span>
					Synced
				</span>
			{/if}
		</div>
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
	.shell {
		display: flex;
		gap: 0;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		/* Default height for embedded hosts that don't set a height. The
		   /coach route overrides this with `height: 100%` via :global so
		   the chat fills the viewport. */
		height: 36rem;
		min-height: 0;
	}
	.sidebar {
		flex: 0 0 16rem;
		display: flex;
		flex-direction: column;
		background: var(--color-bg-secondary);
		border-right: 1px solid var(--color-border);
		min-height: 0;
		overflow: hidden;
		transition: flex-basis var(--transition-fast);
	}
	.sidebar.collapsed {
		flex-basis: 0;
		border-right: none;
	}
	.sidebar-header {
		display: flex;
		gap: 0.4rem;
		padding: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
	}
	.thread-list {
		flex: 1;
		overflow-y: auto;
		padding: 0.4rem;
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
	}
	.thread-row {
		display: grid;
		grid-template-columns: 1fr auto;
		grid-template-rows: auto auto;
		align-items: start;
		gap: 0.05rem 0.4rem;
		padding: 0.5rem 0.6rem;
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-md);
		text-align: left;
		color: inherit;
		font: inherit;
		cursor: pointer;
		min-width: 0;
		position: relative;
	}
	.thread-row:hover {
		background: var(--color-surface);
	}
	.thread-row.active {
		background: var(--color-surface);
		border-color: var(--color-primary);
	}
	.thread-title {
		grid-column: 1;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		min-width: 0;
	}
	.thread-meta {
		grid-column: 1 / -1;
		grid-row: 2;
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
	}
	.thread-delete {
		grid-column: 2;
		grid-row: 1;
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		padding: 0 0.2rem;
		cursor: pointer;
		opacity: 0;
		transition: opacity var(--transition-fast);
		border-radius: var(--radius-sm);
	}
	.archive-row:hover .thread-delete,
	.archive-row:focus-within .thread-delete {
		opacity: 1;
	}
	.thread-delete:hover { color: var(--color-danger); }
	.thread-delete .material-symbols { font-size: 1rem; line-height: 1; }
	.sidebar-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.2rem 0.4rem;
		cursor: pointer;
		color: var(--color-text-secondary);
		font: inherit;
	}
	.sidebar-toggle:hover { color: var(--color-primary); border-color: var(--color-primary); }
	.sidebar-toggle .material-symbols { font-size: 1.1rem; line-height: 1; }
	.sidebar-toggle-count {
		min-width: 1.2rem;
		padding: 0 0.3rem;
		background: var(--color-bg-tertiary);
		border-radius: 9999px;
		font-size: 0.7rem;
		font-weight: 700;
		text-align: center;
		line-height: 1.4;
	}
	.chat {
		flex: 1;
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
	}
	header {
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
	}
	.header-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	header h3 {
		font-size: 0.95rem;
		font-weight: 600;
		margin: 0;
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
	}
	header .sub {
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
		font-weight: 400;
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
	.header-btn:disabled { opacity: 0.5; cursor: not-allowed; }
	.header-btn.primary-btn {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
		flex: 1;
	}
	.header-btn.primary-btn:hover { background: var(--color-primary-dark, var(--color-primary)); filter: brightness(0.95); }
	.header-btn .material-symbols { font-size: 0.95rem; line-height: 1; }

	.context-strip { display: flex; flex-wrap: wrap; align-items: center; gap: 0.3rem; }
	.chip {
		display: inline-flex; align-items: center; gap: 0.25rem; padding: 0.15rem 0.5rem;
		background: var(--color-primary-light); color: var(--color-primary); border-radius: 999px;
		font-size: 0.72rem; font-weight: 500; line-height: 1.3;
	}
	.chip-muted { background: var(--color-bg-tertiary); color: var(--color-text-tertiary); }
	.chip .material-symbols { font-size: 0.85rem; line-height: 1; }
	.chip-meta { color: inherit; opacity: 0.75; font-weight: 400; }
	.chip-select { cursor: pointer; padding-right: 0.4rem; }
	.chip-select-input {
		appearance: none; background: transparent; border: none; color: inherit; font: inherit;
		font-weight: 600; padding: 0 0.15rem; cursor: pointer;
	}

	.scroll {
		flex: 1; overflow-y: auto; padding: var(--space-md);
		display: flex; flex-direction: column; gap: 0.6rem;
	}
	.bubble {
		/* Cap at a comfortable reading measure rather than a percentage —
		   on a wide viewport, 85% becomes a wall-of-text line. ~64ch
		   keeps prose readable while still letting the chat fill the
		   horizontal space with whitespace on the right. */
		max-width: min(85%, 64ch);
		padding: 0.55rem 0.8rem;
		background: var(--color-bg-secondary); border-radius: var(--radius-md);
		white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word;
		align-self: flex-start; position: relative;
	}
	.bubble.user {
		background: var(--color-primary-light); color: var(--color-primary);
		align-self: flex-end; white-space: pre-wrap;
	}
	.bubble-actions {
		display: flex; gap: 0.15rem;
		opacity: 0; transition: opacity var(--transition-fast);
		margin-top: 0.4rem; margin-left: -0.2rem;
	}
	.bubble:hover .bubble-actions, .bubble:focus-within .bubble-actions { opacity: 1; }
	.bubble-action {
		background: transparent; border: 1px solid transparent; border-radius: var(--radius-sm);
		padding: 0.15rem 0.3rem; cursor: pointer; color: var(--color-text-tertiary);
		display: inline-flex; align-items: center; line-height: 1;
	}
	.bubble-action:hover { color: var(--color-primary); border-color: var(--color-border); }
	.bubble-action.active { color: var(--color-primary); }
	.bubble.user .bubble-action.active { color: var(--color-primary); opacity: 1; }
	.bubble-action .material-symbols { font-size: 0.95rem; line-height: 1; }

	.typing-dots {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.4rem 0.1rem;
	}
	.typing-dots span {
		width: 0.4rem;
		height: 0.4rem;
		border-radius: 50%;
		background: var(--color-text-tertiary);
		opacity: 0.4;
		animation: typing-bounce 1.3s infinite ease-in-out;
	}
	.typing-dots span:nth-child(2) { animation-delay: 0.18s; }
	.typing-dots span:nth-child(3) { animation-delay: 0.36s; }
	@keyframes typing-bounce {
		0%, 60%, 100% { opacity: 0.35; transform: translateY(0); }
		30%           { opacity: 1;    transform: translateY(-3px); }
	}
	@media (prefers-reduced-motion: reduce) {
		.typing-dots span { animation: none; opacity: 0.7; }
	}

	.md :global(p) { margin: 0 0 0.4rem; }
	.md :global(p:last-child) { margin-bottom: 0; }
	.md :global(ul), .md :global(ol) { margin: 0.2rem 0 0.4rem 1.2rem; padding: 0; }
	.md :global(li) { margin-bottom: 0.15rem; }
	.md :global(strong) { font-weight: 700; }
	.md :global(em) { font-style: italic; }
	.md :global(code) {
		background: color-mix(in srgb, var(--color-text) 8%, transparent);
		padding: 0 0.25rem; border-radius: 3px;
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.85em;
	}
	.md :global(pre) {
		background: var(--color-bg-tertiary); padding: 0.6rem 0.8rem;
		border-radius: var(--radius-md); overflow-x: auto;
		margin: 0.4rem 0;
	}
	.md :global(pre) :global(code) { background: transparent; padding: 0; font-size: 0.85em; }
	.md :global(a) { color: var(--color-primary); text-decoration: underline; }
	.md :global(blockquote) {
		border-left: 3px solid var(--color-border); padding-left: 0.8rem;
		margin: 0.4rem 0; color: var(--color-text-secondary);
	}

	.edit-form { display: flex; flex-direction: column; gap: 0.4rem; min-width: 16rem; }
	.edit-form textarea {
		background: var(--color-surface); border: 1px solid var(--color-border);
		border-radius: var(--radius-sm); padding: 0.4rem 0.5rem;
		color: inherit; font: inherit; resize: vertical;
	}
	.edit-actions { display: flex; gap: 0.4rem; justify-content: flex-end; }

	.primer { color: var(--color-text-secondary); }
	.suggestions { display: flex; flex-direction: column; gap: 0.4rem; margin-top: 0.6rem; }
	.suggest {
		text-align: left; background: var(--color-bg-secondary);
		border: 1px solid var(--color-border); padding: 0.45rem 0.7rem;
		border-radius: var(--radius-md); color: inherit; font: inherit; cursor: pointer;
	}
	.suggest:hover { border-color: var(--color-primary); color: var(--color-primary); }

	.composer {
		display: flex; gap: 0.5rem; padding: var(--space-sm);
		border-top: 1px solid var(--color-border); align-items: flex-end;
	}
	.composer textarea {
		flex: 1; background: var(--color-bg-secondary);
		border: 1px solid var(--color-border); border-radius: var(--radius-md);
		padding: 0.5rem 0.75rem; color: inherit; font: inherit; line-height: 1.4;
		resize: none; min-height: 2.4rem; max-height: 10rem; overflow-y: auto;
	}
	.error {
		color: var(--color-danger); background: var(--color-danger-light);
		padding: 0.5rem 0.8rem; margin: 0.6rem; border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
	.usage-bar {
		display: flex; justify-content: space-between; align-items: center;
		padding: var(--space-xs) var(--space-sm);
		font-size: 0.72rem; color: var(--color-text-tertiary);
	}
	.usage-count { font-weight: 500; display: inline-flex; align-items: center; gap: 0.4rem; }
	.tier-badge {
		font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em;
		padding: 0.1rem 0.4rem; border-radius: 9999px;
	}
	.tier-pro { background: rgba(79, 70, 229, 0.12); color: var(--color-primary); }
	.tier-free { background: var(--color-bg-tertiary); color: var(--color-text-secondary); }
	.cache-note { font-size: 0.72rem; color: var(--color-text-tertiary); }
	.save-icon { font-size: 0.85rem; line-height: 1; vertical-align: -2px; margin-right: 0.15rem; }
	.limit-bar {
		display: flex; align-items: center; gap: 0.5rem;
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08); border: 1px solid rgba(239, 68, 68, 0.2);
		border-radius: var(--radius-md); margin: 0 var(--space-sm) var(--space-sm);
		font-size: 0.82rem; color: var(--color-text-secondary);
	}
	.limit-bar .material-symbols { font-size: 1.1rem; color: var(--color-danger); }
	.archive-banner {
		display: flex; align-items: center; gap: 0.5rem;
		padding: 0.5rem 0.8rem; margin: 0 var(--space-sm);
		background: color-mix(in srgb, var(--color-primary) 8%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 25%, var(--color-border));
		border-radius: var(--radius-md); font-size: 0.8rem; color: var(--color-text-secondary);
	}
	.archive-banner > span:nth-child(2) { flex: 1; }
	.archive-banner .material-symbols { font-size: 1rem; color: var(--color-primary); }

	.material-symbols { font-family: 'Material Symbols Outlined'; }

	@media (max-width: 48rem) {
		.sidebar { flex-basis: 12rem; }
		.bubble { max-width: 92%; }
	}
</style>
