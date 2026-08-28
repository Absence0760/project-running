/// The Stripe SDK for the whole tier, imported once so that its
/// declarations actually resolve. Import Stripe from here, never from a
/// URL — `stripe_boundary.test.ts` fails on a direct import.
///
/// esm.sh does serve stripe's declarations: it advertises them on the
/// module's `x-typescript-types` header and Deno fetches all ~450 of
/// them, with no error anywhere in the graph. But it rewrites the ambient
/// `declare module 'stripe'` inside the entry declaration to name that
/// declaration file's own URL, and TypeScript matches an ambient module
/// declaration against the LITERAL text of an import specifier rather
/// than against what the specifier resolves to. A module importing
/// `https://esm.sh/stripe@17.5.0?target=deno` therefore matches no
/// ambient declaration; the file it does resolve to has no top-level
/// exports of its own, since everything is inside that block; and the
/// import silently becomes `any`. Every Stripe call in the tier was
/// checked against nothing — worse than unchecked, because an `any`
/// assigned into a narrowed local widens it back. Decisions § 765.
///
/// The directive below points at a declaration file whose own import IS
/// that literal string, which is what makes the declarations bind.
/// Nothing about the runtime graph changes: the specifier still carries
/// `?target=deno` per decisions § 699, and a declaration file is erased
/// before anything is bundled.

// @ts-types="./stripe_types.d.ts"
import Stripe from 'https://esm.sh/stripe@17.5.0?target=deno';

/// The proof that the line above worked, and the reason this file cannot
/// go quietly back to `any` on a Deno release, an esm.sh change or a
/// version bump.
///
/// It has to be a NEGATIVE test. Every assignability test passes under
/// `any`, in both directions, so a positive assertion is satisfied by the
/// very collapse it exists to catch — including the usual
/// `0 extends 1 & T` any-detector, which over this import resolves to
/// `any` itself and then satisfies any constraint at all. That was tried
/// first and reported nothing with the directive deleted, which is the
/// failure mode this whole entry is about: a check that goes quiet.
/// `Account.id` is a string, so constraining it to `number` must fail; if
/// it ever stops failing, the directive below is unused and `deno check`
/// reports THAT instead, naming this file. No source-grep guard could see
/// a collapse here — the import it would grep for is unchanged.
type MustBeNumber<T extends number> = T;
// @ts-expect-error -- Stripe.Account['id'] is a string, not a number.
type StripeDeclarationsBind = MustBeNumber<Stripe.Account['id']>;
export type { StripeDeclarationsBind };

/// Assert that every key of a hand-shaped params object is one the SDK's
/// own params type declares. Used as a pair at the call site, which is
/// where Stripe is already imported:
///
///   type _ = AssertNoUnknownParamKeys<
///     UnknownParamKeys<Shape, Stripe.SomeCreateParams>
///   >;
///
/// Assignability alone does not check this. The value handed to a Stripe
/// call is a function RETURN, not a fresh object literal, so TypeScript
/// runs no excess-property check on it: a params helper carrying a
/// misspelled optional field compiles, and Stripe answers `Received
/// unknown parameter` at request time — a 502 for every caller. Measured
/// on this tree with the declarations fully bound: a `defualt_currency`
/// added to `events-connect-onboard`'s `AccountCreateParams` passed
/// `deno check` without a word.
///
/// The params helpers themselves stay Stripe-free on purpose:
/// `events-checkout`'s is imported by `stripe-events-webhook`, which has
/// no Stripe in its graph and must not grow the `?target=deno` polyfill
/// tree to get one (decisions § 699 measured that at 228 KB -> 2.4 MB
/// per eszip). So the assertion lives at the call site instead of in the
/// helper's return type.
export type UnknownParamKeys<Shape, Params> = Exclude<keyof Shape, keyof Params>;
export type AssertNoUnknownParamKeys<K extends never> = K;

export default Stripe;
