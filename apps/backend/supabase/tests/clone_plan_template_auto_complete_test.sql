-- Pins migration 20260529000004 — clone_plan_template auto-completes
-- the caller's existing active plan before inserting the new one.
-- Persona-hunt Round 2 finding Intermediate #1.

begin;
select plan(3);

-- Seed: a user with an existing active plan + a club-owned template
-- they want to adopt.
do $$
declare
  v_user uuid := '99999999-9999-9999-9999-9999bbaa0001';
  v_club uuid := '99999999-9999-9999-9999-9999bbaa0c01';
  v_template uuid := gen_random_uuid();
  v_active_plan uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'plan-adopt@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_user, 'Plan Adopter', 'km', 'free')
    on conflict (id) do nothing;
  insert into clubs (id, slug, name, is_public, join_policy, owner_id)
    values (v_club, 'plan-club', 'Plan Club', true, 'open', v_user)
    on conflict (id) do nothing;
  insert into club_members (club_id, user_id, role, status, joined_at)
    values (v_club, v_user, 'member', 'active', now())
    on conflict (club_id, user_id) do nothing;

  -- The user's existing active plan.
  insert into training_plans (
    id, user_id, name, goal_event, goal_distance_m,
    start_date, end_date, days_per_week, status, is_template
  ) values (
    v_active_plan, v_user, 'My existing plan', 'distance_10k', 10000,
    current_date - 7, current_date + 49, 4, 'active', false
  );

  -- A club-published template.
  insert into training_plans (
    id, user_id, club_id, name, goal_event, goal_distance_m,
    start_date, end_date, days_per_week, status, is_template
  ) values (
    v_template, v_user, v_club, 'Spring Half template',
    'distance_half', 21097, current_date, current_date + 84,
    4, 'completed', true
  );

  -- Persist ids for the test by storing in session settings.
  perform set_config('persona.user', v_user::text, true);
  perform set_config('persona.template', v_template::text, true);
  perform set_config('persona.active_plan', v_active_plan::text, true);
end $$;

-- Pretend we're authenticated as the test user so auth.uid() in the
-- RPC returns the right value.
set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-9999bbaa0001","role":"authenticated"}';
set local role = 'authenticated';

-- Call the RPC.
do $$
declare
  v_new_plan uuid;
begin
  select clone_plan_template(
    current_setting('persona.template', true)::uuid,
    current_date + 1
  ) into v_new_plan;
  perform set_config('persona.new_plan', v_new_plan::text, true);
end $$;

reset role;

-- 1. The previous active plan is now `completed`.
select is(
  (select status from training_plans
   where id = current_setting('persona.active_plan', true)::uuid),
  'completed',
  'Existing active plan auto-completes when Adopt clones a new one'
);

-- 2. The new clone is `active`.
select is(
  (select status from training_plans
   where id = current_setting('persona.new_plan', true)::uuid),
  'active',
  'Cloned plan lands as active'
);

-- 3. Only one active plan for the user (the `one_active` partial
-- unique index is the contract; double-active would violate it).
select is(
  (select count(*) from training_plans
   where user_id = current_setting('persona.user', true)::uuid
     and status = 'active'
     and is_template = false),
  1::bigint,
  'Exactly one active plan post-clone (training_plans_one_active honoured)'
);

rollback;
