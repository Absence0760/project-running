import XCTest
import WatchConnectivity
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
        let s = State.failed("Phone unavailable")
        guard case .failed(let msg) = s else {
            return XCTFail("Expected .failed")
        }
        XCTAssertEqual(msg, "Phone unavailable")
    }

    // `transferRun` gates on `WCSession.default.activationState == .activated`
    // and returns a Bool the caller (`ContentView.syncRun`) uses to decide
    // whether to mark the run synced. The activation guard is the whole point
    // of issue #372: a `false` when the session isn't activated is what keeps a
    // finished run from being silently dropped. Constructing the manager would
    // activate a real `WCSession` (unavailable in the unit-test host), so the
    // decision is pulled into the pure `canTransfer` and pinned here.
    func testCanTransferOnlyWhenActivated() {
        XCTAssertTrue(WatchConnectivityManager.canTransfer(activationState: .activated))
    }

    func testCanTransferFalseWhenNotActivated() {
        // The cold-launch window: `WCSession.activate()` hasn't completed.
        XCTAssertFalse(WatchConnectivityManager.canTransfer(activationState: .notActivated))
    }

    func testCanTransferFalseWhenInactive() {
        // A session that went `.inactive` (e.g. phone unpaired mid-session)
        // must also refuse the hand-off so the run is kept for retry.
        XCTAssertFalse(WatchConnectivityManager.canTransfer(activationState: .inactive))
    }
}
