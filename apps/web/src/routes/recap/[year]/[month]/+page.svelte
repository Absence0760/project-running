<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { activeFormatLocale } from '$lib/format/time';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchRuns, fetchRecapExtras, publishRecap } from '$lib/core/data';
	import { buildMonthInRunningRecap, type YearInRunningRecap } from '$lib/runs/recap';
	import { buildRecapShareSvg } from '$lib/share/recap_share_image';
	import { svgToPngBlob } from '$lib/share/svg_to_png';
	import RecapView from '$lib/components/RecapView.svelte';
	import { fmtKm, getUnit } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';
	import type { Run } from '$lib/types';

	let runs = $state<Run[]>([]);
	let extras = $state<{ photoCount: number; personalRecordCount: number }>({
		photoCount: 0,
		personalRecordCount: 0
	});
	let loading = $state(true);
	let recap = $state<YearInRunningRecap | null>(null);
	let publishing = $state(false);

	let year = $derived(parseInt($page.params.year ?? '0', 10));
	let month = $derived(parseInt($page.params.month ?? '0', 10));
	let valid = $derived(
		!Number.isNaN(year) && year >= 2010 && year <= 2100 && !Number.isNaN(month) && month >= 1 && month <= 12
	);

	function monthLabel(y: number, mo: number): string {
		if (!valid) return '';
		return new Date(y, mo - 1, 1).toLocaleDateString(activeFormatLocale(), {
			month: 'long',
			year: 'numeric'
		});
	}

	let periodLabel = $derived(monthLabel(year, month));
	let periodKey = $derived(`${year}-${String(month).padStart(2, '0')}`);

	onMount(async () => {
		await auth.ready();
		if (!auth.user) {
			loading = false;
			return;
		}
		const yr = year;
		[runs, extras] = await Promise.all([
			fetchRuns(),
			valid ? fetchRecapExtras(yr) : Promise.resolve({ photoCount: 0, personalRecordCount: 0 })
		]);
		loading = false;
	});

	$effect(() => {
		if (!valid) return;
		recap = buildMonthInRunningRecap(runs, year, month, extras);
	});

	async function shareRecap() {
		if (!recap) return;
		const lines = [
			t('recap.monthShareTitle', { period: periodLabel }),
			'',
			t('recap.shareDistance', { distance: fmtKm(recap.totalDistanceM), n: recap.runCount }),
			t('recap.shareLongest', { distance: fmtKm(recap.longestRunM) }),
			t('recap.shareTopWeek', { distance: fmtKm(recap.topWeek?.distanceM ?? 0) })
		];
		const text = lines.join('\n');

		try {
			const svg = buildRecapShareSvg(recap, getUnit(), periodLabel);
			const blob = await svgToPngBlob(svg, 1080);
			const file = new File([blob], `threkir-${periodKey}.png`, { type: 'image/png' });
			if (navigator.canShare?.({ files: [file] })) {
				await navigator.share({
					files: [file],
					title: t('recap.monthShareTitle', { period: periodLabel }),
					text
				});
				return;
			}
			const dl = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = dl;
			a.download = `threkir-${periodKey}.png`;
			a.click();
			URL.revokeObjectURL(dl);
			return;
		} catch (err) {
			console.warn('recap card share failed, falling back to text', err);
		}

		if (navigator.share) {
			try {
				await navigator.share({ title: t('recap.monthShareTitle', { period: periodLabel }), text });
				return;
			} catch (_) {
				// fall through to clipboard
			}
		}
		await navigator.clipboard.writeText(text);
		alert(t('recap.copiedToClipboard'));
	}

	async function publishAndShareLink() {
		if (!recap || publishing) return;
		publishing = true;
		try {
			const id = await publishRecap('month', periodKey, recap);
			if (!id) {
				alert(t('recap.publishFailed'));
				return;
			}
			const url = `${location.origin}/recap/share/${id}`;
			if (navigator.share) {
				try {
					await navigator.share({ title: t('recap.monthShareTitle', { period: periodLabel }), url });
					return;
				} catch (_) {
					// fall through to clipboard
				}
			}
			await navigator.clipboard.writeText(url);
			alert(t('recap.publishedLinkCopied'));
		} catch (err) {
			console.warn('recap publish failed', err);
			alert(t('recap.publishFailed'));
		} finally {
			publishing = false;
		}
	}
</script>

<svelte:head>
	<title>{valid ? t('recap.monthPageTitle', { period: periodLabel }) : t('recap.invalidYear')}</title>
</svelte:head>

<div class="page">
	{#if !valid}
		<p class="muted">{t('recap.invalidMonth')}</p>
	{:else if loading}
		<p class="muted">{t('recap.loadingYear')}</p>
	{:else if !auth.user}
		<p class="muted">{t('recap.signInPrompt')}</p>
	{:else if recap == null || recap.runCount === 0}
		<header class="hero-empty">
			<p class="kicker">{periodLabel}</p>
			<h1>{t('recap.noRunsMonth', { period: periodLabel })}</h1>
			<p class="empty-sub">
				{t('recap.emptySub')}
			</p>
		</header>
	{:else}
		<RecapView
			{recap}
			kicker={t('recap.monthHeroKicker', { period: periodLabel })}
			shareLabel={t('recap.shareMyMonth', { period: periodLabel })}
			onshare={shareRecap}
			onpublish={publishAndShareLink}
			{publishing}
		/>
	{/if}
</div>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
		max-width: 72rem;
		margin: 0 auto;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.hero-empty {
		position: relative;
		padding: var(--space-2xl) var(--space-xl);
		text-align: center;
		background: var(--color-bg-secondary);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-xl);
		margin-bottom: var(--space-xl);
	}
	.hero-empty .kicker {
		text-transform: uppercase;
		letter-spacing: 0.12em;
		font-size: 0.78rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-md);
	}
	.hero-empty h1 {
		font-size: 2rem;
	}
	.empty-sub {
		max-width: 32rem;
		margin: 0 auto;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
</style>
