import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  test('light theme replaces the grainy InkSparkle splash with InkRipple', () {
    expect(AppTheme.light.splashFactory, same(InkRipple.splashFactory));
    expect(AppTheme.light.splashFactory, isNot(same(InkSparkle.splashFactory)));
  });

  test('dark theme replaces the grainy InkSparkle splash with InkRipple', () {
    expect(AppTheme.dark.splashFactory, same(InkRipple.splashFactory));
    expect(AppTheme.dark.splashFactory, isNot(same(InkSparkle.splashFactory)));
  });
}
