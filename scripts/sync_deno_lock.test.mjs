import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  PROBE,
  diffWorkspaceSections,
  formatDrift,
  pinnedSectionsMatch,
  regenerate,
  specsOf,
  stageWorkspace,
  workspaceMemberPaths,
} from './sync_deno_lock.mjs';

const denoAvailable = spawnSync('deno', ['--version'], { encoding: 'utf8' }).status === 0;

function section({ root = [], overrides, members = {} } = {}) {
  const s = { packageJson: { dependencies: root } };
  if (overrides) s.packageJson.overrides = overrides;
  if (Object.keys(members).length) {
    s.members = Object.fromEntries(
      Object.entries(members).map(([m, deps]) => [m, { packageJson: { dependencies: deps } }]),
    );
  }
  return s;
}

test('workspaceMemberPaths reads the declared members', () => {
  assert.deepEqual(workspaceMemberPaths({ workspaces: ['apps/web', 'apps/backend'] }), ['apps/web', 'apps/backend']);
});

test('workspaceMemberPaths tolerates a package.json with no workspaces', () => {
  assert.deepEqual(workspaceMemberPaths({}), []);
  assert.deepEqual(workspaceMemberPaths(null), []);
  assert.deepEqual(workspaceMemberPaths({ workspaces: { packages: ['a'] } }), []);
});

test('workspaceMemberPaths drops globs it cannot resolve to one package.json', () => {
  assert.deepEqual(workspaceMemberPaths({ workspaces: ['apps/web', 'packages/*'] }), ['apps/web']);
});

test('specsOf flattens the root and every member, keeping each spec\'s scope', () => {
  const specs = specsOf(section({ root: ['npm:svelte@5.56.9'], members: { 'apps/web': ['npm:vite@8.2.1'] } }));
  assert.deepEqual([...specs.values()], [
    { scope: '.', spec: 'npm:svelte@5.56.9' },
    { scope: 'apps/web', spec: 'npm:vite@8.2.1' },
  ]);
});

test('an unchanged section is in sync', () => {
  const s = section({ root: ['npm:svelte@5.56.9'], members: { 'apps/web': ['npm:vite@8.2.1'] } });
  assert.equal(diffWorkspaceSections(s, s).inSync, true);
});

// The whole point of the report: a bump is ONE line pair, so the reader sees a
// version move rather than an unrelated package appearing and another leaving.
test('a version bump reads as one changed spec, not an add plus a remove', () => {
  const diff = diffWorkspaceSections(section({ root: ['npm:svelte@5.56.7'] }), section({ root: ['npm:svelte@5.56.9'] }));
  assert.equal(diff.inSync, false);
  assert.deepEqual(diff.changed, [{ scope: '.', from: 'npm:svelte@5.56.7', to: 'npm:svelte@5.56.9' }]);
  assert.deepEqual(diff.added, []);
  assert.deepEqual(diff.removed, []);
});

test('a scoped package name keeps its slash and scope through the diff', () => {
  const diff = diffWorkspaceSections(
    section({ members: { 'apps/web': ['npm:@sveltejs/kit@2.70.1'] } }),
    section({ members: { 'apps/web': ['npm:@sveltejs/kit@2.70.2'] } }),
  );
  assert.deepEqual(diff.changed, [
    { scope: 'apps/web', from: 'npm:@sveltejs/kit@2.70.1', to: 'npm:@sveltejs/kit@2.70.2' },
  ]);
});

test('a new dependency is an addition and a dropped one a removal', () => {
  const diff = diffWorkspaceSections(
    section({ members: { 'apps/web': ['npm:jszip@^3.10.1'] } }),
    section({ members: { 'apps/web': ['npm:@types/geojson@^7946.0.16'] } }),
  );
  assert.deepEqual(diff.added, [{ scope: 'apps/web', spec: 'npm:@types/geojson@^7946.0.16' }]);
  assert.deepEqual(diff.removed, [{ scope: 'apps/web', spec: 'npm:jszip@^3.10.1' }]);
});

test('the same package moving in a member is not confused with the root copy', () => {
  const before = section({ root: ['npm:svelte@5.56.7'], members: { 'apps/web': ['npm:svelte@5.56.7'] } });
  const after = section({ root: ['npm:svelte@5.56.7'], members: { 'apps/web': ['npm:svelte@5.56.9'] } });
  const diff = diffWorkspaceSections(before, after);
  assert.deepEqual(diff.changed, [{ scope: 'apps/web', from: 'npm:svelte@5.56.7', to: 'npm:svelte@5.56.9' }]);
});

