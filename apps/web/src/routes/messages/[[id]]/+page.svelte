<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { m as tr } from '$lib/i18n/store.svelte';
	import { onMount } from 'svelte';
	import { initial } from '$lib/format/avatar';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchDmThreads,
		fetchDmThread,
		sendDm,
		markDmThreadRead,
		type DmThread,
		type DirectMessage
	} from '$lib/core/data';

	let ready = $state(false);
	let threads = $state<DmThread[]>([]);
	let messages = $state<DirectMessage[]>([]);
	let draft = $state('');
	let sending = $state(false);
	let loadingThread = $state(false);
	let sendError = $state<string | null>(null);

	let activeId = $derived($page.params.id ?? null);
	let me = $derived(auth.user?.id ?? null);
	let activeThread = $derived(threads.find((t) => t.partnerId === activeId) ?? null);

	onMount(async () => {
		await auth.ready();
		ready = true;
		if (auth.user) threads = await fetchDmThreads();
	});

	// Load the open conversation whenever the route param changes.
	$effect(() => {
		const id = activeId;
		if (!id || !auth.user) {
			messages = [];
			return;
		}
		void openThread(id);
	});

	async function openThread(id: string) {
		loadingThread = true;
		try {
			messages = await fetchDmThread(id);
			await markDmThreadRead(id);
			// Zero the unread badge locally without a full refetch.
			threads = threads.map((t) => (t.partnerId === id ? { ...t, unread: 0 } : t));
		} finally {
			loadingThread = false;
		}
	}

	async function send() {
		const id = activeId;
		if (!id || !draft.trim() || sending) return;
		sending = true;
		sendError = null;
		try {
			const msg = await sendDm(id, draft);
			messages = [...messages, msg];
			draft = '';
			threads = await fetchDmThreads();
		} catch (e) {
			sendError = e instanceof Error ? e.message : tr('messages.sendFailed');
		} finally {
			sending = false;
		}
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			void send();
		}
	}

	function fmtTime(iso: string): string {
		return new Date(iso).toLocaleString(activeFormatLocale(), {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}

</script>

<svelte:head><title>{tr('messages.pageTitle')}</title></svelte:head>

<div class="page">
	<h1 class="visually-hidden">{tr('messages.heading')}</h1>
	{#if !ready}
		<p class="muted">{tr('shell.loading')}</p>
	{:else if !auth.user}
		<p class="muted">{tr('messages.signInPrompt')}</p>
	{:else}
		<div class="layout">
			<aside class="threads" class:has-active={activeId}>
				<header class="pane-head"><h2>{tr('messages.heading')}</h2></header>
				{#if threads.length === 0}
					<p class="muted empty">{tr('messages.emptyThreads')}</p>
				{:else}
					<ul>
						{#each threads as t (t.partnerId)}
							<li>
								<a
									class="thread"
									class:active={t.partnerId === activeId}
									href={`/messages/${t.partnerId}`}
								>
									<span class="avatar">{initial(t.partnerName)}</span>
									<span class="thread-body">
										<span class="thread-top">
											<strong>{t.partnerName ?? tr('messages.runnerFallback')}</strong>
											{#if t.unread > 0}<span class="badge">{t.unread}</span>{/if}
										</span>
										<span class="preview">{t.lastFromMe ? tr('messages.youPrefix') : ''}{t.lastBody}</span>
									</span>
								</a>
							</li>
						{/each}
					</ul>
				{/if}
			</aside>

			<section class="conversation" class:has-active={activeId}>
				{#if !activeId}
					<p class="muted center">{tr('messages.pickConversation')}</p>
				{:else}
					<header class="pane-head conv-head">
						<a class="back" href="/messages" aria-label={tr('messages.backAria')}>←</a>
						<a class="who" href={`/u/${activeId}`}>
							{activeThread?.partnerName ?? tr('messages.runnerFallback')}
						</a>
					</header>
					<div class="messages">
						{#if loadingThread}
							<p class="muted center">{tr('shell.loading')}</p>
						{:else if messages.length === 0}
							<p class="muted center">{tr('messages.emptyConversation')}</p>
						{:else}
							{#each messages as m (m.id)}
								<div class="bubble" class:mine={m.sender_id === me}>
									<span class="text">{m.body}</span>
									<span class="when">{fmtTime(m.created_at)}</span>
								</div>
							{/each}
						{/if}
					</div>
					{#if sendError}<p class="send-error" role="alert">{sendError}</p>{/if}
					<div class="composer">
						<textarea
							bind:value={draft}
							onkeydown={onKeydown}
							placeholder={tr('messages.composerPlaceholder')}
							rows="1"
							maxlength="4000"
						></textarea>
						<button class="btn btn-primary" onclick={send} disabled={sending || !draft.trim()}>
							{sending ? '…' : tr('messages.send')}
						</button>
					</div>
				{/if}
			</section>
		</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-lg) var(--space-2xl);
		height: calc(100vh - var(--app-header-h, 0px));
		display: flex;
		flex-direction: column;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.center {
		text-align: center;
		margin: auto;
	}
	.layout {
		display: grid;
		grid-template-columns: 20rem 1fr;
		gap: var(--space-lg);
		flex: 1 1 auto;
		min-height: 0;
	}
	.threads,
	.conversation {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
		min-height: 0;
		overflow: hidden;
	}
	.pane-head {
		padding: var(--space-md) var(--space-lg);
		border-bottom: 1px solid var(--color-border);
	}
	.pane-head h2 {
		margin: 0;
		font-size: 1rem;
	}
	.threads ul {
		list-style: none;
		margin: 0;
		padding: 0;
		overflow-y: auto;
	}
	.thread {
		display: flex;
		gap: 0.6rem;
		align-items: center;
		padding: var(--space-sm) var(--space-lg);
		text-decoration: none;
		color: var(--color-text);
		border-bottom: 1px solid var(--color-border);
	}
	.thread:hover,
	.thread.active {
		background: var(--color-bg-secondary);
	}
	.avatar {
		flex: 0 0 auto;
		width: 2.2rem;
		height: 2.2rem;
		border-radius: 50%;
		background: var(--color-primary);
		color: var(--color-bg);
		display: grid;
		place-items: center;
		font-weight: 700;
	}
	.thread-body {
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.thread-top {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.badge {
		background: var(--color-primary);
		color: var(--color-bg);
		border-radius: 999px;
		font-size: 0.7rem;
		padding: 0.05rem 0.4rem;
		font-weight: 700;
	}
	.preview {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.conv-head {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.conv-head .who {
		font-weight: 700;
		color: var(--color-text);
		text-decoration: none;
	}
	.back {
		display: none;
		text-decoration: none;
		color: var(--color-text-secondary);
		font-size: 1.2rem;
	}
	.messages {
		flex: 1 1 auto;
		overflow-y: auto;
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.bubble {
		max-width: 70%;
		padding: 0.5rem 0.75rem;
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		align-self: flex-start;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.bubble.mine {
		align-self: flex-end;
		background: var(--color-primary);
		color: var(--color-bg);
	}
	.bubble .when {
		font-size: 0.65rem;
		opacity: 0.7;
	}
	.send-error {
		color: var(--color-danger);
		font-size: 0.8rem;
		padding: 0 var(--space-lg);
		margin: 0;
	}
	.composer {
		display: flex;
		gap: 0.5rem;
		padding: var(--space-md) var(--space-lg);
		border-top: 1px solid var(--color-border);
	}
	.composer textarea {
		flex: 1 1 auto;
		resize: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.5rem 0.7rem;
		font: inherit;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.empty {
		padding: var(--space-lg);
	}

	@media (max-width: 48rem) {
		.layout {
			grid-template-columns: 1fr;
		}
		/* On narrow screens show one pane at a time. */
		.threads.has-active {
			display: none;
		}
		.conversation:not(.has-active) {
			display: none;
		}
		.back {
			display: inline;
		}
	}
</style>
