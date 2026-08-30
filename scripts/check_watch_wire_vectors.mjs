#!/usr/bin/env node
// Guardrail: the watch's six wire formats say the same bytes on both rails, by
// reading the firmware's golden vectors and the phone's golden vectors and
// comparing them.
//
// Why this exists: decisions.md § 793. Every `CRS1` / `WKT1` / `RBK1` / `SCR1`
// / `SET1` / `TRK1` golden vector exists TWICE — a Rust test recomputing it
// from the firmware codec, a Dart test recomputing it from the phone codec —
// and nothing compared the two. Both sides even carried a comment reading
// "update BOTH this vector and the … mirror", which is an instruction where an
// enforcement belongs: a one-sided version bump fails only the rail that
// changed, and the other rail's suite stays green while the phone encodes a
// frame the watch would refuse. That is § 641's standing lesson — a rail
// registered in no registry drifts with nothing able to notice — applied to a
// wire format rather than to a helper.
//
// The design is `check_watch_ble_uuids.mjs`'s: parse both rails, transcribe
// neither. Only the anchor→anchor pairing below lives in this file; every byte
// is read out of a source file. A guard that hardcoded a third copy of each
// vector would be the defect wearing a new hat — it would pass while both
// rails moved together away from it, and it would fail on a legitimate bump in
// a place that has no codec to be right or wrong about.
//
// Soundness. This compares the two rails' PINNED literals, not two live codecs
// in one process: a `no_std` Rust test binary and a Flutter test binary cannot
// meet, and a runner that ran both would need the Rust toolchain and the
// Flutter SDK to answer a question that is decidable from source. What makes it
// a real check rather than a transcription check is that each literal is
// already asserted equal to its own rail's freshly-computed bytes by the very
// test it is read out of. `usesCodec` keeps that middle term honest: a pair
// whose Rust or Dart site stops calling a codec — the assertion deleted, or a
// literal compared to another literal — fails here rather than quietly
// degrading into a comparison of two decorations.
//
// What the composition proves differs by direction, and the guard does not
// overclaim. For `CRS1` / `WKT1` / `RBK1` / `SCR1` / `SET1` both rails ENCODE,
// so it gives firmware-encoder == phone-encoder. `TRK1` runs the other way —
// the watch writes a run blob and the phone only ever reads one — so there it
// gives phone-decoder-input == firmware-encoder-output, which is the contract
// that rail actually has.
//
// Run: `node scripts/check_watch_wire_vectors.mjs`
// CI:  the `watch-wire-vectors` job in .github/workflows/ci.yml, which is in
//      the `CI gate` aggregator's `needs:` list — a guard nothing runs
//      enforces nothing.
// Unit tests: `node --test scripts/check_watch_wire_vectors.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripComments } from './comment_strip.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const RUST_ROOT =
	process.env.WATCH_VECTORS_RUST_ROOT ??
	join(REPO_ROOT, 'apps/custom_watch/core/src');
export const DART_ROOT =
	process.env.WATCH_VECTORS_DART_ROOT ??
	join(REPO_ROOT, 'apps/mobile_android/test');

// The magic each format stamps in its first four bytes, hex-encoded. The
// completeness scan uses these to recognise a wire vector wherever it appears,
// so a newly added one has to be paired or explicitly excused rather than
// silently living on one rail — which is the whole failure this file exists to
// stop, one step earlier.
/** @type {Readonly<Record<string, string>>} */
export const MAGICS = {
	CRS1: '43525331',
	WKT1: '574b5431',
	RBK1: '52424b31',
	SCR1: '53435231',
	SET1: '53455431',
	TRK1: '54524b31',
};

/**
 * Where a vector is written. `file` is a basename under RUST_ROOT / DART_ROOT;
 * `anchor` is the enclosing declaration, spelled `fn:<name>` / `const:<NAME>`
 * on the Rust side and `const:<name>` / `test:<exact test name>` on the Dart
 * side. `#<n>` picks the nth (0-based) vector when the block holds more.
 * @typedef {{ file: string, anchor: string }} Site
 * @typedef {{ id: string, magic: keyof typeof MAGICS, rust: Site, dart: Site }} Pair
 */

/**
 * The registry. A row says "these two literals are the same bytes"; the bytes
 * themselves are never written down here.
 * @type {readonly Pair[]}
 */
