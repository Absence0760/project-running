/// GoTrue send-email auth hook (config.toml [auth.hook.send_email]).
///
/// Replaces GoTrue's built-in English-only templates for signup
/// confirmation / recovery / magic link / invite / email change /
/// reauthentication with the project's localized, branded email
/// layout (docs/features/email.md), sent over the same SMTP transport
/// the Go worker uses (Mailpit locally, Resend / SES in prod).
///
/// Auth: Standard Webhooks signature over the raw body, keyed by
/// SEND_EMAIL_HOOK_SECRET (the same `v1,whsec_…` value GoTrue signs
/// with). `verify_jwt = false` in config.toml — GoTrue sends no
/// Supabase JWT; the signature is the gate and the function fails
/// closed without the secret.
///
/// The recipient's locale comes from user_settings.prefs.locale
/// (service-role read; decisions §120), falling back to the
/// signup-time user_metadata.locale, then English.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { withSentry } from '../_shared/sentry.ts';
import { makeAuthEmailHandler } from './handler.ts';
import { smtpSend } from './smtp.ts';

let admin: ReturnType<typeof createClient> | null = null;

function adminClient() {
  if (!admin) {
    admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
  }
  return admin;
}

const handler = makeAuthEmailHandler({
  getEnv: (name) => Deno.env.get(name),
  lookupLocale: async (userId) => {
    const { data, error } = await adminClient()
      .from('user_settings')
      .select('prefs')
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw new Error(error.code ?? 'settings_read_failed');
    const prefs = (data?.prefs ?? null) as Record<string, unknown> | null;
    const locale = prefs?.locale;
    return typeof locale === 'string' ? locale : null;
  },
  sendMime: (to, mime) =>
    smtpSend(
      {
        host: Deno.env.get('SMTP_HOST')!,
        port: Number.parseInt(Deno.env.get('SMTP_PORT') ?? '587', 10),
        username: Deno.env.get('SMTP_USERNAME') || undefined,
        password: Deno.env.get('SMTP_PASSWORD') || undefined,
        from: Deno.env.get('SMTP_FROM')!,
      },
      to,
      mime,
    ),
});

Deno.serve(withSentry('auth-email', handler));
