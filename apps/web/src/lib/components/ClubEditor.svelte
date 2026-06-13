<script lang="ts">
	import { createClub } from '$lib/core/data';
	import { geocodePlace } from '$lib/routes/geocoding';
	import type { JoinPolicy } from '$lib/types';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

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
	let requireWaiver = $state(false);
	let busy = $state(false);

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
		try {
			// Geocode the location string so the new club is searchable
			// by region (see `searchClubs` + migration 20260905_001).
			// Null is fine — the club still appears via the ILIKE branch
			// and the column can be filled by a later edit.
			let locationPointWkt: string | undefined;
			if (location.trim()) {
				const place = await geocodePlace(location.trim());
				if (place) {
					locationPointWkt = `SRID=4326;POINT(${place.center.lng} ${place.center.lat})`;
				}
			}
			const club = await createClub({
				name: name.trim(),
				description: description.trim() || undefined,
				location_label: location.trim() || undefined,
				location_point_wkt: locationPointWkt,
				is_public: visibility === 'public',
				join_policy: joinPolicy,
				requires_activity_waiver: requireWaiver
			});
			oncreated?.(club);
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : m('clubEditor.createFailed'), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<form onsubmit={submit} class="editor-form">
	<label>
		<span>{m('clubEditor.name')}</span>
		<input
			type="text"
			bind:value={name}
			placeholder={m('clubEditor.namePlaceholder')}
			required
			maxlength="80"
		/>
	</label>

	<label>
		<span>{m('clubEditor.description')} <span class="optional">{m('clubEditor.optional')}</span></span>
		<textarea
			bind:value={description}
			placeholder={m('clubEditor.descriptionPlaceholder')}
			rows="4"
			maxlength="600"
		></textarea>
	</label>

	<label>
		<span>{m('clubEditor.location')} <span class="optional">{m('clubEditor.optional')}</span></span>
		<input type="text" bind:value={location} placeholder={m('clubEditor.locationPlaceholder')} maxlength="80" />
	</label>

	<fieldset>
		<legend>{m('clubEditor.visibility')}</legend>
		<label class="radio">
			<input
				type="radio"
				name="vis"
				checked={visibility === 'public'}
				onchange={() => (visibility = 'public')}
			/>
			<span>
				<strong>{m('clubEditor.public')}</strong>
				<span class="hint">{m('clubEditor.publicHint')}</span>
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
				<strong>{m('clubEditor.private')}</strong>
				<span class="hint">
					{m('clubEditor.privateHint')}
				</span>
			</span>
		</label>
	</fieldset>

	{#if visibility === 'public'}
		<fieldset>
			<legend>{m('clubEditor.whoCanJoin')}</legend>
			<label class="radio">
				<input
					type="radio"
					name="policy"
					checked={joinPolicy === 'open'}
					onchange={() => (joinPolicy = 'open')}
				/>
				<span>
					<strong>{m('clubEditor.anyone')}</strong>
					<span class="hint">{m('clubEditor.anyoneHint')}</span>
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
					<strong>{m('clubEditor.approvalRequired')}</strong>
					<span class="hint">
						{m('clubEditor.approvalRequiredHint')}
					</span>
				</span>
			</label>
		</fieldset>
	{/if}

	<label class="toggle-row">
		<input type="checkbox" bind:checked={requireWaiver} />
		<span>
			{m('clubEditor.waiverLabel')}
		</span>
	</label>

	<div class="actions">
		{#if oncancel}
			<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>{m('clubEditor.cancel')}</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={!name.trim() || busy}>
			{busy ? m('clubEditor.creating') : m('clubEditor.createClub')}
		</button>
	</div>
</form>

