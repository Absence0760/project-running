/// The in-app surface a tapped push notification should open.
///
/// The Go worker stamps an ABSOLUTE web URL into the notification's `url`
/// data key (`pathForKind` in `apps/job_worker/internal/mailer.go`, shared by
/// the email CTA, the web-push payload and the native FCM/APNs message), so
/// the phone receives e.g. `https://threkir.com/runs/<id>`. This maps that URL
/// onto a typed target the app can navigate to.
///
/// Pure — no BuildContext, no navigation, no I/O — so the whole target table
/// is host-testable. The host ([HomeScreen]) owns the actual push.
enum PushTargetKind {
  /// The notifications inbox. Also the degrade-to target for anything we
  /// can't recognise, mirroring `pathForKind`'s own `default:` arm — a
  /// notification the app can't place still opens the list it came from
  /// rather than being silently dropped.
  notifications,

  /// A user profile (`/u/<id>`).
  profile,

  /// A single run (`/runs/<id>`).
  run,

  /// The training-plan list (`/plans`).
  plans,

  /// The challenge list (`/challenges`).
  challenges,

  /// The clubs hub (`/clubs`) — the worker's fallback when a club- or
  /// event-scoped notification carries no id.
  clubs,

  /// A single club (`/clubs/<id>`). Carries the club UUID; the mobile club
  /// screen is slug-addressed, so the host resolves id → slug before pushing.
  club,

  /// A single club event (`/events/<id>`). Carries the event UUID; the host
  /// resolves the owning club's slug before pushing.
  event,

  /// Settings → Account (`/settings/account`), where a finished Art 20
  /// export is collected. Carries no id: the export lives in
  /// `data_export_jobs` and the screen reads the subject's latest one.
  settingsAccount,
}

/// A resolved push target: a [kind] plus the entity id when the kind carries
/// one. Value type so tests can compare targets directly.
class PushTarget {
  const PushTarget(this.kind, [this.id]);

  final PushTargetKind kind;
  final String? id;

  static const inbox = PushTarget(PushTargetKind.notifications);

  @override
  bool operator ==(Object other) =>
      other is PushTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'PushTarget(${kind.name}${id == null ? '' : ', $id'})';
}

/// Maps a push notification's `url` data key onto a [PushTarget].
///
/// Total and never throws: a null / blank / unparseable / unknown URL resolves
/// to [PushTarget.inbox]. The origin is ignored on purpose — the same build
/// receives links stamped with whichever `APP_BASE_URL` the environment runs
/// (prod, preview, a local worker), and a relative path is accepted too.
PushTarget pushTargetFromUrl(String? url) {
  if (url == null) return PushTarget.inbox;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return PushTarget.inbox;

  // pathSegments drops the origin and the query/fragment and percent-decodes
  // each segment; the empty filter absorbs a trailing slash and any doubled
  // separator. Wrapped because this runs on a payload we didn't author — a
  // throw here would lose the tap, and the inbox is the honest degrade.
  List<String> segments;
  try {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return PushTarget.inbox;
    segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
  } catch (_) {
    return PushTarget.inbox;
  }
  if (segments.isEmpty) return PushTarget.inbox;

  final head = segments.first;
  final id = segments.length > 1 ? segments[1] : null;

  switch (head) {
    case 'events':
      return id == null ? const PushTarget(PushTargetKind.clubs)
                        : PushTarget(PushTargetKind.event, id);
    case 'clubs':
      return id == null ? const PushTarget(PushTargetKind.clubs)
                        : PushTarget(PushTargetKind.club, id);
    case 'runs':
      return id == null ? PushTarget.inbox : PushTarget(PushTargetKind.run, id);
    case 'u':
      return id == null
          ? PushTarget.inbox
          : PushTarget(PushTargetKind.profile, id);
    case 'settings':
      // Only the Account screen is a push destination today. Any other
      // settings path degrades to the inbox rather than dumping the runner
      // on a screen the notification was not about.
      return id == 'account'
          ? const PushTarget(PushTargetKind.settingsAccount)
          : PushTarget.inbox;
    case 'plans':
      return const PushTarget(PushTargetKind.plans);
    case 'challenges':
      return const PushTarget(PushTargetKind.challenges);
    // `/messages` has no mobile surface (web-only, decisions §24), so a
    // message push lands on the inbox where the same notification is listed.
    case 'messages':
    case 'notifications':
      return PushTarget.inbox;
    default:
      return PushTarget.inbox;
  }
}