export const PAIRS = [
	{
		id: 'CRS1 course frame',
		magic: 'CRS1',
		rust: { file: 'course_store.rs', anchor: 'fn:golden_frame_is_stable' },
		dart: { file: 'watch_course_test.dart', anchor: 'const:_goldenHex' },
	},
	{
		id: 'CRS1 course frame with elevations',
		magic: 'CRS1',
		rust: {
			file: 'course_store.rs',
			anchor: 'fn:golden_elevation_frame_is_stable',
		},
		dart: { file: 'watch_course_test.dart', anchor: 'const:_goldenElevHex' },
	},
	{
		id: 'WKT1 workout frame',
		magic: 'WKT1',
		rust: { file: 'workout_store.rs', anchor: 'fn:golden_frame_is_stable' },
		dart: { file: 'watch_workout_test.dart', anchor: 'const:_goldenHex' },
	},
	{
		id: 'RBK1 roadbook frame',
		magic: 'RBK1',
		rust: { file: 'roadbook_store.rs', anchor: 'fn:golden_frame_is_stable' },
		dart: { file: 'watch_roadbook_test.dart', anchor: 'const:_goldenHex' },
	},
	{
		id: 'SCR1 screens frame',
		magic: 'SCR1',
		rust: { file: 'screens.rs', anchor: 'fn:the_golden_frame_is_stable' },
		dart: { file: 'watch_screens_test.dart', anchor: 'const:_goldenHex' },
	},
	{
		id: 'SET1 every field',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector' },
		dart: { file: 'watch_settings_test.dart', anchor: 'const:_goldenHex' },
	},
	{
		id: 'SET1 v4 arming fields only',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector_v4_arms_only' },
		dart: {
			file: 'watch_settings_test.dart',
			anchor: 'test:the five v4 fields keep flags2 bit order',
		},
	},
	{
		id: 'SET1 resting HR only',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector_resting_hr_only' },
		dart: {
			file: 'watch_settings_test.dart',
			anchor: 'test:restingHr sets flags2 bit6 and matches the firmware golden',
		},
	},
	{
		id: 'SET1 ICE card only',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector_ice_only' },
		dart: {
			file: 'watch_settings_test.dart',
			anchor: 'test:ice sets flags2 bit7 and matches the firmware golden',
		},
	},
	{
		id: 'SET1 tz offset only',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector_tz_only' },
		dart: {
			file: 'watch_settings_test.dart',
			anchor: 'test:tz-only frame matches the firmware golden byte-for-byte',
		},
	},
	{
		id: 'SET1 auto-lap only',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector_auto_lap_only' },
		dart: {
			file: 'watch_settings_test.dart',
			anchor: 'test:the min10 auto-lap rung matches the firmware golden',
		},
	},
	{
		id: 'SET1 storm alert only',
		magic: 'SET1',
		rust: { file: 'settings.rs', anchor: 'fn:golden_vector_storm_only' },
		dart: {
			file: 'watch_settings_test.dart',
			anchor:
				'test:stormAlertHpa sets flags3 bit1, travels as tenths, and 0 disarms',
		},
	},
	{
		id: 'TRK1 v4 run blob',
		magic: 'TRK1',
		rust: { file: 'run_store.rs', anchor: 'fn:golden_blob_is_stable' },
		dart: { file: 'sim_watch_sync_test.dart', anchor: 'const:_goldenV4Hex' },
	},
	{
		id: 'TRK1 v4 run blob with a lap',
		magic: 'TRK1',
		rust: { file: 'run_store.rs', anchor: 'fn:golden_blob_with_a_lap_is_stable' },
		dart: { file: 'sim_watch_sync_test.dart', anchor: 'const:_goldenV4LapHex' },
	},
	{
		id: 'TRK1 v4 run blob with workout records',
		magic: 'TRK1',
		rust: {
			file: 'run_store.rs',
			anchor: 'fn:golden_blob_with_workout_records_is_stable',
		},
		dart: { file: 'sim_watch_sync_test.dart', anchor: 'const:_goldenWorkoutHex' },
	},
	{
		id: 'TRK1 v1 run blob (refused on both rails)',
		magic: 'TRK1',
		rust: { file: 'run_store.rs', anchor: 'const:V1_HEX' },
		dart: { file: 'sim_watch_sync_test.dart', anchor: 'const:_v1GoldenHex' },
	},
	{
		id: 'TRK1 v2 run blob (refused on both rails)',
		magic: 'TRK1',
		rust: { file: 'run_store.rs', anchor: 'const:V2_HEX' },
		dart: { file: 'sim_watch_sync_test.dart', anchor: 'const:_v2GoldenHex' },
	},
];

