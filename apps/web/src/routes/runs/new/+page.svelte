<script lang="ts">
	import { goto } from '$app/navigation';
	import { createManualRun } from '$lib/data';
	import { showToast } from '$lib/stores/toast.svelte';

	// Default to "now" in the user's local timezone so the date-time
	// input shows something useful. The input's value is a local
	// datetime string (YYYY-MM-DDTHH:mm); we convert to ISO UTC before
	// posting.
	function nowLocalIso() {
		const d = new Date();
		const off = d.getTimezoneOffset() * 60_000;
		return new Date(d.getTime() - off).toISOString().slice(0, 16);
	}

	let startedAt = $state(nowLocalIso());
	let durationMin = $state(30);
	let durationSec = $state(0);
	let distanceKm = $state(5);
	let activityType = $state<'run' | 'walk' | 'hike' | 'cycle'>('run');
	let notes = $state('');
	let submitting = $state(false);

	async function handleSubmit(e: Event) {
		e.preventDefault();
		if (submitting) return;
		const totalSec =
			Math.max(0, Math.floor(durationMin)) * 60 +
			Math.max(0, Math.floor(durationSec));
		const distanceM = Math.max(0, distanceKm * 1000);
		if (totalSec <= 0 || distanceM <= 0) {
			showToast('Distance and duration are both required.', 'error');
			return;
		}
		submitting = true;
		try {
			const iso = new Date(startedAt).toISOString();
			const { id } = await createManualRun({
				startedAt: iso,
				durationS: totalSec,
				distanceM,
				activityType,
				notes: notes.trim() || null,
			});
			showToast('Run added.', 'success');
			goto(`/runs/${id}`);
		} catch (err) {
			showToast(`Couldn't add run: ${(err as Error).message}`, 'error');
		} finally {
			submitting = false;
		}
	}
</script>

<div class="page">
	<header class="page-header">
		<h1>Add a run</h1>
		<p class="subtitle">
			Manually enter a run you did without the app — a treadmill session,
			a race result from a chip timer, a trail run where GPS failed.
		</p>
	</header>

	<form class="card" onsubmit={handleSubmit}>
		<label class="field">
			<span class="field-label">Started at</span>
			<input
				type="datetime-local"
				bind:value={startedAt}
				required
				class="input"
			/>
		</label>

		<label class="field">
			<span class="field-label">Activity</span>
			<div class="chip-row">
				{#each ['run', 'walk', 'hike', 'cycle'] as a}
					<button
						type="button"
						class="chip"
						class:active={activityType === a}
						onclick={() => (activityType = a as typeof activityType)}
					>
						{a.charAt(0).toUpperCase() + a.slice(1)}
					</button>
				{/each}
			</div>
		</label>

		<div class="row">
			<label class="field">
				<span class="field-label">Distance (km)</span>
				<input
					type="number"
					min="0"
					step="0.01"
					bind:value={distanceKm}
					required
					class="input"
				/>
			</label>
			<label class="field">
				<span class="field-label">Duration — min</span>
				<input
					type="number"
					min="0"
					step="1"
					bind:value={durationMin}
					required
					class="input"
				/>
			</label>
			<label class="field">
				<span class="field-label">Sec</span>
				<input
					type="number"
					min="0"
					max="59"
					step="1"
					bind:value={durationSec}
					class="input"
				/>
			</label>
		</div>

		<label class="field">
			<span class="field-label">Notes (optional)</span>
			<textarea
				bind:value={notes}
				rows="3"
				class="input"
				placeholder="How did it feel? What was the weather like?"
			></textarea>
		</label>

		<div class="actions">
			<button
				type="button"
				class="btn-secondary"
				onclick={() => goto('/runs')}
				disabled={submitting}
			>
				Cancel
			</button>
			<button type="submit" class="btn-primary" disabled={submitting}>
				{submitting ? 'Saving…' : 'Save run'}
			</button>
		</div>
	</form>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 40rem;
	}
	h1 {
		font-size: 1.5rem;
		font-weight: 800;
		margin: 0 0 var(--space-xs);
	}
	.subtitle {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0 0 var(--space-xl);
		line-height: 1.5;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
		display: grid;
		gap: 1.1rem;
	}
	.field { display: grid; gap: 0.35rem; }
	.field-label {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.input {
		padding: 0.55rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text-primary);
		font-size: 0.95rem;
		font-family: inherit;
	}
	.row { display: grid; grid-template-columns: 2fr 1fr 1fr; gap: 0.75rem; }
	@media (max-width: 30rem) {
		.row { grid-template-columns: 1fr 1fr; }
	}
	.chip-row { display: flex; flex-wrap: wrap; gap: 0.4rem; }
	.chip {
		padding: 0.4rem 0.9rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.chip.active {
		background: var(--color-primary);
		color: white;
		border-color: var(--color-primary);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.6rem;
		margin-top: 0.3rem;
	}
	.btn-primary {
		padding: 0.7rem 1.3rem;
		background: var(--color-primary);
		color: white;
		border: none;
		border-radius: var(--radius-md);
		font-weight: 600;
		cursor: pointer;
	}
	.btn-primary:disabled { opacity: 0.55; cursor: not-allowed; }
	.btn-secondary {
		padding: 0.7rem 1.3rem;
		background: transparent;
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-weight: 600;
		cursor: pointer;
	}
</style>
