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
	import { ACTIVITY_TYPES } from '$lib/runs/activity_type';
	import { activityTypeLabel } from '$lib/runs/activity_type.svelte';
	import { getUnit, formatDistance, formatElevation } from '$lib/format/units.svelte';
	import { formatDuration } from '$lib/format/time';
	import {
		challengeGoalUnit,
		challengeGoalToStored,
		challengeGoalFromStored,
		maxStreakDaysInWindow,
		checkChallengeGoal
	} from '$lib/social/challenge_goal';
	import { showToast } from '$lib/stores/toast.svelte';
	import { untrack } from 'svelte';
	import { trackDirty } from '$lib/core/form_dirty';
	import UnsavedChangesGuard from './UnsavedChangesGuard.svelte';

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
	// The field asks for the goal in the unit the reader thinks in; the column
	// stores metres / seconds / a count. An existing challenge is pre-filled
	// through the inverse so re-opening the editor shows what was typed, not
	// the stored figure.
	let goalValue = $state<string>(
		untrack(() => {
			if (existing?.goal_value == null) return '';
			const typed = challengeGoalFromStored(
				existing.goal_value,
				existing.metric,
				getUnit()
			);
			return String(Math.round(typed * 1000) / 1000);
		})
	);
	let activityType = $state<ActivityType | ''>(untrack(() => existing?.activity_type ?? ''));
	let clubId = $state<string>(untrack(() => existing?.club_id ?? ''));
	let startsAt = $state(untrack(() => toLocalInput(existing?.starts_at, 0)));
	let endsAt = $state(untrack(() => toLocalInput(existing?.ends_at, 30)));
	let isPublic = $state(untrack(() => existing?.is_public ?? true));
	let busy = $state(false);

	const dirty = trackDirty(() => ({
		title,
		description,
		metric,
		scope,
		goalValue,
		activityType,
		clubId,
		startsAt,
		endsAt,
		isPublic,
	}));

	let goalError = $state<string | null>(null);
	let windowError = $state<string | null>(null);

	// A numeric <input bind:value> yields number | null, not a string, so the
	// value is coerced at this boundary rather than at each read.
	const typedGoal = $derived.by(() => {
		const raw = goalValue as unknown;
		if (raw === '' || raw === null || raw === undefined) return null;
		const n = Number(raw);
		return Number.isFinite(n) ? n : null;
	});
	const storedGoal = $derived(
		typedGoal === null ? null : challengeGoalToStored(typedGoal, metric, getUnit())
	);
	const startMs = $derived(new Date(startsAt).getTime());
	const endMs = $derived(new Date(endsAt).getTime());
	const streakCeiling = $derived(maxStreakDaysInWindow(startMs, endMs));

	const goalUnitSuffix = $derived.by(() => {
		switch (challengeGoalUnit(metric)) {
			case 'distance':
				return getUnit();
			case 'elevation':
				return getUnit() === 'mi' ? 'ft' : 'm';
			case 'hours':
				return m('challenges.goalSuffixHours');
			case 'activities':
				return m('challenges.goalSuffixActivities');
			case 'days':
				return m('challenges.goalSuffixDays');
		}
	});

	// The readback exists for the metrics where a conversion happened — it is
	// what makes a mistyped 100 visible before it becomes a 100 metre goal.
	// For the two counting metrics the typed number IS the stored one, so
	// echoing it back says nothing.
	const goalPreview = $derived.by(() => {
		if (storedGoal === null || storedGoal <= 0) return null;
		switch (metric) {
			case 'distance':
				return formatDistance(storedGoal);
			case 'vert':
				return formatElevation(storedGoal);
			case 'duration':
				return formatDuration(Math.round(storedGoal));
			default:
				return null;
		}
	});

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

	// The typed number meant the previous metric's unit; a 100 that meant
	// kilometres must not silently become 100 hours. Mirrors the mobile sheet's
	// _pickMetric.
	function onMetricChange() {
		goalValue = '';
		goalError = null;
	}

	async function submit(e: Event) {
		e.preventDefault();
		if (!title.trim() || busy) return;

		// Validate in one pass so every invalid field is flagged at once. Both
		// rules mirror a CHECK that raises a 23514 naming neither the bound nor
		// the column (`challenges_goal_ck`, `challenges_window_ck`), so
		// catching them here is the only way the author is told what to move.
		const nextWindowError = endMs > startMs ? null : m('challenges.errWindow');
		const refusal = checkChallengeGoal(storedGoal, metric, startMs, endMs);
		// An inverted window carries its own message and moving the end is the
		// fix for both, so a ceiling of zero days beside it is noise rather
		// than a second thing to correct.
		const nextGoalError =
			refusal === 'not_positive'
				? m('challenges.errGoal')
				: refusal === 'exceeds_window' && nextWindowError === null
					? m('challenges.goalStreakCeiling', { n: streakCeiling })
					: null;
		goalError = nextGoalError;
		windowError = nextWindowError;
		if (nextGoalError || nextWindowError) return;

		busy = true;
		try {
			const goal = storedGoal;
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
				dirty.rebaseline();
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
				dirty.rebaseline();
			oncreated?.({ id: created.id });
			}
		} catch (err) {
			console.error(err);
			// A PostgrestError is a plain object, so only a message data.ts
			// deliberately wrapped in an Error reaches the reader.
			showToast(err instanceof Error ? err.message : m('challenges.createFailed'), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<UnsavedChangesGuard isDirty={dirty.isDirty} />

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
			<select bind:value={metric} disabled={!!existing} onchange={onMetricChange}>
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
			<span class="goal-row">
				<input
					type="number"
					inputmode="decimal"
					step="any"
					bind:value={goalValue}
					oninput={() => (goalError = null)}
					aria-invalid={goalError !== null}
				/>
				<span class="goal-unit">{goalUnitSuffix}</span>
			</span>
			{#if goalPreview}
				<span class="field-hint">{m('challenges.goalPreview', { value: goalPreview })}</span>
			{/if}
			{#if metric === 'streak_days' && streakCeiling > 0}
				<span class="field-hint">
					{m('challenges.goalStreakCeiling', { n: streakCeiling })}
				</span>
			{/if}
			{#if goalError}
				<span class="error" role="alert">{goalError}</span>
			{/if}
		</label>
		<label>
			{m('challenges.activityTypeLabel')}
			<select bind:value={activityType}>
				<option value="">{m('challenges.activityAny')}</option>
				{#each ACTIVITY_TYPES as t}
					<option value={t}>{activityTypeLabel(t)}</option>
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
			<input
				type="datetime-local"
				bind:value={endsAt}
				oninput={() => (windowError = null)}
				aria-invalid={windowError !== null}
			/>
			{#if windowError}
				<span class="error" role="alert">{windowError}</span>
			{/if}
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
	.goal-row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.goal-row input {
		flex: 1 1 auto;
		min-width: 0;
	}
	.goal-unit {
		flex: 0 0 auto;
		font-weight: 400;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		white-space: nowrap;
	}
	.row-2 {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-md);
	}
	@media (max-width: 30rem) {
		.row-2 {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
