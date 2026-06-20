import 'dart:async';
import 'dart:io' show Platform;

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../event_category.dart';
import '../event_gym_template.dart';
import '../finisher_certificate.dart';
import '../local_gym_store.dart';
import 'checkpoint_checkin_screen.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../preferences.dart';
import '../recurrence.dart';
import '../social_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/finisher_certificate_card.dart';
import '../widgets/gym_compose_sheet.dart';
import '../widgets/top_banner.dart';

/// Host-only attendance marking is offered iff the viewer organises the
/// event's club AND the event is a `class` (instructor_business.md M6).
/// Orthogonal to RSVP; non-hosts never see the marking controls.
@visibleForTesting
bool canMarkEventAttendance(ClubView? club, String category) =>
    club?.isEventOrganiser == true && category == 'class';

class EventDetailScreen extends StatefulWidget {
  final SocialService social;
  final String clubSlug;
  final String eventId;
  const EventDetailScreen({
    super.key,
    required this.social,
    required this.clubSlug,
    required this.eventId,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  EventView? _event;
  ClubView? _club;
  List<AttendeeView> _attendees = const [];
  String? _markingAttendance;
  List<EventResultView> _results = const [];
  RaceSessionRow? _raceSession;
  DateTime? _activeInstance;
  List<DateTime> _instances = const [];
  /// Members-only meetup coordinates via get_event_meet_point (null for
  /// non-members / no point set). Persona-hunt social-group #10.
  ({double lat, double lng})? _meetPoint;
  bool _loading = true;
  bool _busy = false;
  bool _submittingResult = false;
  /// Set while an arm/go/end mutation is in flight so the admin can't
  /// fire three buttons in quick succession. Separate from [_busy]
  /// (which gates RSVP writes) so a slow network on one doesn't block
  /// the other.
  bool _raceBusy = false;
  bool _autoApproveOnArm = true;
  _EventLoadError? _loadError;

  RealtimeChannel? _channel;
  Timer? _debounce;

  /// The class -> gym seam writes through this store (inform-tier: the composer
  /// is what saves). Created + initialised lazily on first use so a run/social
  /// event never touches the gym store; the write is offline-first and drains
  /// the next time a gym surface hydrates — no need to thread a shared store
  /// through every EventDetailScreen push site.
  LocalGymStore? _gymStore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The class -> gym seam hint, parsed from the loose jsonb bag. Null for a
  /// non-class event or a class the host didn't template.
  EventGymTemplate? get _gymTemplate {
    final e = _event;
    if (e == null || e.row.category != 'class') return null;
    return parseGymTemplate(e.row.gymTemplate);
  }

  bool get _canLogAsWorkout =>
      _gymTemplate != null &&
      Supabase.instance.client.auth.currentUser != null;

  Future<void> _logAsWorkout() async {
    final e = _event;
    if (e == null) return;
    final draft = workoutDraftFromTemplate(_gymTemplate, e.row.title);
    final store = _gymStore ??= LocalGymStore();
    await store.init();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final saved = await showGymComposeSheet(
      context: context,
      store: store,
      prefillTitle: draft.title,
    );
    if (saved == true && mounted) {
      showTopBanner(context, l10n.clubEventLogAsWorkoutSaved);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final clubFut =
          widget.social.fetchClubBySlug(widget.clubSlug);
      final eventFut = widget.social.fetchEventById(widget.eventId);
      final headResults = await Future.wait([clubFut, eventFut])
          .timeout(kBackendLoadTimeout);
      final club = headResults[0] as ClubView?;
      final event = headResults[1] as EventView?;
      if (event == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _activeInstance ??= event.nextInstanceStart;
      final now = DateTime.now();
      // Match web (persona #40): a full year of upcoming occurrences at the
      // default cap, so a weekly series' weeks 7+ are reachable in the picker
      // rather than truncated at 6. expandInstances still honours
      // recurrence_until / recurrence_count.
      final horizon = now.add(const Duration(days: 365));
      final instances = expandInstances(event.toRecurrence(), now, horizon);
      final bodyResults = await Future.wait([
        widget.social.fetchAttendees(event.row.id, _activeInstance!),
        widget.social.fetchEventResults(event.row.id, _activeInstance!),
        widget.social.fetchRaceSession(event.row.id, _activeInstance!),
        widget.social.fetchEventMeetPoint(event.row.id),
      ]).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _event = event;
        _club = club;
        _attendees = bodyResults[0] as List<AttendeeView>;
        _results = bodyResults[1] as List<EventResultView>;
        _raceSession = bodyResults[2] as RaceSessionRow?;
        _meetPoint = bodyResults[3] as ({double lat, double lng})?;
        _instances = instances;
        _loading = false;
      });
      if (_channel == null && club != null) {
        _channel = widget.social.subscribeToEvent(
          event.row.id,
          club.row.id,
          _onRealtimeChange,
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('EventDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _EventLoadError.timeout;
        });
      }
    } catch (e, s) {
      debugPrint('EventDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _EventLoadError.generic;
        });
      }
    }
  }

  void _onRealtimeChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _load();
    });
  }

  /// MapTiler static map centred on the meetup point with a marker.
  /// lon,lat order in the path; null when no key configured. Mirrors the
  /// web `buildStaticMarkerMapUrl` shape (persona social-group #10).
  String? _meetMapUrl(double lat, double lng) {
    final key = dotenv.env['MAPTILER_KEY'] ?? '';
    if (key.isEmpty) return null;
    final lo = lng.toStringAsFixed(5);
    final la = lat.toStringAsFixed(5);
    return 'https://api.maptiler.com/maps/streets-v2/static/'
        '$lo,$la,14/320x180@2x.png?markers=$lo,$la&key=$key';
  }

  /// Open the meetup point in a maps app. `geo:` is the Android-native
  /// intent (opens the user's chosen map app); the Google Maps universal
  /// URL is the fallback for iOS / when no geo: handler is present.
  Future<void> _navigateToMeetPoint(double lat, double lng, String? label) async {
    final gmaps = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (Platform.isAndroid) {
      final q = label != null ? '?q=$lat,$lng(${Uri.encodeComponent(label)})' : '';
      final geo = Uri.parse('geo:$lat,$lng$q');
      try {
        if (await canLaunchUrl(geo)) {
          await launchUrl(geo, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (e) {
        debugPrint('geo: launch failed, falling back to maps URL: $e');
      }
    }
    try {
      await launchUrl(gmaps, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('maps URL launch failed: $e');
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).eventCouldNotOpenMaps);
      }
    }
  }

  List<Widget> _buildMeetPoint(ThemeData theme, EventView e) {
    final mp = _meetPoint!;
    final mapUrl = _meetMapUrl(mp.lat, mp.lng);
    final label = e.row.meetLabel;
    return [
      const SizedBox(height: 10),
      if (mapUrl != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _navigateToMeetPoint(mp.lat, mp.lng, label),
            child: Image.network(
              mapUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              // L4: a tile-fetch failure must not break the card.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _navigateToMeetPoint(mp.lat, mp.lng, label),
          icon: const Icon(Icons.directions, size: 18),
          label: Text(label != null
              ? AppLocalizations.of(context).eventGetDirectionsTo(label)
              : AppLocalizations.of(context).eventGetDirections),
        ),
      ),
    ];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      widget.social.unsubscribe(channel);
    }
    super.dispose();
  }

  Future<void> _pickInstance(DateTime dt) async {
    setState(() => _activeInstance = dt);
    final e = _event;
    if (e == null) return;
    final attendees = await widget.social.fetchAttendees(e.row.id, dt);
    final results = await widget.social.fetchEventResults(e.row.id, dt);
    final race = await widget.social.fetchRaceSession(e.row.id, dt);
    if (mounted) {
      setState(() {
        _attendees = attendees;
        _results = results;
        _raceSession = race;
      });
    }
  }

  Future<void> _submitMyTime() async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _submittingResult) return;
    setState(() => _submittingResult = true);
    try {
      final picked = await showModalBottomSheet<_SubmitResultChoice>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _SubmitTimeSheet(social: widget.social),
      );
      if (picked == null) return;
      await widget.social.submitEventResult(
        eventId: e.row.id,
        instance: inst,
        durationS: picked.durationS,
        distanceM: picked.distanceM,
        runId: picked.runId,
        finisherStatus: picked.finisherStatus,
      );
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).eventResultSubmitted);
      }
      await _load();
    } catch (err) {
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).eventSubmitFailed('$err'));
      }
    } finally {
      if (mounted) setState(() => _submittingResult = false);
    }
  }

  Future<void> _removeMyResult() async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _submittingResult) return;
    setState(() => _submittingResult = true);
    try {
      await widget.social.removeEventResult(e.row.id, inst);
      await _load();
    } catch (err) {
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).eventRemoveResultFailed('$err'));
      }
    } finally {
      if (mounted) setState(() => _submittingResult = false);
    }
  }

  /// Arm / Fire Go / End dispatcher. Uses the current `_raceSession`
  /// state to decide which mutation to run. Errors surface as a
  /// snackbar; successful writes leave the realtime channel to push
  /// the UI back into sync (belt-and-suspenders: we also reload on
  /// return in case realtime is slow).
  Future<void> _raceMutation(_RaceAction action) async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _raceBusy) return;
    setState(() => _raceBusy = true);
    try {
      final social = widget.social;
      final row = switch (action) {
        _RaceAction.arm => await social.armRace(
            eventId: e.row.id,
            instance: inst,
            isAutoApprove: _autoApproveOnArm,
          ),
        _RaceAction.go => await social.startRace(
            eventId: e.row.id,
            instance: inst,
          ),
        _RaceAction.end => await social.endRace(
            eventId: e.row.id,
            instance: inst,
            status: 'finished',
          ),
        _RaceAction.cancel => await social.endRace(
            eventId: e.row.id,
            instance: inst,
            status: 'cancelled',
          ),
      };
      if (mounted) {
        setState(() => _raceSession = row);
      }
    } catch (err) {
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).eventRaceControlFailed('$err'));
      }
    } finally {
      if (mounted) setState(() => _raceBusy = false);
    }
  }

  /// End / Cancel are irreversible and affect every participant, so they
  /// confirm before firing (mirrors the web ConfirmDialog gate). Arm and
  /// Fire Go stay one-tap.
  Future<void> _confirmRaceAction(_RaceAction action) async {
    final l10n = AppLocalizations.of(context);
    final isCancel = action == _RaceAction.cancel;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(isCancel ? l10n.eventRaceCancelRace : l10n.eventRaceEnd),
            content: Text(isCancel
                ? l10n.eventRaceCancelConfirmBody
                : l10n.eventRaceEndConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.eventSubmitCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(
                    isCancel ? l10n.eventRaceCancelRace : l10n.eventRaceEnd),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) await _raceMutation(action);
  }

  Future<void> _rsvp(String status) async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _busy) return;
    setState(() => _busy = true);
    try {
      // If user taps the same status they already have for the NEXT instance,
      // clear it. Otherwise (or for non-next instances) write the RSVP.
      final isSameNext = inst == e.nextInstanceStart && e.viewerRsvp == status;
      if (isSameNext) {
        await widget.social.clearRsvp(e.row.id, inst);
      } else {
        await widget.social.rsvpEvent(e.row.id, status, inst);
      }
      await _load();
    } catch (err) {
      // RSVP is the primary action — surface a failure (network / RLS /
      // event-full race) instead of letting it vanish as an uncaught
      // async error with the chip just silently reverting.
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).eventRsvpFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markAttendance(
      String userId, String? current, String value) async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _markingAttendance != null) return;
    // Toggle off when the host taps the already-set state.
    final next = current == value ? null : value;
    setState(() => _markingAttendance = userId);
    try {
      // Scope the mark to the occurrence in view — a recurring event keeps a
      // distinct attendee row per instance_start.
      await widget.social.markAttendance(e.row.id, userId, inst, next);
      if (mounted) {
        setState(() {
          _attendees = [
            for (final a in _attendees)
              if (a.userId == userId)
                AttendeeView(
                  userId: a.userId,
                  status: a.status,
                  displayName: a.displayName,
                  attendance: next,
                )
              else
                a,
          ];
        });
      }
    } catch (_) {
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).eventAttendanceFailed);
      }
    } finally {
      if (mounted) setState(() => _markingAttendance = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: _loadError == _EventLoadError.timeout
              ? l10n.eventTimeoutError
              : l10n.eventLoadError,
          onRetry: _load,
        ),
      );
    }
    final e = _event;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.eventNotFound)),
      );
    }
    final desc = describeRecurrence(e.freq, e.byday);
    final active = _activeInstance!;
    final isMember = _club?.isMember == true;
    // Slice E: class / social events are attendance-only — no course, no race,
    // no leaderboard. isAthleticEventCategory is the single source of truth.
    final athletic = isAthleticEventCategory(e.row.category);
    // Host-only attendance marking (instructor_business.md M6): the organiser
    // of a `class` event records who showed up. Non-hosts see it read-only.
    final canMarkAttendance = canMarkEventAttendance(_club, e.row.category);

    return Scaffold(
      appBar: AppBar(title: Text(e.row.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (e.freq != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.autorenew, size: 14,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    desc.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          if (e.row.isPublic == false)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        l10n.clubEventMembersOnly,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16,
                  color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                fmtEventDate(active, localeToTag(Localizations.localeOf(context))),
                style: theme.textTheme.titleMedium,
              ),
              if (e.row.durationMin != null) ...[
                const SizedBox(width: 6),
                Text(
                  l10n.eventDurationMin(e.row.durationMin!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
          if (e.row.meetLabel != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.place, size: 16,
                    color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(child: Text(e.row.meetLabel!)),
              ],
            ),
          ],
          if (_meetPoint != null) ..._buildMeetPoint(theme, e),
          if (!athletic &&
              e.row.category == 'class' &&
              (e.row.discipline?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            EventDisciplineLabel(discipline: e.row.discipline!.trim()),
          ],
          if (_canLogAsWorkout) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                key: const Key('log-as-workout'),
                onPressed: _logAsWorkout,
                icon: const Icon(Icons.fitness_center, size: 18),
                label: Text(l10n.clubEventLogAsWorkout),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.clubEventLogAsWorkoutHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
          if (e.row.description != null && e.row.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.row.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          if (_instances.length > 1) ...[
            Text(
              l10n.eventPickOccurrence,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final dt in _instances)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(formatMonthDayShort(
                        dt, localeToTag(Localizations.localeOf(context)))),
                    selected: dt == _activeInstance,
                    onSelected: (_) => _pickInstance(dt),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _buildRsvpRow(theme, e),
          if (athletic &&
              (e.row.distanceM != null || e.row.paceTargetSec != null)) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (e.row.distanceM != null) ...[
                  _metric(theme, l10n.runStatDistance,
                      formatDistanceForPref(e.row.distanceM!)),
                  const SizedBox(width: 24),
                ],
                if (e.row.paceTargetSec != null)
                  _metric(theme, l10n.eventTargetPace,
                      fmtPace(e.row.paceTargetSec!)),
              ],
            ),
          ],
          if (athletic && _club?.isRaceDirector == true) ...[
            const SizedBox(height: 24),
            _buildRaceControl(theme, active),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CheckpointCheckinScreen(
                    eventId: e.row.id,
                    instanceStart: active,
                  ),
                ),
              ),
              icon: const Icon(Icons.where_to_vote_outlined),
              label: Text(l10n.checkpointCheckinAction),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            l10n.eventAttendees(_attendees.length),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          if (_attendees.isEmpty)
            Text(
              l10n.eventNoRsvps,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in _attendees)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: HSLColor.fromAHSL(
                              1, hashHue(a.userId).toDouble(), 0.5, 0.55,
                            ).toColor(),
                          ),
                          child: Text(
                            initialFor(a.displayName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(a.displayName ?? l10n.eventAttendeeMember,
                            style: theme.textTheme.bodySmall),
                        if (a.status != 'going') ...[
                          const SizedBox(width: 4),
                          Text(
                            l10n.eventAttendeeStatus(a.status),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                        if (canMarkAttendance) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            tooltip: l10n.eventMarkAttended,
                            color: a.attendance == 'attended'
                                ? Colors.green
                                : theme.colorScheme.outline,
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: _markingAttendance != null
                                ? null
                                : () => _markAttendance(
                                    a.userId, a.attendance, 'attended'),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            tooltip: l10n.eventMarkNoShow,
                            color: a.attendance == 'no_show'
                                ? theme.colorScheme.error
                                : theme.colorScheme.outline,
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: _markingAttendance != null
                                ? null
                                : () => _markAttendance(
                                    a.userId, a.attendance, 'no_show'),
                          ),
                        ] else if (a.attendance != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            a.attendance == 'attended'
                                ? l10n.eventAttendanceAttended
                                : l10n.eventAttendanceNoShow,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: a.attendance == 'attended'
                                  ? Colors.green
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          if (athletic) ...[
            const SizedBox(height: 24),
            EventResultsSection(
              results: _results,
              myUserId: widget.social.currentUserId,
              submitting: _submittingResult,
              onSubmit: _submitMyTime,
              onRemove: _removeMyResult,
              eventTitle: e.row.title,
              clubName: _club?.row.name,
              certificateDate: _activeInstance ?? e.row.startsAt,
            ),
          ],
          if (isMember) ...[
            const SizedBox(height: 24),
            _AdminUpdateComposer(
              onSubmit: (body) async {
                await widget.social.createPost(
                  clubId: _club!.row.id,
                  eventId: e.row.id,
                  eventInstanceStart: e.freq != null ? active : null,
                  body: body,
                );
                if (!mounted) return;
                showTopBanner(
                    context, AppLocalizations.of(context).eventUpdatePosted);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRsvpRow(ThemeData theme, EventView e) {
    final active = _activeInstance!;
    final isNext = active == e.nextInstanceStart;
    final current = isNext ? e.viewerRsvp : null;

    Widget chip(String value, String label) {
      final selected = current == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: selected
            ? FilledButton(
                onPressed: _busy ? null : () => _rsvp(value),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: _busy ? null : () => _rsvp(value),
                child: Text(label),
              ),
      );
    }

    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        chip('going', l10n.eventRsvpGoing),
        chip('maybe', l10n.eventRsvpMaybe),
        chip('declined', l10n.eventRsvpDeclined),
      ],
    );
  }

  Widget _metric(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 0.6,
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }


  /// Admin-only "Race control" panel. Visible to owners / admins /
  /// race directors. Renders the state machine as a single status line
  /// + primary CTA; secondary destructive actions (cancel / reset)
  /// sit below at reduced visual weight.
  Widget _buildRaceControl(ThemeData theme, DateTime active) {
    final l10n = AppLocalizations.of(context);
    final race = _raceSession;
    final status = race?.status ?? 'idle';
    final banner = switch (status) {
      'armed' => l10n.eventRaceArmed,
      'running' => l10n.eventRaceRunning,
      'finished' => l10n.eventRaceFinished,
      'cancelled' => l10n.eventRaceCancelled,
      _ => l10n.eventRaceNotArmed,
    };
    final bannerColour = switch (status) {
      'armed' => theme.colorScheme.tertiary,
      'running' => theme.colorScheme.primary,
      'finished' => theme.colorScheme.outline,
      'cancelled' => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sports_score, size: 18, color: bannerColour),
                const SizedBox(width: 6),
                Text(
                  l10n.eventRaceControlLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              banner,
              style: theme.textTheme.titleMedium?.copyWith(color: bannerColour),
            ),
            const SizedBox(height: 8),
            if (status == 'idle' || status == 'finished' || status == 'cancelled') ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  l10n.eventRaceAutoApprove,
                  style: theme.textTheme.bodySmall,
                ),
                value: _autoApproveOnArm,
                onChanged: (v) => setState(() => _autoApproveOnArm = v ?? true),
              ),
              FilledButton.icon(
                onPressed: _raceBusy ? null : () => _raceMutation(_RaceAction.arm),
                icon: const Icon(Icons.bolt),
                label: Text(l10n.eventRaceArm),
              ),
            ] else if (status == 'armed') ...[
              Text(
                l10n.eventRaceArmedHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _raceBusy
                        ? null
                        : () => _raceMutation(_RaceAction.go),
                    icon: const Icon(Icons.flag),
                    label: Text(l10n.eventRaceFireGo),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _raceBusy
                        ? null
                        : () => _confirmRaceAction(_RaceAction.cancel),
                    child: Text(l10n.eventRaceCancel),
                  ),
                ],
              ),
            ] else if (status == 'running') ...[
              if (race?.startedAt != null)
                Text(
                  l10n.eventRaceStartedAt(fmtEventDate(
                      race!.startedAt!.toLocal(),
                      localeToTag(Localizations.localeOf(context)))),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _raceBusy
                        ? null
                        : () => _confirmRaceAction(_RaceAction.end),
                    icon: const Icon(Icons.stop_circle),
                    label: Text(l10n.eventRaceEnd),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _raceBusy
                        ? null
                        : () => _confirmRaceAction(_RaceAction.cancel),
                    child: Text(l10n.eventRaceCancelRace),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _RaceAction { arm, go, end, cancel }

enum _EventLoadError { timeout, generic }

class _AdminUpdateComposer extends StatefulWidget {
  final Future<void> Function(String body) onSubmit;
  const _AdminUpdateComposer({required this.onSubmit});

  @override
  State<_AdminUpdateComposer> createState() => _AdminUpdateComposerState();
}

class _AdminUpdateComposerState extends State<_AdminUpdateComposer> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(body);
      _ctrl.clear();
    } catch (e) {
      // Without the explicit catch this was `try/finally` — the
      // onSubmit failure propagated up as an uncaught Future error,
      // logged silently by Flutter, and the user saw no banner. The
      // composer text stays in `_ctrl` because the `_ctrl.clear()`
      // above only fires on success.
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).eventPostUpdateFailed('$e'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).eventPostUpdateLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            maxLength: 1200,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).eventUpdateHint,
              border: InputBorder.none,
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(AppLocalizations.of(context).eventPostUpdate),
            ),
          ),
        ],
      ),
    );
  }
}

