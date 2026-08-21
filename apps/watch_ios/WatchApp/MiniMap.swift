import CoreGraphics
import Foundation

/// One position the mini-map draws, in degrees. Deliberately not a
/// `CLLocationCoordinate2D`: the projection, the trail and the display
/// decision are pure value maths, so the whole surface is testable without a
/// `CLLocationManager` or a device.
struct MiniMapPoint: Equatable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }
}

/// A local planar offset from some origin, in metres east / north.
struct MiniMapOffset: Equatable {
    let east: Double
    let north: Double
}

enum MiniMapGeo {
    /// Metres per degree of latitude — the flat model every local frame in
    /// this codebase uses (`watch_core::record::METRES_PER_DEGREE_LAT`).
    static let metresPerDegreeLatitude = 111_320.0

    /// East-west degree delta folded onto [-180, 180]. A plain subtraction is
    /// wrong by a whole turn across the antimeridian, so an uncorrected frame
    /// reads a point just over the line as ~40,000 km away and collapses the
    /// whole map onto a single pixel. Same correction as `route_geometry`'s
    /// `lonDeltaDeg` and the firmware's `geo::lon_delta_deg`.
    static func longitudeDeltaDegrees(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    static func wrapLongitudeDegrees(_ degrees: Double) -> Double {
        longitudeDeltaDegrees(from: 0, to: degrees)
    }

    static func metresPerDegreeLongitude(atLatitude latitude: Double) -> Double {
        metresPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    /// `point` as metres east / north of `origin`.
    static func offset(of point: MiniMapPoint, from origin: MiniMapPoint) -> MiniMapOffset {
        MiniMapOffset(
            east: longitudeDeltaDegrees(from: origin.longitude, to: point.longitude)
                * metresPerDegreeLongitude(atLatitude: origin.latitude),
            north: (point.latitude - origin.latitude) * metresPerDegreeLatitude
        )
    }

    static func distanceMetres(_ a: MiniMapPoint, _ b: MiniMapPoint) -> Double {
        let o = offset(of: b, from: a)
        return (o.east * o.east + o.north * o.north).squareRoot()
    }
}

/// The drawing frame a set of points is fitted into: a centre plus the ground
/// metres one rendered point covers. North is up and the centre lands in the
/// middle of a square of side `sideLength`.
///
/// A local planar metre frame rather than the Web Mercator the Wear sibling
/// projects through: Mercator earns its keep only where raster tiles have to
/// line up with the polyline, and this map draws no tiles. See
/// decisions.md § 702.
struct MiniMapFrame: Equatable {
    let centre: MiniMapPoint
    let metresPerPoint: Double

    /// Fraction of the side reserved as margin on each edge, so a track that
    /// fills the frame doesn't touch the bezel.
    static let paddingFraction = 0.10

    /// Smallest ground span the frame will show. Without a floor the opening
    /// metres of a run — or a stationary runner's GPS jitter — would be
    /// stretched across the whole screen and read as movement.
    static let minimumSpanMetres = 200.0

    static func fit(_ points: [MiniMapPoint], sideLength: Double) -> MiniMapFrame? {
        let usable = points.filter { $0.isValid }
        guard let first = usable.first,
              sideLength.isFinite, sideLength > 0 else { return nil }

        // Longitudes are unwrapped onto the first point's side of the line
        // before min/max, so a track straddling the antimeridian keeps a
        // monotone frame instead of spanning 359.9 degrees.
        let reference = first.longitude
        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = reference
        var maxLongitude = reference
        for point in usable {
            minLatitude = min(minLatitude, point.latitude)
            maxLatitude = max(maxLatitude, point.latitude)
            let unwrapped = reference
                + MiniMapGeo.longitudeDeltaDegrees(from: reference, to: point.longitude)
            minLongitude = min(minLongitude, unwrapped)
            maxLongitude = max(maxLongitude, unwrapped)
        }

        let centreLatitude = (minLatitude + maxLatitude) / 2
        let centre = MiniMapPoint(
            latitude: centreLatitude,
            longitude: MiniMapGeo.wrapLongitudeDegrees((minLongitude + maxLongitude) / 2)
        )

        let usableSide = sideLength * (1 - 2 * Self.paddingFraction)
        guard usableSide > 0 else { return nil }
        let spanNorth = (maxLatitude - minLatitude) * MiniMapGeo.metresPerDegreeLatitude
        let spanEast = (maxLongitude - minLongitude)
            * MiniMapGeo.metresPerDegreeLongitude(atLatitude: centreLatitude)
        let span = max(max(spanNorth, spanEast), Self.minimumSpanMetres)
        let metresPerPoint = span / usableSide
        guard metresPerPoint.isFinite, metresPerPoint > 0 else { return nil }
        return MiniMapFrame(centre: centre, metresPerPoint: metresPerPoint)
    }

    /// Nil for a point the frame cannot place, never a (0, 0) that would draw
    /// at the centre of the map and read as the runner standing there.
    func project(_ point: MiniMapPoint, sideLength: Double) -> CGPoint? {
        guard point.isValid, sideLength.isFinite, sideLength > 0 else { return nil }
        let offset = MiniMapGeo.offset(of: point, from: centre)
        guard offset.east.isFinite, offset.north.isFinite else { return nil }
        let half = sideLength / 2
        return CGPoint(
            x: half + offset.east / metresPerPoint,
            y: half - offset.north / metresPerPoint
        )
    }
}

enum MiniMapThinning {
    /// Which indices of a `count`-point polyline survive a reduction to
    /// `budget` points: both endpoints always, then repeatedly the point
    /// furthest from the chord it would split, so shape survives and
    /// near-collinear filler is what goes. A featureless straight finds no
    /// deviation and falls back to splitting the widest index gap, so
    /// occupancy still reaches the budget exactly. Swift port of the
    /// firmware's `route_simplify::simplify_to_budget`.
    static func keptIndices(
        count: Int,
        budget: Int,
        perpendicular: (Int, Int, Int) -> Double
    ) -> [Int] {
        guard count > 0 else { return [] }
        var kept = [0]
        guard count > 1 else { return kept }
        kept.append(count - 1)
        let budget = min(budget, count)
        while kept.count < budget {
            var bestDeviation = 0.0
            var bestSlot = 0
            var bestIndex = 0
            var found = false
            for slot in 0..<(kept.count - 1) {
                let a = kept[slot]
                let b = kept[slot + 1]
                guard b > a + 1 else { continue }
                var segmentDeviation = 0.0
                var segmentIndex = a
                for i in (a + 1)..<b {
                    let deviation = perpendicular(a, b, i)
                    if deviation > segmentDeviation {
                        segmentDeviation = deviation
                        segmentIndex = i
                    }
                }
                if segmentDeviation > bestDeviation {
                    bestDeviation = segmentDeviation
                    bestSlot = slot
                    bestIndex = segmentIndex
                    found = true
                }
            }
            if found {
                kept.insert(bestIndex, at: bestSlot + 1)
                continue
            }
            var widestSlot = 0
            var widestGap = 0
            for slot in 0..<(kept.count - 1) {
                let gap = kept[slot + 1] - kept[slot]
                if gap > widestGap {
                    widestGap = gap
                    widestSlot = slot
                }
            }
            guard widestGap >= 2 else { break }
            kept.insert((kept[widestSlot] + kept[widestSlot + 1]) / 2, at: widestSlot + 1)
        }
        return kept
    }

    /// Distance from `p` to the segment `a`-`b`, projection clamped to the
    /// segment's ends. Coordinate-space agnostic — fed metre offsets here.
    static func pointSegmentDistance(
        _ p: MiniMapOffset, _ a: MiniMapOffset, _ b: MiniMapOffset
    ) -> Double {
        let dx = b.east - a.east
        let dy = b.north - a.north
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            let ex = p.east - a.east
            let ey = p.north - a.north
            return (ex * ex + ey * ey).squareRoot()
        }
        let t = min(1, max(0, ((p.east - a.east) * dx + (p.north - a.north) * dy) / lengthSquared))
        let ex = p.east - (a.east + dx * t)
        let ey = p.north - (a.north + dy * t)
        return (ex * ex + ey * ey).squareRoot()
    }
}

/// A fixed-capacity, distance-decimated breadcrumb of the run so far.
///
/// `WorkoutManager.track` cannot be drawn: it is a 600-fix rolling window
/// (decisions § 467), so a map fed from it shows the last few minutes and
/// silently drops the start of the run. Holding the whole track instead is
/// exactly the unbounded array that window exists to avoid — a 100-hour ultra
/// is ~360k fixes.
///
/// So the map keeps its own trail. A fix is admitted once it is
/// `spacingMetres` from the last kept one; when the buffer fills, the trail
/// halves and the spacing doubles, so the whole run stays represented at
/// coarser resolution at flat memory for as long as the run lasts. Ported from
/// the firmware's `watch_core::trackback` breadcrumb, including its reason for
/// halving geometrically rather than by index parity: parity thinning is blind
/// to shape and can delete the apex of a switchback, replacing it with a
/// straight chord across the terrain the switchbacks exist to avoid.
struct MiniMapTrail: Equatable {
    /// With the initial spacing this covers ~1.9 km before the first thinning;
    /// each thinning halves the count and doubles the spacing, so coverage
    /// grows geometrically with run length (seven doublings reach ~245 km).
    static let capacity = 96

