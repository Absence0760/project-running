-- Recipes — N ingredients summed into ONE logged meal (multi_modal.md
-- § Nutrition mid depth tier, the bullet after "Meal templates"). The sibling
-- of meal_templates (migration 20270219_001): a recipe is the same idea — a
-- reusable, owner-scoped set of food items — but where a meal template logs
-- each item as its own food_log entry, a recipe SUMS its ingredients into a
-- single combined-macro food_log entry, scaled by a `servings` count so logging
-- one serving divides the total. No execution loop, no progression — a recipe
-- is a reusable plan, NOT a dated activity, so it never feeds the activities
-- view. Instantiate-by-copy: no FK from food_log to recipes (decisions §173),
-- so deleting a recipe leaves logged meals intact.

-- ── recipes — a user-owned named recipe ─────────────────────────────────────
create table public.recipes (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 120),

  -- Number of servings the summed ingredients yield. Logging one serving
  -- divides the recipe's combined macros by this count, so it must be >= 1.
  servings          numeric(5,1) not null default 1 check (servings >= 1),

  -- Default meal slot one logged serving lands in (overridable at log time).
  -- Mirrors food_log.meal_slot's domain; nullable.
  meal_slot         text check (meal_slot is null or meal_slot in ('breakfast','lunch','dinner','snack')),

  -- denormalised count for the list screen; client-stamped on save, NOT a
  -- trigger cache (mirrors meal_templates.item_count — see derived_state.md).
  ingredient_count  int not null default 0 check (ingredient_count >= 0),

  external_id       text,
  last_modified_at  timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

create unique index recipes_user_external_id_key
  on public.recipes (user_id, external_id) where external_id is not null;
create index recipes_user_modified_idx
  on public.recipes (user_id, last_modified_at desc);

-- ── recipe_ingredients — food items within a recipe ─────────────────────────
-- Shaped like a food_log row's macro columns (the recipe sums them). No own
-- user_id — gated via the parent. quantity is a free multiplier on the item's
-- macros (e.g. 2 = "two of these"), defaulting to 1.
create table public.recipe_ingredients (
  id                uuid primary key default gen_random_uuid(),
  recipe_id         uuid not null references public.recipes (id) on delete cascade,

  position          int not null check (position >= 0),

  item_name         text not null check (length(item_name) between 1 and 200),
  quantity          numeric(7,2) not null default 1 check (quantity >= 0),
  calories          numeric(7,1) check (calories is null or calories >= 0),
  protein_g         numeric(6,1) check (protein_g is null or protein_g >= 0),
  carbs_g           numeric(6,1) check (carbs_g is null or carbs_g >= 0),
  fat_g             numeric(6,1) check (fat_g is null or fat_g >= 0),

  -- Open Food Facts code (off:<code>) the ingredient was sourced from, kept so
  -- a recipe ingredient keeps its provenance like a direct food_log entry.
  external_id       text check (external_id is null or length(external_id) <= 200)
);

create index recipe_ingredients_recipe_idx
  on public.recipe_ingredients (recipe_id, position);

-- ── RLS — owner-scoped, deny-by-default ─────────────────────────────────────
alter table public.recipes            enable row level security;
alter table public.recipe_ingredients enable row level security;

create policy "recipes owner select"
  on public.recipes for select using (user_id = auth.uid());
create policy "recipes owner insert"
  on public.recipes for insert with check (user_id = auth.uid());
create policy "recipes owner update"
  on public.recipes for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "recipes owner delete"
  on public.recipes for delete using (user_id = auth.uid());

create policy "recipe_ingredients via parent select"
  on public.recipe_ingredients for select
  using (exists (select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()));
create policy "recipe_ingredients via parent insert"
  on public.recipe_ingredients for insert
  with check (exists (select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()));
create policy "recipe_ingredients via parent update"
  on public.recipe_ingredients for update
  using (exists (select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()))
  with check (exists (select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()));
create policy "recipe_ingredients via parent delete"
  on public.recipe_ingredients for delete
  using (exists (select 1 from public.recipes r
    where r.id = recipe_ingredients.recipe_id and r.user_id = auth.uid()));
