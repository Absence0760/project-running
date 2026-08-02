import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/run_screen.dart';

void main() {
  group('shouldStartBroadcastOnRunStart', () {
    test('auto-live-share on starts the broadcast', () {
      expect(
        shouldStartBroadcastOnRunStart(
          autoLiveShareEnabled: true,
          liveShareRequested: false,
          broadcasterActive: false,
        ),
        isTrue,
      );
    });

    test('a manual share request starts the broadcast even with auto off', () {
      // The safety fix: a runner who tapped "Share live link" (whose pre-GO
      // begin may have failed transiently) must still broadcast on GO, so the
      // shared link isn't dead. Without the intent flag this returned false.
      expect(
        shouldStartBroadcastOnRunStart(
          autoLiveShareEnabled: false,
          liveShareRequested: true,
          broadcasterActive: false,
        ),
        isTrue,
      );
    });

    test('no start when neither auto nor a manual request is set', () {
      expect(
        shouldStartBroadcastOnRunStart(
          autoLiveShareEnabled: false,
          liveShareRequested: false,
          broadcasterActive: false,
        ),
        isFalse,
      );
    });

    test('an already-active broadcaster is not re-started', () {
      expect(
        shouldStartBroadcastOnRunStart(
          autoLiveShareEnabled: true,
          liveShareRequested: true,
          broadcasterActive: true,
        ),
        isFalse,
      );
    });
  });

  group('postLiveVisibilityActionOnStop', () {
    // Issue #664: the live window's is_public=true opt-in must not
    // silently outlive the run — keeping a live-shared run public is an
    // explicit post-stop choice, never a side effect of sharing for
    // safety (incl. the Settings → Safety auto-live-share path).
    test('an active broadcast at stop prompts for an explicit choice', () {
      expect(
        postLiveVisibilityActionOnStop(
          broadcastBegun: true,
          broadcasterActiveAtStop: true,
          defaultPublic: false,
          signedIn: true,
        ),
        PostLiveVisibilityAction.prompt,
      );
    });

    test('a share stopped mid-run reverts quietly — the runner already chose',
        () {
      expect(
        postLiveVisibilityActionOnStop(
          broadcastBegun: true,
          broadcasterActiveAtStop: false,
          defaultPublic: false,
          signedIn: true,
        ),
        PostLiveVisibilityAction.revertToDefault,
      );
    });

    test('a public default needs no resolution — the save honoured it', () {
      expect(
        postLiveVisibilityActionOnStop(
          broadcastBegun: true,
          broadcasterActiveAtStop: true,
          defaultPublic: true,
          signedIn: true,
        ),
        PostLiveVisibilityAction.none,
      );
    });

    test('no broadcast begun means nothing to resolve', () {
      expect(
        postLiveVisibilityActionOnStop(
          broadcastBegun: false,
          broadcasterActiveAtStop: false,
          defaultPublic: false,
          signedIn: true,
        ),
        PostLiveVisibilityAction.none,
      );
    });

    test('signed out cannot flip visibility either way', () {
      expect(
        postLiveVisibilityActionOnStop(
          broadcastBegun: true,
          broadcasterActiveAtStop: true,
          defaultPublic: false,
          signedIn: false,
        ),
        PostLiveVisibilityAction.none,
      );
    });
  });
}
