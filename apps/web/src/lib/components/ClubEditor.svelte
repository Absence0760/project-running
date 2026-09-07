<script lang="ts">
	import { createClub, updateClub } from '$lib/core/data';
	import { geocodePlace } from '$lib/routes/geocoding';
	import type { Club, JoinPolicy } from '$lib/types';
	import { m } from '$lib/i18n/store.svelte';
	import { joinPolicyLabel } from '$lib/i18n/enum_labels.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { untrack } from 'svelte';
	import { trackDirty } from '$lib/core/form_dirty';
	import { TEXT_LIMITS } from '$lib/core/text_limits';
	import { clubNameNamesSomething } from '$lib/social/club_slug';
	import UnsavedChangesGuard from './UnsavedChangesGuard.svelte';

	interface Props {
		/// When set, the editor edits this club instead of creating a new one.
		existing?: Club;
		oncreated?: (club: { slug: string; id: string }) => void;
		onsaved?: () => void;
		oncancel?: () => void;
	}
	let { existing, oncreated, onsaved, oncancel }: Props = $props();

	let name = $state(untrack(() => existing?.name ?? ''));
	let description = $state(untrack(() => existing?.description ?? ''));
	let location = $state(untrack(() => existing?.location_label ?? ''));
	let visibility = $state<'public' | 'private'>(
		untrack(() => (existing && !existing.is_public ? 'private' : 'public'))
	);
	let joinPolicy = $state<JoinPolicy>(untrack(() => existing?.join_policy ?? 'open'));
	let requireWaiver = $state(untrack(() => existing?.requires_activity_waiver ?? false));
	let websiteUrl = $state(untrack(() => existing?.website_url ?? ''));
	let instagramUrl = $state(untrack(() => existing?.instagram_url ?? ''));
	let stravaUrl = $state(untrack(() => existing?.strava_url ?? ''));
	let facebookUrl = $state(untrack(() => existing?.facebook_url ?? ''));
	let busy = $state(false);

	const dirty = trackDirty(() => ({
		name,
		description,
		location,
		visibility,
		joinPolicy,
		requireWaiver,
		websiteUrl,
		instagramUrl,
		stravaUrl,
		facebookUrl,
	}));

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
		// A name has to name something. Without this a club called `!!!` was
		// creatable here and refused on the phone, and it landed under the
		// `CLUB_SLUG_FALLBACK` slug — a permanent public URL of `club` for a club
		// whose name spells nothing (decisions § 1338). The predicate is the
		// pair's, not this component's, so the two clients cannot disagree.
		if (!clubNameNamesSomething(name)) {
			showToast(m('clubEditor.errNameNeedsCharacter'), 'error');
			return;
		}
		busy = true;
		try {
			if (existing) {
				await updateClub(existing.id, {
					name: name.trim(),
					description: description.trim() || null,
					location_label: location.trim() || null,
					is_public: visibility === 'public',
					website_url: websiteUrl,
					instagram_url: instagramUrl,
					strava_url: stravaUrl,
					facebook_url: facebookUrl
				});
				dirty.rebaseline();
				onsaved?.();
				return;
			}
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
				requires_activity_waiver: requireWaiver,
				website_url: websiteUrl,
				instagram_url: instagramUrl,
				strava_url: stravaUrl,
				facebook_url: facebookUrl
			});
			dirty.rebaseline();
			oncreated?.(club);
		} catch (e: unknown) {
			showToast(e instanceof Error ? e.message : m('clubEditor.createFailed'), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<UnsavedChangesGuard isDirty={dirty.isDirty} />

<form onsubmit={submit} class="editor-form">
	<label>
		<span>{m('clubEditor.name')}</span>
		<input
			type="text"
			bind:value={name}
			placeholder={m('clubEditor.namePlaceholder')}
			required
			maxlength={TEXT_LIMITS.clubName}
		/>
	</label>

	<label>
		<span>{m('clubEditor.description')} <span class="optional">{m('clubEditor.optional')}</span></span>
		<textarea
			bind:value={description}
			placeholder={m('clubEditor.descriptionPlaceholder')}
			rows="4"
			maxlength={TEXT_LIMITS.clubDescription}
		></textarea>
	</label>

	<label>
		<span>{m('clubEditor.location')} <span class="optional">{m('clubEditor.optional')}</span></span>
		<input
			type="text"
			bind:value={location}
			placeholder={m('clubEditor.locationPlaceholder')}
			maxlength={TEXT_LIMITS.clubLocationLabel}
		/>
	</label>

	<fieldset>
		<legend>{m('clubEditor.links')} <span class="optional">{m('clubEditor.optional')}</span></legend>
		<label class="link-field">
			<span>{m('clubEditor.website')}</span>
			<input type="url" bind:value={websiteUrl} placeholder="https://example.com" maxlength="500" inputmode="url" />
		</label>
		<label class="link-field">
			<span>{m('clubEditor.instagram')}</span>
			<input type="url" bind:value={instagramUrl} placeholder="https://instagram.com/yourclub" maxlength="500" inputmode="url" />
		</label>
		<label class="link-field">
			<span>{m('clubEditor.strava')}</span>
			<input type="url" bind:value={stravaUrl} placeholder="https://strava.com/clubs/yourclub" maxlength="500" inputmode="url" />
		</label>
		<label class="link-field">
			<span>{m('clubEditor.facebook')}</span>
			<input type="url" bind:value={facebookUrl} placeholder="https://facebook.com/yourclub" maxlength="500" inputmode="url" />
		</label>
	</fieldset>

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

	{#if visibility === 'public' && !existing}
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
					<strong>{joinPolicyLabel('open')}</strong>
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
					<strong>{joinPolicyLabel('request')}</strong>
					<span class="hint">
						{m('clubEditor.approvalRequiredHint')}
					</span>
				</span>
			</label>
		</fieldset>
	{/if}

	{#if !existing}
		<label class="toggle-row">
			<input type="checkbox" bind:checked={requireWaiver} />
			<span>
				{m('clubEditor.waiverLabel')}
			</span>
		</label>
	{/if}

	<div class="actions">
		{#if oncancel}
			<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>{m('clubEditor.cancel')}</button>
		{/if}
		<button type="submit" class="btn btn-primary" disabled={!name.trim() || busy}>
			{#if existing}
				{busy ? m('clubEditor.saving') : m('clubEditor.saveChanges')}
			{:else}
				{busy ? m('clubEditor.creating') : m('clubEditor.createClub')}
			{/if}
		</button>
	</div>
</form>

