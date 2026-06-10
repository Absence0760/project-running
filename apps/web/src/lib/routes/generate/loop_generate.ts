/**
 * Sampled via-point polygon loop generator (route_loop_generation.md).
 *
 * Drives OSRM's multi-waypoint `/route/v1/foot` as a routing primitive: places
 * K via-points on a ring around the start (loop_polygon.ts) to force a compact
 * loop, routes `start → v1 → … → vK → start`, scores the traced paths with
 * `pickBestPolygonLoop` (loop_select.ts), and returns the best loop — or null
 * when the location is loop-poor (nothing clears the spur/snap bar), the signal
 * the handler uses to fall back to round_trip.
 *
 * Two-stage search (route_loop_generation.md § Search): a coarse rotation scan
 * (one radius per rotation) finds the productive rotations, then a refine pass
 * samples every radius at the best rotations. Radius→distance is mostly but not
 * strictly monotonic (snapping breaks it), so we sample-and-pick-closest rather
 * than bisect.
 *
 * The HTTP call is isolated behind an injectable `Fetcher` (the same seam as
 * graphhopper.ts) so the placement + parse + selection logic is unit-testable
 * without network. Self-hosted OSRM only — the engine URL is a server-only env;
 * the browser never calls OSRM directly, so user start-coordinates stay on our
 * infra (privacy parity, decisions §45).
 */

import type { Fetcher } from './graphhopper';
import {
	candidatePlacements,
	viaPoints,
	DEFAULT_PLACEMENT_PARAMS,
	type PlacementParams,
} from './loop_polygon';
import { pickBestPolygonLoop, type PolygonCandidate } from './loop_select';

export interface PolygonLoopConfig {
	/// Raw OSRM base URL (e.g. `http://osrm:5000`). Undefined/empty → the
	/// generator is unavailable; the caller falls back to round_trip.
	osrmUrl: string | undefined;
	params?: PlacementParams;
	/// How many of the best coarse rotations to refine across all radii.
	refineRotations?: number;
	timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 8000;
const DEFAULT_REFINE_ROTATIONS = 2;

/// Build the OSRM `/route/v1/foot` URL for the closed loop
/// `start → via… → start`. Coordinates are `lng,lat` semicolon-joined (OSRM
/// order). `overview=full&geometries=geojson` returns the full traced polyline
/// so the shape metric scores the actual path, not the via-point hull.
export function buildOsrmLoopUrl(
	baseUrl: string,
	start: { lat: number; lng: number },
	vias: ReadonlyArray<{ lat: number; lng: number }>,
): string {
	const base = baseUrl.replace(/\/+$/, '');
	const pts = [start, ...vias, start].map((p) => `${p.lng},${p.lat}`).join(';');
	const params = new URLSearchParams({
		overview: 'full',
		geometries: 'geojson',
		steps: 'false',
	});
	return `${base}/route/v1/foot/${pts}?${params.toString()}`;
}

/// Parse an OSRM `/route` response into a PolygonCandidate. Pure. Returns null
/// when the response carries no usable route (`code !== 'Ok'`, no routes, or
/// empty geometry). `maxSnapM` is the farthest any waypoint snapped from where
/// we placed it (`waypoints[].distance`) — the free bad-snap signal.
export function parseOsrmLoop(json: unknown): PolygonCandidate | null {
	const j = json as { code?: unknown; routes?: unknown[]; waypoints?: unknown[] } | null;
	if (!j || j.code !== 'Ok' || !Array.isArray(j.routes) || j.routes.length === 0) return null;
	const route = j.routes[0] as Record<string, unknown>;
	const geom = route.geometry as { coordinates?: unknown } | undefined;
	const raw = geom?.coordinates;
	if (!Array.isArray(raw)) return null;
	const coordinates: [number, number][] = [];
	for (const c of raw) {
		if (!Array.isArray(c) || c.length < 2) continue;
		const lng = Number(c[0]);
		const lat = Number(c[1]);
		if (!Number.isFinite(lng) || !Number.isFinite(lat)) continue;
		coordinates.push([lng, lat]);
	}
	if (coordinates.length < 2) return null;
	const distanceM =
		typeof route.distance === 'number' && Number.isFinite(route.distance) ? route.distance : 0;

	let maxSnapM = 0;
	if (Array.isArray(j.waypoints)) {
		for (const w of j.waypoints) {
			const d = (w as { distance?: unknown }).distance;
			if (typeof d === 'number' && Number.isFinite(d) && d > maxSnapM) maxSnapM = d;
		}
	}
	return { coordinates, distanceM, maxSnapM };
}

async function routePlacement(
	osrmUrl: string,
	start: { lat: number; lng: number },
	placement: { k: number; rotationDeg: number; radiusM: number },
	fetcher: Fetcher,
	timeoutMs: number,
): Promise<PolygonCandidate | null> {
	const vias = viaPoints(start, placement.radiusM, placement.k, placement.rotationDeg);
	const url = buildOsrmLoopUrl(osrmUrl, start, vias);
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), timeoutMs);
	try {
		const res = await fetcher(url, { signal: controller.signal });
		if (!res.ok) return null;
		const json = await res.json();
		return parseOsrmLoop(json);
	} catch {
		// A single placement failing (timeout, network, bad JSON) is expected at
		// the edges of the sampling grid; it must not abort the whole scan. The
		// candidate is simply absent.
		return null;
	} finally {
		clearTimeout(timer);
	}
}

