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
      console.error(`[${efName}] unhandled:`, err);
      if (enabled) {
        Sentry.withScope((scope) => {
          scope.setTag('ef', efName);
          Sentry.captureException(err);
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
    console.error(`[${efName}]`, err, ctx);
    return;
  }
  Sentry.withScope((scope) => {
    scope.setTag('ef', efName);
    if (ctx) for (const [k, v] of Object.entries(ctx)) scope.setExtra(k, v);
    Sentry.captureException(err);
  });
}
