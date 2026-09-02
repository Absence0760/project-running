// Unit tests for verify_chromium.sh — the install-playwright composite
// action's verification + apt fallback.
//
// This shell had never been executed by anything. A composite action's steps
// are in no job's test suite, and its apt branch runs only after a launch has
// already failed, which the incident history says is rare — so the entire
// repair path shipped unrun, and the property its comments claim (the verdict
// is the browser, not apt's exit code) was asserted nowhere.
//
// Driven with stub `node`, `pnpm`, `sudo`, `timeout` and `grep` on PATH. The
// `sudo` stub records rather than executes: nothing in the script branches on
// what any of its calls return — they are the apt.conf write, the lock reap and
// the sources dump, each `|| true` or ignored — so running them would gain no
// coverage and would write to /etc.

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const SCRIPT = fileURLToPath(new URL('./verify_chromium.sh', import.meta.url));

/// `node -e '<launch>'` is the only `node` the script runs. The stub answers
/// from a queue file so a case can say "fails, then succeeds" — which is the
/// whole shape of the repair path.
const NODE_STUB = `#!/usr/bin/env bash
n=$(cat "$LAUNCH_N" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" > "$LAUNCH_N"
verdict=$(awk -v i="$n" 'NR==i' "$LAUNCH_PLAN")
[ -n "$verdict" ] || verdict=$(tail -n1 "$LAUNCH_PLAN")
if [ "$verdict" = ok ]; then
  exit 0
fi
echo "Host system is missing dependencies to run browsers: libnss3"
exit 1
`;

/// `pnpm exec playwright install-deps chromium` is the only `pnpm` it runs.
const PNPM_STUB = `#!/usr/bin/env bash
printf '%s\\n' "pnpm $*" >> "$CMD_LOG"
n=$(cat "$APT_N" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" > "$APT_N"
verdict=$(awk -v i="$n" 'NR==i' "$APT_PLAN")
[ -n "$verdict" ] || verdict=$(tail -n1 "$APT_PLAN")
[ "$verdict" = ok ]
`;

/// Records and succeeds. See the header for why it does not execute.
const SUDO_STUB = `#!/usr/bin/env bash
printf '%s\\n' "sudo $*" >> "$CMD_LOG"
cat >/dev/null 2>&1 || true
exit 0
`;

/// `timeout [-k N] SECONDS cmd...` — drop the bounds, run the command. The
/// script's own timeouts are 120s; a test that honoured them would spend them.
const TIMEOUT_STUB = `#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  case "$1" in
    -k) shift 2;;
    [0-9]*) shift; break;;
    *) break;;
  esac
done
exec "$@"
`;

/// The sources dump reads /etc; on a container with no sources.list the real
/// grep answers nothing, which would make the assertion untestable.
const GREP_STUB = `#!/usr/bin/env bash
case "$*" in
  *sources.list*) echo 'http://azure.archive.ubuntu.com'; exit 0;;
esac
exec /usr/bin/grep "$@"
`;

/**
 * @param {{ launches: string[], apt?: string[] }} plan
 * @returns {{ status: number | null, out: string, commands: string[], launches: number }}
 */
function run({ launches, apt = ['ok'] }) {
	const dir = mkdtempSync(join(tmpdir(), 'verify-chromium-'));
	const files = {
		LAUNCH_PLAN: launches.join('\n') + '\n',
		APT_PLAN: apt.join('\n') + '\n',
		LAUNCH_N: '',
		APT_N: '',
		CMD_LOG: '',
	};
	/** @type {Record<string, string>} */
	const env = {};
	for (const [name, body] of Object.entries(files)) {
		const p = join(dir, name);
		writeFileSync(p, body);
		env[name] = p;
	}
	for (const [name, body] of [
		['node', NODE_STUB],
		['pnpm', PNPM_STUB],
		['sudo', SUDO_STUB],
		['timeout', TIMEOUT_STUB],
		['grep', GREP_STUB],
	]) {
		const p = join(dir, name);
		writeFileSync(p, body);
		chmodSync(p, 0o755);
	}
	const res = spawnSync('bash', [SCRIPT], {
		encoding: 'utf8',
		env: { ...process.env, ...env, PATH: `${dir}:${process.env.PATH}` },
	});
	return {
		status: res.status,
		out: `${res.stdout}${res.stderr}`,
		commands: readFileSync(env.CMD_LOG, 'utf8').trim().split('\n').filter(Boolean),
		launches: Number(readFileSync(env.LAUNCH_N, 'utf8') || 0),
	};
}

const installDeps = (/** @type {string[]} */ commands) =>
	commands.filter((c) => c.includes('install-deps'));

