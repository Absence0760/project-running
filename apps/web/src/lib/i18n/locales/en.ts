// Source-of-truth message catalogue. Every other locale must define
// exactly these keys (enforced by `satisfies Messages` on each locale
// module and by messages_parity.test.ts). Keys are dotted, grouped by
// surface; `{name}`-style placeholders are filled by m()'s params arg.
//
// English is statically bundled (it is the fallback for any missing key
// and the prerender default); other locales are lazy-imported by the
// runtime in store.svelte.ts so a single-locale visitor only downloads
// their own strings.

export const en = {
	// App shell / sidebar (+layout.svelte)
	'nav.dashboard': 'Dashboard',
	'nav.history': 'History',
	'nav.routes': 'Routes',
	'nav.coach': 'Coach',
	'nav.social': 'Social',
	'shell.offline': "You're offline. New runs save locally and sync when you're back online.",
	'shell.skipToMain': 'Skip to main content',
	'shell.loading': 'Loading…',
	'shell.accountMenu': 'Account menu',
	'shell.profileAria': '{name} — profile and sign out',
	'shell.expandSidebar': 'Expand sidebar',
	'shell.collapseSidebar': 'Collapse sidebar',
	'shell.collapse': 'Collapse',
	'shell.viewProfile': 'View profile',
	'shell.coaching': 'Coaching',
	'shell.settings': 'Settings',
	'shell.signOut': 'Sign out',

	// Settings → Preferences
	'prefs.language': 'Language',
} satisfies Record<string, string>;
