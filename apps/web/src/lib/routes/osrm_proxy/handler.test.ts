import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	buildUpstreamQuery,
	handleOsrmProxy,
	MAX_ROUTE_COORDS,
	OSRM_DEMO_URL,
	parseOsrmProxyPath,
	type Fetcher,
	type OsrmProxyConfig,
} from './handler';

const CONFIG: OsrmProxyConfig = {
	osrmUrl: 'http://osrm.local',
	allowDemoFallback: false,
	publicSupabaseUrl: 'http://supabase.local',
	publicSupabaseAnonKey: 'anon',
};

const AUTH = 'Bearer token-123';
const okAuth = async () => 'ok' as const;

function osrmOk(body: unknown): Response {
	return new Response(JSON.stringify(body), {
		status: 200,
		headers: { 'content-type': 'application/json' },
	});
}

// --- parseOsrmProxyPath ---

test('parseOsrmProxyPath accepts the two client shapes', () => {
	const nearest = parseOsrmProxyPath('/nearest/v1/foot/2.35,48.85');
	assert.deepEqual(nearest, { service: 'nearest', profile: 'foot', coords: [[2.35, 48.85]] });

	const route = parseOsrmProxyPath('/route/v1/car/2.35,48.85;2.36,48.86');
	assert.deepEqual(route, {
		service: 'route',
		profile: 'car',
		coords: [
			[2.35, 48.85],
			[2.36, 48.86],
		],
	});
});

test('parseOsrmProxyPath rejects unknown services, profiles, and malformed coords', () => {
	assert.equal(parseOsrmProxyPath('/table/v1/foot/1,1;2,2'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/bike/1,1'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v2/foot/1,1'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/1,1/extra'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/abc,1'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/1'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/1,1,1'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/,1'), null);
	assert.equal(parseOsrmProxyPath(''), null);
});

test('parseOsrmProxyPath rejects out-of-range coordinates', () => {
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/181,10'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/10,91'), null);
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/Infinity,10'), null);
});

test('parseOsrmProxyPath enforces per-service coordinate counts', () => {
	// nearest is exactly one point; route needs 2..MAX_ROUTE_COORDS.
	assert.equal(parseOsrmProxyPath('/nearest/v1/foot/1,1;2,2'), null);
	assert.equal(parseOsrmProxyPath('/route/v1/foot/1,1'), null);
	const atCap = Array.from({ length: MAX_ROUTE_COORDS }, (_, i) => `${i / 100},${i / 100}`).join(';');
	assert.ok(parseOsrmProxyPath(`/route/v1/foot/${atCap}`));
	const overCap = `${atCap};9,9`;
	assert.equal(parseOsrmProxyPath(`/route/v1/foot/${overCap}`), null);
});

// --- buildUpstreamQuery ---

test('buildUpstreamQuery forwards only allowlisted params and drops unknown ones', () => {
	const parsed = parseOsrmProxyPath('/route/v1/foot/1,1;2,2')!;
	const q = buildUpstreamQuery(parsed, {
		overview: 'full',
		geometries: 'geojson',
		radiuses: '100;100',
		evil: 'http://attacker.example',
	});
	assert.ok(q);
	const params = new URLSearchParams(q!.slice(1));
	assert.equal(params.get('overview'), 'full');
	assert.equal(params.get('geometries'), 'geojson');
	assert.equal(params.get('radiuses'), '100;100');
	assert.equal(params.get('evil'), null);
});

test('buildUpstreamQuery rejects invalid values on recognised params', () => {
	const route = parseOsrmProxyPath('/route/v1/foot/1,1;2,2')!;
	assert.equal(buildUpstreamQuery(route, { overview: 'everything' }), null);
	assert.equal(buildUpstreamQuery(route, { geometries: 'wkt' }), null);
	// radiuses count must match the coordinate count; each in (0, 10000].
	assert.equal(buildUpstreamQuery(route, { radiuses: '100' }), null);
	assert.equal(buildUpstreamQuery(route, { radiuses: '100;0' }), null);
	assert.equal(buildUpstreamQuery(route, { radiuses: '100;999999' }), null);
	assert.equal(buildUpstreamQuery(route, { radiuses: '100;-5' }), null);
	// number is nearest-only and 1..10.
	assert.equal(buildUpstreamQuery(route, { number: '1' }), null);
	const nearest = parseOsrmProxyPath('/nearest/v1/foot/1,1')!;
	assert.equal(buildUpstreamQuery(nearest, { number: '0' }), null);
	assert.equal(buildUpstreamQuery(nearest, { number: '11' }), null);
	assert.equal(buildUpstreamQuery(nearest, { number: '2e1' }), null);
	assert.equal(buildUpstreamQuery(nearest, { number: '1', radiuses: '100' }), '?number=1&radiuses=100');
});

test('buildUpstreamQuery returns empty string when nothing is set', () => {
	const nearest = parseOsrmProxyPath('/nearest/v1/foot/1,1')!;
	assert.equal(buildUpstreamQuery(nearest, {}), '');
});

