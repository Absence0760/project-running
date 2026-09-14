/// Typed Supabase REST client with auth token management.
///
/// **This package's tests need `flutter test`, not `dart test`.** Nothing in
/// this pubspec says so — the Flutter SDK arrives transitively through
/// `supabase_flutter` — so `dart test` crashes the front-end compiler on every
/// file that imports this library, with `type 'InvalidType' is not a subtype
/// of type 'FunctionType' in type cast` out of `_FfiUseSiteTransformer`. That
/// names no package, no dependency and no runner, and reads as a broken tree.
/// The per-package runner table is in `docs/testing/testing.md § Which runner
/// a package takes`, kept true by `test/test_runner_test.dart`.
library api_client;

export 'src/api_client.dart';
export 'src/chunk.dart';
export 'src/effort_rank.dart';
export 'src/paged_read.dart';
export 'src/segments_rank.dart';
export 'src/settings_service.dart';
