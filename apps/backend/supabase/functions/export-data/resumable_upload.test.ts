// Boundary tests for the chunked (tus) Storage sink the Art 20 export
// streams its archive through. No network: every case drives a fake
// fetch and asserts the protocol the sink speaks.

import {
	assert,
	assertEquals,
	assertRejects,
	assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { ZipReader } from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import { ZipWriter } from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import { TextReader } from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import { Uint8ArrayReader } from 'https://deno.land/x/zipjs@v2.7.45/index.js';
import {
	createResumableUpload,
	resumableWritable,
	TUS_CHUNK_BYTES,
} from './resumable_upload.ts';

interface Call {
	method: string;
	url: string;
	headers: Record<string, string>;
	bytes: number;
}

interface Recorder {
	calls: Call[];
	received: number[];
	body: Uint8Array;
}

function fakeStorage(
	opts: { failPatchAt?: number; createStatus?: number; offsetLie?: number } = {},
) {
	const rec: Recorder = { calls: [], received: [], body: new Uint8Array(0) };
	let offset = 0;
	let patches = 0;
	const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
		const url = String(input);
		const method = init?.method ?? 'GET';
		const headers = Object.fromEntries(
			Object.entries((init?.headers ?? {}) as Record<string, string>)
				.map(([k, v]) => [k.toLowerCase(), v]),
		);
		const bodyBytes = init?.body instanceof Blob
			? new Uint8Array(await init.body.arrayBuffer())
			: new Uint8Array(0);
		rec.calls.push({ method, url, headers, bytes: bodyBytes.length });
		if (method === 'POST') {
			const status = opts.createStatus ?? 201;
			return new Response(null, {
				status,
				headers: status === 201 ? { Location: `${url}/upload-1` } : {},
			});
		}
		if (method === 'PATCH') {
			patches++;
			if (opts.failPatchAt != null && patches === opts.failPatchAt) {
				return new Response(null, { status: 500 });
			}
			const merged = new Uint8Array(rec.body.length + bodyBytes.length);
			merged.set(rec.body);
			merged.set(bodyBytes, rec.body.length);
			rec.body = merged;
			rec.received.push(bodyBytes.length);
			offset += bodyBytes.length;
			const reported = opts.offsetLie != null && patches === 1 ? opts.offsetLie : offset;
			return new Response(null, {
				status: 204,
				headers: { 'Upload-Offset': String(reported) },
			});
		}
		return new Response(null, { status: 204 });
	}) as unknown as typeof fetch;
	return { rec, fetchImpl };
}

function sink(fetchImpl: typeof fetch, chunkBytes: number) {
	return createResumableUpload({
		supabaseUrl: 'https://proj.supabase.co/',
		bucket: 'runs',
		objectPath: 'user-1/exports/2026-08-21.zip',
		contentType: 'application/zip',
		headers: { apikey: 'k' },
		chunkBytes,
		fetchImpl,
	});
}

Deno.test('empty export declares length 0 and uploads no chunk', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 16);
	await up.finish();
	assertEquals(rec.calls.map((c) => c.method), ['POST']);
	assertEquals(rec.calls[0].headers['upload-length'], '0');
	assert(
		!('upload-defer-length' in rec.calls[0].headers),
		'an empty archive has a known length; deferral buys nothing',
	);
	assertEquals(up.uploaded, 0);
});

Deno.test('an archive that fits one chunk declares its length up front', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 16);
	await up.write(new Uint8Array(10).fill(7));
	// Below the boundary, so nothing has been flushed yet.
	assertEquals(rec.calls.length, 0);
	await up.finish();
	assertEquals(rec.calls.map((c) => c.method), ['POST', 'PATCH']);
	assertEquals(rec.calls[0].headers['upload-length'], '10');
	assert(!('upload-defer-length' in rec.calls[0].headers));
	assertEquals(rec.received, [10]);
	assertEquals(up.uploaded, 10);
});

