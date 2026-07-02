<script lang="ts">
	import { onMount } from 'svelte';
	import {
		fetchRouteConditionsWithError,
		addRouteCondition,
		deleteRouteCondition,
	} from '$lib/core/data';
	import type { RouteCondition, RouteConditionKind, RouteConditionSeverity } from '$lib/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { formatRelativeTime } from '$lib/format/time';
	import { formatDistance } from '$lib/format/units.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';

	interface Props {
		routeId: string;
		routeOwnerId: string;
		/// When false (a shared/public read-only view) the report composer is
		/// hidden even for a signed-in viewer. Defaults to true.
		canReport?: boolean;
		wrapperClass?: string;
	}
	let { routeId, routeOwnerId, canReport = true, wrapperClass = 'card' }: Props = $props();

	const CONDITION_KINDS: RouteConditionKind[] = [
		'clear',
		'muddy',
		'flooded',
		'snow_ice',
		'overgrown',
		'closed',
		'hazard',
		'other',
	];
	const SEVERITIES: RouteConditionSeverity[] = ['info', 'caution', 'impassable'];

	// Reports older than this fade — a month-old "muddy" is weaker signal than a
	// fresh one. Never deleted (decisions §171 freshness policy): the reporter or
	// route owner can delete; the UI just fades by age.
	const FADE_AFTER_DAYS = 30;

	let conditions = $state<RouteCondition[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let submitting = $state(false);
	let confirmDelete = $state<RouteCondition | null>(null);

	let composerOpen = $state(false);
	let kind = $state<RouteConditionKind>('muddy');
	let severity = $state<RouteConditionSeverity>('caution');
	let note = $state('');

	let signedIn = $derived(auth.user != null);
	let showComposer = $derived(canReport && signedIn);

	async function load() {
		loading = true;
		loadError = null;
		try {
			const res = await fetchRouteConditionsWithError(routeId);
			if (res.error) {
				loadError = res.error;
				return;
			}
			conditions = res.conditions;
		} catch (e) {
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function conditionLabel(k: RouteConditionKind): string {
		switch (k) {
			case 'clear':
				return m('routeConditions.kind.clear');
			case 'muddy':
				return m('routeConditions.kind.muddy');
			case 'flooded':
				return m('routeConditions.kind.flooded');
			case 'snow_ice':
				return m('routeConditions.kind.snowIce');
			case 'overgrown':
				return m('routeConditions.kind.overgrown');
			case 'closed':
				return m('routeConditions.kind.closed');
			case 'hazard':
				return m('routeConditions.kind.hazard');
			case 'other':
				return m('routeConditions.kind.other');
		}
	}

	function severityLabel(s: RouteConditionSeverity): string {
		switch (s) {
			case 'info':
				return m('routeConditions.severity.info');
			case 'caution':
				return m('routeConditions.severity.caution');
			case 'impassable':
				return m('routeConditions.severity.impassable');
		}
	}

	function ageDays(iso: string): number {
		return (Date.now() - new Date(iso).getTime()) / 86_400_000;
	}

	function isStale(c: RouteCondition): boolean {
		return ageDays(c.created_at) > FADE_AFTER_DAYS;
	}

	function canDelete(c: RouteCondition): boolean {
		return auth.user?.id === c.user_id || auth.user?.id === routeOwnerId;
	}

	async function submit() {
		if (submitting) return;
		submitting = true;
		try {
			const created = await addRouteCondition({
				route_id: routeId,
				condition: kind,
				severity,
				note: note.trim() || null,
			});
			conditions = [created, ...conditions];
			note = '';
			composerOpen = false;
			showToast(m('routeConditions.reported'), 'success');
		} catch (e: any) {
			showToast(e?.message ?? m('routeConditions.reportFailed'), 'error');
		} finally {
			submitting = false;
		}
	}

	async function doDelete(c: RouteCondition) {
		try {
			await deleteRouteCondition(c.id);
			conditions = conditions.filter((x) => x.id !== c.id);
		} catch (e: any) {
			showToast(e?.message ?? m('routeConditions.deleteFailed'), 'error');
		} finally {
			confirmDelete = null;
		}
	}
</script>

<section class={wrapperClass}>
	<div class="conditions-header">
		<h3>{m('routeConditions.title')}</h3>
		{#if showComposer && !composerOpen}
			<button class="btn btn-secondary btn-sm" onclick={() => (composerOpen = true)}>
				{m('routeConditions.report')}
			</button>
		{/if}
	</div>

	{#if composerOpen}
		<form
			class="editor-form condition-composer"
			onsubmit={(e) => {
				e.preventDefault();
				submit();
			}}
		>
			<div class="composer-row">
				<label>
					{m('routeConditions.kindLabel')}
					<select bind:value={kind}>
						{#each CONDITION_KINDS as k}
							<option value={k}>{conditionLabel(k)}</option>
						{/each}
					</select>
				</label>
				<label>
					{m('routeConditions.severityLabel')}
					<select bind:value={severity}>
						{#each SEVERITIES as s}
							<option value={s}>{severityLabel(s)}</option>
						{/each}
					</select>
				</label>
			</div>
			<label>
				{m('routeConditions.noteLabel')}
				<textarea
					bind:value={note}
					rows="2"
					maxlength="500"
					placeholder={m('routeConditions.notePlaceholder')}
				></textarea>
			</label>
			<div class="composer-actions">
				<button type="button" class="btn btn-outline btn-sm" onclick={() => (composerOpen = false)}>
					{m('routeConditions.cancel')}
				</button>
				<button type="submit" class="btn btn-primary btn-sm" disabled={submitting}>
					{submitting ? m('routeConditions.reporting') : m('routeConditions.report')}
				</button>
			</div>
		</form>
	{/if}

	{#if loading}
		<p class="muted">{m('routeConditions.loading')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('routesPage.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline btn-sm" onclick={load}>{m('routesPage.retry')}</button>
		</div>
	{:else if conditions.length === 0}
		<p class="muted empty">{m('routeConditions.empty')}</p>
	{:else}
		<ul class="conditions-list">
			{#each conditions as c (c.id)}
				<li class="condition" class:stale={isStale(c)}>
					<div class="condition-main">
						<span class="chip severity-{c.severity}">{conditionLabel(c.condition)}</span>
						<span class="sev-tag severity-{c.severity}">{severityLabel(c.severity)}</span>
						{#if c.position_m != null}
							<span class="at-km">{m('routeConditions.atDistance', { distance: formatDistance(c.position_m) })}</span>
						{/if}
						<span class="age">{formatRelativeTime(c.created_at)}</span>
						{#if canDelete(c)}
							<button
								class="delete-btn"
								title={m('routeConditions.delete')}
								aria-label={m('routeConditions.delete')}
								onclick={() => (confirmDelete = c)}>×</button
							>
						{/if}
					</div>
					{#if c.note}
						<p class="condition-note">{c.note}</p>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</section>

<ConfirmDialog
	open={confirmDelete != null}
	title={m('routeConditions.deleteTitle')}
	message={m('routeConditions.deleteConfirm')}
	confirmLabel={m('routeConditions.delete')}
	danger
	onconfirm={() => {
		if (confirmDelete) doDelete(confirmDelete);
	}}
	oncancel={() => {
		confirmDelete = null;
	}}
/>

<style>
	.conditions-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		margin-bottom: var(--space-sm);
	}
	.conditions-header h3 {
		margin: 0;
	}
	.condition-composer {
		margin-bottom: var(--space-md);
	}
	.composer-row {
		display: flex;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.composer-row label {
		flex: 1 1 8rem;
	}
	.composer-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.conditions-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.condition {
		padding: var(--space-sm) 0;
		border-top: 1px solid var(--color-border);
	}
	.condition.stale {
		opacity: 0.55;
	}
	.condition-main {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.chip {
		font-weight: 600;
		font-size: 0.85rem;
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		background: var(--color-surface-alt, rgba(0, 0, 0, 0.06));
	}
	.sev-tag {
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.02em;
	}
	.severity-info {
		color: var(--color-text-muted, #667);
	}
	.severity-caution {
		color: var(--color-warning, #b45309);
	}
	.severity-impassable {
		color: var(--color-danger, #b91c1c);
		font-weight: 700;
	}
	.chip.severity-caution {
		background: rgba(180, 83, 9, 0.12);
	}
	.chip.severity-impassable {
		background: rgba(185, 28, 28, 0.12);
	}
	.at-km,
	.age {
		font-size: 0.8rem;
		color: var(--color-text-muted, #667);
	}
	.age {
		margin-inline-start: auto;
	}
	.delete-btn {
		background: none;
		border: none;
		font-size: 1.1rem;
		line-height: 1;
		cursor: pointer;
		color: var(--color-text-muted, #889);
		padding: 0 0.25rem;
	}
	.delete-btn:hover {
		color: var(--color-danger, #b91c1c);
	}
	.condition-note {
		margin: 0.25rem 0 0;
		font-size: 0.9rem;
	}
	.muted {
		color: var(--color-text-muted, #667);
		font-size: 0.9rem;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: #ef4444;
		font-size: 1.3rem;
	}
</style>
