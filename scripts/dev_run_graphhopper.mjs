#!/usr/bin/env node
// Preflight wrapper for `docker compose up` on the local GraphHopper stack.
//
// GraphHopper builds its routing graph inside the container on first boot, but
// it needs the source PBF at apps/job_worker/graphhopper/data/region.osm.pbf
// first. A bare `docker compose up` against a fresh checkout would start the
// container, fail to find the PBF, and crash-loop with a stack of Java errors.
//
// This wrapper checks for the PBF BEFORE starting, prints the one-line setup
// recipe if it's missing, and otherwise falls through to `docker compose up`
// (which builds the image from source on first run — slow once, cached after).
// Sibling of scripts/dev_run_osrm.mjs.

import { accessSync, constants, existsSync, statSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ghDir = resolve(repoRoot, 'apps/job_worker/graphhopper');
const dataDir = resolve(ghDir, 'data');
const pbf = resolve(dataDir, 'region.osm.pbf');

// Detect the "data/ owned by root from a prior `docker compose up`" trap, the
// same way dev_run_osrm.mjs does.
if (existsSync(dataDir)) {
	try {
		accessSync(dataDir, constants.W_OK);
	} catch {
		const owner = (() => {
			try {
				return statSync(dataDir).uid;
			} catch {
				return null;
			}
		})();
		console.error('');
		console.error(`  ✗ ${dataDir} exists but isn't writable by you${owner === 0 ? ' (owned by root)' : ''}.`);
		console.error('');
		console.error('    A previous `docker compose up` ran as root and created the bind-mount');
		console.error('    target. One-line fix:');
		console.error('');
		console.error(`      sudo chown -R $USER:$USER ${dataDir}`);
		console.error('');
		console.error('    Then re-run `npm run dev:setup:graphhopper`.');
		console.error('');
		process.exit(1);
	}
}

if (!existsSync(pbf)) {
	console.error('');
	console.error('  ✗ Local GraphHopper is missing its region PBF.');
	console.error('');
	console.error(`  Expected: ${pbf}`);
	console.error('');
	console.error('  One-time setup (reuses the OSRM extract if present, else downloads it):');
	console.error('');
	console.error('    npm run dev:setup:graphhopper');
	console.error('');
	console.error('  Then re-run `npm run dev:run:graphhopper`. First boot builds the image');
	console.error('  from source and imports the graph (a few minutes); later boots reuse both.');
	console.error('');
	console.error('  Once it is serving, point the web dev server at it by setting');
	console.error('  GRAPHHOPPER_URL=http://127.0.0.1:8989 in apps/web/.env.local.');
	console.error('');
	process.exit(1);
}

const child = spawn('docker', ['compose', 'up', '--build'], {
	cwd: ghDir,
	stdio: 'inherit',
});
child.on('exit', (code) => process.exit(code ?? 1));