    /// A fix is kept once it is this far from the last kept point. Doubles on
    /// each thinning pass.
    static let initialSpacingMetres = 20.0

    private(set) var points: [MiniMapPoint] = []
    private(set) var spacingMetres = MiniMapTrail.initialSpacingMetres

    mutating func append(_ point: MiniMapPoint) {
        guard point.isValid else { return }
        guard let last = points.last else {
            points.append(point)
            return
        }
        let offset = MiniMapGeo.offset(of: point, from: last)
        let squared = offset.east * offset.east + offset.north * offset.north
        guard squared.isFinite, squared >= spacingMetres * spacingMetres else { return }
        if points.count >= Self.capacity { thin() }
        points.append(point)
    }

    mutating func reset() {
        points = []
        spacingMetres = Self.initialSpacingMetres
    }

    private mutating func thin() {
        guard let origin = points.first else { return }
        let offsets = points.map { MiniMapGeo.offset(of: $0, from: origin) }
        let kept = MiniMapThinning.keptIndices(
            count: offsets.count,
            budget: (offsets.count + 1) / 2
        ) { a, b, i in
            MiniMapThinning.pointSegmentDistance(offsets[i], offsets[a], offsets[b])
        }
        points = kept.map { points[$0] }
        spacingMetres *= 2
    }
}

/// Everything one render of the mini-map draws, or nil when there is nothing
/// honest to draw at all.
struct MiniMapContent: Equatable {
    let frame: MiniMapFrame
    let route: [MiniMapPoint]
    let trail: [MiniMapPoint]
    /// The runner's position, or nil when no usable fix has arrived. Never
    /// defaulted: a dot at (0, 0) is a confident claim about the Gulf of
    /// Guinea, and a map that plants one has told the runner where they are
    /// when it does not know.
    let current: MiniMapPoint?

    /// Distance within which a route's first and last points read as one
    /// start/finish marker rather than two indistinguishable stacked dots.
    /// Matches the recorder's GPS sample-spacing floor, so a route imported
    /// from a real GPX with sub-metre wobble still reads as a loop.
    static let loopThresholdMetres = 12.0

    var awaitingFix: Bool { current == nil }

    var routeIsLoop: Bool {
        guard let first = route.first, let last = route.last, route.count >= 2 else { return false }
        return MiniMapGeo.distanceMetres(first, last) < Self.loopThresholdMetres
    }

    static func make(
        route: [MiniMapPoint],
        trail: [MiniMapPoint],
        current: MiniMapPoint?,
        sideLength: Double
    ) -> MiniMapContent? {
        let route = route.filter { $0.isValid }
        let trail = trail.filter { $0.isValid }
        let current = current.flatMap { $0.isValid ? $0 : nil }
        var all = route + trail
        if let current { all.append(current) }
        guard let frame = MiniMapFrame.fit(all, sideLength: sideLength) else { return nil }
        return MiniMapContent(frame: frame, route: route, trail: trail, current: current)
    }
}
