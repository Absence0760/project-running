#!/usr/bin/env node
// Preflight wrapper for `docker compose up` on the local OSRM stack.
//
// The OSRM container needs a pre-built routing graph at
// `apps/job_worker/osrm/data/region.osrm.*` (12-ish files produced by
// the osrm-extract / osrm-partition / osrm-customize pipeline). The
// previous `dev:run:osrm` script ran `docker compose up` blindly, so
// a fresh checkout would crash-loop with twelve "Missing/Broken File"
// errors and the user had to dig through README.md to find the
// `make download && make build` one-time-setup steps.
//
// This wrapper checks for the load-bearing graph files BEFORE the
// container starts and prints a clear setup recipe if any are
// missing. Once the graph exists, it falls through to the same
// `docker compose up` as before.

import { existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const osrmDir = resolve(repoRoot, 'apps/job_worker/osrm');
const dataDir = resolve(osrmDir, 'data');

// Files osrm-routed errors out on if any are missing. Pick a handful
// from each stage of the build pipeline so a partial / interrupted
// build is also caught.
const REQUIRED = [
	'region.osrm', // base
	'region.osrm.ramIndex',
	'region.osrm.fileIndex',
	'region.osrm.edges',
	'region.osrm.geometry',
	'region.osrm.partition', // partition stage
	'region.osrm.cells',
	'region.osrm.mldgr', // customize stage
];

const missing = REQUIRED.filter((f) => !existsSync(resolve(dataDir, f)));

if (missing.length > 0) {
	const pbfExists = existsSync(resolve(dataDir, 'region.osm.pbf'));
	console.error('');
	console.error('  ✗ Local OSRM is missing its routing graph.');
	console.error('');
	console.error(`  ${missing.length} required file(s) are absent from ${dataDir}/`);
	console.error(`  e.g. ${missing.slice(0, 3).join(', ')}${missing.length > 3 ? ', …' : ''}`);
	console.error('');
	console.error('  This is a one-time setup step — the routing graph is built locally from a');
	console.error('  Geofabrik OSM extract and is too large (multi-GB intermediates) to check into');
	console.error('  git. Run:');
	console.error('');
	if (pbfExists) {
		console.error('    pnpm dev:setup:osrm');
		console.error('');
		console.error('  (skips the download — region.osm.pbf is already on disk — and rebuilds');
		console.error('  the graph. Takes ~5-15 min depending on the region.)');
	} else {
		console.error('    pnpm dev:setup:osrm');
		console.error('');
		console.error('  This downloads the default region (Victoria, Australia — matches the');
		console.error('  Melbourne seed runs) and builds the graph. The download is ~50-200 MB');
		console.error('  and the build takes ~5-15 min. Override the region with:');
		console.error('');
		console.error('    cd apps/job_worker/osrm');
		console.error('    make clean');
		console.error('    make download REGION_URL=https://download.geofabrik.de/...');
		console.error('    make build');
	}
	console.error('');
	console.error('  Once that finishes, re-run `pnpm dev:run:osrm`.');
	console.error('');
	process.exit(1);
}

// Graph is present — start the server.
const child = spawn('docker', ['compose', 'up'], {
	cwd: osrmDir,
	stdio: 'inherit',
});
child.on('exit', (code) => process.exit(code ?? 1));
