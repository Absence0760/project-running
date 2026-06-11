import 'package:flutter_test/flutter_test.dart';

import '../lib/event_category.dart';

void main() {
  test('kEventCategories lists every category once in picker order', () {
    expect(kEventCategories, ['run', 'cycle', 'class', 'social']);
  });

  test('run and cycle are athletic', () {
    expect(isAthleticEventCategory('run'), isTrue);
    expect(isAthleticEventCategory('cycle'), isTrue);
  });

  test('class and social are not athletic', () {
    expect(isAthleticEventCategory('class'), isFalse);
    expect(isAthleticEventCategory('social'), isFalse);
  });
}
