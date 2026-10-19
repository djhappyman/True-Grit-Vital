import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/features/recording/actual_time.dart';

void main() {
  test('repeated local clock returns both instants in time order', () {
    final transition = DateTime.utc(2026, 10, 25, 1);
    DateTime london(DateTime instant) => instant.add(
      instant.isBefore(transition) ? const Duration(hours: 1) : Duration.zero,
    );
    final options = actualTimeCandidates(
      DateTime.utc(2026, 10, 25, 1, 30),
      localize: london,
      offsets: const [Duration(hours: 1), Duration.zero],
    );
    expect(options, [
      DateTime.utc(2026, 10, 25, 0, 30),
      DateTime.utc(2026, 10, 25, 1, 30),
    ]);
  });
  test('nonexistent local clock has no candidate; normal clock has one', () {
    final transition = DateTime.utc(2026, 3, 29, 1);
    DateTime london(DateTime instant) => instant.add(
      instant.isBefore(transition) ? Duration.zero : const Duration(hours: 1),
    );
    expect(
      actualTimeCandidates(
        DateTime.utc(2026, 3, 29, 1, 30),
        localize: london,
        offsets: const [Duration.zero, Duration(hours: 1)],
      ),
      isEmpty,
    );
    expect(
      actualTimeCandidates(
        DateTime.utc(2026, 3, 29, 2, 30),
        localize: london,
        offsets: const [Duration.zero, Duration(hours: 1)],
      ),
      [DateTime.utc(2026, 3, 29, 1, 30)],
    );
  });
  test('offset display preserves sign and fractional hours', () {
    expect(utcOffset(const Duration(hours: 5, minutes: 30)), 'UTC+05:30');
    expect(utcOffset(const Duration(hours: -3, minutes: -30)), 'UTC-03:30');
  });
}
