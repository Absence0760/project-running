<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchGymWorkoutWithSets,
		fetchGymSetHistory,
		deleteGymWorkout,
		type GymWorkoutWithSets,
		type GymSet,
		type GymSetWithDate,
	} from '$lib/core/data';
	import { workoutPrs, type GymSetLike, type PrKind } from '$lib/gym/gym_prs';
	import { formatDate } from '$lib/format/time';
	import Modal from '$lib/components/Modal.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	const id = $derived($page.params.id ?? '');

	let data = $state<GymWorkoutWithSets | null>(null);
	let history = $state<GymSetWithDate[]>([]);
	let loading = $state(true);
	let notFound = $state(false);
	let editing = $state(false);
	let confirmingDelete = $state(false);

	const isOwner = $derived(!!data && data.workout.user_id === auth.user?.id);

	async function load() {
		loading = true;
		const [w, h] = await Promise.all([fetchGymWorkoutWithSets(id), fetchGymSetHistory()]);
		data = w;
		history = h;
		notFound = w == null;
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
	});

	// Group this workout's sets into exercise blocks (set_index order).
	const blocks = $derived.by(() => {
		const out: { name: string; sets: GymSet[] }[] = [];
		for (const s of data?.sets ?? []) {
			const last = out[out.length - 1];
			if (last && last.name === s.exercise_name) last.sets.push(s);
			else out.push({ name: s.exercise_name, sets: [s] });
		}
		return out;
	});

	// PR kinds this workout achieved, per exercise, judged against all of
	// the user's OTHER (earlier) sets.
	const prByExercise = $derived.by(() => {
		const out = new Map<string, PrKind[]>();
		if (!data || !isOwner) return out;
		const startedAt = data.workout.started_at;
		const prior: GymSetLike[] = history
			.filter((s) => s.workout_id !== data!.workout.id && s.started_at < startedAt)
			.map((s) => ({ exercise_name: s.exercise_name, reps: s.reps, weight_kg: s.weight_kg }));
		const mine: GymSetLike[] = data.sets.map((s) => ({
			exercise_name: s.exercise_name,
			reps: s.reps,
			weight_kg: s.weight_kg,
		}));
		for (const r of workoutPrs(prior, mine)) {
			out.set(r.exerciseName.trim().toLowerCase(), r.kinds);
		}
		return out;
	});

	function prLabel(kind: PrKind): string {
		return kind === 'weight'
			? t('gym.pr.weight')
			: kind === 'volume'
				? t('gym.pr.volume')
				: t('gym.pr.e1rm');
	}
	function setSummary(s: GymSet): string {
		const parts: string[] = [];
		if (s.reps != null) parts.push(`${s.reps}`);
		if (s.weight_kg != null) parts.push(`${s.weight_kg} ${t('gym.kg')}`);
		return parts.join(' × ');
	}

	function onUpdated() {
		editing = false;
		void load();
	}

	async function doDelete() {
		confirmingDelete = false;
		try {
			await deleteGymWorkout(id);
			showToast(t('gym.deleted'));
			goto('/gym');
		} catch (e) {
			console.error('delete gym workout failed', e);
			showToast(t('gym.saveFailed'));
		}
	}
</script>

<svelte:head><title>{data?.workout.title || t('gym.title')} · Threkir</title></svelte:head>

<div class="detail-page">
	<a class="back" href="/gym">
		<span class="material-symbols-outlined">arrow_back</span>{t('gym.back')}
	</a>

	{#if loading}
		<p class="muted">{t('shell.loading')}</p>
	{:else if notFound}
		<p class="muted">{t('gym.notFound')}</p>
	{:else if data}
		<header class="detail-head">
			<div>
				<h1>{data.workout.title || t('gym.untitled')}</h1>
				<p class="muted">{formatDate(data.workout.started_at)}</p>
			</div>
			{#if isOwner}
				<div class="head-actions">
					<button class="btn btn-secondary" onclick={() => (editing = true)}>{t('gym.edit')}</button>
					<button class="btn btn-danger" onclick={() => (confirmingDelete = true)}>{t('gym.delete')}</button>
				</div>
			{/if}
		</header>

		{#each blocks as block (block.name)}
			<section class="exercise-block">
				<div class="block-head">
					<h2>{block.name}</h2>
					{#each prByExercise.get(block.name.trim().toLowerCase()) ?? [] as kind (kind)}
						<span class="pr-chip">{prLabel(kind)}</span>
					{/each}
				</div>
				<ol class="sets">
					{#each block.sets as s (s.id)}
						<li>
							<span class="set-n">{t('gym.setN', { n: s.set_index + 1 })}</span>
							<span class="set-val">{setSummary(s) || '—'}</span>
							{#if s.rpe != null}<span class="rpe">{t('gym.rpe')} {s.rpe}</span>{/if}
						</li>
					{/each}
				</ol>
			</section>
		{/each}

		{#if data.workout.notes}
			<section class="notes">
				<h2>{t('gym.notes')}</h2>
				<p>{data.workout.notes}</p>
			</section>
		{/if}
	{/if}
</div>

{#if data}
	<Modal open={editing} title={t('gym.editor.editTitle')} onclose={() => (editing = false)}>
		<GymEditor existing={data} onupdated={onUpdated} oncancel={() => (editing = false)} />
	</Modal>
{/if}

<ConfirmDialog
	open={confirmingDelete}
	title={t('gym.deleteConfirm.title')}
	message={t('gym.deleteConfirm.body')}
	confirmLabel={t('gym.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmingDelete = false)}
/>

<style>
	.detail-page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 48rem;
	}
	.back {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--text-secondary);
		text-decoration: none;
		margin-bottom: var(--space-lg);
	}
	.back:hover {
		color: var(--text-primary);
	}
	.muted {
		color: var(--text-secondary);
	}
	.detail-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	.detail-head h1 {
		margin: 0 0 var(--space-2xs);
	}
	.head-actions {
		display: flex;
		gap: var(--space-sm);
		flex-shrink: 0;
	}
	.exercise-block {
		margin-bottom: var(--space-lg);
		padding: var(--space-md) var(--space-lg);
		border: 1px solid var(--border);
		border-radius: var(--radius-md);
	}
	.block-head {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin-bottom: var(--space-sm);
		flex-wrap: wrap;
	}
	.block-head h2 {
		margin: 0;
		font-size: 1.05rem;
	}
	.pr-chip {
		font-size: 0.7rem;
		font-weight: 700;
		color: #fff;
		background: var(--accent, #d97a54);
		padding: 2px 6px;
		border-radius: var(--radius-sm);
	}
	.sets {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.sets li {
		display: flex;
		align-items: baseline;
		gap: var(--space-md);
	}
	.set-n {
		font-size: 0.8rem;
		color: var(--text-secondary);
		min-width: 3.5rem;
	}
	.set-val {
		font-variant-numeric: tabular-nums;
	}
	.rpe {
		font-size: 0.8rem;
		color: var(--text-secondary);
	}
	.notes p {
		white-space: pre-wrap;
	}
</style>
