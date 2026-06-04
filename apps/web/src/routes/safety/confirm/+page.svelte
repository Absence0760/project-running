<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { confirmSafetyContactByToken } from '$lib/core/data';
	import { m } from '$lib/i18n/store.svelte';

	type State = 'working' | 'success' | 'failure' | 'missing';
	let state = $state<State>('working');

	onMount(async () => {
		const token = $page.url.searchParams.get('token');
		if (!token) {
			state = 'missing';
			return;
		}
		try {
			state = (await confirmSafetyContactByToken(token)) ? 'success' : 'failure';
		} catch (_) {
			state = 'failure';
		}
	});

	const message = $derived(
		state === 'working'
			? m('safetyConfirm.working')
			: state === 'success'
				? m('safetyConfirm.success')
				: state === 'missing'
					? m('safetyConfirm.missingToken')
					: m('safetyConfirm.failure'),
	);
</script>

<svelte:head>
	<title>{m('safetyConfirm.title')}</title>
</svelte:head>

<main class="confirm-card">
	<div class="card" data-testid="safety-confirm-card" data-state={state}>
		<h1>{m('safetyConfirm.title')}</h1>
		<p class:ok={state === 'success'} class:bad={state === 'failure' || state === 'missing'}>
			{message}
		</p>
		{#if state !== 'working'}
			<a class="btn-primary" href="/">{m('safetyConfirm.home')}</a>
		{/if}
	</div>
</main>

<style>
	.confirm-card {
		min-height: 100vh;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 1.5rem;
		background: var(--color-bg, #f4f5f7);
	}
	.card {
		max-width: 440px;
		width: 100%;
		background: #fff;
		border-radius: 14px;
		padding: 2rem;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
		text-align: center;
	}
	h1 {
		margin: 0 0 1rem;
		font-size: 1.4rem;
	}
	p {
		margin: 0 0 1.5rem;
		line-height: 1.5;
		color: var(--color-text, #374151);
	}
	p.ok {
		color: var(--color-primary, #2c5f6e);
	}
	p.bad {
		color: var(--color-danger, #b91c1c);
	}
	.btn-primary {
		display: inline-block;
		background: var(--color-primary, #2c5f6e);
		color: #fff;
		text-decoration: none;
		border-radius: 8px;
		padding: 0.6rem 1.3rem;
		font-weight: 600;
	}
</style>
