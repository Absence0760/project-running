import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	MAX_PARKRUN_FIELD_LEN,
	MAX_PARKRUN_HTML_BYTES,
	MAX_PARKRUN_ROWS,
	capParkrunField,
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
