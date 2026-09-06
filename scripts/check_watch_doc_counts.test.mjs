import { spawnSync } from 'node:child_process';
import {
	cpSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

import {
	DATED_LOGS,
	DOC_FILES,
	NOT_A_SYMBOL_COUNT,
	REGISTRY,
	ROOT,
	SWEEP_NOUNS,
	arrayLen,
	attributeCount,
	check,
	constValue,
	declaredModules,
	derivedValue,
	enumVariants,
	loadDocs,
	loadSource,
	numberOf,
	testFnCount,
	unregisteredDocs,
} from './check_watch_doc_counts.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GUARD = join(HERE, 'check_watch_doc_counts.mjs');

/**
 * Every source file some registry row resolves through, RECORDED rather than
 * listed: a hand-written list is one more transcription, and this file exists
 * because transcriptions rot.
 * @returns {string[]}
 */
function sourcePaths() {
	/** @type {Set<string>} */
	const seen = new Set();
	for (const row of REGISTRY) {
		row.resolve((p) => {
			seen.add(p);
			return loadSource(p);
		});
	}
	return [...seen];
}

/**
 * A throwaway copy of exactly what the guard reads, so a mutation can be shown
 * to fail the whole process — exit code and all — without touching the tree.
 * @param {(path: string, read: (p: string) => string, write: (p: string, s: string) => void) => void} mutate
 * @returns {{ status: number | null, stdout: string, stderr: string }}
 */
function runOnCopy(mutate) {
	const dir = mkdtempSync(join(tmpdir(), 'watch-doc-counts-'));
	try {
		for (const rel of [...DOC_FILES, ...sourcePaths()]) {
			const dest = join(dir, rel);
			mkdirSync(dirname(dest), { recursive: true });
			cpSync(join(ROOT, rel), dest);
		}
		mutate(
			dir,
			(p) => readFileSync(join(dir, p), 'utf-8'),
			(p, s) => writeFileSync(join(dir, p), s),
		);
		return spawnSync(process.execPath, [GUARD], {
			encoding: 'utf-8',
			env: { ...process.env, WATCH_DOC_COUNT_ROOT: dir },
		});
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

// --- the committed tree ------------------------------------------------------

test('the committed docs agree with the committed firmware', () => {
	const { errors, ok } = check(loadDocs(), loadSource);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 1);
	assert.match(ok[0], /doc statement\(s\) agree with \d+ firmware symbol\(s\)/);
});

test('every registry row resolves to a positive number', () => {
	for (const row of REGISTRY) {
		const n = row.resolve(loadSource);
		assert.ok(Number.isInteger(n) && n > 0, `${row.id} resolved to ${n}`);
	}
});

test('the registry ids are unique, and every template carries exactly one slot', () => {
	const ids = REGISTRY.map((r) => r.id);
	assert.equal(new Set(ids).size, ids.length);
	for (const row of REGISTRY) {
		assert.ok(row.phrases.length > 0, `${row.id} has no template`);
		for (const p of row.phrases) {
			assert.equal(p.split('{n}').length, 2, `${row.id}: "${p}" must carry one {n}`);
		}
	}
});

// --- the resolvers -----------------------------------------------------------

test('constValue, arrayLen and attributeCount read past comments', () => {
	const src = [
		'// pub const MENU_ITEMS: usize = 99;',
		'/// A doc comment holding #[characteristic(uuid = "x")] and nothing real.',
		'pub const MENU_ITEMS: usize = 8;',
		'pub const PRESETS_S: [u32; 11] = [0, 1];',
		'#[characteristic(uuid = "a", read)]',
		'a: u8,',
		'#[characteristic(uuid = "b", write)]',
		'b: u8,',
	].join('\n');
	assert.equal(constValue(src, 'MENU_ITEMS'), 8);
	assert.equal(arrayLen(src, 'PRESETS_S'), 11);
	assert.equal(attributeCount(src, 'characteristic'), 2);
});

test('enumVariants skips attributes, doc comments and variant payloads', () => {
	const src = [
		'/// Page::Ghost is named in a comment and is not a variant.',
		'#[derive(Clone)]',
		'pub enum Page {',
		'    #[default]',
		'    Dashboard,',
		'    /// A doc comment mentioning Screen9.',
		'    Screen1,',
		'    Screen2,',
		'    Carrying(u8),',
		'    Struct { a: u8, b: u8 },',
		'}',
	].join('\n');
	assert.deepEqual(enumVariants(src, 'Page'), [
		'Dashboard',
		'Screen1',
		'Screen2',
		'Carrying',
		'Struct',
	]);
});

test('a source the resolver cannot read throws rather than returning a number', () => {
	assert.throws(() => constValue('pub const MENU_ITEMS: usize = ROWS - 1;', 'MENU_ITEMS'), /no longer a plain integer const/);
	assert.throws(() => enumVariants('pub struct Page {}', 'Page'), /no `enum Page`/);
	assert.throws(() => attributeCount('fn main() {}', 'characteristic'), /no `#\[characteristic\(`/);
});

test('derivedValue refuses a rail that has stopped deriving', () => {
	const derived = 'pub const MENU_VISIBLE: usize = ROWS - MENU_TOP_ROW;';
	assert.equal(derivedValue(derived, 'MENU_VISIBLE', 'ROWS - MENU_TOP_ROW', 7), 7);
	assert.throws(
		() => derivedValue('pub const MENU_VISIBLE: usize = 7;', 'MENU_VISIBLE', 'ROWS - MENU_TOP_ROW', 7),
		/has stopped deriving must not/,
	);
});

test('numberOf reads digits and the spelled-out words the docs use', () => {
	assert.equal(numberOf('41'), 41);
	assert.equal(numberOf('nine'), 9);
	assert.equal(numberOf('Eight'), 8);
	assert.equal(numberOf('eleven'), 11);
	assert.throws(() => numberOf('umpteen'), /unreadable number/);
});

// --- the two directions, on fixtures ----------------------------------------

/** @type {import('./check_watch_doc_counts.mjs').Row} */
const ROW = {
	id: 'fixture.items',
	symbol: '`fixture::ITEMS`',
	resolve: (read) => constValue(read('fixture.rs'), 'ITEMS'),
	phrases: ['{n} settings-menu rows'],
};
const SOURCE_8 = { 'fixture.rs': 'pub const ITEMS: usize = 8;' };
/** @param {Record<string, string>} src @returns {(p: string) => string} */
const reader = (src) => (p) => src[p];

test('a doc that states the wrong number fails, naming both sides', () => {
	const { errors } = check(
		{ 'a.md': 'The menu has seven settings-menu rows today.' },
		reader(SOURCE_8),
		[ROW],
		[],
		SWEEP_NOUNS,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"seven settings-menu rows" states 7 where `fixture::ITEMS` is 8/);
});

test('the SYMBOL moving under a correct sentence fails it too', () => {
	const docs = { 'a.md': 'The menu has eight settings-menu rows today.' };
	assert.deepEqual(check(docs, reader(SOURCE_8), [ROW], [], SWEEP_NOUNS).errors, []);
	const { errors } = check(
		docs,
		reader({ 'fixture.rs': 'pub const ITEMS: usize = 9;' }),
		[ROW],
		[],
		SWEEP_NOUNS,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /states 8 where `fixture::ITEMS` is 9/);
});

test('a bold or capitalised number is still read', () => {
	assert.deepEqual(
		check({ 'a.md': 'Eight settings-menu rows.' }, reader(SOURCE_8), [ROW], [], SWEEP_NOUNS).errors,
		[],
	);
	assert.deepEqual(
		check({ 'a.md': 'now **8** settings-menu rows' }, reader(SOURCE_8), [ROW], [], SWEEP_NOUNS).errors,
		[],
	);
});

test('a template that matches nothing is an error, not a pass', () => {
	const { errors, ok } = check({ 'a.md': 'no counts here' }, reader(SOURCE_8), [ROW], [], SWEEP_NOUNS);
	assert.deepEqual(ok, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /matches nothing in the doc set, so it checks nothing/);
});

test('the sweep catches a count no template reads', () => {
	const { errors } = check(
		{ 'a.md': 'eight settings-menu rows, and six waypoints.' },
		reader(SOURCE_8),
		[ROW],
		[],
		SWEEP_NOUNS,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"six waypoints" is a count about a firmware symbol that no template/);
});

test('an exemption wins over a template that would otherwise claim history', () => {
	const docs = { 'a.md': 'It had four settings-menu rows then; eight settings-menu rows today.' };
	const bare = check(docs, reader(SOURCE_8), [ROW], [], SWEEP_NOUNS);
	assert.equal(bare.errors.length, 1);
	assert.match(bare.errors[0], /states 4 where/);

	const excused = check(
		docs,
		reader(SOURCE_8),
		[ROW],
		[{ file: 'a.md', text: 'four settings-menu rows then', reason: 'the ring it used to be' }],
		SWEEP_NOUNS,
	);
	assert.deepEqual(excused.errors, []);
});

test('an exemption that matches nothing is an error', () => {
	const { errors } = check(
		{ 'a.md': 'eight settings-menu rows' },
		reader(SOURCE_8),
		[ROW],
		[{ file: 'a.md', text: 'nine settings-menu rows', reason: 'gone' }],
		SWEEP_NOUNS,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /matches nothing\. The sentence it excuses is gone/);
});

test('an exemption naming a file outside DOC_FILES excuses nothing and says so', () => {
	const { errors } = check(
		{ 'a.md': 'eight settings-menu rows' },
		reader(SOURCE_8),
		[ROW],
		[{ file: 'elsewhere.md', text: 'nine settings-menu rows', reason: 'gone' }],
		SWEEP_NOUNS,
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /which is not in DOC_FILES, so it excuses nothing/);
});

test('a resolver that throws is reported, never silently skipped', () => {
	const { errors, ok } = check(
		{ 'a.md': 'eight settings-menu rows' },
		reader({ 'fixture.rs': 'pub const ITEMS: usize = SOMETHING_ELSE;' }),
		[ROW],
		[],
		SWEEP_NOUNS,
	);
	assert.deepEqual(ok, []);
	// Two errors, both correct: the row could not be resolved, and the sentence
	// it would have covered is then a count nothing reads.
	assert.equal(errors.length, 2);
	assert.match(errors[0], /no longer a plain integer const/);
	assert.match(errors[1], /no template in this registry reads/);
});

test('a section reference is not a count', () => {
	// `§351 menu row` and `#41 built-ins` must not read as a quantity.
	const { errors } = check(
		{ 'a.md': 'eight settings-menu rows, selected from a fourth §351 menu row.' },
		reader(SOURCE_8),
		[ROW],
		[],
		SWEEP_NOUNS,
	);
	assert.deepEqual(errors, []);
});

// --- the whole process ------------------------------------------------------

test('the guard exits 0 on an unmutated copy of the tree', () => {
	const res = runOnCopy(() => {});
	assert.equal(res.status, 0, res.stderr);
	assert.match(res.stdout, /doc statement\(s\) agree with/);
});

test('a doc drifting off the firmware exits 1 with an ::error:: line', () => {
	const res = runOnCopy((_dir, read, write) => {
		const nav = read('docs/custom_watch/navigation.md');
		const bumped = nav.replace('41 built-in pages', '42 built-in pages');
		assert.notEqual(bumped, nav, 'navigation.md must still carry the built-in page count');
		write('docs/custom_watch/navigation.md', bumped);
	});
	assert.equal(res.status, 1);
	assert.match(res.stderr, /::error::check_watch_doc_counts: docs\/custom_watch\/navigation\.md/);
	assert.match(res.stderr, /"42 built-in pages" states 42 where `Page` variants less the `Screen\*` seats/);
});

test('the firmware growing under correct docs exits 1 — the § 793 direction', () => {
	const res = runOnCopy((_dir, read, write) => {
		const page = read('apps/custom_watch/core/src/page.rs');
		const grown = page.replace('pub enum Page {', 'pub enum Page {\n    Invented,');
		assert.notEqual(grown, page);
		write('apps/custom_watch/core/src/page.rs', grown);
	});
	assert.equal(res.status, 1);
	// Both the built-in ring and the composed total move, and both are named.
	assert.match(res.stderr, /states 41 where `Page` variants less the `Screen\*` seats.*is 42/);
	assert.match(res.stderr, /states 45 where `Page` variants in `core\/src\/page\.rs`.*is 46/);
});

test('a new unregistered count in a doc exits 1 rather than passing unread', () => {
	const res = runOnCopy((_dir, read, write) => {
		const md = read('docs/custom_watch/firmware.md');
		write('docs/custom_watch/firmware.md', `${md}\n\nThe service carries twelve characteristics.\n`);
	});
	assert.equal(res.status, 1);
	assert.match(res.stderr, /"twelve characteristics" is a count about a firmware symbol/);
});

test('deleting a registered sentence exits 1 rather than leaving a dead template', () => {
	const res = runOnCopy((_dir, read, write) => {
		const md = read('docs/custom_watch/quality_standards.md');
		const cut = md.replace(/eleven-rung preset ladder/g, 'preset ladder');
		assert.notEqual(cut, md);
		write('docs/custom_watch/quality_standards.md', cut);
	});
	assert.equal(res.status, 1);
	assert.match(res.stderr, /the template "the \{n\}-rung preset ladder" \(timers\.presets\) matches nothing/);
});

test('a derived constant rewritten as a literal exits 1', () => {
	const res = runOnCopy((_dir, read, write) => {
		const src = read('apps/custom_watch/core/src/flash_store.rs');
		const frozen = src.replace(
			'pub const MAX_POINTS_PER_RUN: u32 = ((SLOT_LEN - HEADER_LEN - FOOTER_LEN) / POINT_LEN) as u32;',
			'pub const MAX_POINTS_PER_RUN: u32 = 253;',
		);
		assert.notEqual(frozen, src);
		write('apps/custom_watch/core/src/flash_store.rs', frozen);
	});
	assert.equal(res.status, 1);
	assert.match(res.stderr, /`MAX_POINTS_PER_RUN` is now `253`.*not the derivation/s);
});

test('every NOT_A_SYMBOL_COUNT entry names a doc in DOC_FILES and carries a reason', () => {
	for (const e of NOT_A_SYMBOL_COUNT) {
		assert.ok(DOC_FILES.includes(e.file), `${e.file} is not in DOC_FILES`);
		assert.ok(e.reason.length > 40, `the exemption for "${e.text}" needs a written reason`);
	}
});

// --- the doc set reconciles with the directory ------------------------------

test('every markdown under docs/custom_watch is registered or named a dated log', () => {
	assert.deepEqual(unregisteredDocs(readdirSync(join(ROOT, 'docs/custom_watch'))), []);
	for (const log of DATED_LOGS) assert.ok(!DOC_FILES.includes(log), `${log} is in both lists`);
});

test('a new doc under docs/custom_watch fails the guard rather than going unread', () => {
	assert.deepEqual(unregisteredDocs(['README.md', 'invented.md']), [
		'docs/custom_watch/invented.md',
	]);
	const res = runOnCopy((dir) => {
		writeFileSync(
			join(dir, 'docs/custom_watch/invented.md'),
			'# invented\n\nThe wrist holds twelve waypoints.\n',
		);
	});
	assert.equal(res.status, 1);
	assert.match(res.stderr, /invented\.md is under docs\/custom_watch but in neither DOC_FILES/);
});

// --- the host-test count -----------------------------------------------------

test('declaredModules reads lib.rs\'s own list, not a directory', () => {
	const src = [
		'//! A crate doc comment naming mod ghost;',
		'// mod commented_out;',
		'pub mod age_grade;',
		'mod internal;',
		'pub use age_grade::Foo;',
	].join('\n');
	assert.deepEqual(declaredModules(src), ['age_grade', 'internal']);
	assert.throws(() => declaredModules('pub use x::y;'), /no `mod` declarations/);
});

test('testFnCount counts attributes and not comments about them', () => {
	const src = [
		'// #[test] in a comment is not a test.',
		'/// Nor is #[test] in a doc comment.',
		'#[test]',
		'fn a() {}',
		'#[ test ]',
		'fn b() {}',
		'#[tokio::test]',
		'fn c() {}',
	].join('\n');
	// `#[tokio::test]` is deliberately not matched: the attribute this counts is
	// the bare libtest one, which is what `cargo test` runs in this crate.
	assert.equal(testFnCount(src), 2);
	assert.equal(testFnCount('fn a() {}'), 0);
});

test('the host-test count is the sum over the declared modules', () => {
	const row = REGISTRY.find((r) => r.id === 'core.host_tests');
	assert.ok(row, 'core.host_tests is gone from the registry');
	/** @type {Record<string, string>} */
	const fixture = {
		'apps/custom_watch/core/src/lib.rs': 'pub mod a;\npub mod b;\n',
		'apps/custom_watch/core/src/a.rs': '#[test]\nfn one() {}\n#[test]\nfn two() {}\n',
		'apps/custom_watch/core/src/b.rs': '#[test]\nfn three() {}\n',
		// Present on disk, declared by nobody: not compiled, so its tests do not
		// run and must not be counted.
		'apps/custom_watch/core/src/orphan.rs': '#[test]\nfn never() {}\n',
	};
	assert.equal(
		row.resolve((path) => {
			const src = fixture[path];
			assert.ok(src !== undefined, `resolve read an undeclared file: ${path}`);
			return src;
		}),
		3,
	);
});

test('a stale host-test count in a present-tense doc fails the guard', () => {
	const { status, stderr } = runOnCopy((_dir, read, write) => {
		const f = 'apps/custom_watch/CLAUDE.md';
		const md = read(f);
		const m = /(\d+) host tests in `watch_core`/.exec(md);
		assert.ok(m, 'the registered sentence is gone from apps/custom_watch/CLAUDE.md');
		write(f, md.replace(m[0], `${Number(m[1]) + 1} host tests in \`watch_core\``));
	});
	assert.notEqual(status, 0);
	assert.match(stderr, /core\.host_tests/);
});

test('a NEW numbered host-test claim must be registered or exempted', () => {
	// The sweep half: this is what catches a count nobody thought to register,
	// which is the case the registry is structurally blind to.
	const { status, stderr } = runOnCopy((_dir, read, write) => {
		const f = 'apps/custom_watch/local_testing.md';
		write(f, `${read(f)}\n\nThe driver crates carry 99 host tests between them.\n`);
	});
	assert.notEqual(status, 0);
	assert.match(stderr, /99 host tests/);
});

test('a stale per-module host-test count fails too', () => {
	const { status, stderr } = runOnCopy((_dir, read, write) => {
		const f = 'apps/custom_watch/core/src/privacy.rs';
		write(f, `${read(f)}\n#[test]\nfn planted() {}\n`);
	});
	assert.notEqual(status, 0);
	assert.match(stderr, /privacy\.host_tests/);
});
