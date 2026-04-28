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

  const NotificationView({
    required this.row,
    this.actor,
    this.runDistanceM,
    this.commentExcerpt,
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
