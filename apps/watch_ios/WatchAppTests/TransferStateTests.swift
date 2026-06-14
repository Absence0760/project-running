import XCTest
@testable import WatchApp

/// `WatchConnectivityManager.TransferState` drives the post-run sync UI
/// (`PostRunView` reads `case .failed(let msg)` and shows the message; the
/// "Sent to phone" / "Queued — will retry" status text switches on it). The
/// Equatable conformance with an associated value is easy to get subtly wrong
/// — two `.failed` with different messages must NOT compare equal — so pin it.
///
/// Tested without constructing the manager (its `init` activates a real
/// `WCSession`, unavailable in the unit-test host); the enum is a value type
/// reachable as a nested type.
final class TransferStateTests: XCTestCase {
    typealias State = WatchConnectivityManager.TransferState

    func testSimpleCasesEqual() {
        XCTAssertEqual(State.idle, State.idle)
        XCTAssertEqual(State.pending, State.pending)
        XCTAssertEqual(State.completed, State.completed)
    }

    func testDistinctSimpleCasesNotEqual() {
        XCTAssertNotEqual(State.idle, State.pending)
        XCTAssertNotEqual(State.pending, State.completed)
        XCTAssertNotEqual(State.completed, State.idle)
    }

    func testFailedEqualOnlyWhenMessageMatches() {
        XCTAssertEqual(State.failed("network down"), State.failed("network down"))
        XCTAssertNotEqual(State.failed("network down"), State.failed("timeout"))
    }

    func testFailedNotEqualToSimpleCases() {
        XCTAssertNotEqual(State.failed("x"), State.idle)
        XCTAssertNotEqual(State.failed("x"), State.completed)
    }

    func testPatternMatchExtractsMessage() {
        // PostRunView relies on `if case .failed(let msg)` to surface the
        // error text — pin that the associated value is recoverable.
        let s = State.failed("WCSession not activated")
        guard case .failed(let msg) = s else {
            return XCTFail("Expected .failed")
        }
        XCTAssertEqual(msg, "WCSession not activated")
    }
}
