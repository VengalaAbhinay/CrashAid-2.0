import 'package:flutter_test/flutter_test.dart';
import 'package:crashaid/services/crash_math.dart';

void main() {
  group('applyLowPass', () {
    test('gravity converges to zero when raw is 0', () {
      double g = 9.8;
      for (int i = 0; i < 200; i++) {
        g = applyLowPass(g, 0.0, 0.8);
      }
      expect(g, closeTo(0.0, 0.001));
    });

    test('tracks a constant value exactly after enough steps', () {
      double g = 0.0;
      for (int i = 0; i < 200; i++) {
        g = applyLowPass(g, 9.8, 0.8);
      }
      expect(g, closeTo(9.8, 0.001));
    });

    test('alpha 0 means no memory — instantly follows raw', () {
      final result = applyLowPass(9.8, 0.0, 0.0);
      expect(result, equals(0.0));
    });

    test('alpha 1 means full memory — ignores raw entirely', () {
      final result = applyLowPass(9.8, 0.0, 1.0);
      expect(result, equals(9.8));
    });
  });

  group('linearMagnitude', () {
    test('zero linear acceleration returns 0', () {
      // Phone lying flat — all acceleration is gravity on Z axis
      final m = linearMagnitude(0, 0, 9.8, 0, 0, 9.8);
      expect(m, closeTo(0.0, 0.001));
    });

    test('25 m/s² spike on X axis exceeds crash threshold', () {
      // Simulates a head-on crash impact on the X axis
      final m = linearMagnitude(25, 0, 9.8, 0, 0, 9.8);
      expect(m, greaterThan(24.9));
    });

    test('normal hard braking stays below threshold', () {
      // ~0.5g braking = ~5 m/s² linear on X
      final m = linearMagnitude(5, 0, 9.8, 0, 0, 9.8);
      expect(m, lessThan(25.0));
    });

    test('phone drop spike on all axes — should exceed threshold', () {
      // Diagonal impact across all 3 axes — sqrt(21²+15²) = ~25.8
      final m = linearMagnitude(21, 15, 9.8, 0, 0, 9.8);
      expect(m, greaterThan(25.0));
    });

    test('diagonal crash — magnitude calculated correctly', () {
      // 3-4-5 right triangle: sqrt(3²+4²) = 5 linear mag
      final m = linearMagnitude(3, 4, 9.8, 0, 0, 9.8);
      expect(m, closeTo(5.0, 0.001));
    });
  });
}