#!/usr/bin/env bash
#
# Wait until the local Supabase stack's sidecars actually serve, and leave
# the evidence behind when one of them never does.
#
# `supabase start` returns before its sidecars can serve. This wait used to
# be three byte-identical copies inline in ci.yml (e2e-web, the OAuth lane,
# the SSO lane) and every one of them was vacuous: they polled with
# `-X POST` and treated ANY status other than curl's `000` as ready, on the
# stated theory that "kong routed + the upstream answered". kong answers on
# its own when it CANNOT reach an upstream — 503 `{"message":"name
# resolution failed"}` with the edge runtime down, 503 `{"code":"BOOT_ERROR"}`
# while a worker is failing to boot — and the function it probed
# (refresh-tokens) returns 503 `cron_not_configured` in CI anyway, so the two
# were indistinguishable. The loop therefore passed on its first poll against
# a stack that was still cold, which is how CI run 31361094964 (e2e shard 4)
# spent its first 2.5 minutes timing out every delete-account-guards request
# at 30s and then ran green for the rest of the shard. The same comment
# already blamed an earlier instance of that exact failure (run 26478978751,
# same spec, same shard).
#
# So each probe below names the answer that only the upstream itself can give:
#   - the edge runtime by clip-public-track's own 405 (verify_jwt is false, so
#     a GET reaches the handler; the 405 is pinned by
#     clip-public-track-guards.spec.ts),
#   - GoTrue by a real password grant rather than /health, because what the
#     suites open with is minting a token, and
#   - Storage REST by any answer of its own.
#
# The budget is a WALL-CLOCK deadline, not an attempt count. It used to be
# `for i in $(seq 1 45)` with `sleep 2` and an error string that claimed
# "within 90s": that arithmetic charges the sleeps and nothing else, so an
# attempt that spends curl's whole `--max-time` is free. Two 2026-08-14 jobs
# died here with `edge runtime (clip-public-track) never became ready within
# 90s` after ~45 attempts spanning ~9 minutes — 45 x (10s --max-time + 2s
# sleep) = 540s, i.e. the loop, not the message, was telling the truth about
# the wait and the message was understating it 6x. Every attempt is now
# charged against the deadline and the last attempt's `--max-time` is clamped
# to what is left of it, so the failure costs what it says it costs. The
# budget itself is deliberately NOT widened: a run that answers within 10s
# (kong's 503 while the runtime is booting) still gets the same ~45 tries it
# always did, and a run where every attempt burns the full --max-time is a
# stack that is not coming up at all.
#
# 90s is kept because it was MEASURED against green runs, not inherited.
# Across 277 jobs carrying this step in 14 workflow runs (2026-08-13 to
# 2026-08-19 — every stack-using job: 14 e2e shards, the SSO/OAuth and
# live-hub lanes, pgtap, edge-functions, api_client, cross-client, schema
# drift), the 275 green ones took a median of 1.21s and a maximum of 12.15s,
# 274 of them finished under 2s, and exactly ONE needed a retry at all (one
# attempt, e2e shard 10/14 in run 32150279557). So the worst healthy boot on
# record uses 13% of the deadline. Converting an attempt count into a real
# deadline does tighten the effective ceiling from ~540s to 90s; the tightening
# is only ever spent by the failure mode it is meant to bound, because an
# attempt that fails costs the whole 10s --max-time when it fails at all
# (measured: attempts 2-45 of run 31834502152 are 12.013s apart to the
# millisecond), and 90s still affords 8 such attempts against the 1 observed.
set -uo pipefail

if [ -z "${ANON_KEY:-}" ]; then
  echo "::error::ANON_KEY is empty — could not read it from supabase status"
  exit 1
fi

BUDGET_S=${PROBE_BUDGET_S:-90}
MAX_TIME_S=${PROBE_MAX_TIME_S:-10}
INTERVAL_S=${PROBE_INTERVAL_S:-2}
LOG_TAIL=${PROBE_LOG_TAIL:-200}
API=${PROBE_API_URL:-http://127.0.0.1:54321}

# A probe that gives up has to answer "why did this container never serve",
# and the wait loop's own output cannot: it only ever saw kong's side of the
# conversation. The 2026-08-14 failures left nothing else in the run log, so
# neither one is diagnosable after the fact.
dump_sidecar_forensics() {
  local hint=$1 cid name
  echo "--- stack containers ---"
  docker ps -a --filter 'name=supabase_' --format '{{.Names}} {{.Status}} {{.Ports}}' 2>&1 || true
  echo "--- container state ---"
  for cid in $(docker ps -aq --filter 'name=supabase_' 2>/dev/null); do
    docker inspect -f '{{.Name}} status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}} error={{.State.Error}}' "$cid" 2>&1 || true
  done
  # The failing sidecar and kong: the request path has two ends and either
  # can be the one that never came up.
  for name in "$hint" kong; do
    for cid in $(docker ps -aq --filter "name=supabase_${name}" 2>/dev/null); do
      echo "--- docker logs --tail ${LOG_TAIL} supabase_${name} (${cid}) ---"
      docker logs --tail "$LOG_TAIL" "$cid" 2>&1 || true
    done
  done
}

# <label> <ready-status-regex> <container-name-substring> <curl args...>
probe() {
  local label=$1 want=$2 hint=$3
  shift 3
  local start attempts=0 code='' elapsed=0 remaining max_time
  start=$(date +%s)
  while :; do
    elapsed=$(( $(date +%s) - start ))
    remaining=$(( BUDGET_S - elapsed ))
    [ "$remaining" -le 0 ] && break
    max_time=$MAX_TIME_S
    [ "$max_time" -gt "$remaining" ] && max_time=$remaining
    attempts=$(( attempts + 1 ))
    # No `|| echo 000` fallback: curl writes `000` itself when it has no
    # status to report, so the fallback appended a SECOND one — which is
    # where `(last status 000000)` in the incident log came from.
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$max_time" "$@")
    [ -n "$code" ] || code=000
    elapsed=$(( $(date +%s) - start ))
    if printf '%s' "$code" | grep -qE "$want"; then
      echo "ready: $label -> $code after ${elapsed}s (${attempts} attempt(s))"
      return 0
    fi
    echo "wait: $label -> $code (attempt ${attempts}, ${elapsed}s of ${BUDGET_S}s)"
    [ $(( elapsed + INTERVAL_S )) -ge "$BUDGET_S" ] && break
    sleep "$INTERVAL_S"
  done
  elapsed=$(( $(date +%s) - start ))
  echo "::error::${label} never became ready — gave up after ${elapsed}s and ${attempts} attempt(s) (budget ${BUDGET_S}s, last status ${code})"
  dump_sidecar_forensics "$hint"
  return 1
}

probe "storage REST" '^[234][0-9][0-9]$' storage \
  -X POST "${API}/storage/v1/bucket" \
  -H "apikey: $ANON_KEY" -H "authorization: Bearer $ANON_KEY" || exit 1

probe "edge runtime (clip-public-track)" '^405$' edge_runtime \
  -X GET "${API}/functions/v1/clip-public-track" \
  -H "apikey: $ANON_KEY" || exit 1

probe "auth password grant" '^200$' auth \
  -X POST "${API}/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H 'content-type: application/json' \
  -d '{"email":"runner@test.com","password":"testtest"}' || exit 1
