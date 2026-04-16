# Backup and restore

Lossless round-trip for a user's run history. Works cross-device — a backup
created on web restores on Android and vice versa.

## Why a dedicated format

The existing CSV export (Settings → Data Export → Export All Runs) is a
human-readable summary. It has no GPS traces, no per-run metadata (activity
type, lap markers, avg HR), and no route library. It's useful for spreadsheet
analysis but not for re-hydrating an account.

The backup format defined here captures everything the client needs to
reconstruct the user's run history on a fresh Supabase project, a new
account, or after a deletion.

## File layout

A backup is a single `.zip` file with this structure:

```
run-app-backup-{ISO_TIMESTAMP}.zip
├── manifest.json              # format version + export metadata
├── runs.json                  # every Run row, minus user_id
├── routes.json                # every Route the user owns (optional)
├── goals.json                 # training goals from Preferences (optional)
├── profile.json               # user_profiles row + user_settings.prefs
└── tracks/
    ├── {run_id}.json.gz       # gzipped GPS trace for run_id, same
    │                          # format as runs/{user_id}/{run_id}.json.gz
    │                          # in Supabase Storage
    └── ...
```

Every key inside the archive is UTF-8 JSON. Tracks are pre-gzipped so the
archive can be uploaded straight into the `runs` Storage bucket on restore
without a re-encode step.

## `manifest.json`

```json
{
  "format": "run-app-backup",
  "version": 1,
  "exported_at": "2026-04-15T12:34:56.000Z",
  "exported_by_user_id": "uuid",
  "exported_from": "web" | "mobile_android" | "mobile_ios",
  "counts": { "runs": 47, "routes": 3, "goals": 2, "tracks": 45 }
}
```

Version number is checked on import. A version bump means the reader must
know how to interpret the new layout — older clients reject newer backups
rather than lose data silently.

## `runs.json`

Array of `RunRow`-shaped objects. Keeps the server's column names (snake
case) for forward compatibility with the generated row types. `user_id` is
**omitted** — on restore we stamp it with the importing user's id so the
same archive can re-home runs to a different account.

`track_url` is rewritten on restore to point at the new user's bucket path.

## `routes.json`, `goals.json`, `profile.json`

Optional. Readers must tolerate them being absent. Same shape / semantics
as their DB rows.

## Round-trip guarantees

- Run count is preserved (counts.runs == imported runs).
- GPS traces are byte-for-byte the same files the Storage bucket holds.
- `metadata` jsonb bag is preserved verbatim — `activity_type`, `event_id`,
  lap arrays, and every future key survives. Callers must not whitelist
  known keys when reading.
- `source` is preserved. A Strava-imported run stays `source = 'strava'`
  after a round-trip; an `app` run stays `app`. This matters for dashboard
  counts and integrations.
- `event_id` is preserved but verified — on restore we only keep it when
  the target DB still has the event row. Otherwise we null it so the
  import doesn't 400 on the foreign key.
- Run IDs are **preserved** by default (imported runs keep their original
  UUID). A "keep originals" upsert path means re-importing the same backup
  is idempotent. Pass `generate_new_ids = true` to the importer to mint
  fresh UUIDs (useful when copying runs to a different account that
  already contains the originals).
- Timestamps (`started_at`, `created_at`) are preserved.

## What's intentionally *not* preserved

- In-flight recording state (`LocalRunStore`'s in-progress file). The
  backup captures finished runs only.
- Device-local settings like `device_id` or cached session tokens.
- Realtime objects: pending club RSVPs, event results that were
  auto-submitted, race ping rows. Those re-materialise as the user
  re-engages with their clubs, and coupling them to the backup would
  make backups dependent on the state of other users' accounts.

## Where it's wired today

- **Web** → `/settings/account` → "Download full backup" + "Restore from
  backup". Implemented in `apps/web/src/lib/backup.ts`. Uses `JSZip`.
- **Mobile Android** → Settings → "Full backup" / "Restore from backup".
  Implemented in `apps/mobile_android/lib/backup.dart`. Uses the
  `archive` package.
- Mobile iOS and the watch apps do **not** offer backup — too much UI for
  a small screen. Use the phone or the web.

## Implementation notes

- Both clients stream tracks — a 10-hour run's track is multi-megabyte,
  and holding every track for a heavy user (hundreds of runs) in memory
  during export is a hazard. JSZip writes incrementally; the Dart
  `archive.writeZipBytes` also accepts a streaming builder.
- Restore is **additive**. It never deletes runs that aren't in the
  archive. Users who want to wipe-and-restore should delete their
  account first (Danger Zone in Settings) and import into the fresh one.
- Restore is **resumable on conflict**. An `ON CONFLICT (id) DO UPDATE`
  upsert means an interrupted restore can be re-run and will converge.
- A backup contains PII (the user's own data only). It is not encrypted
  at rest — callers should treat the file as sensitive.
