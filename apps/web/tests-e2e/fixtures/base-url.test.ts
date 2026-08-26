import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { DEFAULT_BASE_URL, DEFAULT_E2E_PORT, originOf, resolveBaseUrl } from './base-url';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

const MAIN_CONFIG = 'playwright.config.ts';
/** The module allowed to spell a dev-server origin out. */
const SOURCE_OF_TRUTH = 'fixtures/base-url.ts';
/** This file, which exercises the override it forbids everyone else from reading. */
const GUARD = 'fixtures/base-url.test.ts';

test('an empty or absent override falls back rather than throwing', () => {
	const original = process.env.PLAYWRIGHT_BASE_URL;
	try {
		delete process.env.PLAYWRIGHT_BASE_URL;
		assert.equal(resolveBaseUrl(), DEFAULT_BASE_URL);
		process.env.PLAYWRIGHT_BASE_URL = '   ';
		assert.equal(resolveBaseUrl(), DEFAULT_BASE_URL);
		process.env.PLAYWRIGHT_BASE_URL = 'http://localhost:7801';
		assert.equal(resolveBaseUrl(), 'http://localhost:7801');
	} finally {
		if (original === undefined) delete process.env.PLAYWRIGHT_BASE_URL;
		else process.env.PLAYWRIGHT_BASE_URL = original;
	}
});

test('an origin drops any path the base URL carries', () => {
	assert.equal(originOf('http://localhost:7801/'), 'http://localhost:7801');
	assert.equal(originOf('http://localhost:7801/app/'), 'http://localhost:7801');
	assert.equal(originOf(undefined), new URL(resolveBaseUrl()).origin);
});

function configNames(): string[] {
	return readdirSync(E2E_ROOT)
		.filter((f) => f.startsWith('playwright') && f.endsWith('.config.ts'))
		.sort();
}

function configSource(name: string): string {
	return readFileSync(join(E2E_ROOT, name), 'utf8');
}

/**
 * The dev-server port each lane binds. The sharded lane derives its own from
 * `DEFAULT_E2E_PORT` so `PLAYWRIGHT_BASE_URL` can move it; the three
 * single-spec lanes pin theirs, because each exists to boot a dev server
 * carrying an env var the sharded one deliberately lacks.
 */
function laneDevPorts(): Map<string, number> {
	const ports = new Map<string, number>();
	for (const name of configNames()) {
		if (name === MAIN_CONFIG) {
			ports.set(name, DEFAULT_E2E_PORT);
			continue;
		}
		const pinned = configSource(name).match(/^const DEV_PORT = '(\d+)';$/m);
		assert.ok(
			pinned,
			`${name} does not pin a dev port as \`const DEV_PORT = '<port>';\` — the base-url ` +
				'guard reads the lane ports from that declaration and cannot see this lane.'
		);
		ports.set(name, Number(pinned[1]));
	}
	return ports;
}

test('the sharded lane takes its port from the one module that defines it', () => {
	const source = configSource(MAIN_CONFIG);
	assert.match(
		source,
		/import \{ resolveBaseUrl \} from '\.\/fixtures\/base-url';/,
		`${MAIN_CONFIG} must resolve its base URL through ${SOURCE_OF_TRUTH} rather than ` +
			'restating one, or the port lives in two places and the spec guard below reads the stale one.'
	);
	assert.doesNotMatch(
		source,
		/^const DEV_PORT = '\d+';$/m,
		`${MAIN_CONFIG} pins a literal dev port again — it derives one from PLAYWRIGHT_BASE_URL.`
	);
});

// Four lanes share one machine. Two of them bound :7779 at the same time until
// this guard existed: CI runs each as its own job so they never collided
// there, but locally `reuseExistingServer` makes whichever starts second adopt
// the first lane's dev server — and a lane's whole reason to exist is an env
// var that server does not carry.
test('every lane binds a dev port no other lane binds', () => {
	const ports = laneDevPorts();
	assert.ok(ports.size >= 4, `expected the four lane configs, found ${[...ports.keys()].join(', ')}`);
	const seen = new Map<number, string>();
	for (const [name, port] of ports) {
		const clash = seen.get(port);
		assert.equal(
			clash,
			undefined,
			`${name} and ${clash} both boot a dev server on :${port}; locally the second lane to ` +
				'start silently reuses the first lane\'s server, which carries the wrong env.'
		);
		seen.set(port, name);
	}
});

