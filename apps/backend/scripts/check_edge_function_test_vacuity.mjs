#!/usr/bin/env node
// Mutation-check the Edge Function Deno suite: prove each test would notice if
// the thing it claims to test stopped working.
//
// decisions.md 741 asked this of the pgtap suite and 777 of the Playwright
// suite. Both found the same shape - an assertion satisfied by a subject that
// was never reached - and neither could see the other's tier. This is the
// third tier, and it needs a different operator again. Nothing here is hidden
// by access control; what hides a subject in a Deno unit suite is a mock that
// answers before the handler does, an assertion on a value the test itself
// supplied, a promise nobody awaited, or a source-grep guard whose regex
// matches something other than the line it is quoting.
//
// The operator is the bluntest honest one: replace EVERY non-test module under
// supabase/functions with a neutered twin (edge_function_neuter.mjs) - same
// exported names, same runtime shapes, no behaviour and no source text - then
// run the whole suite. A test that still passes did not depend on any module
// in this tree, which is the definition of vacuous for a suite whose entire
// subject is this tree.
//
// Shape preservation is what makes the survivor set honest rather than merely
// small: a stub that threw would score a vacuous test as a kill it did not
// earn, and the vacuous test would stay invisible. See edge_function_neuter.
//
// The mutant is assembled OUTSIDE the repo, as a mirror in which only the
// paths named below are real files and every other entry is a symlink to the
// original. Fourteen test files read a path outside the functions tree, so a
// bare copy of functions/ would fail them all for the wrong reason.
//
// Four of those paths are SUBJECTS rather than fixtures - a guard over
// config.toml's verify_jwt posture is not testing a TypeScript module, and
// neutering the tree leaves it passing while proving nothing. They are
// neutered too (NEUTERED_ARTIFACTS), which is what lets this guard demand
// zero survivors rather than keeping an exemption list.
//
//   --report    print every survivor with the file and line that produced it
//   --json      machine-readable survivor list
//   default     guard: fail on a survivor not argued for in EXPECTED_SURVIVORS

import { spawnSync } from 'node:child_process';
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { neuterModule } from './edge_function_neuter.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const BACKEND_DIR = resolve(HERE, '..');
export const REPO_ROOT = resolve(BACKEND_DIR, '..', '..');
export const FUNCTIONS_REL = 'apps/backend/supabase/functions';

// The non-TypeScript artifacts a test in this suite reads AS ITS SUBJECT, with
// the comment marker to blank them to. A test whose subject is one of these
// would otherwise survive the module mutation for a legitimate reason, and an
// argued exemption is indistinguishable from a genuinely vacuous test.
/** @type {{ path: string, marker: string, reason: string }[]} */
export const NEUTERED_ARTIFACTS = [
  {
    path: 'apps/backend/supabase/config.toml',
    marker: '# neutered',
    reason: "_shared/verify_jwt_config.test.ts asserts the verify_jwt posture of every anon-reachable function",
  },
  {
    path: 'apps/backend/supabase/migrations',
    marker: '-- neutered',
    reason: 'export-data/wiring.test.ts reads the exports-bucket migration for its size limit and its policies',
  },
  {
    path: 'apps/backend/.env.development',
    marker: '# neutered',
    reason: 'strava-import/wiring.test.ts asserts the committed dev allowlist carries the mobile callback',
  },
  {
    path: 'apps/backend/.env.example',
    marker: '# neutered',
    reason: 'the same guard reads it as what an operator copies to configure production',
  },
];

/** Every path the mirror materialises rather than symlinks. */
export const MATERIALISED = [FUNCTIONS_REL, ...NEUTERED_ARTIFACTS.map((a) => a.path)];

// A survivor is a test that passes with every module in the tree neutered.
// That is only ever legitimate when the test's subject is NOT a module in this
// tree - a config file, a migration, a workflow, a sibling app's source - and
// each entry has to say which, because "it reads something else" is also what
// a genuinely vacuous test looks like from here.
/** @type {{ file: string, name: string, reason: string }[]} */
export const EXPECTED_SURVIVORS = [
  {
    file: './supabase/functions/stripe-events-webhook/lib.test.ts',
    name: 'donationStatusTransition — the scope default is full, matching the event ledger',
    reason:
      'It compares two calls of donationStatusTransition to each other and asserts nothing about ' +
      'the shared answer, so a function with no answers at all satisfies it - the same ' +
      'self-comparison shape the ipBucketKey determinism test carried. Asserting the pair equals ' +
      "'refunded' closes it. Filed in docs/product/followups.md rather than fixed here: " +
      'stripe-events-webhook was owned by another change in the same round.',
  },
];