/**
 * Generate a compact loop near `start` of roughly `targetM` metres. Returns the
 * best-scoring polygon loop, or null when the location is loop-poor (no
 * candidate clears the spur/snap bar) or OSRM is unconfigured/unreachable —
 * both cases the handler turns into the round_trip fallback.
 */
export async function generatePolygonLoop(
	start: { lat: number; lng: number },
	targetM: number,
	fetcher: Fetcher,
	config: PolygonLoopConfig,
): Promise<{ coordinates: [number, number][]; distanceM: number } | null> {
	const base = (config.osrmUrl ?? '').replace(/\/+$/, '');
	if (!base) return null;

	const params = config.params ?? DEFAULT_PLACEMENT_PARAMS;
	const timeoutMs = config.timeoutMs ?? DEFAULT_TIMEOUT_MS;
	const refineRotations = Math.max(1, config.refineRotations ?? DEFAULT_REFINE_ROTATIONS);

	const opts = {
		spurFloor: params.spurFloor,
		maxSnapM: params.maxSnapM,
		bandFraction: params.bandFraction,
	};

	// Stage 1 — coarse rotation scan: one (the middle) radius per (k, rotation),
	// so the grid is K × rotationCount calls instead of the full product. Finds
	// which rotations are productive at this start (the PoC's best rotation is
	// location-specific).
	const midFraction = params.radiusFractions[Math.floor(params.radiusFractions.length / 2)];
	const coarseParams: PlacementParams = { ...params, radiusFractions: [midFraction] };
	const coarsePlacements = candidatePlacements(targetM, coarseParams);
	const coarse = await Promise.all(
		coarsePlacements.map((p) => routePlacement(base, start, p, fetcher, timeoutMs)),
	);

	const coarseScored = coarsePlacements
		.map((p, i) => ({ placement: p, cand: coarse[i] }))
		.filter((x): x is { placement: typeof x.placement; cand: PolygonCandidate } => x.cand !== null);

	// Stage 2 — refine: take the best coarse rotations (those whose coarse
	// candidate is closest to target), then sample EVERY radius at each so the
	// radius that lands nearest the target shows up. Sample-and-pick-closest, not
	// bisection: snapping makes radius→distance non-monotonic.
	const bestRotations = coarseScored
		.slice()
		.sort(
			(a, b) =>
				Math.abs(a.cand.distanceM - targetM) - Math.abs(b.cand.distanceM - targetM),
		)
		.slice(0, refineRotations)
		.map((x) => ({ k: x.placement.k, rotationDeg: x.placement.rotationDeg }));

	const refinePlacements: { k: number; rotationDeg: number; radiusM: number }[] = [];
	for (const { k, rotationDeg } of bestRotations) {
		for (const fraction of params.radiusFractions) {
			if (fraction === midFraction) continue; // already routed in the coarse scan
			refinePlacements.push({ k, rotationDeg, radiusM: targetM * fraction });
		}
	}
	const refine = await Promise.all(
		refinePlacements.map((p) => routePlacement(base, start, p, fetcher, timeoutMs)),
	);

	const candidates: PolygonCandidate[] = [
		...coarseScored.map((x) => x.cand),
		...refine.filter((c): c is PolygonCandidate => c !== null),
	];

	const best = pickBestPolygonLoop(candidates, targetM, opts);
	if (!best) return null;
	return { coordinates: best.coordinates, distanceM: best.distanceM };
}
