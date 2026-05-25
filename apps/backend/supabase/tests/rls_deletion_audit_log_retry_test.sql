-- Pin the audit-round-3 fix to deletion_audit_log:
-- A failed delete followed by a successful retry must produce TWO
-- rows in the audit log (not a 23505 conflict that drops the
-- success row). The trail goes failure → retry → success, which
-- is exactly the evidence a regulator needs.

begin;

select plan(4);

set local role service_role;

-- 1. First insert — failure code.
do $$
begin
  insert into deletion_audit_log (hashed_user_id, result)
  values
    (
      'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888',
      'storage_drain_failed'
    );
end $$;
select pass('first audit row (storage_drain_failed) accepted');

-- 2. Retry — success code, same hashed_user_id. Must NOT 23505.
do $$
begin
  insert into deletion_audit_log (hashed_user_id, result)
  values
    (
      'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888',
      'ok'
    );
end $$;
select pass('retry audit row (ok) accepted alongside the failed-attempt row');

-- 3. Both rows are present, ordered by deleted_at.
select is(
  (select count(*)::int from deletion_audit_log
     where hashed_user_id = 'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888'),
  2,
  'both rows persist (audit-round-3 expectation)'
);

-- 4. The synthetic id PK is auto-assigned + distinct.
select isnt(
  (select id from deletion_audit_log
     where hashed_user_id = 'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888'
       and result = 'storage_drain_failed'),
  (select id from deletion_audit_log
     where hashed_user_id = 'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888'
       and result = 'ok'),
  'synthetic id PK assigns distinct ids to retry rows'
);

select * from finish();
rollback;
