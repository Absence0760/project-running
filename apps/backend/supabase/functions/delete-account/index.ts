import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  type DeletionAuditResult,
  FCM_BATCH_REMOVE_URL,
  STRAVA_DEAUTHORIZE_URL,
  type ThirdPartyOutcome,
  type ThirdPartyOutcomes,
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

// Look up the user's decrypted OAuth access token for `provider` and
// call its revocation endpoint. Returns 'skipped' when there's no token
// (the provider isn't connected). Shared by Strava + Garmin.
//
// Self-audit (May 2026): an earlier pass tried to read vault via
// `adminClient.schema('vault').from('decrypted_secrets')`, which fails
// with PGRST106 — PostgREST only exposes `public` + `graphql_public`
// schemas. Use the get_integration_tokens SECURITY DEFINER RPC
// (20260603_001), which returns the decrypted tokens to a service_role
// caller for any user_id.
async function deauthorizeOAuthProvider(
  adminClient: SupabaseClient,
  userId: string,
  provider: 'strava' | 'garmin',
  revoke: (accessToken: string) => Promise<Response>,
): Promise<ThirdPartyOutcome> {
  let accessToken: string | null = null;
  try {
    const { data, error } = await adminClient.rpc('get_integration_tokens', {
      p_user_id: userId,
      p_provider: provider,
    });
    if (error) {
      console.error(
        `delete-account: ${provider} token lookup failed:`,
        error.message,
      );
      return 'failed';
    }
    // get_integration_tokens returns a setof; take the first row.
    const row = Array.isArray(data) ? data[0] : data;
    if (row?.access_token) accessToken = row.access_token;
  } catch (e) {
    console.error(
      `delete-account: ${provider} token lookup failed:`,
      e instanceof Error ? e.message : String(e),
    );
    return 'failed';
  }
  if (!accessToken) return 'skipped';
  try {
    const r = await revoke(accessToken);
    return r.ok ? 'ok' : 'failed';
  } catch (e) {
    console.error(
      `delete-account: ${provider} deauthorize failed:`,
      e instanceof Error ? e.message : String(e),
    );
    return 'failed';
  }
}