test('an overrides change alone is drift', () => {
  const diff = diffWorkspaceSections(
    section({ root: ['npm:svelte@5.56.9'], overrides: { cookie: '^1.0.2' } }),
    section({ root: ['npm:svelte@5.56.9'], overrides: { cookie: '^1.0.2', 'brace-expansion': '^5.0.8' } }),
  );
  assert.equal(diff.inSync, false);
  assert.equal(diff.overridesMoved, true);
});

test('formatDrift shows a bump as a minus/plus pair and names the member', () => {
  const diff = diffWorkspaceSections(
    section({ members: { 'apps/web': ['npm:vite@8.1.5'] } }),
    section({ members: { 'apps/web': ['npm:vite@8.2.1'] } }),
  );
  assert.equal(formatDrift(diff), '  - npm:vite@8.1.5 (apps/web)\n  + npm:vite@8.2.1 (apps/web)');
});

test('pinnedSectionsMatch guards version, redirects and remote', () => {
  const base = { version: '5', redirects: { a: 'b' }, remote: { 'https://esm.sh/x': 'sha' } };
  assert.equal(pinnedSectionsMatch(base, { ...base }), true);
  assert.equal(pinnedSectionsMatch(base, { ...base, version: '6' }), false);
  assert.equal(pinnedSectionsMatch(base, { ...base, redirects: {} }), false);
  assert.equal(pinnedSectionsMatch(base, { ...base, remote: { 'https://esm.sh/x': 'other' } }), false);
});

test('stageWorkspace copies the lock, a probe and every member that has a package.json', () => {
  const src = fs.mkdtempSync(path.join(os.tmpdir(), 'stage-src-'));
  const dest = fs.mkdtempSync(path.join(os.tmpdir(), 'stage-dest-'));
  try {
    fs.writeFileSync(
      path.join(src, 'package.json'),
      JSON.stringify({ workspaces: ['apps/web', 'apps/absent'], dependencies: { svelte: '5.56.9' } }),
    );
    fs.mkdirSync(path.join(src, 'apps/web'), { recursive: true });
    fs.writeFileSync(path.join(src, 'apps/web/package.json'), JSON.stringify({ dependencies: { vite: '8.2.1' } }));
    const staged = stageWorkspace(src, '{"version":"5"}\n', dest);
    assert.deepEqual(staged, ['package.json', 'apps/web/package.json']);
    assert.equal(fs.readFileSync(path.join(dest, 'deno.lock'), 'utf8'), '{"version":"5"}\n');
    assert.ok(fs.existsSync(path.join(dest, PROBE)));
    assert.equal(fs.existsSync(path.join(dest, 'apps/absent')), false);
  } finally {
    fs.rmSync(src, { recursive: true, force: true });
    fs.rmSync(dest, { recursive: true, force: true });
  }
});

// The contract this script exists for: deno writes the section, and the ranges
// come back in ITS canonical form. `^0.45.8` reading back as `~0.45.8` is the
// bit no hand-written transcription of package.json gets right, and the reason
// this is not a few lines of JSON assembly.
test('regenerate lets deno write the section, in deno\'s canonical range form', { skip: !denoAvailable }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'regen-'));
  try {
    fs.writeFileSync(
      path.join(root, 'package.json'),
      JSON.stringify({ name: 'fixture', private: true, workspaces: ['pkg'], devDependencies: { svelte: '5.56.9' } }),
    );
    fs.mkdirSync(path.join(root, 'pkg'));
    fs.writeFileSync(
      path.join(root, 'pkg/package.json'),
      JSON.stringify({ name: 'pkg', dependencies: { 'material-symbols': '^0.45.8', vite: '^8.2.1' } }),
    );
    const remote = { 'https://esm.sh/v135/probe@1.0.0/mod.ts': 'sha256-notreal' };
    const out = JSON.parse(regenerate(root, `${JSON.stringify({ version: '5', remote }, null, 2)}\n`));

    assert.deepEqual(out.workspace.packageJson.dependencies, ['npm:svelte@5.56.9']);
    assert.deepEqual(out.workspace.members.pkg.packageJson.dependencies, [
      'npm:material-symbols@~0.45.8',
      'npm:vite@^8.2.1',
    ]);
    assert.deepEqual(out.remote, remote, 'the integrity pins must survive a regeneration untouched');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('the committed deno.lock is in sync with package.json', { skip: !denoAvailable }, () => {
  const rootDir = path.resolve(import.meta.dirname, '..');
  const lockText = fs.readFileSync(path.join(rootDir, 'deno.lock'), 'utf8');
  const after = JSON.parse(regenerate(rootDir, lockText));
  const before = JSON.parse(lockText);
  assert.ok(pinnedSectionsMatch(before, after));
  const diff = diffWorkspaceSections(before.workspace, after.workspace);
  assert.equal(diff.inSync, true, `run \`pnpm sync:deno-lock\`:\n${formatDrift(diff)}`);
});