/**
 * Declarations whose vectors live on ONE rail on purpose. The excuse is by
 * BLOCK, not by bytes, so re-pinning an excused vector after a legitimate
 * change does not require editing this guard — what it does require is that a
 * brand-new declaration full of wire bytes be either paired above or listed
 * here, which is the decision the § 793 filing found nobody was being asked to
 * make.
 *
 * The asymmetry is structural. The phone only ever ENCODES the current
 * version, so every superseded SET1 version is pinned on the firmware side
 * alone, where the decoder that must still read it lives. It runs the other way
 * too: the phone pins single-field SET1 frames the firmware covers by
 * round-trip property test instead of by a golden, and TRK1 compat blobs from
 * firmware that has since moved on.
 *
 * @typedef {{ rail: 'rust' | 'dart', file: string, anchor: string, why: string }} Solo
 * @type {readonly Solo[]}
 */
export const SOLO = [
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:v7_golden_vector_still_decodes',
		why: 'superseded version; the phone stopped encoding v7 at the v8 bump',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:v6_golden_vector_still_decodes',
		why: 'superseded version, firmware-decoder-only',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:v5_golden_vector_still_decodes',
		why: 'superseded version, firmware-decoder-only',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:v4_golden_vector_still_decodes',
		why: 'superseded version, firmware-decoder-only',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:v3_golden_vector_still_decodes',
		why: 'oldest version the firmware accepts, firmware-decoder-only',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:a_v2_golden_vector_is_refused_for_carrying_no_checksum',
		why: 'a refusal pinned against bytes no encoder on either rail produces',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:a_v1_golden_vector_is_refused_for_carrying_no_checksum',
		why: 'a refusal pinned against bytes no encoder on either rail produces',
	},
	{
		rail: 'rust',
		file: 'settings.rs',
		anchor: 'fn:no_pre_crc_framing_however_tidy_survives_the_version_gate',
		why: 'deliberately malformed prefixes, not frames either rail emits',
	},
	{
		rail: 'dart',
		file: 'sim_watch_sync_test.dart',
		anchor: 'test:connects, writes the encoded frame, disconnects',
		why: 'a transport-level assertion that the SET1 bytes reach the write characteristic; the frame itself is pinned by watch_settings_test',
	},
	{
		rail: 'dart',
		file: 'sim_watch_sync_test.dart',
		anchor: 'const:_goldenHex',
		why: 'v3 run blob a bench board may still hold; firmware pins v4 as its own golden',
	},
	{
		rail: 'dart',
		file: 'sim_watch_sync_test.dart',
		anchor: 'const:_goldenLapHex',
		why: 'the v3 form of the lap blob, kept decodable alongside _goldenHex',
	},
];

