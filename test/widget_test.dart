import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arbeitszeit/main.dart';

Map<String, Object> _buildPrefs({
  List<Map<String, dynamic>> sessions = const [],
  List<Map<String, dynamic>> plannedShifts = const [],
  Map<String, dynamic>? settings,
  Map<String, String>? dayTypes,
}) {
  return {
    'work_sessions': sessions.map(jsonEncode).toList(),
    'planned_shifts': plannedShifts.map(jsonEncode).toList(),
    if (settings != null) 'app_settings': jsonEncode(settings),
    if (dayTypes != null) 'day_types': jsonEncode(dayTypes),
  };
}

String _dayKey(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

Future<void> _scrollDown(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE', null);
  });

  testWidgets('App renders work time home page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Arbeitszeit'), findsOneWidget);
    expect(find.textContaining('Heute:'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets(
    'Without planned shifts, logged sessions do not affect monthly overview (8h01 case)',
    (WidgetTester tester) async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final start = DateTime(now.year, now.month, now.day, 8, 0);
      final end = DateTime(now.year, now.month, now.day, 18, 0);

      SharedPreferences.setMockInitialValues(
        _buildPrefs(
          sessions: [
            {
              'start': start.toIso8601String(),
              'end': end.toIso8601String(),
              'paused_seconds': 0,
            },
          ],
          dayTypes: {_dayKey(start): 'worked'},
          settings: {
            'monthlyTargetHours': 169,
            'dailyTargetHours': 8.0,
            'reminderWorkForgotten': true,
            'reminderBreakForgotten': false,
            'reminderEndOfDay': true,
          },
        ),
      );

      await tester.pumpWidget(const MyApp());
      await tester.pump(const Duration(milliseconds: 300));

      await _scrollDown(tester, times: 2);

      expect(find.text('Soll: 169h 00m'), findsOneWidget);
      expect(find.text('Ist: 0h 00m'), findsOneWidget);
    },
  );

  testWidgets(
    'Without planned shifts, logged sessions do not affect monthly overview',
    (WidgetTester tester) async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 8, 0);
      final end = DateTime(now.year, now.month, now.day, 16, 1);

      SharedPreferences.setMockInitialValues(
        _buildPrefs(
          sessions: [
            {
              'start': start.toIso8601String(),
              'end': end.toIso8601String(),
              'paused_seconds': 0,
            },
          ],
          dayTypes: {_dayKey(start): 'worked'},
          settings: {
            'monthlyTargetHours': 169,
            'dailyTargetHours': 8.0,
            'reminderWorkForgotten': true,
            'reminderBreakForgotten': false,
            'reminderEndOfDay': true,
          },
        ),
      );

      await tester.pumpWidget(const MyApp());
      await tester.pump(const Duration(milliseconds: 300));

      await _scrollDown(tester, times: 2);
      expect(find.text('Soll: 169h 00m'), findsOneWidget);
      expect(find.text('Ist: 0h 00m'), findsOneWidget);
    },
  );

  test('Deleting a session removes it from monthly collections', () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final plannedStart = DateTime(now.year, now.month, now.day, 9, 0);
    final plannedEnd = DateTime(now.year, now.month, now.day, 17, 0);
    final sessionStart = DateTime(now.year, now.month, now.day, 8, 0);
    final sessionEnd = DateTime(now.year, now.month, now.day, 16, 1);

    final result = removeSessionEntryFromCollections(
      sessions: [
        WorkSession(
          start: sessionStart,
          end: sessionEnd,
          pausedDuration: Duration.zero,
        ),
      ],
      plannedShifts: {
        _dayKey(day): PlannedShift(
          day: day,
          start: plannedStart,
          end: plannedEnd,
          name: 'Tagesschicht',
          pausedDuration: Duration.zero,
        ),
      },
      dayTypes: {_dayKey(day): DayType.worked},
      session: WorkSession(
        start: sessionStart,
        end: sessionEnd,
        pausedDuration: Duration.zero,
      ),
    );

    expect(result.sessions, isEmpty);
    expect(result.plannedShifts.containsKey(_dayKey(day)), isTrue);
    expect(result.dayTypes[_dayKey(day)], DayType.worked);
  });

  testWidgets('Planned shift without work shows minus for today', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final shiftStart = DateTime(now.year, now.month, now.day, 9, 0);
    final shiftEnd = DateTime(now.year, now.month, now.day, 17, 0);

    SharedPreferences.setMockInitialValues(
      _buildPrefs(
        plannedShifts: [
          {
            'day': day.toIso8601String(),
            'start': shiftStart.toIso8601String(),
            'end': shiftEnd.toIso8601String(),
            'name': 'Tagesschicht',
            'paused_seconds': 0,
          },
        ],
      ),
    );

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Noch bis Feierabend: 8h 00m'), findsOneWidget);
    expect(find.text('Heute im Minus: -8h 00m'), findsOneWidget);
  });

  testWidgets('Update check is blocked on non-Android platforms', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    await _scrollDown(tester, times: 1);
    await tester.ensureVisible(find.text('Nach Update suchen'));
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.text('Nach Update suchen'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('In-App-Update ist nur auf Android verfuegbar.'),
      findsOneWidget,
    );
  });

  testWidgets('Without planned shift, daily target is used for today balance', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8, 0);
    final end = DateTime(now.year, now.month, now.day, 16, 1);

    SharedPreferences.setMockInitialValues(
      _buildPrefs(
        sessions: [
          {
            'start': start.toIso8601String(),
            'end': end.toIso8601String(),
            'paused_seconds': 0,
          },
        ],
        dayTypes: {_dayKey(start): 'worked'},
        settings: {
          'monthlyTargetHours': 160,
          'dailyTargetHours': 8.0,
          'reminderWorkForgotten': true,
          'reminderBreakForgotten': false,
          'reminderEndOfDay': true,
        },
      ),
    );

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ueber Tagesziel: 0h 01m'), findsOneWidget);
    expect(find.text('Heute im Plus: 0h 01m'), findsOneWidget);
  });

  testWidgets('Without planned shift and without work, today stays neutral', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(
      _buildPrefs(
        settings: {
          'monthlyTargetHours': 160,
          'dailyTargetHours': 8.0,
          'reminderWorkForgotten': true,
          'reminderBreakForgotten': false,
          'reminderEndOfDay': true,
        },
      ),
    );

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Noch bis Feierabend: 0h 00m'), findsOneWidget);
    expect(find.text('Heute im Plus: 0h 00m'), findsOneWidget);
  });

  testWidgets('Legacy unmarked sessions do not affect monthly overview', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8, 0);
    final end = DateTime(now.year, now.month, now.day, 16, 1);

    SharedPreferences.setMockInitialValues(
      _buildPrefs(
        sessions: [
          {
            'start': start.toIso8601String(),
            'end': end.toIso8601String(),
            'paused_seconds': 0,
          },
        ],
        settings: {
          'monthlyTargetHours': 169,
          'dailyTargetHours': 8.0,
          'reminderWorkForgotten': true,
          'reminderBreakForgotten': false,
          'reminderEndOfDay': true,
        },
      ),
    );

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Noch bis Feierabend: 0h 00m'), findsOneWidget);
    await _scrollDown(tester, times: 2);
    expect(find.text('Soll: 169h 00m'), findsOneWidget);
    expect(find.text('Ist: 0h 00m'), findsOneWidget);
  });
}
