<script lang="ts">
	import { initial, hashHue, seedBackground, seedForeground } from '$lib/format/avatar';
	import { safeImageSrc } from '$lib/util/safe_image_src';

	type BgMode = 'gradient' | 'primary' | 'seed';

	let {
		url = null,
		name = null,
		size,
		font,
		bg = 'gradient',
		/** Hue (0–359) for `bg="seed"`. Pass `hashHue(id)` for per-entity colour;
		 *  omit for the fixed default. */
		seedHue = null,
	}: {
		url?: string | null;
		name?: string | null;
		size: string;
		font: string;
		bg?: BgMode;
		seedHue?: number | null;
	} = $props();

	const safeUrl = $derived(safeImageSrc(url));

	const hue = $derived(seedHue ?? 260);
	const background = $derived(
		bg === 'seed'
			? seedBackground(hue)
			: bg === 'primary'
				? 'var(--color-primary)'
				: 'var(--gradient-avatar)',
	);
	// The two theme-token modes pair with --color-on-primary; a seeded hue is
	// theme-independent and picks its own ink by computed contrast (§ 481).
	const foreground = $derived(
		bg === 'seed' ? seedForeground(hue) : 'var(--color-on-primary)',
	);
</script>

<span
	class="avatar"
	style="--av-size: {size}; --av-font: {font}; --av-bg: {background}; --av-fg: {foreground};"
	aria-hidden="true"
>
	{#if safeUrl}
		<img src={safeUrl} alt="" />
	{:else}
		{initial(name)}
	{/if}
</span>

<style>
	.avatar {
		width: var(--av-size);
		height: var(--av-size);
		flex-shrink: 0;
		border-radius: 50%;
		background: var(--av-bg);
		color: var(--av-fg);
		display: grid;
		place-items: center;
		font-weight: 700;
		font-size: var(--av-font);
		overflow: hidden;
	}
	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
</style>
