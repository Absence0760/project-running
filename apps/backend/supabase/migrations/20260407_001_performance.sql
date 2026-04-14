-- Performance optimisations for dashboard queries at scale

-- Materialized view for weekly mileage (refreshed by pg_cron or manually)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_weekly_mileage AS
SELECT
  user_id,
  date_trunc('week', started_at)::date AS week_start,
  sum(distance_m) AS total_distance_m,
  count(*) AS run_count
FROM runs
GROUP BY user_id, date_trunc('week', started_at)::date
ORDER BY week_start;

CREATE UNIQUE INDEX IF NOT EXISTS mv_weekly_mileage_pk
  ON mv_weekly_mileage (user_id, week_start);

-- Full-text search index on route names
CREATE INDEX IF NOT EXISTS routes_name_search
  ON routes USING gin (to_tsvector('english', name));

-- Composite index for dashboard recent runs query
CREATE INDEX IF NOT EXISTS runs_user_source
  ON runs (user_id, source, started_at DESC);

-- Index for personal records distance-range queries
CREATE INDEX IF NOT EXISTS runs_user_distance
  ON runs (user_id, distance_m, duration_s);
