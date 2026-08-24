# Backup and restore

Lossless round-trip for a user's run history. Works cross-device — a backup
created on web restores on Android and vice versa.

## Why a dedicated format

The existing CSV export (Settings → Data Export → Export All Runs (CSV)) is a
human-readable summary. It has no GPS traces, no per-run metadata (activity
type, lap markers, avg HR), and no route library. It's useful for spreadsheet
analysis but not for re-hydrating an account.

The same Data Export card also offers **Export All Runs (JSON)** — a single
`runs-{ts}.json` file with every Run row, `user_id` stripped, in the exact
shape used by the `runs.json` entry inside a Full backup ZIP (so scripts that
consume one consume the other). It carries the full per-run metadata bag but
no GPS traces — for a lossless copy with tracks, use the Full backup ZIP
defined below.

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
  "exported_from": "web" | "mobile_android" | "mobile_ios" | "go-service" | "edge-function",
  "counts": { "runs": 47, "routes": 3, "goals": 2, "tracks": 45 },
  "complete": true,
  "incomplete": []
}
```

Version number is checked on import. A version bump means the reader must
know how to interpret the new layout — older clients reject newer backups
rather than lose data silently.

### `complete` / `incomplete` — the honesty pair

`complete` is a boolean; `incomplete` is the sorted list of section names
(`runs`, `routes`, `tracks`, `hr_series`, …) that came up short of what the
writer asked for. `complete` is exactly `incomplete.length == 0`. Every writer
that emits either emits both.

**Only an explicit `complete: false` claims a shortfall.** An archive with no
`complete` key says nothing about its own completeness — every mobile or web
archive built before 2026-08-18 carries no such field, and warning on all of
those would be its own dishonesty. Readers mirror
`ServerBackupSummary.fromJson` / `cloudExportShortfall` /
`noteIncompleteArchive` on this.

What can make each writer short:

| Writer | Can come up short on | Why |
|---|---|---|
| `go-service` | any section whose paging genuinely failed mid-read, blobs | **No run cap and no row ceiling** since [decisions § 708](../architecture/decisions.md) — the archive streams into the `exports` bucket in 6 MiB tus chunks and every section is serialised page by page, so nothing but a failed page can shorten it. `counts` for a short *paged* section publishes the **database's** own total, so a file short of it reads as a shortfall rather than as the whole set |
| `edge-function` | any section the 120 s wall-clock budget cut short, blobs | **No run cap and no row ceiling** since [decisions § 703](../architecture/decisions.md) — the archive streams into the `exports` bucket in 6 MiB tus chunks, so only the platform's request clock can shorten it, and `incomplete` names exactly which sections it reached. (The artifact moved off the `runs` bucket in migration `20270602_001`: `file_size_limit` is per bucket and `runs` caps an object at 25 MB, which was a tighter ceiling on a full-history archive than either removed cap) |
| `mobile_android` / `mobile_ios` | `tracks`, `hr_series` | The row reads are paged and **uncapped**, so the runs and routes in the archive are the whole account. Only a blob download that failed can leave the file short, and the writer swallows that per-blob so one dead download can't sink the archive |
| `web` | `runs`, `routes`, `tracks` | Same per-track swallow as mobile. The row reads page through `readAllRows` and are **uncapped**, so `runs` / `routes` appear only when a page genuinely failed mid-read; a `runs` read that returned nothing at all raises instead of writing a file (decisions § 675) |

The **mobile local writer carries no run ceiling**, deliberately. It streams to
disk and downloads tracks in bounded batches ([decisions.md § 66]), so peak heap
is `O(concurrency × avg-track-size)` and does not grow with run count; the only
per-run cost held in memory is the already-fetched `runs.json` row list, a few
hundred bytes each. A cap would buy nothing and would reintroduce the silent
truncation this pair exists to remove. The **Go** server no longer carries one
either ([decisions § 708](../architecture/decisions.md)): it streams the archive
into Storage the same way, so the mobile fall-through to the local writer is now
a failure path rather than the long-tail path it used to be.
The **Edge Function** no longer has one — it streams into a chunked tus upload
([decisions § 703](../architecture/decisions.md)) and is bounded only by its
150 s request clock — so the two server writers are deliberately no longer in
lockstep on this.

The two server writers (`go-service` — the Go worker's `POST /v1/export`
`format: 'backup'` — and `edge-function` — the deprecated `export-data`
rollback path) emit the same layout plus the Art 20 extras clients don't
fetch: `hr/{run_id}.hr.json.gz` sidecars, `photos/` image bytes, the
`avatar.{ext}` profile picture, one `{table}.json` per personal-data
table (see `exportPersonalDataSpecs` in
`apps/job_worker/internal/supabase.go` / `backup_spec.ts` in the EF),
and a `storage/{bucket}/...` orphan sweep — a prefix walk of the user's
folders in the `runs` + `run-photos` buckets that archives every object
no DB row references (CAS-orphaned matched tracks, legacy tracks, photo
thumbnails), deduped against the row-driven entries and skipping
`{user_id}/exports/`. Readers ignore entries they don't know, so
restore works unchanged.

## `runs.json`

Array of `RunRow`-shaped objects. Keeps the server's column names (snake
case) for forward compatibility with the generated row types. `user_id` is
**omitted** — on restore we stamp it with the importing user's id so the
same archive can re-home runs to a different account.

`track_url` is rewritten on restore to point at the new user's bucket path.

On mobile the array is the union of the server's rows and the local store's
**unsynced** runs — a run that hasn't drained (the drain in backoff, a failed
track upload, a long offline stretch) exists only in `<appDocs>/runs/<id>.json`,
and an archive that omits it is a backup of the cloud rather than of the phone
(decisions § 311). A local-only run's track is gzipped from memory into the same
`tracks/<id>.json.gz` entry and counted in `manifest.counts.tracks`; its row
carries no `track_url`. The server-built archive (the Go service) can only see
cloud rows, so mobile skips that path entirely while anything is local-only.

## `routes.json`, `goals.json`, `profile.json`

Optional. Readers must tolerate them being absent. Same shape / semantics
as their DB rows.

## Round-trip guarantees

- Run count is preserved (counts.runs == imported runs).
- GPS traces are byte-for-byte the same files the Storage bucket holds.
- `metadata` jsonb bag is preserved verbatim — `event_id`,
  lap arrays, and every future key survives (`activity_type` / `is_dnf` are now
  real columns, `20261207_001`, also preserved). Callers must not whitelist
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
  backup". Implemented in `apps/web/src/lib/backup/backup.ts`. Uses `JSZip`.
  Both paths require an authenticated session — there's no local
  persistence to stage into.
- **Mobile Android** → Settings → Account → "Full backup" / "Restore from backup".
  Implemented in `apps/mobile_android/lib/backup.dart`. Uses the
  `archive` package. **Restore works offline** — if the user isn't
  signed in, runs + routes are hydrated into `LocalRunStore` /
  `LocalRouteStore` and `SyncService` pushes them to Supabase on the
  next sign-in. Profile and `user_settings` keys are skipped in that
  mode with a warning; they need a user id to attach to. Export still
  requires sign-in since the canonical source of truth is the server.
  The export is server-first (the Go service's `POST /v1/export?format=backup`)
  and falls back to the local writer on any failure — and skips the server
  outright while anything on the device is still undrained, since the server
  can only see cloud rows. The local writer's completeness verdict surfaces as
  a banner plus a persistent notice under the Full backup tile.
- **Mobile iOS** shares the code — `lib/` is byte-identical (decisions § 39),
  neither tile carries a `Platform` gate, `BackupService` names no `Platform`,
  and `archive` / `file_picker` / `share_plus` / `path_provider` all declare
  iOS. `parity.md`'s iOS backup + restore cells read `Partial` on that basis:
  wired, never exercised on a Mac (decisions § 707). What is still owed is the
  device run, tracked by the single iOS-verification item in `followups.md` —
  not a build.
- The watch apps do **not** offer backup — too much UI for a small screen. Use
  the phone or the web.

## Implementation notes

- Both clients stream tracks — a 10-hour run's track is multi-megabyte,
  and holding every track for a heavy user (hundreds of runs) in memory
  during export is a hazard. JSZip writes incrementally; the Dart
  `archive.writeZipBytes` also accepts a streaming builder.
- Restore is **additive**. It never deletes runs that aren't in the
  archive, and (offline path, `generateNewIds: false`) it never overwrites a
  run already present locally — the on-device copy can hold a richer track
  than the archive, since `createBackup` only logs a failed track download.
  Pass `generateNewIds: true` to import the archive's copy alongside. Users who
  want to wipe-and-restore should delete their account first (Danger Zone in
  Settings) and import into the fresh one.
- Restore is **resumable on conflict**. An `ON CONFLICT (id) DO UPDATE`
  upsert means an interrupted restore can be re-run and will converge.
- **A blob the archive lacks leaves its column out of the upsert**, rather than
  nulling it. PostgREST only `SET`s the columns it is handed, so an existing row
  keeps the `track_url` / `hr_series_url` it already has; writing null instead
  orphaned the Storage object and cost a run its GPS trace when a track-short
  archive was restored into the very account it was taken from. A fresh insert
  still lands with the column null, which is the truthful value there.
- **An archive that declares itself incomplete says so at restore time.**
  `RestoreResult.archiveIncomplete` + `archiveIncompleteSections` carry the
  manifest verdict, and both Settings → Account surfaces render a persistent
  notice under the Restore tile. Mobile additionally inserts a first warning
  naming it; web keeps the verdict out of `warnings` (which it renders as a
  bare count) and localizes the notice from the two fields instead. Nothing is lost either
  way (restore is additive), but a runner about to wipe a phone on the strength
  of the file needs to know it is not the whole history.
- A backup contains PII (the user's own data only). It is not encrypted
  at rest — callers should treat the file as sensitive.
