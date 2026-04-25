<script lang="ts">
	import { createTrainingPlan } from '$lib/data';
	import {
		GOAL_DISTANCES_M,
		defaultPlanWeeks,
		generatePlan,
		PHASE_LABEL,
	} from '$lib/training';
	import type { GoalEvent } from '$lib/training';
	import { fmtKm, fmtPace } from '$lib/units.svelte';

	interface Props {
		oncreated?: (plan: { id: string }) => void;
		oncancel?: () => void;
	}
	let { oncreated, oncancel }: Props = $props();

	let name = $state('');
	let goalEvent = $state<GoalEvent>('distance_half');
	let startDate = $state(defaultStart());
	let daysPerWeek = $state(4);

	let targetHours = $state<number | null>(null);
	let targetMin = $state<number | null>(null);
	let targetSec = $state<number | null>(null);

	let recent5kMin = $state<number | null>(null);
	let recent5kSec = $state<number | null>(null);

	let weekOverride = $state<number | null>(null);
	let busy = $state(false);
	let error = $state<string | null>(null);

	function describeError(e: unknown): string {
		if (e instanceof Error) return e.message;
		if (e && typeof e === 'object') {
			const obj = e as { message?: unknown; code?: unknown; details?: unknown };
			const parts: string[] = [];
			if (typeof obj.message === 'string') parts.push(obj.message);
			if (typeof obj.code === 'string') parts.push(`(${obj.code})`);
			if (typeof obj.details === 'string') parts.push(obj.details);
			if (parts.length) return parts.join(' ');
		}
		return 'Failed to create plan. Check the browser console for details.';
	}

	function defaultStart(): string {
		const d = new Date();
		d.setDate(d.getDate() + 7);
		d.setDate(d.getDate() + ((7 - d.getDay()) % 7));
		const pad = (n: number) => String(n).padStart(2, '0');
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	}

	let goalDistance = $derived(
		goalEvent === 'custom' ? 10_000 : GOAL_DISTANCES_M[goalEvent]
	);
	let weeks = $derived(weekOverride ?? defaultPlanWeeks(goalEvent));

	let goalTimeSec = $derived(
		targetHours != null || targetMin != null || targetSec != null
			? (targetHours ?? 0) * 3600 + (targetMin ?? 0) * 60 + (targetSec ?? 0)
			: null
	);
	let recent5kTotal = $derived(
		recent5kMin != null || recent5kSec != null
			? (recent5kMin ?? 0) * 60 + (recent5kSec ?? 0)
			: null
	);

	let preview = $derived.by(() => {
		if (!startDate) return null;
		try {
			return generatePlan({
				goalEvent,
				goalDistanceM: goalDistance,
				goalTimeSec,
				recent5kSec: recent5kTotal,
				startDate,
				daysPerWeek,
				weeks
			});
		} catch (_) {
			return null;
		}
	});

	const eventOptions: { value: GoalEvent; label: string }[] = [
		{ value: 'distance_5k', label: '5K' },
		{ value: 'distance_10k', label: '10K' },
		{ value: 'distance_half', label: 'Half marathon' },
		{ value: 'distance_full', label: 'Marathon' }
	];

	async function submit(e: Event) {
		e.preventDefault();
		if (!name.trim() || !preview || busy) return;
		busy = true;
		error = null;
		try {
			const plan = await createTrainingPlan({
				name: name.trim(),
				goalEvent,
				goalDistanceM: goalDistance,
				goalTimeSec,
				recent5kSec: recent5kTotal,
				startDate,
				daysPerWeek,
				generated: preview
			});
			oncreated?.(plan);
		} catch (e: unknown) {
			error = describeError(e);
			console.error('Plan create failed', e);
		} finally {
			busy = false;
		}
	}
</script>

