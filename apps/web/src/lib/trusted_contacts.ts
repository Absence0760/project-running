// Trusted contacts — list of designated people who get notified if
// a run goes wrong (overdue finish, panic button, etc).
//
// Persona-hunt Round 3 finding Woman #4. A runner heading out for a
// solo long run wants to designate one or more trusted contacts as
// part of their pre-run safety routine. This module is the scaffold:
// the data type + pref key + a single sanitiser. The actual
// notify-on-overdue / panic-button delivery logic is deferred until
// the safety surface lands — we want the storage shape locked in
// first so runners can start populating their list ahead of the
// feature.
//
// Pure functions, no Svelte / Supabase dependencies — same shape as
// `privacy.ts`. Mobile twin lives at
// `apps/mobile_android/lib/trusted_contacts.dart` (byte-identical to
// the iOS twin per the one-Dart-codebase rule).

export interface TrustedContact {
	/// Required. Display name of the contact. Trimmed; empty rejected
	/// at the editor.
	name: string;
	/// E.164 phone number (or local-format — we don't validate yet).
	/// Optional because some users will prefer email-only.
	phone?: string;
	/// Email address. Same optionality as phone.
	email?: string;
	/// Free-form relationship label ("partner", "parent", "running
	/// buddy"). Optional. Surface-only — never required.
	relationship?: string;
}

export const TRUSTED_CONTACTS_KEY = 'trusted_contacts';

/// Reasonable cap so a runaway editor can't blow up the universal-
/// prefs bag. Five is enough to cover spouse + parent + best friend +
/// run partner + emergency operator without becoming an address book.
export const MAX_TRUSTED_CONTACTS = 5;

/// Normalise a single contact: trim every string field, drop empties.
/// Returns null if `name` is missing — name is the only required
/// field and an entry without it is not a contact.
export function normaliseTrustedContact(input: TrustedContact): TrustedContact | null {
	const name = input.name?.trim() ?? '';
	if (name.length === 0) return null;
	const out: TrustedContact = { name };
	const phone = input.phone?.trim();
	if (phone) out.phone = phone;
	const email = input.email?.trim();
	if (email) out.email = email;
	const relationship = input.relationship?.trim();
	if (relationship) out.relationship = relationship;
	return out;
}

/// Normalise an entire list — drops invalid entries + caps at
/// MAX_TRUSTED_CONTACTS. Returns a fresh array; never mutates input.
export function normaliseTrustedContacts(
	input: TrustedContact[] | null | undefined,
): TrustedContact[] {
	if (!input) return [];
	const out: TrustedContact[] = [];
	for (const c of input) {
		const n = normaliseTrustedContact(c);
		if (n) out.push(n);
		if (out.length >= MAX_TRUSTED_CONTACTS) break;
	}
	return out;
}

/// Quick safety check at editor-submit time: returns true when the
/// contact has at least one reachable channel. The notify-on-overdue
/// path (when it lands) is useless without a phone OR email — a
/// name-only entry would silently produce zero notifications. UI
/// surfaces a warning rather than blocking, since a runner may still
/// want to record someone they'll call manually.
export function hasReachableChannel(c: TrustedContact): boolean {
	return Boolean((c.phone && c.phone.length > 0) || (c.email && c.email.length > 0));
}
