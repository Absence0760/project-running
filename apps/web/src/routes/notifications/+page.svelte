<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';

	// The notification inbox is a tab on the viewer's own profile, so it has no
	// standalone URL to link to. Emails and push payloads sent before that was
	// noticed carry /notifications, which resolved to nothing — this route makes
	// those keep working. The auth guard in +layout.svelte sends an anon visitor
	// to /login?return_to=/notifications first, so by here there is a session.
	onMount(async () => {
		await auth.ready();
		const id = auth.user?.id;
		await goto(id ? `/u/${id}?tab=notifications` : '/dashboard', { replaceState: true });
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
</svelte:head>

<div class="page">
	<p class="muted">{m('shell.loading')}</p>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
