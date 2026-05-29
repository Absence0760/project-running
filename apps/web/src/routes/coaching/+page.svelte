<script lang="ts">
	import { onMount } from 'svelte';
	import {
		fetchMyAthletes,
		fetchPendingCoachInvites,
		fetchMyCoaches,
		createCoachInvite,
		revokeCoachInvite,
		endCoachLink,
		type CoachAthleteLink,
		type PendingCoachInvite
	} from '$lib/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';

	let athletes = $state<CoachAthleteLink[]>([]);
	let pending = $state<PendingCoachInvite[]>([]);
	let coaches = $state<CoachAthleteLink[]>([]);
	let loading = $state(true);
	let minting = $state(false);

	async function load() {
		loading = true;
		// Wait for the auth store to hydrate before fetching — the roster
		// fetchers bail to [] when auth.user is null, and on a hard load
		// (or under CI load) onMount can fire before fetchUser resolves,
		// leaving an empty roster that never refills. Same poll the
		// /coaching/accept landing uses.
		for (let i = 0; i < 40 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		[athletes, pending, coaches] = await Promise.all([
			fetchMyAthletes(),
			fetchPendingCoachInvites(),
			fetchMyCoaches()
		]);
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
			showToast('Invite link copied');
		} catch (_) {
			showToast('Could not copy — long-press the link to copy it manually', 'error');
		}
	}

	async function mintInvite() {
		minting = true;
		try {
			const token = await createCoachInvite();
			await copyLink(token);
			pending = await fetchPendingCoachInvites();
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : 'Could not create invite', 'error');
		} finally {
			minting = false;
		}
	}

	async function revoke(id: string) {
		try {
			await revokeCoachInvite(id);
			pending = pending.filter((p) => p.id !== id);
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : 'Could not revoke invite', 'error');
		}
	}

	async function removeAthlete(link: CoachAthleteLink) {
		if (!confirm(`Remove ${link.display_name ?? 'this athlete'} from your roster?`)) return;
		try {
			await endCoachLink(link.id);
			athletes = athletes.filter((a) => a.id !== link.id);
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : 'Could not remove athlete', 'error');
		}
	}

	async function leaveCoach(link: CoachAthleteLink) {
		if (!confirm(`Stop sharing with ${link.display_name ?? 'this coach'}?`)) return;
		try {
			await endCoachLink(link.id);
			coaches = coaches.filter((c) => c.id !== link.id);
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : 'Could not end link', 'error');
		}
	}

	function initial(name: string | null): string {
		return name?.[0]?.toUpperCase() ?? '?';
	}

	function sinceLabel(iso: string | null): string {
		if (!iso) return '';
		return new Date(iso).toLocaleDateString(undefined, {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		});
	}
</script>

<svelte:head><title>Coaching · Threkir</title></svelte:head>

<div class="page">
	<header class="page-head">
		<h1>Coaching</h1>
		<p class="lede">
			Connect a coach to an athlete with a shareable invite link. Coaches build a
			roster of the athletes who've accepted; athletes see who they're linked to.
		</p>
	</header>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else}
		<section class="card">
			<div class="card-head">
				<div>
					<h2>My athletes</h2>
					<p class="muted">Athletes who've accepted your invite.</p>
				</div>
				<button class="btn btn-primary" onclick={mintInvite} disabled={minting}>
					{minting ? 'Creating…' : 'Invite an athlete'}
				</button>
			</div>

			{#if pending.length > 0}
				<ul class="link-list pending-list">
					{#each pending as inv (inv.id)}
						<li class="link-row">
							<span class="pending-icon material-symbols" aria-hidden="true">link</span>
							<div class="link-body">
								<span class="link-name">Pending invite</span>
								<span class="link-sub">Created {sinceLabel(inv.created_at)} · not yet redeemed</span>
							</div>
							<div class="link-actions">
								<button class="btn btn-sm btn-outline" onclick={() => copyLink(inv.invite_token)}>
									Copy link
								</button>
								<button class="btn btn-sm btn-danger" onclick={() => revoke(inv.id)}>
									Revoke
								</button>
							</div>
						</li>
					{/each}
				</ul>
			{/if}

			{#if athletes.length === 0}
				<p class="empty">No athletes yet. Create an invite and share the link to get started.</p>
			{:else}
				<ul class="link-list">
					{#each athletes as a (a.id)}
						<li class="link-row">
							<span class="avatar" aria-hidden="true">{initial(a.display_name)}</span>
							<div class="link-body">
								<a class="link-name" href="/u/{a.user_id}">{a.display_name ?? 'Runner'}</a>
								<span class="link-sub">Coaching since {sinceLabel(a.accepted_at)}</span>
							</div>
							<div class="link-actions">
								<button class="btn btn-sm btn-outline" onclick={() => removeAthlete(a)}>Remove</button>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<section class="card">
			<div class="card-head">
				<div>
					<h2>My coaches</h2>
					<p class="muted">People coaching you. Accept a coach's invite link to appear here.</p>
				</div>
			</div>
			{#if coaches.length === 0}
				<p class="empty">You're not linked to any coach yet.</p>
			{:else}
				<ul class="link-list">
					{#each coaches as c (c.id)}
						<li class="link-row">
							<span class="avatar" aria-hidden="true">{initial(c.display_name)}</span>
							<div class="link-body">
								<a class="link-name" href="/u/{c.user_id}">{c.display_name ?? 'Coach'}</a>
								<span class="link-sub">Linked since {sinceLabel(c.accepted_at)}</span>
							</div>
							<div class="link-actions">
								<button class="btn btn-sm btn-outline" onclick={() => leaveCoach(c)}>Leave</button>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</div>

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
	.avatar {
		width: 2.25rem;
		height: 2.25rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: #fff;
		display: grid;
		place-items: center;
		font-weight: 700;
		font-size: 0.85rem;
		flex-shrink: 0;
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
