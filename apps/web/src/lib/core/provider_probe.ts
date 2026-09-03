/// What a CREDENTIAL PROBE of an Edge Function may conclude from a failure.
///
/// A probe asks one question — is this leg's credential set server-side? — and
/// exactly one answer says yes: a 200. Every other outcome leaves the question
/// unanswered, so the only honest verdict is unavailable, and reporting
/// anything else offers the runner an action whose very next call refuses.
///
/// The rule this replaces graded the status and read a readable 4xx as proof
/// the function "ran past the credential gate". It does not: `race-results-
/// import` answers 401 before it reads a single env var and 400
/// `unknown_provider` for a leg it does not dispatch at all, so a signed-out
/// session and a provider that does not exist both reported the card as live.
/// A status cannot carry that proof, because the only response that reaches
/// the credential check and clears it is the 200 — which is not an error and
/// never arrives here.
///
/// Fail-closed is the house default and it is also the cheaper mistake in both
/// directions: a card wrongly disabled costs one refresh, a card wrongly
/// enabled costs an import that fails after the runner has typed their bib.
export function probeSaysConfigured(error: unknown): boolean {
	return error === null || error === undefined;
}
