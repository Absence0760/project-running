<script lang="ts">
	import { initial, hashHue } from '$lib/avatar';

	type BgMode = 'gradient' | 'primary' | 'seed';

	let {
		url = null,
		name = null,
		size,
		font,
		bg = 'gradient',
		/** Saturation % for the `seed` background (50 or 55 in existing call sites). */
		sat = 55,
		/** Hue (0–359) for `bg="seed"`. Pass `hashHue(id)` for per-entity colour;
		 *  omit for the fixed default. */
		seedHue = null,
	}: {
		url?: string | null;
		name?: string | null;
		size: string;
		font: string;
		bg?: BgMode;
		sat?: number;
		seedHue?: number | null;
	} = $props();

	const background = $derived(
		bg === 'seed'
			? `hsl(${seedHue ?? 260}, ${sat}%, 55%)`
			: bg === 'primary'
				? 'var(--color-primary)'
				: 'var(--gradient-primary)',
	);
</script>

<span
	class="avatar"
	style="--av-size: {size}; --av-font: {font}; --av-bg: {background};"
	aria-hidden="true"
>
	{#if url}
		<img src={url} alt="" />
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
		color: white;
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
