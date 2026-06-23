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
	<a class="back" href="/challenges">{m('challenges.backToList')}</a>

	{#if notFound}
		<p class="muted">{m('challenges.notFound')}</p>
	{:else if !challenge}
		<p class="muted">…</p>
	{:else}
		<header class="hero">
			<h1>{challenge.title}</h1>
			<p class="window">{windowLabel(challenge)}</p>
			{#if challenge.goal_value != null}
				<p class="goal">
					{m('challenges.goalLabel')}: {formatGoal(challenge.metric, challenge.goal_value)}
				</p>
			{/if}
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
				/>
				{#if challenge.completed_at}
					<span class="badge-earned">{m('challenges.badgeEarned')}</span>
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
	.back {
		display: inline-block;
		margin-bottom: var(--space-md);
		font-size: 0.875rem;
		color: var(--color-accent, #2563eb);
	}
	.hero h1 {
		margin: 0 0 var(--space-2xs);
	}
	.window {
		color: var(--color-text-muted, #6b7280);
		font-size: 0.875rem;
		margin: 0 0 var(--space-sm);
	}
	.goal {
		font-weight: 600;
		margin: 0 0 var(--space-sm);
	}
	.desc {
		margin: 0 0 var(--space-md);
	}
	.my-progress {
		padding: var(--space-lg);
		margin: var(--space-md) 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.badge-earned {
		align-self: flex-start;
		font-size: 0.8rem;
		padding: 0.15rem 0.6rem;
		border-radius: 999px;
		background: var(--color-success-soft, #dcfce7);
		color: var(--color-success, #16a34a);
		font-weight: 600;
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
		color: var(--color-text-muted, #6b7280);
	}
</style>
