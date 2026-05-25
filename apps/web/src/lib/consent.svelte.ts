import { browser } from '$app/environment';
import {
	CONSENT_COOKIE_NAME,
	CONSENT_COOKIE_ACCEPTED_VALUE,
} from './consent_cookie';

const KEY = 'cookie_consent';

// Mirror the localStorage state to a cookie so the server-side hook
// can gate Sentry per-request. audit/cookie-consent +
// audit/third-party-data-flows (May 2026): server-side Sentry was
// firing unconditionally, forwarding EU IPs to a US sub-processor
// before the consent banner had even rendered. The server can't
// read localStorage; the cookie is the bridge.
//
// SameSite=Lax, 1y. Not HttpOnly — same-origin script needs to be
// able to clear it on reset().
const COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

function writeCookie(choice: 'accepted' | 'rejected'): void {
	if (!browser) return;
	const secure = location.protocol === 'https:' ? '; Secure' : '';
	document.cookie =
		`${CONSENT_COOKIE_NAME}=${choice}; Max-Age=${COOKIE_MAX_AGE}; ` +
		`Path=/; SameSite=Lax${secure}`;
}

function clearCookie(): void {
	if (!browser) return;
	document.cookie = `${CONSENT_COOKIE_NAME}=; Max-Age=0; Path=/; SameSite=Lax`;
}

export type ConsentChoice = 'accepted' | 'rejected' | null;

export interface ConsentState {
	choice: ConsentChoice;
	timestamp: number | null;
}

function readStored(): ConsentState {
	if (!browser) return { choice: null, timestamp: null };
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return { choice: null, timestamp: null };
		const parsed = JSON.parse(raw) as ConsentState;
		if (parsed.choice === 'accepted' || parsed.choice === 'rejected') return parsed;
		return { choice: null, timestamp: null };
	} catch {
		return { choice: null, timestamp: null };
	}
}

let state = $state<ConsentState>(readStored());

export const consent = {
	get choice(): ConsentChoice {
		return state.choice;
	},
	get timestamp(): number | null {
		return state.timestamp;
	},
	get accepted(): boolean {
		return state.choice === 'accepted';
	},
	get pending(): boolean {
		return state.choice === null;
	},
	set(choice: 'accepted' | 'rejected') {
		const next: ConsentState = { choice, timestamp: Date.now() };
		state = next;
		if (browser) {
			try {
				localStorage.setItem(KEY, JSON.stringify(next));
			} catch {}
			writeCookie(choice);
		}
	},
	reset() {
		state = { choice: null, timestamp: null };
		if (browser) {
			try {
				localStorage.removeItem(KEY);
			} catch {}
			clearCookie();
		}
	},
};

// Re-export for legacy callers; the cookie helper is the single
// source of truth.
export { CONSENT_COOKIE_NAME, CONSENT_COOKIE_ACCEPTED_VALUE };

export function hasAcceptedConsent(): boolean {
	if (!browser) return false;
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return false;
		const parsed = JSON.parse(raw) as ConsentState;
		return parsed.choice === 'accepted';
	} catch {
		return false;
	}
}
