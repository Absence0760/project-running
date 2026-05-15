import { browser } from '$app/environment';

const KEY = 'cookie_consent';

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
		}
	},
	reset() {
		state = { choice: null, timestamp: null };
		if (browser) {
			try {
				localStorage.removeItem(KEY);
			} catch {}
		}
	},
};

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
