<script lang="ts">
	import { onDestroy } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import SessionExecutionBand from '$lib/components/SessionExecutionBand.svelte';
	import {
		computeSessionAdherence,
		type SessionStep,
		type SessionStepResult,
		type SessionAdherence
	} from '$lib/social/session_steps';
	import type { SessionPlanWithItems } from '$lib/types';

	interface Props {
		plan: SessionPlanWithItems;
		steps: SessionStep[];
		onfinish: (results: SessionStepResult[], adherence: SessionAdherence) => void;
		oncancel: () => void;
	}

	let { plan, steps, onfinish, oncancel }: Props = $props();

	let currentIndex = $state(0);
	let results = $state<SessionStepResult[]>([]);
	let paused = $state(false);
	let confirmAbandon = $state(false);

	// The countdown is driven off the cumulative axis: each timed step's
	// deadline is its `cumulativeS` boundary measured from a monotonic start
	// epoch, so per-step rounding can't accumulate drift over a long session.
	let elapsedS = $state(0);
	let ticker: ReturnType<typeof setInterval> | null = null;
	let segmentStartElapsedS = 0;
	let segmentStartWallMs = 0;

	const current = $derived(currentIndex < steps.length ? steps[currentIndex] : null);
	const isTimed = $derived(!!current && current.kind !== 'reps' && (current.durationS ?? 0) > 0);

	const segmentElapsedS = $derived(Math.max(0, elapsedS - segmentStartElapsedS));
	const remainingS = $derived.by(() => {
		if (!current || !isTimed) return null;
		const target = current.durationS ?? 0;
		return Math.max(0, Math.ceil(target - segmentElapsedS));
	});

	function clearTicker() {
		if (ticker !== null) {
			clearInterval(ticker);
			ticker = null;
		}
	}

	function startTicker() {
		clearTicker();
		segmentStartWallMs = Date.now();
		const baseElapsed = elapsedS;
		try {
			ticker = setInterval(() => {
				try {
					elapsedS = baseElapsed + (Date.now() - segmentStartWallMs) / 1000;
					if (isTimed && remainingS !== null && remainingS <= 0) {
						advance('completed');
					}
				} catch (e) {
					// L4 auxiliary: a tick failure must never wedge the runner —
					// surface it and stop the timer so the user can still tap Done.
					console.error('session runner tick failed', e);
					clearTicker();
				}
			}, 250);
		} catch (e) {
			console.error('session runner timer start failed', e);
		}
	}

	function beginSegment() {
		segmentStartElapsedS = elapsedS;
		if (isTimed && !paused) startTicker();
		else clearTicker();
	}

	function recordCurrent(status: 'completed' | 'skipped') {
		if (!current) return;
		const target = current.durationS ?? null;
		results = [
			...results,
			{
				itemId: current.itemId,
				movementName: current.movementName,
				kind: current.kind,
				side: current.side,
				targetDurationS: target,
				actualDurationS: isTimed ? Math.round(segmentElapsedS) : null,
				status
			}
		];
	}

	function advance(status: 'completed' | 'skipped') {
		recordCurrent(status);
		currentIndex += 1;
		if (currentIndex >= steps.length) {
			clearTicker();
			finish();
			return;
		}
		beginSegment();
	}

	function finish() {
		const adherence = computeSessionAdherence(steps, results);
		onfinish(results, adherence);
	}

	function togglePause() {
		paused = !paused;
		if (paused) {
			clearTicker();
		} else if (isTimed) {
			startTicker();
		}
	}

	function abandon() {
		clearTicker();
		confirmAbandon = false;
		oncancel();
	}

	// Re-arm the per-step timing whenever the step changes (initial mount
	// included). $effect keeps the segment boundary in sync with currentIndex.
	let armedIndex = $state(-1);
	$effect(() => {
		if (currentIndex !== armedIndex && currentIndex < steps.length) {
			armedIndex = currentIndex;
			beginSegment();
		}
	});

	onDestroy(clearTicker);
</script>

<div class="runner-overlay" data-testid="session-runner" role="dialog" aria-modal="true" aria-label={m('session.run.title')}>
	<div class="runner-body">
		{#if current}
			<SessionExecutionBand
				step={current}
				index={currentIndex}
				total={steps.length}
				{remainingS}
				onDone={() => advance('completed')}
				onSkip={() => advance('skipped')}
				onAbandon={() => (confirmAbandon = true)}
			/>

			{#if isTimed}
				<div class="transport">
					<button type="button" class="btn btn-secondary" onclick={togglePause} data-testid="session-pause">
						{paused ? m('session.run.resume') : m('session.run.pause')}
					</button>
				</div>
			{/if}
		{/if}
	</div>
</div>

<ConfirmDialog
	open={confirmAbandon}
	title={m('session.run.discardTitle')}
	message={m('session.run.discardBody')}
	confirmLabel={m('session.run.discardConfirm')}
	danger
	onconfirm={abandon}
	oncancel={() => (confirmAbandon = false)}
	data-testid="session-abandon-dialog"
/>

<style>
	.runner-overlay {
		position: fixed;
		inset: 0;
		z-index: 50;
		background: var(--color-bg);
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-xl);
	}
	.runner-body {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-lg);
		width: 100%;
		max-width: 36rem;
	}
	.transport {
		display: flex;
		justify-content: center;
	}
</style>
