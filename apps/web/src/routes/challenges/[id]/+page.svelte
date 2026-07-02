<script lang="ts">
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import {
		fetchChallengeById,
		fetchChallengeLeaderboard,
		joinChallenge,
		leaveChallenge,
		deleteChallenge,
		fetchMyClubs
	} from '$lib/core/data';
	import type { ChallengeWithMeta, ChallengeLeaderboardRow, ClubWithMeta } from '$lib/types';
	import ChallengeProgressBar from '$lib/components/ChallengeProgressBar.svelte';
	import ChallengeLeaderboard from '$lib/components/ChallengeLeaderboard.svelte';
	import ChallengeEditor from '$lib/components/ChallengeEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { formatDistance, formatElevation } from '$lib/format/units.svelte';
	import { formatDuration } from '$lib/format/time';
	import type { ChallengeMetric } from '$lib/types';

	const id = $derived($page.params.id ?? '');

	function formatGoal(metric: ChallengeMetric, v: number): string {
		switch (metric) {
			case 'distance':
				return formatDistance(v);
			case 'duration':
				return formatDuration(Math.round(v));
			case 'vert':
				return formatElevation(v);
			case 'streak_days':
				return m('challenges.unitDays', { n: Math.round(v) });
			case 'activity_count':
				return m('challenges.unitActivities', { n: Math.round(v) });
		}
	}

	let challenge = $state<ChallengeWithMeta | null>(null);
	let notFound = $state(false);
	let board = $state<ChallengeLeaderboardRow[]>([]);
	let clubNames = $state<Record<string, string>>({});
	let busy = $state(false);
	let editing = $state(false);
	let confirmLeave = $state(false);
	let confirmDelete = $state(false);

	const isCreator = $derived(!!challenge && challenge.creator_id === auth.user?.id);

	async function load() {
		notFound = false;
		try {
			const c = await fetchChallengeById(id);
			if (!c) {
				notFound = true;
				return;
			}
			challenge = c;
			board = await fetchChallengeLeaderboard(id, c.scope === 'club_vs_club');
			if (c.scope === 'club_vs_club') {
				const clubs = await fetchMyClubs();
				clubNames = Object.fromEntries(clubs.map((cl: ClubWithMeta) => [cl.id, cl.name]));
			}
		} catch {
			notFound = true;
		}
	}
	$effect(() => {
		if (id) load();
	});

	const myRow = $derived(
		challenge?.scope === 'club_vs_club'
			? null
			: board.find((r) => r.user_id === auth.user?.id) ?? null
	);

	async function doJoin() {
		if (busy || !challenge) return;
		busy = true;
		try {
			await joinChallenge(challenge.id);
			await load();
		} catch {
			showToast(m('challenges.joinFailed'), 'error');
		} finally {
			busy = false;
		}
	}

	async function doLeave() {
		confirmLeave = false;
		if (busy || !challenge) return;
		busy = true;
		try {
			await leaveChallenge(challenge.id);
			await load();
		} catch {
			showToast(m('challenges.leaveFailed'), 'error');
		} finally {
			busy = false;
		}
	}

	async function doDelete() {
		confirmDelete = false;
		if (busy || !challenge) return;
		busy = true;
		try {
			await deleteChallenge(challenge.id);
			goto('/challenges');
		} catch {
			showToast(m('challenges.deleteFailed'), 'error');
			busy = false;
		}
	}

	function daysLeft(endsIso: string): number {
		return Math.ceil((new Date(endsIso).getTime() - Date.now()) / 86400000);
	}

	function windowLabel(c: ChallengeWithMeta): string {
		const now = Date.now();
		if (now < new Date(c.starts_at).getTime()) {
			return m('challenges.startsIn', { n: Math.ceil((new Date(c.starts_at).getTime() - now) / 86400000) });
		}
		if (now >= new Date(c.ends_at).getTime()) return m('challenges.ended');
		const d = daysLeft(c.ends_at);
		return d <= 1 ? m('challenges.endsToday') : m('challenges.endsIn', { n: d });
	}
</script>

<svelte:head>
	<title>{challenge?.title ?? m('challenges.title')}</title>
</svelte:head>