// --- handleOsrmProxy ---

test('handleOsrmProxy proxies a valid route call and passes the OSRM JSON through', async () => {
	let upstreamUrl = '';
	const fetcher: Fetcher = async (url) => {
		upstreamUrl = url;
		return osrmOk({ code: 'Ok', routes: [{ distance: 42 }] });
	};
	const result = await handleOsrmProxy(
		AUTH,
		'/route/v1/foot/2.35,48.85;2.36,48.86',
		{ overview: 'full', geometries: 'geojson', radiuses: '100;100' },
		CONFIG,
		{ fetcher, authChecker: okAuth },
	);
	assert.equal(result.status, 200);
	assert.deepEqual(result.body, { code: 'Ok', routes: [{ distance: 42 }] });
	const u = new URL(upstreamUrl);
	assert.equal(u.origin, 'http://osrm.local');
	assert.equal(u.pathname, '/route/v1/foot/2.35,48.85;2.36,48.86');
	assert.equal(u.searchParams.get('radiuses'), '100;100');
});

test('handleOsrmProxy answers 400 on a bad path or bad query without touching auth or upstream', async () => {
	let touched = false;
	const fetcher: Fetcher = async () => {
		touched = true;
		return osrmOk({});
	};
	const spyAuth = async () => {
		touched = true;
		return 'ok' as const;
	};
	const badPath = await handleOsrmProxy(AUTH, '/table/v1/foot/1,1;2,2', {}, CONFIG, {
		fetcher,
		authChecker: spyAuth,
	});
	assert.equal(badPath.status, 400);
	const badQuery = await handleOsrmProxy(AUTH, '/nearest/v1/foot/1,1', { number: 'x' }, CONFIG, {
		fetcher,
		authChecker: spyAuth,
	});
	assert.equal(badQuery.status, 400);
	assert.equal(touched, false);
});

test('handleOsrmProxy requires a signed-in caller', async () => {
	const fetcher: Fetcher = async () => osrmOk({ code: 'Ok' });
	const noHeader = await handleOsrmProxy(null, '/nearest/v1/foot/1,1', {}, CONFIG, { fetcher });
	assert.equal(noHeader.status, 401);

	const rejected = await handleOsrmProxy(AUTH, '/nearest/v1/foot/1,1', {}, CONFIG, {
		fetcher,
		authChecker: async () => 'unauthenticated' as const,
	});
	assert.equal(rejected.status, 401);

	// Fail-closed: an unanswerable auth check denies, never grants.
	const errored = await handleOsrmProxy(AUTH, '/nearest/v1/foot/1,1', {}, CONFIG, {
		fetcher,
		authChecker: async () => 'error' as const,
	});
	assert.equal(errored.status, 500);
});

test('handleOsrmProxy answers 501 when OSRM_URL is unset and the demo fallback is off', async () => {
	const result = await handleOsrmProxy(
		AUTH,
		'/nearest/v1/foot/1,1',
		{},
		{ ...CONFIG, osrmUrl: undefined },
		{ fetcher: async () => osrmOk({}), authChecker: okAuth },
	);
	assert.equal(result.status, 501);
});

test('handleOsrmProxy uses the community demo only under allowDemoFallback (dev wrapper)', async () => {
	let upstreamUrl = '';
	const fetcher: Fetcher = async (url) => {
		upstreamUrl = url;
		return osrmOk({ code: 'Ok' });
	};
	const result = await handleOsrmProxy(
		AUTH,
		'/nearest/v1/foot/1,1',
		{},
		{ ...CONFIG, osrmUrl: undefined, allowDemoFallback: true },
		{ fetcher, authChecker: okAuth },
	);
	assert.equal(result.status, 200);
	assert.ok(upstreamUrl.startsWith(OSRM_DEMO_URL));
});

test('handleOsrmProxy collapses upstream failures to 502', async () => {
	const upstream400 = await handleOsrmProxy(AUTH, '/nearest/v1/foot/1,1', {}, CONFIG, {
		fetcher: async () => new Response('{"code":"InvalidQuery"}', { status: 400 }),
		authChecker: okAuth,
	});
	assert.equal(upstream400.status, 502);

	const upstreamThrow = await handleOsrmProxy(AUTH, '/nearest/v1/foot/1,1', {}, CONFIG, {
		fetcher: async () => {
			throw new Error('connect ECONNREFUSED');
		},
		authChecker: okAuth,
	});
	assert.equal(upstreamThrow.status, 502);
});

test('handleOsrmProxy strips trailing slashes off the configured base URL', async () => {
	let upstreamUrl = '';
	const fetcher: Fetcher = async (url) => {
		upstreamUrl = url;
		return osrmOk({ code: 'Ok' });
	};
	await handleOsrmProxy(
		AUTH,
		'/nearest/v1/foot/1,1',
		{},
		{ ...CONFIG, osrmUrl: 'http://osrm.local///' },
		{ fetcher, authChecker: okAuth },
	);
	assert.equal(upstreamUrl, 'http://osrm.local/nearest/v1/foot/1,1');
});
