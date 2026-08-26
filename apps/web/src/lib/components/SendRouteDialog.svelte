<script lang="ts">
	import Modal from './Modal.svelte';
	import { m as tr } from '$lib/i18n/store.svelte';
	import { initial } from '$lib/format/avatar';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchFollowers, fetchFollowing, sendDm } from '$lib/core/data';
	import {
		dmRecipientCandidates,
		filterDmRecipients,
		type DmRecipient
	} from '$lib/social/dm_recipients';

	interface Props {
		open: boolean;
		/// The public /share/route/[id] URL, already made reachable by the
		/// host's ensure-public step. Sent verbatim as the message body —
		/// route_direct_share.md v1 carries no typed attachment.
		shareUrl: string;
		onclose: () => void;
	}

	let { open, shareUrl, onclose }: Props = $props();

	let loading = $state(false);
	let loadFailed = $state(false);
	let candidates = $state<DmRecipient[]>([]);
	let query = $state('');
	let sendingTo = $state<string | null>(null);
	let sendError = $state<string | null>(null);
	let sentTo = $state<DmRecipient | null>(null);

	const shown = $derived(filterDmRecipients(candidates, query));

	// Mirrors the /messages thread-list latch: the fetch is driven off `open`
	// rather than a mount-time gate, because auth.ready() can resolve on its
	// safety timeout before the session settles.
	let requested = false;
	$effect(() => {
		if (!open) {
			requested = false;
			loading = false;
			loadFailed = false;
			candidates = [];
			query = '';
			sendingTo = null;
			sendError = null;
			sentTo = null;
			return;
		}
		if (requested) return;
		requested = true;
		void load();
	});

	async function load() {
		const me = auth.user?.id;
		if (!me) return;
		loading = true;
		loadFailed = false;
		try {
			const [followers, following] = await Promise.all([fetchFollowers(me), fetchFollowing(me)]);
			candidates = dmRecipientCandidates(followers, following, me);
		} catch {
			// Never degrade to an empty list: "you have nobody to send to" and
			// "we couldn't find out who you could send to" are different
			// answers, and only one of them is worth acting on.
			candidates = [];
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	function retry() {
		requested = true;
		void load();
	}

	async function send(recipient: DmRecipient) {
		if (sendingTo) return;
		sendingTo = recipient.id;
		sendError = null;
		try {
			await sendDm(recipient.id, shareUrl);
			sentTo = recipient;
		} catch (e) {
			sendError = e instanceof Error ? e.message : `${e}`;
		} finally {
			sendingTo = null;
		}
	}

	function nameOf(r: DmRecipient): string {
		return r.displayName ?? tr('messages.runnerFallback');
	}

	function relationLabel(r: DmRecipient): string {
		if (r.relation === 'mutual') return tr('routeDetail.sendDm.relationMutual');
		if (r.relation === 'follows_you') return tr('routeDetail.sendDm.relationFollowsYou');
		return tr('routeDetail.sendDm.relationYouFollow');
	}
</script>

<Modal {open} {onclose} title={tr('routeDetail.sendDm.title')} narrow data-testid="send-route-dialog">
	{#if sentTo}
		<p class="sent" data-testid="send-route-sent">
			{tr('routeDetail.sendDm.sent', { name: nameOf(sentTo) })}
		</p>
		<div class="actions">
			<a class="btn btn-primary btn-sm" href={`/messages/${sentTo.id}`}>
				{tr('routeDetail.sendDm.openThread')}
			</a>
			<button type="button" class="btn btn-outline btn-sm" onclick={onclose}>
				{tr('routeDetail.sendDm.done')}
			</button>
		</div>
	{:else}
		<p class="intro">{tr('routeDetail.sendDm.intro')}</p>
		<p class="note">{tr('routeDetail.sendDm.linkNote')}</p>

		{#if sendError}
			<p class="send-error" role="alert" data-testid="send-route-error">
				{tr('routeDetail.sendDm.sendFailed', { error: sendError })}
			</p>
		{/if}

		{#if loading}
			<p class="muted">{tr('shell.loading')}</p>
		{:else if loadFailed}
			<p class="muted" role="alert" data-testid="send-route-load-error">
				{tr('routeDetail.sendDm.loadFailed')}
				<button type="button" class="btn btn-secondary btn-sm" onclick={retry}>
					{tr('messages.retry')}
				</button>
			</p>
		{:else if candidates.length === 0}
			<p class="muted">{tr('routeDetail.sendDm.empty')}</p>
		{:else}
			<label class="search">
				<span class="material-symbols" aria-hidden="true">search</span>
				<input
					type="text"
					bind:value={query}
					placeholder={tr('routeDetail.sendDm.searchPlaceholder')}
					aria-label={tr('routeDetail.sendDm.searchPlaceholder')}
					data-testid="send-route-search"
				/>
			</label>
			{#if shown.length === 0}
				<p class="muted">{tr('routeDetail.sendDm.noMatches')}</p>
			{:else}
				<ul>
					{#each shown as r (r.id)}
						<li>
							<button
								type="button"
								class="recipient"
								disabled={sendingTo !== null}
								onclick={() => send(r)}
							>
								<span class="avatar" aria-hidden="true">{initial(r.displayName)}</span>
								<span class="who">
									<strong>{nameOf(r)}</strong>
									<span class="relation">{relationLabel(r)}</span>
								</span>
								<span class="cta">
									{sendingTo === r.id
										? tr('routeDetail.sendDm.sending')
										: tr('routeDetail.sendDm.send')}
								</span>
							</button>
						</li>
					{/each}
				</ul>
			{/if}
		{/if}
	{/if}
</Modal>

<style>
	.intro {
		margin: 0 0 var(--space-xs);
	}
	.note,
	.muted {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.note {
		margin: 0 0 var(--space-md);
	}
	.send-error {
		color: var(--color-danger-text);
		margin: 0 0 var(--space-sm);
	}
	.search {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0 var(--space-sm);
		margin-block-end: var(--space-sm);
	}
	.search input {
		flex: 1 1 auto;
		border: none;
		background: none;
		color: inherit;
		padding: var(--space-sm) 0;
	}
	.search input:focus {
		outline: none;
	}
	.search input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.recipient:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
		max-height: 22rem;
		overflow-y: auto;
	}
	.recipient {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		inline-size: 100%;
		text-align: start;
		background: none;
		border: none;
		border-radius: var(--radius-md);
		padding: var(--space-sm);
		color: inherit;
		cursor: pointer;
	}
	.recipient:hover:not(:disabled) {
		background: var(--color-bg-secondary);
	}
	.recipient:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.avatar {
		inline-size: 2rem;
		block-size: 2rem;
		border-radius: 50%;
		background: var(--color-bg-secondary);
		display: grid;
		place-items: center;
		flex: 0 0 auto;
	}
	.who {
		display: flex;
		flex-direction: column;
		min-inline-size: 0;
		flex: 1 1 auto;
	}
	.who strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.relation {
		color: var(--color-text-secondary);
		font-size: 0.8rem;
	}
	.cta {
		color: var(--color-primary);
		font-size: 0.85rem;
		flex: 0 0 auto;
	}
	.sent {
		margin: 0 0 var(--space-md);
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
	}
</style>
