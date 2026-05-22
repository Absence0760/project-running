#!/usr/bin/env node
// Seed gzipped GPS tracks for the Virginia run rows in seed.sql so
// /runs/[id] renders a real polyline instead of "No GPS track for
// this run".
//
// Storage bytes live in MinIO behind Supabase Storage — SQL alone
// can't write them. This helper:
//   1. Reads the local Supabase anon + service_role keys via
//      `supabase status -o json` (or env overrides).
//   2. Generates a densified track for each Virginia route by
//      walking the route waypoints + interpolating 50-100 points
//      with a little Gaussian jitter (simulates GPS noise).
//   3. Gzips the JSON via `zlib.gzipSync`.
//   4. PUTs to /storage/v1/object/runs/{user_id}/{run_id}.json.gz
//      with the service-role key so the upload bypasses RLS.
//
// Idempotent: a re-run overwrites existing objects via the `x-upsert`
// header. Safe to re-invoke after `supabase db reset`.
//
// Run via: npm run dev:db:seed-tracks

import { execSync } from 'node:child_process';
import { gzipSync } from 'node:zlib';

const SUPABASE_URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const SEED_USER_ID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

function getServiceRoleKey() {
	if (process.env.SUPABASE_SERVICE_ROLE_KEY) {
		return process.env.SUPABASE_SERVICE_ROLE_KEY;
	}
	try {
		const out = execSync('supabase --workdir apps/backend status -o json', {
			stdio: ['ignore', 'pipe', 'ignore'],
		});
		return JSON.parse(out.toString()).SERVICE_ROLE_KEY;
	} catch (e) {
		console.error('Failed to read service_role key from `supabase status`.');
		console.error('Set SUPABASE_SERVICE_ROLE_KEY manually or start Supabase first.');
		process.exit(1);
	}
}

// Generate a TrackPoint[] by walking the waypoints + interpolating
// `pointsPerSegment` points between each. Adds small jitter so the
// polyline looks like real GPS data instead of a straight-edged
// connect-the-dots line.
function densifyTrack(waypoints, pointsPerSegment, baseTs) {
	const pts = [];
	let cumSec = 0;
	for (let i = 0; i < waypoints.length - 1; i++) {
		const a = waypoints[i];
		const b = waypoints[i + 1];
		for (let s = 0; s < pointsPerSegment; s++) {
			const t = s / pointsPerSegment;
			// 5e-5 = ~5m at mid-latitudes; tiny enough to look like
			// natural GPS noise without bending the route.
			const jitter = () => (Math.random() - 0.5) * 5e-5;
			const lat = a.lat + (b.lat - a.lat) * t + jitter();
			const lng = a.lng + (b.lng - a.lng) * t + jitter();
			const ele = a.ele != null && b.ele != null
				? Math.round(a.ele + (b.ele - a.ele) * t)
				: undefined;
			const ts = new Date(baseTs.getTime() + cumSec * 1000).toISOString();
			// Synthesise a believable HR profile: low-150s at the
			// start, drifting up to mid-160s on hills, plus tiny
			// per-point variation.
			const bpm = Math.round(152 + (ele != null ? (ele - 50) * 0.02 : 0) + (Math.random() - 0.5) * 4);
			pts.push({ lat, lng, ele, ts, bpm });
			cumSec += 6; // ~6s between points = realistic GPS sample rate
		}
	}
	// Close the polyline by appending the final waypoint.
	const last = waypoints[waypoints.length - 1];
	pts.push({
		lat: last.lat,
		lng: last.lng,
		ele: last.ele,
		ts: new Date(baseTs.getTime() + cumSec * 1000).toISOString(),
		bpm: 158,
	});
	return pts;
}

