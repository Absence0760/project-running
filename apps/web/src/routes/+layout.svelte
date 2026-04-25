<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { auth } from '$lib/stores/auth.svelte';
	import { initTheme } from '$lib/theme';
	import { setMapStyle, type MapStyle } from '$lib/map-style.svelte';
	import ToastContainer from '$lib/components/ToastContainer.svelte';

	// Apply the persisted theme on first client mount. Users with a
	// saved non-auto preference may see a brief flash on first paint —
	// that's the cost of not using a blocking script tag in app.html;
	// acceptable for now.
	onMount(() => {
		initTheme();
	});

	// Hydrate the map-style signal once the user is known so the
	// preview on /runs/[id] matches the user's saved preference without
	// needing the preferences page to be visited first this session.
	$effect(() => {
		const uid = auth.user?.id;
		if (!browser || !uid) return;
		(async () => {
			try {
				const { loadSettings, effective } = await import('$lib/settings');
				const settings = await loadSettings(uid);
				const ms = effective<MapStyle>(settings, 'map_style');
				setMapStyle(ms);
			} catch (_) {
				/* silent — falls back to default */
			}
		})();
	});

	const navItems = [
		{ href: '/dashboard', label: 'Dashboard', icon: 'dashboard', accent: '#F2A07B' },
		{ href: '/runs', label: 'History', icon: 'directions_run', accent: '#D97A54' },
		{ href: '/routes', label: 'Routes', icon: 'route', accent: '#B9A7E8' },
		{ href: '/explore', label: 'Explore', icon: 'explore', accent: '#7FB3C2' },
		{ href: '/plans', label: 'Plans', icon: 'calendar_month', accent: '#89D0B8' },
		{ href: '/coach', label: 'Coach', icon: 'sports', accent: '#7FB3C2' },
		{ href: '/clubs', label: 'Clubs', icon: 'groups', accent: '#C98ECF' },
		{ href: '/settings', label: 'Settings', icon: 'settings', accent: '#9CA3AF' },
	];

	const publicPaths = ['/', '/login', '/auth/callback'];
	const isPublic = (path: string) =>
		publicPaths.includes(path) ||
		path.startsWith('/live/') ||
		path.startsWith('/share/') ||
		path.startsWith('/clubs/join/');

	function isActive(href: string, path: string): boolean {
		return path.startsWith(href);
	}

	// Auth guard — redirect to /login if not authenticated on protected routes
	$effect(() => {
		if (browser && !auth.loading && !auth.loggedIn && !isPublic($page.url.pathname)) {
			goto('/login');
		}
	});

	let showLogoutModal = $state(false);

	/// Sidebar collapsed state. Persisted in localStorage so the user's
	/// preference survives reloads. Initial value is read on first mount —
	/// before that the app renders expanded (matches SSR / GitHub Pages).
	let sidebarCollapsed = $state(false);

	onMount(() => {
		try {
			sidebarCollapsed = localStorage.getItem('sidebar_collapsed') === '1';
		} catch (_) {
			/* localStorage may be unavailable — leave default */
		}
	});

	function toggleSidebar() {
		sidebarCollapsed = !sidebarCollapsed;
		try {
			localStorage.setItem('sidebar_collapsed', sidebarCollapsed ? '1' : '0');
		} catch (_) {
			/* silent */
		}
	}

	async function handleLogout() {
		showLogoutModal = false;
		await auth.logout();
		goto('/login');
	}
</script>

<ToastContainer />