// Every Dart SET1 single-field frame outside the six paired above. The firmware
// covers these by round-trip property test (`prop_settings.rs`) rather than by
// a golden, so there is no counterpart literal to compare and pairing them
// would mean inventing one — a third transcription, which is the shape this
// guard exists to avoid. They are excused as a block because they all sit in
// the one `WatchSettings.encode` group.
const DART_SETTINGS_SOLO_TESTS = [
	'empty frame is header + crc with zero flags in all three bytes',
	'maxHr-only frame sets bit0 and carries the u16',
	'pacer-only frame sets bit1 and carries distance then time',
	'gear-only frame sets bit2 and carries baseline then target',
	'a null gear target encodes as 0.0 (no target / untracked)',
	'zoneCeiling 0 clears the ceiling and still sets bit3',
	'zoneCeiling 4 encodes the top ceiling zone',
	'seaLevelPa-only frame sets bit4 and carries the f32',
	'fuel-only frame sets bit5 and carries drink then eat',
	'present fields are laid out in bit order regardless of set subset',
	'sea-level and fuel keep bit order after the earlier fields',
	'pages-only frame sets bit6 and carries the u64 mask',
	'hideEmptyPages sets bit7 and encodes as one byte',
	'pages and hideEmpty keep bit order after the earlier fields',
	'a positive tz offset encodes as i16 LE after every flags field',
	'a zero tz offset (UTC zone) is still a present field',
	'distanceIntervalM sets flags2 bit1 and 0 disarms the alert',
	'timeIntervalS sets flags2 bit2 and 0 disarms the alert',
	'paceBand travels whole under flags2 bit3 and an all-zero band disarms',
	'racePhases sets flags2 bit4 and carries distance, goal, preset index',
	'guidedRunId sets flags2 bit5 and pads the ascii id with NULs',
	'restingHr lays out after the flags fields and after guidedRunId',
	'an all-blank card is a real field that CLEARS the watch card',
	'autoLap sets flags3 bit0 and carries the rung as one byte',
	'an armed threshold never rounds into the disarm sentinel',
	'the flags3 fields lay out last, in bit order after the ice card',
	'every frame stamps v8, so a v8 field can never ride a v7 header',
];

/** @type {readonly Solo[]} */
const ALL_SOLO = [
	...SOLO,
	...DART_SETTINGS_SOLO_TESTS.map((name) => ({
		/** @type {'dart'} */
		rail: /** @type {'dart'} */ ('dart'),
		file: 'watch_settings_test.dart',
		anchor: `test:${name}`,
		why: 'single-field SET1 frame; the firmware covers it by round-trip property test',
	})),
];

