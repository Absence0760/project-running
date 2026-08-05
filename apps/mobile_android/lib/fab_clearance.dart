import 'package:flutter/widgets.dart';

/// Height of a Material 3 [FloatingActionButton], regular or extended.
const double kFabHeight = 56;

/// Vertical gap between stacked FABs in this app's two-FAB columns.
const double kFabStackGap = 12;

/// Bottom padding a scroll view owes a single floating action button, before
/// any system inset: the Scaffold's own 16dp FAB margin, the button, and 16dp
/// so the last row is not flush against it.
///
/// Measured, not guessed — `Scaffold` places an end-floating FAB with its
/// bottom `kFloatingActionButtonMargin + minViewPadding.bottom` above the
/// content bottom, so a list with no clearance ends underneath it.
const double kFabScrollClearance = 16 + kFabHeight + 16;

/// Bottom padding for a scroll view that [fabCount] floating action buttons
/// float over.
///
/// The system inset comes from `MediaQuery.padding`, not `viewPadding`, so
/// the number composes: a `SafeArea` above the caller, or a parent `Scaffold`
/// with a `bottomNavigationBar`, has already consumed the nav bar and reports
/// zero — exactly the cases where adding it again would leave a dead band at
/// the end of the list.
double fabScrollClearance(BuildContext context, {int fabCount = 1}) =>
    MediaQuery.paddingOf(context).bottom +
    kFabScrollClearance +
    (fabCount - 1) * (kFabHeight + kFabStackGap);
