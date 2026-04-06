<script lang="ts">
	import '../app.css';
	import { page } from '$app/stores';

	const navItems = [
		{ href: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
		{ href: '/runs', label: 'Runs', icon: 'directions_run' },
		{ href: '/routes', label: 'Routes', icon: 'route' },
		{ href: '/settings/integrations', label: 'Settings', icon: 'settings' },
	];

	function isActive(href: string, path: string): boolean {
		if (href === '/settings/integrations') return path.startsWith('/settings');
		return path.startsWith(href);
	}
</script>

{#if $page.url.pathname === '/' || $page.url.pathname === '/login'}
	<slot />
{:else}
	<div class="app-shell">
		<nav class="sidebar">
			<a href="/" class="logo">
				<span class="logo-icon">&#9654;</span>
				<span class="logo-text">Run</span>
			</a>

			<ul class="nav-list">
				{#each navItems as item}
					<li>
						<a
							href={item.href}
							class="nav-link"
							class:active={isActive(item.href, $page.url.pathname)}
						>
							<span class="nav-icon material-symbols">{item.icon}</span>
							<span>{item.label}</span>
						</a>
					</li>
				{/each}
			</ul>

			<div class="sidebar-footer">
				<a href="/login" class="nav-link">
					<span class="nav-icon material-symbols">person</span>
					<span>Sign In</span>
				</a>
			</div>
		</nav>

		<main class="main-content">
			<slot />
		</main>
	</div>
{/if}

<style>
	.app-shell {
		display: flex;
		min-height: 100vh;
	}

	.sidebar {
		width: var(--sidebar-width);
		background: var(--color-surface);
		border-right: 1px solid var(--color-border);
		display: flex;
		flex-direction: column;
		padding: var(--space-md);
		position: fixed;
		top: 0;
		left: 0;
		bottom: 0;
		z-index: 10;
	}

	.logo {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		margin-bottom: var(--space-lg);
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--color-primary);
	}

	.logo-icon {
		font-size: 1rem;
	}

	.nav-list {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		flex: 1;
	}

	.nav-link {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
	}

	.nav-link:hover {
		background: var(--color-bg-secondary);
		color: var(--color-text);
	}

	.nav-link.active {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}

	.nav-icon {
		font-size: 1.25rem;
		width: 1.5rem;
		text-align: center;
	}

	.sidebar-footer {
		border-top: 1px solid var(--color-border);
		padding-top: var(--space-md);
	}

	.main-content {
		flex: 1;
		margin-left: var(--sidebar-width);
		min-height: 100vh;
	}

	/* Material Symbols font — using text labels as icon names */
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		font-size: 1.25rem;
		display: inline-block;
		line-height: 1;
		text-transform: none;
		letter-spacing: normal;
		word-wrap: normal;
		white-space: nowrap;
		direction: ltr;
		-webkit-font-smoothing: antialiased;
	}
</style>
