-- Extended nutrient columns on food_log (issue #492).
--
-- v1 tracked only the four headline macros (calories, protein, carbs, fat).
-- These five commonly-labelled nutrients round out a nutrition-facts panel
-- and are already carried upstream by Open Food Facts + USDA FoodData Central,
-- so a searched food logs them for free. All nullable — a manually-entered or
-- upstream-incomplete item simply leaves them null (never a phantom 0).
--
-- Units follow the label convention: grams for fibre / sugar / saturated fat,
-- milligrams for sodium / cholesterol (the units both food databases and every
-- packaged label report them in). food_log is owner-private + low-volume, and
-- these are new nullable columns whose inline CHECK holds trivially over the
-- all-null existing rows, so no online-safety two-step is needed.

alter table public.food_log
  add column fiber_g         numeric(6, 1) check (fiber_g is null or fiber_g >= 0),
  add column sugar_g         numeric(6, 1) check (sugar_g is null or sugar_g >= 0),
  add column sodium_mg       numeric(7, 1) check (sodium_mg is null or sodium_mg >= 0),
  add column saturated_fat_g numeric(6, 1) check (saturated_fat_g is null or saturated_fat_g >= 0),
  add column cholesterol_mg  numeric(6, 1) check (cholesterol_mg is null or cholesterol_mg >= 0);
