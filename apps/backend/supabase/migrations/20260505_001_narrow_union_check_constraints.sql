-- Enforce narrow-union text columns at the DB level.
--
-- These columns have TypeScript/Dart unions on the client side but were
-- previously unconstrained in Postgres, so a misbehaving client could write
-- any string and the row would be accepted silently. Adding CHECK constraints
-- here closes the gap: invalid values now produce a PostgreSQL 23514
-- check_violation at write time, surfacing immediately rather than drifting
-- invisibly across clients.
--
-- Seed data and all existing clients conform to these values; no backfill
-- is required.

alter table runs
  add constraint runs_source_check
    check (source in ('app','watch','healthkit','healthconnect','strava','garmin','parkrun','race'));

alter table routes
  add constraint routes_surface_check
    check (surface in ('road','trail','mixed'));

alter table integrations
  add constraint integrations_provider_check
    check (provider in ('strava','garmin','parkrun','runsignup'));

alter table user_profiles
  add constraint user_profiles_preferred_unit_check
    check (preferred_unit in ('km','mi'));
