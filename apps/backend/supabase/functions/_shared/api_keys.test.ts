import {
  assertEquals,
  assertThrows,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { publishableKey, secretKey, secretKeyHeaders } from './api_keys.ts';

const VARS = [
  'SUPABASE_SECRET_KEYS',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_PUBLISHABLE_KEYS',
  'SUPABASE_ANON_KEY',
];

function withEnv(env: Record<string, string>, fn: () => void) {
  const saved = new Map(VARS.map((v) => [v, Deno.env.get(v)]));
  try {
    for (const v of VARS) Deno.env.delete(v);
    for (const [k, val] of Object.entries(env)) Deno.env.set(k, val);
    fn();
  } finally {
    for (const [k, val] of saved) {
      if (val === undefined) Deno.env.delete(k);
      else Deno.env.set(k, val);
    }
  }
}

Deno.test('secretKey prefers the named default in SUPABASE_SECRET_KEYS', () => {
  withEnv({
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_new', other: 'sb_secret_x' }),
    SUPABASE_SERVICE_ROLE_KEY: 'legacy-jwt',
  }, () => {
    assertEquals(secretKey(), 'sb_secret_new');
  });
});

Deno.test('secretKey takes the first named key when no default exists', () => {
  withEnv({
    SUPABASE_SECRET_KEYS: JSON.stringify({ rotated: 'sb_secret_rotated' }),
  }, () => {
    assertEquals(secretKey(), 'sb_secret_rotated');
  });
});

Deno.test('secretKey falls back to the legacy var when the new var is absent', () => {
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: 'legacy-jwt' }, () => {
    assertEquals(secretKey(), 'legacy-jwt');
  });
});

Deno.test('secretKey falls back to the legacy var on malformed JSON', () => {
  withEnv({
    SUPABASE_SECRET_KEYS: 'not-json',
    SUPABASE_SERVICE_ROLE_KEY: 'legacy-jwt',
  }, () => {
    assertEquals(secretKey(), 'legacy-jwt');
  });
});

Deno.test('secretKey throws when no source yields a key', () => {
  withEnv({}, () => {
    assertThrows(() => secretKey());
  });
});

Deno.test('publishableKey prefers SUPABASE_PUBLISHABLE_KEYS over the legacy anon var', () => {
  withEnv({
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: 'sb_publishable_new' }),
    SUPABASE_ANON_KEY: 'legacy-anon-jwt',
  }, () => {
    assertEquals(publishableKey(), 'sb_publishable_new');
  });
});

Deno.test('publishableKey falls back to the legacy anon var', () => {
  withEnv({ SUPABASE_ANON_KEY: 'legacy-anon-jwt' }, () => {
    assertEquals(publishableKey(), 'legacy-anon-jwt');
  });
});

Deno.test('secretKeyHeaders sends a legacy JWT as apikey + bearer', () => {
  withEnv({ SUPABASE_SERVICE_ROLE_KEY: 'legacy-jwt' }, () => {
    assertEquals(secretKeyHeaders(), {
      apikey: 'legacy-jwt',
      Authorization: 'Bearer legacy-jwt',
    });
  });
});

Deno.test('secretKeyHeaders sends an sb_secret key as apikey alone', () => {
  withEnv({
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_new' }),
  }, () => {
    assertEquals(secretKeyHeaders(), { apikey: 'sb_secret_new' });
  });
});
