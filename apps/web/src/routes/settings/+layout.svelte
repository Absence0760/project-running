<script lang="ts">
	import { page } from '$app/stores';

	const tabs = [
		{ href: '/settings/account', label: 'Account', icon: 'person' },
		{ href: '/settings/preferences', label: 'Preferences', icon: 'tune' },
		{ href: '/settings/integrations', label: 'Integrations', icon: 'link' },
		{ href: '/settings/devices', label: 'Devices', icon: 'devices' },
		{ href: '/settings/upgrade', label: 'Pro & support', icon: 'favorite' },
		{ href: '/settings/licenses', label: 'Licenses', icon: 'description' },
	];
</script>

<div class="settings-shell">
	<nav class="settings-nav">
		<h2>Settings</h2>
		{#each tabs as tab}
			<a
				href={tab.href}
				class="nav-item"
				class:active={$page.url.pathname.startsWith(tab.href)}
			>
				<span class="material-symbols">{tab.icon}</span>
				{tab.label}
			</a>
		{/each}
	</nav>
	<div class="settings-content">
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
		border-right: 1px solid var(--color-border);
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
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		display: inline-block;
		line-height: 1;
	}
</style>
