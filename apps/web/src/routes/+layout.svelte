<script lang="ts">
	import '../app.css';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { auth } from '$lib/stores/auth.svelte';

	const navItems = [
		{ href: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
		{ href: '/runs', label: 'Runs', icon: 'directions_run' },
		{ href: '/routes', label: 'Routes', icon: 'route' },
		{ href: '/settings/integrations', label: 'Settings', icon: 'settings' },
	];

	const publicPaths = ['/', '/login', '/auth/callback'];
	const isPublic = (path: string) => publicPaths.includes(path) || path.startsWith('/live/') || path.startsWith('/share/');

	function isActive(href: string, path: string): boolean {
		if (href === '/settings/integrations') return path.startsWith('/settings');
		return path.startsWith(href);
	}

	// Auth guard — redirect to /login if not authenticated on protected routes
	$effect(() => {
		if (browser && !auth.loading && !auth.loggedIn && !isPublic($page.url.pathname)) {
			goto('/login');
		}
	});

	async function handleLogout() {
		await auth.logout();
		goto('/login');
	}
</script>

{#if isPublic($page.url.pathname)}
	<!-- Public pages: landing + login — no sidebar -->
	<slot />
{:else if auth.loading}
	<div class="loading-screen">
		<span class="loading-text">Loading...</span>
	</div>
{:else if auth.loggedIn}
	<!-- Authenticated app shell -->
	<div class="app-shell">
		<nav class="sidebar">
			<a href="/dashboard" class="logo">
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
				{#if auth.user}
					<div class="user-info">
						<div class="user-avatar">
							{auth.user.display_name?.[0]?.toUpperCase() ?? '?'}
						</div>
						<div class="user-details">
							<span class="user-name">{auth.user.display_name ?? auth.user.email}</span>
							<span class="user-email">{auth.user.email}</span>
						</div>
					</div>
				{/if}
				<button class="nav-link logout-btn" onclick={handleLogout}>
					<span class="nav-icon material-symbols">logout</span>
					<span>Sign Out</span>
				</button>
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

		--sidebar-text: #E2E8F0;
		--sidebar-text-muted: #94A3B8;
		--sidebar-hover-bg: rgba(255, 255, 255, 0.08);
		--sidebar-active-bg: rgba(79, 70, 229, 0.25);
		--sidebar-active-text: #C7D2FE;
		--sidebar-border: rgba(255, 255, 255, 0.08);
	}

	.sidebar {
		width: var(--sidebar-width);
		background: var(--gradient-sidebar);
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
		color: #ffffff;
	}

	.logo-icon {
		font-size: 1rem;
		background: var(--gradient-primary);
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
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
		color: var(--sidebar-text-muted);
		transition: all var(--transition-fast);
		border: none;
		background: none;
		width: 100%;
		text-align: left;
		cursor: pointer;
	}

	.nav-link:hover {
		background: var(--sidebar-hover-bg);
		color: var(--sidebar-text);
	}

	.nav-link.active {
		background: var(--sidebar-active-bg);
		color: var(--sidebar-active-text);
	}

	.nav-icon {
		font-size: 1.25rem;
		width: 1.5rem;
		text-align: center;
	}

	.sidebar-footer {
		border-top: 1px solid var(--sidebar-border);
		padding-top: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.user-info {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
	}

	.user-avatar {
		width: 2rem;
		height: 2rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: white;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 0.8rem;
		font-weight: 700;
		flex-shrink: 0;
	}

	.user-details {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.user-name {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--sidebar-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.user-email {
		font-size: 0.7rem;
		color: var(--sidebar-text-muted);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.logout-btn {
		color: var(--sidebar-text-muted);
		font-size: 0.85rem;
	}

	.logout-btn:hover {
		color: #FCA5A5;
		background: rgba(239, 68, 68, 0.15);
	}

	.main-content {
		flex: 1;
		margin-left: var(--sidebar-width);
		min-height: 100vh;
	}

	.loading-screen {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
	}

	.loading-text {
		color: var(--color-text-tertiary);
	}

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
