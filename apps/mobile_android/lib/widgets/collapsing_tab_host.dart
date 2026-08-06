import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../adaptive_width.dart';

/// A tab host whose hero band scrolls away above a pinned tab strip, over one
/// scrollable per tab.
///
/// Two constraints drive the shape.
///
/// The strip travels with the body it labels. While it sat in `AppBar.bottom` a
/// content clamp on the body alone left a full-width strip above a 720 dp
/// column, which is why `club_detail` and `profile` were the two screens § 538
/// had to leave unclamped; here the strip is a sliver inside the scroll view
/// and [contentColumn] wraps hero, strip and body together.
///
/// And every entry in [tabs] must be a real scrollable that accepts a drag even
/// when its content fits. `NestedScrollView` collapses its header out of the
/// *inner* scrollable's drag, so a body that is not a scrollable receives no
/// drag at all and the band is fixed again — which is exactly what a bare
/// `Center` empty state did on four of `club_detail`'s six tabs. ui_kit's
/// `EmptyState` under bounded height already is that scrollable (a
/// fill-and-centre `SingleChildScrollView` on `AlwaysScrollableScrollPhysics`),
/// so an empty tab passes one straight through. See decisions § 545.
class CollapsingTabHost extends StatelessWidget {
  const CollapsingTabHost({
    super.key,
    required this.controller,
    required this.labels,
    required this.tabs,
    this.header = const [],
  }) : assert(labels.length == tabs.length,
            'one tab body per label — the TabController length is shared');

  final TabController controller;

  /// Already-localized strip labels, one per entry in [tabs].
  final List<String> labels;

  /// Box widgets above the strip that scroll away — the hero, and any banner
  /// that belongs to the whole surface rather than to one tab.
  final List<Widget> header;

  /// One per label, each a scrollable on `AlwaysScrollableScrollPhysics`.
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    return contentColumn(
      context,
      NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          for (final band in header) SliverToBoxAdapter(child: band),
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            // A zero toolbar leaves only `bottom`, so the strip is the whole
            // pinned extent. `primary: false` keeps it from claiming the status
            // bar a second time — the screen's own AppBar already has it.
            sliver: SliverAppBar(
              primary: false,
              pinned: true,
              toolbarHeight: 0,
              automaticallyImplyLeading: false,
              bottom: AppTabBar(controller: controller, labels: labels),
            ),
          ),
        ],
        body: TabBarView(
          controller: controller,
          children: [
            for (final tab in tabs)
              // The absorber hands the body the extent the strip covers, so
              // the body owes it back as a top inset. The absorbed amount is
              // the strip's `maxScrollObstructionExtent`, which for a fully
              // pinned header is its min extent — constant, and the same
              // figure `AppTabBar.preferredSize` reports.
              Padding(
                padding: const EdgeInsets.only(top: AppTabBar.height),
                child: tab,
              ),
          ],
        ),
      ),
    );
  }
}
