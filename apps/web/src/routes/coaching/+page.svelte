<script lang="ts">
	import { activeFormatLocale } from '$lib/format/time';
	import { onMount } from 'svelte';
	import Avatar from '$lib/components/Avatar.svelte';
	import {
		fetchMyAthletesWithError,
		fetchPendingCoachInvites,
		fetchMyCoaches,
		createCoachInvite,
		revokeCoachInvite,
		endCoachLink,
		type CoachAthleteLink,
		type PendingCoachInvite
	} from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';

	let athletes = $state<CoachAthleteLink[]>([]);
	let pending = $state<PendingCoachInvite[]>([]);
	let coaches = $state<CoachAthleteLink[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let minting = $state(false);

	type PendingConfirm =
		| { kind: 'revoke'; id: string }
		| { kind: 'remove'; link: CoachAthleteLink }
		| { kind: 'leave'; link: CoachAthleteLink };
	let confirmAction = $state<PendingConfirm | null>(null);
	let acting = $state(false);

	async function load() {
		loading = true;
		loadError = null;
		// Wait for the auth store to hydrate before fetching — the roster
		// fetchers bail to [] when auth.user is null, and on a hard load
		// (or under CI load) onMount can fire before fetchUser resolves,
		// leaving an empty roster that never refills. Same poll the
		// /coaching/accept landing uses.
		for (let i = 0; i < 40 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		const [athletesResult, p, c] = await Promise.all([
			fetchMyAthletesWithError(),
			fetchPendingCoachInvites(),
			fetchMyCoaches()
		]);
		athletes = athletesResult.athletes;
		pending = p;
		coaches = c;
		loadError = athletesResult.error;
		loading = false;
	}

	onMount(load);

	function inviteLink(token: string): string {
		const origin = typeof location !== 'undefined' ? location.origin : '';
		return `${origin}/coaching/accept/${token}`;
	}

	async function copyLink(token: string) {
		try {
			await navigator.clipboard.writeText(inviteLink(token));
			showToast(m('coaching.inviteLinkCopied'));
		} catch (_) {
			showToast(m('coaching.copyFailed'), 'error');
		}
	}

	async function mintInvite() {
		minting = true;
		try {
			const token = await createCoachInvite();
			await copyLink(token);
			pending = await fetchPendingCoachInvites();
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : m('coaching.createInviteFailed'), 'error');
		} finally {
			minting = false;
		}
	}

	// All three relationship-severing actions route through the shared
	// ConfirmDialog (native confirm() looks like a phishing overlay on iOS
	// Safari and breaks the project convention) and an `acting` in-flight
	// guard so a double-click can't fire endCoachLink twice.
	const confirmCopy = $derived.by(() => {
		const a = confirmAction;
		if (!a) return { title: '', message: '', label: '' };
		if (a.kind === 'revoke')
			return {
				title: m('coaching.revoke'),
				message: m('coaching.revokeInviteConfirm'),
				label: m('coaching.revoke')
			};
		if (a.kind === 'remove')
			return {
				title: m('coaching.remove'),
				message: m('coaching.removeAthleteConfirm', {
					name: a.link.display_name ?? m('coaching.thisAthlete')
				}),
				label: m('coaching.remove')
			};
		return {
			title: m('coaching.leave'),
			message: m('coaching.leaveCoachConfirm', {
				name: a.link.display_name ?? m('coaching.thisCoach')
			}),
			label: m('coaching.leave')
		};
	});

	async function runConfirmAction() {
		const a = confirmAction;
		if (!a || acting) return;
		acting = true;
		try {
			if (a.kind === 'revoke') {
				await revokeCoachInvite(a.id);
				pending = pending.filter((p) => p.id !== a.id);
			} else if (a.kind === 'remove') {
				await endCoachLink(a.link.id);
				athletes = athletes.filter((x) => x.id !== a.link.id);
			} else {
				await endCoachLink(a.link.id);
				coaches = coaches.filter((c) => c.id !== a.link.id);
			}
			confirmAction = null;
		} catch (e: unknown) {
			const fallback =
				a.kind === 'revoke'
					? m('coaching.revokeInviteFailed')
					: a.kind === 'remove'
						? m('coaching.removeAthleteFailed')
						: m('coaching.endLinkFailed');
			showToast(e instanceof Error ? e.message : fallback, 'error');
		} finally {
			acting = false;
		}
	}


	function sinceLabel(iso: string | null): string {
		if (!iso) return '';
		return new Date(iso).toLocaleDateString(activeFormatLocale(), {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		});
	}
</script>

<svelte:head><title>{m('shell.coaching')} · Threkir</title></svelte:head>

<div class="page">
	<header class="page-head">
		<h1>{m('shell.coaching')}</h1>
		<p class="lede">
			{m('coaching.lede')}
		</p>
	</header>

	{#if loading}
		<p class="muted">{m('shell.loading')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('coaching.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{m('coaching.retry')}</button>
		</div>
	{:else}
		<section class="card">
			<div class="card-head">
				<div>
					<h2>{m('coaching.myAthletes')}</h2>
					<p class="muted">{m('coaching.myAthletesSub')}</p>
				</div>
				<button class="btn btn-primary" onclick={mintInvite} disabled={minting}>
					{minting ? m('coaching.creating') : m('coaching.inviteAnAthlete')}
				</button>
			</div>

			{#if pending.length > 0}
				<ul class="link-list pending-list">
					{#each pending as inv (inv.id)}
						<li class="link-row">
							<span class="pending-icon material-symbols" aria-hidden="true">link</span>
							<div class="link-body">
								<span class="link-name">{m('coaching.pendingInvite')}</span>
								<span class="link-sub">{m('coaching.pendingInviteSub', { date: sinceLabel(inv.created_at) })}</span>
							</div>
							<div class="link-actions">
								<button class="btn btn-sm btn-outline" onclick={() => copyLink(inv.invite_token)}>
									{m('coaching.copyLink')}
								</button>
								<button
									class="btn btn-sm btn-danger"
									onclick={() => (confirmAction = { kind: 'revoke', id: inv.id })}
									disabled={acting}
								>
									{m('coaching.revoke')}
								</button>
							</div>
						</li>
					{/each}
				</ul>
			{/if}

			{#if athletes.length === 0}
				<p class="empty">{m('coaching.noAthletes')}</p>
			{:else}
				<ul class="link-list">
					{#each athletes as a (a.id)}
						<li class="link-row">
							<Avatar name={a.display_name} size="2.25rem" font="0.85rem" />
							<div class="link-body">
								<a class="link-name" href="/coaching/athletes/{a.user_id}">{a.display_name ?? m('coaching.runner')}</a>
								<span class="link-sub">{m('coaching.coachingSince', { date: sinceLabel(a.accepted_at) })}</span>
							</div>
							<div class="link-actions">
								<a class="btn btn-sm btn-primary" href="/coaching/athletes/{a.user_id}">{m('coaching.review')}</a>
								<button
									class="btn btn-sm btn-outline"
									onclick={() => (confirmAction = { kind: 'remove', link: a })}
									disabled={acting}>{m('coaching.remove')}</button
								>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<section class="card">
			<div class="card-head">
				<div>
					<h2>{m('coaching.myCoaches')}</h2>
					<p class="muted">{m('coaching.myCoachesSub')}</p>
				</div>
			</div>
			{#if coaches.length === 0}
				<p class="empty">{m('coaching.noCoaches')}</p>
			{:else}
				<ul class="link-list">
					{#each coaches as c (c.id)}
						<li class="link-row">
							<Avatar name={c.display_name} size="2.25rem" font="0.85rem" />
							<div class="link-body">
								<a class="link-name" href="/u/{c.user_id}">{c.display_name ?? m('coaching.coach')}</a>
								<span class="link-sub">{m('coaching.linkedSince', { date: sinceLabel(c.accepted_at) })}</span>
							</div>
							<div class="link-actions">
								<button
									class="btn btn-sm btn-outline"
									onclick={() => (confirmAction = { kind: 'leave', link: c })}
									disabled={acting}>{m('coaching.leave')}</button
								>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</div>

<ConfirmDialog
	open={confirmAction !== null}
	title={confirmCopy.title}
	message={confirmCopy.message}
	confirmLabel={confirmCopy.label}
	onconfirm={runConfirmAction}
	oncancel={() => (confirmAction = null)}
	danger
/>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 64rem;
	}
	.page-head {
		margin-bottom: var(--space-xl);
	}
	h1 {
		margin: 0 0 var(--space-xs);
		font-size: 1.9rem;
		font-weight: 800;
		letter-spacing: -0.01em;
	}
	.lede {
		color: var(--color-text-secondary);
		max-width: 46rem;
		line-height: 1.5;
		margin: 0;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-lg);
	}
	.card-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
		flex-wrap: wrap;
	}
	h2 {
		margin: 0 0 var(--space-2xs);
		font-size: 1.15rem;
		font-weight: 700;
	}
	.muted {
		color: var(--color-text-secondary);
		font-size: 0.88rem;
		margin: 0;
	}
	.empty {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
		margin: 0;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.4rem;
	}
	.link-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.pending-list {
		margin-bottom: var(--space-md);
	}
	.link-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
	}
	.pending-list .link-row {
		border-style: dashed;
	}
	.pending-icon {
		width: 2.25rem;
		height: 2.25rem;
		display: grid;
		place-items: center;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	.link-body {
		display: flex;
		flex-direction: column;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.link-name {
		font-weight: 600;
		color: var(--color-text);
		text-decoration: none;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		min-width: 0;
	}
	a.link-name:hover {
		text-decoration: underline;
	}
	.link-sub {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.link-actions {
		display: flex;
		gap: var(--space-xs);
		flex-shrink: 0;
	}
</style>
