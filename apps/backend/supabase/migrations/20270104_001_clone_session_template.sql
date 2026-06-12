-- Club-published session templates — the session-planner P3 analogue of the
-- training-plan club-template flow (clone_plan_template, 20260524_001 /
-- 20261010_001). A club-owned session plan (session_plans.club_id set) is the
-- "template"; a member adopts it by cloning the head + blocks + items into a new
-- personal plan (author_id = caller, club_id = null, is_public = false).
--
-- Mirrors clone_plan_template's shape: SECURITY DEFINER (so the membership
-- check is reliable regardless of the caller's row visibility), an
-- enforce_create_rate_limit anti-bulk-clone guard, and an authorisation gate
-- that allows the template's author or any member of its owning club. A session
-- plan carries no private fitness data (unlike a training plan's vdot /
-- current_5k_seconds), so there is nothing to strip on clone.

create or replace function clone_session_template(template_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  tmpl session_plans%rowtype;
  new_plan_id uuid;
  new_block_id uuid;
  block_record record;
  item_record record;
begin
  if caller is null then
    raise exception 'clone_session_template: not authenticated';
  end if;

  -- Anti-bulk-clone rate limit, same shape + budget as clone_plan_template.
  perform enforce_create_rate_limit('clone_session_template', caller, 20, 3600);

  select * into tmpl from session_plans where id = template_id;
  if not found then
    raise exception 'clone_session_template: template not found';
  end if;

  -- Author, or any member of the owning club, may clone. A purely personal
  -- plan (no club_id) is clonable only by its author.
  if tmpl.author_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
  then
    raise exception 'clone_session_template: not authorised to clone template %', template_id;
  end if;

  insert into session_plans (
    author_id, club_id, title, discipline, equipment, est_duration_min, is_public
  )
  values (
    caller, null, tmpl.title, tmpl.discipline, tmpl.equipment, tmpl.est_duration_min, false
  )
  returning id into new_plan_id;

  -- Copy blocks (preserving position) and remember the old->new id mapping so
  -- items keep their block grouping.
  for block_record in
    select * from session_plan_blocks where plan_id = template_id order by position
  loop
    insert into session_plan_blocks (plan_id, position, name)
    values (new_plan_id, block_record.position, block_record.name)
    returning id into new_block_id;

    for item_record in
      select * from session_plan_items
      where plan_id = template_id and block_id = block_record.id
      order by position
    loop
      insert into session_plan_items (
        plan_id, block_id, position, movement_name, kind,
        duration_s, reps, per_side, tempo, cue
      )
      values (
        new_plan_id, new_block_id, item_record.position, item_record.movement_name,
        item_record.kind, item_record.duration_s, item_record.reps,
        item_record.per_side, item_record.tempo, item_record.cue
      );
    end loop;
  end loop;

  -- Blockless items (block_id is null) copy across with a null block.
  for item_record in
    select * from session_plan_items
    where plan_id = template_id and block_id is null
    order by position
  loop
    insert into session_plan_items (
      plan_id, block_id, position, movement_name, kind,
      duration_s, reps, per_side, tempo, cue
    )
    values (
      new_plan_id, null, item_record.position, item_record.movement_name,
      item_record.kind, item_record.duration_s, item_record.reps,
      item_record.per_side, item_record.tempo, item_record.cue
    );
  end loop;

  return new_plan_id;
end;
$$;

revoke execute on function clone_session_template(uuid) from public;
grant execute on function clone_session_template(uuid) to authenticated;
