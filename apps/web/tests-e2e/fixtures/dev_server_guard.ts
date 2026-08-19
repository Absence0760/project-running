import { fileURLToPath } from 'node:url';

/**
 * Refuse to run the suite against a dev server booted from a different
 * checkout.
 *
 * `playwright.config.ts` sets `reuseExistingServer: !CI`, so a `vite dev`
 * left running on :7777 by another worktree is adopted silently. It serves
 * ITS bundle, so a spec for a component that only exists here fails with no
 * console error while every pre-existing spec passes — a failure mode that
 * reads as a real break and has cost several rounds.
 *
 * The probe abuses Vite's `/@fs/` route, which serves an absolute path only
 * when it falls inside the server's own `server.fs.allow` root: 200 means
 * the server is rooted in THIS tree, 403 means the file exists but belongs
 * to another one. Anything else (404, a non-Vite server, a network error)
 * is inconclusive and only warns — the guard must never turn an unfamiliar
 * setup into a failing suite.
 */
const PROBE = fileURLToPath(new URL('../../src/lib/i18n/locale.ts', import.meta.url));

export async function assertServedTreeMatches(baseURL: string): Promise<void> {
	if (process.env.CI) return;

	let status: number;
	try {
		status = (await fetch(`${baseURL.replace(/\/$/, '')}/@fs${PROBE}`)).status;
	} catch (e) {
		console.warn(`[dev-server guard] probe failed (${String(e)}) — skipping the check.`);
		return;
	}

	if (status === 403) {
		throw new Error(
			`[dev-server guard] ${baseURL} is served by a dev server rooted in a different ` +
				`checkout — it refused ${PROBE} as outside its allow list, so it is serving ` +
				`another tree's bundle and your changes are not under test.\n` +
				`Stop that server (or run this suite from the checkout that owns it) and retry.`
		);
	}
	if (status !== 200) {
		console.warn(
			`[dev-server guard] probe returned ${status}; could not confirm ${baseURL} serves ` +
				`this checkout. Continuing.`
		);
	}
}
