<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import { activeFormatLocale } from '$lib/format/time';
	import {
		groupImportFailures,
		importFailureReportCsv,
		type ImportFailureLog,
	} from '$lib/integrations/import_failures';

	interface Props {
		log: ImportFailureLog;
		provider: string;
		ondismiss: () => void;
	}

	const { log, provider, ondismiss }: Props = $props();

	const groups = $derived(groupImportFailures(log));

	function formatStart(iso: string | null): string {
		if (!iso) return m('importFailures.noDate');
		const ms = Date.parse(iso);
		if (!Number.isFinite(ms)) return m('importFailures.noDate');
		return new Date(ms).toLocaleDateString(activeFormatLocale(), {
			year: 'numeric',
			month: 'short',
			day: 'numeric',
		});
	}

	function download() {
		const blob = new Blob([importFailureReportCsv(log)], { type: 'text/csv;charset=utf-8' });
		const url = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = url;
		a.download = `${provider}-import-failures.csv`;
		document.body.appendChild(a);
		a.click();
		a.remove();
		URL.revokeObjectURL(url);
	}
</script>

<section class="failure-report" data-testid="import-failure-report">
	<h3>{m('importFailures.heading', { count: log.items.length + log.truncated })}</h3>
	<p class="intro">{m('importFailures.intro')}</p>

	<ul class="reasons">
		{#each groups as g (g.reason)}
			<li>
				<span class="reason-label">{m(`importFailures.reason.${g.reason}` as MessageKey)}</span>
				<span class="reason-count">{g.count}</span>
			</li>
		{/each}
	</ul>

	{#if log.truncated > 0}
		<p class="truncated">{m('importFailures.truncated', { count: log.truncated })}</p>
	{/if}

	<details>
		<summary>{m('importFailures.showDetail')}</summary>
		<ul class="items">
			{#each log.items as f, i (i)}
				<li>
					<span class="item-name">{f.name}</span>
					<span class="item-meta">
						{formatStart(f.startedAt)} · {m(`importFailures.reason.${f.reason}` as MessageKey)}
					</span>
					{#if f.detail}
						<span class="item-detail">{f.detail}</span>
					{/if}
				</li>
			{/each}
		</ul>
	</details>

	<div class="actions">
		<button type="button" class="btn btn-secondary btn-sm" onclick={download}>
			{m('importFailures.download')}
		</button>
		<button type="button" class="btn btn-sm" onclick={ondismiss}>
			{m('importFailures.dismiss')}
		</button>
	</div>
</section>

<style>
	.failure-report {
		margin-top: var(--space-md);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-left: 3px solid var(--color-danger-text);
		border-radius: var(--radius-md);
		background: var(--color-fill-subtle);
	}
	.failure-report h3 {
		margin: 0;
		font-size: 0.95rem;
	}
	.intro {
		margin: var(--space-xs) 0 0;
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.reasons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
		margin: var(--space-sm) 0 0;
		padding: 0;
		list-style: none;
	}
	.reasons li {
		display: flex;
		align-items: baseline;
		gap: 0.35rem;
		padding: 0.15rem 0.5rem;
		border-radius: 999px;
		background: var(--color-surface);
		font-size: 0.75rem;
	}
	.reason-count {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
	.truncated {
		margin: var(--space-sm) 0 0;
		font-size: 0.75rem;
		color: var(--color-text-tertiary);
	}
	details {
		margin-top: var(--space-sm);
		font-size: 0.8rem;
	}
	summary {
		cursor: pointer;
		color: var(--color-text-secondary);
	}
	.items {
		max-height: 18rem;
		overflow-y: auto;
		margin: var(--space-sm) 0 0;
		padding: 0;
		list-style: none;
	}
	.items li {
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
		padding: 0.4rem 0;
		border-top: 1px solid var(--color-border);
	}
	.item-name {
		font-weight: 500;
		overflow-wrap: anywhere;
	}
	.item-meta {
		font-size: 0.75rem;
		color: var(--color-text-secondary);
	}
	.item-detail {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		overflow-wrap: anywhere;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
</style>
