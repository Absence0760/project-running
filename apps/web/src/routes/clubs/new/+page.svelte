<script lang="ts">
	import { goto } from '$app/navigation';
	import { createClub } from '$lib/data';

	let name = $state('');
	let description = $state('');
	let location = $state('');
	let isPublic = $state(true);
	let busy = $state(false);
	let error = $state<string | null>(null);

	async function submit(e: Event) {
		e.preventDefault();
		if (!name.trim() || busy) return;
		busy = true;
		error = null;
		try {
			const club = await createClub({
				name: name.trim(),
				description: description.trim() || undefined,
				location_label: location.trim() || undefined,
				is_public: isPublic
			});
			goto(`/clubs/${club.slug}`);
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Failed to create club';
		} finally {
			busy = false;
		}
	}
</script>

<div class="page">
	<a class="back" href="/clubs">
		<span class="material-symbols">arrow_back</span>
		Back to clubs
	</a>
	<h1>Create a club</h1>
	<p class="sub">Set up a group for weekly long runs, a local chapter, or a training crew.</p>

	<form onsubmit={submit}>
		<label>
			<span>Name</span>
			<input type="text" bind:value={name} placeholder="e.g. Riverside Runners" required maxlength="80" />
		</label>

		<label>
			<span>Description <span class="optional">optional</span></span>
			<textarea
				bind:value={description}
				placeholder="Who are you, where do you meet, what kind of pace?"
				rows="4"
				maxlength="600"
			></textarea>
		</label>

		<label>
			<span>Location <span class="optional">optional</span></span>
			<input type="text" bind:value={location} placeholder="e.g. Austin, TX" maxlength="80" />
		</label>

		<fieldset>
			<legend>Visibility</legend>
			<label class="radio">
				<input type="radio" name="vis" checked={isPublic} onchange={() => (isPublic = true)} />
				<span>
					<strong>Public</strong>
					<span class="hint">Anyone can find and join.</span>
				</span>
			</label>
			<label class="radio">
				<input type="radio" name="vis" checked={!isPublic} onchange={() => (isPublic = false)} />
				<span>
					<strong>Private</strong>
					<span class="hint">Only members see posts and events. You invite people by sharing the link.</span>
				</span>
			</label>
		</fieldset>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		<div class="actions">
			<button type="button" class="btn-secondary" onclick={() => history.back()}>Cancel</button>
			<button type="submit" class="btn-primary" disabled={!name.trim() || busy}>
				{busy ? 'Creating…' : 'Create club'}
			</button>
		</div>
	</form>
</div>

<style>
	.page {
		max-width: 40rem;
		margin: 0 auto;
		padding: var(--space-xl);
	}

	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
	}

	h1 {
		font-size: 1.75rem;
		font-weight: 700;
	}

	.sub {
		color: var(--color-text-secondary);
		margin: 0.35rem 0 var(--space-lg) 0;
	}

	form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	label {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text);
	}

	.optional {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}

	input[type='text'],
	input[type='search'],
	textarea {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.6rem 0.8rem;
		font: inherit;
		color: inherit;
		width: 100%;
	}

	input:focus,
	textarea:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}

	textarea {
		resize: vertical;
	}

	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.8rem 1rem;
		background: var(--color-surface);
	}

	legend {
		font-weight: 600;
		font-size: 0.9rem;
		padding: 0 0.4rem;
	}

	.radio {
		flex-direction: row;
		align-items: flex-start;
		gap: 0.6rem;
		font-weight: 500;
		padding: 0.4rem 0;
	}

	.radio input {
		margin-top: 0.3rem;
	}

	.radio span {
		display: flex;
		flex-direction: column;
	}

	.radio .hint {
		font-weight: 400;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}

	.actions {
		display: flex;
		gap: 0.6rem;
		justify-content: flex-end;
		margin-top: var(--space-md);
	}

	.btn-primary {
		background: var(--color-primary);
		color: var(--color-bg);
		padding: 0.6rem 1.2rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: none;
		cursor: pointer;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--color-primary-hover);
	}

	.btn-primary:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.btn-secondary {
		background: transparent;
		color: var(--color-text);
		padding: 0.6rem 1.2rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: 1px solid var(--color-border);
		cursor: pointer;
	}

	.error {
		color: var(--color-danger);
		font-size: 0.9rem;
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}
</style>
