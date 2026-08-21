/// Chunked (tus) Storage upload sink for the Art 20 export.
///
/// The export used to assemble the whole archive as one in-memory Blob
/// and hand it to `storage.upload()`. That is what forced the two caps
/// the manifest had to apologise for — 5000 runs and 50,000 rows per
/// section — because a deep history's tracks alone run to hundreds of
/// megabytes and the function has a few hundred available. A cap that
/// exists to keep an allocation alive is not a data-minimisation
/// decision; it is a subject not receiving their data.
///
/// Supabase Storage speaks tus 1.0 at `/storage/v1/upload/resumable`,
/// so the archive can be pushed as it is produced and only one chunk is
/// ever resident. Every non-final chunk must be exactly 6 MiB — that is
/// the server's requirement, not a tunable — so this sink buffers to
/// that boundary and flushes.
///
/// Two properties matter more than throughput:
///
///   - **Fail closed.** tus materialises the object only once the
///     declared length has been received. A creation, PATCH or offset
///     mismatch throws, and the caller turns that into a 500 with no
///     artifact at all — so a run that died half-way can never present
///     a truncated archive as a complete one. That is the whole reason
///     the total length is declared on the FINAL chunk rather than
///     guessed up front.
///   - **The total length is not knowable up front.** A zip's size is
///     whatever the deflate stream turns out to be, so creation uses
///     tus's `creation-defer-length` and the last PATCH declares the
///     total. An archive that fits in a single chunk skips the deferral
///     entirely (the length IS known by then), which keeps the common
///     case on the plainest path the server offers.

const TUS_VERSION = '1.0.0';

/// 6 MiB. Supabase Storage requires every non-final tus chunk to be
/// exactly this size; it is a protocol constant, not a tuning knob.
export const TUS_CHUNK_BYTES = 6 * 1024 * 1024;

export interface ResumableUploadInit {
	/// Project URL (`SUPABASE_URL`), no trailing slash required.
	supabaseUrl: string;
	bucket: string;
	/// Object key inside the bucket, e.g. `{user_id}/exports/<ts>.zip`.
	objectPath: string;
	contentType: string;
	/// Auth headers — `secretKeyHeaders()` in production.
	headers: Record<string, string>;
	/// Overridable so tests can drive chunk boundaries without moving
	/// 6 MiB of bytes around. Production must leave it alone.
	chunkBytes?: number;
	fetchImpl?: typeof fetch;
}

export interface ResumableUpload {
	/// Buffer `bytes` and flush whole chunks. Throws on any transport
	/// or protocol failure; the caller must abandon the export.
	write(bytes: Uint8Array): Promise<void>;
	/// Flush the tail, declare the total length, and finalise.
	finish(): Promise<void>;
	/// Best-effort tus termination. Never throws — it runs on a path
	/// that is already failing.
	abort(): Promise<void>;
	/// Bytes the server has acknowledged.
	readonly uploaded: number;
}

function base64Utf8(v: string): string {
	const bytes = new TextEncoder().encode(v);
	let latin1 = '';
	for (const b of bytes) latin1 += String.fromCharCode(b);
	return btoa(latin1);
}

function encodeMetadata(pairs: Record<string, string>): string {
	return Object.entries(pairs)
		.map(([k, v]) => `${k} ${base64Utf8(v)}`)
		.join(',');
}