{#if isPublic($page.url.pathname)}
	<!-- Public pages: landing + login — no sidebar -->
	<slot />
{:else if auth.loading}
	<div class="loading-screen">
		<span class="loading-text">Loading...</span>
	</div>
{:else if auth.loggedIn}
	<!-- Authenticated app shell -->
	<div class="app-shell" class:sidebar-collapsed={sidebarCollapsed}>
		<nav class="sidebar" class:collapsed={sidebarCollapsed}>
			<div class="sidebar-head">
				<a href="/dashboard" class="logo" aria-label="Run">
					<span class="logo-icon">&#9654;</span>
					<span class="logo-text">Run</span>
				</a>
				<button
					class="collapse-toggle"
					type="button"
					aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
					aria-expanded={!sidebarCollapsed}
					title={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
					onclick={toggleSidebar}
				>
					<span class="material-symbols">{sidebarCollapsed ? 'menu' : 'menu_open'}</span>
				</button>
			</div>

			<ul class="nav-list">
				{#each navItems as item}
					<li>
						<a
							href={item.href}
							class="nav-link"
							class:active={isActive(item.href, $page.url.pathname)}
							style="--accent: {item.accent};"
							title={sidebarCollapsed ? item.label : undefined}
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
					<button
						class="profile-btn"
						onclick={() => (showLogoutModal = true)}
						title={sidebarCollapsed ? auth.user.display_name ?? auth.user.email : undefined}
					>
						<div class="user-avatar">
							{auth.user.display_name?.[0]?.toUpperCase() ?? '?'}
						</div>
						<div class="user-details">
							<span class="user-name">{auth.user.display_name ?? auth.user.email}</span>
							<span class="user-email">{auth.user.email}</span>
						</div>
					</button>
				{/if}
			</div>
		</nav>

		<main class="main-content">
			<slot />
		</main>
	</div>

	{#if showLogoutModal}
		<div class="popover-backdrop" onclick={() => (showLogoutModal = false)} role="presentation"></div>
		<div class="popover" role="menu">
			<div class="popover-header">
				<div class="popover-avatar">
					{auth.user?.display_name?.[0]?.toUpperCase() ?? '?'}
				</div>
				<div class="popover-info">
					<span class="popover-name">{auth.user?.display_name ?? 'Account'}</span>
					<span class="popover-email">{auth.user?.email}</span>
				</div>
			</div>
			<div class="popover-divider"></div>
			<button class="popover-item popover-danger" onclick={handleLogout}>
				<span class="material-symbols">logout</span>
				Sign out
			</button>
		</div>
	{/if}
{/if}

<style>
	.app-shell {
		display: flex;
		min-height: 100vh;
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
		transition: width var(--transition-base);
	}

	.sidebar.collapsed {
		width: var(--sidebar-collapsed-width, 4.5rem);
	}

	.sidebar-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		margin-bottom: var(--space-lg);
	}

	.collapse-toggle {
		display: grid;
		place-items: center;
		width: 2rem;
		height: 2rem;
		border: none;
		border-radius: var(--radius-md);
		background: transparent;
		color: var(--sidebar-text-muted);
		cursor: pointer;
		flex-shrink: 0;
		transition:
			background var(--transition-fast),
			color var(--transition-fast);
	}
	.collapse-toggle:hover {
		background: var(--sidebar-hover-bg);
		color: var(--sidebar-text);
	}
	.collapse-toggle .material-symbols {
		font-size: 1.25rem;
	}

	.logo {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		font-weight: 700;
		font-size: 1.25rem;
		color: var(--sidebar-logo);
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
		display: grid;
		place-items: center;
		width: 2.25rem;
		height: 2.25rem;
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
		font-size: 1.25rem;
		font-variation-settings: 'FILL' 0, 'wght' 500, 'GRAD' 0, 'opsz' 24;
		transition: font-variation-settings var(--transition-base);
		line-height: 1;
		width: 1.25rem;
		height: 1.25rem;
		display: block;
		text-align: center;
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

	.profile-btn {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		width: 100%;
		border: none;
		background: none;
		border-radius: var(--radius-md);
		cursor: pointer;
		text-align: left;
		transition: background var(--transition-fast);
	}
	.profile-btn:hover {
		background: var(--sidebar-hover-bg);
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

	.popover-backdrop {
		position: fixed;
		inset: 0;
		z-index: 99;
	}
	.popover {
		position: fixed;
		bottom: 4rem;
		left: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-sm);
		min-width: 14rem;
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
		z-index: 100;
	}
	.popover-header {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.6rem;
	}
	.popover-avatar {
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
	.popover-info {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.popover-name {
		font-size: 0.85rem;
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.popover-email {
		font-size: 0.72rem;
		color: var(--color-text-secondary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.popover-divider {
		height: 1px;
		background: var(--color-border);
		margin: 0.3rem 0;
	}
	.popover-item {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.6rem;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		font-weight: 500;
		color: var(--color-text);
		border: none;
		background: none;
		width: 100%;
		text-align: left;
		cursor: pointer;
		text-decoration: none;
		transition: background var(--transition-fast);
	}
	.popover-item:hover {
		background: var(--color-bg-tertiary);
	}
	.popover-item .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.popover-danger {
		color: var(--color-danger);
	}
	.popover-danger .material-symbols {
		color: var(--color-danger);
	}

	.main-content {
		flex: 1;
		margin-left: var(--sidebar-width);
		min-height: 100vh;
		transition: margin-left var(--transition-base);
	}

	.app-shell.sidebar-collapsed .main-content {
		margin-left: var(--sidebar-collapsed-width, 4.5rem);
	}

	/* Hide labels and trim spacing when collapsed. Icons keep their
	   layout so the rail stays visually consistent. */
	.sidebar.collapsed .nav-label,
	.sidebar.collapsed .user-details {
		opacity: 0;
		visibility: hidden;
		width: 0;
		overflow: hidden;
		white-space: nowrap;
	}
	.sidebar.collapsed .nav-link,
	.sidebar.collapsed .profile-btn {
		justify-content: center;
		gap: 0;
		padding-left: 0;
		padding-right: 0;
	}
	/* When collapsed, the logo would crowd the menu button on a 4.5rem
	   rail — hide it and let the menu icon stand alone (clicking it
	   re-expands the sidebar). */
	.sidebar.collapsed .logo {
		display: none;
	}
	.sidebar.collapsed .sidebar-head {
		justify-content: center;
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