/// A choice returned from the submit-time bottom sheet. Captures both the
/// "pick an existing run" path (with [runId]) and the "record a DNF/DNS"
/// path (no run, manual finisher_status).
class _SubmitResultChoice {
  final String? runId;
  final int durationS;
  final double distanceM;
  final String finisherStatus;
  const _SubmitResultChoice({
    required this.runId,
    required this.durationS,
    required this.distanceM,
    required this.finisherStatus,
  });
}

/// Prominent free-text discipline label for a non-athletic class (yoga,
/// pilates, …). Shown in place of the athletic course / race surface so a
/// class reads as an instructor-led session, not a timed effort.
@visibleForTesting
class EventDisciplineLabel extends StatelessWidget {
  final String discipline;
  const EventDisciplineLabel({super.key, required this.discipline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.self_improvement,
              size: 22, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.eventClassSessionEyebrow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  discipline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
class EventResultsSection extends StatelessWidget {
  final List<EventResultView> results;
  final String? myUserId;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onRemove;
  final String eventTitle;
  final String? clubName;
  final DateTime certificateDate;
  const EventResultsSection({
    super.key,
    required this.results,
    required this.myUserId,
    required this.submitting,
    required this.onSubmit,
    required this.onRemove,
    required this.eventTitle,
    required this.clubName,
    required this.certificateDate,
  });

  // The result removal is destructive (it deletes the runner's
  // submitted finish time), so it asks to confirm before invoking
  // onRemove. The host owns the actual deletion + error banner.
  Future<void> _confirmRemove(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.eventRemoveResultTitle),
            content: Text(l10n.eventRemoveResultBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.eventSubmitCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.eventRemoveResultConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasMine = myUserId != null && results.any((r) => r.userId == myUserId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(l10n.eventResultsTitle, style: theme.textTheme.titleSmall),
            const Spacer(),
            if (hasMine)
              TextButton(
                onPressed: submitting ? null : () => _confirmRemove(context),
                child: Text(l10n.eventRemoveMine),
              )
            else
              FilledButton.tonalIcon(
                onPressed: submitting ? null : onSubmit,
                icon: const Icon(Icons.timer_outlined, size: 16),
                label: Text(submitting
                    ? l10n.eventSubmitting
                    : l10n.eventSubmitMyTime),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          Text(
            l10n.eventNoResults,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        else
          ...results.map((r) => _ResultRow(
                row: r,
                isMe: r.userId == myUserId,
                eventTitle: eventTitle,
                clubName: clubName,
                certificateDate: certificateDate,
              )),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final EventResultView row;
  final bool isMe;
  final String eventTitle;
  final String? clubName;
  final DateTime certificateDate;
  const _ResultRow({
    required this.row,
    required this.isMe,
    required this.eventTitle,
    required this.clubName,
    required this.certificateDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rank = row.rank?.toString() ?? '—';
    final time = _formatDuration(row.durationS);
    final distKm =
        formatFixed(row.distanceM / 1000, 2, activeLocaleTag);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              rank,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: row.finisherStatus == 'finished'
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.displayName ?? AppLocalizations.of(context).eventResultRunner,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).eventResultYou,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      )),
                ],
                if (row.finisherStatus != 'finished') ...[
                  const SizedBox(width: 6),
                  Text(
                    row.finisherStatus.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (row.finisherStatus == 'finished') ...[
            Text(time,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 10),
            Text('$distKm km',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                )),
          ],
          if (isCertificateEligible(
            finisherStatus: row.finisherStatus,
            organiserApproved: row.organiserApproved,
          )) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.of(context).clubEventDownloadCertificate,
              icon: const Icon(Icons.workspace_premium_outlined, size: 20),
              onPressed: () => showFinisherCertificateSheet(
                context,
                eventTitle: eventTitle,
                finisherName: row.displayName ??
                    AppLocalizations.of(context).eventResultRunner,
                durationS: row.durationS,
                distanceM: row.distanceM,
                rank: row.rank,
                date: certificateDate,
                clubName: clubName,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

/// Bottom sheet that lets a user attach one of their recent runs, or
/// record a DNF/DNS without a run.
class _SubmitTimeSheet extends StatefulWidget {
  final SocialService social;
  const _SubmitTimeSheet({required this.social});

  @override
  State<_SubmitTimeSheet> createState() => _SubmitTimeSheetState();
}

class _SubmitTimeSheetState extends State<_SubmitTimeSheet> {
  List<RecentRunRow> _runs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final runs = await widget.social.fetchRecentRuns(limit: 20);
    if (mounted) setState(() { _runs = runs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.eventSubmitTimeTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.eventSubmitTimeSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_runs.isEmpty)
              Text(
                l10n.eventNoRecentRuns,
                style: theme.textTheme.bodySmall,
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _runs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _runs[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${_dateLabel(r.startedAt, localeToTag(Localizations.localeOf(context)))} · ${formatDistanceForPref(r.distanceM)}',
                      ),
                      subtitle: Text(
                        '${_ResultRow._formatDuration(r.durationS)} · ${r.activityType}',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.of(context).pop(
                        _SubmitResultChoice(
                          runId: r.id,
                          durationS: r.durationS,
                          distanceM: r.distanceM,
                          finisherStatus: 'finished',
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const _SubmitResultChoice(
                      runId: null,
                      durationS: 0,
                      distanceM: 0,
                      finisherStatus: 'dnf',
                    ),
                  ),
                  child: Text(l10n.eventRecordDnf),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const _SubmitResultChoice(
                      runId: null,
                      durationS: 0,
                      distanceM: 0,
                      finisherStatus: 'dns',
                    ),
                  ),
                  child: Text(l10n.eventRecordDns),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.eventSubmitCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime dt, String localeTag) =>
      formatDateMed(dt.toLocal(), localeTag);
}