const SCANNED_EXTENSIONS = ['.ts', '.mjs', '.js'];

function scannedSources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) scannedSources(full, out);
		else if (SCANNED_EXTENSIONS.some((ext) => full.endsWith(ext))) out.push(full);
	}
	return out;
}

/**
 * Source with comments removed, so prose naming a port never trips the scan.
 * The `//` of a scheme is preceded by its colon, which is what separates it
 * from the `//` that opens a comment — `dates.test.ts` keeps any line holding
 * `://` whole for the opposite reason, and that rule would keep every comment
 * this scan is about.
 */
function withoutComments(source: string): string {
	return source
		// Blanked, not deleted, so a reported line number is the file's own.
		.replace(/\/\*[\s\S]*?\*\//g, (block) => block.replace(/[^\n]/g, ' '))
		.split('\n')
		.map((line) => line.replace(/(?<!:)\/\/.*$/, ''))
		.join('\n');
}

function hitLines(file: string, pattern: RegExp): number[] {
	const lines = withoutComments(readFileSync(file, 'utf8')).split('\n');
	const hits: number[] = [];
	lines.forEach((line, i) => {
		if (pattern.test(line)) hits.push(i + 1);
	});
	return hits;
}

function scannedRelPaths(): string[] {
	return scannedSources(E2E_ROOT).map((f) => relative(E2E_ROOT, f).split('\\').join('/'));
}

/**
 * A loopback origin on a port some lane's dev server binds. Deliberately NOT
 * every loopback origin: Supabase (:54321), Mailpit (:54324) and the
 * dev-server guard's deliberately-unbound :1 are real, correct literals, and
 * exempting them by name is how an allowlist rots into a list of defects
 * wearing a reason (decisions.md § 738). Scoping the pattern to the ports the
 * configs themselves declare means the rule has no exemptions to keep honest.
 */
function devServerOriginPattern(): RegExp {
	const ports = [...new Set(laneDevPorts().values())].sort((a, b) => a - b);
	return new RegExp(`https?://(?:localhost|127\\.0\\.0\\.1):(?:${ports.join('|')})\\b`);
}

test('no spec or fixture hard-codes a lane dev-server origin', () => {
	const pattern = devServerOriginPattern();
	const offenders: string[] = [];
	for (const rel of scannedRelPaths()) {
		if (rel === SOURCE_OF_TRUTH) continue;
		if (rel.startsWith('playwright') && rel.endsWith('.config.ts')) continue;
		const hits = hitLines(join(E2E_ROOT, rel), pattern);
		if (hits.length) offenders.push(`${rel}:${hits.join(',')}`);
	}
	assert.deepEqual(
		offenders,
		[],
		'These files name a dev-server origin, so they run against :' +
			`${DEFAULT_E2E_PORT} whatever lane they are in and whatever PLAYWRIGHT_BASE_URL says. ` +
			'Playwright resolves a relative page.goto / request.get against the lane baseURL; where ' +
			'an absolute origin is genuinely required (context.grantPermissions, a bare Node fetch) ' +
			`take the baseURL fixture through originOf() from ${SOURCE_OF_TRUTH}: ${offenders.join(' ')}`
	);
});

// The four sites that read the env var directly each restated the config's own
// default beside it, and were therefore wrong in the three lanes that set no
// override — right about :7777 while their lane ran on :7778, :7779 or :7780.
test('only the base-url module reads PLAYWRIGHT_BASE_URL', () => {
	const offenders: string[] = [];
	for (const rel of scannedRelPaths()) {
		if (rel === SOURCE_OF_TRUTH || rel === GUARD) continue;
		const hits = hitLines(join(E2E_ROOT, rel), /process\.env\.PLAYWRIGHT_BASE_URL/);
		if (hits.length) offenders.push(`${rel}:${hits.join(',')}`);
	}
	assert.deepEqual(
		offenders,
		[],
		'PLAYWRIGHT_BASE_URL overrides the SHARDED lane only, so re-reading it names :' +
			`${DEFAULT_E2E_PORT} inside the livehub / exporthub / sso lanes. Take the baseURL ` +
			`fixture, or resolveBaseUrl() from ${SOURCE_OF_TRUTH} where no fixture is in scope: ` +
			offenders.join(' ')
	);
});
