import SwiftUI

/// The in-run live-position mini-map: the track so far, the route the phone
/// armed if there is one, and the runner's current position, auto-fitting as
/// the run grows.
///
/// Drawn with `Canvas` rather than MapKit — see decisions.md § 702.
///
/// An auxiliary (L3) surface in the layering contract: it renders from state
/// the recorder has already committed and calls nothing back, so there is no
/// path from anything the map does to the clock or the distance. Every value it
/// needs is optional at the source, so an absent fix renders as an absent fix.
struct RunMiniMapView: View {
    let route: [MiniMapPoint]
    let trail: [MiniMapPoint]
    let current: MiniMapPoint?

    private static let trailWidth = 1.5
    private static let routeWidth = 2.0
    private static let markerRadius = 3.0
    private static let haloRadius = 5.5

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let content = MiniMapContent.make(
                route: route, trail: trail, current: current, sideLength: side
            )
            ZStack {
                AppTheme.midnight
                if let content {
                    Canvas { context, size in
                        draw(content, into: &context, size: size, side: side)
                    }
                    .accessibilityLabel("Run map")
                }
                if content?.awaitingFix ?? true {
                    Text("Waiting for GPS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .background(AppTheme.midnight.opacity(0.75))
                }
            }
        }
    }

    private func draw(
        _ content: MiniMapContent,
        into context: inout GraphicsContext,
        size: CGSize,
        side: CGFloat
    ) {
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        func place(_ point: MiniMapPoint) -> CGPoint? {
            content.frame.project(point, sideLength: side).map {
                CGPoint(x: originX + $0.x, y: originY + $0.y)
            }
        }
        func polyline(_ points: [MiniMapPoint]) -> Path? {
            let placed = points.compactMap(place)
            guard let first = placed.first, placed.count >= 2 else { return nil }
            var path = Path()
            path.move(to: first)
            for point in placed.dropFirst() { path.addLine(to: point) }
            return path
        }

        if let path = polyline(content.trail) {
            context.stroke(
                path,
                with: .color(AppTheme.coral),
                style: StrokeStyle(lineWidth: Self.trailWidth, lineJoin: .round)
            )
        }

        if let path = polyline(content.route) {
            context.stroke(
                path,
                with: .color(AppTheme.lilac),
                style: StrokeStyle(lineWidth: Self.routeWidth, lineJoin: .round)
            )
            // Start and finish share one marker on a loop: two stacked circles
            // a runner cannot tell apart is worse than one that says
            // "start/finish". Filled for the start, hollow for the finish, so
            // the two read apart by shape rather than by a second hue on a
            // 1-bit-legible wrist palette.
            if let start = content.route.first.flatMap(place) {
                context.fill(Self.circle(at: start, radius: Self.markerRadius),
                             with: .color(AppTheme.lilac))
            }
            if !content.routeIsLoop, let end = content.route.last.flatMap(place) {
                context.stroke(Self.circle(at: end, radius: Self.markerRadius),
                               with: .color(AppTheme.lilac),
                               lineWidth: Self.routeWidth)
            }
        }

        if let position = content.current.flatMap(place) {
            context.fill(
                Self.circle(at: position, radius: Self.haloRadius),
                with: .color(AppTheme.parchment.opacity(0.3))
            )
            context.fill(
                Self.circle(at: position, radius: Self.markerRadius),
                with: .color(AppTheme.parchment)
            )
        }
    }

    private static func circle(at centre: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
