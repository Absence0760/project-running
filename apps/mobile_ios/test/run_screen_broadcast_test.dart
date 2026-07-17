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
}
