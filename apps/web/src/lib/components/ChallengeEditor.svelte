<script lang="ts">
	import { createChallenge, updateChallenge, fetchMyClubs } from '$lib/core/data';
	import type {
		Challenge,
		ChallengeMetric,
		ChallengeScope,
		ActivityType,
		ClubWithMeta
	} from '$lib/types';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { untrack } from 'svelte';

	interface Props {
		existing?: Challenge;
		oncreated?: (challenge: { id: string }) => void;
		onsaved?: () => void;
		oncancel?: () => void;
	}
	let { existing, oncreated, onsaved, oncancel }: Props = $props();

	const METRICS: { id: ChallengeMetric; labelKey: 'challenges.metricDistance' | 'challenges.metricDuration' | 'challenges.metricVert' | 'challenges.metricActivityCount' | 'challenges.metricStreak' }[] = [
		{ id: 'distance', labelKey: 'challenges.metricDistance' },
		{ id: 'duration', labelKey: 'challenges.metricDuration' },
		{ id: 'vert', labelKey: 'challenges.metricVert' },
		{ id: 'activity_count', labelKey: 'challenges.metricActivityCount' },
		{ id: 'streak_days', labelKey: 'challenges.metricStreak' }
	];
	const SCOPES: { id: ChallengeScope; labelKey: 'challenges.scopeIndividual' | 'challenges.scopeClubVsClub' | 'challenges.scopeGroupGoal' }[] = [
		{ id: 'individual', labelKey: 'challenges.scopeIndividual' },
		{ id: 'club_vs_club', labelKey: 'challenges.scopeClubVsClub' },
		{ id: 'group_goal', labelKey: 'challenges.scopeGroupGoal' }
	];
	const ACTIVITY_TYPES: ActivityType[] = ['run', 'walk', 'hike', 'cycle', 'stroller'];

	function toLocalInput(iso: string | undefined, fallbackDaysFromNow: number): string {
		const d = iso ? new Date(iso) : new Date(Date.now() + fallbackDaysFromNow * 86400000);
		// datetime-local wants YYYY-MM-DDTHH:mm in local time.
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
	}

	let title = $state(untrack(() => existing?.title ?? ''));
	let description = $state(untrack(() => existing?.description ?? ''));
	let metric = $state<ChallengeMetric>(untrack(() => existing?.metric ?? 'distance'));
	let scope = $state<ChallengeScope>(untrack(() => existing?.scope ?? 'individual'));
	let goalValue = $state<string>(untrack(() => (existing?.goal_value != null ? String(existing.goal_value) : '')));
	let activityType = $state<ActivityType | ''>(untrack(() => existing?.activity_type ?? ''));
	let clubId = $state<string>(untrack(() => existing?.club_id ?? ''));
	let startsAt = $state(untrack(() => toLocalInput(existing?.starts_at, 0)));
	let endsAt = $state(untrack(() => toLocalInput(existing?.ends_at, 30)));
	let isPublic = $state(untrack(() => existing?.is_public ?? true));
	let busy = $state(false);

	let adminClubs = $state<ClubWithMeta[]>([]);
	$effect(() => {
		fetchMyClubs()
			.then((clubs) => {
				adminClubs = clubs.filter(
					(c) => c.viewer_role === 'owner' || c.viewer_role === 'admin'
				);
			})
			.catch(() => {
				adminClubs = [];
			});
	});

	// club_vs_club aggregates across many clubs, so it never anchors to a single
	// club; force the anchor empty in that mode.
	$effect(() => {
		if (scope === 'club_vs_club' && clubId) clubId = '';
	});

	async function submit(e: Event) {
		e.preventDefault();
		if (!title.trim() || busy) return;
		busy = true;
		try {
			// A numeric <input bind:value> yields number | null, not a string,
			// so coerce at the boundary before parsing (the .trim() gotcha).
			const rawGoal = goalValue as unknown;
			const goal =
				rawGoal === '' || rawGoal === null || rawGoal === undefined
					? null
					: Number(rawGoal);
			if (existing) {
				await updateChallenge(existing.id, {
					title: title.trim(),
					description: description.trim() || null,
					goal_value: goal,
					activity_type: activityType || null,
					starts_at: new Date(startsAt).toISOString(),
					ends_at: new Date(endsAt).toISOString(),
					is_public: isPublic
				});
				onsaved?.();
			} else {
				const created = await createChallenge({
					title: title.trim(),
					description: description.trim() || null,
					metric,
					scope,
					goal_value: goal,
					activity_type: activityType || null,
					club_id: scope === 'club_vs_club' ? null : clubId || null,
					starts_at: new Date(startsAt).toISOString(),
					ends_at: new Date(endsAt).toISOString(),
					is_public: isPublic
				});
				oncreated?.({ id: created.id });
			}
		} catch (err) {
			console.error(err);
			showToast(m('challenges.createFailed'), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<form class="editor-form" onsubmit={submit}>
	<label>
		{m('challenges.titleLabel')}
		<input type="text" bind:value={title} maxlength="120" required />
	</label>

	<label>
		{m('challenges.descriptionLabel')}
		<textarea bind:value={description} rows="2" maxlength="2000"></textarea>
	</label>

	<div class="row-2">
		<label>
			{m('challenges.metricLabel')}
			<select bind:value={metric} disabled={!!existing}>
				{#each METRICS as opt}
					<option value={opt.id}>{m(opt.labelKey)}</option>
				{/each}
			</select>
		</label>
		<label>
			{m('challenges.scopeLabel')}
			<select bind:value={scope} disabled={!!existing}>
				{#each SCOPES as opt}
					<option value={opt.id}>{m(opt.labelKey)}</option>
				{/each}
			</select>
		</label>
	</div>

	<div class="row-2">
		<label>
			{m('challenges.goalOptional')}
			<input type="number" inputmode="decimal" bind:value={goalValue} min="0" />
		</label>
		<label>
			{m('challenges.activityTypeLabel')}
			<select bind:value={activityType}>
				<option value="">{m('challenges.activityAny')}</option>
				{#each ACTIVITY_TYPES as t}
					<option value={t}>{t}</option>
				{/each}
			</select>
		</label>
	</div>

	{#if scope !== 'club_vs_club' && !existing}
		<label>
			{m('challenges.clubLabel')}
			<select bind:value={clubId}>
				<option value="">{m('challenges.clubNone')}</option>
				{#each adminClubs as c}
					<option value={c.id}>{c.name}</option>
				{/each}
			</select>
		</label>
	{/if}

	<div class="row-2">
		<label>
			{m('challenges.startLabel')}
			<input type="datetime-local" bind:value={startsAt} disabled={!!existing} />
		</label>
		<label>
			{m('challenges.endLabel')}
			<input type="datetime-local" bind:value={endsAt} />
		</label>
	</div>

	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>
			{m('challenges.cancel')}
		</button>
		<button type="submit" class="btn btn-primary" disabled={busy || !title.trim()}>
			{existing ? m('challenges.save') : m('challenges.create')}
		</button>
	</div>
</form>

<style>
	.row-2 {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-md);
	}
	@media (max-width: 30rem) {
		.row-2 {
			grid-template-columns: 1fr;
		}
	}
</style>
