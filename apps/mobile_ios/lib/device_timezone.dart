import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA zone name (`Europe/Berlin`) for server aggregates
/// that bucket by the runner's local day (`run_streaks_for_user`'s
/// `p_tz`, decisions § 471 / § 475). `DateTime.now().timeZoneName` is an
/// abbreviation (`CEST`) the server rejects, and a fixed UTC offset
/// buckets DST-era history onto different days than the on-device
/// display compute — so the platform zone id is the only honest source.
/// When the platform can't name one, degrade to `'UTC'` explicitly: the
/// same fallback web takes when `Intl` fails, still an all-time answer
/// over the right run set, just bucketed in UTC.
Future<String> deviceIanaTimeZone() async {
  try {
    final id = (await FlutterTimezone.getLocalTimezone()).identifier;
    return id.isEmpty ? 'UTC' : id;
  } catch (e) {
    debugPrint('deviceIanaTimeZone failed: $e');
    return 'UTC';
  }
}
