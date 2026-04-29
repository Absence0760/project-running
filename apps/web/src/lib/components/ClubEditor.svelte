<script lang="ts">
	import { createClub } from '$lib/data';
	import type { JoinPolicy } from '$lib/types';

	interface Props {
		oncreated?: (club: { slug: string; id: string }) => void;
		oncancel?: () => void;
	}
	let { oncreated, oncancel }: Props = $props();

	let name = $state('');
	let description = $state('');
	let location = $state('');
	let visibility = $state<'public' | 'private'>('public');
	let joinPolicy = $state<JoinPolicy>('open');
	let busy = $state(false);
	let error = $state<string | null>(null);

	$effect(() => {
		// Private clubs don't appear in Browse; 'request' makes no sense
		// without discoverability, so invite is the only sensible pairing.
		if (visibility === 'private' && joinPolicy !== 'invite') {
			joinPolicy = 'invite';
		}
		if (visibility === 'public' && joinPolicy === 'invite') {
			joinPolicy = 'open';
		}
	});

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
				is_public: visibility === 'public',
				join_policy: joinPolicy
			});
			oncreated?.(club);
		} catch (e: unknown) {
			error = e instanceof Error ? e.message : 'Failed to create club';
		} finally {
			busy = false;
		}
	}
</script>

<form onsubmit={submit} class="club-editor">
	<label>
		<span>Name</span>
		<input
			type="text"
			bind:value={name}
			placeholder="e.g. Riverside Runners"
			required
			maxlength="80"
		/>
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
			<input
				type="radio"
				name="vis"
				checked={visibility === 'public'}
				onchange={() => (visibility = 'public')}
			/>
			<span>
				<strong>Public</strong>
				<span class="hint">Anyone can find this club in Browse.</span>
			</span>
		</label>
		<label class="radio">
			<input
				type="radio"
				name="vis"
				checked={visibility === 'private'}
				onchange={() => (visibility = 'private')}
			/>
			<span>
				<strong>Private</strong>
				<span class="hint">
					Hidden from Browse. Invite-only — share the generated link to let people join.
				</span>
			</span>
		</label>
	</fieldset>

	{#if visibility === 'public'}
		<fieldset>
			<legend>Who can join?</legend>
			<label class="radio">
				<input
					type="radio"
					name="policy"
					checked={joinPolicy === 'open'}
					onchange={() => (joinPolicy = 'open')}
				/>
				<span>
					<strong>Anyone</strong>
					<span class="hint">One click to join, no approval needed.</span>
				</span>
			</label>
			<label class="radio">
				<input
					type="radio"
					name="policy"
					checked={joinPolicy === 'request'}
					onchange={() => (joinPolicy = 'request')}
				/>
				<span>
					<strong>Approval required</strong>
					<span class="hint">
						New members sit in a pending queue until an admin accepts them.
					</span>
				</span>
			</label>
		</fieldset>
	{/if}

	{#if error}
		<p class="error">{error}</p>
	{/if}

	<div class="actions">
		{#if oncancel}
			<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>Cancel</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={!name.trim() || busy}>
			{busy ? 'Creating…' : 'Create club'}
		</button>
	</div>
</form>

<style>
	.club-editor {
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
	.error {
		color: var(--color-danger);
		font-size: 0.9rem;
		background: var(--color-danger-light);
		padding: 0.5rem 0.8rem;
		border-radius: var(--radius-md);
	}
</style>
