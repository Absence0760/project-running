/// Request handler for the auth-email send-email hook, factored out of
/// index.ts behind injected deps (env lookup, locale lookup, SMTP send)
/// so a deno test can drive the FULL request path — signature check,
/// payload parse, locale pick, render, send — with a synthetic signed
/// Request and no running stack.
///
/// Fail-closed like the other webhook EFs: no hook secret → 503, bad
/// signature → 401, unconfigured SMTP → 503. GoTrue surfaces a hook
/// failure to the auth API caller, so a 5xx here means "the email was
/// not sent" — never a silent drop.

import { readTextWithLimit } from '../_shared/body_limit.ts';
import {
  type HookEmailData,
  type HookUser,
  buildMime,
  planSends,
  renderAuthEmail,
  resolveAuthEmailLocale,
  verifySendEmailHook,
} from './lib.ts';

export interface AuthEmailDeps {
  getEnv: (name: string) => string | undefined;
  lookupLocale: (userId: string) => Promise<string | null>;
  sendMime: (to: string, mime: string) => Promise<void>;
  now?: () => number;
}

export function makeAuthEmailHandler(
  deps: AuthEmailDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method !== 'POST') {
      return Response.json({ error: 'method_not_allowed' }, { status: 405 });
    }

    const guarded = await readTextWithLimit(req, 64 * 1024);
    if ('tooLarge' in guarded) return guarded.tooLarge;
    const body = guarded.text;

    const secret = deps.getEnv('SEND_EMAIL_HOOK_SECRET');
    if (!secret) {
      return Response.json({ error: 'hook_not_configured' }, { status: 503 });
    }

    const outcome = await verifySendEmailHook(
      body,
      {
        id: req.headers.get('webhook-id'),
        timestamp: req.headers.get('webhook-timestamp'),
        signature: req.headers.get('webhook-signature'),
      },
      secret,
      (deps.now ?? Date.now)(),
    );
    if (outcome !== 'ok') {
      return Response.json({ error: outcome }, { status: 401 });
    }

    const smtpHost = deps.getEnv('SMTP_HOST');
    const smtpFrom = deps.getEnv('SMTP_FROM');
    if (!smtpHost || !smtpFrom) {
      return Response.json({ error: 'smtp_not_configured' }, { status: 503 });
    }

    let payload: { user?: HookUser; email_data?: HookEmailData };
    try {
      payload = JSON.parse(body);
    } catch {
      return Response.json({ error: 'invalid_json' }, { status: 400 });
    }
    const user = payload.user ?? {};
    const emailData = payload.email_data ?? {};

    const sends = planSends(user, emailData);
    if (sends.length === 0) {
      return Response.json({ ok: true, skipped: 'no_recipient' });
    }

    // Locale lookup is auxiliary — a failed settings read must not block
    // an auth email, it just falls back to the signup-time metadata
    // locale, then English.
    let settingsLocale: string | null = null;
    if (user.id) {
      try {
        settingsLocale = await deps.lookupLocale(user.id);
      } catch (err) {
        console.error(
          'auth-email locale lookup failed:',
          err instanceof Error ? err.message : 'unknown',
        );
      }
    }
    const locale = resolveAuthEmailLocale(
      settingsLocale,
      user.user_metadata?.locale,
    );

    const supabaseUrl = deps.getEnv('SUPABASE_URL') ?? emailData.site_url ?? '';

    for (const send of sends) {
      const rendered = renderAuthEmail(locale, send, {
        supabaseUrl,
        redirectTo: emailData.redirect_to,
      });
      const mime = buildMime(
        smtpFrom,
        send.to,
        rendered,
        new Date((deps.now ?? Date.now)()).toUTCString(),
      );
      try {
        await deps.sendMime(send.to, mime);
      } catch (err) {
        // Action type only — never the recipient address (PII-in-logs
        // rule; these lines land in the shared function-log aggregator).
        console.error(
          `auth-email send failed (${send.catalogueKey}):`,
          err instanceof Error ? err.message : 'unknown',
        );
        return Response.json({ error: 'send_failed' }, { status: 500 });
      }
    }

    return Response.json({});
  };
}
