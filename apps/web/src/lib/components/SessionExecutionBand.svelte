<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import type { SessionStep } from '$lib/social/session_steps';

	interface Props {
		step: SessionStep;
		index: number;
		total: number;
		remainingS: number | null;
		onDone: () => void;
		onSkip: () => void;
		onAbandon: () => void;
	}

	let { step, index, total, remainingS, onDone, onSkip, onAbandon }: Props = $props();

	const isTimed = $derived(step.kind !== 'reps' && (step.durationS ?? 0) > 0);

	const movementName = $derived.by(() => {
		if (step.side === 'left') return m('session.sideLeft', { name: step.movementName });
		if (step.side === 'right') return m('session.sideRight', { name: step.movementName });
		return step.movementName;
	});

	const progress = $derived.by(() => {
		if (!isTimed || remainingS === null) return 0;
		const total = step.durationS ?? 0;
		if (total <= 0) return 1;
		return Math.min(1, Math.max(0, (total - remainingS) / total));
	});
</script>

<div class="band" data-testid="session-execution-band">
	<p class="counter">{m('session.run.stepCount', { index: index + 1, total })}</p>
	<h2 class="movement" data-testid="session-step-name">{movementName}</h2>

	{#if isTimed && remainingS !== null}
		<div
			class="countdown"
			role="timer"
			aria-live="off"
			aria-label={m('session.run.remaining', { seconds: remainingS })}
		>
			<span class="remaining" data-testid="session-remaining">{remainingS}</span>
			<div class="bar" aria-hidden="true">
				<div class="bar-fill" style="width: {progress * 100}%"></div>
			</div>
		</div>
	{/if}

	{#if step.cue}
		<p class="cue">{step.cue}</p>
	{/if}
	{#if step.tempo}
		<p class="tempo">{step.tempo}</p>
	{/if}

	<div class="actions">
		<button type="button" class="btn btn-primary" onclick={onDone} data-testid="session-done">
			{m('session.run.done')}
		</button>
		<button type="button" class="btn btn-secondary" onclick={onSkip} data-testid="session-skip">
			{m('session.run.skip')}
		</button>
		<button type="button" class="btn btn-danger" onclick={onAbandon} data-testid="session-abandon">
			{m('session.run.abandon')}
		</button>
	</div>
</div>

<style>
	.band {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		text-align: center;
	}
	.counter {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin: 0;
	}
	.movement {
		margin: 0;
		font-size: 1.6rem;
	}
	.countdown {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		width: 100%;
		max-width: 22rem;
	}
	.remaining {
		font-size: 3rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.bar {
		width: 100%;
		height: 0.5rem;
		border-radius: var(--radius-md);
		background: var(--color-border);
		overflow: hidden;
	}
	.bar-fill {
		height: 100%;
		background: var(--color-primary);
		transition: width 0.25s linear;
	}
	.cue {
		color: var(--color-text-secondary);
		margin: 0;
		max-width: 28rem;
	}
	.tempo {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin: 0;
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
		justify-content: center;
	}
</style>
