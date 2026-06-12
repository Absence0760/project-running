<script lang="ts">
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		seconds: number;
		ondone: () => void;
		onskip: () => void;
	}

	let { seconds, ondone, onskip }: Props = $props();

	let remaining = $state(0);

	$effect(() => {
		remaining = seconds;
		let id: ReturnType<typeof setInterval> | null = null;
		try {
			id = setInterval(() => {
				remaining -= 1;
				if (remaining <= 0) {
					remaining = 0;
					ondone();
				}
			}, 1000);
		} catch (e) {
			console.error('rest timer interval failed', e);
		}
		return () => {
			try {
				if (id != null) clearInterval(id);
			} catch (e) {
				console.error('rest timer clear failed', e);
			}
		};
	});
</script>

<div class="rest" role="timer" aria-live="polite" data-testid="gym-rest-timer">
	<span class="material-symbols rest-icon" aria-hidden="true">timer</span>
	<span class="rest-label section-label">{t('gym.session.rest')}</span>
	<span class="rest-remaining" data-testid="rest-remaining">
		{t('gym.session.restRemaining', { seconds: remaining })}
	</span>
	<button type="button" class="btn btn-secondary btn-sm" onclick={onskip} data-testid="rest-skip">
		{t('gym.session.restSkip')}
	</button>
</div>

<style>
	.rest {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-bg-secondary);
		border-radius: var(--radius-md);
	}
	.rest-icon {
		color: var(--color-text-secondary);
	}
	.rest-label {
		color: var(--color-text-tertiary);
	}
	.rest-remaining {
		font-size: 1.4rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
		margin-inline-end: auto;
	}
</style>
