/// Sentry helper for Edge Functions.
///
/// Wraps a `serve` handler with try/catch + `Sentry.captureException` so
/// unhandled errors land tagged with the EF name and the deployment's
/// `APP_RELEASE`. Off when `SENTRY_DSN` is unset (local dev) — falls back
/// to a passthrough so EFs don't carry an init-failure path.
///
/// Usage:
///
///   import { withSentry } from '../_shared/sentry.ts';
///   serve(withSentry('parkrun-import', async (req) => { ... }));

import * as Sentry from 'https://deno.land/x/sentry@8.40.0/index.mjs';
import { sanitizeErrorForCapture } from './sentry_scrub.ts';

let _initialized = false;

function ensureInit(): boolean {
  if (_initialized) return true;
  const dsn = Deno.env.get('SENTRY_DSN');
  if (!dsn) return false;
  Sentry.init({
    dsn,
    release: Deno.env.get('APP_RELEASE') ?? 'dev',
    environment: Deno.env.get('APP_RELEASE') && Deno.env.get('APP_RELEASE') !== 'dev'
      ? 'production'
      : 'development',
    tracesSampleRate: 0.1,
    // Data minimisation under the legitimate-interest basis (see
    // sentry_scrub.ts): never attach default PII (IP, headers), and drop
    // the request envelope (cookies / JWT / body / query) from any event
    // that picks it up. The row-bearing PostgREST details/hint are
    // stripped at capture time by sanitizeErrorForCapture below.
    sendDefaultPii: false,
    beforeSend: (event) => {
      delete event.request;
      delete event.user;
      delete event.server_name;
      return event;
    },
  });
  _initialized = true;
  return true;
}

export function withSentry(
  efName: string,
  handler: (req: Request) => Promise<Response> | Response,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const enabled = ensureInit();
    try {
      return await handler(req);
    } catch (err) {
      // Both sinks stay narrow on row data. Postgrest errors carry
      // `details` + `hint` fields that can leak column names, constraint
      // names, or partial row values: the console path logs only the
      // message string, and the Sentry path runs the error through
      // sanitizeErrorForCapture (message + SQLSTATE only, details/hint
      // dropped) — so neither sink exports the offending row to a
      // third party. /audit/all edge-functions Low + audit-findings
      // 2026-05-30 High (third-party-data-flows).
      console.error(
        `[${efName}] unhandled:`,
        err instanceof Error ? err.message : String(err),
      );
      if (enabled) {
        Sentry.withScope((scope) => {
          scope.setTag('ef', efName);
          Sentry.captureException(sanitizeErrorForCapture(err));
        });
        await Sentry.flush(2000);
      }
      return new Response(
        JSON.stringify({ error: 'internal_error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      );
    }
  };
}

export function captureException(err: unknown, efName: string, ctx?: Record<string, unknown>) {
  if (!ensureInit()) {
    console.error(
      `[${efName}]`,
      err instanceof Error ? err.message : String(err),
      ctx,
    );
    return;
  }
  Sentry.withScope((scope) => {
    scope.setTag('ef', efName);
    if (ctx) for (const [k, v] of Object.entries(ctx)) scope.setExtra(k, v);
    Sentry.captureException(sanitizeErrorForCapture(err));
  });
}
