<script lang="ts">
	import ChallengeEditor from '$lib/components/ChallengeEditor.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { goto } from '$app/navigation';
</script>

<svelte:head>
	<title>{m('challenges.create')}</title>
</svelte:head>

<div class="page narrow">
	<header class="page-head">
		<h1>{m('challenges.create')}</h1>
	</header>
	<ChallengeEditor
		oncreated={(ch) => goto(`/challenges/${ch.id}`)}
		oncancel={() => goto('/challenges')}
	/>
</div>

<style>
	.narrow {
		max-width: 40rem;
	}
</style>
