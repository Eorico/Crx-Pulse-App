import 'package:flutter_test/flutter_test.dart';

import 'package:crx_pulse/core/ph_reading_filter.dart';

void main() {
  group('PhReadingFilter', () {
    test('single spike is held', () {
      final f = PhReadingFilter();
      expect(f.accept(7.0), 7.0);
      expect(f.accept(10.0), 7.0);
      expect(f.accept(7.1), 7.1);
    });

    test('confirmed jump is accepted', () {
      final f = PhReadingFilter();
      expect(f.accept(7.0), 7.0);
      expect(f.accept(10.0), 7.0);
      expect(f.accept(10.1), closeTo(10.1, 0.0001));
    });

    test('small drift passes immediately', () {
      final f = PhReadingFilter();
      expect(f.accept(7.0), 7.0);
      expect(f.accept(7.3), 7.3);
    });

    test('reset makes the next reading authoritative', () {
      final f = PhReadingFilter();
      expect(f.accept(7.0), 7.0);
      expect(f.accept(10.0), 7.0);
      f.reset();
      expect(f.accept(10.0), 10.0);
    });

    test('non-finite reading clears state', () {
      final f = PhReadingFilter();
      expect(f.accept(7.0), 7.0);
      expect(f.accept(double.nan), isNull);
      expect(f.accept(10.0), 10.0);
      expect(f.accept(double.infinity), isNull);
      expect(f.accept(7.5), 7.5);
    });

    test('cached reading seeds the next live comparison', () {
      final f = PhReadingFilter();
      f.seed(7.0);
      expect(f.accept(10.0), 7.0);
      expect(f.accept(7.1), 7.1);
    });
  });
}
