import 'package:flutter_test/flutter_test.dart';

import '../lib/adaptive_width.dart';

void main() {
  group('widthClassOfWidth', () {
    test('phone widths are compact', () {
      expect(widthClassOfWidth(320), WidthClass.compact);
      expect(widthClassOfWidth(411), WidthClass.compact);
      expect(widthClassOfWidth(599), WidthClass.compact);
    });

    test('600-839 is medium — includes the 800dp flutter_test surface', () {
      expect(widthClassOfWidth(600), WidthClass.medium);
      expect(widthClassOfWidth(800), WidthClass.medium);
      expect(widthClassOfWidth(839), WidthClass.medium);
    });

    test('840+ is expanded — the 10-inch tablet class', () {
      expect(widthClassOfWidth(840), WidthClass.expanded);
      expect(widthClassOfWidth(1280), WidthClass.expanded);
    });
  });
}