Deno.test('exactly one chunk of bytes stays a single-chunk upload', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 16);
	await up.write(new Uint8Array(16).fill(1));
	// Strictly-greater flush: 16 bytes at a 16-byte boundary must not
	// drain the buffer, or there would be no tail PATCH left to carry
	// the declared total.
	assertEquals(rec.calls.length, 0);
	await up.finish();
	assertEquals(rec.received, [16]);
	assertEquals(rec.calls[0].headers['upload-length'], '16');
});

Deno.test('multi-chunk upload defers the length and declares it on the tail', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 16);
	await up.write(new Uint8Array(40).fill(3));
	assertEquals(rec.received, [16, 16], 'whole chunks flush as they fill');
	assertEquals(rec.calls[0].headers['upload-defer-length'], '1');
	assert(!('upload-length' in rec.calls[0].headers));
	const patchesBeforeFinish = rec.calls.filter((c) => c.method === 'PATCH');
	for (const p of patchesBeforeFinish) {
		assert(
			!('upload-length' in p.headers),
			'only the final chunk may declare the total',
		);
		assertEquals(p.bytes, 16, 'every non-final chunk is exactly one chunk');
	}
	await up.finish();
	assertEquals(rec.received, [16, 16, 8]);
	const last = rec.calls[rec.calls.length - 1];
	assertEquals(last.headers['upload-length'], '40');
	assertEquals(last.headers['upload-offset'], '32');
	assertEquals(up.uploaded, 40);
});

Deno.test('one oversized write is split on chunk boundaries', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 8);
	await up.write(new Uint8Array(30).fill(9));
	await up.finish();
	assertEquals(rec.received, [8, 8, 8, 6]);
	assertEquals(rec.body.length, 30);
});

Deno.test('many small writes coalesce into whole chunks', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 10);
	for (let i = 0; i < 25; i++) await up.write(new Uint8Array(1).fill(i));
	await up.finish();
	assertEquals(rec.received, [10, 10, 5]);
	assertEquals(rec.body.length, 25);
	assertEquals([...rec.body.slice(0, 3)], [0, 1, 2]);
});

Deno.test('a mid-stream chunk failure throws and never declares a length', async () => {
	const { rec, fetchImpl } = fakeStorage({ failPatchAt: 2 });
	const up = sink(fetchImpl, 8);
	await assertRejects(
		() => up.write(new Uint8Array(40)),
		Error,
		'resumable patch failed at 8',
	);
	// The object only materialises once the declared length arrives, so
	// a failed run leaves nothing a caller could mistake for complete.
	assert(
		!rec.calls.some((c) => 'upload-length' in c.headers),
		'a failed upload must never declare its total length',
	);
});

Deno.test('a creation failure throws before any byte moves', async () => {
	const { rec, fetchImpl } = fakeStorage({ createStatus: 409 });
	const up = sink(fetchImpl, 8);
	await assertRejects(
		() => up.write(new Uint8Array(20)),
		Error,
		'resumable create failed: 409',
	);
	assertEquals(rec.calls.filter((c) => c.method === 'PATCH').length, 0);
});

Deno.test('a disagreeing server offset aborts rather than splicing bytes', async () => {
	const { fetchImpl } = fakeStorage({ offsetLie: 4 });
	const up = sink(fetchImpl, 8);
	await assertRejects(
		() => up.write(new Uint8Array(20)),
		Error,
		'resumable offset mismatch',
	);
});

Deno.test('abort terminates the tus session and swallows its own failure', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 8);
	await up.write(new Uint8Array(20));
	await up.abort();
	const del = rec.calls.filter((c) => c.method === 'DELETE');
	assertEquals(del.length, 1);
	assertEquals(del[0].headers['tus-resumable'], '1.0.0');

	const boom = (() => {
		throw new Error('network down');
	}) as unknown as typeof fetch;
	const up2 = createResumableUpload({
		supabaseUrl: 'https://proj.supabase.co',
		bucket: 'runs',
		objectPath: 'u/e.zip',
		contentType: 'application/zip',
		headers: {},
		chunkBytes: 8,
		fetchImpl: boom,
	});
	await up2.abort();
});