/**
 * @param {string} src
 * @returns {string}
 */
function unescapeXml(src) {
  return src
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/g, '&');
}

/**
 * Every test case in a Deno JUnit report, keyed `file::name`.
 * @param {string} xml
 * @returns {Map<string, { file: string, name: string, line: string, passed: boolean }>}
 */
export function parseJunit(xml) {
  /** @type {Map<string, { file: string, name: string, line: string, passed: boolean }>} */
  const out = new Map();
  const chunks = xml.split('<testcase ').slice(1);
  for (const chunk of chunks) {
    const head = chunk.slice(0, chunk.indexOf('>'));
    const name = unescapeXml(/(?:^|\s)name="([^"]*)"/.exec(head)?.[1] ?? '');
    const file = unescapeXml(/(?:^|\s)classname="([^"]*)"/.exec(head)?.[1] ?? '');
    const line = /(?:^|\s)line="([^"]*)"/.exec(head)?.[1] ?? '';
    const body = chunk.slice(0, chunk.indexOf('</testcase>'));
    // Deno emits <skipped/> for an ignored test; those are neither passes nor
    // failures and must not be scored either way.
    if (body.includes('<skipped')) continue;
    const passed = !body.includes('<failure') && !body.includes('<error');
    out.set(`${file}::${name}`, { file, name, line, passed });
  }
  return out;
}

/**
 * Mirror the repo into `dest` so that every path in MATERIALISED is a real copy
 * and every other entry is a symlink to the original. Only the directories on
 * the way down to a materialised path are created for real.
 * @param {string} dest
 */
export function mirrorRepo(dest) {
  /** @type {Set<string>} */
  const realDirs = new Set(['']);
  /** @type {Set<string>} */
  const copies = new Set(MATERIALISED);
  for (const rel of MATERIALISED) {
    const parts = rel.split('/');
    for (let i = 1; i < parts.length; i++) realDirs.add(parts.slice(0, i).join('/'));
  }
  for (const relDir of [...realDirs].sort()) {
    const realDir = relDir ? join(REPO_ROOT, relDir) : REPO_ROOT;
    const mirrorDir = relDir ? join(dest, relDir) : dest;
    mkdirSync(mirrorDir, { recursive: true });
    for (const entry of readdirSync(realDir, { withFileTypes: true })) {
      const childRel = relDir ? `${relDir}/${entry.name}` : entry.name;
      if (realDirs.has(childRel) || copies.has(childRel)) continue;
      if (entry.name === '.git') continue;
      symlinkSync(join(realDir, entry.name), join(mirrorDir, entry.name));
    }
  }
  for (const rel of MATERIALISED) {
    cpSync(join(REPO_ROOT, rel), join(dest, rel), { recursive: true });
  }
}

/**
 * Every non-test TypeScript module in the functions tree, repo-relative.
 * @returns {string[]}
 */
export function sourceModules() {
  /** @type {string[]} */
  const out = [];
  /** @param {string} dir */
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts') && !entry.name.endsWith('.d.ts')) {
        out.push(relative(REPO_ROOT, full));
      }
    }
  };
  walk(join(REPO_ROOT, FUNCTIONS_REL));
  return out;
}

/**
 * @param {string} dest
 * @param {string[]} modules repo-relative paths to neuter in the mirror
 */
export function applyNeuter(dest, modules) {
  for (const rel of modules) {
    const target = join(dest, rel);
    writeFileSync(target, neuterModule(readFileSync(join(REPO_ROOT, rel), 'utf8'), rel));
  }
  for (const { path, marker } of NEUTERED_ARTIFACTS) {
    const target = join(dest, path);
    if (statSync(target).isDirectory()) {
      for (const entry of readdirSync(target, { withFileTypes: true })) {
        if (entry.isFile()) writeFileSync(join(target, entry.name), `${marker}\n`);
      }
    } else {
      writeFileSync(target, `${marker}\n`);
    }
  }
}

/**
 * @param {string} root mirror root
 * @param {string} junitPath
 * @returns {Map<string, { file: string, name: string, line: string, passed: boolean }>}
 */
