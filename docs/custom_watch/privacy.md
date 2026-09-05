# Privacy posture — the tier-1 watch

What personal data this firmware holds, where it sits, how long it stays, who
can read it, and which of the main app's disciplines it inherits, does not
inherit, and does not owe.

**This is research-tier firmware. There are zero devices, zero wearers, and no
production deployment** ([§ 71](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely)).
Nothing here is a compliance claim, a certification, or a statement that the
device is fit to carry a real person's data. It is an inventory and a set of
rules, written down so the gap between this device and the rest of the product
is a decision rather than an accident. Every rung claimed below is
*host-tested* or *build-verified* in the sense
[`quality_standards.md`](quality_standards.md) defines; **nothing on this page
is bench-verified, because no hardware exists.**

Recorded as [decisions § 377](../architecture/decisions.md), and amended by
[§ 378](../architecture/decisions.md), which closed the largest gap this page
opened with: **there is now a user-reachable factory erase** — a guarded
settings-menu row, reachable on the device alone. See
[*The erase*](#the-erase--378) below.

## What the watch holds

### Flash — survives a power cycle

| Data | Where | What it is | Bound |
|---|---|---|---|
| **Finished + in-progress runs** | 4 slots of 4 KiB at the top of flash (`flash_store::SLOT_LEN`, `SLOT_COUNT`) | per track point: latitude + longitude at 1e-7° (**~1.1 cm**), time offset, elevation, and **heart rate in bpm** (`run_store::TrackPoint`); plus closed laps and workout step results | 253 points per run (`MAX_POINTS_PER_RUN`), 4 runs, of which at most 2 while a run is recording |
| **ICE / medical ID** | config page + 256 (`ICE_RECORD_OFFSET`) | holder name, blood type, conditions or allergies, next-of-kin name, next-of-kin phone (`ice::IceCard`) — **special-category health data** | one card |
| **Waypoints** | config page + 128 (`WAYPOINT_RECORD_OFFSET`) | 8 × (latitude + longitude at 1e-7°, uptime stamp) — places the wearer chose to mark: a gear cache, a water stash | 8, newest-wins |
| **BLE bond** | config page + 64 (`BOND_RECORD_OFFSET`) | the paired phone's LTK, IRK, and address (`flash_store::BondRecord`) | one peer |
| Composed data screens | config page + 512 | layout choices — not personal | one set |
| Config | config page + 0 | GNSS mode, feature flags, activity profile — not personal | one record |

### RAM only — gone at reset

The live GNSS fix, the live heart-rate sample, the barometric elevation
reading, the pushed course (where the runner *plans* to be), and the pushed
workout. None is written to flash in its own right; the fix and the bpm reach
flash only as points inside a run blob.

### What the watch is never told

It holds no account identity: no email, no `user_id`, no auth token, no
password. A run blob is anonymous until the phone that pulled it attaches an
owner. That is a property of the design worth keeping.

## What leaves the watch

| Path | What crosses it | Who can read it |
|---|---|---|
| GATT `frame` (read + notify) | live latitude + longitude at 1e-6°, speed, course, satellites, altitude, GNSS time-of-day, fix age — once per second (`link::status_frame`) | **paired + encrypted peers only** |
| GATT `run_manifest` (read + notify) | run sequence, blob size, start uptime | paired only |
| GATT `run_chunk` (write + notify) | the whole run blob — every coordinate and every bpm | paired only |
| GATT `settings`, `course`, `workout`, `screens` (write) | inbound config; no readback | paired only |
| The display | the ICE card, to anyone holding the wrist — **by design** | anyone physically present |
| defmt / RTT log stream | fix quality and pulse presence; coordinates and bpm only under `log-personal-data` | anyone with the debug cable |
| UARTE1 → TCP (`tasks::phone`) | the same `link::status_frame` bytes, unencrypted and unauthenticated | **simulator only** — the module is `#![cfg(not(feature = "ble"))]`, so it is compiled out of every hardware build |

**The BLE data plane is fail-closed** ([§ 285](../architecture/decisions.md#285-run-store-v2-byte-15-becomes-a-record-tag-laps-interleave-with-points-and-a-full-slot-decimates-instead-of-truncating-the-threkir-gatt-service-is-encrypted-only-with-one-persisted-bond),
issue #598). Every characteristic carries `security = "justworks"` —
Security Mode 1 Level 2 — so the SoftDevice rejects every read, write and CCCD
subscription from an unencrypted connection. An unbonded central can discover
the service's shape and nothing else. This is **build-verified only** and can
never be sim-verified ([§ 210](../architecture/decisions.md#210-tier-1-ble-s140-softdevice-is-a-compile-verified-feature-gated-build--mutually-exclusive-with-the-sim-off-by-default):
Renode has no SoftDevice).

## Retention

**There is no time-based retention on this device. None.** Not a TTL, not an
expiry, not an age check — the word does not appear in the store.

What exists is a *capacity* bound, which is not the same thing:

- A **run** occupies one of four slots. It is displaced only when a later run
  reserves that slot, and `flash_store::victim` prefers to sacrifice a run the
  phone has already pulled over one it has not. Until that happens the blob is
  readable in full over `run_chunk`. Four quiet weeks after a race, the race is
  still on the wrist.
- `SlotDir::forget` drops a slot's **directory entry**, not its bytes. The page
  is erased when a later reservation takes it, not when the entry goes. The
  § 378 erase deliberately does **not** use it — see below.
- A **waypoint** survives until eight newer marks push it out
  (`waypoints.rs`). The first eight marks of a device's life can sit in flash
  indefinitely.
- The **ICE card**, the **bond**, and the **config** persist until something
  overwrites them.

The main app, by contrast, has a real per-category policy in
[`docs/compliance/retention.md`](../compliance/retention.md): durable tracks
are kept *until the user deletes them*, and only ephemeral broadcast data
(`live_run_pings`, `race_pings`) carries a clock, at 48 hours. The watch's
flash holds the owner's own record, so "until the user deletes it" is the
correct target for it too — and since § 378 the watch **has** a delete. It is
an all-or-nothing one: a factory erase, not a per-run one.

## The erase (§ 378)

**The wearer can sanitise the device with no phone in reach.** A seventh
settings-menu row, `FACTORY ERASE`, on the ring's far seat — 5 presses to arm,
6 to complete. A right press arms `erase::EraseGuard` and the row reads
`ERASE ALL? B1` under a replaced legend row (`B1 ERASE    B4 CANCEL`); a second
right inside the stop guard's own 4 s window wipes. Any other press cancels,
and so does the window lapsing. The button edges and the recomputed press costs
are in [`navigation.md`](navigation.md).

| What | Cleared? | Why |
|---|---|---|
| The four run slots — every coordinate and every bpm | yes | the payload |
| The eight waypoints | yes | saved coordinates the runner chose; `Waypoints::clear` finally has a caller |
| The **ICE card** | yes | the only *third-party* personal data here — a next-of-kin who never consented to the next holder — and special-category health data. Phone-authored, so the recovery cost is one push against an unbounded exposure |
| The **BLE bond** (LTK, IRK, peer address) | yes | a live **credential**, not a stale record: a kept bond lets the previous owner's phone read the new owner's runs and live position, and the IRK resolves that phone's random addresses forever. Re-pairing costs one phone-side action and loses nothing |
| The config record (GNSS mode, filter, profile, backyard, auto-lap) | yes | a *factory* erase, not a runs-only clear |
| Composed data screens | yes | same |
| Pushed max HR / resting HR, pacer goal, gear, roadbook, fuel plan | yes | biometrics and race config, held in the recorder, which is replaced whole |
| The pushed course, workout, and the trackback breadcrumb | yes (RAM) | where the runner planned to be, and where they went; all drawn on pages a next holder would page straight to |
| The **timezone offset** | **no** | not personal — a UTC offset is shared by a continent — RAM-only, and the channel has no propagating "unset", so writing `0` would make the home clock claim `LOCAL` while showing UTC. A false label is worse than a retained offset |
| A **live BLE connection** | **no** | the durable bond is gone, so the next boot has no peer; the only window is until power-cycle, during which the wearer is holding the watch. Tearing a SoftDevice link down needs a `ble`-only seam that can be neither host- nor sim-verified (§ 210) |

**It erases bytes, not directory entries.** `SlotDir::forget` would satisfy
every reader in this firmware while leaving each blob's coordinates and heart
rates at the address they were written to — and the adversary a factory erase
exists for is whoever holds the device next, with no APPROTECT between them and
a debug probe (item 6 under *Deferred*). `flash_plan::plan_factory_erase`
returns one contiguous range covering the config page and all four slots, and
its host test checks every published record offset against that range rather
than against a copy of the arithmetic — so a record added at a new offset fails
the test rather than surviving a wipe.

**What that claim is bounded to.** The erase returns every address the firmware
wrote to `0xFF`, and this store addresses pages directly with no wear-levelling
or copy-back layer underneath to leave a shadow copy elsewhere. It is **not** a
claim against charge-remnant recovery on a decapped die, and it does nothing
about a probe attached *before* the erase. That is encryption at rest, which
tier 1 does not have.

**Rung.** Host-tested (the guard, the row's placement, the range's coverage)
and sim-verified for the guard, the fan-out and the RAM half — the `idle`
scenario asserts that one press arms rather than wipes, that stepping off the
row cancels the arm, and that the confirming press resets a setting the
scenario itself moved. **The flash wipe is not sim-verified**: Renode answers
`NVMC:READY` from its SVD and swallows the `ERASEPAGE` write, so the firmware
reports success over an emulator that changed no byte. That the slots really
read back `0xFF` is a bench item, and it is the half that matters for a watch
that has left its owner's hands.

## What the watch inherits for free

This is the part that is already right, and it is right because of a design
choice worth naming: **the watch introduces no new backend surface.**

A synced run rides `run_manifest` / `run_chunk` to the phone, where
`runFromWatchPayload` reshapes the blob and hands it to `api.saveRun`
(`watch_ingest_queue.dart`) — the same call a phone-recorded run makes. It
lands as an ordinary `runs` row plus an ordinary `runs/{user_id}/{run_id}.json.gz`
Storage object. No new table, no new bucket, no new column. Therefore:

- **Export (GDPR Art 20)** — already covered. The exporter's table set is
  guarded by `personal_data_export_guard_test.go`, which fails the build for
  any table carrying an owner-style FK to `auth.users` that is neither exported
  nor explicitly excluded with a reason. A watch run cannot drift out of the
  export, because it is not a new table.
- **Deletion (GDPR Art 17)** — already covered. `delete-account`'s recursive
  `deletePrefix` over the `runs` bucket removes the blob with every other track.
- **Privacy zones** — already covered. Once the run is an ordinary row,
  `clip_track_for_user` clips it on every non-owner surface exactly as it clips
  a phone-recorded run.

The obligation this creates is a *rule for the future*, not work owed today: if
the watch ever grows a data class the phone does not already have, it must
arrive as a table with an owner FK (so the export guard sees it) and either an
`on delete cascade` or an explicit drain in `delete-account`.

**None of this reaches the copy still on the watch.** A user who deletes their
account still has up to four runs, eight waypoints, a medical ID and a bond key
on their wrist — until they run the § 378 erase, which is a *separate,
device-local* action and is not driven by the account deletion. Nothing in this
firmware learns that an account went away, and nothing should: the watch holds
no account identity to match against, which is a property worth keeping.

## Why `privacy.rs` is dormant, and what would wire it

`core/src/privacy.rs` is a faithful port of the web zone-clipping helper, with
nine host tests. **It has zero callers.** That is correct, and it should stay
that way at tier 1.

Clipping in this product is a **read-time, viewer-keyed** transform, not a
write-time one ([§ 33](../architecture/decisions.md)). The reasoning recorded
there is that insert-time clipping is *destructive* — a runner who later turns
a zone off can never recover the trace it ate — so the durable track is stored
unclipped and `clip_track_for_user` runs when, and only when, the viewer is not
the owner. The phone recorder evaluates no zones at all; it uploads the raw
track.

The watch's only egress is to the single phone it is bonded to, which is its
owner's. Clipping there would be precisely the destructive write-time clip § 33
rejected, and it would mutilate the run before the owner had ever seen it. So
the watch storing and syncing a raw track is **consistent with the model, not a
violation of it.** The invariant is *owner versus non-owner*, not *device
versus cloud*.

Two further facts pin this down:

- There is **no transport for zones**. `WatchSettings` carries no zone list, so
  the device cannot learn where home is even if something wanted to clip.
  Wiring `privacy.rs` therefore starts with a `SET1` field, not with a call
  site.
- The precedent for the boundary already exists in this workspace, from the
  other direction. § 370's course push clips the polyline for a non-owner
  before it crosses the radio, on the stated grounds that *"the radio is just
  another way out of the app, and the invariant does not care which one."*

**The trigger that wires it** is tier-2 live spectator tracking, which
[`tier2_scope.md`](tier2_scope.md) already flags as needing this posture to land
with it. Forwarding `link::status_frame` into the live pipeline turns a
1 Hz position stream into a **broadcast to non-owners**, and § 33's
`live_run_pings` precedent is explicit that a broadcast must drop in-zone fixes
*at the source*, because a downstream filter cannot unsend what already left.
For that path the watch **is** the source. That is the day `privacy.rs` earns
its call site, and it is why the port was worth keeping dormant rather than
deleting.

## The rules this device follows

1. **Personal data never enters the log stream.** A defmt stream goes wherever
   the cable, the CI artifact, or the bug report goes. A stock build logs fix
   *quality* and pulse *presence*; coordinates, bpm and the strap address are
   behind `log-personal-data`, default off, which only `bin/watch-sim.sh`
   enables and only because its coordinates are a synthetic fixture with no
   wearer behind them.
2. **Nothing personal crosses an unpaired or unencrypted link** (§ 285).
3. **A type that carries personal data does not derive its own formatter.**
   `IceCard` hand-writes `defmt::Format` to print `blank` or `set` and never a
   field; `Fix`, `Waypoint`, `CoursePoint` and `BondRecord` carry no `Format`
   impl at all. The LTK and IRK have no path to a log line.
4. **Refuse rather than degrade.** A medical ID with one unrenderable byte is
   rejected whole, never rendered with a field blanked: a clipped allergy line
   reads as complete, and a truncated phone number dials a stranger.
5. **The ICE card is deliberately readable without authentication, and is
   bounded to exactly that.** It is a face on the display, reachable by a medic
   holding an unresponsive runner's wrist. It is **not** a GATT characteristic,
   is not in the run blob, and is not in the log stream — so "readable by
   whoever holds the wrist" is the whole of its exposure, not the start of it.
6. **Personal fields are phone-authored.** The watch has no text entry, so the
   medical ID and the calibration biometrics arrive by push and leave by push.
7. **Store raw locally; clip at the boundary to a non-owner.** There is no such
   boundary today; when there is one, see the section above.

## Deferred, with reasons

1. ~~**No user-reachable erase — the largest gap on this page.**~~ **Closed
   2026-07-31 by [§ 378](../architecture/decisions.md)** — see
   [*The erase*](#the-erase--378) above. What is left of it is one bench item
   (that the page erase really returns the slots to `0xFF`, which Renode cannot
   settle) and one bounded limit (a live BLE connection is not torn down; the
   durable bond is). Kept as item 1 rather than deleted, because the two items
   below reference it and because a reader arriving from § 377 will look here
   for it.
2. **No erase-on-sync — deliberate, not an oversight.**
   `mark_synced_if_complete` fires when the phone has *pulled* the bytes, but
   the phone then queues them to disk and uploads later, retrying across
   sign-ins (`WatchIngestQueue`). A pull is not durability. Erasing at pull
   would delete the only surviving copy of a run whose upload had not yet
   landed. Preferring a synced run as the eviction victim is the right
   strength; erasing it is not.
3. **`WatchSettings` derives `defmt::Format` while carrying `max_hr`,
   `resting_hr` and the ICE card.** Not a live leak — nothing formats it today,
   and the settings paths log byte counts only — but a single
   `info!("settings {}", s)` would make it one. The durable fix is the
   `IceCard` treatment: a hand-written presence-only impl. Not taken here, to
   keep this change out of `settings.rs` while the `SET1` frame is under
   concurrent edit.
4. **Just-works pairing carries no MITM protection** during the one-time
   pairing itself. Accepted and documented at § 285 rather than hidden: the
   tier-1 face has no passkey UI. Since § 432 the exposure is scoped, not
   standing: a bonded watch refuses pairing outright except inside the 90 s
   wearer-armed PAIR PHONE window, so the bond is replaceable only by whoever
   holds the watch — possession beats possession of an old radio capture,
   and beats mere radio range too.
5. **The advertised name is the constant `"Threkir"`.** A passive observer can
   track the device's presence — and by extension the wearer's — without ever
   pairing. Resolvable private addresses are the answer; that is a SoftDevice
   configuration and a phone-side change, and it can be neither host-tested nor
   sim-verified (§ 210). Tier 2.
6. **Nothing is encrypted at rest.** Runs, the medical ID and the bond keys sit
   in plaintext in internal flash. Nothing in this workspace enables APPROTECT,
   so a debug probe on the DK reads all of it. This is honest for a bench
   prototype on a development kit and is not acceptable for anything worn by
   someone who is not the author.
7. **The live frame streams position whenever a bonded phone subscribes**,
   whether or not a run is recording. The control is the CCCD subscription —
   the phone must ask — rather than a recording gate. Adequate for an
   owner-to-owner link; revisit when the frame feeds spectators.
8. **Tier 2 resets all of this.** The external NAND store changes the capacity
   bound that is currently standing in for a retention policy, and
   [`tier2_scope.md`](tier2_scope.md) already records that store's retention as
   an open architectural choice.
