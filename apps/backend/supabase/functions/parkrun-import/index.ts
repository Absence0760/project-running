import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as cheerio from 'https://esm.sh/cheerio@1.0.0-rc.12';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { enforceBodyLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

serve(withSentry('parkrun-import', async (req: Request) => {
  const tooBig = enforceBodyLimit(req, 1024);
  if (tooBig) return tooBig;

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

  // Per-user limit: free 4/h, pro 16/h. parkrun.org doesn't publish
  // a crawl rate; the free ceiling errs on polite scraping while
  // still letting a user retry after a glitch. The pro multiplier is
  // 4× — enough that a Pro user importing across multiple historic
  // athlete numbers in one sitting doesn't hit the wall.
  const denied = await checkRateLimitTiered(supabase, user.id, 'parkrun-import', 4, 16, 3600);
  if (denied) return denied;

  const { athleteNumber } = await req.json();

  // Validate athlete number format. parkrun's real numbers top out at
  // 7-8 digits today; cap the regex at 12 so an attacker can't post
  // a 1 MB digit string and force the URL build + outbound fetch to
  // walk through it before parkrun's own server rejects.
  if (typeof athleteNumber !== 'string' || !/^A\d{1,12}$/.test(athleteNumber)) {
    return Response.json({ error: 'Invalid athlete number' }, { status: 400 });
  }

  // Fetch parkrun results page
  const url = `https://www.parkrun.org.uk/parkrunner/${athleteNumber}/all/`;
  const html = await fetch(url, {
    headers: { 'User-Agent': Deno.env.get('PARKRUN_USER_AGENT') || 'RunApp/1.0' },
  }).then((r) => r.text());

  const $ = cheerio.load(html);
  const runs: Record<string, unknown>[] = [];

  $('table tbody tr').each((_: number, row: cheerio.Element) => {
    const cells = $(row).find('td');
    if (cells.length < 6) return;

    const event = $(cells[0]).text().trim();
    const date = $(cells[1]).text().trim();
    const time = $(cells[3]).text().trim();

    runs.push({
      id: crypto.randomUUID(),
      user_id: user.id,
      started_at: parseParkrunDate(date),
      duration_s: parseTime(time),
      distance_m: 5000,
      source: 'parkrun',
      external_id: `parkrun:${event}:${date}`,
      metadata: {
        // parkrun is always 5K running — no walking-only events.
        activity_type: 'run',
        event,
        position: parseInt($(cells[4]).text().trim()),
        age_grade: $(cells[5]).text().trim(),
      },
    });
  });

  if (runs.length > 0) {
    await supabase.from('runs').upsert(runs, { onConflict: 'external_id' });
  }

  return Response.json({ imported: runs.length, skipped: 0 });
}));

function parseParkrunDate(d: string): string {
  const [dd, mm, yyyy] = d.split('/');
  return `${yyyy}-${mm}-${dd}T08:00:00Z`;
}

function parseTime(time: string): number {
  const parts = time.split(':').map(Number);
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return 0;
}
