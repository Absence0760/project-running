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

/**
 * The two halves of `deno.lock` this script tells apart. `dependencies` is an
 * array of npm specs — deno's transcription of a package.json mapping, not the
 * mapping itself.
 *
 * @typedef {{ dependencies?: string[], overrides?: Record<string, string> }} LockPackageJson
 * @typedef {{ packageJson?: LockPackageJson, members?: Record<string, { packageJson?: LockPackageJson }> }} WorkspaceSection
 * @typedef {{ version?: unknown, redirects?: unknown, remote?: unknown, workspace?: WorkspaceSection }} DenoLock
 * @typedef {{ scope: string, spec: string }} ScopedSpec
 * @typedef {{ changed: { scope: string, from: string, to: string }[], added: ScopedSpec[], removed: ScopedSpec[], overridesMoved: boolean, inSync: boolean }} WorkspaceDiff
 */

export const PROBE = 'probe.ts';
const GENERATED_SECTION = 'workspace';
/** @type {readonly ('version' | 'redirects' | 'remote')[]} */
const PINNED_SECTIONS = ['version', 'redirects', 'remote'];
// Neither a workspace member path nor an npm spec can contain it.
const KEY_SEP = '::';

/**
 * @param {{ workspaces?: unknown } | null | undefined} rootPkg
 * @returns {string[]}
 */
export function workspaceMemberPaths(rootPkg) {
  const declared = rootPkg?.workspaces;
  if (!Array.isArray(declared)) return [];
  /** @type {string[]} */
  const members = [];
  for (const m of declared) {
    if (typeof m === 'string' && m.length > 0 && !m.includes('*')) members.push(m);
  }
  return members;
}

/**
 * @param {WorkspaceSection | undefined} section
 * @returns {Map<string, ScopedSpec>}
 */
export function specsOf(section) {
  /** @type {Map<string, ScopedSpec>} */
  const out = new Map();
  /**
   * @param {string} scope
   * @param {LockPackageJson | undefined} pkgJson
   */
  const record = (scope, pkgJson) => {
    for (const spec of pkgJson?.dependencies ?? []) out.set(`${scope}${KEY_SEP}${spec}`, { scope, spec });
  };
  record('.', section?.packageJson);
  for (const [member, body] of Object.entries(section?.members ?? {})) record(member, body?.packageJson);
  return out;
}

// A spec's identity is its package name, so a version move reads as one
// changed line rather than an unrelated removal and addition.
/** @param {string} spec */
function nameOf(spec) {
  const at = spec.lastIndexOf('@');
  return at > 'npm:'.length ? spec.slice(0, at) : spec;
}

/**
 * @param {WorkspaceSection | undefined} before
 * @param {WorkspaceSection | undefined} after
 * @returns {WorkspaceDiff}
 */
