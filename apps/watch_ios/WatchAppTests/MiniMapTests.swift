import XCTest
@testable import WatchApp

/// The pure half of the in-run mini-map: the fit / projection frame, the
/// bounded breadcrumb the map draws instead of the recorder's rolling window,
/// and the display decision. The honesty cases are the point of the suite — an
/// empty track, a single point, and a run with no fix yet must never resolve
/// to a confident dot in the middle of the map.
final class MiniMapTests: XCTestCase {
    private let side = 160.0

    private func point(_ lat: Double, _ lng: Double) -> MiniMapPoint {
        MiniMapPoint(latitude: lat, longitude: lng)
    }

    // MARK: - Frame

    func testFitRefusesAnEmptyPointList() {
        XCTAssertNil(MiniMapFrame.fit([], sideLength: side))
    }

    func testFitRefusesAZeroSideViewport() {
        XCTAssertNil(MiniMapFrame.fit([point(51.5, -0.1)], sideLength: 0))
    }

    func testFitDropsNonFinitePointsAndKeepsTheRest() {
        let frame = MiniMapFrame.fit(
            [point(.nan, -0.1), point(51.5, .infinity), point(51.5, -0.1)],
            sideLength: side
        )
        XCTAssertEqual(frame?.centre, point(51.5, -0.1))
    }

    func testFitOfAllNonFinitePointsIsNil() {
        XCTAssertNil(MiniMapFrame.fit([point(.nan, .nan)], sideLength: side))
    }

    func testASinglePointCentresAndFallsBackToTheMinimumSpan() {
        guard let frame = MiniMapFrame.fit([point(51.5, -0.1)], sideLength: side) else {
            return XCTFail("expected a frame")
        }
        XCTAssertEqual(frame.centre, point(51.5, -0.1))
        let usable = side * (1 - 2 * MiniMapFrame.paddingFraction)
        XCTAssertEqual(
            frame.metresPerPoint,
            MiniMapFrame.minimumSpanMetres / usable,
            accuracy: 1e-9
        )
        // The one point lands dead centre, which is the only honest place for it.
        let projected = frame.project(point(51.5, -0.1), sideLength: side)
        XCTAssertEqual(projected?.x ?? -1, side / 2, accuracy: 1e-6)
        XCTAssertEqual(projected?.y ?? -1, side / 2, accuracy: 1e-6)
    }

    func testATinyTrackIsNotStretchedAcrossTheWholeScreen() {
        // ~10 m of GPS jitter. Below the minimum span it must render as a stub
        // near the centre, not as a screen-filling scribble.
        let jitter = [point(51.5, -0.1), point(51.50009, -0.1)]
        guard let frame = MiniMapFrame.fit(jitter, sideLength: side) else {
            return XCTFail("expected a frame")
        }
        let usable = side * (1 - 2 * MiniMapFrame.paddingFraction)
        XCTAssertEqual(
            frame.metresPerPoint,
            MiniMapFrame.minimumSpanMetres / usable,
            accuracy: 1e-9
        )
        guard let a = frame.project(jitter[0], sideLength: side),
              let b = frame.project(jitter[1], sideLength: side) else {
            return XCTFail("expected both points to project")
        }
        XCTAssertLessThan(abs(a.y - b.y), usable / 4)
    }

    func testFitFramesTheWideSpanAndHonoursThePadding() {
        // ~1 km north-south, narrower east-west: the taller axis sets the scale.
        let points = [point(51.5, -0.1), point(51.509, -0.1)]
        guard let frame = MiniMapFrame.fit(points, sideLength: side) else {
            return XCTFail("expected a frame")
        }
        guard let top = frame.project(points[1], sideLength: side),
              let bottom = frame.project(points[0], sideLength: side) else {
            return XCTFail("expected both points to project")
        }
        let usable = side * (1 - 2 * MiniMapFrame.paddingFraction)
        XCTAssertEqual(bottom.y - top.y, usable, accuracy: 0.5)
        XCTAssertEqual(top.x, side / 2, accuracy: 1e-6)
        // North is up.
        XCTAssertLessThan(top.y, bottom.y)
    }

