/// Cross-row domain shapes for the social engagement loop.
///
/// `db_rows.dart` mirrors the Postgres schema row-by-row; these
/// classes represent join-style views (a comment + its author
/// profile, a feed entry = run + author, a notification + the
/// resolved actor profile + a slice of the source run / comment)
/// that view code consumes. Living in `core_models` rather than the
/// Flutter client keeps the same shape on web and android — the
/// android `ApiClient` builds these from row joins; the SvelteKit
/// data layer constructs the equivalent TypeScript interfaces from
/// the same Supabase queries.

import 'generated/db_rows.dart';

/// Compact public-facing user view used everywhere a profile is
/// referenced from another row — feed avatar, kudos giver pills,
/// comment author, notification actor, segment athlete, …
///
/// `UserProfileRow` has more fields (preferred_unit, subscription
/// _tier, parkrun_number) that no social surface needs. Stripping
/// to id + display_name + avatar_url keeps the join payload small
/// and means a profile leak on a public surface can't accidentally
/// expose the parkrun_number.
class PublicProfile {
  final String id;
  final String? displayName;
  final String? avatarUrl;

  const PublicProfile({
    required this.id,
    this.displayName,
    this.avatarUrl,
  });

  factory PublicProfile.fromRow(UserProfileRow r) => PublicProfile(
        id: r.id,
        displayName: r.displayName,
        avatarUrl: r.avatarUrl,
      );

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// Profile + follower / following counts + whether the current
/// viewer follows the target. Powers the `/u/[id]`-equivalent
/// profile screen.
class ProfileSummary extends PublicProfile {
  final int followerCount;
  final int followingCount;
  final bool viewerFollows;

  const ProfileSummary({
    required super.id,
    super.displayName,
    super.avatarUrl,
    required this.followerCount,
    required this.followingCount,
    required this.viewerFollows,
  });
}

/// One row of the activity feed: a `RunRow` from someone the viewer
/// follows, with the author profile pre-joined so the entry card
/// can render the avatar + display name without a follow-up fetch.
class FeedEntry {
  final RunRow run;
  final PublicProfile author;

  const FeedEntry({required this.run, required this.author});
}

/// Cross-modal activity-feed entry — a run or a public gym workout.
/// Mirrors web's `ActivityFeedEntry` discriminated union (multi_modal.md
/// § Social feed). Carries `id` / `startedAt` so the feed can merge + cursor
/// both kinds on the same window.
sealed class ActivityFeedEntry {
  PublicProfile get author;
  String get id;
  DateTime get startedAt;
}

/// A run surfaced in the feed.
class RunFeedEntry extends ActivityFeedEntry {
  final RunRow run;
  @override
  final PublicProfile author;

  RunFeedEntry({required this.run, required this.author});

  @override
  String get id => run.id;
  @override
  DateTime get startedAt => run.startedAt;
}

/// A public gym workout surfaced in the feed as a "lift card" — only the
/// non-sensitive headline (title / set count / total volume in canonical kg).
/// No notes / RPE / per-set detail leak into the feed.
class LiftFeedEntry extends ActivityFeedEntry {
  @override
  final String id;
  @override
  final DateTime startedAt;
  final String? title;
  final int setCount;
  final double volumeKg;
  @override
  final PublicProfile author;

  LiftFeedEntry({
    required this.id,
    required this.startedAt,
    required this.title,
    required this.setCount,
    required this.volumeKg,
    required this.author,
  });
}

/// A comment with the author profile resolved. Used by the
/// comments thread on run-detail / public-share screens.
class RunCommentWithAuthor {
  final RunCommentRow comment;
  final PublicProfile author;

  const RunCommentWithAuthor({required this.comment, required this.author});
}

/// Notification + resolved actor + a small slice of the source
/// row(s) needed to render the verb line ("Alice gave kudos to your
/// 12 km", "Bob replied to your comment"). The view code shouldn't
/// need a follow-up `runs` fetch to render distance, so we carry
/// `run_distance_m` on the view; same for the comment excerpt.
class NotificationView {
  final NotificationRow row;
  final PublicProfile? actor;
  final double? runDistanceM;
  final String? commentExcerpt;
  final String? eventTitle;
  final String? eventClubSlug;
  final String? clubName;
  final String? clubSlug;

  const NotificationView({
    required this.row,
    this.actor,
    this.runDistanceM,
    this.commentExcerpt,
    this.eventTitle,
    this.eventClubSlug,
    this.clubName,
    this.clubSlug,
  });
}

/// Per-run kudos + comment count rollup with the viewer's own
/// kudos state. Drives the kudos pill / comment chip on every
/// surface that lists runs.
class EngagementSummary {
  final int kudosCount;
  final bool viewerHasKudos;
  final int commentCount;

