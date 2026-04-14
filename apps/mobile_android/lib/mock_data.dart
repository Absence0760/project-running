/// Mock data for local development and testing.

class MockRun {
  final String id;
  final String title;
  final DateTime date;
  final Duration duration;
  final double distanceMetres;

  const MockRun({
    required this.id,
    required this.title,
    required this.date,
    required this.duration,
    required this.distanceMetres,
  });

  String get formattedDistance =>
      '${(distanceMetres / 1000).toStringAsFixed(2)} km';

  String get formattedDuration {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  String get formattedPace {
    if (distanceMetres == 0) return '--:--';
    final paceSeconds = duration.inSeconds / (distanceMetres / 1000);
    final m = (paceSeconds ~/ 60);
    final s = (paceSeconds % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class MockRoute {
  final String id;
  final String name;
  final double distanceMetres;
  final double elevationGainMetres;

  const MockRoute({
    required this.id,
    required this.name,
    required this.distanceMetres,
    this.elevationGainMetres = 0,
  });

  String get formattedDistance =>
      '${(distanceMetres / 1000).toStringAsFixed(1)} km';

  String get formattedElevation => '${elevationGainMetres.toInt()}m gain';
}

final mockRuns = [
  MockRun(
    id: '1',
    title: 'Morning Run',
    date: DateTime(2026, 4, 7),
    duration: const Duration(minutes: 28, seconds: 14),
    distanceMetres: 5230,
  ),
  MockRun(
    id: '2',
    title: 'Interval Training',
    date: DateTime(2026, 4, 5),
    duration: const Duration(minutes: 35, seconds: 42),
    distanceMetres: 6800,
  ),
  MockRun(
    id: '3',
    title: 'Easy Recovery',
    date: DateTime(2026, 4, 3),
    duration: const Duration(minutes: 22, seconds: 8),
    distanceMetres: 3950,
  ),
  MockRun(
    id: '4',
    title: 'Long Run',
    date: DateTime(2026, 3, 30),
    duration: const Duration(hours: 1, minutes: 12, seconds: 33),
    distanceMetres: 14200,
  ),
  MockRun(
    id: '5',
    title: 'parkrun',
    date: DateTime(2026, 3, 29),
    duration: const Duration(minutes: 24, seconds: 51),
    distanceMetres: 5000,
  ),
];

final mockRoutes = [
  const MockRoute(
    id: '1',
    name: 'River Loop',
    distanceMetres: 5400,
    elevationGainMetres: 32,
  ),
  const MockRoute(
    id: '2',
    name: 'Hill Repeats',
    distanceMetres: 3200,
    elevationGainMetres: 145,
  ),
  const MockRoute(
    id: '3',
    name: 'Park Circuit',
    distanceMetres: 7800,
    elevationGainMetres: 58,
  ),
];

double get weeklyDistanceMetres {
  final now = DateTime(2026, 4, 8);
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  return mockRuns
      .where((r) => r.date.isAfter(weekStart.subtract(const Duration(days: 1))))
      .fold(0.0, (sum, r) => sum + r.distanceMetres);
}

int get weeklyRunCount {
  final now = DateTime(2026, 4, 8);
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  return mockRuns
      .where((r) => r.date.isAfter(weekStart.subtract(const Duration(days: 1))))
      .length;
}

Duration get weeklyDuration {
  final now = DateTime(2026, 4, 8);
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  return mockRuns
      .where((r) => r.date.isAfter(weekStart.subtract(const Duration(days: 1))))
      .fold(Duration.zero, (sum, r) => sum + r.duration);
}
