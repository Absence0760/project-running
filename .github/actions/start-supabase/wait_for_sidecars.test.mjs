import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const SCRIPT = fileURLToPath(new URL('./wait_for_sidecars.sh', import.meta.url));

// The edge-runtime probe is the one that failed in CI, so it is the knob most
// cases turn; the other two default to answering immediately so a case
// exercises exactly one behaviour. They are knobs too, because each probe's
// READY PATTERN is the property this script exists for — the loop it replaced
// accepted kong's own answer as the upstream's — and a stub that always says
// 200 never asks whether the pattern would.
/** @param {{ edge: string, storage?: string, auth?: string }} bodies */
const CURL_STUB = ({ edge, storage = "printf '200'; exit 0", auth = "printf '200'; exit 0" }) =>
	`#!/usr/bin/env bash
url=''
maxtime=0
while [ $# -gt 0 ]; do
  case "$1" in
    --max-time) maxtime=$2; shift 2;;
    http*) url=$1; shift;;
    *) shift;;
  esac
done
printf '%s %s\\n' "$url" "$maxtime" >> "$CURL_LOG"
case "$url" in
  */storage/*) ${storage};;
  */auth/*) ${auth};;
  */functions/*) ${edge};;
esac
printf '000'
exit 7
`;

const DOCKER_STUB = `#!/usr/bin/env bash
cmd=$1
shift
case "$cmd" in
  ps)
    if printf '%s ' "$@" | grep -q -- '-aq'; then
      echo cid_edge
      echo cid_kong
    else
      echo 'supabase_edge_runtime_run Exited (1) 10 seconds ago'
    fi;;
  inspect) echo "STUB-INSPECT $*";;
  logs) echo "STUB-LOGS $*";;
esac
`;

/**
 * @param {{ edge: string, storage?: string, auth?: string, budget: number, maxTime: number, interval: number }} knobs
 * @returns {{ status: number | null, out: string, calls: string[], wallMs: number }}
 */
function run({ edge, storage, auth, budget, maxTime, interval }) {
	const dir = mkdtempSync(join(tmpdir(), 'wait-sidecars-'));
	const curlLog = join(dir, 'curl.log');
	writeFileSync(curlLog, '');
	for (const [name, body] of [
		['curl', CURL_STUB({ edge, storage, auth })],
		['docker', DOCKER_STUB]
	]) {
		const p = join(dir, name);
		writeFileSync(p, body);
		chmodSync(p, 0o755);
	}
	const startedAt = Date.now();
	const res = spawnSync('bash', [SCRIPT], {
		encoding: 'utf8',
		env: {
			...process.env,
			PATH: `${dir}:${process.env.PATH}`,
			CURL_LOG: curlLog,
			ANON_KEY: 'anon-key',
			PROBE_BUDGET_S: String(budget),
			PROBE_MAX_TIME_S: String(maxTime),
			PROBE_INTERVAL_S: String(interval),
			PROBE_LOG_TAIL: '5'
		}
	});
	const calls = readFileSync(curlLog, 'utf8').trim().split('\n').filter(Boolean);
	return {
		status: res.status,
		out: `${res.stdout}${res.stderr}`,
		calls,
		wallMs: Date.now() - startedAt
	};
}

/**
 * @param {readonly string[]} calls
 * @param {string} part
 * @returns {string[]}
 */
const attemptsOn = (calls, part) => calls.filter((l) => l.includes(part));

test('every sidecar answering leaves no error and reports the attempt count', () => {
	const r = run({ edge: "printf '405'; exit 0", budget: 8, maxTime: 2, interval: 1 });
	assert.equal(r.status, 0);
	assert.match(r.out, /ready: edge runtime \(clip-public-track\) -> 405 after \d+s \(1 attempt\(s\)\)/);
	assert.doesNotMatch(r.out, /::error::/);
});

test('a refused edge runtime reports the real elapsed time and attempt count', () => {
	const budget = 4;
	const r = run({ edge: "printf '000'; exit 7", budget, maxTime: 2, interval: 1 });
	assert.equal(r.status, 1);
	const m = r.out.match(
		/::error::edge runtime \(clip-public-track\) never became ready — gave up after (\d+)s and (\d+) attempt\(s\) \(budget 4s, last status (\d+)\)/
	);
	assert.ok(m, `no accounted failure line in:\n${r.out}`);
	const [, elapsed, attempts, lastStatus] = m;
	// The reported figures are the loop's own, not a constant: elapsed must
	// fit the budget and the attempt count must match the calls actually made.
	assert.ok(Number(elapsed) <= budget, `elapsed ${elapsed}s exceeds the ${budget}s budget`);
	assert.equal(Number(attempts), attemptsOn(r.calls, '/functions/').length);
	assert.ok(Number(attempts) > 1, `expected repeated attempts, got ${attempts}`);
	// curl reports 000 itself; the old `|| echo 000` fallback doubled it.
	assert.equal(lastStatus, '000');
	assert.doesNotMatch(r.out, /000000/);
	// A failed probe short-circuits — the auth probe must not have run.
	assert.equal(attemptsOn(r.calls, '/auth/').length, 0);
});

