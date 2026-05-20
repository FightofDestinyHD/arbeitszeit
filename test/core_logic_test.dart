import 'package:flutter_test/flutter_test.dart';

import 'package:arbeitszeit/main.dart';

void main() {
  test('WorkSession duration subtracts paused duration', () {
    final start = DateTime(2026, 5, 21, 8, 0);
    final end = DateTime(2026, 5, 21, 17, 0);
    final session = WorkSession(
      start: start,
      end: end,
      pausedDuration: const Duration(minutes: 30),
    );

    expect(session.duration, const Duration(hours: 8, minutes: 30));
  });

  test('PlannedShift duration subtracts paused duration', () {
    final day = DateTime(2026, 5, 21);
    final start = DateTime(2026, 5, 21, 9, 0);
    final end = DateTime(2026, 5, 21, 18, 0);
    final shift = PlannedShift(
      day: day,
      start: start,
      end: end,
      name: 'Spätschicht',
      pausedDuration: const Duration(minutes: 45),
    );

    expect(shift.duration, const Duration(hours: 8, minutes: 15));
  });

  test('UpdateManifest parses build number from int', () {
    final manifest = UpdateManifest.fromJson(const {
      'version': 'v1.1.16',
      'build_number': 10116,
      'apk_url': 'https://example.com/app-release.apk',
      'notes': 'Release notes',
    });

    expect(manifest.version, 'v1.1.16');
    expect(manifest.buildNumber, 10116);
    expect(manifest.apkUrl, 'https://example.com/app-release.apk');
  });

  test('UpdateManifest parses build number from string and trims values', () {
    final manifest = UpdateManifest.fromJson(const {
      'version': ' v1.1.17 ',
      'build_number': ' 10117 ',
      'apk_url': ' https://example.com/app-release.apk ',
      'notes': '  Stable update  ',
    });

    expect(manifest.version, 'v1.1.17');
    expect(manifest.buildNumber, 10117);
    expect(manifest.apkUrl, 'https://example.com/app-release.apk');
    expect(manifest.notes, 'Stable update');
  });
}
