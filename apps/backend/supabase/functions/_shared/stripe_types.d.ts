/// The Stripe SDK's real declarations, reached by the ONE specifier that
/// binds them.
///
/// esm.sh rewrites the ambient `declare module 'stripe'` inside stripe's
/// entry declaration to name this file's own URL, and TypeScript matches
/// an ambient module declaration against the LITERAL text of an import
/// specifier. So importing exactly this string is what resolves the
/// declarations, and importing the runtime module — a different string —
/// resolves nothing at all. `stripe.ts` is where that is explained and
/// where it is used; nothing else should import this file.
///
/// The version here must match `stripe.ts`'s runtime specifier, which
/// `stripe_boundary.test.ts` pins.
import Stripe from 'https://esm.sh/stripe@17.5.0/types/index.d.ts';

export default Stripe;