    func testEastIsRightOfCentre() {
        let points = [point(51.5, -0.1), point(51.5, -0.09)]
        guard let frame = MiniMapFrame.fit(points, sideLength: side),
              let east = frame.project(points[1], sideLength: side),
              let west = frame.project(points[0], sideLength: side) else {
            return XCTFail("expected a frame and two projections")
        }
        XCTAssertGreaterThan(east.x, west.x)
    }

    func testAntimeridianTrackKeepsAFrameItsPointsFitInside() {
        // Six points straddling 180 degrees. A plain longitude subtraction
        // reads this as most of the way round the world and collapses the
        // track to a single pixel.
        let longitudes = [179.85, 179.90, 179.95, -179.95, -179.90, -179.85]
        let points = longitudes.map { point(-17.5, $0) }
        guard let frame = MiniMapFrame.fit(points, sideLength: side) else {
            return XCTFail("expected a frame")
        }
        XCTAssertLessThan(frame.metresPerPoint, 1_000)
        var minX = Double.infinity
        var maxX = -Double.infinity
        for p in points {
            guard let projected = frame.project(p, sideLength: side) else {
                return XCTFail("expected \(p) to project")
            }
            minX = min(minX, projected.x)
            maxX = max(maxX, projected.x)
        }
        XCTAssertGreaterThanOrEqual(minX, 0)
        XCTAssertLessThanOrEqual(maxX, side)
    }

    func testProjectRefusesANonFinitePoint() {
        guard let frame = MiniMapFrame.fit([point(51.5, -0.1)], sideLength: side) else {
            return XCTFail("expected a frame")
        }
        XCTAssertNil(frame.project(point(.nan, -0.1), sideLength: side))
        XCTAssertNil(frame.project(point(51.5, -0.1), sideLength: 0))
    }

    // MARK: - Longitude delta

    func testLongitudeDeltaFoldsAcrossTheAntimeridian() {
        XCTAssertEqual(
            MiniMapGeo.longitudeDeltaDegrees(from: 179.9, to: -179.9),
            0.2,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            MiniMapGeo.longitudeDeltaDegrees(from: -179.9, to: 179.9),
            -0.2,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            MiniMapGeo.longitudeDeltaDegrees(from: -0.2, to: -0.1),
            0.1,
            accuracy: 1e-9
        )
    }

    // MARK: - Trail

    func testTrailKeepsTheFirstFixImmediately() {
        var trail = MiniMapTrail()
        trail.append(point(51.5, -0.1))
        XCTAssertEqual(trail.points, [point(51.5, -0.1)])
    }

    func testTrailRejectsANonFiniteFix() {
        var trail = MiniMapTrail()
        trail.append(point(.nan, -0.1))
        XCTAssertTrue(trail.points.isEmpty)
    }

    func testTrailAdmitsOnePointPerSpacingInterval() {
        var trail = MiniMapTrail()
        // ~5 m per step: only every fourth or so clears the 20 m spacing.
        for i in 0..<40 {
            trail.append(point(51.5 + Double(i) * 0.000045, -0.1))
        }
        XCTAssertGreaterThan(trail.points.count, 5)
        XCTAssertLessThan(trail.points.count, 15)
        for i in 1..<trail.points.count {
            XCTAssertGreaterThanOrEqual(
                MiniMapGeo.distanceMetres(trail.points[i - 1], trail.points[i]),
                MiniMapTrail.initialSpacingMetres - 0.001
            )
        }
    }