// What "a codec ran here" looks like on each rail. Deliberately loose about
// WHICH codec: the magic in the bytes already says which format it is, and the
// property being checked is only that something computed the left-hand side.
export const RUST_CODEC =
	/\b(encode|encode_vec|encode_vec_with|finalize|build|from_hex|verify_blob|decode)\s*\(/;
export const DART_CODEC =
	/(\.encode\(|\b(encodeCourse|encodeWorkoutSteps|encodeRoadbook|encodeWatchScreens|verifyBlob|payloadFromBlob|decodeManifest)\s*\()/;

/** @typedef {{ hex: string, line: number, at: number }} Found */
/** @typedef {{ name: string, from: number, to: number }} Block */

/**
 * Rust and Dart both concatenate adjacent string literals, so a vector written
 * across several quoted chunks (with `\`-continuations on the Rust side) is one
 * value. Whitespace and `_` inside a chunk are layout, never data.
 * @param {string} raw @returns {string}
 */
function normaliseHex(raw) {
	return raw.replace(/\\\s*\n/g, '').replace(/[\s_]/g, '').toLowerCase();
}

/** @param {string} src @param {number} at @returns {number} */
function lineAt(src, at) {
	return src.slice(0, at).split('\n').length;
}

/** @param {string} s @returns {string} */
function escapeRe(s) {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * The offset one past the string literal opening at `at`.
 * @param {string} code @param {number} at @returns {number}
 */
function endOfString(code, at) {
	const quote = code[at];
	let i = at + 1;
	while (i < code.length) {
		if (code[i] === '\\') {
			i += 2;
			continue;
		}
		if (code[i] === quote) return i + 1;
		i++;
	}
	throw new Error('unterminated string literal');
}

/**
 * The offset one past the `{ … }` block opening at or after `from`. String-aware,
 * because `format_args!("{:02x}", b)` must not move the depth counter.
 * @param {string} code @param {number} from @returns {number}
 */
function endOfBlock(code, from) {
	let i = code.indexOf('{', from);
	if (i === -1) throw new Error('no block opens after the anchor');
	let depth = 0;
	while (i < code.length) {
		const c = code[i];
		if (c === '"' || c === "'") {
			i = endOfString(code, i);
			continue;
		}
		if (c === '{') depth++;
		else if (c === '}') {
			depth--;
			if (depth === 0) return i + 1;
		}
		i++;
	}
	throw new Error('unterminated block after the anchor');
}

/**
 * Every declaration in the file that can hold a vector, with its span. A Rust
 * `const` and a Dart `const` both end at the `;`; a `fn` and a `test(…)` both
 * end at their block.
 * @param {string} code comment-stripped source
 * @param {'rust' | 'dart'} lang
 * @returns {Block[]}
 */
export function blocksIn(code, lang) {
	/** @type {Block[]} */
	const out = [];
	const decl =
		lang === 'rust'
			? /\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(|\bconst\s+([A-Za-z_][A-Za-z0-9_]*)\s*:/g
			: /\btest\s*\(\s*(['"])((?:[^'"\\]|\\.)*)\1|\bconst\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=/g;
	for (const m of code.matchAll(decl)) {
		const at = m.index ?? 0;
		if (lang === 'rust') {
			if (m[1] !== undefined) {
				out.push({ name: `fn:${m[1]}`, from: at, to: endOfBlock(code, at) });
			} else if (m[2] !== undefined) {
				const semi = code.indexOf(';', at);
				out.push({
					name: `const:${m[2]}`,
					from: at,
					to: semi === -1 ? code.length : semi,
				});
			}
			continue;
		}
		if (m[2] !== undefined) {
			out.push({ name: `test:${m[2]}`, from: at, to: endOfBlock(code, at) });
		} else if (m[3] !== undefined) {
			const semi = code.indexOf(';', at);
			out.push({
				name: `const:${m[3]}`,
				from: at,
				to: semi === -1 ? code.length : semi,
			});
		}
	}
	return out;
}

/**
 * The innermost declaration containing `at`, or null.
 * @param {Block[]} blocks @param {number} at @returns {Block | null}
 */
function enclosing(blocks, at) {
	/** @type {Block | null} */
	let best = null;
	for (const b of blocks) {
		if (at < b.from || at >= b.to) continue;
		if (best === null || b.to - b.from < best.to - best.from) best = b;
	}
	return best;
}

/**
 * Every run of adjacent hex string literals in `code[from, to)`, plus every
 * `[0x.., 0x.., …]` byte array. Both are how a wire vector is spelled in this
 * tree; a run under four bytes cannot carry a magic and is layout, not a vector.
 * @param {string} code @param {number} from @param {number} to @returns {Found[]}
 */
export function vectorsIn(code, from, to) {
	/** @type {Found[]} */
	const out = [];
	let i = from;
	/** @type {Found | null} */
	let run = null;
	const flush = () => {
		if (run && run.hex.length >= 8) out.push(run);
		run = null;
	};
	while (i < to) {
		const c = code[i];
		if (c === '"' || c === "'") {
			const end = endOfString(code, i);
			const body = normaliseHex(code.slice(i + 1, end - 1));
			if (/^[0-9a-f]*$/.test(body) && body.length % 2 === 0) {
				if (run) run.hex += body;
				else run = { hex: body, line: lineAt(code, i), at: i };
			} else {
				flush();
			}
			i = end;
			continue;
		}
		// Whitespace between two literals keeps the run alive; any other token
		// ends it, so two vectors in one argument list stay two vectors.
		if (!/\s/.test(c)) flush();
		i++;
	}
	flush();

	const byteArray = /(?:\b0x[0-9a-fA-F]{2}\b\s*,\s*){3,}\b0x[0-9a-fA-F]{2}\b/g;
	for (const m of code.slice(from, to).matchAll(byteArray)) {
		const at = from + (m.index ?? 0);
		const hex = (m[0].match(/0x([0-9a-fA-F]{2})\b/g) ?? [])
			.map((b) => b.slice(2).toLowerCase())
			.join('');
		out.push({ hex, line: lineAt(code, at), at });
	}
	out.sort((a, b) => a.at - b.at);
	// A bare magic is a claim about the first four bytes, not a frame — the
	// `header carries …` tests on both rails spell one out, and pairing those
	// would mean pairing a magic with itself.
	const magics = Object.values(MAGICS);
	return out.filter((f) => !magics.includes(f.hex));
}

/**
 * Resolve one site to its bytes.
 * @param {string} src raw source
 * @param {string} anchor
 * @param {'rust' | 'dart'} lang
 * @param {string} where file label, for errors
 * @returns {Found}
 */
export function vectorAt(src, anchor, lang, where) {
	const code = stripComments(src, lang);
	const hash = anchor.lastIndexOf('#');
	const index = hash === -1 ? 0 : Number(anchor.slice(hash + 1));
	const name = hash === -1 ? anchor : anchor.slice(0, hash);
	const block = blocksIn(code, lang).find((b) => b.name === name);
	if (!block) throw new Error(`${where}: no ${name}`);
	const found = vectorsIn(code, block.from, block.to);
	if (found.length <= index) {
		throw new Error(
			`${where}: ${name} holds ${found.length} vector(s), wanted #${index}`,
		);
	}
	return found[index];
}

/**
 * Does the site's declaration actually run a codec? A pinned literal is only
 * evidence about a codec while something compares it to that codec's output.
 * A `const` names a value used elsewhere, so its USE SITES are what is checked
 * — scanning the whole file instead would pass on any file that mentions a
 * codec anywhere, which is every file here.
 * @param {string} src @param {string} anchor @param {'rust' | 'dart'} lang
 * @param {RegExp} shape @returns {boolean}
 */
export function usesCodec(src, anchor, lang, shape) {
	const code = stripComments(src, lang);
	const hash = anchor.lastIndexOf('#');
	const name = hash === -1 ? anchor : anchor.slice(0, hash);
	const blocks = blocksIn(code, lang);
	const block = blocks.find((b) => b.name === name);
	if (!block) return false;
	if (!name.startsWith('const:')) {
		return shape.test(code.slice(block.from, block.to));
	}
	const ident = name.slice('const:'.length);
	const uses = [...code.matchAll(new RegExp(`\\b${escapeRe(ident)}\\b`, 'g'))];
	return uses.some((m) => {
		const at = m.index ?? 0;
		if (at >= block.from && at < block.to) return false;
		const host = enclosing(blocks, at);
		return host !== null && shape.test(code.slice(host.from, host.to));
	});
}

/** @param {unknown} e @returns {string} */
function errText(e) {
	return e instanceof Error ? e.message : String(e);
}

/** @param {string} a @param {string} b @returns {string} */
function describeDiff(a, b) {
	const n = Math.min(a.length, b.length) / 2;
	for (let i = 0; i < n; i++) {
		const x = a.slice(i * 2, i * 2 + 2);
		const y = b.slice(i * 2, i * 2 + 2);
		if (x !== y) return `byte ${i}, firmware 0x${x} vs phone 0x${y}`;
	}
	return `byte ${n}, one rail is ${Math.abs(a.length - b.length) / 2} byte(s) longer`;
}

/** @returns {{ errors: string[], checked: number }} */
export function check() {
	/** @type {string[]} */
	const errors = [];
	/** @type {Map<string, string>} */
	const cache = new Map();
	/** @param {'rust' | 'dart'} rail @param {string} file */
	const read = (rail, file) => {
		const path = join(rail === 'rust' ? RUST_ROOT : DART_ROOT, file);
		let src = cache.get(path);
		if (src === undefined) {
			src = readFileSync(path, 'utf8');
			cache.set(path, src);
		}
		return src;
	};

	/** @type {Map<string, Set<string>>} `${rail}/${file}` -> claimed anchors */
	const claimed = new Map();
	/** @param {string} rail @param {string} file @param {string} anchor */
	const claim = (rail, file, anchor) => {
		const key = `${rail}/${file}`;
		const set = claimed.get(key) ?? new Set();
		set.add(anchor.includes('#') ? anchor.slice(0, anchor.lastIndexOf('#')) : anchor);
		claimed.set(key, set);
	};
	for (const s of ALL_SOLO) claim(s.rail, s.file, s.anchor);

	let checked = 0;
	for (const pair of PAIRS) {
		/** @type {Found | null} */ let rust = null;
		/** @type {Found | null} */ let dart = null;
		try {
			rust = vectorAt(
				read('rust', pair.rust.file),
				pair.rust.anchor,
				'rust',
				pair.rust.file,
			);
		} catch (e) {
			errors.push(`${pair.id}: firmware rail unreadable — ${errText(e)}`);
		}
		try {
			dart = vectorAt(
				read('dart', pair.dart.file),
				pair.dart.anchor,
				'dart',
				pair.dart.file,
			);
		} catch (e) {
			errors.push(`${pair.id}: phone rail unreadable — ${errText(e)}`);
		}
		claim('rust', pair.rust.file, pair.rust.anchor);
		claim('dart', pair.dart.file, pair.dart.anchor);
		if (!rust || !dart) continue;
		checked++;

		const magic = MAGICS[pair.magic];
		for (const [rail, site, found] of /** @type {const} */ ([
			['firmware', pair.rust, rust],
			['phone', pair.dart, dart],
		])) {
			if (!found.hex.startsWith(magic)) {
				errors.push(
					`${pair.id}: the ${rail} vector at ${site.file}:${found.line} does not open ` +
						`with the ${pair.magic} magic ${magic} — it starts ${found.hex.slice(0, 8)}. ` +
						'The registry row names the wrong literal.',
				);
			}
		}

		if (rust.hex !== dart.hex) {
			errors.push(
				`${pair.id}: THE TWO RAILS DISAGREE.\n` +
					`    firmware ${pair.rust.file}:${rust.line} (${rust.hex.length / 2} bytes)\n` +
					`      ${rust.hex}\n` +
					`    phone    ${pair.dart.file}:${dart.line} (${dart.hex.length / 2} bytes)\n` +
					`      ${dart.hex}\n` +
					`    first difference: ${describeDiff(rust.hex, dart.hex)}`,
			);
		}

		if (
			!usesCodec(read('rust', pair.rust.file), pair.rust.anchor, 'rust', RUST_CODEC)
		) {
			errors.push(
				`${pair.id}: the firmware vector at ${pair.rust.file}:${rust.line} is no longer ` +
					'compared against a codec call, so it pins nothing about the firmware ' +
					'codec and this guard would be comparing two decorations.',
			);
		}
		if (
			!usesCodec(read('dart', pair.dart.file), pair.dart.anchor, 'dart', DART_CODEC)
		) {
			errors.push(
				`${pair.id}: the phone vector at ${pair.dart.file}:${dart.line} is no longer ` +
					'compared against a codec call, so it pins nothing about the phone codec ' +
					'and this guard would be comparing two decorations.',
			);
		}
	}

	if (checked === 0 && errors.length === 0) {
		errors.push(
			'check_watch_wire_vectors: nothing was compared. An empty run is not a pass.',
		);
	}

	for (const s of ALL_SOLO) {
		const lang = /** @type {'rust' | 'dart'} */ (s.rail);
		const code = stripComments(read(s.rail, s.file), lang);
		if (!blocksIn(code, lang).some((b) => b.name === s.anchor)) {
			errors.push(
				`SOLO excuses ${s.file} ${s.anchor}, which no longer exists. A stale ` +
					'excuse silences whatever declaration takes its place.',
			);
		}
	}

	/** @type {Array<readonly ['rust' | 'dart', string]>} */
	const files = [];
	for (const p of PAIRS) {
		files.push(['rust', p.rust.file], ['dart', p.dart.file]);
	}
	for (const s of ALL_SOLO) files.push([s.rail, s.file]);
	/** @type {Set<string>} */
	const done = new Set();
	for (const [rail, file] of files) {
		if (done.has(`${rail}/${file}`)) continue;
		done.add(`${rail}/${file}`);
		const lang = /** @type {'rust' | 'dart'} */ (rail === 'rust' ? 'rust' : 'dart');
		const code = stripComments(read(rail, file), lang);
		const blocks = blocksIn(code, lang);
		const known = claimed.get(`${rail}/${file}`) ?? new Set();
		for (const found of vectorsIn(code, 0, code.length)) {
			if (!Object.values(MAGICS).some((m) => found.hex.startsWith(m))) continue;
			const host = enclosing(blocks, found.at);
			if (host && known.has(host.name)) continue;
			errors.push(
				`${file}:${found.line}: a wire vector in ${host ? host.name : 'no declaration'} ` +
					'that no PAIRS row claims and no SOLO row excuses. Pair it with its ' +
					'counterpart on the other rail, or add it to SOLO with the reason it ' +
					`lives on one rail.\n      ${found.hex}`,
			);
		}
	}

	return { errors, checked };
}

const invokedDirectly =
	process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
	const { errors, checked } = check();
	for (const e of errors) console.error(`::error::check_watch_wire_vectors: ${e}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_watch_wire_vectors: ${errors.length} problem(s) across ${PAIRS.length} registered pair(s).`,
		);
		process.exit(1);
	}
	console.log(
		`check_watch_wire_vectors: OK — ${checked} wire vector(s) agree on both rails.`,
	);
}
