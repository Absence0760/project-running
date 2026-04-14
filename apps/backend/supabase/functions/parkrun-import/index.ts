import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import * as cheerio from 'https://esm.sh/cheerio@1.0.0-rc.12';

serve(async (req: Request) => {
  const { athleteNumber } = await req.json();
  const authHeader = req.headers.get('Authorization')!;

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // Validate athlete number format
  if (!/^A\d+$/.test(athleteNumber)) {
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
      started_at: date,
      duration_s: parseTime(time),
      distance_m: 5000,
      source: 'parkrun',
      external_id: `parkrun:${event}:${date}`,
      metadata: {
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
});

function parseTime(time: string): number {
  const parts = time.split(':').map(Number);
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return 0;
}
