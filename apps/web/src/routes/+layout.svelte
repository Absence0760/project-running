<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { browser } from '$app/environment';
	import { auth } from '$lib/stores/auth.svelte';
	import { initTheme } from '$lib/theme';
	import { setMapStyle, type MapStyle } from '$lib/map-style.svelte';
	import BillingIssueBanner from '$lib/components/BillingIssueBanner.svelte';
	import CookieConsentBanner from '$lib/components/CookieConsentBanner.svelte';
	import ToastContainer from '$lib/components/ToastContainer.svelte';
	import NotificationBell from '$lib/components/NotificationBell.svelte';
	import { notificationStore } from '$lib/stores/notifications.svelte';

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

	// Notification bell — refresh unread count on auth-ready and on
	// window focus. No polling timer; the focus handler covers the
	// "left tab open, came back later" case while keeping the UI
	// silent in the background.
	$effect(() => {
		const uid = auth.user?.id;
		if (!browser || !uid) {
			notificationStore.clear();
			return;
		}
		notificationStore.refresh();
		const onFocus = () => notificationStore.refresh();
		window.addEventListener('focus', onFocus);
		return () => window.removeEventListener('focus', onFocus);
	});

	// Order is runner-led: log + review + train is the daily loop, then
	// content, then social. Five items total — Settings lives in the
	// profile popover at the bottom of the sidebar; Feed is a self-only
	// tab on /u/[me]; Guided runs are surfaced from /coach (both are
	// coach-driven). Top-down scan time matches frequency-of-use.
	const navItems = [
		{ href: '/dashboard', label: 'Dashboard', icon: 'dashboard', accent: '#F2A07B' },
		{ href: '/runs', label: 'History', icon: 'directions_run', accent: '#D97A54' },
		{ href: '/routes', label: 'Routes', icon: 'route', accent: '#B9A7E8' },
		{ href: '/coach', label: 'Coach', icon: 'sports', accent: '#7FB3C2' },
		{ href: '/social', label: 'Social', icon: 'public', accent: '#C98ECF' },
	];

	// "Shell-less" surfaces: rendered without the app sidebar regardless of
	// auth state. Landing, auth flows, and the share / spectator pages that
	// have their own chrome. A signed-in user visiting /share/run/<id> sees
	// the share view, not the dashboard's sidebar wrapped around it.
	const shellLessExact = ['/', '/login', '/auth/callback', '/auth/reset'];
	const isShellless = (path: string) =>
		shellLessExact.includes(path) ||
		path.startsWith('/share/') ||
		path.startsWith('/live/') ||
		path.startsWith('/clubs/join/');

	// "Anon-allowed" surfaces: reachable without auth. Superset of shell-less
	// — also includes the legal pages, marketing pages, and the guided /
	// recap content surfaces. When a signed-in user visits one of these,
	// the app shell still wraps it (sidebar stays put).
	const anonExtraExact = ['/privacy', '/terms', '/cookie-notice', '/compare', '/guided'];
	const isAnonAllowed = (path: string) =>
		isShellless(path) ||
		anonExtraExact.includes(path) ||
		path.startsWith('/guided/') ||
		path.startsWith('/recap/') ||
		// Public clubs + their event detail pages are RLS-visible to
		// anon (clubs.is_public + events FK). The page-level guards on
		// /clubs/new and /clubs/[slug]/events/new still kick non-admins,
		// so adding the prefix here only unblocks the read surfaces.
		path.startsWith('/clubs/');

	function isActive(href: string, path: string): boolean {
		return path.startsWith(href);
	}

	// Auth guard — redirect to /login if not authenticated on protected routes.
	// Preserve the original destination via ?return_to so the user lands back
	// where they wanted after signing in (matches the safeReturnTo() helper
	// already in /login). Without this, a user clicking a stale email link
	// to /runs/<id> gets bounced to the dashboard after sign-in and has to
	// hunt for the destination.
	$effect(() => {
		if (browser && !auth.loading && !auth.loggedIn && !isAnonAllowed($page.url.pathname)) {
			const returnTo = $page.url.pathname + $page.url.search;
			const isDefault = returnTo === '/dashboard' || returnTo === '/';
			goto(isDefault ? '/login' : `/login?return_to=${encodeURIComponent(returnTo)}`);
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
<CookieConsentBanner />

{#if isShellless($page.url.pathname)}
	<!-- Landing, login, share, live, club-invite — these have their own
	     chrome and render shell-less regardless of auth state. -->
	<slot />
{:else if !auth.loggedIn && isAnonAllowed($page.url.pathname)}
	<!-- Anon viewer on an anon-allowed content page (/privacy, /terms,
	     /cookie-notice, /compare, /guided, /guided/*, /recap/*). Render
	     the slot without the signed-in shell. Bypasses the auth.loading
	     branch so SSR + anon-first-paint serves the real page body
	     instead of the spinner. The auth guard above redirects anon
	     viewers on protected paths to /login. -->
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
				<a href="/dashboard" class="logo" aria-label="Threkir">
					<img src="/icon-192.png" alt="" class="logo-mark" />
					<span class="logo-text">Threkir</span>
				</a>
				<div class="sidebar-head-actions">
					<NotificationBell />
				</div>
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
						aria-haspopup="menu"
						aria-expanded={showLogoutModal}
						title={sidebarCollapsed ? auth.user.display_name ?? auth.user.email : undefined}
					>
						<div class="user-avatar">
							{auth.user.display_name?.[0]?.toUpperCase() ?? '?'}
						</div>
						<div class="user-details">
							<span class="user-name">{auth.user.display_name ?? auth.user.email}</span>
							<span class="user-email">{auth.user.email}</span>
						</div>
						<span class="profile-chevron material-symbols" aria-hidden="true">unfold_more</span>
					</button>
				{/if}
				<button
					class="collapse-toggle"
					type="button"
					aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
					aria-expanded={!sidebarCollapsed}
					title={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
					onclick={toggleSidebar}
				>
					<span class="material-symbols">{sidebarCollapsed ? 'chevron_right' : 'chevron_left'}</span>
					{#if !sidebarCollapsed}<span class="collapse-toggle-label">Collapse</span>{/if}
				</button>
			</div>
		</nav>

		<main class="main-content">
			<BillingIssueBanner />
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
			{#if auth.user}
				<a
					class="popover-item"
					href="/u/{auth.user.id}"
					onclick={() => (showLogoutModal = false)}
				>
					<span class="material-symbols">person</span>
					View profile
				</a>
				<a
					class="popover-item"
					href="/settings"
					onclick={() => (showLogoutModal = false)}
				>
					<span class="material-symbols">settings</span>
					Settings
				</a>
				<div class="popover-divider"></div>
			{/if}
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
		z-index: var(--z-sidebar);
		border-right: 1px solid var(--sidebar-border);
		transition: width var(--transition-base);
	}

	.sidebar.collapsed {
		width: var(--sidebar-collapsed-width, 4.5rem);
	}

	.sidebar-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-xs);
		padding: var(--space-2xs) 0 var(--space-2xs) var(--space-xs);
		margin-bottom: var(--space-md);
	}

	.sidebar-head-actions {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		flex-shrink: 0;
	}

	.collapse-toggle {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		height: 2rem;
		min-width: 2rem;
		padding: 0 var(--space-sm);
		border: none;
		border-radius: var(--radius-md);
		background: transparent;
		color: var(--sidebar-text-muted);
		font-size: 0.78rem;
		font-weight: 500;
		cursor: pointer;
		flex-shrink: 0;
		align-self: flex-end;
		transition:
			background var(--transition-fast),
			color var(--transition-fast);
	}
	.collapse-toggle:hover {
		background: var(--sidebar-hover-bg);
		color: var(--sidebar-text);
	}
	.collapse-toggle .material-symbols {
		font-size: 1.1rem;
	}
	.collapse-toggle-label {
		letter-spacing: var(--section-label-tracking);
		text-transform: uppercase;
		font-size: 0.65rem;
	}

	.logo {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xs) 0;
		font-weight: 700;
		font-size: 1.05rem;
		letter-spacing: -0.01em;
		color: var(--sidebar-logo);
		min-width: 0;
		flex: 1;
	}

	.logo-mark {
		width: 1.85rem;
		height: 1.85rem;
		border-radius: var(--radius-md);
		flex-shrink: 0;
		box-shadow: var(--shadow-sm);
		object-fit: cover;
		display: block;
	}

	.logo-text {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
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
		left: calc(-1 * var(--space-md));
		top: 18%;
		bottom: 18%;
		width: 3px;
		border-radius: 0 2px 2px 0;
		background: var(--accent);
	}
	.sidebar.collapsed .nav-link.active::before {
		display: none;
	}

	.sidebar-footer {
		border-top: 1px solid var(--sidebar-border);
		padding-top: var(--space-sm);
		margin-top: var(--space-sm);
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: var(--space-2xs);
	}

	.profile-btn {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm);
		width: 100%;
		min-width: 0;
		border: 1px solid transparent;
		background: none;
		border-radius: var(--radius-md);
		cursor: pointer;
		text-align: left;
		transition:
			background var(--transition-fast),
			border-color var(--transition-fast);
	}
	.profile-btn:hover {
		background: var(--sidebar-hover-bg);
		border-color: var(--sidebar-border);
	}
	.profile-btn[aria-expanded='true'] {
		background: var(--sidebar-hover-bg);
		border-color: var(--sidebar-border);
	}

	.user-avatar {
		width: 2.25rem;
		height: 2.25rem;
		border-radius: 50%;
		background: var(--gradient-primary);
		color: #FFFFFF;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 0.85rem;
		font-weight: 700;
		flex-shrink: 0;
		box-shadow: var(--shadow-sm);
	}

	.user-details {
		display: flex;
		flex-direction: column;
		min-width: 0;
		flex: 1;
		gap: var(--space-2xs);
	}

	.user-name {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--sidebar-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		line-height: 1.15;
	}

	.user-email {
		font-size: 0.72rem;
		color: var(--sidebar-text-muted);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		line-height: 1.15;
	}

	.profile-chevron {
		flex-shrink: 0;
		font-size: 1.1rem;
		color: var(--sidebar-text-muted);
	}

	.popover-backdrop {
		position: fixed;
		inset: 0;
		z-index: 99;
	}
	.popover {
		position: fixed;
		bottom: calc(var(--space-md) + 4.5rem);
		left: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-sm);
		min-width: 14rem;
		box-shadow: var(--shadow-lg);
		z-index: 100;
	}
	.popover-header {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm);
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
	.sidebar.collapsed .user-details,
	.sidebar.collapsed .profile-chevron,
	.sidebar.collapsed .collapse-toggle-label,
	.sidebar.collapsed .logo-text {
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
	/* On the narrow rail keep only the logo mark + nav icons + avatar +
	   collapse-toggle. The bell would crowd the 4.5rem rail and its
	   popover would clip — surface it only when expanded. */
	.sidebar.collapsed .sidebar-head {
		justify-content: center;
		padding: 0;
	}
	.sidebar.collapsed .sidebar-head-actions {
		display: none;
	}
	.sidebar.collapsed .logo {
		padding: 0;
		justify-content: center;
	}
	.sidebar.collapsed .collapse-toggle {
		align-self: stretch;
		padding: 0;
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

	/* Narrow viewports: force the rail-only state so the sidebar stops
	   eating ~40% of the canvas on phones. The collapse-toggle is
	   hidden here because the user can't usefully expand to 15rem on
	   a 480px screen — the rail is the only viable shape. */
	@media (max-width: 40rem) {
		.sidebar {
			width: var(--sidebar-collapsed-width, 4.5rem);
		}
		.main-content {
			margin-left: var(--sidebar-collapsed-width, 4.5rem);
		}
		.sidebar .nav-label,
		.sidebar .user-details,
		.sidebar .profile-chevron,
		.sidebar .collapse-toggle-label,
		.sidebar .logo-text,
		.sidebar-head-actions,
		.collapse-toggle {
			opacity: 0;
			visibility: hidden;
			width: 0;
			overflow: hidden;
			pointer-events: none;
		}
		.sidebar .nav-link,
		.sidebar .profile-btn {
			justify-content: center;
			gap: 0;
			padding-left: 0;
			padding-right: 0;
		}
		.sidebar .nav-link.active::before {
			display: none;
		}
		.sidebar-head {
			justify-content: center;
			padding: 0;
		}
		.logo {
			padding: 0;
			justify-content: center;
		}
		/* The popover is anchored to the left edge — pin it inside the
		   viewport so it doesn't clip when the rail is only 4.5rem. */
		.popover {
			left: calc(var(--sidebar-collapsed-width, 4.5rem) + var(--space-xs));
			min-width: 13rem;
			max-width: calc(100vw - var(--sidebar-collapsed-width, 4.5rem) - var(--space-md));
		}
	}
</style>