    func testAFullTrailHalvesInsteadOfDroppingTheStart() {
        var trail = MiniMapTrail()
        let start = point(51.5, -0.1)
        // 30 m per step, so every fix is admitted until the buffer fills.
        for i in 0...MiniMapTrail.capacity {
            trail.append(point(51.5 + Double(i) * 0.00027, -0.1))
        }
        XCTAssertEqual(trail.points.count, MiniMapTrail.capacity / 2 + 1)
        XCTAssertEqual(trail.points.first, start, "the run start survives thinning")
        XCTAssertEqual(trail.spacingMetres, MiniMapTrail.initialSpacingMetres * 2)
    }

    func testTrailStaysBoundedOverAVeryLongRun() {
        var trail = MiniMapTrail()
        for i in 0..<20_000 {
            trail.append(point(51.5 + Double(i) * 0.00027, -0.1))
        }
        XCTAssertLessThanOrEqual(trail.points.count, MiniMapTrail.capacity)
        XCTAssertEqual(trail.points.first, point(51.5, -0.1))
    }

    func testResetClearsThePointsAndTheSpacing() {
        var trail = MiniMapTrail()
        for i in 0...MiniMapTrail.capacity {
            trail.append(point(51.5 + Double(i) * 0.00027, -0.1))
        }
        trail.reset()
        XCTAssertTrue(trail.points.isEmpty)
        XCTAssertEqual(trail.spacingMetres, MiniMapTrail.initialSpacingMetres)
    }

    // MARK: - Thinning

    func testThinningKeepsBothEndpoints() {
        let kept = MiniMapThinning.keptIndices(count: 9, budget: 4) { _, _, i in Double(i) }
        XCTAssertEqual(kept.first, 0)
        XCTAssertEqual(kept.last, 8)
        XCTAssertEqual(kept.count, 4)
        XCTAssertEqual(kept, kept.sorted())
    }

    func testThinningADegenerateInputComesBackWhole() {
        XCTAssertEqual(MiniMapThinning.keptIndices(count: 0, budget: 4) { _, _, _ in 0 }, [])
        XCTAssertEqual(MiniMapThinning.keptIndices(count: 1, budget: 4) { _, _, _ in 0 }, [0])
        XCTAssertEqual(MiniMapThinning.keptIndices(count: 2, budget: 4) { _, _, _ in 0 }, [0, 1])
    }

    func testAFeaturelessStraightStillFillsTheBudget() {
        let kept = MiniMapThinning.keptIndices(count: 16, budget: 8) { _, _, _ in 0 }
        XCTAssertEqual(kept.count, 8)
        XCTAssertEqual(kept.first, 0)
        XCTAssertEqual(kept.last, 15)
    }

    func testThinningASwitchbackKeepsTheApexesIndexParityWouldCut() {
        // Five apexes 40 m either side of a climbing centre line, sampled at
        // even index parity so `points[0, 2, 4, ...]` would keep only the
        // centre-line points and flatten the whole zig-zag.
        var switchback: [MiniMapOffset] = []
        for i in 0..<21 {
            let north = Double(i) * 20
            let east: Double
            switch i % 4 {
            case 1: east = 40
            case 3: east = -40
            default: east = 0
            }
            switchback.append(MiniMapOffset(east: east, north: north))
        }
        let kept = MiniMapThinning.keptIndices(
            count: switchback.count,
            budget: 11
        ) { a, b, i in
            MiniMapThinning.pointSegmentDistance(switchback[i], switchback[a], switchback[b])
        }
        let apexesKept = kept.filter { $0 % 2 == 1 }.count
        let centreKept = kept.filter { $0 % 2 == 0 }.count
        XCTAssertGreaterThan(
            apexesKept, centreKept,
            "geometric thinning must prefer the apexes over collinear filler"
        )
    }

    func testPointSegmentDistanceClampsToTheSegmentEnds() {
        let a = MiniMapOffset(east: 0, north: 0)
        let b = MiniMapOffset(east: 100, north: 0)
        XCTAssertEqual(
            MiniMapThinning.pointSegmentDistance(MiniMapOffset(east: 50, north: 30), a, b),
            30, accuracy: 1e-9
        )
        XCTAssertEqual(
            MiniMapThinning.pointSegmentDistance(MiniMapOffset(east: -30, north: 0), a, b),
            30, accuracy: 1e-9
        )
        XCTAssertEqual(
            MiniMapThinning.pointSegmentDistance(MiniMapOffset(east: 5, north: 0), a, a),
            5, accuracy: 1e-9
        )
    }

