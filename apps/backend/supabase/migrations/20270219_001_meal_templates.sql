-- Meal templates — saved meals a user logs with one tap (multi_modal.md
-- § Nutrition mid depth tier). Mirrors the gym "save as routine / repeat last"
-- pattern (migration 20270101_001) one tier simpler: a named template holds an
-- ordered set of food items, each shaped like a food_log row so the template
-- instantiates straight into food_log entries. No execution loop, no
-- progression — the template is a reusable plan, NOT a dated activity, so it
-- never feeds the activities view.

-- ── meal_templates — a user-owned named meal ────────────────────────────────
create table public.meal_templates (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 120),

  -- Default meal slot the whole template logs into (overridable at log time).
  -- Mirrors food_log.meal_slot's domain; nullable.
  meal_slot         text check (meal_slot is null or meal_slot in ('breakfast','lunch','dinner','snack')),

  -- denormalised count for the list screen; client-stamped on save, NOT a
  -- trigger cache (mirrors gym_routines.exercise_count — see derived_state.md).
  item_count        int not null default 0 check (item_count >= 0),

  external_id       text,
  last_modified_at  timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

create unique index meal_templates_user_external_id_key
  on public.meal_templates (user_id, external_id) where external_id is not null;
create index meal_templates_user_modified_idx
  on public.meal_templates (user_id, last_modified_at desc);

-- ── meal_template_items — food items within a template ──────────────────────
-- Shaped like a food_log row (sans timestamps / is_public) so instantiation is
-- a straight copy into food_log. No own user_id — gated via the parent.
create table public.meal_template_items (
  id                uuid primary key default gen_random_uuid(),
  template_id       uuid not null references public.meal_templates (id) on delete cascade,

  position          int not null check (position >= 0),

  item_name         text not null check (length(item_name) between 1 and 200),
  meal_slot         text check (meal_slot is null or meal_slot in ('breakfast','lunch','dinner','snack')),
  calories          numeric(7,1) check (calories is null or calories >= 0),
  protein_g         numeric(6,1) check (protein_g is null or protein_g >= 0),
  carbs_g           numeric(6,1) check (carbs_g is null or carbs_g >= 0),
  fat_g             numeric(6,1) check (fat_g is null or fat_g >= 0),

  -- Open Food Facts code (off:<code>) the item was sourced from, so a
  -- re-logged template item keeps its provenance like a direct food_log entry.
  external_id       text check (external_id is null or length(external_id) <= 200)
);

create index meal_template_items_template_idx
  on public.meal_template_items (template_id, position);

-- ── RLS — owner-scoped, deny-by-default ─────────────────────────────────────
alter table public.meal_templates      enable row level security;
alter table public.meal_template_items enable row level security;

create policy "meal_templates owner select"
  on public.meal_templates for select using (user_id = auth.uid());
create policy "meal_templates owner insert"
  on public.meal_templates for insert with check (user_id = auth.uid());
create policy "meal_templates owner update"
  on public.meal_templates for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "meal_templates owner delete"
  on public.meal_templates for delete using (user_id = auth.uid());

create policy "meal_template_items via parent select"
  on public.meal_template_items for select
  using (exists (select 1 from public.meal_templates t
    where t.id = meal_template_items.template_id and t.user_id = auth.uid()));
create policy "meal_template_items via parent insert"
  on public.meal_template_items for insert
  with check (exists (select 1 from public.meal_templates t
    where t.id = meal_template_items.template_id and t.user_id = auth.uid()));
create policy "meal_template_items via parent update"
  on public.meal_template_items for update
  using (exists (select 1 from public.meal_templates t
    where t.id = meal_template_items.template_id and t.user_id = auth.uid()))
  with check (exists (select 1 from public.meal_templates t
    where t.id = meal_template_items.template_id and t.user_id = auth.uid()));
create policy "meal_template_items via parent delete"
  on public.meal_template_items for delete
  using (exists (select 1 from public.meal_templates t
    where t.id = meal_template_items.template_id and t.user_id = auth.uid()));
