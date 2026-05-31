<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';

	interface Option {
		value: string;
		label: string;
		/// Optional secondary line under the label (e.g. plan status).
		sub?: string;
	}

	interface Props {
		value: string;
		options: Option[];
		onChange: (next: string) => void;
		/// Material Symbols ligature shown as the leading icon.
		icon?: string;
		/// Static text rendered before the selected value (e.g. "Last").
		prefix?: string;
		/// Static text rendered after the selected value (e.g. "· 12w").
		suffix?: string;
		ariaLabel: string;
		title?: string;
		/// Extra classes for the trigger so the host can apply variants
		/// (e.g. `chip-muted` when the picker is showing the empty
		/// option).
		triggerClass?: string;
	}
	let {
		value,
		options,
		onChange,
		icon,
		prefix,
		suffix,
		ariaLabel,
		title,
		triggerClass = ''
	}: Props = $props();

	let open = $state(false);
	let trigger: HTMLButtonElement | null = $state(null);
	let panel: HTMLDivElement | null = $state(null);
	let activeIndex = $state(0);

	let current = $derived(options.find((o) => o.value === value) ?? null);

	async function toggle() {
		open = !open;
		if (open) {
			activeIndex = Math.max(
				options.findIndex((o) => o.value === value),
				0
			);
			await tick();
			focusActiveOption();
		}
	}

	function close() {
		open = false;
	}

	function pick(v: string) {
		open = false;
		if (v !== value) onChange(v);
		trigger?.focus();
	}

	function onDocClick(e: MouseEvent) {
		if (!open) return;
		const target = e.target as Node | null;
		if (panel?.contains(target ?? null)) return;
		if (trigger?.contains(target ?? null)) return;
		close();
	}

	function onKeydown(e: KeyboardEvent) {
		if (!open) {
			if ((e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') && document.activeElement === trigger) {
				e.preventDefault();
				toggle();
			}
			return;
		}
		if (e.key === 'Escape') {
			e.preventDefault();
			close();
			trigger?.focus();
		} else if (e.key === 'ArrowDown') {
			e.preventDefault();
			activeIndex = (activeIndex + 1) % options.length;
			focusActiveOption();
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			activeIndex = (activeIndex - 1 + options.length) % options.length;
			focusActiveOption();
		} else if (e.key === 'Home') {
			e.preventDefault();
			activeIndex = 0;
			focusActiveOption();
		} else if (e.key === 'End') {
			e.preventDefault();
			activeIndex = options.length - 1;
			focusActiveOption();
		} else if (e.key === 'Enter') {
			e.preventDefault();
			pick(options[activeIndex]?.value ?? value);
		}
	}

	function focusActiveOption() {
		if (!panel) return;
		const items = panel.querySelectorAll<HTMLElement>('[role="option"]');
		items[activeIndex]?.focus();
	}

	onMount(() => {
		document.addEventListener('mousedown', onDocClick);
		document.addEventListener('keydown', onKeydown);
	});
	onDestroy(() => {
		document.removeEventListener('mousedown', onDocClick);
		document.removeEventListener('keydown', onKeydown);
	});
</script>

<div class="chip-dropdown">
	<button
		bind:this={trigger}
		type="button"
		class="chip chip-select-trigger {triggerClass}"
		onclick={toggle}
		aria-haspopup="listbox"
		aria-expanded={open}
		aria-label={ariaLabel}
		{title}
	>
		{#if icon}<span class="material-symbols">{icon}</span>{/if}
		{#if prefix}<span class="prefix">{prefix}</span>{/if}
		<span class="value">{current?.label ?? '—'}</span>
		{#if suffix}<span class="chip-meta">{suffix}</span>{/if}
		<span class="material-symbols caret" class:open>expand_more</span>
	</button>

	{#if open}
		<div bind:this={panel} class="popover" role="listbox">
			{#each options as o, i (o.value)}
				<button
					type="button"
					class="opt"
					class:selected={o.value === value}
					class:active={i === activeIndex}
					role="option"
					aria-selected={o.value === value}
					tabindex={-1}
					onclick={() => pick(o.value)}
					onmouseenter={() => (activeIndex = i)}
				>
					<span class="opt-label">{o.label}</span>
					{#if o.sub}<span class="opt-sub">{o.sub}</span>{/if}
				</button>
			{/each}
		</div>
	{/if}
</div>

<style>
	.chip-dropdown {
		position: relative;
		display: inline-flex;
	}
	/* The trigger reuses .chip styling (defined by the host) and adds
	   only the bits the chip-as-button needs: a caret, a hand cursor,
	   a focus ring. The .chip and .chip-muted classes carry the
	   colour. */
	.chip-select-trigger {
		background: inherit;
		border: 1px solid transparent;
		font: inherit;
		color: inherit;
		cursor: pointer;
		max-width: 18rem;
	}
	.chip-select-trigger:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.value {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.prefix {
		opacity: 0.85;
	}
	.caret {
		transition: transform var(--transition-fast);
		opacity: 0.7;
	}
	.caret.open {
		transform: rotate(180deg);
	}

	/* Popover panel — themed dropdown that replaces the OS-rendered
	   <select> popup. Anchored under the trigger; min-width matches
	   the trigger so the panel is at least as wide. */
	.popover {
		position: absolute;
		top: calc(100% + 0.3rem);
		inset-inline-start: 0;
		z-index: 60;
		min-width: 100%;
		max-width: 22rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.16);
		padding: 0.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.05rem;
		max-height: 16rem;
		overflow-y: auto;
	}
	.opt {
		display: flex;
		flex-direction: column;
		gap: 0.05rem;
		text-align: start;
		background: transparent;
		border: none;
		font: inherit;
		color: var(--color-text);
		padding: 0.4rem 0.55rem;
		border-radius: var(--radius-sm);
		cursor: pointer;
		min-width: 0;
	}
	.opt:hover,
	.opt.active {
		background: var(--color-bg-secondary);
	}
	.opt.selected {
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	.opt-label {
		font-size: 0.82rem;
		line-height: 1.3;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.opt-sub {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
	}
	.opt.selected .opt-sub {
		color: inherit;
		opacity: 0.7;
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 0.85rem;
		line-height: 1;
	}
	.caret {
		font-size: 0.95rem;
	}
</style>
