/// Body-size guards for Edge Functions that parse JSON bodies.
///
/// `req.json()` will happily await an arbitrarily large request body
/// before failing the parse — that means a malicious caller can force
/// every JSON-eating EF to allocate megabytes of UTF-8 + JSON parse
/// overhead per request. Supabase's edge runtime has its own ceiling
/// (~10 MB for incoming bodies), but each of our functions accepts a
/// payload that is at most a few hundred bytes in the legitimate case.
/// Cap aggressively at the application layer so we reject before
/// parsing.
///
/// Two entry points:
///
///   const tooBig = enforceBodyLimit(req, 16_384);  // sync header check only
///   if (tooBig) return tooBig;
///   const body = await req.json();                 // unbounded if header is absent
///
/// or, the safe form that closes the chunked-encoding bypass:
///
///   const guarded = await readJsonWithLimit(req, 16_384);
///   if (guarded.tooLarge) return guarded.tooLarge;
///   const body = guarded.body;                     // bounded regardless of header
///
/// Edge Functions that take a body and need genuine size guarantees
/// must use `readJsonWithLimit`. The bare `enforceBodyLimit` is
/// retained for callers that have an additional auth gate before the
/// parse (e.g. JWT-checked + then trust the runtime's 10 MB ceiling),
/// but new code should prefer the streamed reader.

export function enforceBodyLimit(req: Request, limitBytes: number): Response | null {
  const lenHeader = req.headers.get('content-length');
  if (!lenHeader) return null;
  const len = Number.parseInt(lenHeader, 10);
  if (!Number.isFinite(len) || len < 0) return null;
  if (len > limitBytes) {
    return new Response(
      JSON.stringify({ error: 'request body too large', max_bytes: limitBytes }),
      { status: 413, headers: { 'content-type': 'application/json' } },
    );
  }
  return null;
}

/// Read the request body, abort streaming once `limitBytes` is exceeded,
/// then JSON.parse the bounded slice. Closes the chunked-transfer-
/// encoding bypass that `enforceBodyLimit` alone leaves open: a caller
/// without `Content-Length` could otherwise stream up to the runtime
/// ceiling. The streamed reader cancels the source on overflow so the
/// remaining bytes never land in our process.
///
/// Discriminated-union return so callers can just spread:
///
///   const guarded = await readJsonWithLimit(req, 4096);
///   if ('tooLarge' in guarded) return guarded.tooLarge;
///   const body = guarded.body;
export async function readJsonWithLimit<T = unknown>(
  req: Request,
  limitBytes: number,
): Promise<{ body: T } | { tooLarge: Response }> {
  // Header fast path — reject before any byte arrives if Content-Length
  // is honest about an oversize payload.
  const tooBig = enforceBodyLimit(req, limitBytes);
  if (tooBig) return { tooLarge: tooBig };

  const tooLargeResponse = (): Response =>
    new Response(
      JSON.stringify({ error: 'request body too large', max_bytes: limitBytes }),
      { status: 413, headers: { 'content-type': 'application/json' } },
    );

  if (!req.body) {
    return { body: undefined as T };
  }

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > limitBytes) {
        try {
          await reader.cancel();
        } catch (_e) { /* swallow — we're already returning 413 */ }
        return { tooLarge: tooLargeResponse() };
      }
      chunks.push(value);
    }
  } finally {
    try {
      reader.releaseLock();
    } catch (_e) { /* swallow */ }
  }

  if (total === 0) {
    return { body: undefined as T };
  }

  const buf = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    buf.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const text = new TextDecoder().decode(buf);
  try {
    return { body: JSON.parse(text) as T };
  } catch (_e) {
    return {
      tooLarge: new Response(
        JSON.stringify({ error: 'invalid_json' }),
        { status: 400, headers: { 'content-type': 'application/json' } },
      ),
    };
  }
}

/// Same shape as `readJsonWithLimit` but returns the raw decoded text
/// instead of JSON-parsing. Used by webhook handlers that need to HMAC
/// the original bytes before deserialising — JSON.parse / stringify
/// won't round-trip whitespace and key ordering, so the HMAC must run
/// on the wire-format text.
export async function readTextWithLimit(
  req: Request,
  limitBytes: number,
): Promise<{ text: string } | { tooLarge: Response }> {
  const tooBig = enforceBodyLimit(req, limitBytes);
  if (tooBig) return { tooLarge: tooBig };

  const tooLargeResponse = (): Response =>
    new Response(
      JSON.stringify({ error: 'request body too large', max_bytes: limitBytes }),
      { status: 413, headers: { 'content-type': 'application/json' } },
    );

  if (!req.body) return { text: '' };

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > limitBytes) {
        try {
          await reader.cancel();
        } catch (_e) { /* swallow */ }
        return { tooLarge: tooLargeResponse() };
      }
      chunks.push(value);
    }
  } finally {
    try {
      reader.releaseLock();
    } catch (_e) { /* swallow */ }
  }

  if (total === 0) return { text: '' };
  const buf = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    buf.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { text: new TextDecoder().decode(buf) };
}
