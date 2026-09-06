import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createServer, type Server } from 'node:http';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';

import {
	assertServedFilesMatch,
	changedWebSources,
	extractRawDefault
} from './dev_server_guard';

const REL = 'src/lib/i18n/locale.ts';
const DISK = "export const locale = 'en';\n";

const raw = (content: string) => `export default ${JSON.stringify(content)}\n`;

const cleanups: Array<() => void> = [];
after(() => cleanups.forEach((fn) => fn()));

function tempWebDir(): string {
	const dir = mkdtempSync(join(tmpdir(), 'dev-guard-'));
	cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
	mkdirSync(join(dir, 'src/lib/i18n'), { recursive: true });
	writeFileSync(join(dir, REL), DISK);
	return dir;
}

/** Answers `/@fs/…` and root-relative requests independently. */
async function stubServer(handlers: {
	absolute: { status: number; body?: string };
	relative: { status: number; body?: string };
}): Promise<string> {
	const server: Server = createServer((req, res) => {
		const h = req.url?.startsWith('/@fs/') ? handlers.absolute : handlers.relative;
		res.writeHead(h.status, { 'content-type': 'text/javascript' });
		res.end(h.body ?? '');
	});
	await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
	cleanups.push(() => server.close());
	const { port } = server.address() as { port: number };
	return `http://127.0.0.1:${port}`;
}

test('a server serving this tree passes', async () => {
	const dir = tempWebDir();
	const base = await stubServer({
		absolute: { status: 200, body: raw(DISK) },
		relative: { status: 200, body: raw(DISK) }
	});
	await assertServedFilesMatch(base, dir, [REL]);
});

test('a 403 on the absolute path names the foreign checkout', async () => {
	const dir = tempWebDir();
	const base = await stubServer({
		absolute: { status: 403 },
		relative: { status: 200, body: raw(DISK) }
	});
	await assert.rejects(
		assertServedFilesMatch(base, dir, [REL]),
		/rooted in a different checkout/
	);
});

test('the same path served with other content is reported as stale, not as a pass', async () => {
	const dir = tempWebDir();
	const base = await stubServer({
		absolute: { status: 200, body: raw('export const locale = "de";\n') },
		relative: { status: 200, body: raw(DISK) }
	});
	await assert.rejects(assertServedFilesMatch(base, dir, [REL]), /serving a stale copy of/);
});

test("a file missing from the served tree fails naming it", async () => {
	const dir = tempWebDir();
	const base = await stubServer({
		absolute: { status: 200, body: raw(DISK) },
		relative: { status: 404 }
	});
	await assert.rejects(
		assertServedFilesMatch(base, dir, [REL]),
		(err: unknown) =>
			err instanceof Error &&
			err.message.includes(`has no ${REL} in the tree it is serving`)
	);
});

test('the served tree carrying a different copy of the file fails', async () => {
	const dir = tempWebDir();
	const base = await stubServer({
		absolute: { status: 200, body: raw(DISK) },
		relative: { status: 200, body: raw(`${DISK}// another checkout\n`) }
	});
	await assert.rejects(
		assertServedFilesMatch(base, dir, [REL]),
		/serving a different src\/lib\/i18n\/locale\.ts than this working tree's/
	);
});

test('an inconclusive answer warns rather than failing the suite', async () => {
	const dir = tempWebDir();
	const base = await stubServer({
		absolute: { status: 404 },
		relative: { status: 404 }
	});
	await assertServedFilesMatch(base, dir, [REL]);
});

test('an unreachable server does not fail the suite', async () => {
	const dir = tempWebDir();
	// Port 1 is reserved and unbound — fetch rejects rather than answering.
	await assertServedFilesMatch('http://127.0.0.1:1', dir, [REL]);
});

test('extractRawDefault reads the payload, sourcemap comment or not', () => {
	assert.equal(extractRawDefault(raw('a\n"b"\n')), 'a\n"b"\n');
	assert.equal(
		extractRawDefault(`${raw(DISK)}//# sourceMappingURL=data:application/json;base64,e30=\n`),
		DISK
	);
	assert.equal(extractRawDefault('<!doctype html>'), null);
	assert.equal(extractRawDefault('export default "unterminated'), null);
});

test('extractRawDefault reads a payload Vite left a literal tab in', () => {
	// `raw()` above builds the body with JSON.stringify, which escapes tabs.
	// Vite does not: it escapes newlines, quotes and backslashes and emits a
	// TAB raw, which JSON.parse refuses as a control character in a string
	// literal. This repo indents with tabs, so the synthetic fixture was the
	// only shape the guard ever parsed and every real probe silently fell
	// through to "could not compare" — a guard that passed by doing nothing.
	const content = 'function f() {\n\treturn 1;\n}\n';
	const viteBody = `export default ${JSON.stringify(content).replace(/\\t/g, '\t')};\n`;
	assert.ok(viteBody.includes('\t'), 'the fixture must carry a raw tab');
	assert.equal(extractRawDefault(viteBody), content);
});

test('changedWebSources reports modified, staged and untracked web sources', () => {
	const root = mkdtempSync(join(tmpdir(), 'dev-guard-repo-'));
	cleanups.push(() => rmSync(root, { recursive: true, force: true }));
	const webDir = join(root, 'apps/web');
	const git = (...args: string[]) =>
		execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' });

	mkdirSync(join(webDir, 'src/lib'), { recursive: true });
	for (const f of ['src/lib/a.ts', 'src/lib/b.ts', 'src/lib/gone.ts']) {
		writeFileSync(join(webDir, f), 'export const x = 1;\n');
	}
	git('init', '-q');
	git('config', 'user.email', 't@example.com');
	git('config', 'user.name', 'test');
	git('add', '-A');
	git('commit', '-qm', 'seed');

	writeFileSync(join(webDir, 'src/lib/a.ts'), 'export const x = 2;\n');
	writeFileSync(join(webDir, 'src/lib/new.svelte'), '<p>hi</p>\n');
	writeFileSync(join(webDir, 'src/lib/notes.txt'), 'ignored\n');
	rmSync(join(webDir, 'src/lib/gone.ts'));

	const found = changedWebSources(webDir);
	assert.deepEqual(found.sort(), ['src/lib/a.ts', 'src/lib/new.svelte']);

	// Paths are relative to the web app, not the repo root, and the probe set
	// is bounded.
	assert.equal(changedWebSources(webDir, 1).length, 1);
	// A tree with no web changes reports none, so the caller falls back.
	git('add', '-A');
	git('commit', '-qm', 'all');
	assert.deepEqual(changedWebSources(webDir), []);
});

test('changedWebSources returns nothing outside a git repo', () => {
	assert.deepEqual(changedWebSources(mkdtempSync(join(tmpdir(), 'dev-guard-nogit-'))), []);
});
