-- db-design cleanups (audit 2026-07-03): drop a duplicate index and align the
-- two outlier ON DELETE behaviours on FKs referencing routes(id).
--
-- 1. training_plans_active (20260419_001, non-unique) duplicates the partial
--    UNIQUE index training_plans_one_active — identical column (user_id) and
--    predicate (status = 'active'). The unique index serves the same lookups;
--    the non-unique twin only costs write amplification.
--
-- 2. FKs referencing routes(id) fall into two semantic groups. Children of
--    the route (segments, saved_routes, route_photos, route_markers,
--    route_conditions) correctly CASCADE. Records that merely LINK to a route
--    should survive its deletion: events.route_id is already SET NULL, but
--    runs.route_id and route_reviews.route_id shipped with NO ACTION, so a
--    route with runs or reviews cannot be deleted at all (23503).
--      * runs.route_id → SET NULL: a deleted route must never block or delete
--        a run — the run is the user's history, the link is decoration.
--      * route_reviews.route_id → CASCADE: the column is NOT NULL (SET NULL
--        impossible) and a review is content ABOUT the route, meaningless
--        without it — same class as route_photos / route_conditions.

drop index training_plans_active;

alter table runs
  drop constraint runs_route_id_fkey,
  add constraint runs_route_id_fkey
    foreign key (route_id) references routes(id) on delete set null;

alter table route_reviews
  drop constraint route_reviews_route_id_fkey,
  add constraint route_reviews_route_id_fkey
    foreign key (route_id) references routes(id) on delete cascade;
