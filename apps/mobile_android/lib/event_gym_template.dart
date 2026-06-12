/// The class -> gym seam: a typed contract over the loose `events.gym_template`
/// jsonb bag (migration 20261227_001 + the SELECT grant in 20261230_001).
///
/// `gym_template` is meaningful only for `category == 'class'`. A host attaches
/// an optional discipline + default duration; an attendee one-tap-logs the
/// class as a gym workout, pre-filled from this template (they confirm in the
/// composer — inform-tier, nothing auto-writes).
///
/// Web twin: `apps/web/src/lib/social/event_gym_template.ts` — keep in lockstep
/// (same parse tolerance, same build rules, same draft shape).
library;

import 'session_steps.dart';

class EventGymTemplate {
  const EventGymTemplate({required this.discipline, required this.durationMin});

  final String? discipline;
  final int? durationMin;
}

/// The minimal composer seed the seam produces from a template.
class GymWorkoutDraft {
  const GymWorkoutDraft({required this.title, required this.durationS});

  final String? title;
  final int? durationS;
}

String? _asString(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _asPositiveInt(Object? v) {
  if (v is! num || !v.isFinite) return null;
  final n = v.floor();
  return n > 0 ? n : null;
}

/// Parse the raw jsonb into a typed template, tolerant of the loose bag.
/// Returns `null` when the value is absent, malformed, or carries neither a
/// discipline nor a duration (an effectively-empty template), so callers can
/// treat "no template" and "empty template" identically.
EventGymTemplate? parseGymTemplate(Object? json) {
  if (json is! Map) return null;
  final discipline = _asString(json['discipline']);
  final durationMin = _asPositiveInt(json['duration_min']);
  if (discipline == null && durationMin == null) return null;
  return EventGymTemplate(discipline: discipline, durationMin: durationMin);
}

/// Build the template to persist from the editor inputs. Returns `null` when
/// both are empty so a class without a template writes NULL (not `{}`), which
/// keeps the attendee affordance hidden for an un-templated class.
EventGymTemplate? gymTemplateFromInputs(String? discipline, int? durationMin) {
  final d = _asString(discipline);
  final m = _asPositiveInt(durationMin);
  if (d == null && m == null) return null;
  return EventGymTemplate(discipline: d, durationMin: m);
}

/// Produce the composer prefill from a template. The title falls back to the
/// event title when the class carries no discipline; sets stay empty for the
/// user to fill in the composer.
GymWorkoutDraft workoutDraftFromTemplate(
  EventGymTemplate? template,
  String? eventTitle,
) {
  final title = template?.discipline ?? _asString(eventTitle);
  final min = template?.durationMin;
  return GymWorkoutDraft(
    title: title,
    durationS: min == null ? null : min * 60,
  );
}

/// One logged set per expanded session step (the class -> gym log seam, M5).
class SessionDraftItem {
  const SessionDraftItem({
    required this.exerciseName,
    required this.durationS,
    required this.reps,
  });

  final String exerciseName;
  final int? durationS;
  final int? reps;
}

/// The gym-log prefill from an expanded session plan (M5 follow-along log):
/// the draft head plus one set per expanded step.
class SessionWorkoutDraft {
  const SessionWorkoutDraft({
    required this.title,
    required this.durationS,
    required this.sets,
  });

  final String? title;
  final int? durationS;
  final List<SessionDraftItem> sets;
}

/// Produce the gym-log prefill from an expanded session plan (M5 follow-along
/// log). The title prefers the class discipline, falling back to the plan
/// title; the duration is the plan's total estimate. Each expanded step becomes
/// one set (a per-side step stays two rows) — the side word is never baked into
/// the exercise name, callers localize it.
SessionWorkoutDraft workoutDraftFromSession(
  ExpandedSession expanded,
  String? planTitle,
  String? discipline,
) {
  final title = _asString(discipline) ?? _asString(planTitle);
  return SessionWorkoutDraft(
    title: title,
    durationS: expanded.totalS > 0 ? expanded.totalS : null,
    sets: [
      for (final step in expanded.steps)
        SessionDraftItem(
          exerciseName: step.movementName,
          durationS: step.durationS,
          reps: step.reps,
        ),
    ],
  );
}
