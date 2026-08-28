/// Run with `cd apps/backend && deno test --allow-read supabase/functions/events-connect-onboard/wiring.test.ts`.
///
/// Source-grep guards in the `stripe-events-webhook/wiring.test.ts` idiom.
/// `lib.test.ts` proves the account params are shaped right; it cannot see
/// whether the CREATE carries an idempotency key, and an unkeyed create is the
/// one that leaves live Stripe accounts stranded on the platform.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the connected-account create is keyed on the host', () => {
  // A host has exactly one payout account. An attempt that created the account
  // and then failed to persist it created a SECOND one on the retry and
  // abandoned the first, live and unreachable, on the platform.
  const create = SRC.indexOf('stripe.accounts.create');
  assert(create !== -1, 'the account create is gone — has it moved?');
  const end = SRC.indexOf('} catch', create);
  assert(end > create, 'could not find the end of the account create call');
  assert(
    SRC.slice(create, end).includes('{ idempotencyKey: `events-connect-onboard:${user.id}` }'),
    'the account create must carry a key derived from the host, not from this request',
  );
});

Deno.test('the account LINK is deliberately unkeyed', () => {
  // The inverse guard. An account link is single-use and short-lived, so a key
  // here would replay a spent URL to a host returning to finish onboarding —
  // the opposite failure to the one above, and just as invisible.
  const create = SRC.indexOf('stripe.accountLinks.create');
  assert(create !== -1, 'the account link create is gone');
  const end = SRC.indexOf('} catch', create);
  assert(end > create, 'could not find the end of the account link call');
  assert(
    !SRC.slice(create, end).includes('idempotencyKey'),
    'replaying a spent account link hands the host a dead URL',
  );
});
