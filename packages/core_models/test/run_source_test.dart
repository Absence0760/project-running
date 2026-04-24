import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  test('Run.toJson serialises RunSource.watch as "watch"', () {
    final run = Run(
      id: 'test-id',
      startedAt: DateTime(2026, 4, 23, 8),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.watch,
    );
    final json = run.toJson();
    expect(json['source'], 'watch');
  });

  test('Run.fromJson deserialises "watch" as RunSource.watch', () {
    final run = Run(
      id: 'test-id',
      startedAt: DateTime(2026, 4, 23, 8),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.watch,
    );
    final json = run.toJson();
    final decoded = Run.fromJson(json);
    expect(decoded.source, RunSource.watch);
  });
}