    // MARK: - Content

    func testNothingToDrawWhenThereIsNoRouteNoTrackAndNoFix() {
        XCTAssertNil(
            MiniMapContent.make(route: [], trail: [], current: nil, sideLength: side)
        )
    }

    func testAFixWithNoTrackYetStillDrawsTheRunnersPosition() {
        guard let content = MiniMapContent.make(
            route: [], trail: [], current: point(51.5, -0.1), sideLength: side
        ) else { return XCTFail("expected content") }
        XCTAssertFalse(content.awaitingFix)
        XCTAssertEqual(content.current, point(51.5, -0.1))
        XCTAssertTrue(content.trail.isEmpty)
    }

    func testAnArmedRouteWithNoFixDrawsTheCourseAndReportsTheMissingFix() {
        let route = [point(51.5, -0.1), point(51.51, -0.09)]
        guard let content = MiniMapContent.make(
            route: route, trail: [], current: nil, sideLength: side
        ) else { return XCTFail("expected content") }
        XCTAssertTrue(content.awaitingFix)
        XCTAssertNil(content.current)
        XCTAssertEqual(content.route, route)
    }

    func testANonFiniteFixIsTreatedAsNoFixAtAll() {
        guard let content = MiniMapContent.make(
            route: [point(51.5, -0.1), point(51.51, -0.09)],
            trail: [],
            current: point(.nan, .nan),
            sideLength: side
        ) else { return XCTFail("expected content") }
        XCTAssertTrue(content.awaitingFix)
        XCTAssertNil(content.current)
    }

    func testAFixOutsideTheValidRangeIsNotPlanted() {
        XCTAssertNil(
            MiniMapContent.make(
                route: [], trail: [], current: point(91, 0), sideLength: side
            )
        )
    }

    func testTheFrameSpansTheRouteTheTrackAndTheRunner() {
        let route = [point(51.50, -0.10), point(51.52, -0.10)]
        let trail = [point(51.50, -0.10), point(51.505, -0.10)]
        guard let content = MiniMapContent.make(
            route: route, trail: trail, current: point(51.505, -0.10), sideLength: side
        ) else { return XCTFail("expected content") }
        for p in route + trail {
            guard let projected = content.frame.project(p, sideLength: side) else {
                return XCTFail("expected \(p) to project")
            }
            XCTAssertGreaterThanOrEqual(projected.y, 0)
            XCTAssertLessThanOrEqual(projected.y, side)
        }
    }

    func testALoopRouteReadsAsOneStartFinishMarker() {
        let loop = [
            point(51.50, -0.10),
            point(51.51, -0.10),
            point(51.51, -0.09),
            point(51.500001, -0.100001)
        ]
        guard let content = MiniMapContent.make(
            route: loop, trail: [], current: nil, sideLength: side
        ) else { return XCTFail("expected content") }
        XCTAssertTrue(content.routeIsLoop)
    }

    func testAPointToPointRouteKeepsTwoMarkers() {
        let outAndBack = [point(51.50, -0.10), point(51.52, -0.08)]
        guard let content = MiniMapContent.make(
            route: outAndBack, trail: [], current: nil, sideLength: side
        ) else { return XCTFail("expected content") }
        XCTAssertFalse(content.routeIsLoop)
    }

    func testAnUnguidedRunIsNeverALoop() {
        guard let content = MiniMapContent.make(
            route: [], trail: [point(51.5, -0.1)], current: point(51.5, -0.1), sideLength: side
        ) else { return XCTFail("expected content") }
        XCTAssertFalse(content.routeIsLoop)
    }
}
