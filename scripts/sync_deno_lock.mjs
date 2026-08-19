#!/usr/bin/env node
// deno.lock's `workspace` section is generated from the npm workspace's
// package.json files. Sync it (default) or fail on drift (`--check`).
//
// Two halves of that lockfile, with very different standing:
//
//   remote + redirects — 299 esm.sh integrity pins. This is the load-bearing
//     half: the Edge Function tests resolve against it, and it is written by
//     the Supabase CLI inside its Docker container during `supabase db reset`
//     / `functions serve` (apps/backend/CLAUDE.md).
//   workspace — a transcription of every package.json dependency spec in the
//     npm workspace. Nothing resolves against it. It exists only because the
//     lockfile happens to sit at the root of an npm workspace, so deno records
//     what it saw.
//
// The second half therefore drifts on every web dependency bump, and nothing
// noticed: five hand-written "sync deno.lock" commits between 2026-04 and
// 2026-08, each one a session re-deriving the same chore, plus a stale
// half-synced lockfile left sitting in the shared working tree in between.
// The visible cost is small (the DENO_DIR cache key in the edge-functions job
// keys off `hashFiles('deno.lock')`, so a stale lock caches under the wrong
// key while an unrelated web bump needlessly busts it) but the rediscovery
// cost is not.
//
// Deno writes the section, not this script. The ranges are canonicalized on
// the way in — `^0.46.0` reads back as `0.46`, `^0.45.8` as `~0.45.8`, both
// only for 0.x — so hand-transcribing package.json produces a file deno
// immediately rewrites. Regeneration runs deno against a temp copy holding
// nothing but the package.json files and the lock, with `--no-remote` and
// `--node-modules-dir=none`: no network, no node_modules, no Docker, and
// nothing for deno to resolve except the workspace config.
//
// Fail-closed on the load-bearing half: if a run comes back with a changed
// `remote`/`redirects`, this refuses to write rather than quietly moving a
// supply-chain pin, which is not this script's business to touch.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const PROBE = 'probe.ts';
const GENERATED_SECTION = 'workspace';
const PINNED_SECTIONS = ['version', 'redirects', 'remote'];
// Neither a workspace member path nor an npm spec can contain it.
const KEY_SEP = '::';

export function workspaceMemberPaths(rootPkg) {
  const declared = rootPkg?.workspaces;
  if (!Array.isArray(declared)) return [];
  return declared.filter((m) => typeof m === 'string' && m.length > 0 && !m.includes('*'));
}

export function specsOf(section) {
  const out = new Map();
  const record = (scope, pkgJson) => {
    for (const spec of pkgJson?.dependencies ?? []) out.set(`${scope}${KEY_SEP}${spec}`, { scope, spec });
  };
  record('.', section?.packageJson);
  for (const [member, body] of Object.entries(section?.members ?? {})) record(member, body?.packageJson);
  return out;
}

// A spec's identity is its package name, so a version move reads as one
// changed line rather than an unrelated removal and addition.
function nameOf(spec) {
  const at = spec.lastIndexOf('@');
  return at > 'npm:'.length ? spec.slice(0, at) : spec;
}

export function diffWorkspaceSections(before, after) {
  const beforeSpecs = specsOf(before);
  const afterSpecs = specsOf(after);
  const byName = (specs) => {
    const m = new Map();
    for (const { scope, spec } of specs.values()) m.set(`${scope}${KEY_SEP}${nameOf(spec)}`, spec);
    return m;
  };
  const b = byName(beforeSpecs);
  const a = byName(afterSpecs);
  const changed = [];
  const added = [];
  const removed = [];
  for (const [key, spec] of a) {
    const [scope] = key.split(KEY_SEP);
    if (!b.has(key)) added.push({ scope, spec });
    else if (b.get(key) !== spec) changed.push({ scope, from: b.get(key), to: spec });
  }
  for (const [key, spec] of b) if (!a.has(key)) removed.push({ scope: key.split(KEY_SEP)[0], spec });
  const overridesMoved =
    JSON.stringify(before?.packageJson?.overrides ?? null) !==
    JSON.stringify(after?.packageJson?.overrides ?? null);
  return {
    changed,
    added,
    removed,
    overridesMoved,
    inSync: !changed.length && !added.length && !removed.length && !overridesMoved,
  };
}