test("a hanging edge runtime is charged its curl timeout against the budget", () => {
	const budget = 6;
	const maxTime = 3;
	// Emulates curl exhausting --max-time: the failure mode whose cost the
	// old attempt-counted loop did not account for at all.
	const r = run({ edge: 'sleep "$maxtime"; printf \'000\'; exit 28', budget, maxTime, interval: 1 });
	assert.equal(r.status, 1);
	const m = r.out.match(/gave up after (\d+)s and (\d+) attempt\(s\)/);
	assert.ok(m, `no accounted failure line in:\n${r.out}`);
	assert.ok(Number(m[1]) <= budget + 1, `reported ${m[1]}s for a ${budget}s budget`);
	// The old loop ran 45 attempts of (--max-time + sleep) regardless of the
	// stated 90s: at these knobs that is 180s of wall clock, not ~6s.
	assert.ok(r.wallMs < (budget + maxTime) * 1000, `took ${r.wallMs}ms for a ${budget}s budget`);
	const times = attemptsOn(r.calls, '/functions/').map((l) => Number(l.split(' ')[1]));
	assert.ok(times.length >= 2, `expected more than one attempt, got ${times.length}`);
	// The last attempt may not outrun the deadline, so its --max-time is
	// clamped to whatever is left.
	assert.ok(
		times.some((t) => t < maxTime),
		`no attempt was clamped below --max-time ${maxTime}: ${times.join(',')}`
	);
});

test('giving up captures the container list, state and logs', () => {
	const r = run({ edge: "printf '000'; exit 7", budget: 2, maxTime: 1, interval: 1 });
	assert.equal(r.status, 1);
	assert.match(r.out, /--- stack containers ---/);
	assert.match(r.out, /supabase_edge_runtime_run Exited \(1\)/);
	assert.match(r.out, /STUB-INSPECT .*State\.ExitCode/);
	assert.match(r.out, /--- docker logs --tail 5 supabase_edge_runtime \(cid_edge\) ---/);
	assert.match(r.out, /--- docker logs --tail 5 supabase_kong \(cid_kong\) ---/);
	assert.match(r.out, /STUB-LOGS --tail 5/);
});

// The reason this script exists, applied to the probe that runs FIRST. kong
// answers 503 on its own when it cannot reach an upstream — that is the answer
// the loop this replaced read as ready, and nothing asked whether the storage
// probe's own pattern rejects it.
test('kong’s own 503 on the storage path is not storage answering', () => {
	const r = run({
		edge: "printf '405'; exit 0",
		storage: "printf '503'; exit 0",
		budget: 3,
		maxTime: 1,
		interval: 1
	});
	assert.equal(r.status, 1);
	assert.match(r.out, /::error::storage REST never became ready/);
	assert.match(r.out, /last status 503/);
	// And it short-circuits: neither later sidecar is probed, so no "ready"
	// line can appear underneath a failure.
	assert.equal(attemptsOn(r.calls, '/functions/').length, 0);
	assert.equal(attemptsOn(r.calls, '/auth/').length, 0);
	assert.doesNotMatch(r.out, /ready:/);
});

// The other half of the same pattern, stated so a later tightening does not
// silently start waiting on a stack that is already serving: storage's own 4xx
// IS an answer from storage, and the probe deliberately takes it.
test('storage answering with its own 4xx is ready, not a wait', () => {
	const r = run({
		edge: "printf '405'; exit 0",
		storage: "printf '400'; exit 0",
		budget: 3,
		maxTime: 1,
		interval: 1
	});
	assert.equal(r.status, 0);
	assert.match(r.out, /ready: storage REST -> 400/);
});

// The auth probe is a real password grant rather than /health precisely
// because what every suite opens with is minting a token. GoTrue up with the
// seed not yet applied answers 400 — the container is serving, and the thing
// the suites need still does not work.
test('a password grant GoTrue refuses is not auth being ready', () => {
	const r = run({
		edge: "printf '405'; exit 0",
		auth: "printf '400'; exit 0",
		budget: 3,
		maxTime: 1,
		interval: 1
	});
	assert.equal(r.status, 1);
	assert.match(r.out, /::error::auth password grant never became ready/);
	assert.match(r.out, /last status 400/);
	// Its forensics name the auth container, not the edge runtime the
	// previous probe just cleared.
	assert.match(r.out, /docker logs --tail 5 supabase_auth/);
});

// Every probe reaches its own sidecar. A stub that answered 200 to everything
// would pass this suite with the URLs swapped.
test('each probe addresses the sidecar it claims to', () => {
	const r = run({ edge: "printf '405'; exit 0", budget: 8, maxTime: 2, interval: 1 });
	assert.equal(r.status, 0);
	assert.equal(attemptsOn(r.calls, '/storage/v1/bucket').length, 1);
	assert.equal(attemptsOn(r.calls, '/functions/v1/clip-public-track').length, 1);
	assert.equal(attemptsOn(r.calls, '/auth/v1/token?grant_type=password').length, 1);
});

test('an empty ANON_KEY fails before any probe', () => {
	const res = spawnSync('bash', [SCRIPT], {
		encoding: 'utf8',
		env: { ...process.env, ANON_KEY: '' }
	});
	assert.equal(res.status, 1);
	assert.match(res.stdout, /::error::ANON_KEY is empty/);
});

test('the script is valid bash', () => {
	execFileSync('bash', ['-n', SCRIPT]);
});
