import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The auth-transition seam for identity-bearing screens (#223/#232).
///
/// Long-mounted screens — the keep-alive tab pages, pushed settings
/// routes — read identity-derived state (viewer id, email, avatar,
/// per-user server fetches) once at [State.initState] or at build time,
/// and nothing rebuilds them when the session ends or a different
/// account signs in within the same process. Mix this in and implement
/// [onAuthUserChanged] to clear + refetch; the mixin subscribes to
/// [ApiClient.authUserChanges] on mount and calls through only when the
/// authoritative [ApiClient.userId] differs from the id last seen, so
/// token refreshes for the same user dedupe away and implementations
/// can refetch unconditionally.
mixin AuthChangeAware<T extends StatefulWidget> on State<T> {
  StreamSubscription<String?>? _authChangeSub;
  String? _authAwareUserId;

  /// The client whose auth state this screen renders — usually
  /// `widget.apiClient`. Null (backend not configured) means no
  /// subscription: the screen can never show an identity that could
  /// go stale.
  ApiClient? get authApi;

  /// Fired whenever the signed-in user id changes while mounted:
  /// sign-out delivers null, a sign-in or account switch delivers the
  /// new id.
  void onAuthUserChanged(String? userId);

  @override
  void initState() {
    super.initState();
    final api = authApi;
    if (api == null) return;
    _authAwareUserId = api.userId;
    _authChangeSub = api.authUserChanges.listen((_) {
      final current = authApi?.userId;
      if (current == _authAwareUserId) return;
      _authAwareUserId = current;
      if (!mounted) return;
      onAuthUserChanged(current);
    }, onError: (Object e) {
      // L4 auxiliary effect: a broken auth stream must not take the
      // screen down — the screen just stops reacting to transitions.
      debugPrint('AuthChangeAware subscription error: $e');
    });
  }

  @override
  void dispose() {
    _authChangeSub?.cancel();
    super.dispose();
  }
}
