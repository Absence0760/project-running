-- Star ("favorite") flag on routes.
--
-- Why: the watch picker can only fit ~6 routes on a 1.4-inch face
-- before scrolling, and "30 most-recently-updated" turned out to be
-- a poor proxy for "the routes I actually run weekly". A user-curated
-- star is a much stronger signal — runners can star their training
-- rotation on the web / phone (big screen, easy interaction) and the
-- watch fetches starred-only at run prep time.
--
-- Default false so existing routes stay un-starred until the runner
-- actively curates. Indexed for the watch's filtered fetch — without
-- the index a starred-only query degrades to a full-table scan once
-- a power user accumulates a few hundred routes.

alter table routes
    add column is_starred boolean not null default false;

create index idx_routes_user_starred
    on routes (user_id, updated_at desc)
    where is_starred;
