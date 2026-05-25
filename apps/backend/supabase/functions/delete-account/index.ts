import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2.105.1';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  type DeletionAuditResult,
  FCM_BATCH_REMOVE_URL,
  STRAVA_DEAUTHORIZE_URL,
  fcmBatchRemoveBody,
  hashUserIdForAudit,
  revenueCatSubscriberUrl,
} from './lib.ts';

const PAGE = 1000;

// Recursively delete every blob under `prefix` in `bucket`. Supabase
// Storage's `list` returns subdirectory pseudo-entries (id = null)
// alongside files; bulk-removing those entries is a no-op against
// flat object keys, so we filter them out and recurse explicitly.
// Without this, `${user.id}/exports/<ts>.{csv,zip}` blobs survive
// account deletion even though the parent prefix is "drained" — a
// privacy-deletion failure mode that audit/storage pass 3 caught.
//
// Throws on any list / remove error so the caller can abort before
// dropping the auth user. A partial Storage drain followed by the
// auth-row cascade orphans blobs with no row to point at them — a
// privacy-deletion silent failure that the user can't observe and
// can't retry (their auth row is already gone).
async function deletePrefix(
  client: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<void> {
  while (true) {
    const { data: entries, error: listErr } = await client.storage
      .from(bucket)
      .list(prefix, { limit: PAGE });
    if (listErr) {
      throw new Error(`list ${bucket}/${prefix} failed: ${listErr.message}`);
    }
    if (!entries || entries.length === 0) break;

    const files = entries.filter((e) => e.id !== null);
    const folders = entries.filter((e) => e.id === null);

    if (files.length > 0) {
      const { error: rmErr } = await client.storage
        .from(bucket)
        .remove(files.map((f) => `${prefix}/${f.name}`));
      if (rmErr) {
        throw new Error(`remove in ${bucket}/${prefix} failed: ${rmErr.message}`);
      }
    }
    for (const folder of folders) {
      await deletePrefix(client, bucket, `${prefix}/${folder.name}`);
    }

    if (entries.length < PAGE) break;
  }
}

// Best-effort third-party cleanup. Each helper logs + swallows on
// failure — none of these are allowed to abort the deletion (we
// can't strand a user mid-erasure if a third party is down), but
// every failure shows up in Sentry / function logs so an operator
// can replay the cleanup later if needed.

async function deauthorizeStrava(
  adminClient: SupabaseClient,
  userId: string,
): Promise<void> {
  // 20260603_001_integrations_vault stores Strava tokens in vault.
  // We need the access token to call deauthorize; fetch via the
  // get_integration_tokens RPC (SECURITY DEFINER, gated to caller =
  // owner, which is true here because we run as service_role).
  let accessToken: string | null = null;
  try {
    const { data, error } = await adminClient
      .from('integrations')
      .select('access_token_secret_id')
      .eq('user_id', userId)
      .eq('provider', 'strava')
      .maybeSingle();
    if (error || !data?.access_token_secret_id) return;
    const { data: secret } = await adminClient
      .schema('vault')
      .from('decrypted_secrets')
      .select('decrypted_secret')
      .eq('id', data.access_token_secret_id)
      .maybeSingle();
    if (secret?.decrypted_secret) accessToken = secret.decrypted_secret;
  } catch (e) {
    console.error(
      'delete-account: strava token lookup failed:',
      e instanceof Error ? e.message : String(e),
    );
    return;
  }
  if (!accessToken) return;
  try {
    await fetch(STRAVA_DEAUTHORIZE_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch (e) {
    console.error(
      'delete-account: strava deauthorize failed:',
      e instanceof Error ? e.message : String(e),
    );
  }
}

async function deleteRevenueCatSubscriber(userId: string): Promise<void> {
  const apiKey = Deno.env.get('REVENUECAT_SECRET_API_KEY');
  if (!apiKey) return;
  try {
    await fetch(revenueCatSubscriberUrl(userId), {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${apiKey}` },
    });
  } catch (e) {
    console.error(
      'delete-account: revenuecat delete failed:',
      e instanceof Error ? e.message : String(e),
    );
  }
}

async function invalidateFcmTokens(
  adminClient: SupabaseClient,
  userId: string,
): Promise<void> {
  const fcmServerKey = Deno.env.get('FCM_SERVER_KEY');
  if (!fcmServerKey) return;
  let tokens: string[] = [];
  try {
    const { data } = await adminClient
      .from('device_tokens')
      .select('token')
      .eq('user_id', userId)
      .eq('platform', 'android');
    tokens = (data ?? []).map((r: { token: string }) => r.token);
  } catch (e) {
    console.error(
      'delete-account: device_tokens lookup failed:',
      e instanceof Error ? e.message : String(e),
    );
    return;
  }
  if (tokens.length === 0) return;
  try {
    await fetch(FCM_BATCH_REMOVE_URL, {
      method: 'POST',
      headers: {
        Authorization: `key=${fcmServerKey}`,
        'content-type': 'application/json',
      },
      body: fcmBatchRemoveBody(tokens),
    });
  } catch (e) {
    console.error(
      'delete-account: fcm batchRemove failed:',
      e instanceof Error ? e.message : String(e),
    );
  }
}

// Vault holds Strava access + refresh tokens (20260603_001). The
// integrations row's FK to vault.secrets is `on delete set null`, so
// the cascade from auth.users -> integrations leaves the secrets
// orphaned. Explicit cleanup before the cascade.
async function cleanupVaultSecrets(
  adminClient: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  try {
    const { data, error } = await adminClient
      .from('integrations')
      .select('access_token_secret_id, refresh_token_secret_id')
      .eq('user_id', userId);
    if (error) return { ok: false, reason: error.message };
    const ids = new Set<string>();
    for (const row of data ?? []) {
      if (row.access_token_secret_id) ids.add(row.access_token_secret_id);
      if (row.refresh_token_secret_id) ids.add(row.refresh_token_secret_id);
    }
    if (ids.size === 0) return { ok: true };
    const { error: delErr } = await adminClient
      .schema('vault')
      .from('secrets')
      .delete()
      .in('id', [...ids]);
    if (delErr) return { ok: false, reason: delErr.message };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : String(e) };
  }
}

// `reports.target_id` is polymorphic (UUID with no FK because the
// target can be a user / club / route). When target_kind = 'user',
// the row stores the deleted user's id indefinitely — no cascade.
// Delete those rows explicitly before the auth-row cascade so the
// UUID doesn't outlive the user.
async function deleteUserReports(
  adminClient: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  try {
    const { error } = await adminClient
      .from('reports')
      .delete()
      .eq('target_kind', 'user')
      .eq('target_id', userId);
    if (error) return { ok: false, reason: error.message };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : String(e) };
  }
}

async function recordAudit(
  adminClient: SupabaseClient,
  userId: string,
  result: DeletionAuditResult,
  notes: string | null = null,
): Promise<void> {
  try {
    const hashed = await hashUserIdForAudit(userId);
    await adminClient
      .from('deletion_audit_log')
      .insert({ hashed_user_id: hashed, result, notes });
  } catch (e) {
    // Best-effort. The audit log is a regulator-evidence trail; if
    // the write itself fails we still want the delete to complete.
    console.error(
      'delete-account: audit log write failed:',
      e instanceof Error ? e.message : String(e),
    );
  }
}

serve(withSentry('delete-account', async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // delete-account takes no body — clamp tightly. The streamed reader
  // closes the chunked-transfer-encoding bypass that the bare header
  // check left open.
  const guarded = await readJsonWithLimit(req, 256);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

  // 3/hour. Destructive endpoint, but we want a typo or double-tap
  // to fail fast rather than panic-spam-cancelling. Once a delete
  // succeeds the user's auth row is gone, so subsequent calls 401.
  // Fail-closed: if the rate-limit RPC errors we 503 rather than
  // letting unbounded delete attempts through (the throttle is the
  // only thing between a stolen JWT and account-destruction spam).
  const denied = await checkRateLimit(userClient, user.id, 'delete-account', 3, 3600, {
    failClosed: true,
  });
  if (denied) return denied;

  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // ─── Best-effort third-party cleanups ───
  // Each of these can fail without aborting the delete (a stale
  // Strava token, an offline RevenueCat, FCM down — none of these
  // should strand a user mid-erasure). Errors are logged but
  // swallowed. Order: do them BEFORE the auth-row cascade so the
  // integrations / device_tokens rows still exist for the lookups.
  await deauthorizeStrava(adminClient, user.id);
  await deleteRevenueCatSubscriber(user.id);
  await invalidateFcmTokens(adminClient, user.id);

  // ─── Mandatory cleanups before the cascade ───
  // These leak personal data past the auth-row cascade, so failure
  // must abort + leave the auth row intact (the user can retry).

  // vault.secrets — Strava access + refresh tokens stored via
  // 20260603_001. The integrations FK is `on delete set null`,
  // not cascade, so the cascade orphans the secrets.
  const vault = await cleanupVaultSecrets(adminClient, user.id);
  if (!vault.ok) {
    console.error('delete-account: vault cleanup failed:', vault.reason);
    await recordAudit(
      adminClient,
      user.id,
      'vault_cleanup_failed',
      vault.reason.slice(0, 200),
    );
    return Response.json({ error: 'vault cleanup failed' }, { status: 500 });
  }

  // reports.target_id (polymorphic, no FK). Stores the user's id
  // when target_kind = 'user'; orphans the UUID indefinitely if
  // we don't delete first.
  const reports = await deleteUserReports(adminClient, user.id);
  if (!reports.ok) {
    console.error('delete-account: reports cleanup failed:', reports.reason);
    await recordAudit(
      adminClient,
      user.id,
      'reports_cleanup_failed',
      reports.reason.slice(0, 200),
    );
    return Response.json({ error: 'reports cleanup failed' }, { status: 500 });
  }

  // Delete Storage files. The `runs` bucket holds gzipped tracks +
  // per-user export blobs at `{user.id}/exports/<ts>.{csv,zip}`; the
  // `run-photos` bucket holds run photos. deletePrefix recurses
  // through pseudo-folders so the exports/ subdirectory is fully
  // drained alongside the top-level tracks. A partial drain followed
  // by the auth-row cascade orphans blobs with no row to point at
  // them, so we abort before deleting the auth user — the user can
  // retry once Storage recovers.
  try {
    for (const bucket of ['runs', 'run-photos']) {
      await deletePrefix(adminClient, bucket, user.id);
    }
  } catch (err) {
    console.error(
      'delete-account: Storage drain failed:',
      err instanceof Error ? err.message : String(err),
    );
    await recordAudit(
      adminClient,
      user.id,
      'storage_drain_failed',
      (err instanceof Error ? err.message : String(err)).slice(0, 200),
    );
    return Response.json(
      { error: 'storage drain failed' },
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  // Best-effort avatars-bucket drain. audit/account-deletion-
  // completeness (May 2026) flagged that user_profiles.avatar_url
  // may reference a Supabase Storage object once a self-hosted
  // upload path lands (today the column carries OAuth provider URLs
  // only). The bucket doesn't exist yet, so the call fails with
  // bucket-not-found — that's expected. Logged + swallowed so the
  // delete proceeds; the moment the bucket is created the drain
  // starts working without a code change here.
  try {
    await deletePrefix(adminClient, 'avatars', user.id);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    // bucket-not-found is the expected steady state pre-launch; only
    // log unusual errors so the Sentry signal stays clean.
    if (!/Bucket not found|not_found/i.test(msg)) {
      console.error('delete-account: avatars drain warning:', msg);
    }
  }

  // Row data cascades from auth.users via ON DELETE CASCADE on every
  // table that references it. Migration 20260728_001 closed the gap
  // where eight tables had `references auth.users` without
  // `on delete cascade`, which used to make this admin.deleteUser
  // call 23503 for any user with even a user_profiles row.

  const { error } = await adminClient.auth.admin.deleteUser(user.id);
  if (error) {
    console.error(
      'delete-account: admin.deleteUser failed:',
      error?.message ?? String(error),
    );
    await recordAudit(
      adminClient,
      user.id,
      'auth_delete_failed',
      (error?.message ?? String(error)).slice(0, 200),
    );
    return Response.json(
      { error: 'delete failed' },
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  await recordAudit(adminClient, user.id, 'ok');
  return Response.json({ ok: true });
}));