export function formatDrift(diff) {
  const lines = [];
  const where = (scope) => (scope === '.' ? '' : ` (${scope})`);
  for (const c of diff.changed) lines.push(`  - ${c.from}${where(c.scope)}\n  + ${c.to}${where(c.scope)}`);
  for (const a of diff.added) lines.push(`  + ${a.spec}${where(a.scope)}`);
  for (const r of diff.removed) lines.push(`  - ${r.spec}${where(r.scope)}`);
  if (diff.overridesMoved) lines.push('  ! root package.json "overrides" changed');
  return lines.join('\n');
}

export function pinnedSectionsMatch(before, after) {
  return PINNED_SECTIONS.every((k) => JSON.stringify(before?.[k] ?? null) === JSON.stringify(after?.[k] ?? null));
}

// Copy the workspace's package.json files and the lock into a scratch tree, so
// the deno run cannot touch the real checkout (several sessions share it).
export function stageWorkspace(rootDir, lockText, destDir) {
  const rootPkgPath = path.join(rootDir, 'package.json');
  const rootPkg = JSON.parse(fs.readFileSync(rootPkgPath, 'utf8'));
  fs.writeFileSync(path.join(destDir, 'package.json'), fs.readFileSync(rootPkgPath));
  const staged = ['package.json'];
  for (const member of workspaceMemberPaths(rootPkg)) {
    const src = path.join(rootDir, member, 'package.json');
    if (!fs.existsSync(src)) continue;
    fs.mkdirSync(path.join(destDir, member), { recursive: true });
    fs.writeFileSync(path.join(destDir, member, 'package.json'), fs.readFileSync(src));
    staged.push(`${member}/package.json`);
  }
  fs.writeFileSync(path.join(destDir, 'deno.lock'), lockText);
  fs.writeFileSync(path.join(destDir, PROBE), 'export const probe = 1;\n');
  return staged;
}

export function regenerate(rootDir, lockText) {
  const destDir = fs.mkdtempSync(path.join(os.tmpdir(), 'deno-lock-sync-'));
  try {
    stageWorkspace(rootDir, lockText, destDir);
    const run = spawnSync('deno', ['check', '--no-remote', '--node-modules-dir=none', PROBE], {
      cwd: destDir,
      encoding: 'utf8',
    });
    if (run.error?.code === 'ENOENT') {
      throw new Error('deno is not installed — it is the only thing that can write this section');
    }
    if (run.status !== 0) {
      throw new Error(`deno exited ${run.status}: ${(run.stderr || run.stdout || '').trim()}`);
    }
    return fs.readFileSync(path.join(destDir, 'deno.lock'), 'utf8');
  } finally {
    fs.rmSync(destDir, { recursive: true, force: true });
  }
}

function main(argv) {
  const check = argv.includes('--check');
  const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const lockPath = path.join(rootDir, 'deno.lock');
  const lockText = fs.readFileSync(lockPath, 'utf8');
  const regenerated = regenerate(rootDir, lockText);

  const before = JSON.parse(lockText);
  const after = JSON.parse(regenerated);
  if (!pinnedSectionsMatch(before, after)) {
    console.error(
      `deno.lock: refusing to write — the regeneration moved ${PINNED_SECTIONS.join('/')}, which only\n` +
        'the Supabase CLI (`supabase db reset` / `functions serve`) should touch. Inspect by hand.',
    );
    return 1;
  }

  const diff = diffWorkspaceSections(before[GENERATED_SECTION], after[GENERATED_SECTION]);
  const specCount = specsOf(after[GENERATED_SECTION]).size;
  if (diff.inSync) {
    console.log(`deno.lock workspace section is in sync with package.json (${specCount} specs).`);
    return 0;
  }
  if (check) {
    console.error("deno.lock's workspace section has drifted from package.json:");
    console.error(formatDrift(diff));
    console.error('\nrun `pnpm sync:deno-lock` and commit the result.');
    return 1;
  }
  fs.writeFileSync(lockPath, regenerated);
  console.log(`deno.lock workspace section synced (${specCount} specs):`);
  console.log(formatDrift(diff));
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (err) {
    console.error(`deno.lock sync failed: ${err.message}`);
    process.exit(1);
  }
}
