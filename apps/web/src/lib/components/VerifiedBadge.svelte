<!--
	Verified-club badge — a small ✓-in-a-circle icon shown next to a
	club's name (or an event title whose parent club is verified)
	indicating the entity has been manually confirmed as the
	authentic operator.

	Why this exists: `clubs.name` is NOT unique (only `clubs.slug`
	is), so a fan can register "Richmond Marathon" before the
	official organisation does. The badge differentiates the
	verified-as-official surface from the squatter / fan surface.

	Twin of the Flutter `VerifiedBadge` widget; both render the
	same icon + accessible label so cross-platform users learn one
	mark.
-->
<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';

	interface Props {
		size?: number;
		title?: string;
	}
	let { size = 16, title }: Props = $props();
	// Default the accessible label to the localized standard copy when a
	// caller doesn't pass one (which is every caller today) — the Flutter
	// twin already does this, so web was the only side shipping a
	// hardcoded-English label to screen readers.
	const label = $derived(title ?? m('verifiedBadge.tooltip'));
</script>

<span
	class="verified-badge"
	style="--badge-size: {size}px"
	title={label}
	aria-label={label}
	data-testid="verified-badge"
>
	<svg
		viewBox="0 0 24 24"
		width={size}
		height={size}
		aria-hidden="true"
		focusable="false"
	>
		<!--
			Two-tone twelve-point ribbon mirroring Twitter / Strava's
			verified mark — slight wave around the outside so the
			check sits inside a recognisable "official" envelope.
		-->
		<path
			fill="currentColor"
			d="M12 2.25l1.6 1.43 2.16-.32.63 2.08 2.06.68-.32 2.16 1.43 1.6-1.43 1.6.32 2.16-2.06.68-.63 2.08-2.16-.32L12 21.75l-1.6-1.43-2.16.32-.63-2.08-2.06-.68.32-2.16L4.44 14l1.43-1.6-.32-2.16 2.06-.68.63-2.08 2.16.32L12 2.25z"
		/>
		<path
			fill="#fff"
			d="M10.6 14.6l-2.4-2.4 1.4-1.4 1 1 3.6-3.6 1.4 1.4-5 5z"
		/>
	</svg>
</span>

<style>
	.verified-badge {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		color: #2563eb;
		vertical-align: middle;
		margin-inline-start: 4px;
		line-height: 0;
	}
	.verified-badge svg {
		display: block;
		width: var(--badge-size);
		height: var(--badge-size);
	}
</style>
