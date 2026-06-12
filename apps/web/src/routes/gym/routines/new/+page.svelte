<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchGymExerciseNames } from '$lib/core/data';
	import RoutineEditor from '$lib/components/RoutineEditor.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let suggestions = $state<string[]>([]);

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		suggestions = await fetchGymExerciseNames();
	});

	function onCreated(id: string) {
		goto(`/gym/routines/${id}`);
	}
</script>

<svelte:head><title>{t('gym.routine.editor.newTitle')} — Threkir</title></svelte:head>

<div class="page">
	<header class="page-header">
		<a class="back-link" href="/gym/routines">
			<span class="material-symbols" aria-hidden="true">arrow_back</span>
			{t('gym.routine.back')}
		</a>
		<h1>{t('gym.routine.editor.newTitle')}</h1>
	</header>

	<div class="editor-wrap">
		<RoutineEditor {suggestions} oncreated={onCreated} oncancel={() => goto('/gym/routines')} />
	</div>
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--text-muted);
		font-size: 0.9rem;
	}
	.editor-wrap {
		margin-top: var(--space-md);
	}
</style>
