-- Gate route_reviews INSERT on route visibility.
--
-- Pre-prod RLS audit Medium. The original
-- "users manage their own reviews" policy from 20260414_001 is
-- `for all using (auth.uid() = user_id) with check (...)` — the
-- INSERT side only enforces that the writer is the row's user_id.
-- It does NOT gate on the linked route being visible to the writer.
--
-- An authenticated user can therefore plant review rows against any
-- route_id (including UUIDs of private routes they enumerate). The
-- SELECT policy hides those rows from anyone but the writer when
-- the route is private, but the rows are still in the table:
--   - The route owner (if the route is private) cannot see them to
--     clean up — their own SELECT on route_reviews is gated by
--     `routes.is_public = true` per the existing public-read policy,
--     not by ownership.
--   - The pollution survives until/unless the writer deletes their
--     own row.
--
-- Closes the same shape as run_kudos / run_comments / run_photos
-- which already gate INSERT on `exists (select 1 from <parent>
-- where <parent>.id = <table>.<parent_id>)`. The subquery picks
-- up RLS on `routes` automatically, so the writer can only review
-- routes they can SELECT (own + public + club-readable).
--
-- The fix splits the catch-all `for all` policy into:
--   - SELECT (no change in behaviour — already covered by the
--     existing "reviews on public routes" policy from 20260414_001;
--     plus a new owner-self-read so the writer can see their own
--     pending review on a route that flips public→private).
--   - INSERT (new visibility-gated check).
--   - UPDATE (owner only, mirrors the original `with check`).
--   - DELETE (owner only).

drop policy "users manage their own reviews" on route_reviews;

-- Owner can read their own reviews even when the route's public
-- read policy doesn't apply (e.g. they reviewed a then-public route
-- that's since flipped private). The existing public-read policy
-- from 20260414_001 stays in place; SELECT picks up either match.
create policy "users read their own reviews"
  on route_reviews for select
  to authenticated
  using (auth.uid() = user_id);

create policy "users insert reviews on visible routes"
  on route_reviews for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from routes where routes.id = route_reviews.route_id
    )
  );

create policy "users update their own reviews"
  on route_reviews for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users delete their own reviews"
  on route_reviews for delete
  to authenticated
  using (auth.uid() = user_id);
