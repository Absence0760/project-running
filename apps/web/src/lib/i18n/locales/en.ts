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

	// Login / signup / reset (/login)
	'login.kicker.signin': 'Welcome back',
	'login.kicker.signup': 'Join Threkir',
	'login.kicker.reset': 'Forgot your password?',
	'login.headline.signin': 'Sign in to your account',
	'login.headline.signup': 'Create an account',
	'login.headline.reset': 'Reset your password',
	'login.subtitle.signin': 'Pick up where you left off — your runs are waiting.',
	'login.subtitle.signup': 'Track your runs across every device. Free forever.',
	'login.subtitle.reset': "Enter your email and we'll send you a reset link.",
	'login.brandHeadline': 'Track every run. Plan every race. Bring your club along.',
	'login.bullet1': 'Map, splits, elevation, HR zones — the basics, polished.',
	'login.bullet2': 'Plans that adapt: VDOT, Riegel, week-by-week editable preview.',
	'login.bullet3': 'Clubs, kudos, comments. Private by default; share what you choose.',
	'login.brandFoot': 'Free forever. Add Pro to unlock club perks, the coach, and bulk imports.',
	'login.continueGoogle': 'Continue with Google',
	'login.continueApple': 'Continue with Apple',
	'login.soon': 'Soon',
	'login.orEmail': 'or continue with email',
	'login.emailPlaceholder': 'Email address',
	'login.passwordPlaceholder': 'Password',
	'login.confirmAdult': 'I confirm I am 16 years of age or older.',
	'login.agreePrefix': 'I have read and agree to the',
	'login.agreeBetween': 'and',
	'login.agreeSuffix': '.',
	'legal.termsOfService': 'Terms of Service',
	'legal.privacyPolicy': 'Privacy Policy',
	'login.sending': 'Sending…',
	'login.signingUp': 'Signing up…',
	'login.signingIn': 'Signing in…',
	'login.sendResetLink': 'Send reset link',
	'login.signUp': 'Sign Up',
	'login.signIn': 'Sign In',
	'login.backToSignIn': 'Back to sign in',
	'login.haveAccount': 'Already have an account?',
	'login.noAccount': "Don't have an account?",
	'login.toggleToSignIn': 'Sign in',
	'login.toggleToSignUp': 'Sign up',
	'login.appleSoon': 'Sign in with Apple is coming soon. For now, please use Google or email.',
	'login.signInFailed': 'Sign in failed',
	'login.authFailed': 'Authentication failed',
} satisfies Record<string, string>;
