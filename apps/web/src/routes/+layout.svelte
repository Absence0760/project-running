<script lang="ts">
	import '../app.css';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { auth } from '$lib/stores/auth.svelte';

	const navItems = [
		{ href: '/dashboard', label: 'Dashboard', icon: 'dashboard', accent: '#F2A07B' },
		{ href: '/runs', label: 'Runs', icon: 'directions_run', accent: '#D97A54' },
		{ href: '/routes', label: 'Routes', icon: 'route', accent: '#B9A7E8' },
		{ href: '/clubs', label: 'Clubs', icon: 'groups', accent: '#C98ECF' },
		{ href: '/explore', label: 'Explore', icon: 'explore', accent: '#7FB3C2' },
		{ href: '/settings/integrations', label: 'Settings', icon: 'settings', accent: '#E6A96B' },
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
							style="--accent: {item.accent};"
						>
							<span class="nav-icon-wrap">
								<span class="nav-icon material-symbols">{item.icon}</span>
							</span>
							<span class="nav-label">{item.label}</span>
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
				<button class="nav-link logout-btn" onclick={handleLogout} style="--accent: #8A8298;">
					<span class="nav-icon-wrap">
						<span class="nav-icon material-symbols">logout</span>
					</span>
					<span class="nav-label">Sign Out</span>
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

		--sidebar-text: #F7F3EC;
		--sidebar-text-muted: #B5ADC3;
		--sidebar-hover-bg: rgba(247, 243, 236, 0.06);
		--sidebar-active-bg: rgba(58, 46, 92, 0.55);
		--sidebar-active-text: #F7F3EC;
		--sidebar-border: rgba(247, 243, 236, 0.08);
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
		--accent: #F2A07B;
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		font-weight: 500;
		color: var(--sidebar-text-muted);
		transition:
			background var(--transition-fast),
			color var(--transition-fast),
			transform var(--transition-fast);
		border: none;
		background: none;
		width: 100%;
		text-align: left;
		cursor: pointer;
		position: relative;
	}

	.nav-icon-wrap {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2rem;
		height: 2rem;
		border-radius: 10px;
		background: color-mix(in srgb, var(--accent) 14%, transparent);
		color: var(--accent);
		box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 22%, transparent);
		transition:
			background var(--transition-base),
			color var(--transition-base),
			transform var(--transition-base),
			box-shadow var(--transition-base);
		flex-shrink: 0;
	}

	.nav-icon {
		font-size: 1.125rem;
		font-variation-settings: 'FILL' 0, 'wght' 500, 'GRAD' 0, 'opsz' 24;
		transition: font-variation-settings var(--transition-base);
		line-height: 1;
	}

	.nav-label {
		transition: transform var(--transition-base);
	}

	.nav-link:hover .nav-icon-wrap {
		background: color-mix(in srgb, var(--accent) 24%, transparent);
		box-shadow:
			inset 0 0 0 1px color-mix(in srgb, var(--accent) 40%, transparent),
			0 6px 18px -6px color-mix(in srgb, var(--accent) 55%, transparent);
		transform: translateY(-1px) scale(1.06);
	}

	.nav-link:hover {
		color: var(--sidebar-text);
		background: var(--sidebar-hover-bg);
	}

	.nav-link:hover .nav-label {
		transform: translateX(2px);
	}

	.nav-link:active .nav-icon-wrap {
		transform: translateY(0) scale(0.98);
	}

	.nav-link.active {
		color: var(--sidebar-text);
		background: var(--sidebar-hover-bg);
	}

	.nav-link.active .nav-icon-wrap {
		background: var(--accent);
		color: #1B1628;
		box-shadow:
			inset 0 0 0 1px color-mix(in srgb, var(--accent) 70%, transparent),
			0 8px 22px -6px color-mix(in srgb, var(--accent) 60%, transparent);
	}

	.nav-link.active .nav-icon {
		font-variation-settings: 'FILL' 1, 'wght' 600, 'GRAD' 0, 'opsz' 24;
	}

	.nav-link.active::before {
		content: '';
		position: absolute;
		left: -8px;
		top: 20%;
		bottom: 20%;
		width: 3px;
		border-radius: 2px;
		background: var(--accent);
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
		--accent: #8A8298;
	}

	.logout-btn:hover {
		--accent: #D8594C;
		color: #F7F3EC;
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
