import 'package:flutter/material.dart';

/// The app's motion tier: one duration per role, plus the four curves that
/// actually ship.
///
/// Every rung is the **modal** value of its role in the population that was
/// already shipping when the tier was introduced, so adopting it moves the
/// off-mode sites and leaves the majority untouched:
///
/// | rung       | ms   | role                              | shipped values                        |
/// |------------|------|-----------------------------------|---------------------------------------|
/// | [brief]    | 200  | a small element changing in place | 200, 200, 260, 350                    |
/// | [standard] | 300  | an animated scroll or page change | 180, 300, 300                         |
/// | [pulse]    | 1500 | a repeating loop                  | 600, 720, 900, 1050, 1100, 1500, 1500 |
///
/// Four of those seven loop values stay **off** the [pulse] rung, and
/// deliberately: the coach typing dots (600), the skeleton shimmer (900) and
/// the two remaining `ActivityLoader` gait cadences (720, 1050) are
/// indeterminate-progress rhythms rather than chrome timing. A gait cycle and
/// a typing rhythm carry their meaning at their own speed, and the loader's
/// three are ported frame-for-frame from web's `ActivityLoader.svelte` — the
/// cross-platform match is the contract there, so retiming them would be the
/// divergence. They are not a fourth rung either: there is no mode across the
/// four to derive one from, and an invented number wearing a tier's clothes is
/// worse than four honest locals.
abstract final class AppMotion {
  static const brief = Duration(milliseconds: 200);
  static const standard = Duration(milliseconds: 300);
  static const pulse = Duration(milliseconds: 1500);

  static const Curve curveStandard = Curves.easeOut;
  static const Curve curveEmphasised = Curves.easeOutCubic;
  static const Curve curveOvershoot = Curves.easeOutBack;

  /// For interpolating a value toward a new *datum* rather than styling a UI
  /// change. Easing between two equally-spaced GPS fixes would make the dot
  /// accelerate and brake once a second on a runner holding a steady pace.
  static const Curve curveLinear = Curves.linear;
}

/// Whether the platform is asking for reduced motion — the OS-level
/// "Reduce motion" / "Remove animations" switch, WCAG 2.3.3, and a
/// vestibular-disorder accommodation.
///
/// `maybeOf` rather than `of` so a widget pumped without a [MediaQuery]
/// (several unit tests, and any future non-`MaterialApp` host) reads as
/// "no preference expressed" instead of throwing.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// [d], collapsed to [Duration.zero] under [reduceMotion].
///
/// Flutter already scales a *one-shot* `forward`/`reverse`/`animateTo` to 5 %
/// of its duration when the platform flag is set ([AnimationBehavior.normal]),
/// so this is exactness rather than rescue on those sites. It is a genuine
/// rescue for anything the framework does not touch — see [syncMotionLoop]
/// and [motionScrollTo].
Duration motionDuration(BuildContext context, Duration d) =>
    reduceMotion(context) ? Duration.zero : d;

/// Drives a **repeating** [controller] from the platform reduce-motion signal:
/// under reduce-motion it is *stopped* and parked at [restValue], not merely
/// run faster.
///
/// Call from `didChangeDependencies` so the widget re-reads the flag when the
/// user changes it mid-session.
///
/// Two reasons stopping is the only correct answer. First, Flutter's 5 %
/// duration scale is applied in `_animateToInternal` and **not** in `repeat`,
/// whose own source comment explains why: "the common pattern of an eternally
/// repeating animation might cause an endless loop if it weren't delayed for
/// at least one frame". So a repeating controller runs at its full period no
/// matter what the user has asked for. Second, a ticker that keeps requesting
/// frames for the length of a recording costs battery on the app's
/// highest-traffic screen even when nothing about the frame changes.
void syncMotionLoop(
  BuildContext context,
  AnimationController controller, {
  double restValue = 0,
  bool reverse = false,
}) {
  if (reduceMotion(context)) {
    if (controller.isAnimating) controller.stop();
    controller.value = restValue;
  } else if (!controller.isAnimating) {
    controller.repeat(reverse: reverse);
  }
}

/// [ScrollController.animateTo], or an instant [ScrollController.jumpTo] under
/// [reduceMotion].
///
/// An animated scroll is the one motion the framework flag does not reach at
/// all: `animateTo` builds a `DrivenScrollActivity` over an
/// `AnimationController.unbounded`, which defaults to
/// [AnimationBehavior.preserve]. And the collapse cannot be a zero duration —
/// that same constructor asserts `duration > Duration.zero` — so it has to be
/// a different call, not a different number.
Future<void> motionScrollTo(
  BuildContext context,
  ScrollController controller,
  double offset, {
  Duration duration = AppMotion.standard,
  Curve curve = AppMotion.curveStandard,
}) async {
  if (!controller.hasClients) return;
  if (reduceMotion(context)) {
    controller.jumpTo(offset);
    return;
  }
  await controller.animateTo(offset, duration: duration, curve: curve);
}
