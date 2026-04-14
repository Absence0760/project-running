-- Route ratings and comments.
--
-- Lets users rate and review public routes they've run. Each user can leave
-- one review per route (upsert on user_id + route_id). The avg rating is
-- computed client-side from the reviews list for now; a materialized view
-- can be added later if the query becomes expensive.

create table route_reviews (
  id          uuid primary key default gen_random_uuid(),
  route_id    uuid references routes not null,
  user_id     uuid references auth.users not null,
  rating      smallint not null check (rating >= 1 and rating <= 5),
  comment     text,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (route_id, user_id)
);

create index route_reviews_route on route_reviews (route_id, created_at desc);

alter table route_reviews enable row level security;

-- Anyone can read reviews on public routes.
create policy "reviews on public routes are readable by anyone"
  on route_reviews for select
  using (
    exists (
      select 1 from routes where routes.id = route_reviews.route_id and routes.is_public = true
    )
  );

-- Authenticated users can insert/update/delete their own reviews.
create policy "users manage their own reviews"
  on route_reviews for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
