<script lang="ts">
	import { page } from '$app/state';
	import { confirmSafetyContactByToken } from '$lib/core/data';
	import { m } from '$lib/i18n/store.svelte';

	type Phase = 'prompt' | 'working' | 'success' | 'failure' | 'missing';
	// The anon token flow can't read whether the owner stored a phone, so we
	// always offer the opt-in and let the RPC force it null when there's no
	// number on file.
	const token = page.url.searchParams.get('token');
	let phase = $state<Phase>(token ? 'prompt' : 'missing');
	let smsOptIn = $state(false);

	async function confirm() {
		if (!token) return;
		phase = 'working';
		try {
			phase = (await confirmSafetyContactByToken(token, smsOptIn)) ? 'success' : 'failure';
		} catch (_) {
			phase = 'failure';
		}
	}

	const message = $derived(
		phase === 'prompt'
			? m('safetyConfirm.prompt')
			: phase === 'working'
				? m('safetyConfirm.working')
				: phase === 'success'
					? m('safetyConfirm.success')
					: phase === 'missing'
						? m('safetyConfirm.missingToken')
						: m('safetyConfirm.failure'),
	);
</script>

<svelte:head>
	<title>{m('safetyConfirm.title')}</title>
</svelte:head>

<main class="confirm-card">
	<div class="card" data-testid="safety-confirm-card" data-state={phase}>
		<h1>{m('safetyConfirm.title')}</h1>
		<p class:ok={phase === 'success'} class:bad={phase === 'failure' || phase === 'missing'}>
			{message}
		</p>
		{#if phase === 'prompt'}
			<label class="sms-opt">
				<input type="checkbox" bind:checked={smsOptIn} data-testid="safety-confirm-sms" />
				<span>{m('safety.confirmSmsLabel')}</span>
			</label>
			<button class="btn-primary" onclick={confirm} data-testid="safety-confirm-button">
				{m('safetyConfirm.confirmButton')}
			</button>
		{:else if phase !== 'working'}
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
		border: none;
		cursor: pointer;
		font-size: 1rem;
		border-radius: 8px;
		padding: 0.6rem 1.3rem;
		font-weight: 600;
	}
	.sms-opt {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		justify-content: center;
		margin: 0 0 1.25rem;
		font-size: 0.92rem;
		color: var(--color-text, #374151);
		cursor: pointer;
	}
</style>
