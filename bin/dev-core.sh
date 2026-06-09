#!/usr/bin/env bash
# One-shot local-stack bootstrap for the Run app.
#
# Brings up everything a fresh clone needs to test the whole product locally,
# then prints the commands to run the apps. Idempotent — safe to re-run (e.g.
# after replugging a phone, which clears `adb reverse`).
#
#   • Supabase (Postgres + Auth + Storage + Edge runtime) on :54321, seeded
#     with runner@test.com / testtest (+ GPS tracks so runs render on a map)
#   • Protomaps map tiles on :8080
#   • adb reverse for every attached Android device/emulator
#     (54321 Supabase, 54322 Postgres, 7777 web/Coach, 8080 tiles)
#   • Ollama check + optional model pull for the local AI Coach
#
# Then start the apps in their own terminals:
#   npm run dev:run:web        # web on http://localhost:7777
#   npm run dev:run:android    # Flutter app on a device/emulator
#
# Usage: bin/dev-core.sh   (or: npm run dev:core)

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -t 1 ]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; GRN=$'\e[32m'; YEL=$'\e[33m'; RED=$'\e[31m'; RST=$'\e[0m'
else
  BOLD=; DIM=; GRN=; YEL=; RED=; RST=
fi
step() { printf '\n%s▸ %s%s\n' "$BOLD" "$1" "$RST"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$YEL" "$RST" "$1"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }

# ── Supabase ──────────────────────────────────────────────────────────────
step "Supabase (local stack on :54321)"
if ! command -v supabase >/dev/null 2>&1; then
  err "supabase CLI not found — install it (see apps/backend/CLAUDE.md), then re-run."
  exit 1
fi
if ( cd apps/backend && supabase status ) >/dev/null 2>&1; then
  ok "already running"
else
  ( cd apps/backend && supabase start ) >/dev/null
  ok "started"
fi

# ── Seed GPS tracks ───────────────────────────────────────────────────────
# `supabase start` applies migrations + seed.sql on first init; the track
# generator gives seeded runs real GPS traces (same as `npm run dev:db:reset`).
step "Seed data"
if node scripts/seed-run-tracks.mjs >/dev/null 2>&1; then
  ok "seed user runner@test.com / testtest ready (+ run tracks)"
else
  warn "run-track seeding skipped (non-fatal). For a clean reseed: npm run dev:db:reset"
fi

# ── Protomaps map tiles ───────────────────────────────────────────────────
step "Protomaps map tiles (:8080)"
if curl -fs http://localhost:8080/health >/dev/null 2>&1; then
  ok "already running"
elif bin/protomaps-dev.sh start >/dev/null 2>&1; then
  ok "started"
else
  warn "tile server didn't start — run 'npm run dev:tiles:up' to see why (maps fall back to MapTiler if you set a key)"
fi

# ── adb reverse (devices reach the host loopback) ─────────────────────────
step "adb reverse (Android devices → host loopback)"
if command -v adb >/dev/null 2>&1; then
  mapfile -t DEVICES < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
  if [ "${#DEVICES[@]}" -eq 0 ]; then
    warn "no Android device/emulator attached — start one and re-run 'npm run dev:core'"
  else
    for d in "${DEVICES[@]}"; do
      for p in 54321 54322 7777 8080; do adb -s "$d" reverse "tcp:$p" "tcp:$p" >/dev/null; done
      ok "$d → 54321 / 54322 / 7777 / 8080"
    done
  fi
else
  warn "adb not found — install Android platform-tools to run the Flutter app on a device"
fi

# ── Ollama (AI Coach) ─────────────────────────────────────────────────────
step "Ollama (local AI Coach)"
# Effective coach model: a gitignored .env.local override wins over the
# committed .env.development default (same precedence Vite applies).
MODEL="$(grep -hoE '^OPENAI_MODEL=.+' apps/web/.env.local apps/web/.env.development 2>/dev/null | head -1 | cut -d= -f2 || true)"
MODEL="${MODEL:-llama3.2}"
if curl -fs http://localhost:11434/api/tags >/dev/null 2>&1; then
  if curl -fs http://localhost:11434/api/tags | grep -q "\"${MODEL}\""; then
    ok "running; coach model '${MODEL}' present"
  elif [ -t 0 ] && command -v ollama >/dev/null 2>&1; then
    printf '  %s⚠%s coach model %s not pulled. ' "$YEL" "$RST" "$MODEL"
    read -r -p "Pull it now (~2GB)? [Y/n] " ans
    case "${ans:-Y}" in
      [Nn]*) warn "skipped — run 'ollama pull ${MODEL}' before using Coach" ;;
      *)     ollama pull "$MODEL" && ok "pulled '${MODEL}'" ;;
    esac
  else
    warn "running, but coach model '${MODEL}' isn't pulled — run 'ollama pull ${MODEL}'"
  fi
else
  warn "not reachable on :11434 — run 'ollama serve' + 'ollama pull ${MODEL}' to use the AI Coach (everything else works without it)"
fi

# ── Done ──────────────────────────────────────────────────────────────────
# `dev:full` calls this script with DEV_CORE_NO_FOOTER=1 so it can add
# the worker + routing engines and print one combined footer instead of two.
if [ -z "${DEV_CORE_NO_FOOTER:-}" ]; then
  printf '\n%s%sLocal stack ready.%s Start the apps in their own terminals:\n\n' "$BOLD" "$GRN" "$RST"
  printf '  %snpm run dev:run:web%s      %s# web app on http://localhost:7777%s\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '  %snpm run dev:run:android%s  %s# Flutter app on a device/emulator%s\n\n' "$BOLD" "$RST" "$DIM" "$RST"
  printf '  %sseed login: runner@test.com / testtest (mobile auto-logs in)%s\n' "$DIM" "$RST"
  printf '  %sre-run anytime (e.g. after replugging a phone): npm run dev:core%s\n' "$DIM" "$RST"
  printf '  %sfull stack incl. job worker + routing engines: npm run dev:full%s\n' "$DIM" "$RST"
fi
