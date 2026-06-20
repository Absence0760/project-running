<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		amIAdmin,
		fetchPendingReports,
		fetchReportsForTarget,
		resolveTargetReports,
		adminUnhideTarget,
		type PendingReportTarget,
		type TargetReport,
		type ReportTargetKind,
	} from '$lib/core/data';
	import { formatRelativeTime } from '$lib/format/time';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let isAdmin = $state<boolean | null>(null);
	let loading = $state(true);
	let queue = $state<PendingReportTarget[]>([]);

	let selected = $state<PendingReportTarget | null>(null);
	let detail = $state<TargetReport[]>([]);
	let detailLoading = $state(false);
	let resolution = $state('');
	let resolving = $state(false);
	let unhiding = $state(false);
	let confirm = $state<{ status: 'reviewed' | 'dismissed' } | null>(null);
	let confirmUnhide = $state(false);

	function targetHref(kind: ReportTargetKind, id: string): string {
		if (kind === 'user') return `/u/${id}`;
		if (kind === 'route') return `/routes/${id}`;
		return `/clubs/${id}`;
	}

	function kindLabel(kind: ReportTargetKind): string {
		if (kind === 'user') return t('admin.reports.kind.user');
		if (kind === 'club') return t('admin.reports.kind.club');
		return t('admin.reports.kind.route');
	}

	function statusLabel(status: string): string {
		if (status === 'reviewed') return t('admin.reports.statusReviewed');
		if (status === 'dismissed') return t('admin.reports.statusDismissed');
		return t('admin.reports.statusPending');
	}

	async function loadQueue() {
		try {
			queue = await fetchPendingReports();
		} catch (e) {
			showToast(t('admin.reports.loadFailed', { error: String((e as Error)?.message ?? e) }), 'error');
		}
	}

	async function openTarget(target: PendingReportTarget) {
		selected = target;
		resolution = '';
		detail = [];
		detailLoading = true;
		try {
			detail = await fetchReportsForTarget(target.target_kind, target.target_id);
		} catch (e) {
			showToast(t('admin.reports.detailFailed', { error: String((e as Error)?.message ?? e) }), 'error');
		} finally {
			detailLoading = false;
		}
	}

	function closeDetail() {
		selected = null;
		detail = [];
	}

	async function doResolve(status: 'reviewed' | 'dismissed') {
		if (!selected || resolving) return;
		resolving = true;
		const target = selected;
		try {
			const n = await resolveTargetReports(
				target.target_kind,
				target.target_id,
				status,
				resolution.trim() || null,
			);
			const msgKey = status === 'reviewed' ? 'admin.reports.resolvedReviewed' : 'admin.reports.resolvedDismissed';
			showToast(t(msgKey, { count: n }), 'success');
			closeDetail();
			await loadQueue();
		} catch (e) {
			showToast(t('admin.reports.resolveFailed', { error: String((e as Error)?.message ?? e) }), 'error');
		} finally {
			resolving = false;
		}
	}

	async function doUnhide() {
		if (!selected || unhiding) return;
		unhiding = true;
		const target = selected;
		try {
			await adminUnhideTarget(target.target_kind, target.target_id);
			showToast(t('admin.reports.unhidden'), 'success');
			selected = { ...target, shadow_hidden: false };
			queue = queue.map((q) =>
				q.target_kind === target.target_kind && q.target_id === target.target_id
					? { ...q, shadow_hidden: false }
					: q,
			);
		} catch (e) {
			showToast(t('admin.reports.unhideFailed', { error: String((e as Error)?.message ?? e) }), 'error');
		} finally {
			unhiding = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) await loadQueue();
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.reports.title')}</title></svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="admin-not-authorized">
			<h1>{t('admin.reports.notAuthorized')}</h1>
			<p class="muted">{t('admin.reports.notAuthorizedHint')}</p>
		</div>
	{:else}
		<header>
			<h1>{t('admin.reports.title')}</h1>
			<p class="muted">{t('admin.reports.subtitle')}</p>
		</header>

		{#if queue.length === 0}
			<div class="card-elevated empty" data-testid="admin-queue-empty">
				<p class="muted">{t('admin.reports.empty')}</p>
			</div>
		{:else}
			<div class="card-elevated">
				<table data-testid="admin-queue">
					<thead>
						<tr>
							<th>{t('admin.reports.colTarget')}</th>
							<th>{t('admin.reports.colReports')}</th>
							<th>{t('admin.reports.colReporters')}</th>
							<th>{t('admin.reports.colReasons')}</th>
							<th>{t('admin.reports.colLatest')}</th>
						</tr>
					</thead>
					<tbody>
						{#each queue as target (target.target_kind + target.target_id)}
							<tr
								class="row"
								data-testid="admin-queue-row"
								onclick={() => openTarget(target)}
							>
								<td>
									<span class="kind">{kindLabel(target.target_kind)}</span>
									<a
										href={targetHref(target.target_kind, target.target_id)}
										class="target-link"
										onclick={(e) => e.stopPropagation()}
									>{target.target_id.slice(0, 8)}</a>
									{#if target.shadow_hidden}
										<span class="hidden-badge" data-testid="admin-hidden-badge">{t('admin.reports.hiddenBadge')}</span>
									{/if}
								</td>
								<td>{target.report_count}</td>
								<td>{target.reporter_count}</td>
								<td>
									<span class="reasons">
										{#each Object.entries(target.reasons) as [reason, n] (reason)}
											<span class="chip">{reason} · {n}</span>
										{/each}
									</span>
								</td>
								<td class="muted">{formatRelativeTime(target.latest_at)}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	{/if}
</div>

{#if selected}
	<Modal
		open={!!selected}
		title={t('admin.reports.detailTitle')}
		onclose={closeDetail}
		data-testid="admin-detail-modal"
	>
		<div class="detail-body">
			<div class="detail-head">
				<span class="kind">{kindLabel(selected.target_kind)}</span>
				<a href={targetHref(selected.target_kind, selected.target_id)} class="target-link">
					{t('admin.reports.viewTarget')}
				</a>
				{#if selected.shadow_hidden}
					<span class="hidden-badge" data-testid="admin-detail-hidden-badge">{t('admin.reports.hiddenBadge')}</span>
				{/if}
			</div>

			{#if selected.shadow_hidden}
				<div class="hidden-notice" data-testid="admin-hidden-notice">
					<p class="muted">{t('admin.reports.hiddenNotice')}</p>
					<button
						type="button"
						class="btn btn-secondary"
						disabled={unhiding}
						data-testid="admin-unhide"
						onclick={() => (confirmUnhide = true)}
					>{t('admin.reports.unhide')}</button>
				</div>
			{/if}

			{#if detailLoading}
				<p class="muted">…</p>
			{:else}
				<ul class="report-list">
					{#each detail as r (r.id)}
						<li class="report">
							<div class="report-top">
								<span class="reason chip">{r.reason}</span>
								<span class="status status-{r.status}">{statusLabel(r.status)}</span>
								<span class="muted when">{formatRelativeTime(r.created_at)}</span>
							</div>
							<p class="report-by muted">{t('admin.reports.reportBy', { id: r.reporter_id.slice(0, 8) })}</p>
							<p class="notes">{r.notes || t('admin.reports.noNotes')}</p>
						</li>
					{/each}
				</ul>

				<label class="resolution">
					<span>{t('admin.reports.resolutionLabel')}</span>
					<textarea
						bind:value={resolution}
						rows="2"
						placeholder={t('admin.reports.resolutionPlaceholder')}
						data-testid="admin-resolution-input"
					></textarea>
				</label>

				<div class="actions">
					<button
						type="button"
						class="btn btn-secondary"
						disabled={resolving}
						data-testid="admin-dismiss"
						onclick={() => (confirm = { status: 'dismissed' })}
					>{t('admin.reports.dismiss')}</button>
					<button
						type="button"
						class="btn btn-primary"
						disabled={resolving}
						data-testid="admin-mark-reviewed"
						onclick={() => (confirm = { status: 'reviewed' })}
					>{t('admin.reports.markReviewed')}</button>
				</div>
			{/if}
		</div>
	</Modal>
{/if}

<ConfirmDialog
	open={!!confirm}
	danger={confirm?.status === 'dismissed'}
	title={confirm?.status === 'dismissed'
		? t('admin.reports.confirmDismissTitle')
		: t('admin.reports.confirmReviewedTitle')}
	message={confirm?.status === 'dismissed'
		? t('admin.reports.confirmDismissMessage', { count: selected?.report_count ?? 0 })
		: t('admin.reports.confirmReviewedMessage', { count: selected?.report_count ?? 0 })}
	confirmLabel={confirm?.status === 'dismissed'
		? t('admin.reports.dismiss')
		: t('admin.reports.markReviewed')}
	data-testid="admin-resolve-confirm"
	onconfirm={() => {
		const status = confirm?.status;
		confirm = null;
		if (status) doResolve(status);
	}}
	oncancel={() => (confirm = null)}
/>

<ConfirmDialog
	open={confirmUnhide}
	title={t('admin.reports.confirmUnhideTitle')}
	message={t('admin.reports.confirmUnhideMessage')}
	confirmLabel={t('admin.reports.unhide')}
	data-testid="admin-unhide-confirm"
	onconfirm={() => {
		confirmUnhide = false;
		doUnhide();
	}}
	oncancel={() => (confirmUnhide = false)}
/>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	header h1,
	.not-authorized h1 {
		margin: 0 0 0.25rem;
		font-size: 1.4rem;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.not-authorized,
	.empty {
		padding: var(--space-xl);
		text-align: center;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	th {
		text-align: start;
		padding: var(--space-sm);
		color: var(--color-text-secondary);
		font-weight: 600;
		border-bottom: 1px solid var(--color-border);
	}
	td {
		padding: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	.row {
		cursor: pointer;
	}
	.row:hover {
		background: var(--color-bg-subtle, rgba(0, 0, 0, 0.03));
	}
	.kind {
		display: inline-block;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--color-text-secondary);
		margin-inline-end: 0.4rem;
	}
	.target-link {
		font-family: var(--font-mono, monospace);
		color: var(--color-accent, var(--color-primary));
	}
	.reasons,
	.report-top {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		align-items: center;
	}
	.chip {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--color-bg-subtle, rgba(0, 0, 0, 0.05));
		font-size: 0.78rem;
	}
	.detail-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.detail-head {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.hidden-badge {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--color-warning, #b45309);
		color: #fff;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		margin-inline-start: 0.4rem;
	}
	.hidden-notice {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
		padding: var(--space-sm);
		border: 1px solid var(--color-warning, #b45309);
		border-radius: var(--radius-sm);
		background: var(--color-bg-subtle, rgba(180, 83, 9, 0.08));
	}
	.hidden-notice p {
		margin: 0;
		font-size: 0.84rem;
	}
	.report-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		max-height: 40vh;
		overflow-y: auto;
	}
	.report {
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.status {
		font-size: 0.74rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.status-pending {
		color: var(--color-warning, #b45309);
	}
	.report-by,
	.when {
		font-size: 0.78rem;
	}
	.notes {
		margin: 0;
		font-size: 0.88rem;
	}
	.resolution {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.84rem;
	}
	.resolution textarea {
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		font: inherit;
		resize: vertical;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
