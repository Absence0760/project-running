/// Direct-invocation tests for the auth-email handler: a synthetic
/// Standard-Webhooks-signed Request driven through the FULL request
/// path with injected deps — no running stack, no network. Run with
/// `cd apps/backend && deno test supabase/functions/auth-email/handler.test.ts`.

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { makeAuthEmailHandler } from './handler.ts';
import { signSendEmailHook } from './lib.ts';

const SECRET = 'v1,whsec_' + btoa('0123456789abcdef0123456789abcdef');
const NOW = 1_750_000_000_000;

const BASE_ENV: Record<string, string> = {
  SEND_EMAIL_HOOK_SECRET: SECRET,
  SMTP_HOST: 'mail.local',
  SMTP_FROM: 'Threkir <noreply@threkir.com>',
  SUPABASE_URL: 'http://127.0.0.1:54321',
};

interface Recorded {
  to: string;
  mime: string;
}

function makeDeps(overrides: {
  env?: Record<string, string | undefined>;
  locale?: string | null;
  localeThrows?: boolean;
  sendThrows?: boolean;
}) {
  const env = { ...BASE_ENV, ...(overrides.env ?? {}) };
  const sent: Recorded[] = [];
  const localeCalls: string[] = [];
  const deps = {
    getEnv: (name: string) => env[name],
    lookupLocale: (userId: string) => {
      localeCalls.push(userId);
      if (overrides.localeThrows) {
        return Promise.reject(new Error('settings_read_failed'));
      }
      return Promise.resolve(overrides.locale ?? null);
    },
    sendMime: (to: string, mime: string) => {
      if (overrides.sendThrows) return Promise.reject(new Error('boom'));
      sent.push({ to, mime });
      return Promise.resolve();
    },
    now: () => NOW,
  };
  return { deps, sent, localeCalls };
}

async function signedRequest(
  payload: unknown,
  opts: { secret?: string; tamper?: boolean } = {},
): Promise<Request> {
  const body = JSON.stringify(payload);
  const ts = String(Math.floor(NOW / 1000));
  const sig = await signSendEmailHook(opts.secret ?? SECRET, 'msg_1', ts, body);
  return new Request('http://localhost/auth-email', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'webhook-id': 'msg_1',
      'webhook-timestamp': ts,
      'webhook-signature': sig,
    },
    body: opts.tamper ? body.replace('signup', 'recovery') : body,
  });
}

const SIGNUP_PAYLOAD = {
  user: {
    id: '11111111-1111-1111-1111-111111111111',
    email: 'runner@test.com',
    user_metadata: { locale: 'fr' },
  },
  email_data: {
    token: '123456',
    token_hash: 'pkce_hash',
    email_action_type: 'signup',
    redirect_to: 'http://localhost:7777/auth/callback',
    site_url: 'http://localhost:7777',
  },
};

Deno.test('handler — non-POST is 405', async () => {
  const { deps } = makeDeps({});
  const res = await makeAuthEmailHandler(deps)(
    new Request('http://localhost/auth-email', { method: 'GET' }),
  );
  assertEquals(res.status, 405);
});

Deno.test('handler — missing hook secret fails closed with 503', async () => {
  const { deps, sent } = makeDeps({ env: { SEND_EMAIL_HOOK_SECRET: undefined } });
  const res = await makeAuthEmailHandler(deps)(await signedRequest(SIGNUP_PAYLOAD));
  assertEquals(res.status, 503);
  assertEquals((await res.json()).error, 'hook_not_configured');
  assertEquals(sent.length, 0);
});

Deno.test('handler — bad signature is 401, nothing sent', async () => {
  const { deps, sent } = makeDeps({});
  const res = await makeAuthEmailHandler(deps)(
    await signedRequest(SIGNUP_PAYLOAD, { tamper: true }),
  );
  assertEquals(res.status, 401);
  assertEquals(sent.length, 0);
});