export function createResumableUpload(init: ResumableUploadInit): ResumableUpload {
	const doFetch = init.fetchImpl ?? fetch;
	const chunkBytes = init.chunkBytes && init.chunkBytes > 0 ? init.chunkBytes : TUS_CHUNK_BYTES;
	const createUrl = `${init.supabaseUrl.replace(/\/+$/, '')}/storage/v1/upload/resumable`;

	let pending: Uint8Array[] = [];
	let pendingBytes = 0;
	let uploaded = 0;
	let location: string | null = null;
	let deferred = false;
	let finished = false;

	const takeExactly = (n: number): Uint8Array => {
		const out = new Uint8Array(n);
		let filled = 0;
		while (filled < n) {
			const head = pending[0];
			const want = n - filled;
			if (head.length <= want) {
				out.set(head, filled);
				filled += head.length;
				pending.shift();
			} else {
				out.set(head.subarray(0, want), filled);
				pending[0] = head.subarray(want);
				filled = n;
			}
		}
		pendingBytes -= n;
		return out;
	};

	const create = async (declaredLength: number | null): Promise<void> => {
		const headers: Record<string, string> = {
			...init.headers,
			'Tus-Resumable': TUS_VERSION,
			'Upload-Metadata': encodeMetadata({
				bucketName: init.bucket,
				objectName: init.objectPath,
				contentType: init.contentType,
				cacheControl: '3600',
			}),
			// The export path carries a fresh timestamp per call, so a
			// collision means a duplicate request, not a re-upload.
			// Overwriting would let a retry clobber an archive whose
			// signed URL is already in the caller's hands.
			'x-upsert': 'false',
		};
		if (declaredLength == null) {
			headers['Upload-Defer-Length'] = '1';
			deferred = true;
		} else {
			headers['Upload-Length'] = String(declaredLength);
		}
		const res = await doFetch(createUrl, { method: 'POST', headers });
		if (res.status !== 201) {
			// Body is drained but not logged: a Storage error body can
			// carry the object key, and the key embeds the user id.
			await res.body?.cancel();
			throw new Error(`resumable create failed: ${res.status}`);
		}
		await res.body?.cancel();
		const loc = res.headers.get('location');
		if (!loc) throw new Error('resumable create returned no Location');
		location = new URL(loc, createUrl).toString();
	};

	const patch = async (chunk: Uint8Array, declareTotal: number | null): Promise<void> => {
		if (!location) throw new Error('resumable patch before create');
		const headers: Record<string, string> = {
			...init.headers,
			'Tus-Resumable': TUS_VERSION,
			'Upload-Offset': String(uploaded),
			'Content-Type': 'application/offset+octet-stream',
		};
		if (declareTotal != null && deferred) headers['Upload-Length'] = String(declareTotal);
		const res = await doFetch(location, {
			method: 'PATCH',
			headers,
			body: chunk,
		});
		if (res.status !== 204 && res.status !== 200) {
			await res.body?.cancel();
			throw new Error(`resumable patch failed at ${uploaded}: ${res.status}`);
		}
		await res.body?.cancel();
		const expected = uploaded + chunk.length;
		const reported = res.headers.get('upload-offset');
		// A server that acknowledges a different offset has a different
		// idea of the object than we do. Continuing would splice bytes
		// into the wrong place and produce a corrupt archive that still
		// finalised — the one outcome worse than failing.
		if (reported != null && Number(reported) !== expected) {
			throw new Error(`resumable offset mismatch: sent ${expected}, server ${reported}`);
		}
		uploaded = expected;
	};

	return {
		get uploaded() {
			return uploaded;
		},

		async write(bytes: Uint8Array): Promise<void> {
			if (finished) throw new Error('resumable write after finish');
			if (bytes.length === 0) return;
			pending.push(bytes);
			pendingBytes += bytes.length;
			// Strictly greater, not >=: the tail PATCH is what declares
			// the total length, so the buffer must never drain to empty
			// while more bytes may still arrive.
			while (pendingBytes > chunkBytes) {
				if (!location) await create(null);
				await patch(takeExactly(chunkBytes), null);
			}
		},

		async finish(): Promise<void> {
			if (finished) return;
			finished = true;
			const total = uploaded + pendingBytes;
			if (!location) await create(total);
			if (pendingBytes > 0) await patch(takeExactly(pendingBytes), total);
			pending = [];
			if (uploaded !== total) {
				throw new Error(`resumable finish short: ${uploaded} of ${total}`);
			}
		},

		async abort(): Promise<void> {
			pending = [];
			pendingBytes = 0;
			if (!location) return;
			try {
				const res = await doFetch(location, {
					method: 'DELETE',
					headers: { ...init.headers, 'Tus-Resumable': TUS_VERSION },
				});
				await res.body?.cancel();
			} catch (e) {
				console.error(
					'export-data: resumable abort failed:',
					e instanceof Error ? e.message : String(e),
				);
			}
		},
	};
}

/// A `WritableStream` over the sink, which is what `zip.js`'s
/// `ZipWriter` accepts in place of a `BlobWriter`. Closing the stream
/// finalises the upload; aborting it terminates the tus session, so a
/// zip-side failure leaves no object rather than a half-archive.
export function resumableWritable(upload: ResumableUpload): WritableStream<Uint8Array> {
	return new WritableStream<Uint8Array>({
		write(chunk) {
			return upload.write(chunk);
		},
		close() {
			return upload.finish();
		},
		abort() {
			return upload.abort();
		},
	});
}
