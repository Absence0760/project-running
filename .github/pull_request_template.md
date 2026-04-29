## Summary

<!-- 1–3 sentences on what this PR does and why. -->

## Changes

<!-- Bulleted list of the user-visible or developer-visible changes. -->

-
-

## Platforms touched

<!-- Tick every surface this PR modifies. -->

- [ ] Android (`apps/mobile_android`)
- [ ] iOS (`apps/mobile_ios`)
- [ ] Web (`apps/web`)
- [ ] Wear OS (`apps/watch_wear`)
- [ ] Apple Watch (`apps/watch_ios`)
- [ ] Backend — Supabase migrations / Edge Functions (`apps/backend`)
- [ ] Shared packages (`packages/*`)
- [ ] Docs only

## Docs checklist

<!-- Required before merge — see CLAUDE.md § Docs hygiene. -->

- [ ] If this changes a user-visible feature on any platform, [`docs/parity.md`](../docs/parity.md) has been updated (row added / cells flipped / Notes explained).
- [ ] If this changes a feature's spec, [`docs/features.md`](../docs/features.md) has been updated.
- [ ] If this ticks or adds a roadmap item, [`docs/roadmap.md`](../docs/roadmap.md) has been updated in the same PR.
- [ ] If this changes the database schema, both generated type files have been regenerated (`npm run gen:types` + `dart run scripts/gen_dart_models.dart`) and committed — see [`docs/schema_codegen.md`](../docs/schema_codegen.md).
- [ ] If this introduces a new convention, [`docs/conventions.md`](../docs/conventions.md) has been updated.
- [ ] If this is a non-obvious trade-off, a one-paragraph entry has been appended to [`docs/decisions.md`](../docs/decisions.md).

## Test plan

<!-- How this was verified. Delete rows that don't apply. -->

- [ ] Unit / widget tests pass locally
- [ ] Manual walkthrough on at least one affected platform (describe below)
- [ ] Screenshots attached for UI changes

<!-- Manual walkthrough notes: -->
