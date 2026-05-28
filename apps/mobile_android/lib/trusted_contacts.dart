/// Trusted contacts — list of designated people who get notified if
/// a run goes wrong (overdue finish, panic button, etc).
///
/// Persona-hunt Round 3 finding Woman #4. Mobile twin of
/// `apps/web/src/lib/trusted_contacts.ts`. Keep both in lockstep —
/// the `shared-library-syncer` agent flags divergence.
///
/// Pure-data + pure-functions module. No Flutter / Supabase deps.

class TrustedContact {
  final String name;
  final String? phone;
  final String? email;
  final String? relationship;

  const TrustedContact({
    required this.name,
    this.phone,
    this.email,
    this.relationship,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (relationship != null) 'relationship': relationship,
      };

  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
        name: (j['name'] as String?) ?? '',
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        relationship: j['relationship'] as String?,
      );
}

const String kTrustedContactsKey = 'trusted_contacts';

/// Cap pinned to the web side. Surface to UI rather than failing
/// silently when the user tries to add a sixth.
const int kMaxTrustedContacts = 5;

/// Normalise a single contact — trim every string field, drop empties.
/// Returns null when `name` is missing (name is required; an entry
/// without it is not a contact).
TrustedContact? normaliseTrustedContact(TrustedContact input) {
  final name = input.name.trim();
  if (name.isEmpty) return null;
  final phone = input.phone?.trim();
  final email = input.email?.trim();
  final relationship = input.relationship?.trim();
  return TrustedContact(
    name: name,
    phone: (phone != null && phone.isNotEmpty) ? phone : null,
    email: (email != null && email.isNotEmpty) ? email : null,
    relationship:
        (relationship != null && relationship.isNotEmpty) ? relationship : null,
  );
}

/// Normalise an entire list — drops invalid entries + caps at
/// kMaxTrustedContacts. Returns a fresh list; never mutates input.
List<TrustedContact> normaliseTrustedContacts(List<TrustedContact>? input) {
  if (input == null || input.isEmpty) return const [];
  final out = <TrustedContact>[];
  for (final c in input) {
    final n = normaliseTrustedContact(c);
    if (n != null) out.add(n);
    if (out.length >= kMaxTrustedContacts) break;
  }
  return out;
}

/// True when the contact has at least one reachable channel.
bool hasReachableChannel(TrustedContact c) {
  return (c.phone != null && c.phone!.isNotEmpty) ||
      (c.email != null && c.email!.isNotEmpty);
}
