import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import * as cheerio from 'https://esm.sh/cheerio@1.0.0-rc.12';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import {
  MAX_PARKRUN_ROWS,
  capParkrunField,
  isUsableParkrunResult,
  parseParkrunDate,
  parseParkrunTime,
  readBodyTextWithCap,
} from './lib.ts';

Deno.serve(withSentry('parkrun-import', async (req: Request) => {
  const guarded = await readJsonWithLimit<{ athleteNumber?: unknown }>(req, 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  // Authenticate before parsing the body. Malformed JSON from an
  // unauthenticated caller would otherwise produce a 500 distinguishable
  // from a 401, and any future code added between the parse and the
  // auth check would run unauthenticated.
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

  // Honour the user's privacy_default for imported runs — parity with the
  // web createManualRun/saveRun + Strava/Garmin ZIP-import paths (persona
  // #27). Only an explicit 'public' default publishes; followers/private/
  // unset stay private, and any read error falls closed to private.
  let importIsPublic = false;
  try {
    const { data: settings } = await supabase
      .from('user_settings')
      .select('prefs')
      .eq('user_id', user.id)
      .maybeSingle();
    const prefs = (settings?.prefs ?? null) as Record<string, unknown> | null;
    importIsPublic = prefs?.privacy_default === 'public';
  } catch (_) {
    importIsPublic = false;
  }

  // Per-user limit: free 4/h, pro 16/h. parkrun.org doesn't publish
  // a crawl rate; the free ceiling errs on polite scraping while
  // still letting a user retry after a glitch. The pro multiplier is
  // 4× — enough that a Pro user importing across multiple historic
  // athlete numbers in one sitting doesn't hit the wall.
  const denied = await checkRateLimitTiered(supabase, user.id, 'parkrun-import', 4, 16, 3600);
  if (denied) return denied;

  const { athleteNumber } = (guarded.body ?? {}) as { athleteNumber?: unknown };

  // Validate athlete number format. parkrun's real numbers top out at
  // 7-8 digits today; cap the regex at 12 so an attacker can't post
  // a 1 MB digit string and force the URL build + outbound fetch to
  // walk through it before parkrun's own server rejects.
  if (typeof athleteNumber !== 'string' || !/^A\d{1,12}$/.test(athleteNumber)) {
    return Response.json({ error: 'Invalid athlete number' }, { status: 400 });
  }

  // Fetch parkrun results page. Fail loudly on a non-2xx upstream
  // (parkrun outage, bot-detection block, 429 rate-limit response)
  // rather than feeding the error-page HTML into Cheerio and silently
  // returning `{ imported: 0 }` 200 — the original silent-failure mode
  // masked outages and let an attacker drain our IP reputation with
  // parkrun without any signal. /audit/all edge-functions Medium.
  const url = `https://www.parkrun.org.uk/parkrunner/${athleteNumber}/all/`;
  const upstream = await fetch(url, {
    headers: { 'User-Agent': Deno.env.get('PARKRUN_USER_AGENT') || 'RunApp/1.0' },
  });
  if (!upstream.ok) {
    return Response.json(
      { error: `parkrun upstream ${upstream.status}` },
      { status: 502 },
    );
  }

  // Cap the upstream HTML before it reaches Cheerio. A hostile or
  // misconfigured upstream serving a multi-MB page would otherwise
  // exhaust EF memory parsing it. /audit/edge-functions Medium.
  const htmlResult = await readBodyTextWithCap(upstream);
  if (!htmlResult.ok) {
    return Response.json(
      { error: 'parkrun upstream too large' },
      { status: 502 },
    );
  }
  const html = htmlResult.text;

  const $ = cheerio.load(html);
  const runs: Record<string, unknown>[] = [];

  $('table tbody tr').each((_: number, row: cheerio.Element) => {
    // Bound the result set independently of upstream input. /audit/all.
    if (runs.length >= MAX_PARKRUN_ROWS) return false;

    const cells = $(row).find('td');
    if (cells.length < 6) return;

    // capParkrunField trims + truncates so a single scraped cell can
    // never grow external_id or metadata.event past the cap.
    const event = capParkrunField($(cells[0]).text());
    const date = capParkrunField($(cells[1]).text());
    const time = capParkrunField($(cells[3]).text());
    const ageGrade = capParkrunField($(cells[5]).text());

    // Skip non-result rows (sub-headers, footers, "--:--" assisted/unknown
    // times). Without this, a blank date produces an unparseable timestamp
    // that fails the whole batch INSERT, and an unknown time imports a
    // corrupt 5000 m / 0 s run. Only rows with a real time + date become runs.
    if (!isUsableParkrunResult(time, date)) return;

    runs.push({
      id: crypto.randomUUID(),
      user_id: user.id,
      started_at: parseParkrunDate(date),
      duration_s: parseParkrunTime(time),
      distance_m: 5000,
      source: 'parkrun',
      // parkrun is always 5K running — no walking-only events.
      // activity_type is a real column now (F3 / 20261207_001).
      activity_type: 'run',
      is_public: importIsPublic,
      external_id: `parkrun:${event}:${date}`,
      metadata: {
        event,
        position: parseInt($(cells[4]).text().trim()),
        age_grade: ageGrade,
      },
    });
  });

  // Dedupe per-user against existing imports, then plain-insert the rest.
  // We can't upsert with `onConflict` here: the global unique on
  // runs.external_id was dropped for a PER-USER partial unique index
  // (runs_user_external_id ... where external_id is not null,
  // migration 20260528000003), and Postgres won't use a PARTIAL index as
  // an ON CONFLICT arbiter unless the index predicate is also supplied —
  // which PostgREST's `onConflict` param can't express, so any onConflict
  // target raised 42P10 and the import 500'd, importing nothing.
  let imported = 0;
  let skipped = 0;
  if (runs.length > 0) {
    const externalIds = runs.map((r) => r.external_id as string);
    const { data: existing } = await supabase
      .from('runs')
      .select('external_id')
      .eq('user_id', user.id)
      .in('external_id', externalIds);
    const seen = new Set((existing ?? []).map((r) => r.external_id as string));
    const fresh = runs.filter((r) => !seen.has(r.external_id as string));
    skipped = runs.length - fresh.length;
    if (fresh.length > 0) {
      const { error } = await supabase.from('runs').insert(fresh);
      if (error) {
        return Response.json({ error: 'parkrun import failed to save' }, { status: 500 });
      }
      imported = fresh.length;
    }
  }

  return Response.json({ imported, skipped });
}));