<form onsubmit={submit} class="plan-editor">
	<div class="grid">
		<section class="form">
			<label>
				<span>Plan name</span>
				<input
					type="text"
					bind:value={name}
					placeholder="Autumn half marathon"
					required
					maxlength="80"
				/>
			</label>

			<label>
				<span>Goal race</span>
				<select bind:value={goalEvent}>
					{#each eventOptions as opt}
						<option value={opt.value}>{opt.label}</option>
					{/each}
				</select>
			</label>

			<label>
				<span>Start date <span class="optional">first week begins Sunday</span></span>
				<input type="date" bind:value={startDate} required />
			</label>

			<label>
				<span>Days per week</span>
				<select bind:value={daysPerWeek}>
					{#each [3, 4, 5, 6, 7] as n}
						<option value={n}>{n} days</option>
					{/each}
				</select>
			</label>

			<fieldset>
				<legend>Goal time <span class="optional">optional</span></legend>
				<p class="hint">Drives the pace targets. Leave blank for a volume-only plan.</p>
				<div class="time-row">
					<input type="number" min="0" max="9" bind:value={targetHours} placeholder="h" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetMin} placeholder="m" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={targetSec} placeholder="s" />
				</div>
			</fieldset>

			<fieldset>
				<legend>Recent 5K time <span class="optional">optional</span></legend>
				<p class="hint">Anchor paces on a real result via Riegel equivalence.</p>
				<div class="time-row">
					<input type="number" min="0" max="59" bind:value={recent5kMin} placeholder="m" />
					<span>:</span>
					<input type="number" min="0" max="59" bind:value={recent5kSec} placeholder="s" />
				</div>
			</fieldset>

			<label>
				<span>Override total weeks <span class="optional">optional</span></span>
				<input
					type="number"
					min="4"
					max="24"
					bind:value={weekOverride}
					placeholder={String(defaultPlanWeeks(goalEvent))}
				/>
			</label>

			{#if error}
				<p class="error">{error}</p>
			{/if}

			<div class="actions">
				{#if oncancel}
					<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>Cancel</button>
				{/if}
				<button type="submit" class="btn btn-primary" disabled={!name.trim() || !preview || busy}>
					{busy ? 'Creating…' : 'Create plan'}
				</button>
			</div>
		</section>

		<aside class="preview">
			<h2>Preview</h2>
			{#if preview}
				<div class="paces">
					<div class="pace-row"><span>Easy</span><strong>{fmtPace(preview.paces.easy)}</strong></div>
					<div class="pace-row"><span>Marathon</span><strong>{fmtPace(preview.paces.marathon)}</strong></div>
					<div class="pace-row"><span>Tempo</span><strong>{fmtPace(preview.paces.tempo)}</strong></div>
					<div class="pace-row"><span>Interval</span><strong>{fmtPace(preview.paces.interval)}</strong></div>
					<div class="pace-row"><span>Repetition</span><strong>{fmtPace(preview.paces.repetition)}</strong></div>
				</div>

				{#if preview.vdot}
					<p class="vdot">Daniels VDOT: <strong>{preview.vdot.toFixed(1)}</strong></p>
				{/if}

				<h3>Week outline</h3>
				<ul class="weeks">
					{#each preview.weeks.slice(0, 6) as w}
						<li>
							<span class="week-num">#{w.week_index + 1}</span>
							<span class="week-phase">{PHASE_LABEL[w.phase]}</span>
							<span class="week-km">{fmtKm(w.target_volume_m, 0)}</span>
							<span class="week-workouts">
								{w.workouts.filter((x) => x.kind !== 'rest').length} sessions
							</span>
						</li>
					{/each}
					{#if preview.weeks.length > 6}
						<li class="more">+ {preview.weeks.length - 6} more weeks</li>
					{/if}
				</ul>
			{:else}
				<p class="muted">Fill in the form to see a preview.</p>
			{/if}
		</aside>
	</div>
</form>

<style>
	.plan-editor {
		display: block;
	}
	.grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr) minmax(0, 20rem);
		gap: var(--space-lg);
	}
	@media (max-width: 48rem) {
		.grid {
			grid-template-columns: 1fr;
		}
	}
	.form,
	.preview {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	label,
	fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.9rem;
		font-weight: 600;
	}
	.optional {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}
	input[type='text'],
	input[type='date'],
	input[type='number'],
	select {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.55rem 0.75rem;
		font: inherit;
		color: inherit;
	}
	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.8rem 1rem;
		background: var(--color-surface);
	}
	legend {
		font-weight: 600;
		padding: 0 0.4rem;
	}
	.hint {
		font-weight: 400;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin-bottom: 0.4rem;
	}
	.time-row {
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}
	.time-row input {
		width: 4rem;
		text-align: center;
	}
	.time-row span {
		font-weight: 700;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
	}
	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}
	.preview h2 {
		font-size: 1.1rem;
	}
	.preview h3 {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin-top: var(--space-md);
	}
	.paces {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.4rem 0.8rem;
	}
	.pace-row {
		display: flex;
		justify-content: space-between;
		padding: 0.3rem 0.55rem;
		background: var(--color-surface);
		border-radius: var(--radius-md);
		font-size: 0.88rem;
	}
	.vdot {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-top: -0.2rem;
	}
	.weeks {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}
	.weeks li {
		display: grid;
		grid-template-columns: 2rem auto 1fr auto;
		gap: 0.5rem;
		align-items: center;
		font-size: 0.85rem;
		padding: 0.3rem 0.5rem;
		background: var(--color-surface);
		border-radius: var(--radius-md);
	}
	.weeks li.more {
		display: block;
		text-align: center;
		color: var(--color-text-tertiary);
	}
	.week-num {
		font-weight: 700;
		color: var(--color-primary);
	}
	.week-phase {
		color: var(--color-text-secondary);
	}
	.week-km {
		color: var(--color-text);
		text-align: right;
		font-variant-numeric: tabular-nums;
	}
	.week-workouts {
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
