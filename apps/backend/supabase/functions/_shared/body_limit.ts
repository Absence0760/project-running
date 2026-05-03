/// Body-size guard for Edge Functions that parse JSON bodies.
///
/// `req.json()` will happily await an arbitrarily large request body
/// before failing the parse — that means a malicious caller can force
/// every JSON-eating EF to allocate megabytes of UTF-8 + JSON parse
/// overhead per request. Supabase's edge runtime has its own ceiling
/// (~10 MB for incoming bodies), but each of our functions accepts a
/// payload that is at most a few hundred bytes in the legitimate
/// case. Cap aggressively at the application layer so we reject
/// before parsing.
///
///   const guard = enforceBodyLimit(req, 16_384);
///   if (guard) return guard;       // 413 with explanation
///   const body = await req.json(); // safe — at most LIMIT bytes
///
/// The Content-Length header is the only cheap pre-parse check
/// available in Deno's `serve`. A request without Content-Length
/// (chunked transfer-encoding) is allowed through but still bounded
/// by the runtime ceiling — practically every legitimate caller
/// (browser fetch, supabase-js, Dart http) sends the header.

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
