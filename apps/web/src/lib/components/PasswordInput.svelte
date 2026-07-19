<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';

	let {
		value = $bindable(''),
		id = undefined,
		placeholder = '',
		autocomplete = 'current-password',
		minlength = undefined,
		required = false,
		toggleDisabled = false
	}: {
		value?: string;
		id?: string;
		placeholder?: string;
		autocomplete?: AutoFill;
		minlength?: number | undefined;
		required?: boolean;
		toggleDisabled?: boolean;
	} = $props();

	let show = $state(false);
</script>

<div class="password-wrap">
	<input
		{id}
		type={show ? 'text' : 'password'}
		bind:value
		{placeholder}
		{required}
		{minlength}
		{autocomplete}
	/>
	<button
		type="button"
		class="password-toggle"
		disabled={toggleDisabled}
		onclick={() => (show = !show)}
		aria-label={show ? m('login.hidePassword') : m('login.showPassword')}
		aria-pressed={show}
	>
		<span class="material-symbols" aria-hidden="true">
			{show ? 'visibility_off' : 'visibility'}
		</span>
	</button>
</div>

<style>
	.password-wrap {
		position: relative;
	}

	.password-wrap input {
		width: 100%;
		padding: 0.7rem var(--space-md);
		padding-inline-end: 2.9rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.95rem;
		font-family: inherit;
		background: var(--color-surface);
		color: var(--color-text);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}

	.password-wrap input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-primary) 18%, transparent);
	}

	.password-wrap input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.password-toggle {
		position: absolute;
		top: 50%;
		inset-inline-end: var(--space-xs);
		transform: translateY(-50%);
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0.3rem;
		background: none;
		border: none;
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
		cursor: pointer;
	}

	.password-toggle:hover {
		color: var(--color-text);
	}

	.password-toggle:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.password-toggle .material-symbols {
		font-size: 20px;
	}
</style>
