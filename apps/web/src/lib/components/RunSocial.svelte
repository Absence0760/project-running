<script lang="ts">
	import { onMount } from 'svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import { formatRelativeTime } from '$lib/format/time';
	import { currentLocale, m as t } from '$lib/i18n/store.svelte';
	import {
		fetchKudosForRun,
		giveKudos,
		rescindKudos,
		fetchRunComments,
		postRunComment,
		deleteRunComment,
		type RunKudosSummary,
		type RunCommentWithAuthor,
	} from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import ReportDialog from '$lib/components/ReportDialog.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';

	interface Props {
		runId: string;
		runOwnerId: string;
	}
	let { runId, runOwnerId }: Props = $props();

	let reportCommentId = $state<string | null>(null);
	let confirmDeleteCommentId = $state<string | null>(null);
	let deletingComment = $state(false);

	let kudos = $state<RunKudosSummary>({ count: 0, viewer_has_kudos: false });
	let comments = $state<RunCommentWithAuthor[]>([]);
	let loading = $state(true);
	let kudosBusy = $state(false);
	let draftBody = $state('');
	let posting = $state(false);
	let replyTo = $state<string | null>(null);
	let replyBody = $state('');

	let isOwn = $derived(auth.user?.id === runOwnerId);

	async function load() {
		loading = true;
		const [k, c] = await Promise.all([fetchKudosForRun(runId), fetchRunComments(runId)]);
		kudos = k;
		comments = c;
		loading = false;
	}

	onMount(load);

	async function toggleKudos() {
		if (!auth.loggedIn || isOwn) return;
		kudosBusy = true;
		try {
			if (kudos.viewer_has_kudos) {
				await rescindKudos(runId);
				kudos = { count: Math.max(kudos.count - 1, 0), viewer_has_kudos: false };
			} else {
				await giveKudos(runId);
				kudos = { count: kudos.count + 1, viewer_has_kudos: true };
			}
		} catch (e) {
			showToast(t('runSocial.kudosUpdateFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			kudosBusy = false;
		}
	}

	async function submitComment() {
		const body = draftBody.trim();
		if (!body || !auth.loggedIn) return;
		posting = true;
		try {
			await postRunComment({ run_id: runId, body });
			draftBody = '';
			await load();
		} catch (e) {
			showToast(t('runSocial.commentPostFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			posting = false;
		}
	}

	async function submitReply(parentId: string) {
		const body = replyBody.trim();
		if (!body || !auth.loggedIn) return;
		posting = true;
		try {
			await postRunComment({ run_id: runId, body, parent_comment_id: parentId });
			replyBody = '';
			replyTo = null;
			await load();
		} catch (e) {
			showToast(t('runSocial.replyPostFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			posting = false;
		}
	}

	async function removeComment() {
		const commentId = confirmDeleteCommentId;
		if (!commentId || deletingComment) return;
		deletingComment = true;
		try {
			await deleteRunComment(commentId);
			confirmDeleteCommentId = null;
			await load();
		} catch (e) {
			showToast(t('runSocial.deleteFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			deletingComment = false;
		}
	}



	let topLevel = $derived(comments.filter((c) => c.parent_comment_id == null));
	let repliesByParent = $derived.by(() => {
		const m = new Map<string, RunCommentWithAuthor[]>();
		for (const c of comments) {
			if (c.parent_comment_id) {
				const list = m.get(c.parent_comment_id) ?? [];
				list.push(c);
				m.set(c.parent_comment_id, list);
			}
		}
		return m;
	});
</script>

<div class="run-social">
	<div class="kudos-row">
		<button
			class="kudos-btn"
			class:given={kudos.viewer_has_kudos}
			disabled={!auth.loggedIn || isOwn || kudosBusy}
			type="button"
			onclick={toggleKudos}
			title={!auth.loggedIn
				? t('runSocial.signInToGiveKudos')
				: isOwn
					? t('runSocial.cannotKudosOwnRun')
					: kudos.viewer_has_kudos
						? t('runSocial.rescindKudos')
						: t('runSocial.giveKudos')}
		>
			<span class="material-symbols">
				{kudos.viewer_has_kudos ? 'favorite' : 'favorite_border'}
			</span>
			<span class="kudos-count">{kudos.count}</span>
			<span class="kudos-label">{t('runSocial.kudosLabel')}</span>
		</button>
		<span class="comment-count">
			<span class="material-symbols">chat_bubble_outline</span>
			{comments.length === 1 ? t('runSocial.commentCountOne', { n: comments.length }) : t('runSocial.commentCountMany', { n: comments.length })}
		</span>
	</div>

	{#if !loading}
		<div class="comments">
			{#each topLevel as comment (comment.id)}
				<article class="comment">
					<a href="/u/{comment.author_id}" class="comment-author">
						<Avatar
							url={comment.author.avatar_url}
							name={comment.author.display_name}
							size="2rem"
							font="0.85rem"
						/>
					</a>
					<div class="comment-body">
						<div class="comment-head">
							<a href="/u/{comment.author_id}" class="comment-author-link">
								<strong>{comment.author.display_name ?? t('runSocial.runnerFallback')}</strong>
							</a>
							<span class="when">{formatRelativeTime(comment.created_at, undefined, currentLocale())}</span>
							{#if auth.loggedIn && auth.user?.id !== comment.author_id}
								<button
									class="icon-btn report-btn"
									type="button"
									aria-label={t('runSocial.reportComment')}
									title={t('runSocial.reportComment')}
									onclick={() => (reportCommentId = comment.id)}
								>
									<span class="material-symbols">flag</span>
								</button>
							{/if}
							{#if auth.user?.id === comment.author_id || isOwn}
								<button
									class="icon-btn"
									type="button"
									aria-label={t('runSocial.deleteComment')}
									onclick={() => (confirmDeleteCommentId = comment.id)}
								>
									<span class="material-symbols">close</span>
								</button>
							{/if}
						</div>
						<p>{comment.body}</p>
						{#if auth.loggedIn}
							<button class="link-btn" type="button" onclick={() => (replyTo = replyTo === comment.id ? null : comment.id)}>
								{t('runSocial.reply')}
							</button>
						{/if}

						{#if (repliesByParent.get(comment.id)?.length ?? 0) > 0}
							<div class="replies">
								{#each repliesByParent.get(comment.id) ?? [] as reply (reply.id)}
									<div class="reply">
										<a href="/u/{reply.author_id}" class="reply-author">
											<Avatar
												url={reply.author.avatar_url}
												name={reply.author.display_name}
												size="2rem"
												font="0.85rem"
											/>
										</a>
										<div class="reply-body">
											<div class="comment-head">
												<a href="/u/{reply.author_id}" class="comment-author-link">
													<strong>{reply.author.display_name ?? t('runSocial.runnerFallback')}</strong>
												</a>
												<span class="when">{formatRelativeTime(reply.created_at, undefined, currentLocale())}</span>
												{#if auth.loggedIn && auth.user?.id !== reply.author_id}
													<button
														class="icon-btn report-btn"
														type="button"
														aria-label={t('runSocial.reportReply')}
														title={t('runSocial.reportReply')}
														onclick={() => (reportCommentId = reply.id)}
													>
														<span class="material-symbols">flag</span>
													</button>
												{/if}
												{#if auth.user?.id === reply.author_id || isOwn}
													<button
														class="icon-btn"
														type="button"
														aria-label={t('runSocial.deleteReply')}
														onclick={() => (confirmDeleteCommentId = reply.id)}
													>
														<span class="material-symbols">close</span>
													</button>
												{/if}
											</div>
											<p>{reply.body}</p>
										</div>
									</div>
								{/each}
							</div>
						{/if}

						{#if replyTo === comment.id}
							<form class="reply-form" onsubmit={(e) => { e.preventDefault(); submitReply(comment.id); }}>
								<input
									type="text"
									placeholder={t('runSocial.writeReplyPlaceholder')}
									bind:value={replyBody}
									maxlength="2000"
								/>
								<button class="btn btn-primary btn-sm" type="submit" disabled={!replyBody.trim() || posting}>
									{posting ? t('runSocial.posting') : t('runSocial.reply')}
								</button>
							</form>
						{/if}
					</div>
				</article>
			{/each}
		</div>

		{#if auth.loggedIn}
			<form class="composer" onsubmit={(e) => { e.preventDefault(); submitComment(); }}>
				<textarea
					bind:value={draftBody}
					placeholder={t('runSocial.addCommentPlaceholder')}
					rows="2"
					maxlength="2000"
				></textarea>
				<button class="btn btn-primary" type="submit" disabled={!draftBody.trim() || posting}>
					{posting ? t('runSocial.posting') : t('runSocial.post')}
				</button>
			</form>
		{:else}
			<p class="muted">
				<a href="/login">{t('runSocial.signIn')}</a>{t('runSocial.signInToEngageSuffix')}
			</p>
		{/if}
	{/if}
</div>

<ReportDialog
	open={reportCommentId !== null}
	targetKind="comment"
	targetId={reportCommentId ?? ''}
	onclose={() => (reportCommentId = null)}
/>

<ConfirmDialog
	open={confirmDeleteCommentId !== null}
	title={t('runSocial.deleteCommentTitle')}
	message={t('runSocial.deleteCommentMessage')}
	confirmLabel={t('runSocial.deleteComment')}
	onconfirm={removeComment}
	oncancel={() => (confirmDeleteCommentId = null)}
	danger
/>

<style>
	.run-social {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.kudos-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding-bottom: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
	}

	.kudos-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.45rem 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
		font-size: 0.9rem;
		font-weight: 600;
		transition:
			color var(--transition-fast),
			border-color var(--transition-fast),
			background var(--transition-fast);
	}

	.kudos-btn:disabled {
		cursor: not-allowed;
		opacity: 0.6;
	}

	.kudos-btn:not(:disabled):hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.kudos-btn.given {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.kudos-count {
		font-variant-numeric: tabular-nums;
	}

	.kudos-label,
	.comment-count {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}

	.comment-count .material-symbols {
		font-size: 1rem;
	}

	.comments {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.comment {
		display: flex;
		gap: var(--space-sm);
	}

	.comment-author,
	.reply-author {
		flex-shrink: 0;
		text-decoration: none;
	}



	.comment-body,
	.reply-body {
		flex: 1;
		min-width: 0;
	}

	.comment-author-link {
		text-decoration: none;
		color: inherit;
	}

	.comment-author-link:hover strong {
		color: var(--color-primary);
	}

	.comment-head {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		margin-bottom: 0.2rem;
	}

	.when {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}

	.icon-btn {
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.15rem;
		border-radius: var(--radius-sm);
	}

	.comment-head .icon-btn:first-of-type {
		margin-inline-start: auto;
	}

	.icon-btn:hover {
		color: var(--color-danger, #ef4444);
	}

	.comment-body p,
	.reply-body p {
		margin: 0;
		white-space: pre-wrap;
		word-break: break-word;
	}

	.link-btn {
		background: none;
		border: none;
		padding: 0.25rem 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		cursor: pointer;
	}

	.link-btn:hover {
		color: var(--color-primary);
	}

	.replies {
		margin-top: var(--space-sm);
		padding-inline-start: var(--space-md);
		border-inline-start: 2px solid var(--color-border);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.reply {
		display: flex;
		gap: var(--space-sm);
	}

	.reply-form {
		display: flex;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}

	.reply-form input {
		flex: 1;
		padding: 0.4rem 0.65rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font-size: 0.9rem;
	}

	.composer {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.composer textarea {
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font-family: inherit;
		font-size: 0.95rem;
		resize: vertical;
	}

	.composer button {
		align-self: flex-end;
	}

	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}

	.muted a {
		color: var(--color-primary);
	}
</style>
