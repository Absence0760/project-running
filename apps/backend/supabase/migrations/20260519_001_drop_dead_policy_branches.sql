-- Clean up dead `c.id is null` branches in two SELECT policies.
--
-- Both `race_sessions_visible_when_event_is` and
-- `event_results_visible_when_event_is` `LEFT JOIN clubs c ON c.id =
-- e.club_id` and treat the null-c.id branch as visible. But
-- `events.club_id` is declared `NOT NULL`, so the LEFT JOIN can't
-- produce a null row — the branch is unreachable. The policies work
-- correctly because the other branches (`is_public`, `owner_id`,
-- `is_club_member`) fire as expected, but the dead code is visual
-- noise that could mislead a future reader into thinking events
-- without clubs exist.
--
-- Drop the dead branch and switch LEFT JOIN to plain JOIN. No
-- behavioural change — the policy still permits the same set of
-- rows.

drop policy if exists race_sessions_visible_when_event_is on race_sessions;
create policy race_sessions_visible_when_event_is
  on race_sessions for select
  using (
    exists (
      select 1 from events e
      join clubs c on c.id = e.club_id
      where e.id = race_sessions.event_id
        and (
          c.is_public = true
          or c.owner_id = auth.uid()
          or is_club_member(c.id)
        )
    )
  );

drop policy if exists event_results_visible_when_event_is on event_results;
create policy event_results_visible_when_event_is
  on event_results for select
  using (
    exists (
      select 1 from events e
      join clubs c on c.id = e.club_id
      where e.id = event_results.event_id
        and (
          c.is_public = true
          or c.owner_id = auth.uid()
          or is_club_member(c.id)
        )
    )
  );