// Run plan — id + the waypoint shape from seed.sql. Each id MUST
// match the row inserted in seed.sql (the script + the SQL are
// linked by these UUIDs). Tracks generated here will land at
// `{user_id}/{id}.json.gz` and the seed row's `track_url` column
// points at the same path.
const PLAN = [
	{
		id: 'a1000001-0000-0000-0000-000000000001',
		startedAt: new Date('2026-05-15T07:30:00Z'),
		waypoints: [
			{ lat: 37.5311, lng: -77.452, ele: 58 },
			{ lat: 37.5318, lng: -77.45, ele: 54 },
			{ lat: 37.5325, lng: -77.448, ele: 50 },
			{ lat: 37.5331, lng: -77.446, ele: 47 },
			{ lat: 37.5335, lng: -77.4438, ele: 45 },
			{ lat: 37.534, lng: -77.4418, ele: 43 },
			{ lat: 37.5346, lng: -77.4398, ele: 41 },
			{ lat: 37.5352, lng: -77.4378, ele: 40 },
			{ lat: 37.5358, lng: -77.436, ele: 42 },
			{ lat: 37.5362, lng: -77.4345, ele: 45 },
			{ lat: 37.5365, lng: -77.433, ele: 48 },
			{ lat: 37.536, lng: -77.4348, ele: 50 },
			{ lat: 37.5354, lng: -77.4368, ele: 48 },
			{ lat: 37.5348, lng: -77.4388, ele: 46 },
			{ lat: 37.5342, lng: -77.4408, ele: 44 },
			{ lat: 37.5337, lng: -77.4428, ele: 42 },
			{ lat: 37.5333, lng: -77.4448, ele: 44 },
			{ lat: 37.5328, lng: -77.4468, ele: 48 },
			{ lat: 37.5322, lng: -77.4488, ele: 52 },
			{ lat: 37.5315, lng: -77.4508, ele: 56 },
			{ lat: 37.5311, lng: -77.452, ele: 58 },
		],
	},
	{
		id: 'a1000001-0000-0000-0000-000000000002',
		startedAt: new Date('2026-05-12T18:00:00Z'),
		waypoints: [
			{ lat: 38.0356, lng: -78.5067, ele: 150 },
			{ lat: 38.0362, lng: -78.507, ele: 152 },
			{ lat: 38.0368, lng: -78.5075, ele: 155 },
			{ lat: 38.0373, lng: -78.5082, ele: 160 },
			{ lat: 38.0378, lng: -78.509, ele: 165 },
			{ lat: 38.0382, lng: -78.51, ele: 168 },
			{ lat: 38.0384, lng: -78.511, ele: 170 },
			{ lat: 38.0385, lng: -78.512, ele: 168 },
			{ lat: 38.0382, lng: -78.5128, ele: 166 },
			{ lat: 38.0376, lng: -78.5132, ele: 164 },
			{ lat: 38.0368, lng: -78.513, ele: 162 },
			{ lat: 38.036, lng: -78.5125, ele: 160 },
			{ lat: 38.0355, lng: -78.5115, ele: 158 },
			{ lat: 38.0352, lng: -78.5102, ele: 155 },
			{ lat: 38.035, lng: -78.509, ele: 153 },
			{ lat: 38.0351, lng: -78.5078, ele: 151 },
			{ lat: 38.0356, lng: -78.5067, ele: 150 },
		],
	},
	{
		id: 'a1000001-0000-0000-0000-000000000003',
		startedAt: new Date('2026-05-10T06:45:00Z'),
		waypoints: [
			{ lat: 38.887, lng: -77.056, ele: 10 },
			{ lat: 38.8845, lng: -77.054, ele: 11 },
			{ lat: 38.881, lng: -77.0518, ele: 12 },
			{ lat: 38.877, lng: -77.0498, ele: 13 },
			{ lat: 38.873, lng: -77.048, ele: 14 },
			{ lat: 38.869, lng: -77.0468, ele: 15 },
			{ lat: 38.8645, lng: -77.0455, ele: 16 },
			{ lat: 38.8595, lng: -77.0445, ele: 17 },
			{ lat: 38.854, lng: -77.0438, ele: 18 },
			{ lat: 38.8485, lng: -77.0432, ele: 18 },
			{ lat: 38.843, lng: -77.0428, ele: 19 },
			{ lat: 38.8485, lng: -77.0432, ele: 18 },
			{ lat: 38.854, lng: -77.0438, ele: 18 },
			{ lat: 38.8595, lng: -77.0445, ele: 17 },
			{ lat: 38.8645, lng: -77.0455, ele: 16 },
			{ lat: 38.869, lng: -77.0468, ele: 15 },
			{ lat: 38.873, lng: -77.048, ele: 14 },
			{ lat: 38.877, lng: -77.0498, ele: 13 },
			{ lat: 38.881, lng: -77.0518, ele: 12 },
			{ lat: 38.8845, lng: -77.054, ele: 11 },
			{ lat: 38.887, lng: -77.056, ele: 10 },
		],
	},
	{
		id: 'a1000001-0000-0000-0000-000000000004',
		startedAt: new Date('2026-05-08T08:00:00Z'),
		waypoints: [
			{ lat: 37.271, lng: -79.9416, ele: 280 },
			{ lat: 37.27, lng: -79.94, ele: 300 },
			{ lat: 37.2688, lng: -79.9385, ele: 330 },
			{ lat: 37.2675, lng: -79.937, ele: 365 },
			{ lat: 37.266, lng: -79.9355, ele: 405 },
			{ lat: 37.2645, lng: -79.9345, ele: 445 },
			{ lat: 37.263, lng: -79.9338, ele: 485 },
			{ lat: 37.2615, lng: -79.9335, ele: 520 },
			{ lat: 37.2602, lng: -79.9332, ele: 555 },
			{ lat: 37.2592, lng: -79.933, ele: 580 },
			{ lat: 37.2602, lng: -79.9332, ele: 555 },
			{ lat: 37.2615, lng: -79.9335, ele: 520 },
			{ lat: 37.263, lng: -79.9338, ele: 485 },
			{ lat: 37.2645, lng: -79.9345, ele: 445 },
			{ lat: 37.266, lng: -79.9355, ele: 405 },
			{ lat: 37.2675, lng: -79.937, ele: 365 },
			{ lat: 37.2688, lng: -79.9385, ele: 330 },
			{ lat: 37.27, lng: -79.94, ele: 300 },
			{ lat: 37.271, lng: -79.9416, ele: 280 },
		],
	},
];

async function uploadTrack(serviceRoleKey, run) {
	const path = `${SEED_USER_ID}/${run.id}.json.gz`;
	const track = densifyTrack(run.waypoints, 4, run.startedAt);
	const json = JSON.stringify(track);
	const gz = gzipSync(Buffer.from(json));

	const url = `${SUPABASE_URL}/storage/v1/object/runs/${path}`;
	const res = await fetch(url, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${serviceRoleKey}`,
			apikey: serviceRoleKey,
			'Content-Type': 'application/gzip',
			'x-upsert': 'true',
		},
		body: gz,
	});
	if (!res.ok) {
		console.error(`  ✗ ${run.id}: ${res.status} ${await res.text()}`);
		return false;
	}
	console.log(`  ✓ ${run.id} (${track.length} pts, ${gz.length} bytes gzipped)`);
	return true;
}

async function main() {
	const key = getServiceRoleKey();
	console.log(`Uploading ${PLAN.length} run tracks to ${SUPABASE_URL}/storage/v1/object/runs/`);
	let ok = 0;
	for (const run of PLAN) {
		if (await uploadTrack(key, run)) ok++;
	}
	console.log(`\n${ok}/${PLAN.length} tracks uploaded.`);
	if (ok < PLAN.length) process.exit(1);
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
