import { execFileSync } from 'node:child_process';
import { existsSync, realpathSync, statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Refuse to run the suite against a dev server that is not serving this
 * working tree.
 *
 * `playwright.config.ts` sets `reuseExistingServer: !CI`, so a `vite dev`
 * left running on :7777 by another worktree — or by another agent sharing
 * this checkout — is adopted silently. It serves ITS bundle, so a spec for a
 * component that only exists here fails with no console error while every
 * pre-existing spec passes: a failure mode that reads as a real break and has
 * cost several rounds.
 *
 * Two things are checked, and the second is the one that matters. Vite's
 * `/@fs/` route serves an absolute path only when it falls inside the
 * server's own `server.fs.allow` root, so a `403` proves the server is rooted
 * in another tree. But `403` is only reachable when the allow list excludes
 * us; a server rooted in an ancestor, or one with a widened allow list,
 * answers `200` for our file while still serving its own copy of everything
 * the app imports. So the guard also compares CONTENT: `?raw` makes Vite emit
 * a module whose default export is the file's bytes read at request time
 * (`export default "<contents>"`), which gives two comparable answers —
 * the file at an absolute path (ours, byte for byte) and the file at the same
 * path relative to the server's own root (whatever tree it is serving).
 * Either one disagreeing with disk is a bundle that does not match this tree.
 *
 * The files probed are the ones whose staleness would actually break a spec:
 * this tree's own uncommitted web sources, falling back to a fixed module
 * when the tree is clean. Anything inconclusive (404 on both routes, a
 * non-Vite server, a network error) only warns — the guard must never turn an
 * unfamiliar setup into a failing suite.
 */
const WEB_DIR = fileURLToPath(new URL('../../', import.meta.url));

const FALLBACK_PROBE = 'src/lib/i18n/locale.ts';

const PROBE_LIMIT = 5;
const PROBE_MAX_BYTES = 256 * 1024;
const PROBE_EXTENSIONS = ['.ts', '.js', '.mjs', '.svelte', '.css', '.json'];
const URL_SAFE_PATH = /^[A-Za-z0-9._+\-/[\]()@]+$/;

export async function assertServedTreeMatches(baseURL: string): Promise<void> {
	if (process.env.CI) return;

	const base = baseURL.replace(/\/$/, '');
	const changed = changedWebSources(WEB_DIR);
	await assertServedFilesMatch(base, WEB_DIR, changed.length > 0 ? changed : [FALLBACK_PROBE]);
}

/**
 * The web sources this working tree has that `HEAD` does not — modified,
 * staged, or untracked. Deletions are skipped (nothing to compare), as are
 * binaries, oversized files and paths git had to quote.
 */
export function changedWebSources(webDir: string, limit = PROBE_LIMIT): string[] {
	let root: string;
	let status: string;
	try {
		root = execFileSync('git', ['-C', webDir, 'rev-parse', '--show-toplevel'], {
			encoding: 'utf8'
		}).trim();
		status = execFileSync(
			'git',
			['-C', webDir, 'status', '--porcelain', '--untracked-files=all', '--', 'src'],
			{ encoding: 'utf8' }
		);
	} catch {
		return [];
	}

	// git reports the toplevel as a real path; webDir may reach it through a
	// symlink (macOS /tmp, a symlinked worktree), and an unresolved compare
	// then reads every changed file as outside the app.
	const webRoot = realpathSync(webDir);
	const out: string[] = [];
	for (const line of status.split('\n')) {
		if (line.length < 4) continue;
		const code = line.slice(0, 2);
		if (code.includes('D')) continue;
		let path = line.slice(3);
		const renamed = path.split(' -> ');
		path = renamed[renamed.length - 1];
		if (path.startsWith('"')) continue;
		const rel = relative(webRoot, join(root, path));
		if (rel.startsWith('..')) continue;
		if (!PROBE_EXTENSIONS.some((ext) => rel.endsWith(ext))) continue;
		// The probe URL interpolates the path, and percent-encoding it would
		// break SvelteKit's own filenames (`+page.svelte` survives decodeURI
		// as `%2Bpage.svelte`), so skip anything that would need escaping.
		if (!URL_SAFE_PATH.test(rel)) continue;
		const abs = join(webRoot, rel);
		if (!existsSync(abs) || statSync(abs).size > PROBE_MAX_BYTES) continue;
		out.push(rel);
		if (out.length === limit) break;
	}
	return out;
}

export async function assertServedFilesMatch(
	base: string,
	webDir: string,
	relPaths: string[]
): Promise<void> {
	for (const rel of relPaths) {
		const abs = join(webDir, rel);
		const disk = await readFile(abs, 'utf8');

		const ours = await servedRaw(`${base}/@fs${abs}?raw`);
		if (ours.status === 403) {
			throw new Error(
				`[dev-server guard] ${base} is served by a dev server rooted in a different ` +
					`checkout — it refused ${abs} as outside its allow list, so it is serving ` +
					`another tree's bundle and your changes are not under test.\n` +
					`Stop that server (or run this suite from the checkout that owns it) and retry.`
			);
		}
		if (ours.status === 0) return;
		if (ours.status !== 200 || ours.content === null) {
			console.warn(
				`[dev-server guard] ${base} did not answer a Vite ?raw module for ${rel} by ` +
					`absolute path (status ${ours.status}); could not confirm it serves this ` +
					`checkout. Continuing.`
			);
			continue;
		}
		if (ours.content !== disk) {
			throw new Error(
				`[dev-server guard] ${base} is serving a stale copy of ${rel} — ` +
					`${ours.content.length} chars against ${disk.length} on disk, for the same ` +
					`absolute path. Its module graph predates your edit, so your changes are not ` +
					`under test. Stop that server and let Playwright start its own.`
			);
		}

		const theirs = await servedRaw(`${base}/${rel}?raw`);
		if (theirs.status === 0) return;
		if (theirs.status !== 200) {
			throw new Error(
				`[dev-server guard] ${base} has no ${rel} in the tree it is serving ` +
					`(status ${theirs.status} for /${rel}, while the same file read by absolute ` +
					`path served fine). The server on that port belongs to another checkout, so ` +
					`your changes are not under test.\n` +
					`Stop that server (or run this suite from the checkout that owns it) and retry.`
			);
		}
		if (theirs.content === null) {
			console.warn(
				`[dev-server guard] ${base} answered /${rel} with something other than a Vite ` +
					`?raw module; could not compare it against disk. Continuing.`
			);
			continue;
		}
		if (theirs.content !== disk) {
			throw new Error(
				`[dev-server guard] ${base} is serving a different ${rel} than this working ` +
					`tree's — ${theirs.content.length} chars against ${disk.length} on disk. The ` +
					`server on that port is rooted in another checkout, so your changes are not ` +
					`under test.\n` +
					`Stop that server (or run this suite from the checkout that owns it) and retry.`
			);
		}
	}
}

async function servedRaw(url: string): Promise<{ status: number; content: string | null }> {
	let res: Response;
	try {
		res = await fetch(url);
	} catch (e) {
		console.warn(`[dev-server guard] probe failed (${String(e)}) — skipping the check.`);
		return { status: 0, content: null };
	}
	if (res.status !== 200) return { status: res.status, content: null };
	return { status: 200, content: extractRawDefault(await res.text()) };
}

/**
 * Vite's `?raw` module is `export default <JSON string>` — one line, since
 * every newline is escaped — optionally followed by a sourcemap comment.
 *
 * It is not, however, `JSON.stringify` output: a literal TAB survives
 * unescaped, and `JSON.parse` rejects a raw control character inside a string
 * literal. This repo indents with tabs, so every real probe threw and the
 * guard degraded to its "could not compare" warning — inert against exactly
 * the stale cross-worktree server it exists to catch, on a clean tree and a
 * dirty one alike. The escape below is applied to the whole literal, which is
 * safe because no C0 character can appear in it for any other reason.
 */
export function extractRawDefault(body: string): string | null {
	const line = body.split('\n').find((l) => l.startsWith('export default "'));
	if (!line) return null;
	const literal = line
		.slice('export default '.length)
		.replace(/;$/, '')
		.replace(/[\u0000-\u001f]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`);
	try {
		return JSON.parse(literal);
	} catch {
		return null;
	}
}
