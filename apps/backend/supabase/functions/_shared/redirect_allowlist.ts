/// The one parse of a comma-separated `*_ALLOWED_REDIRECTS` env var, and
/// the whole-URL comparison the Strava OAuth exchange pins its
/// client-claimed `redirect_uri` against.
///
/// Four Edge Functions gate a redirect on an operator-declared allowlist
/// — `strava-import` on `STRAVA_ALLOWED_REDIRECTS`, and
/// `donations-checkout` / `events-checkout` / `events-connect-onboard` on
/// `STRIPE_EVENTS_ALLOWED_REDIRECTS` — and each had copied the split /
/// trim / filter inline. Every one of them then treats an empty result as
/// "not configured" and fails closed, so a fifth copy that split on the
/// wrong character would fail closed too; the copy that matters is one
/// that stops filtering blanks, because `'a,,b'` would then admit the
/// empty string and any caller claiming `redirect_uri: ''`. The parse
/// lives here and `redirect_allowlist.test.ts` guards that no function
/// spells it out again.

export function parseRedirectAllowlist(raw: string | null | undefined): string[] {
  return (raw ?? '').split(',').map((s) => s.trim()).filter(Boolean);
}

/// Whether `redirectUri` is an entry of `allowlist`, compared whole.
///
/// Deliberately stricter than the origin match `validateReturnUrl`
/// (`events-connect-onboard/lib.ts`) applies to the Stripe return URLs.
/// Those are operator-configured and legitimately carry a query string,
/// so an origin match is the right shape for them. The Strava
/// `redirect_uri` is not: Strava's own `/oauth/authorize` already pins
/// the callback to the registered Authorization Callback Domain, and the
/// gap this allowlist exists to close is that its check is path-prefix
/// loose — any path under our domain counts. Matching on origin here
/// would re-open exactly that window.
///
/// Fails closed on a non-string or empty claim and on an empty
/// allowlist. Callers still report the empty-allowlist case separately
/// (503, not 400): an unset env var is an operator error, and answering
/// the caller "your redirect_uri is wrong" would send an operator
/// hunting the wrong bug.
export function isExactRedirectAllowed(
  redirectUri: unknown,
  allowlist: readonly string[],
): boolean {
  if (typeof redirectUri !== 'string' || redirectUri.length === 0) return false;
  return allowlist.includes(redirectUri);
}