Deno.test('handler — unconfigured SMTP is 503 after a valid signature', async () => {
  const { deps, sent } = makeDeps({ env: { SMTP_HOST: undefined } });
  const res = await makeAuthEmailHandler(deps)(await signedRequest(SIGNUP_PAYLOAD));
  assertEquals(res.status, 503);
  assertEquals((await res.json()).error, 'smtp_not_configured');
  assertEquals(sent.length, 0);
});

Deno.test('handler — valid signup sends one localized mail with the verify link', async () => {
  const { deps, sent, localeCalls } = makeDeps({ locale: 'de' });
  const res = await makeAuthEmailHandler(deps)(await signedRequest(SIGNUP_PAYLOAD));
  assertEquals(res.status, 200);
  assertEquals(localeCalls, ['11111111-1111-1111-1111-111111111111']);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].to, 'runner@test.com');
  // user_settings locale (de) beats the metadata locale (fr).
  assertStringIncludes(sent[0].mime, btoa(new TextEncoder().encode('Bestätige deine Registrierung').reduce((s, b) => s + String.fromCharCode(b), '')));
  assertStringIncludes(
    sent[0].mime,
    'http://127.0.0.1:54321/auth/v1/verify?token=pkce_hash&type=signup&redirect_to=http://localhost:7777/auth/callback',
  );
});

Deno.test('handler — settings lookup failure falls back to metadata locale', async () => {
  const { deps, sent } = makeDeps({ localeThrows: true });
  const res = await makeAuthEmailHandler(deps)(await signedRequest(SIGNUP_PAYLOAD));
  assertEquals(res.status, 200);
  assertEquals(sent.length, 1);
  assertStringIncludes(sent[0].mime, 'Confirmez votre inscription');
});

Deno.test('handler — secure email change sends two mails', async () => {
  const { deps, sent } = makeDeps({ locale: 'en' });
  const res = await makeAuthEmailHandler(deps)(
    await signedRequest({
      user: {
        id: '11111111-1111-1111-1111-111111111111',
        email: 'old@test.com',
        new_email: 'new@test.com',
      },
      email_data: {
        token: '111111',
        token_hash: 'hash_new',
        token_new: '222222',
        token_hash_new: 'hash_current',
        email_action_type: 'email_change',
      },
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(sent.map((s) => s.to).sort(), ['new@test.com', 'old@test.com']);
});

Deno.test('handler — SMTP failure surfaces as 500 so GoTrue never thinks it sent', async () => {
  const { deps } = makeDeps({ sendThrows: true });
  const res = await makeAuthEmailHandler(deps)(await signedRequest(SIGNUP_PAYLOAD));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, 'send_failed');
});

Deno.test('handler — payload without a recipient is a 200 skip', async () => {
  const { deps, sent } = makeDeps({});
  const res = await makeAuthEmailHandler(deps)(
    await signedRequest({ user: {}, email_data: { email_action_type: 'signup' } }),
  );
  assertEquals(res.status, 200);
  assertEquals((await res.json()).skipped, 'no_recipient');
  assertEquals(sent.length, 0);
});

Deno.test('handler — invalid JSON after a valid signature is 400', async () => {
  const { deps } = makeDeps({});
  const body = 'not json';
  const ts = String(Math.floor(NOW / 1000));
  const sig = await signSendEmailHook(SECRET, 'msg_1', ts, body);
  const res = await makeAuthEmailHandler(deps)(
    new Request('http://localhost/auth-email', {
      method: 'POST',
      headers: {
        'webhook-id': 'msg_1',
        'webhook-timestamp': ts,
        'webhook-signature': sig,
      },
      body,
    }),
  );
  assertEquals(res.status, 400);
});

Deno.test('handler — oversized body is rejected before verification', async () => {
  const { deps } = makeDeps({});
  const res = await makeAuthEmailHandler(deps)(
    new Request('http://localhost/auth-email', {
      method: 'POST',
      body: 'x'.repeat(65 * 1024),
    }),
  );
  assert(res.status === 413 || res.status === 400);
});