export function diffWorkspaceSections(before, after) {
  const beforeSpecs = specsOf(before);
  const afterSpecs = specsOf(after);
  /** @param {Map<string, ScopedSpec>} specs */
  const byName = (specs) => {
    /** @type {Map<string, string>} */
    const m = new Map();
    for (const { scope, spec } of specs.values()) m.set(`${scope}${KEY_SEP}${nameOf(spec)}`, spec);
    return m;
  };
  const b = byName(beforeSpecs);
  const a = byName(afterSpecs);
  /** @type {WorkspaceDiff['changed']} */
  const changed = [];
  /** @type {ScopedSpec[]} */
  const added = [];
  /** @type {ScopedSpec[]} */
  const removed = [];
  for (const [key, spec] of a) {
    const [scope] = key.split(KEY_SEP);
    const was = b.get(key);
    if (was === undefined) added.push({ scope, spec });
    else if (was !== spec) changed.push({ scope, from: was, to: spec });
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

/**
 * @param {WorkspaceDiff} diff
 * @returns {string}
 */
export function formatDrift(diff) {
  const lines = [];
  /** @param {string} scope */
  const where = (scope) => (scope === '.' ? '' : ` (${scope})`);
  for (const c of diff.changed) lines.push(`  - ${c.from}${where(c.scope)}\n  + ${c.to}${where(c.scope)}`);
  for (const a of diff.added) lines.push(`  + ${a.spec}${where(a.scope)}`);
  for (const r of diff.removed) lines.push(`  - ${r.spec}${where(r.scope)}`);
  if (diff.overridesMoved) lines.push('  ! root package.json "overrides" changed');
  return lines.join('\n');
}

/**
 * @param {DenoLock | undefined} before
 * @param {DenoLock | undefined} after
 * @returns {boolean}
 */
export function pinnedSectionsMatch(before, after) {
  return PINNED_SECTIONS.every((k) => JSON.stringify(before?.[k] ?? null) === JSON.stringify(after?.[k] ?? null));
}

// Copy the workspace's package.json files and the lock into a scratch tree, so
// the deno run cannot touch the real checkout (several sessions share it).
/**
 * @param {string} rootDir
 * @param {string} lockText
 * @param {string} destDir
 * @returns {string[]} The workspace-relative package.json paths staged.
 */
export function stageWorkspace(rootDir, lockText, destDir) {
  const rootPkgPath = path.join(rootDir, 'package.json');
  /** @type {{ workspaces?: unknown }} */
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

// `spawnSync` reports a failure to START the process as an `error` carrying an
// errno `code`, which its declared `Error` type does not admit. Every such
// failure also leaves `status` and `stderr` null, so an unrecognised one read
// as `deno exited null: ` and named nothing.
/** @param {unknown} value */
function errnoCode(value) {
  if (typeof value !== 'object' || value === null || !('code' in value)) return null;
  const { code } = value;
  return typeof code === 'string' ? code : null;
}

/**
 * @param {string} rootDir
 * @param {string} lockText
 * @returns {string} The regenerated lockfile text.
 */
export function regenerate(rootDir, lockText) {
  const destDir = fs.mkdtempSync(path.join(os.tmpdir(), 'deno-lock-sync-'));
  try {
    stageWorkspace(rootDir, lockText, destDir);
    const run = spawnSync('deno', ['check', '--no-remote', '--node-modules-dir=none', PROBE], {
      cwd: destDir,
      encoding: 'utf8',
    });
    if (errnoCode(run.error) === 'ENOENT') {
      throw new Error('deno is not installed — it is the only thing that can write this section');
    }
    if (run.error) {
      throw new Error(`could not run deno (${errnoCode(run.error) ?? 'spawn failed'}): ${run.error.message}`);
    }
    if (run.status !== 0) {
      throw new Error(`deno exited ${run.status}: ${(run.stderr || run.stdout || '').trim()}`);
    }
    return fs.readFileSync(path.join(destDir, 'deno.lock'), 'utf8');
  } finally {
    fs.rmSync(destDir, { recursive: true, force: true });
  }
}

/// The whole verdict as data, so each of its refusals can be asserted on
/// without a deno run or a checkout — `write` says whether the regenerated
/// text should replace the lock.
/**
 * @param {DenoLock} before
 * @param {DenoLock} after
 * @param {boolean} check
 * @returns {{ code: number, write: boolean, out: string[], err: string[] }}
 */
export function verdict(before, after, check) {
  if (!pinnedSectionsMatch(before, after)) {
    return {
      code: 1,
      write: false,
      out: [],
      err: [
        `deno.lock: refusing to write — the regeneration moved ${PINNED_SECTIONS.join('/')}, which only\n` +
          'the Supabase CLI (`supabase db reset` / `functions serve`) should touch. Inspect by hand.',
      ],
    };
  }

  const diff = diffWorkspaceSections(before[GENERATED_SECTION], after[GENERATED_SECTION]);
  const specCount = specsOf(after[GENERATED_SECTION]).size;
  // The floor under the comparison itself. Two empty sections read as in sync,
  // so a regeneration that stops recording specs at all would be written once
  // and then agree with itself forever, reporting a lock nothing checks as
  // clean. `pinnedSectionsMatch` refuses for the other half of the file.
  if (specCount === 0) {
    return {
      code: 1,
      write: false,
      out: [],
      err: [
        `deno.lock: refusing to write — the regeneration produced no \`${GENERATED_SECTION}\` specs at ` +
          'all, so this check compared nothing against nothing. Either the npm workspace stopped ' +
          'declaring dependencies, or deno stopped recording them and this script now enforces nothing.',
      ],
    };
  }
  if (diff.inSync) {
    return {
      code: 0,
      write: false,
      out: [`deno.lock workspace section is in sync with package.json (${specCount} specs).`],
      err: [],
    };
  }
  if (check) {
    return {
      code: 1,
      write: false,
      out: [],
      err: [
        "deno.lock's workspace section has drifted from package.json:",
        formatDrift(diff),
        '\nrun `pnpm sync:deno-lock` and commit the result.',
      ],
    };
  }
  return {
    code: 0,
    write: true,
    out: [`deno.lock workspace section synced (${specCount} specs):`, formatDrift(diff)],
    err: [],
  };
}

/** @param {readonly string[]} argv */
function main(argv) {
  const check = argv.includes('--check');
  const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const lockPath = path.join(rootDir, 'deno.lock');
  const lockText = fs.readFileSync(lockPath, 'utf8');
  const regenerated = regenerate(rootDir, lockText);

  /** @type {DenoLock} */
  const before = JSON.parse(lockText);
  /** @type {DenoLock} */
  const after = JSON.parse(regenerated);
  const { code, write, out, err } = verdict(before, after, check);
  if (write) fs.writeFileSync(lockPath, regenerated);
  for (const line of out) console.log(line);
  for (const line of err) console.error(line);
  return code;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (err) {
    console.error(`deno.lock sync failed: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
