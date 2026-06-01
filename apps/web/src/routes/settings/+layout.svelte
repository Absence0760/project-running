<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { m } from '$lib/i18n/store.svelte';

	type Tab = { href: string; label: string; icon: string };
	type Section = { label: string; tabs: Tab[] };

	// "Finish setup" nudge — shows when a user who skipped fields
	// during the /onboarding wizard hasn't filled them in since. The
	// onboarded_at column is already populated (the wizard stamps it
	// on Finish OR Skip-onboarding so the gate doesn't re-trigger),
	// so we detect the fields directly. Conservative: only checks
	// the highest-impact unset values so we don't badger users who
	// deliberately left optional fields blank.
	let unsetFields = $state<string[]>([]);
	onMount(async () => {
		if (!auth.user) return;
		const checks: string[] = [];
		if (!auth.user.display_name) checks.push(m('settingsLayout.fieldDisplayName'));
		try {
			const { data } = await supabase
				.from('user_settings')
				.select('prefs')
				.eq('user_id', auth.user.id)
				.maybeSingle();
			const p = (data?.prefs ?? {}) as Record<string, unknown>;
			if (!p.body_weight_kg) checks.push(m('settingsLayout.fieldBodyWeight'));
			if (!p.privacy_default) checks.push(m('settingsLayout.fieldPrivacyDefault'));
		} catch (_) {
			/* L4 — if the read fails, just don't surface the nudge. */
		}
		unsetFields = checks;
	});

	const sections: Section[] = [
		{
			label: m('settingsLayout.sectionProfile'),
			tabs: [
				{ href: '/settings/account', label: m('settingsLayout.tabAccount'), icon: 'person' },
				{ href: '/settings/preferences', label: m('settingsLayout.tabPreferences'), icon: 'tune' },
			],
		},
		{
			label: m('settingsLayout.sectionAppsData'),
			tabs: [
				{ href: '/settings/integrations', label: m('settingsLayout.tabIntegrations'), icon: 'link' },
				{ href: '/settings/devices', label: m('settingsLayout.tabDevices'), icon: 'devices' },
				{ href: '/settings/gear', label: m('settingsLayout.tabGear'), icon: 'directions_run' },
			],
		},
		{
			label: m('settingsLayout.sectionAccountLegal'),
			tabs: [
				{ href: '/settings/upgrade', label: m('settingsLayout.tabProSupport'), icon: 'favorite' },
				{ href: '/settings/licenses', label: m('settingsLayout.tabLicenses'), icon: 'description' },
			],
		},
	];
</script>

<svelte:head>
	<title>{m('settingsLayout.pageTitle')}</title>
</svelte:head>

<div class="settings-shell">
	<nav class="settings-nav">
		<h2>{m('shell.settings')}</h2>
		{#each sections as section}
			<div class="nav-section-label">{section.label}</div>
			{#each section.tabs as tab}
				<a
					href={tab.href}
					class="nav-item"
					class:active={$page.url.pathname.startsWith(tab.href)}
				>
					<span class="material-symbols">{tab.icon}</span>
					{tab.label}
				</a>
			{/each}
		{/each}
	</nav>
	<div class="settings-content">
		{#if unsetFields.length > 0}
			<aside class="finish-setup">
				<span class="material-symbols">info</span>
				<div class="finish-setup-text">
					<strong>{m('settingsLayout.finishSetupTitle')}</strong>
					<span>{m('settingsLayout.finishSetupBody', { fields: unsetFields.join(', ') })}</span>
				</div>
			</aside>
		{/if}
		<slot />
	</div>
</div>

<style>
	.settings-shell {
		display: flex;
		min-height: 100%;
	}
	.settings-nav {
		width: 14rem;
		flex-shrink: 0;
		padding: var(--space-xl) var(--space-lg);
		border-inline-end: 1px solid var(--color-border);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.settings-nav h2 {
		font-size: 0.75rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
		margin-bottom: var(--space-md);
	}
	.nav-section-label {
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		padding: var(--space-md) 0.75rem var(--space-2xs);
	}
	.nav-section-label:first-of-type {
		padding-top: 0;
	}
	.nav-item {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.75rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
		text-decoration: none;
	}
	.nav-item:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.nav-item.active {
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	.nav-item .material-symbols {
		font-size: 1.15rem;
	}
	.settings-content {
		flex: 1;
		min-width: 0;
	}
	.finish-setup {
		display: flex;
		gap: 0.65rem;
		align-items: flex-start;
		margin: var(--space-lg) var(--space-2xl) 0;
		padding: var(--space-md);
		background: color-mix(in srgb, var(--color-primary) 7%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 25%, transparent);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
	}
	.finish-setup .material-symbols {
		font-size: 1.2rem;
		color: var(--color-primary);
		flex-shrink: 0;
		margin-top: 0.1rem;
	}
	.finish-setup-text { display: flex; flex-direction: column; gap: 0.2rem; }
	.finish-setup-text strong { font-weight: 600; }
	.finish-setup-text span { color: var(--color-text-secondary); line-height: 1.45; }
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		display: inline-block;
		line-height: 1;
	}
</style>
