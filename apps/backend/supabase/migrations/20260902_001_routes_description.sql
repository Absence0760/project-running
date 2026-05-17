-- Optional free-text description on routes.
--
-- The route builder's Save modal has had a description textarea for a
-- while, but `saveRoute()` never forwarded the value to the database
-- and there was no column to hold it — runners were typing notes into
-- a field that silently dropped them on submit. Closing that loop.
--
-- Nullable, unbounded TEXT. No index — routes are looked up by id or
-- spatial query, never by description text. The /routes/[id] detail
-- page renders the description below the title for owners + viewers
-- of public routes.

alter table routes
    add column description text;

-- The public_routes view (migration 20260703_001) intentionally
-- projects a narrow column set and the description is omitted on
-- purpose for now — the owner detail page reads from `routes`
-- directly via fetchRouteById and gets the column. A follow-up can
-- widen the view + dependent RPCs (search_public_routes,
-- nearby_routes, routes_within_box) so the /share/route/[id] and
-- Explore surfaces show it too.
