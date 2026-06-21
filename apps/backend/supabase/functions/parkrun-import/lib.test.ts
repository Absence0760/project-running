import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	MAX_PARKRUN_FIELD_LEN,
	MAX_PARKRUN_HTML_BYTES,
	MAX_PARKRUN_ROWS,
	capParkrunField,
	parseParkrunDate,
	parseParkrunTime,
	readBodyTextWithCap,
} from './lib.ts';

Deno.test('capParkrunField — trims whitespace', () => {
	assertEquals(capParkrunField('  Bushy Park  '), 'Bushy Park');
});

Deno.test('capParkrunField — short string passes through', () => {
	assertEquals(capParkrunField('Bushy Park'), 'Bushy Park');
});

Deno.test('capParkrunField — non-string returns empty', () => {
	assertEquals(capParkrunField(null), '');
	assertEquals(capParkrunField(undefined), '');
	assertEquals(capParkrunField(42 as unknown), '');
});

Deno.test('capParkrunField — truncates at MAX_PARKRUN_FIELD_LEN', () => {
	const long = 'A'.repeat(MAX_PARKRUN_FIELD_LEN + 50);
	const capped = capParkrunField(long);
	assertEquals(capped.length, MAX_PARKRUN_FIELD_LEN);
	assertEquals(capped, 'A'.repeat(MAX_PARKRUN_FIELD_LEN));
});

Deno.test('capParkrunField — honours a custom cap', () => {
	assertEquals(capParkrunField('hello world', 5), 'hello');
});

Deno.test('readBodyTextWithCap — body under cap returns text', async () => {
	const r = new Response('parkrun results html');
	const result = await readBodyTextWithCap(r, 10 * 1024);
	assertEquals(result.ok, true);
	if (result.ok) assertEquals(result.text, 'parkrun results html');
});

Deno.test('readBodyTextWithCap — body over cap rejects without slurping', async () => {
	// Build a 4-MB body in 64-KB chunks so the cap kicks in mid-stream.
	const chunk = new Uint8Array(64 * 1024).fill(0x41); // 'A'
	const stream = new ReadableStream({
		start(controller) {
			for (let i = 0; i < 64; i++) controller.enqueue(chunk);
			controller.close();
		},
	});
	const r = new Response(stream);
	const result = await readBodyTextWithCap(r, 1024 * 1024); // 1 MB cap
	assertEquals(result.ok, false);
	if (!result.ok) assertEquals(result.reason, 'too_large');
});

Deno.test('readBodyTextWithCap — body at exactly the cap is accepted', async () => {
	const exact = new Uint8Array(1024).fill(0x42); // 1 KB of 'B'
	const r = new Response(exact);
	const result = await readBodyTextWithCap(r, 1024);
	assertEquals(result.ok, true);
	if (result.ok) assertEquals(result.text.length, 1024);
});

Deno.test('readBodyTextWithCap — Content-Length over cap bails early', async () => {
	const r = new Response('x'.repeat(100), {
		headers: { 'content-length': String(10 * 1024 * 1024) },
	});
	const result = await readBodyTextWithCap(r, 1024);
	assertEquals(result.ok, false);
	if (!result.ok) assertEquals(result.reason, 'too_large');
});

Deno.test('constants stay in sensible ranges', () => {
	// Cheap guards: if a future writer drops the field cap to 0 or
	// blows the HTML cap to 1 GB by accident, this fires.
	assertEquals(MAX_PARKRUN_FIELD_LEN > 0 && MAX_PARKRUN_FIELD_LEN <= 1000, true);
	assertEquals(MAX_PARKRUN_HTML_BYTES <= 10 * 1024 * 1024, true);
	assertEquals(MAX_PARKRUN_ROWS > 0 && MAX_PARKRUN_ROWS <= 100000, true);
});

// ──────────────────────────────────────────────────────────────────
// parseParkrunDate / parseParkrunTime — persona-hunt finding Pro #5.

function localDateAt(stampIso: string, offsetHours: number): string {
	const stampMs = Date.parse(stampIso);
	const localMs = stampMs + offsetHours * 3_600_000;
	const d = new Date(localMs);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

Deno.test('parseParkrunDate — DD/MM/YYYY parses to T10:00:00Z', () => {
	assertEquals(parseParkrunDate('15/04/2026'), '2026-04-15T10:00:00Z');
});

Deno.test('parseParkrunDate — date preserved at UTC+0 (UK)', () => {
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), 0), '2026-04-15');
});

Deno.test('parseParkrunDate — date preserved at UTC+1 (UK BST)', () => {
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), 1), '2026-04-15');
});

Deno.test('parseParkrunDate — date preserved at UTC+11 (AU AEDT)', () => {
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), 11), '2026-04-15');
});

Deno.test('parseParkrunDate — date preserved at UTC+13 (NZ NZDT)', () => {
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), 13), '2026-04-15');
});

Deno.test('parseParkrunDate — date preserved at UTC-8 (US West)', () => {
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), -8), '2026-04-15');
});

Deno.test('parseParkrunDate — date preserved at UTC-10 (Hawaii, the bug case)', () => {
	// Pre-fix at T08:00:00Z, Hawaii's UTC-10 offset wrapped a
	// Saturday parkrun back to Friday. T10:00:00Z keeps it on
	// Saturday. Pinned so a future "back to T08" refactor breaks
	// this test.
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), -10), '2026-04-15');
});

Deno.test('parseParkrunDate — known limit at UTC+14 (Samoa DST)', () => {
	// No single UTC hour can satisfy every offset in the 26-hour
	// worldwide range. Samoa during DST (UTC+14) is the documented
	// known exception. Pinning the actual behaviour so a future
	// "improve this" attempt has a clear baseline.
	assertEquals(localDateAt(parseParkrunDate('15/04/2026'), 14), '2026-04-16');
});

Deno.test('parseParkrunTime — HH:MM:SS parses to seconds', () => {
	assertEquals(parseParkrunTime('00:18:30'), 18 * 60 + 30);
});

Deno.test('parseParkrunTime — MM:SS parses to seconds', () => {
	assertEquals(parseParkrunTime('18:30'), 18 * 60 + 30);
});

Deno.test('parseParkrunTime — invalid input returns 0', () => {
	assertEquals(parseParkrunTime('nope'), 0);
});

Deno.test('parseParkrunTime — dash placeholder returns 0, not NaN', () => {
	// parkrun renders "--:--" (or "--:--:--") for an unknown / assisted
	// time. Number('--') is NaN; the unguarded map produced a NaN
	// duration_s that serialised to JSON null and broke the NOT NULL
	// insert. Must be a clean 0 (treated as "no usable time").
	assertEquals(parseParkrunTime('--:--'), 0);
	assertEquals(parseParkrunTime('--:--:--'), 0);
	assertEquals(Number.isNaN(parseParkrunTime('--:--')), false);
});

Deno.test('parseParkrunTime — non-numeric part returns 0', () => {
	assertEquals(parseParkrunTime('18:ab'), 0); // ['18','ab'] → [18, NaN]
	assertEquals(parseParkrunTime('ab:30'), 0);
});

Deno.test('parseParkrunTime — negative part is rejected', () => {
	assertEquals(parseParkrunTime('-1:00'), 0);
});
