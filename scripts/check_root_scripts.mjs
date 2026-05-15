#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pkgPath = path.join(rootDir, 'package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
const scripts = pkg.scripts ?? {};
const errors = [];

const childPkgCache = new Map();
function loadChildPkg(dir) {
  if (childPkgCache.has(dir)) return childPkgCache.get(dir);
  const childPath = path.join(rootDir, dir, 'package.json');
  if (!fs.existsSync(childPath)) {
    childPkgCache.set(dir, null);
    return null;
  }
  const json = JSON.parse(fs.readFileSync(childPath, 'utf8'));
  childPkgCache.set(dir, json);
  return json;
}

const RESERVED_PNPM_VERBS = new Set([
  'install', 'add', 'remove', 'update', 'exec', 'dlx',
  'run', 'test', 'start', 'build', 'publish', 'pack', 'audit',
  'list', 'ls', 'why', 'outdated', 'config', 'store', 'recursive',
  'rebuild', 'prune', 'link', 'unlink', 'import', 'fetch',
]);

for (const [name, cmd] of Object.entries(scripts)) {
  for (const m of cmd.matchAll(/pnpm\s+-C\s+(\S+)\s+(\S+)/g)) {
    const [, dir, verbOrScript] = m;
    const child = loadChildPkg(dir);
    if (!child) {
      errors.push(`${name}: missing ${dir}/package.json`);
      continue;
    }
    const target = verbOrScript === 'run' ? cmd.match(/pnpm\s+-C\s+\S+\s+run\s+(\S+)/)?.[1] : verbOrScript;
    if (!target) continue;
    if (RESERVED_PNPM_VERBS.has(target)) continue;
    if (!(target in (child.scripts ?? {}))) {
      errors.push(`${name}: ${dir}/package.json has no "${target}" script`);
    }
  }

  for (const m of cmd.matchAll(/(?:^|&&\s*)cd\s+(\S+)/g)) {
    const dir = m[1];
    if (!fs.existsSync(path.join(rootDir, dir))) {
      errors.push(`${name}: missing directory ${dir}`);
    }
  }
}

if (errors.length) {
  console.error(`Root scripts validation failed (${errors.length} issue${errors.length === 1 ? '' : 's'}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log(`Root scripts validation passed (${Object.keys(scripts).length} scripts).`);