function runSuite(root, junitPath) {
  const res = spawnSync(
    'deno',
    [
      'test',
      '--no-check',
      '--allow-read',
      '--allow-env',
      `--junit-path=${junitPath}`,
      'supabase/functions/',
    ],
    { cwd: join(root, 'apps', 'backend'), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  );
  let xml = '';
  try {
    xml = readFileSync(junitPath, 'utf8');
  } catch {
    throw new Error(
      `deno test produced no JUnit report in ${root}.\nstdout:\n${res.stdout}\nstderr:\n${res.stderr}`,
    );
  }
  return parseJunit(xml);
}

function main() {
  const argv = process.argv.slice(2);
  const workdir = mkdtempSync(join(tmpdir(), 'edge-vacuity-'));
  try {
    const baseRoot = join(workdir, 'base');
    const mutRoot = join(workdir, 'mut');
    mirrorRepo(baseRoot);
    mirrorRepo(mutRoot);
    const modules = sourceModules();
    applyNeuter(mutRoot, modules);

    const baseline = runSuite(baseRoot, join(workdir, 'base.xml'));
    const mutant = runSuite(mutRoot, join(workdir, 'mut.xml'));

    const basePassing = [...baseline.values()].filter((t) => t.passed);
    if (basePassing.length !== baseline.size) {
      const red = [...baseline.values()].filter((t) => !t.passed);
      console.error(
        `::error::The Edge Function suite is not green before the mutation (${red.length} failing). ` +
          `Vacuity cannot be measured against a red baseline. First failure: ${red[0]?.file} :: ${red[0]?.name}`,
      );
      process.exit(1);
    }

    // A test case that is absent from the mutant report did not run: the
    // mutation broke its module load rather than its answer, so nothing was
    // measured about it and scoring it as a kill would make this guard pass
    // for the reason it exists to detect (decisions § 741's inversion, one
    // tier out). That is what the neuterer's shape preservation buys, so a
    // vanished case means the shape preservation has slipped.
    const vanished = [...baseline.keys()].filter((k) => !mutant.has(k));
    if (vanished.length) {
      console.error(
        `::error::${vanished.length} test cases ran in the baseline and not in the mutant, so they were ` +
          'not measured at all. The neutered twin of a module they import no longer loads - check that ' +
          'edge_function_neuter.mjs still emits every exported name with its original shape. First: ' +
          vanished[0],
      );
      process.exit(1);
    }

    /** @type {{ file: string, name: string, line: string }[]} */
    const survivors = [];
    for (const [key, base] of baseline) {
      const after = mutant.get(key);
      if (base.passed && after?.passed) survivors.push({ file: base.file, name: base.name, line: base.line });
    }
    survivors.sort((a, b) => (a.file + a.name).localeCompare(b.file + b.name));

    if (argv.includes('--json')) {
      console.log(JSON.stringify({ population: baseline.size, survivors }, null, 2));
      return;
    }

    const killed = baseline.size - survivors.length;
    console.log(
      `${baseline.size} Edge Function test cases mutation-checked against a fully neutered backend ` +
        `(${modules.length} modules + ${NEUTERED_ARTIFACTS.length} artifacts, ` +
        `${killed} killed, ${survivors.length} survived).`,
    );

    if (argv.includes('--report')) {
      /** @type {Map<string, typeof survivors>} */
      const byFile = new Map();
      for (const s of survivors) {
        if (!byFile.has(s.file)) byFile.set(s.file, []);
        byFile.get(s.file)?.push(s);
      }
      for (const [file, entries] of [...byFile].sort()) {
        console.log(`\n${file}  (${entries.length})`);
        for (const e of entries) console.log(`  :${e.line}  ${e.name}`);
      }
      return;
    }

    const expected = new Set(EXPECTED_SURVIVORS.map((e) => `${e.file}::${e.name}`));
    const unexplained = survivors.filter((s) => !expected.has(`${s.file}::${s.name}`));
    const stale = EXPECTED_SURVIVORS.filter(
      (e) => !survivors.some((s) => s.file === e.file && s.name === e.name),
    );
    for (const e of EXPECTED_SURVIVORS) {
      if (!e.reason.trim()) {
        console.error(`::error::EXPECTED_SURVIVORS entry ${e.file} :: ${e.name} carries no reason.`);
        process.exit(1);
      }
    }
    for (const e of stale) {
      console.error(
        `::error::EXPECTED_SURVIVORS entry ${e.file} :: "${e.name}" no longer matches a surviving test. ` +
          'It was renamed, deleted, or now dies under the mutation: remove the entry rather than leaving it ' +
          'to excuse something that no longer exists.',
      );
    }
    for (const s of unexplained) {
      console.error(
        `::error::${s.file}:${s.line} :: "${s.name}" still passes with every Edge Function module neutered, ` +
          'so it is not testing any of them.',
      );
    }
    if (unexplained.length || stale.length) process.exit(1);
    console.log('No unexplained survivors.');
  } finally {
    rmSync(workdir, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) main();