Deno.test('creation carries the tus metadata Storage keys off', async () => {
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 16);
	await up.finish();
	const meta = rec.calls[0].headers['upload-metadata'];
	assertStringIncludes(meta, `bucketName ${btoa('runs')}`);
	assertStringIncludes(meta, `objectName ${btoa('user-1/exports/2026-08-21.zip')}`);
	assertStringIncludes(meta, `contentType ${btoa('application/zip')}`);
	assertEquals(rec.calls[0].headers['x-upsert'], 'false');
	assertEquals(rec.calls[0].url, 'https://proj.supabase.co/storage/v1/upload/resumable');
	assertEquals(up.uploaded, 0);
});

Deno.test('write after finish is refused', async () => {
	const { fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 16);
	await up.finish();
	await assertRejects(() => up.write(new Uint8Array(1)), Error, 'write after finish');
});

Deno.test('the production chunk size is the 6 MiB Storage requires', () => {
	assertEquals(TUS_CHUNK_BYTES, 6 * 1024 * 1024);
});

Deno.test('a real zip streamed through the sink round-trips', async () => {
	// The point of the sink is that ZipWriter can target it instead of a
	// BlobWriter. Chunking at 64 bytes forces many boundaries inside
	// entry data, headers and the central directory, then the assembled
	// bytes are re-read to prove nothing was spliced wrong.
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 64);
	const zip = new ZipWriter(resumableWritable(up));
	await zip.add('manifest.json', new TextReader(JSON.stringify({ complete: true })));
	await zip.add('big.bin', new Uint8ArrayReader(new Uint8Array(5000).fill(0xab)), { level: 0 });
	await zip.add('runs.json', new TextReader('[\n{"id":"r-1"}\n]\n'));
	await zip.close();

	assert(rec.received.length > 2, 'a 5 KB archive at a 64-byte chunk must be multi-chunk');
	for (const n of rec.received.slice(0, -1)) assertEquals(n, 64);
	assertEquals(rec.body.length, up.uploaded);

	const reader = new ZipReader(new Uint8ArrayReader(rec.body));
	const entries = await reader.getEntries();
	assertEquals(entries.map((e: { filename: string }) => e.filename).sort(), [
		'big.bin',
		'manifest.json',
		'runs.json',
	]);
	await reader.close();
});

Deno.test('an entry streamed from a ReadableStream needs no known size', async () => {
	// Section files are produced page by page, so their length is not
	// known when the entry opens. zip.js writes a data descriptor, which
	// is what makes a forward-only sink legal at all.
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 32);
	const zip = new ZipWriter(resumableWritable(up));
	const enc = new TextEncoder();
	let page = 0;
	const stream = new ReadableStream<Uint8Array>({
		pull(controller) {
			if (page === 3) {
				controller.close();
				return;
			}
			controller.enqueue(enc.encode(`page-${page++}\n`));
		},
	});
	await zip.add('food_log.json', stream);
	await zip.close();

	const reader = new ZipReader(new Uint8ArrayReader(rec.body));
	const entries = await reader.getEntries();
	assertEquals(entries.length, 1);
	const text = await entries[0].getData!(
		new (await import('https://deno.land/x/zipjs@v2.7.45/index.js')).TextWriter(),
	);
	assertEquals(text, 'page-0\npage-1\npage-2\n');
	await reader.close();
});

Deno.test('tens of thousands of tiny writes stay linear and byte-exact', async () => {
	// A CSV export hands the sink one small array per run, so the pending
	// queue is compacted by a head index rather than shifted piece by
	// piece — 100k runs through a shift() queue is quadratic.
	const { rec, fetchImpl } = fakeStorage();
	const up = sink(fetchImpl, 4096);
	const started = Date.now();
	for (let i = 0; i < 60_000; i++) await up.write(new Uint8Array([i & 0xff]));
	await up.finish();
	assertEquals(rec.body.length, 60_000);
	assertEquals(up.uploaded, 60_000);
	assertEquals(rec.body[59_999], 59_999 & 0xff);
	for (const n of rec.received.slice(0, -1)) assertEquals(n, 4096);
	assert(Date.now() - started < 10_000, 'the pending queue is not linear');
});
