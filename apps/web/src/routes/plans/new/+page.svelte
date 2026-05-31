<script lang="ts">
	import { onMount } from 'svelte';
	import { formatISO } from '$lib/training/training';
	import { goto, afterNavigate } from '$app/navigation';
	import PlanEditor from '$lib/components/PlanEditor.svelte';
	import {
		fetchMyClubs,
		fetchClubTemplates,
		clonePlanTemplate,
	} from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';
	import type { TrainingPlan } from '$lib/types';

	interface TemplateOption {
		template: TrainingPlan;
		clubName: string;
	}

	let templates = $state<TemplateOption[]>([]);
	let loadingTemplates = $state(true);
	let selectedTemplateId = $state('');
	let startDate = $state(defaultStartDate());
	let cloning = $state(false);

	let cameFromPlans = $state(false);
	afterNavigate(({ from }) => {
		if (cameFromPlans || !from) return;
		if (from.url.pathname === '/plans' || from.url.pathname.startsWith('/plans?')) {
			cameFromPlans = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (cameFromPlans) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (cameFromPlans) history.back();
		else goto('/plans');
	}

	function defaultStartDate(): string {
		const d = new Date();
		// Snap to the next Monday — that's the canonical week-start the
		// schedule generator assumes.
		const offset = (8 - d.getDay()) % 7;
		d.setDate(d.getDate() + (offset === 0 ? 7 : offset));
		return formatISO(d);
	}

	onMount(async () => {
		try {
			const clubs = await fetchMyClubs();
			const lists = await Promise.all(
				clubs.map(async (c) => {
					const list = await fetchClubTemplates(c.id);
					return list.map((template) => ({ template, clubName: c.name }));
				})
			);
			templates = lists.flat();
		} catch (e) {
			console.warn('fetch templates failed', e);
		} finally {
			loadingTemplates = false;
		}
	});

	async function cloneSelected() {
		if (!selectedTemplateId || !startDate) return;
		cloning = true;
		try {
			const newPlanId = await clonePlanTemplate(selectedTemplateId, startDate);
			showToast('Plan created from template.');
			goto(`/plans/${newPlanId}`);
		} catch (e) {
			showToast(`Failed to clone template: ${e}`, 'error');
		} finally {
			cloning = false;
		}
	}
</script>

<svelte:head>
	<title>New plan — Threkir</title>
</svelte:head>

<div class="page">
	<a href="/plans" class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		Back to plans
	</a>

	<header class="page-header">
		<p class="kicker">New plan</p>
		<h1>Build a training plan</h1>
		<p class="tagline">
			Pick a goal race and we'll schedule the phases, long runs, and quality sessions for you.
			Every week is editable before you commit — adjust days per week, target paces, or
			individual workouts as you go.
		</p>
	</header>

	{#if !loadingTemplates && templates.length > 0}
		<section class="template-picker">
			<h2>Start from a club template</h2>
			<p class="picker-hint">
				Clone a coach- or club-authored plan and anchor it to a start date you choose. The
				clone is your own copy — edits won't sync back to the template.
			</p>
			<div class="picker-row">
				<label class="picker-field">
					<span>Template</span>
					<select bind:value={selectedTemplateId}>
						<option value="">— select —</option>
						{#each templates as t (t.template.id)}
							<option value={t.template.id}>
								{t.template.name} — {t.clubName}
							</option>
						{/each}
					</select>
				</label>
				<label class="picker-field">
					<span>Start date</span>
					<input type="date" bind:value={startDate} />
				</label>
				<button
					class="btn btn-primary"
					type="button"
					disabled={!selectedTemplateId || !startDate || cloning}
					onclick={cloneSelected}
				>
					{#if cloning}
						<span class="btn-spinner" aria-hidden="true"></span>
						Cloning…
					{:else}
						Clone template
					{/if}
				</button>
			</div>
		</section>

		<div class="or-rule"><span>or build a plan from scratch</span></div>
	{/if}

	<PlanEditor
		oncreated={(plan) => goto(`/plans/${plan.id}`)}
		oncancel={handleCancel}
	/>
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		padding: var(--space-xs) 0;
		margin-bottom: var(--space-md);
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	.page-header {
		margin-bottom: var(--space-xl);
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-2xs);
	}
	h1 {
		font-size: 1.75rem;
		font-weight: 800;
		line-height: 1.2;
		margin: 0 0 var(--space-xs);
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
	}

	.template-picker {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-lg);
	}
	.template-picker h2 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0 0 0.2rem 0;
	}
	.picker-hint {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin: 0 0 var(--space-md) 0;
	}
	.picker-row {
		display: flex;
		gap: var(--space-md);
		flex-wrap: wrap;
		align-items: flex-end;
	}
	.picker-field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		min-width: 12rem;
	}
	.picker-field span {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.picker-field select,
	.picker-field input {
		padding: 0.45rem 0.75rem;
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
	}

	.or-rule {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		margin: var(--space-lg) 0;
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.or-rule::before,
	.or-rule::after {
		content: '';
		flex: 1;
		height: 1px;
		background: var(--color-border);
	}

	.btn-spinner {
		display: inline-block;
		width: 0.85em;
		height: 0.85em;
		margin-right: 0.35em;
		border: 2px solid color-mix(in srgb, currentColor 40%, transparent);
		border-top-color: currentColor;
		border-radius: 50%;
		vertical-align: -0.1em;
		animation: btn-spin 0.6s linear infinite;
	}
	@keyframes btn-spin {
		to { transform: rotate(360deg); }
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
</style>