  const EngagementSummary({
    required this.kudosCount,
    required this.viewerHasKudos,
    required this.commentCount,
  });
}

/// One row of a segment leaderboard: an effort + the athlete +
/// the rank. Rank is computed client-side after sorting by
/// `time_seconds`, dedupe-by-user.
class SegmentLeaderboardEntry {
  final SegmentEffortRow effort;
  final PublicProfile athlete;
  final int rank;

  const SegmentLeaderboardEntry({
    required this.effort,
    required this.athlete,
    required this.rank,
  });
}

/// One row of the social-people search / suggested list: profile +
/// public-runs count + how many of the viewer's clubs they share +
/// whether the viewer follows them. Drives the People discovery
/// surface (web: `/social?tab=people`, mobile: feed AppBar entry).
class PeopleSuggestion extends PublicProfile {
  final int publicRunsCount;
  final int sharedClubs;
  final bool viewerFollows;

  const PeopleSuggestion({
    required super.id,
    super.displayName,
    super.avatarUrl,
    required this.publicRunsCount,
    required this.sharedClubs,
    required this.viewerFollows,
  });
}

/// One row of a run's segment-effort summary: the effort + the parent
/// segment + the rank against the segment's leaderboard. Backs the
/// per-run effort chips on the run-detail page.
class SegmentEffortWithSegment {
  final SegmentEffortRow effort;
  final SegmentRow segment;
  final int rank;

  const SegmentEffortWithSegment({
    required this.effort,
    required this.segment,
    required this.rank,
  });
}

/// A single (lat, lng) sample returned by `heatmap_points_in_bbox`.
/// Mobile mirror of the web `HeatmapPoint` interface; renders as a
/// low-opacity circle on the heatmap layer so stacking creates the
/// heat-density visual.
class HeatmapPoint {
  final double lat;
  final double lng;

  const HeatmapPoint({required this.lat, required this.lng});
}

/// A discoverable public route pin returned by `discoverable_routes_in_bbox`.
/// Mobile mirror of the web `DiscoverableRoutePin` interface — featured /
/// popular / friends' / hidden-gem routes the discovery map drops a pin
/// at (the start point).
class DiscoverableRoutePin {
  final String id;
  final String name;
  final String? slug;
  final bool featured;
  final double distanceM;
  final double? elevationM;
  final String surface;
  final int runCount;
  final double lat;
  final double lng;

  const DiscoverableRoutePin({
    required this.id,
    required this.name,
    this.slug,
    required this.featured,
    required this.distanceM,
    this.elevationM,
    required this.surface,
    required this.runCount,
    required this.lat,
    required this.lng,
  });
}

/// A club pin returned by `clubs_in_bbox`. Mobile mirror of the web
/// club-pin shape used by the discovery map's club layer.
class ClubPin {
  final String id;
  final String name;
  final String? slug;
  final String? avatarUrl;
  final String? locationLabel;
  final int memberCount;
  final double lat;
  final double lng;

  const ClubPin({
    required this.id,
    required this.name,
    this.slug,
    this.avatarUrl,
    this.locationLabel,
    required this.memberCount,
    required this.lat,
    required this.lng,
  });
}

/// A safety contact the owner added (decisions §131). Mobile mirror of the
/// web `SafetyContact` interface. Carries only the owner-readable columns the
/// settings list shows — never `confirm_token` (the email-link capability) or
/// `owner_id`. `confirmedAt == null` means pending (the contact hasn't opted
/// in yet, so no finish alerts are sent).
class SafetyContact {
  final String id;
  final String contactEmail;
  final String? contactUserId;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  const SafetyContact({
    required this.id,
    required this.contactEmail,
    this.contactUserId,
    this.confirmedAt,
    required this.createdAt,
  });

  bool get isConfirmed => confirmedAt != null;

  factory SafetyContact.fromJson(Map<String, dynamic> json) => SafetyContact(
        id: json['id'] as String,
        contactEmail: json['contact_email'] as String,
        contactUserId: json['contact_user_id'] as String?,
        confirmedAt: json['confirmed_at'] == null
            ? null
            : DateTime.parse(json['confirmed_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// A pending safety-contact request addressed to the signed-in user's account
/// email (decisions §131). Mobile mirror of the web `PendingSafetyRequest`
/// interface. Returned by the `my_pending_safety_requests` SECURITY DEFINER
/// RPC, which only ever surfaces rows whose `contact_email` equals the
/// caller's own email — so it leaks nothing about other users.
class PendingSafetyRequest {
  final String id;
  final String ownerName;
  final DateTime createdAt;

  const PendingSafetyRequest({
    required this.id,
    required this.ownerName,
    required this.createdAt,
  });

  factory PendingSafetyRequest.fromJson(Map<String, dynamic> json) =>
      PendingSafetyRequest(
        id: json['id'] as String,
        ownerName: (json['owner_name'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