function deauthorizeStrava(
  adminClient: SupabaseClient,
  userId: string,
): Promise<ThirdPartyOutcome> {
  return deauthorizeOAuthProvider(adminClient, userId, 'strava', (accessToken) =>
    fetch(STRAVA_DEAUTHORIZE_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}` },
    }),
  );
}

// Garmin live OAuth is deferred (bulk-.fit-import only today — no Garmin
// OAuth tokens are ever stored; see docs/features/integrations.md
// § Garmin Connect, Phase 3). This is wired into the deletion sweep so
// the path explicitly accounts for Garmin and can't silently forget it
// once OAuth lands (audit-findings 2026-05-30 High: "only Strava is
// revoked"). Today the token lookup returns nothing → 'skipped'.
//
// We deliberately do NOT POST to a guessed revoke endpoint: Garmin's
// grant-revocation API can't be confirmed until the OAuth program is
// approved, and shipping a plausible-but-wrong URL would silently fail
// to revoke exactly when it matters (deletion). So the revoke callback
// fails closed — if a future OAuth integration ever stores a Garmin
// token without also wiring the real revoke endpoint, deletion records
// `garmin_deauth: 'failed'` (visible in the audit log) instead of a
// false success. The endpoint must be supplied with that integration.
function deauthorizeGarmin(
  adminClient: SupabaseClient,
  userId: string,
): Promise<ThirdPartyOutcome> {
  return deauthorizeOAuthProvider(adminClient, userId, 'garmin', () => {
    throw new Error(
      'Garmin OAuth grant revocation is not implemented — wire the verified ' +
        'revoke endpoint with the Garmin OAuth integration ' +
        '(docs/features/integrations.md § Garmin Connect, Phase 3)',
    );
  });
}

async function deleteRevenueCatSubscriber(userId: string): Promise<ThirdPartyOutcome> {
  const apiKey = Deno.env.get('REVENUECAT_SECRET_API_KEY');
  if (!apiKey) return 'skipped';
  try {
    const r = await fetch(revenueCatSubscriberUrl(userId), {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    // RevenueCat returns 200 on delete, 404 if the subscriber never
    // existed (treated as a successful no-op for Art 17(2) purposes —
    // there's no recipient to notify).
    if (r.ok || r.status === 404) return 'ok';
    return 'failed';
  } catch (e) {
    console.error(
      'delete-account: revenuecat delete failed:',
      e instanceof Error ? e.message : String(e),
    );
    return 'failed';
  }
}

async function invalidatePushTokens(
  adminClient: SupabaseClient,
  userId: string,
): Promise<ThirdPartyOutcome> {
  // Enumerate every platform's tokens. The DB cascade from
  // auth.users → device_tokens removes the rows when admin.deleteUser
  // runs at the end of this handler, so we don't have to delete
  // explicitly here. The provider-side cleanup is best-effort:
  //
  //   * Android (FCM): we POST to FCM's batchRemove which marks the
  //     tokens as invalidated on Google's routing tables.
  //   * iOS (APNs):  Apple does NOT publish a provider-side "unregister"
  //                  endpoint. Tokens become "Unregistered" only when
  //                  the device app explicitly calls
  //                  `unregisterForRemoteNotifications()` or when
  //                  Apple's own routing observes a 410 Gone via a
  //                  subsequent push attempt. Because we stop sending
  //                  the moment device_tokens cascades away, Apple's
  //                  routing observes the gap naturally; the audit-
  //                  flagged concern ("APNs continues to accept push
  //                  attempts") is moot when we are the only sender.
  //                  We still enumerate + log the count so an operator
  //                  reading the deletion_audit_log can correlate.
  //                  Per audit/account-deletion-completeness (2026-05-25).
  let androidTokens: string[] = [];
  let iosCount = 0;
  try {
    const { data } = await adminClient
      .from('device_tokens')
      .select('token, platform')
      .eq('user_id', userId);
    for (const row of (data ?? []) as { token: string; platform: string }[]) {
      if (row.platform === 'android') androidTokens.push(row.token);
      else if (row.platform === 'ios') iosCount++;
    }
  } catch (e) {
    console.error(
      'delete-account: device_tokens lookup failed:',
      e instanceof Error ? e.message : String(e),
    );
    return 'failed';
  }
  if (iosCount > 0) {
    console.log(
      `delete-account: ${iosCount} iOS push token(s) removed via DB ` +
        'cascade — APNs publishes no provider-side unregister API.',
    );
  }
  const fcmServerKey = Deno.env.get('FCM_SERVER_KEY');
  if (!fcmServerKey || androidTokens.length === 0) {
    // No Android tokens OR no FCM key — there's nothing to notify.
    // Treat as `skipped`, distinct from `failed` so the audit trail
    // distinguishes "no recipient" from "recipient errored".
    return 'skipped';
  }
  try {
    const r = await fetch(FCM_BATCH_REMOVE_URL, {
      method: 'POST',
      headers: {
        Authorization: `key=${fcmServerKey}`,
        'content-type': 'application/json',
      },
      body: fcmBatchRemoveBody(androidTokens),
    });
    return r.ok ? 'ok' : 'failed';
  } catch (e) {
    console.error(
      'delete-account: fcm batchRemove failed:',
      e instanceof Error ? e.message : String(e),
    );
    return 'failed';
  }
}

// `jobs` (20260609_001) is a service-role-only queue with `payload`
// holding the user's UUID inside a jsonb. No FK to auth.users, so
// the cascade leaves a user's terminal jobs in the table forever.
// audit/account-deletion-completeness High: drain pre-cascade.
// Mandatory — failure aborts the delete so the user can retry.
async function drainUserJobs(
  adminClient: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  try {
    const { error } = await adminClient
      .from('jobs')
      .delete()
      .filter('payload->>user_id', 'eq', userId);
    if (error) return { ok: false, reason: error.message };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : String(e) };
  }
}

// `rate_limits.user_id` is NOT FK-cascaded to auth.users — the
// table also stores synthetic UUIDs from `ipBucketKey()` for anon
// webhook paths, which a FK would silently reject (see migration
// 20261003_001 for the rollback rationale). Explicit drain here
// closes the audit/gdpr High #1 "deleted UUID survives 24h" gap
// at deletion time; the hourly cron is the long-tail sweep.
async function drainUserRateLimits(
  adminClient: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  try {
    const { error } = await adminClient
      .from('rate_limits')
      .delete()
      .eq('user_id', userId);
    if (error) return { ok: false, reason: error.message };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : String(e) };
  }
}

// `segments.created_by` (20260526_001) is `on delete set null`, so
// segments the user authored survive deletion as orphan rows. The
// segment NAME may carry PII (a toponym derived from the author's
// activity). audit/account-deletion-completeness Medium: anonymise
// pre-cascade — clear the name + null the FK so the leaderboard
// row keeps working but the author identity is unrecoverable.
// Mandatory — failure aborts the delete.
async function anonymiseAuthoredSegments(
  adminClient: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  try {
    const { error } = await adminClient
      .from('segments')
      .update({ name: 'Anonymous segment', created_by: null })
      .eq('created_by', userId);
    if (error) return { ok: false, reason: error.message };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : String(e) };
  }
}

// Vault holds Strava access + refresh tokens (20260603_001). The
// integrations row's FK to vault.secrets is `on delete set null`, so
// the cascade from auth.users -> integrations leaves the secrets
// orphaned. Explicit cleanup before the cascade.
//
// Self-audit (May 2026): the prior pass tried to delete via
// `adminClient.schema('vault').from('secrets').delete()`, which
// fails with PGRST106 — PostgREST only exposes `public` +
// `graphql_public`. Migration 20260918_001 adds a SECURITY DEFINER
// RPC `delete_user_integration_secrets(p_user_id uuid)` that does
// the vault.secrets DELETE on behalf of the service-role caller.
async function cleanupVaultSecrets(
  adminClient: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  try {
    const { error } = await adminClient.rpc('delete_user_integration_secrets', {
      p_user_id: userId,
    });
    if (error) return { ok: false, reason: error.message };
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
  thirdPartyOutcomes: ThirdPartyOutcomes | null = null,
): Promise<void> {
  try {
    const hashed = await hashUserIdForAudit(userId);
    await adminClient
      .from('deletion_audit_log')
      .insert({
        hashed_user_id: hashed,
        result,
        notes,
        third_party_outcomes: thirdPartyOutcomes,
      });
  } catch (e) {
    // Best-effort. The audit log is a regulator-evidence trail; if
    // the write itself fails we still want the delete to complete.
    console.error(
      'delete-account: audit log write failed:',
      e instanceof Error ? e.message : String(e),
    );
  }
}

Deno.serve(withSentry('delete-account', async (req: Request) => {
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
  // swallowed. Each helper returns 'ok' | 'skipped' | 'failed' which
  // we surface to the deletion_audit_log as the per-recipient Art
  // 17(2) evidence trail.
  // Order: do them BEFORE the auth-row cascade so the integrations
  // / device_tokens rows still exist for the lookups.
  // Sentry (audit-findings 2026-05-30 High): no per-user purge call is
  // made — and none is required. Neither the web hooks
  // (apps/web/src/hooks.{client,server}.ts) nor the EF wrapper
  // (functions/_shared/sentry.ts) ever calls `Sentry.setUser`, and
  // `sendDefaultPii` is left at its `false` default, so error events are
  // NOT keyed on the user's UUID. Any UUID that incidentally lands in an
  // error message is covered by the existing `beforeSend` redaction +
  // Sentry's DPA retention window (the audit's stated accepted
  // alternative to a per-user purge). APNs likewise has no provider-side
  // unregister API — passive revocation is handled + documented in
  // invalidatePushTokens above.
  const thirdPartyOutcomes: ThirdPartyOutcomes = {
    strava_deauth: await deauthorizeStrava(adminClient, user.id),
    garmin_deauth: await deauthorizeGarmin(adminClient, user.id),
    revenuecat_delete: await deleteRevenueCatSubscriber(user.id),
    fcm_remove: await invalidatePushTokens(adminClient, user.id),
  };

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
      thirdPartyOutcomes,
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
      thirdPartyOutcomes,
    );
    return Response.json({ error: 'reports cleanup failed' }, { status: 500 });
  }

  // jobs queue (20260609_001, audit/account-deletion-completeness
  // High May 2026). No FK to auth.users, no cascade — the user's
  // UUID survives in `payload` forever if we don't drain first.
  const jobsDrain = await drainUserJobs(adminClient, user.id);
  if (!jobsDrain.ok) {
    console.error('delete-account: jobs drain failed:', jobsDrain.reason);
    await recordAudit(
      adminClient,
      user.id,
      'reports_cleanup_failed',
      `jobs drain: ${jobsDrain.reason}`.slice(0, 200),
      thirdPartyOutcomes,
    );
    return Response.json({ error: 'jobs drain failed' }, { status: 500 });
  }

  // rate_limits drain — audit/gdpr High #1. The FK was rolled back
  // in 20261003_001 to keep the anon-path callers working; the
  // explicit drain here closes the same "deleted UUID survives"
  // gap without breaking strava-webhook + clip-public-track.
  const rl = await drainUserRateLimits(adminClient, user.id);
  if (!rl.ok) {
    console.error('[coach] rate_limits drain failed:', rl.reason);
    await recordAudit(
      adminClient,
      user.id,
      'reports_cleanup_failed',
      `rate_limits drain: ${rl.reason}`.slice(0, 200),
      thirdPartyOutcomes,
    );
    return Response.json({ error: 'rate_limits drain failed' }, { status: 500 });
  }

  // segments.created_by (20260526_001, audit/account-deletion-
  // completeness Medium May 2026). `on delete set null` would leave
  // the segment name behind — anonymise the row pre-cascade so the
  // leaderboard keeps working without surfacing the author identity.
  const segs = await anonymiseAuthoredSegments(adminClient, user.id);
  if (!segs.ok) {
    console.error('delete-account: segments anonymise failed:', segs.reason);
    await recordAudit(
      adminClient,
      user.id,
      'reports_cleanup_failed',
      `segments anonymise: ${segs.reason}`.slice(0, 200),
      thirdPartyOutcomes,
    );
    return Response.json({ error: 'segments anonymise failed' }, { status: 500 });
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
      thirdPartyOutcomes,
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
      thirdPartyOutcomes,
    );
    return Response.json(
      { error: 'delete failed' },
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  await recordAudit(adminClient, user.id, 'ok', null, thirdPartyOutcomes);
  return Response.json({ ok: true });
}));