<div class="page">
	<a class="back" href="/challenges">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('challenges.backToList')}
	</a>

	{#if notFound}
		<p class="muted">{m('challenges.notFound')}</p>
	{:else if !challenge}
		<p class="muted">…</p>
	{:else}
		<header class="hero">
			<h1>{challenge.title}</h1>
			<div class="hero-chips">
				<span class="window-chip">
					<span class="material-symbols" aria-hidden="true">schedule</span>
					{windowLabel(challenge)}
				</span>
				{#if challenge.goal_value != null}
					<span class="goal-chip">
						<span class="material-symbols" aria-hidden="true">flag</span>
						{formatGoal(challenge.metric, challenge.goal_value)}
					</span>
				{/if}
			</div>
			{#if challenge.description}
				<p class="desc">{challenge.description}</p>
			{/if}
		</header>

		{#if challenge.joined && challenge.scope !== 'club_vs_club'}
			<section class="card-elevated my-progress">
				<ChallengeProgressBar
					metric={challenge.metric}
					value={myRow?.value ?? challenge.my_value ?? 0}
					goal={challenge.goal_value}
					startsAt={challenge.starts_at}
					endsAt={challenge.ends_at}
				/>
				{#if challenge.completed_at}
					<span class="badge-earned">
						<span class="material-symbols" aria-hidden="true">military_tech</span>
						{m('challenges.badgeEarned')}
					</span>
				{/if}
			</section>
		{/if}

		<div class="cta-row">
			{#if challenge.joined}
				<button type="button" class="btn btn-secondary" disabled={busy} onclick={() => (confirmLeave = true)}>
					{m('challenges.leave')}
				</button>
			{:else}
				<button type="button" class="btn btn-primary" disabled={busy} onclick={doJoin}>
					{m('challenges.join')}
				</button>
			{/if}
			{#if isCreator}
				<button type="button" class="btn btn-secondary" onclick={() => (editing = true)}>
					{m('challenges.edit')}
				</button>
				<button type="button" class="btn btn-danger" disabled={busy} onclick={() => (confirmDelete = true)}>
					{m('challenges.delete')}
				</button>
			{/if}
		</div>

		<section class="board">
			<h2>{m('challenges.leaderboard')}</h2>
			<ChallengeLeaderboard
				rows={board}
				metric={challenge.metric}
				scope={challenge.scope}
				{clubNames}
				meId={auth.user?.id ?? null}
			/>
		</section>
	{/if}
</div>

{#if challenge}
	<Modal open={editing} onclose={() => (editing = false)} title={m('challenges.edit')}>
		<ChallengeEditor
			existing={challenge}
			onsaved={() => {
				editing = false;
				load();
			}}
			oncancel={() => (editing = false)}
		/>
	</Modal>
{/if}

<ConfirmDialog
	open={confirmLeave}
	title={m('challenges.leaveConfirmTitle')}
	message={m('challenges.leaveConfirm')}
	confirmLabel={m('challenges.leave')}
	danger
	onconfirm={doLeave}
	oncancel={() => (confirmLeave = false)}
/>

<ConfirmDialog
	open={confirmDelete}
	title={m('challenges.deleteConfirmTitle')}
	message={m('challenges.deleteConfirm')}
	confirmLabel={m('challenges.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmDelete = false)}
/>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.1rem;
		margin-bottom: var(--space-md);
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
	}
	.back .material-symbols {
		font-size: 1.1rem;
	}
	.back:hover {
		text-decoration: underline;
	}
	.hero h1 {
		margin: 0 0 var(--space-sm);
	}
	.hero-chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin-bottom: var(--space-sm);
	}
	.window-chip,
	.goal-chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		padding: 0.2rem 0.6rem;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 600;
	}
	.window-chip {
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
	}
	.goal-chip {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.window-chip .material-symbols,
	.goal-chip .material-symbols {
		font-size: 1rem;
		width: 1rem;
		height: 1rem;
	}
	.desc {
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
	}
	.my-progress {
		padding: var(--space-lg);
		margin: var(--space-md) 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.badge-earned {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		align-self: flex-start;
		font-size: 0.8rem;
		padding: 0.15rem 0.6rem;
		border-radius: 999px;
		background: var(--color-success-light);
		color: var(--color-success);
		font-weight: 600;
	}
	.badge-earned .material-symbols {
		font-size: 1rem;
		width: 1rem;
		height: 1rem;
	}
	.cta-row {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
		margin: var(--space-md) 0;
	}
	.board {
		margin-top: var(--space-xl);
	}
	.board h2 {
		font-size: 1.1rem;
		margin: 0 0 var(--space-md);
	}
	.muted {
		color: var(--color-text-secondary);
	}
</style>