// The case that runs on every green shard, and the one the whole design is
// for: apt is never reached, so a dead Ubuntu mirror cannot fail the job.
test('a browser that launches never reaches apt', () => {
	const r = run({ launches: ['ok'] });
	assert.equal(r.status, 0);
	assert.match(r.out, /apt not needed/);
	assert.equal(r.launches, 1);
	assert.deepEqual(r.commands, []);
});

test('a browser that will not launch falls through to apt and is re-verified', () => {
	const r = run({ launches: ['fail', 'ok'] });
	assert.equal(r.status, 0);
	assert.match(r.out, /::warning::Chromium would not launch/);
	// Playwright's own message reaches the log — the library it names is the
	// point of preferring a launch over an `ldd` read.
	assert.match(r.out, /libnss3/);
	assert.match(r.out, /launched after installing/);
	assert.equal(installDeps(r.commands).length, 1);
	assert.equal(r.launches, 2);
	// The apt timeout config is written, and written BEFORE the first attempt
	// rather than after a failure — an unbounded first attempt is what the
	// mirror outages spent. Both halves: an `indexOf` that finds nothing
	// answers -1, which orders before everything and would read as "written
	// first" for a config that is never written at all.
	const confAt = r.commands.findIndex((c) => c.includes('99-ci-timeouts'));
	const aptAt = r.commands.findIndex((c) => c.includes('install-deps'));
	assert.ok(confAt >= 0, `apt.conf never written: ${r.commands.join('\n')}`);
	assert.ok(aptAt >= 0, `install-deps never run: ${r.commands.join('\n')}`);
	assert.ok(confAt < aptAt, r.commands.join('\n'));
});

// The property the script's own comment claims and nothing asserted: apt
// failing on every attempt is not the verdict. It can fail on a mirror having
// already installed what was missing.
test('install-deps failing three times still passes when the browser then launches', () => {
	const r = run({ launches: ['fail', 'ok'], apt: ['fail', 'fail', 'fail'] });
	assert.equal(r.status, 0);
	assert.equal(installDeps(r.commands).length, 3);
	assert.match(r.out, /launched after installing/);
});

// And its converse: apt succeeding is not the verdict either.
test('install-deps succeeding is not enough — the second launch decides', () => {
	const r = run({ launches: ['fail', 'fail'], apt: ['ok'] });
	assert.equal(r.status, 1);
	assert.match(r.out, /::error::Chromium still will not launch/);
	assert.equal(installDeps(r.commands).length, 1);
});

test('a first install-deps that works is not retried', () => {
	const r = run({ launches: ['fail', 'ok'], apt: ['ok'] });
	assert.equal(installDeps(r.commands).length, 1);
});

// A `timeout` kill leaves the apt-get it spawned through sudo holding the
// dpkg locks, so the NEXT attempt would fail on "Could not get lock" and hide
// the mirror behind our own leftovers.
test('each failed attempt reaps apt before the next one', () => {
	const r = run({ launches: ['fail', 'fail'], apt: ['fail', 'fail', 'fail'] });
	assert.equal(r.status, 1);
	const reaps = r.commands.filter((c) => /pkill -9 -x apt-get/.test(c));
	assert.equal(reaps.length, 3, r.commands.join('\n'));
	assert.ok(r.commands.some((c) => /dpkg --configure -a/.test(c)));
});

// A library apt could not resolve is a mirror problem, and the mirror is the
// one fact the log otherwise does not carry.
test('giving up prints the browser’s own error and the apt sources', () => {
	const r = run({ launches: ['fail', 'fail'], apt: ['fail'] });
	assert.equal(r.status, 1);
	// Under the `::error::`, not merely somewhere in the log: the first failed
	// launch already printed the same message under a `::warning::`, so a
	// bare match on the library name passes with the final dump deleted.
	const after = r.out.slice(r.out.indexOf('::error::'));
	assert.match(after, /libnss3/, r.out);
	assert.match(after, /azure\.archive\.ubuntu\.com/, r.out);
});

// The apt.conf heredoc's terminator has to sit at column 0 of the script the
// shell sees. It is written INDENTED inside action.yml's block scalar, and
// only YAML's dedent puts it there — a `<<'CONF'` (not `<<-`) whose terminator
// stays indented never closes, and the shell would swallow the retry loop and
// the final verdict as heredoc content.
test('the apt config heredoc closes, so the code under it runs', () => {
	const text = readFileSync(SCRIPT, 'utf8');
	assert.match(text, /^CONF$/m);
	execFileSync('bash', ['-n', SCRIPT]);
});

test('the action invokes this script rather than carrying its own copy', () => {
	const action = readFileSync(
		fileURLToPath(new URL('./action.yml', import.meta.url)),
		'utf8',
	);
	assert.match(action, /verify_chromium\.sh/);
	assert.doesNotMatch(action, /install-deps/, 'the logic must have one home');
});
