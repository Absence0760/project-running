<script lang="ts">
	import { onMount } from 'svelte';
	import { formatISO } from '$lib/training/training';
	import { goto, afterNavigate } from '$app/navigation';
	import { page } from '$app/stores';
	import PlanEditor from '$lib/components/PlanEditor.svelte';
	import SessionPlanEditor from '$lib/components/SessionPlanEditor.svelte';
	import RoutineEditor from '$lib/components/RoutineEditor.svelte';
	import {
		fetchMyClubs,
		fetchClubTemplates,
		clonePlanTemplate,
		createTrainingPlan,
		fetchGymExerciseNames,
	} from '$lib/core/data';
	import { STARTER_PLANS, starterById, instantiateStarter } from '$lib/training/starter_plans';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { TrainingPlan } from '$lib/types';

	interface TemplateOption {
		template: TrainingPlan;
		clubName: string;
	}

	type PlanKind = 'training' | 'session' | 'gym';

	function initialKind(): PlanKind {
		const t = $page.url.searchParams.get('type');
		return t === 'session' || t === 'gym' ? t : 'training';
	}

	// `?club=<id>` (set by a club's Templates-tab "New …" links) targets the
	// new artifact at that club. Honoured one-step only by the session branch —
	// session_plans support a club-owned create; training + gym templates are
	// build-then-publish, so the club param is informational there.
	const clubId = $page.url.searchParams.get('club');

	// An explicit `?type=` means the caller already chose the kind (a club's
	// contextual "New …" link) — skip the chooser so we don't ask twice. The
	// bare /plans/new entry (no type) shows the chooser to disambiguate.
	const explicitType = $page.url.searchParams.get('type');
	const showChooser = !(
		explicitType === 'training' || explicitType === 'session' || explicitType === 'gym'
	);

	let kind = $state<PlanKind>(initialKind());

	let templates = $state<TemplateOption[]>([]);
	let loadingTemplates = $state(true);
	let selectedTemplateId = $state('');
	let startDate = $state(defaultStartDate());
	let cloning = $state(false);
	let selectedStarterId = $state('');
	let creatingStarter = $state(false);
	let gymSuggestions = $state<string[]>([]);

	const headingKey = $derived(
		kind === 'session'
			? 'plansNew.headingSession'
			: kind === 'gym'
				? 'plansNew.headingGym'
				: 'plansNew.heading'
	);
	const taglineKey = $derived(
		kind === 'session'
			? 'plansNew.taglineSession'
			: kind === 'gym'
				? 'plansNew.taglineGym'
				: 'plansNew.tagline'
	);

	function onSessionCreated(id: string): void {
		// When created for a club, return to the Templates tab the link came
		// from so the new template is visible in its list; otherwise open it.
		if (clubId && backHref.startsWith('/clubs/')) goto(backHref);
		else goto(`/sessions/${id}`);
	}

	function onGymCreated(id: string): void {
		goto(`/gym/routines/${id}`);
	}

	// Back/cancel target. Defaults to /plans; when the user arrived from a
	// club's Templates tab (the "Adopt" link), return them there instead.
	let backHref = $state('/plans');
	let backLabel = $state(m('plansNew.backToPlans'));
	let backViaHistory = $state(false);
	let backCaptured = $state(false);
	afterNavigate(({ from }) => {
		if (backCaptured || !from) return;
		if (from.url.pathname === '/plans' || from.url.pathname.startsWith('/plans?')) {
			backViaHistory = true;
			backCaptured = true;
		} else if (
			from.url.pathname.startsWith('/clubs/') &&
			from.url.searchParams.get('tab') === 'templates'
		) {
			backHref = from.url.pathname + from.url.search;
			backLabel = m('plansNew.backToClubTemplates');
			backCaptured = true;
		}
	});

	function handleBack(e: MouseEvent): void {
		if (backViaHistory) {
			e.preventDefault();
			history.back();
		}
	}

	function handleCancel(): void {
		if (backViaHistory) history.back();
		else goto(backHref);
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
			// Pre-select the template a club's "Adopt" deep link points at
			// (/plans/new?from=<templateId>). Only honour it when it's one of
			// the user's loaded club templates — a stale or foreign id leaves
			// the picker on its placeholder rather than a phantom selection.
			const from = $page.url.searchParams.get('from');
			if (from && templates.some((t) => t.template.id === from)) {
				selectedTemplateId = from;
			}
		} catch (e) {
			console.warn('fetch templates failed', e);
		} finally {
			loadingTemplates = false;
		}
		try {
			gymSuggestions = await fetchGymExerciseNames();
		} catch (e) {
			console.warn('fetch gym exercise names failed', e);
		}
	});

	async function cloneSelected() {
		if (!selectedTemplateId || !startDate) return;
		cloning = true;
		try {
			const newPlanId = await clonePlanTemplate(selectedTemplateId, startDate);
			showToast(m('plansNew.toastCreated'));
			goto(`/plans/${newPlanId}`);
		} catch (e) {
			showToast(m('plansNew.toastCloneFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			cloning = false;
		}
	}

	/// Localized display name per starter id (literal m() keys so the i18n
	/// parity tooling can see them).
	function starterName(id: string): string {
		switch (id) {
			case 'c25k':
				return m('plansNew.starterC25k');
			case 'half_12wk':
				return m('plansNew.starterHalf12');
			case 'marathon_16wk':
				return m('plansNew.starterMarathon16');
			default:
				return id;
		}
	}

	async function createFromStarter() {
		if (!selectedStarterId || !startDate || creatingStarter) return;
		const starter = starterById(selectedStarterId);
		const generated = instantiateStarter(selectedStarterId, startDate);
		if (!starter || !generated) return;
		creatingStarter = true;
		try {
			const plan = await createTrainingPlan({
				name: starterName(selectedStarterId),
				goalEvent: starter.goalEvent,
				goalDistanceM: generated.goalDistanceM,
				startDate,
				daysPerWeek: starter.daysPerWeek,
				generated
			});
			showToast(m('plansNew.toastCreated'));
			goto(`/plans/${plan.id}`);
		} catch (e) {
			showToast(
				m('plansNew.toastCreateFailed', { error: e instanceof Error ? e.message : String(e) }),
				'error'
			);
		} finally {
			creatingStarter = false;
		}
	}
</script>

<svelte:head>
	<title>{m('plansNew.pageTitle')}</title>
</svelte:head>

<div class="page">
	<a href={backHref} class="back-link" onclick={handleBack}>
		<span class="material-symbols">arrow_back</span>
		{backLabel}
	</a>

	<p class="kicker">{m('plansNew.kicker')}</p>

	{#if showChooser}
		<div class="kind-chooser" role="group" aria-label={m('plansNew.chooserLabel')}>
			<button
				type="button"
				class="kind-tab"
				class:active={kind === 'training'}
				aria-pressed={kind === 'training'}
				onclick={() => (kind = 'training')}
				data-testid="kind-training"
			>
				{m('plansNew.kindTraining')}
			</button>
			<button
				type="button"
				class="kind-tab"
				class:active={kind === 'session'}
				aria-pressed={kind === 'session'}
				onclick={() => (kind = 'session')}
				data-testid="kind-session"
			>
				{m('plansNew.kindSession')}
			</button>
			<button
				type="button"
				class="kind-tab"
				class:active={kind === 'gym'}
				aria-pressed={kind === 'gym'}
				onclick={() => (kind = 'gym')}
				data-testid="kind-gym"
			>
				{m('plansNew.kindGym')}
			</button>
		</div>
	{/if}

	<header class="page-header">
		<h1>{m(headingKey)}</h1>
		<p class="tagline">
			{m(taglineKey)}
		</p>
	</header>

	{#if kind === 'training'}
	{#if clubId}
		<p class="picker-hint club-target-note">{m('plansNew.clubPublishNote')}</p>
	{/if}
	<section class="starter-picker">
		<h2>{m('plansNew.starterHeading')}</h2>
		<p class="picker-hint">{m('plansNew.starterHint')}</p>
		<div class="picker-row">
			<label class="picker-field">
				<span>{m('plansNew.starterLabel')}</span>
				<select bind:value={selectedStarterId}>
					<option value="">{m('plansNew.selectPlaceholder')}</option>
					{#each STARTER_PLANS as s (s.id)}
						<option value={s.id}>{starterName(s.id)}</option>
					{/each}
				</select>
			</label>
			<label class="picker-field">
				<span>{m('plansNew.startDateLabel')}</span>
				<input type="date" bind:value={startDate} />
			</label>
			<button
				class="btn btn-primary"
				type="button"
				disabled={!selectedStarterId || !startDate || creatingStarter}
				onclick={createFromStarter}
			>
				{#if creatingStarter}
					<span class="btn-spinner" aria-hidden="true"></span>
					{m('plansNew.creating')}
				{:else}
					{m('plansNew.createStarter')}
				{/if}
			</button>
		</div>
	</section>

	{#if !loadingTemplates && templates.length > 0}
		<section class="template-picker">
			<h2>{m('plansNew.templateHeading')}</h2>
			<p class="picker-hint">
				{m('plansNew.templateHint')}
			</p>
			<div class="picker-row">
				<label class="picker-field">
					<span>{m('plansNew.templateLabel')}</span>
					<select bind:value={selectedTemplateId}>
						<option value="">{m('plansNew.selectPlaceholder')}</option>
						{#each templates as t (t.template.id)}
							<option value={t.template.id}>
								{t.template.name} — {t.clubName}
							</option>
						{/each}
					</select>
				</label>
				<label class="picker-field">
					<span>{m('plansNew.startDateLabel')}</span>
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
						{m('plansNew.cloning')}
					{:else}
						{m('plansNew.cloneTemplate')}
					{/if}
				</button>
			</div>
		</section>
	{/if}

	<div class="or-rule"><span>{m('plansNew.orFromScratch')}</span></div>

	<PlanEditor
		oncreated={(plan) => goto(`/plans/${plan.id}`)}
		oncancel={handleCancel}
	/>
	{:else if kind === 'session'}
		<div class="form-branch">
			{#if clubId}
				<p class="picker-hint club-target-note">{m('plansNew.sessionForClub')}</p>
			{/if}
			<SessionPlanEditor {clubId} oncreated={onSessionCreated} oncancel={handleCancel} />
		</div>
	{:else}
		<div class="form-branch">
			{#if clubId}
				<p class="picker-hint club-target-note">{m('plansNew.clubPublishNote')}</p>
			{/if}
			<RoutineEditor suggestions={gymSuggestions} oncreated={onGymCreated} oncancel={handleCancel} />
		</div>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	/* The session + gym branches are focused single-form editors — cap their
	   content so fields don't stretch the full viewport on a wide screen
	   (conventions § Web page padding). The training branch is a two-column
	   wizard (PlanEditor) and stays uncapped so its calendar pane keeps room. */
	.form-branch {
		max-width: 48rem;
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
		margin: 0 0 var(--space-sm);
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

	.kind-chooser {
		display: inline-flex;
		gap: 0.25rem;
		padding: 0.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		margin-bottom: var(--space-lg);
	}
	.kind-tab {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		font-weight: 600;
		/* Equal width per tab so the active highlight never shifts the row. */
		min-width: 8.5rem;
		text-align: center;
		white-space: nowrap;
		padding: 0.5rem 1rem;
		border-radius: var(--radius-md);
		cursor: pointer;
		transition: background 0.12s ease, color 0.12s ease;
	}
	.kind-tab:hover:not(.active) {
		color: var(--color-text);
		background: color-mix(in srgb, var(--color-text) 6%, transparent);
	}
	.kind-tab.active {
		background: var(--color-primary);
		color: var(--color-on-primary, #fff);
	}
	.club-target-note {
		margin-bottom: var(--space-md);
	}

	.template-picker,
	.starter-picker {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-lg);
	}
	.template-picker h2,
	.starter-picker h2 {
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
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
		transition: border-color var(--transition-fast);
	}
	.picker-field select:focus-visible,
	.picker-field input:focus-visible {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
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
		margin-inline-end: 0.35em;
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
