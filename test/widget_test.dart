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
}) {
  return {
    'work_sessions': sessions.map(jsonEncode).toList(),
    'planned_shifts': plannedShifts.map(jsonEncode).toList(),
    if (settings != null) 'app_settings': jsonEncode(settings),
  };
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

  testWidgets('Monthly target stays fixed when sessions are logged', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
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

    await _scrollDown(tester, times: 2);

    expect(find.text('Soll: 160h 00m'), findsOneWidget);
    expect(find.text('Ist: 10h 00m'), findsOneWidget);
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
}
