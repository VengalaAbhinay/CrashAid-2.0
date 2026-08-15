import 'dart:math';

/// Pure functions for crash detection math.
/// Kept import-free from Flutter/platform so they can be unit tested
/// without a device or emulator.

/// Applies a single step of a low-pass filter.
/// [prev] is the previous filtered value (gravity estimate).
/// [raw] is the new raw accelerometer reading.
/// [alpha] controls smoothing — higher = more inertia (0.8 is typical).
double applyLowPass(double prev, double raw, double alpha) =>
    alpha * prev + (1 - alpha) * raw;

/// Computes the magnitude of linear acceleration after gravity subtraction.
/// [ax/ay/az] = raw accelerometer readings.
/// [gx/gy/gz] = current gravity estimates from the low-pass filter.
double linearMagnitude(
  double ax, double ay, double az,
  double gx, double gy, double gz,
) {
  final lx = ax - gx;
  final ly = ay - gy;
  final lz = az - gz;
  return sqrt(lx * lx + ly * ly + lz * lz);
}