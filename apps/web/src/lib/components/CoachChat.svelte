<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { supabase } from '$lib/supabase';
	import { isLocked } from '$lib/features';
	import ProGate from '$lib/components/ProGate.svelte';

	interface Props {
		planId: string | null;
	}
	let { planId }: Props = $props();
	let locked = $derived(isLocked('ai_coach'));

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

	onMount(async () => {
		const { data: { session } } = await supabase.auth.getSession();
		if (!session) return;
		const { data } = await supabase.rpc('get_coach_usage', {
			p_user_id: session.user.id,
		});
		if (typeof data === 'number') usedToday = data;
	});

	const SUGGESTIONS = [
		'Should I run tomorrow or take a rest day?',
		'Am I on track for my goal time?',
		"Why does this week's long run matter?",
		"What should I focus on for today's workout?"
	];

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
			Second opinion on your plan and runs. Not a replacement for a human
			coach — doesn't generate plans or give medical advice.
		</p>
	</header>

	<div class="scroll" bind:this={scrollEl}>
		{#if messages.length === 0}
			<div class="primer">
				<p>Ask about today's workout, your pace, or how recent runs compare to plan.</p>
				<div class="suggestions">
					{#each SUGGESTIONS as s}
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
		height: 36rem;
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
	.btn-primary {
		background: var(--color-primary);
		color: var(--color-bg);
		padding: 0.5rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: none;
		cursor: pointer;
	}
	.btn-primary:disabled {
		opacity: 0.5;
		cursor: not-allowed;
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
