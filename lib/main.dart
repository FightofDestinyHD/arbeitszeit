import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Schichtvorlage für einfache Schichteinträge ---
class ShiftTemplate {
  final String name;
  final TimeOfDay start;
  final TimeOfDay end;

  ShiftTemplate({required this.name, required this.start, required this.end});

  Map<String, dynamic> toJson() => {
        'name': name,
      'start': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
      'end': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
      };

  static ShiftTemplate fromJson(Map<String, dynamic> json) {
    final startParts = (json['start'] as String).split(':');
    final endParts = (json['end'] as String).split(':');
    return ShiftTemplate(
      name: json['name'] as String,
      start: TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1])),
      end: TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1])),
    );
  }
}

class WorkSession {
  const WorkSession({
    required this.start,
    required this.end,
    this.pausedDuration = Duration.zero,
  });

  final DateTime start;
  final DateTime end;
  final Duration pausedDuration;

  Duration get duration => end.difference(start) - pausedDuration;

  Map<String, dynamic> toJson() {
    return {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'paused_seconds': pausedDuration.inSeconds,
    };
  }

  static WorkSession fromJson(Map<String, dynamic> json) {
    return WorkSession(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      pausedDuration: Duration(
        seconds: (json['paused_seconds'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

enum DayType {
  worked,
  vacation,
  sick,
  free,
}

class AppSettings {
  const AppSettings({
    required this.monthlyTargetHours,
    required this.reminderWorkForgotten,
    required this.reminderBreakForgotten,
    required this.reminderEndOfDay,
  });

  final double monthlyTargetHours;
  final bool reminderWorkForgotten;
  final bool reminderBreakForgotten;
  final bool reminderEndOfDay;

  AppSettings copyWith({
    double? monthlyTargetHours,
    bool? reminderWorkForgotten,
    bool? reminderBreakForgotten,
    bool? reminderEndOfDay,
  }) {
    return AppSettings(
      monthlyTargetHours: monthlyTargetHours ?? this.monthlyTargetHours,
      reminderWorkForgotten: reminderWorkForgotten ?? this.reminderWorkForgotten,
      reminderBreakForgotten:
          reminderBreakForgotten ?? this.reminderBreakForgotten,
      reminderEndOfDay: reminderEndOfDay ?? this.reminderEndOfDay,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monthlyTargetHours': monthlyTargetHours,
      'reminderWorkForgotten': reminderWorkForgotten,
      'reminderBreakForgotten': reminderBreakForgotten,
      'reminderEndOfDay': reminderEndOfDay,
    };
  }

  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      monthlyTargetHours: (json['monthlyTargetHours'] as num?)?.toDouble() ?? 160,
      reminderWorkForgotten: json['reminderWorkForgotten'] as bool? ?? true,
      reminderBreakForgotten: json['reminderBreakForgotten'] as bool? ?? false,
      reminderEndOfDay: json['reminderEndOfDay'] as bool? ?? true,
    );
  }

  static const defaults = AppSettings(
    monthlyTargetHours: 160,
    reminderWorkForgotten: true,
    reminderBreakForgotten: false,
    reminderEndOfDay: true,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arbeitszeit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6F5C)),
      ),
      home: const WorkTimeHomePage(),
    );
  }
}

class _OverviewData {
  const _OverviewData({
    required this.today,
    required this.remainingToday,
    required this.isWorking,
    required this.monthWorked,
    required this.monthTarget,
    required this.monthOverUnder,
    required this.activeSince,
  });

  final Duration today;
  final Duration remainingToday;
  final bool isWorking;
  final Duration monthWorked;
  final Duration monthTarget;
  final Duration monthOverUnder;
  final DateTime? activeSince;
}

class _StatsData {
  const _StatsData({
    required this.averageWorkDay,
    required this.longestDay,
    required this.monthOvertime,
    required this.byWeekday,
  });

  final Duration averageWorkDay;
  final Duration longestDay;
  final Duration monthOvertime;
  final Map<int, Duration> byWeekday;
}

class _WeeklyBalance {
  const _WeeklyBalance({
    required this.label,
    required this.balance,
  });

  final String label;
  final Duration balance;
}

class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.apkUrl,
    required this.notes,
    required this.buildNumber,
  });

  final String version;
  final String apkUrl;
  final String notes;
  final int buildNumber;

  static UpdateManifest fromJson(Map<String, dynamic> json) {
    final rawBuild = json['build_number'];
    final parsedBuild = rawBuild is int
        ? rawBuild
        : int.tryParse((rawBuild as String? ?? '').trim()) ?? 0;

    return UpdateManifest(
      version: (json['version'] as String? ?? '').trim(),
      apkUrl: (json['apk_url'] as String? ?? '').trim(),
      notes: (json['notes'] as String? ?? '').trim(),
      buildNumber: parsedBuild,
    );
  }
}

class WorkTimeHomePage extends StatefulWidget {
  const WorkTimeHomePage({super.key});

  @override
  State<WorkTimeHomePage> createState() => _WorkTimeHomePageState();
}

class _WorkTimeHomePageState extends State<WorkTimeHomePage> {
    static const String shiftTemplatesKey = 'shift_templates';

    List<ShiftTemplate> shiftTemplates = [];
  static const String githubOwner = 'FightofDestinyHD';
  static const String githubRepo = 'arbeitszeit';
  static const String githubLatestReleaseUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
  static const String updateManifestUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest/download/update.json';

  static const String sessionsKey = 'work_sessions';
  static const String activeStartKey = 'active_start';
  static const String pauseStartKey = 'pause_start';
  static const String currentSessionPausedKey = 'current_session_paused_seconds';
  static const String settingsKey = 'app_settings';
  static const String dayTypesKey = 'day_types';

  final DateFormat timeFormat = DateFormat('HH:mm');
  final DateFormat dateKeyFormat = DateFormat('yyyy-MM-dd');

  final List<WorkSession> sessions = [];
  final Map<String, DayType> dayTypes = {};

  DateTime? activeStart;
  DateTime? pauseStart;
  Duration currentSessionPaused = Duration.zero;
  bool autoBreakPromptShown = false;
  AppSettings settings = AppSettings.defaults;
  bool loading = true;
  int currentTab = 0;
  DateTime selectedDay = DateTime.now();
  DateTime focusedDay = DateTime.now();
  Timer? uiTimer;
  bool checkingUpdate = false;
  bool installingUpdate = false;
  String? updateMessage;
  UpdateManifest? availableUpdate;
  String? updateSource; // 'GitHub' or 'Fallback'
  StreamSubscription<Uri?>? widgetClickSubscription;
  Uri? pendingWidgetUri;

  @override
  void initState() {
    super.initState();
    _setupWidgetClickHandling();
    restoreState();
    uiTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
        _maybeShowAutoBreakPrompt();
      }
    });
  }

  @override
  void dispose() {
    uiTimer?.cancel();
    widgetClickSubscription?.cancel();
    super.dispose();
  }

  void _setupWidgetClickHandling() {
    widgetClickSubscription = HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) {
        _handleWidgetAction(uri);
      }
    });

    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      if (uri != null) {
        _handleWidgetAction(uri);
      }
    });
  }

  Future<void> _handleWidgetAction(Uri uri) async {
    if (loading) {
      pendingWidgetUri = uri;
      return;
    }

    final action = uri.host.isNotEmpty ? uri.host : uri.path.replaceFirst('/', '');
    if (action == 'pause') {
      if (isPaused) {
        await resumeTracking();
      } else if (activeStart != null) {
        await startPause();
      } else {
        await startTracking();
      }
    } else if (action == 'resume') {
      await resumeTracking();
    } else if (action == 'toggle') {
      if (activeStart == null) {
        await startTracking();
      } else if (isPaused) {
        await resumeTracking();
      } else {
        await startPause();
      }
    }
  }

  Future<void> restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    // Schichtvorlagen laden
    final templatesRaw = prefs.getStringList(shiftTemplatesKey) ?? [];
    shiftTemplates = templatesRaw
        .map((e) => ShiftTemplate.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();

    final rawSessions = prefs.getStringList(sessionsKey) ?? [];
    final restoredSessions = <WorkSession>[];
    for (final item in rawSessions) {
      final map = Map<String, dynamic>.from(jsonDecode(item) as Map);
      restoredSessions.add(WorkSession.fromJson(map));
    }

    final activeStartRaw = prefs.getString(activeStartKey);
    final pauseStartRaw = prefs.getString(pauseStartKey);
    final pausedSecondsRaw = prefs.getInt(currentSessionPausedKey) ?? 0;
    final settingsRaw = prefs.getString(settingsKey);
    final dayTypesRaw = prefs.getString(dayTypesKey);

    final restoredSettings = settingsRaw == null
        ? AppSettings.defaults
        : AppSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(settingsRaw) as Map),
          );

    final restoredDayTypes = <String, DayType>{};
    if (dayTypesRaw != null) {
      final map = Map<String, dynamic>.from(jsonDecode(dayTypesRaw) as Map);
      for (final entry in map.entries) {
        restoredDayTypes[entry.key] = DayType.values.byName(entry.value as String);
      }
    }

    setState(() {
      sessions
        ..clear()
        ..addAll(restoredSessions);
      activeStart =
          activeStartRaw == null ? null : DateTime.parse(activeStartRaw);
      pauseStart = pauseStartRaw == null ? null : DateTime.parse(pauseStartRaw);
      currentSessionPaused = Duration(seconds: pausedSecondsRaw);
      autoBreakPromptShown = false;
      settings = restoredSettings;
      dayTypes
        ..clear()
        ..addAll(restoredDayTypes);
      loading = false;
    });

    await syncWidgetData();

    final queuedUri = pendingWidgetUri;
    if (queuedUri != null) {
      pendingWidgetUri = null;
      await _handleWidgetAction(queuedUri);
    }
  }

  Future<void> persistState() async {
    final prefs = await SharedPreferences.getInstance();
    // Schichtvorlagen speichern
    final encodedTemplates = shiftTemplates.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(shiftTemplatesKey, encodedTemplates);
    final encodedSessions = sessions
        .map((session) => jsonEncode(session.toJson()))
        .toList();

    await prefs.setStringList(sessionsKey, encodedSessions);
    await prefs.setString(settingsKey, jsonEncode(settings.toJson()));

    final dayTypeJson = <String, String>{};
    for (final entry in dayTypes.entries) {
      dayTypeJson[entry.key] = entry.value.name;
    }
    await prefs.setString(dayTypesKey, jsonEncode(dayTypeJson));

    if (activeStart == null) {
      await prefs.remove(activeStartKey);
      await prefs.remove(pauseStartKey);
      await prefs.remove(currentSessionPausedKey);
    } else {
      await prefs.setString(activeStartKey, activeStart!.toIso8601String());
      if (pauseStart == null) {
        await prefs.remove(pauseStartKey);
      } else {
        await prefs.setString(pauseStartKey, pauseStart!.toIso8601String());
      }
      await prefs.setInt(currentSessionPausedKey, currentSessionPaused.inSeconds);
    }
  }

  Future<void> startTracking() async {
    setState(() {
      activeStart = DateTime.now();
      pauseStart = null;
      currentSessionPaused = Duration.zero;
      autoBreakPromptShown = false;
    });
    await persistState();
    await syncWidgetData();
  }

  bool get isPaused => activeStart != null && pauseStart != null;

  Duration _activeSessionNetDuration({DateTime? now}) {
    final started = activeStart;
    if (started == null) {
      return Duration.zero;
    }

    final currentNow = now ?? DateTime.now();
    final activeSpan = currentNow.difference(started);
    final ongoingPause = pauseStart == null ? Duration.zero : currentNow.difference(pauseStart!);
    return activeSpan - currentSessionPaused - ongoingPause;
  }

  Future<void> startPause() async {
    if (activeStart == null || pauseStart != null) {
      return;
    }

    setState(() {
      pauseStart = DateTime.now();
    });
    await persistState();
    await syncWidgetData();
  }

  Future<void> startSuggestedBreak() async {
    if (activeStart == null) {
      return;
    }

    if (pauseStart == null) {
      await startPause();
    }
  }

  void _maybeShowAutoBreakPrompt() {
    if (!mounted || loading) {
      return;
    }
    if (autoBreakPromptShown || !settings.reminderBreakForgotten) {
      return;
    }
    if (activeStart == null || pauseStart != null) {
      return;
    }

    final worked = _activeSessionNetDuration(now: DateTime.now());
    if (worked < const Duration(hours: 6)) {
      return;
    }

    autoBreakPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Pause nicht vergessen?'),
            content: const Text('Du hast jetzt 6 Stunden erreicht. Soll eine Pause gestartet werden?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Später'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await startSuggestedBreak();
                },
                child: const Text('30 Minuten Pause starten'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> resumeTracking() async {
    if (activeStart == null || pauseStart == null) {
      return;
    }

    setState(() {
      currentSessionPaused += DateTime.now().difference(pauseStart!);
      pauseStart = null;
    });
    await persistState();
    await syncWidgetData();
  }

  Future<void> stopTracking() async {
    if (activeStart == null) {
      return;
    }

    final end = DateTime.now();
    final pausedDuration = currentSessionPaused + (pauseStart == null ? Duration.zero : end.difference(pauseStart!));
    setState(() {
      sessions.insert(
        0,
        WorkSession(
          start: activeStart!,
          end: end,
          pausedDuration: pausedDuration,
        ),
      );
      activeStart = null;
      pauseStart = null;
      currentSessionPaused = Duration.zero;
      autoBreakPromptShown = false;
    });

    await persistState();
    await syncWidgetData();
  }

  Duration todayDuration() {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    var total = Duration.zero;

    for (final session in sessions) {
      if (isSameDay(session.start, dayStart)) {
        total += session.duration;
      }
    }

    if (activeStart != null && isSameDay(activeStart!, dayStart)) {
      total += _activeSessionNetDuration(now: DateTime.now());
    }

    return total;
  }

  Duration monthDuration(DateTime month) {
    var total = Duration.zero;
    for (final session in sessions) {
      if (session.start.year == month.year && session.start.month == month.month) {
        total += session.duration;
      }
    }

    if (activeStart != null &&
        activeStart!.year == month.year &&
        activeStart!.month == month.month) {
      total += _activeSessionNetDuration(now: DateTime.now());
    }

    return total;
  }

  Duration monthlyTargetDuration(DateTime month) {
    return Duration(minutes: (settings.monthlyTargetHours * 60).round());
  }

  double workingDaysInMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    var days = 0.0;

    for (var day = first;
        day.isBefore(nextMonth);
        day = day.add(const Duration(days: 1))) {
      if (day.weekday >= DateTime.monday && day.weekday <= DateTime.friday) {
        days += 1;
      }
    }
    return days <= 0 ? 20 : days;
  }

  Duration targetPerWorkday(DateTime month) {
    final monthly = monthlyTargetDuration(month);
    final workDays = workingDaysInMonth(month);
    final dailyMinutes = (monthly.inMinutes / workDays).round();
    return Duration(minutes: dailyMinutes);
  }

  Duration remainingToday() {
    final target = targetPerWorkday(DateTime.now());
    final remaining = target - todayDuration();
    return remaining;
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String formatDuration(Duration duration) {
    final negative = duration.isNegative;
    final absDuration = negative ? duration.abs() : duration;
    final hours = absDuration.inHours;
    final minutes = absDuration.inMinutes.remainder(60);
    final base = '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    return negative ? '-$base' : base;
  }

  String dayKey(DateTime day) {
    return dateKeyFormat.format(DateTime(day.year, day.month, day.day));
  }

  DayType effectiveDayType(DateTime day) {
    final key = dayKey(day);
    final stored = dayTypes[key];
    if (stored != null) {
      return stored;
    }

    final hasWork = sessions.any((session) => isSameDay(session.start, day));
    if (hasWork) {
      return DayType.worked;
    }
    return DayType.free;
  }

  Color colorForDayType(DayType type, BuildContext context) {
    switch (type) {
      case DayType.worked:
        return Colors.green.shade500;
      case DayType.vacation:
        return Colors.blue.shade500;
      case DayType.sick:
        return Colors.orange.shade700;
      case DayType.free:
        return Colors.grey.shade500;
    }
  }

  String labelForDayType(DayType type) {
    switch (type) {
      case DayType.worked:
        return 'gearbeitet';
      case DayType.vacation:
        return 'urlaub';
      case DayType.sick:
        return 'krank';
      case DayType.free:
        return 'frei';
    }
  }

  Future<void> setSelectedDayType(DayType type) async {
    setState(() {
      dayTypes[dayKey(selectedDay)] = type;
    });
    await persistState();
  }

  String formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  TimeOfDay? parseTimeInput(String input) {
    final normalized = input.trim().replaceAll('.', ':');
    final parts = normalized.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> addShiftFromTemplate(ShiftTemplate template, DateTime day) async {
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      template.start.hour,
      template.start.minute,
    );
    var end = DateTime(
      day.year,
      day.month,
      day.day,
      template.end.hour,
      template.end.minute,
    );

    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }

    setState(() {
      sessions.insert(0, WorkSession(start: start, end: end));
      dayTypes[dayKey(day)] = DayType.worked;
    });
    await persistState();
    await syncWidgetData();
  }

  Future<void> showTemplateDialog({ShiftTemplate? template, int? index}) async {
    final nameController = TextEditingController(text: template?.name ?? '');
    final startController = TextEditingController(
      text: template == null ? '08:00' : formatTimeOfDay(template.start),
    );
    final endController = TextEditingController(
      text: template == null ? '16:00' : formatTimeOfDay(template.end),
    );

    final result = await showDialog<ShiftTemplate>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(template == null ? 'Vorlage erstellen' : 'Vorlage bearbeiten'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name (z.B. Frühschicht)'),
              ),
              TextField(
                controller: startController,
                decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                keyboardType: TextInputType.datetime,
              ),
              TextField(
                controller: endController,
                decoration: const InputDecoration(labelText: 'Ende (HH:mm)'),
                keyboardType: TextInputType.datetime,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final start = parseTimeInput(startController.text);
                final end = parseTimeInput(endController.text);
                if (name.isEmpty || start == null || end == null) {
                  return;
                }
                Navigator.pop(
                  context,
                  ShiftTemplate(name: name, start: start, end: end),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      if (index == null) {
        shiftTemplates.add(result);
      } else {
        shiftTemplates[index] = result;
      }
    });
    await persistState();
  }

  _OverviewData buildOverviewData() {
    final monthWorked = monthDuration(DateTime.now());
    final monthTarget = monthlyTargetDuration(DateTime.now());
    return _OverviewData(
      today: todayDuration(),
      remainingToday: remainingToday(),
      isWorking: activeStart != null,
      monthWorked: monthWorked,
      monthTarget: monthTarget,
      monthOverUnder: monthWorked - monthTarget,
      activeSince: activeStart,
    );
  }

  _StatsData buildStatsData() {
    final now = DateTime.now();
    final thisMonth = sessions
        .where((s) => s.start.year == now.year && s.start.month == now.month)
        .toList();

    final byDay = <String, Duration>{};
    for (final session in thisMonth) {
      final key = dayKey(session.start);
      byDay[key] = (byDay[key] ?? Duration.zero) + session.duration;
    }

    Duration average = Duration.zero;
    Duration longest = Duration.zero;

    if (byDay.isNotEmpty) {
      final total = byDay.values.fold(Duration.zero, (a, b) => a + b);
      average = Duration(minutes: (total.inMinutes / byDay.length).round());
      for (final value in byDay.values) {
        if (value > longest) {
          longest = value;
        }
      }
    }

    final byWeekday = <int, Duration>{
      DateTime.monday: Duration.zero,
      DateTime.tuesday: Duration.zero,
      DateTime.wednesday: Duration.zero,
      DateTime.thursday: Duration.zero,
      DateTime.friday: Duration.zero,
      DateTime.saturday: Duration.zero,
      DateTime.sunday: Duration.zero,
    };

    for (final session in thisMonth) {
      byWeekday[session.start.weekday] =
          (byWeekday[session.start.weekday] ?? Duration.zero) + session.duration;
    }

    final monthOvertime = monthDuration(now) - monthlyTargetDuration(now);

    return _StatsData(
      averageWorkDay: average,
      longestDay: longest,
      monthOvertime: monthOvertime,
      byWeekday: byWeekday,
    );
  }

  List<_WeeklyBalance> buildWeeklyBalances(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final targetPerDay = targetPerWorkday(month);
    final weeks = <int, Duration>{};

    for (var day = firstDay; !day.isAfter(lastDay); day = day.add(const Duration(days: 1))) {
      final normalizedDay = DateTime(day.year, day.month, day.day);
      final weekIndex = ((normalizedDay.day - 1) ~/ 7) + 1;
      final hasSession = sessions.any((session) => isSameDay(session.start, normalizedDay));
      final effectiveType = effectiveDayType(normalizedDay);

      Duration dayBalance = Duration.zero;
      if (hasSession) {
        final worked = sessions
            .where((session) => isSameDay(session.start, normalizedDay))
            .fold(Duration.zero, (total, session) => total + session.duration);
        dayBalance = worked - targetPerDay;
      } else if (effectiveType == DayType.vacation || effectiveType == DayType.sick) {
        dayBalance = Duration.zero;
      } else if (normalizedDay.weekday >= DateTime.monday &&
          normalizedDay.weekday <= DateTime.friday) {
        dayBalance = -targetPerDay;
      }

      weeks[weekIndex] = (weeks[weekIndex] ?? Duration.zero) + dayBalance;
    }

    return weeks.entries
        .map((entry) => _WeeklyBalance(label: 'W${entry.key}', balance: entry.value))
        .toList()
      ..sort((left, right) => left.label.compareTo(right.label));
  }

  Color colorForBalance(Duration balance, BuildContext context) {
    if (balance.isNegative) {
      return Colors.red.shade600;
    }
    if (balance > Duration.zero) {
      return Colors.green.shade600;
    }
    return Theme.of(context).colorScheme.primary;
  }

  String labelForBalance(Duration balance) {
    if (balance.isNegative) {
      return 'Minusstunden';
    }
    if (balance > Duration.zero) {
      return 'Plusstunden';
    }
    return 'Ausgeglichen';
  }

  Widget buildBalanceCard({
    required BuildContext context,
    required String title,
    required Duration balance,
    required IconData icon,
  }) {
    final color = colorForBalance(balance, context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            formatDuration(balance),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(labelForBalance(balance), style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget buildWeeklyBalanceChart(BuildContext context, List<_WeeklyBalance> balances) {
    if (balances.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxMinutes = balances
        .map((entry) => entry.balance.inMinutes.abs())
        .fold<int>(0, (maxValue, value) => value > maxValue ? value : maxValue);
    final safeMax = maxMinutes == 0 ? 1 : maxMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wochenbilanz', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...balances.map((entry) {
          final color = colorForBalance(entry.balance, context);
          final ratio = entry.balance.inMinutes.abs() / safeMax;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(width: 34, child: Text(entry.label)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0, 1),
                      minHeight: 14,
                      backgroundColor: color.withValues(alpha: 0.16),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 82,
                  child: Text(
                    formatDuration(entry.balance),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  int isoWeekNumber(DateTime date) {
    final mondayBasedWeekday = date.weekday == DateTime.sunday ? 7 : date.weekday;
    final thursday = date.add(Duration(days: 4 - mondayBasedWeekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstMondayBasedWeekday = firstThursday.weekday == DateTime.sunday
        ? 7
        : firstThursday.weekday;
    final firstWeekThursday = firstThursday
        .add(Duration(days: 4 - firstMondayBasedWeekday));
    return 1 + thursday.difference(firstWeekThursday).inDays ~/ 7;
  }

  List<int> weekNumbersForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOfGrid = firstDay.subtract(
      Duration(days: firstDay.weekday == DateTime.sunday ? 6 : firstDay.weekday - DateTime.monday),
    );

    return List<int>.generate(
      6,
      (index) => isoWeekNumber(startOfGrid.add(Duration(days: index * 7))),
    );
  }

  Future<void> syncWidgetData() async {
    final overview = buildOverviewData();
    await HomeWidget.saveWidgetData<String>(
      'today_duration',
      formatDuration(overview.today),
    );
    await HomeWidget.saveWidgetData<String>(
      'remaining_duration',
      formatDuration(overview.remainingToday),
    );
    await HomeWidget.saveWidgetData<String>(
      'status_text',
      overview.isWorking
          ? (isPaused ? 'Pause läuft' : 'eingestempelt')
          : 'ausgestempelt',
    );
    await HomeWidget.saveWidgetData<String>(
      'month_balance',
      formatDuration(overview.monthOverUnder),
    );
    await HomeWidget.saveWidgetData<bool>(
      'is_working',
      overview.isWorking,
    );
    await HomeWidget.saveWidgetData<bool>(
      'is_paused',
      isPaused,
    );
    await HomeWidget.saveWidgetData<String>(
      'action_label',
      activeStart == null
          ? 'Start'
          : (isPaused ? 'Pause beenden' : 'Pause starten'),
    );
    await HomeWidget.saveWidgetData<String?>(
      'active_start_millis',
      overview.activeSince?.millisecondsSinceEpoch.toString(),
    );
    await HomeWidget.updateWidget(
      name: 'ArbeitszeitWidgetProvider',
      iOSName: 'ArbeitszeitWidget',
    );
  }

  Future<String> exportCsv() async {
    final dir = await getApplicationDocumentsDirectory();
    final month = DateTime.now();
    final fileName =
        'arbeitszeit_${month.year}_${month.month.toString().padLeft(2, '0')}.csv';
    final file = File('${dir.path}/$fileName');

    final buffer = StringBuffer();
    buffer.writeln('Datum,Start,Ende,DauerMinuten');

    for (final session in sessions) {
      if (session.start.year == month.year && session.start.month == month.month) {
        final day = DateFormat('yyyy-MM-dd').format(session.start);
        final start = formatTimeOfDay(TimeOfDay.fromDateTime(session.start));
        final end = formatTimeOfDay(TimeOfDay.fromDateTime(session.end));
        buffer.writeln('$day,$start,$end,${session.duration.inMinutes}');
      }
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }

  Future<String> exportPdf() async {
    final month = DateTime.now();
    final doc = pw.Document();
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(month);
    final worked = monthDuration(month);
    final target = monthlyTargetDuration(month);
    final diff = worked - target;

    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Arbeitszeitbericht $monthLabel'),
              pw.SizedBox(height: 10),
              pw.Text('Sollstunden: ${formatDuration(target)}'),
              pw.Text('Iststunden: ${formatDuration(worked)}'),
              pw.Text('Differenz: ${formatDuration(diff)}'),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'arbeitszeit_${month.year}_${month.month.toString().padLeft(2, '0')}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  Future<void> showExportSnackBar(Future<String> Function() exportFn) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await exportFn();
      messenger.showSnackBar(
        SnackBar(content: Text('Export gespeichert: $path')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export fehlgeschlagen.')),
      );
    }
  }

  Future<void> editMonthlyTargetHours() async {
    final controller = TextEditingController(
      text: settings.monthlyTargetHours.toStringAsFixed(0),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Monatliche Sollstunden'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Stunden pro Monat',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
                if (parsed != null && parsed > 0) {
                  Navigator.pop(context, parsed);
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      settings = settings.copyWith(monthlyTargetHours: result);
    });
    await persistState();
    await syncWidgetData();
  }

  int compareVersions(String a, String b) {
    final aParts = normalizedVersion(a)
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
    final bParts = normalizedVersion(b)
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < maxLen; i++) {
      final left = i < aParts.length ? aParts[i] : 0;
      final right = i < bParts.length ? bParts[i] : 0;
      if (left > right) {
        return 1;
      }
      if (left < right) {
        return -1;
      }
    }
    return 0;
  }

  String normalizedVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }

    final plusIndex = value.indexOf('+');
    if (plusIndex != -1) {
      value = value.substring(0, plusIndex);
    }

    final clean = value
        .split('.')
        .map((segment) {
          final digits = segment.replaceAll(RegExp(r'[^0-9]'), '');
          return digits.isEmpty ? '0' : digits;
        })
        .join('.');

    return clean.isEmpty ? '0' : clean;
  }

  int buildNumberFromVersion(String raw) {
    final parts = normalizedVersion(raw)
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    final major = parts.isNotEmpty ? parts[0] : 0;
    final minor = parts.length > 1 ? parts[1] : 0;
    final patch = parts.length > 2 ? parts[2] : 0;

    return major * 10000 + minor * 100 + patch;
  }

  UpdateManifest parseGithubRelease(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    final releaseName = (json['name'] as String? ?? '').trim();
    final releaseBody = (json['body'] as String? ?? '').trim();
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    String apkUrl = '';
    for (final asset in assets) {
      final fileName = (asset['name'] as String? ?? '').toLowerCase();
      final browserUrl = (asset['browser_download_url'] as String? ?? '').trim();
      if (browserUrl.isEmpty) {
        continue;
      }
      if (fileName.endsWith('.apk')) {
        apkUrl = browserUrl;
        break;
      }
    }

    if (apkUrl.isEmpty) {
      throw Exception('Kein APK-Asset im letzten GitHub Release gefunden.');
    }

    final version = tagName.isNotEmpty ? tagName : releaseName;
    if (version.isEmpty) {
      throw Exception('Release-Version in GitHub ist leer.');
    }

    return UpdateManifest(
      version: version,
      apkUrl: apkUrl,
      notes: releaseBody,
      buildNumber: buildNumberFromVersion(version),
    );
  }

  Future<UpdateManifest> fetchUpdateManifest() async {
    final releaseResponse = await http.get(
      Uri.parse(githubLatestReleaseUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'arbeitszeit-app',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (releaseResponse.statusCode == 200) {
      setState(() {
        updateSource = 'GitHub';
      });
      final releaseMap =
          Map<String, dynamic>.from(jsonDecode(releaseResponse.body) as Map);
      return parseGithubRelease(releaseMap);
    }

    // Fallback for local/manual hosting scenarios.
    final fallbackResponse = await http.get(Uri.parse(updateManifestUrl));
    if (fallbackResponse.statusCode != 200) {
      setState(() {
        updateSource = null;
      });
      throw Exception(
        'GitHub Release API nicht erreichbar ('
        '${releaseResponse.statusCode}) und Fallback fehlgeschlagen ('
        '${fallbackResponse.statusCode}).',
      );
    }

    setState(() {
      updateSource = 'Fallback';
    });
    final fallbackMap =
        Map<String, dynamic>.from(jsonDecode(fallbackResponse.body) as Map);
    final manifest = UpdateManifest.fromJson(fallbackMap);
    if (manifest.version.isEmpty || manifest.apkUrl.isEmpty) {
      throw Exception('Fallback update.json ist unvollstaendig.');
    }
    return manifest;
  }

  Future<void> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        updateMessage = 'In-App-Update ist nur auf Android verfuegbar.';
        availableUpdate = null;
      });
      return;
    }

    setState(() {
      checkingUpdate = true;
      updateMessage = null;
      updateSource = null;
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber =
          int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
      final manifest = await fetchUpdateManifest();

      final hasUpdate = manifest.buildNumber > 0 && currentBuildNumber > 0
          ? manifest.buildNumber > currentBuildNumber
          : compareVersions(manifest.version, currentVersion) > 0;
      setState(() {
        availableUpdate = hasUpdate ? manifest : null;
        updateMessage = hasUpdate
            ? 'Update ${manifest.version} verfuegbar (Build ${manifest.buildNumber}).'
            : 'App ist aktuell (Version $currentVersion, Build $currentBuildNumber).';
      });
    } catch (e) {
      setState(() {
        availableUpdate = null;
        updateMessage = 'Update-Pruefung fehlgeschlagen: $e';
      });
    } finally {
      setState(() {
        checkingUpdate = false;
      });
    }
  }

  Future<void> installAvailableUpdate() async {
    final manifest = availableUpdate;
    if (manifest == null) {
      return;
    }
    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        updateMessage = 'In-App-Update ist nur auf Android verfuegbar.';
      });
      return;
    }

    setState(() {
      installingUpdate = true;
      updateMessage = 'Update wird heruntergeladen...';
    });

    StreamSubscription<dynamic>? subscription;
    try {
      final done = Completer<void>();
      subscription = OtaUpdate().execute(
        manifest.apkUrl,
        destinationFilename: 'arbeitszeit_${manifest.version.replaceAll('.', '_')}.apk',
      ).listen((event) {
        if (!mounted) {
          return;
        }
        final status = event.status.toString();
        final value = event.value.toString();

        setState(() {
          if (status.contains('INSTALLING')) {
            updateMessage =
                'Download fertig. Android-Installer wird gestartet...';
          } else if (status.contains('DOWNLOADING')) {
            updateMessage = value;
          } else if (status.contains('ALREADY_RUNNING_ERROR') ||
              status.contains('PERMISSION_NOT_GRANTED_ERROR') ||
              status.contains('INSTALL_FAILED')) {
            updateMessage =
                'In-App-Installation fehlgeschlagen. Nutze "APK im Browser öffnen".';
            if (!done.isCompleted) {
              done.complete();
            }
          } else {
            updateMessage = value;
          }
        });

        if (status.contains('INSTALLING') || status.contains('INSTALLED')) {
          if (!done.isCompleted) {
            done.complete();
          }
        }
      }, onError: (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          updateMessage =
              'Update-Installation fehlgeschlagen. Nutze "APK im Browser öffnen".';
        });
        if (!done.isCompleted) {
          done.complete();
        }
      });

      await done.future.timeout(const Duration(minutes: 3), onTimeout: () {
        if (mounted) {
          setState(() {
            updateMessage =
                'Installer reagiert nicht. Bitte "APK im Browser öffnen" nutzen.';
          });
        }
      });
    } catch (e) {
      setState(() {
        updateMessage =
            'Update-Installation fehlgeschlagen: $e. Nutze "APK im Browser öffnen".';
      });
    } finally {
      await subscription?.cancel();
      setState(() {
        installingUpdate = false;
      });
    }
  }

  Future<void> openUpdateInBrowser() async {
    final manifest = availableUpdate;
    if (manifest == null) {
      return;
    }

    final uri = Uri.tryParse(manifest.apkUrl);
    if (uri == null) {
      setState(() {
        updateMessage = 'APK-URL ist ungültig.';
      });
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() {
        updateMessage = 'Konnte APK-Link nicht im Browser öffnen.';
      });
    }
  }

  Widget buildOverviewTab() {
    final data = buildOverviewData();
    final monthColor = colorForBalance(data.monthOverUnder, context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Heute: ${formatDuration(data.today)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  data.remainingToday.isNegative
                      ? 'Ueber Tagesziel: ${formatDuration(data.remainingToday)}'
                      : 'Noch bis Feierabend: ${formatDuration(data.remainingToday)}',
                ),
                const SizedBox(height: 8),
                Text(
                  data.isWorking
                      ? 'Status: seit ${timeFormat.format(data.activeSince!)} eingestempelt'
                      : 'Status: ausgestempelt',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: data.isWorking ? null : startTracking,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: data.isWorking ? stopTracking : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: data.isWorking
                          ? OutlinedButton.icon(
                              onPressed: isPaused ? resumeTracking : startPause,
                              icon: Icon(isPaused ? Icons.play_arrow : Icons.free_breakfast),
                              label: Text(isPaused ? 'Pause beenden' : 'Pause starten'),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildBalanceCard(
                context: context,
                title: 'Monatsbilanz',
                balance: data.monthOverUnder,
                icon: Icons.stacked_line_chart,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buildBalanceCard(
                context: context,
                title: 'Heute',
                balance: data.today - targetPerWorkday(DateTime.now()),
                icon: Icons.today,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('App-Update', style: Theme.of(context).textTheme.titleLarge),
                if (updateSource != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        updateSource == 'GitHub' ? Icons.cloud : Icons.storage,
                        size: 18,
                        color: updateSource == 'GitHub'
                            ? Colors.blue
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Quelle: ${updateSource == 'GitHub' ? 'GitHub Releases API' : 'Fallback update.json'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Die App prueft auf eine neue APK aus deinem GitHub-Repository.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: checkingUpdate ? null : checkForUpdate,
                        icon: const Icon(Icons.system_update_alt),
                        label: Text(checkingUpdate
                            ? 'Pruefe...'
                            : 'Nach Update suchen'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: availableUpdate == null || installingUpdate
                            ? null
                            : installAvailableUpdate,
                        icon: const Icon(Icons.download),
                        label: Text(installingUpdate
                            ? 'Installiere...'
                            : 'Update installieren'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: availableUpdate == null
                            ? null
                            : openUpdateInBrowser,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('APK im Browser öffnen'),
                      ),
                    ),
                  ],
                ),
                if (availableUpdate != null) ...[
                  const SizedBox(height: 10),
                  Text('Version: ${availableUpdate!.version}'),
                  if (availableUpdate!.notes.isNotEmpty)
                    Text('Hinweise: ${availableUpdate!.notes}'),
                ],
                if (updateMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(updateMessage!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monatsuebersicht', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Soll: ${formatDuration(data.monthTarget)}'),
                Text('Ist: ${formatDuration(data.monthWorked)}'),
                Text(
                  data.monthOverUnder.isNegative
                      ? 'Minusstunden: ${formatDuration(data.monthOverUnder)}'
                      : 'Ueberstunden: ${formatDuration(data.monthOverUnder)}',
                  style: TextStyle(color: monthColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildCalendarTab() {
    final selectedType = effectiveDayType(selectedDay);
    final theme = Theme.of(context);
    final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(focusedDay);
    final weekNumbers = weekNumbersForMonth(focusedDay);

    Widget buildDayCell(DateTime day, {bool selected = false, bool today = false}) {
      final type = effectiveDayType(day);
      final baseColor = colorForDayType(type, context);
      final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

      Color backgroundColor;
      Color textColor;
      BoxBorder? border;

      if (selected) {
        backgroundColor = const Color(0xFF2F80ED);
        textColor = Colors.white;
        border = Border.all(color: const Color(0xFF5AA7FF), width: 1.2);
      } else if (today) {
        backgroundColor = const Color(0xFF262A30);
        textColor = Colors.white;
        border = Border.all(color: const Color(0xFF2F80ED), width: 1.2);
      } else if (type == DayType.free) {
        backgroundColor = const Color(0xFF1F2227);
        textColor = isWeekend ? const Color(0xFFFF5A5F) : Colors.white.withValues(alpha: 0.88);
        border = Border.all(color: const Color(0xFF2A2F36));
      } else {
        backgroundColor = baseColor.withValues(alpha: 0.12);
        textColor = isWeekend ? const Color(0xFFFF5A5F) : Colors.white;
        border = Border.all(color: baseColor.withValues(alpha: 0.35));
      }

      return Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(999),
            border: border,
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
              color: textColor,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF191C22),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF2A2F36)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                surface: const Color(0xFF191C22),
                primary: const Color(0xFF2F80ED),
                onSurface: Colors.white,
              ),
              textTheme: Theme.of(context).textTheme.apply(
                bodyColor: Colors.white,
                displayColor: Colors.white,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            monthLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tippen zum Auswaehlen, lang tippen fuer Schicht',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262A30),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF2F80ED)),
                      ),
                      child: Text(
                        DateFormat('dd.MM', 'de_DE').format(selectedDay),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Column(
                        children: [
                          const SizedBox(height: 28),
                          const SizedBox(height: 28),
                          ...weekNumbers.map(
                            (week) => SizedBox(
                              height: 52,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$week',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TableCalendar<dynamic>(
                        locale: 'de_DE',
                        firstDay: DateTime(2020, 1, 1),
                        lastDay: DateTime(2100, 12, 31),
                        focusedDay: focusedDay,
                        selectedDayPredicate: (day) => isSameDay(day, selectedDay),
                        availableGestures: AvailableGestures.horizontalSwipe,
                        calendarFormat: CalendarFormat.month,
                        sixWeekMonthsEnforced: true,
                        shouldFillViewport: true,
                        rowHeight: 52,
                        daysOfWeekHeight: 28,
                        headerVisible: false,
                        availableCalendarFormats: const {CalendarFormat.month: 'Monat'},
                        onDaySelected: (selected, focused) {
                          setState(() {
                            selectedDay = selected;
                            focusedDay = focused;
                          });
                        },
                        onDayLongPressed: (selected, focused) async {
                          setState(() {
                            selectedDay = selected;
                            focusedDay = focused;
                          });
                          await _showShiftDialog(context, selected);
                        },
                        onPageChanged: (focused) {
                          setState(() {
                            focusedDay = focused;
                          });
                        },
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          weekendStyle: const TextStyle(
                            color: Color(0xFFFF5A5F),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: true,
                          todayDecoration: BoxDecoration(
                            color: const Color(0xFF262A30),
                            border: Border.all(color: const Color(0xFF2F80ED), width: 1.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          selectedDecoration: BoxDecoration(
                            color: const Color(0xFF2F80ED),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          defaultTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          weekendTextStyle: const TextStyle(
                            color: Color(0xFFFF5A5F),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          outsideTextStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.28),
                            fontSize: 12,
                          ),
                          todayTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          selectedTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          cellMargin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        ),
                        calendarBuilders: CalendarBuilders(
                          defaultBuilder: (context, day, focusedDay) {
                            return buildDayCell(day);
                          },
                          todayBuilder: (context, day, focusedDay) {
                            return buildDayCell(day, today: true);
                          },
                          selectedBuilder: (context, day, focusedDay) {
                            return buildDayCell(day, selected: true);
                          },
                          outsideBuilder: (context, day, focusedDay) {
                            return buildDayCell(day);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _showShiftDialog(context, selectedDay),
                        icon: const Icon(Icons.add),
                        label: const Text('Schicht'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          if (isPaused) {
                            resumeTracking();
                          } else {
                            startPause();
                          }
                        },
                        icon: Icon(isPaused ? Icons.play_arrow : Icons.free_breakfast),
                        label: Text(isPaused ? 'Weiter' : 'Pause'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => setState(() {
                          selectedDay = DateTime.now();
                          focusedDay = DateTime.now();
                        }),
                        icon: const Icon(Icons.today),
                        label: const Text('Heute'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Status für ${DateFormat('dd.MM.yyyy').format(selectedDay)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: DayType.values
              .map(
                (type) => ChoiceChip(
                  label: Text(labelForDayType(type)),
                  selected: selectedType == type,
                  selectedColor: colorForDayType(type, context).withAlpha(50),
                  onSelected: (_) => setSelectedDayType(type),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Schichtvorlagen', style: Theme.of(context).textTheme.titleMedium),
                    IconButton(
                      onPressed: () => showTemplateDialog(),
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Vorlage erstellen',
                    ),
                  ],
                ),
                if (shiftTemplates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Noch keine Vorlagen vorhanden.'),
                  ),
                ...shiftTemplates.asMap().entries.map(
                  (entry) {
                    final idx = entry.key;
                    final template = entry.value;
                    return ListTile(
                      dense: true,
                      title: Text(template.name),
                      subtitle: Text(
                        '${formatTimeOfDay(template.start)} - ${formatTimeOfDay(template.end)}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            onPressed: () => showTemplateDialog(template: template, index: idx),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Vorlage bearbeiten',
                          ),
                          IconButton(
                            onPressed: () async {
                              await addShiftFromTemplate(template, selectedDay);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Vorlage "${template.name}" auf ${DateFormat('dd.MM.yyyy').format(selectedDay)} angewendet.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.playlist_add_check_circle_outlined),
                            tooltip: 'Auf ausgewählten Tag anwenden',
                          ),
                          IconButton(
                            onPressed: () async {
                              setState(() {
                                shiftTemplates.removeAt(idx);
                              });
                              await persistState();
                            },
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Vorlage löschen',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showShiftDialog(BuildContext context, DateTime day) async {
    final startController = TextEditingController();
    final endController = TextEditingController();
    ShiftTemplate? selectedTemplate;

    final result = await showDialog<WorkSession>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Schicht eintragen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<ShiftTemplate>(
                    value: selectedTemplate,
                    hint: const Text('Vorlage wählen'),
                    items: shiftTemplates
                        .map((template) => DropdownMenuItem(
                              value: template,
                              child: Text(template.name),
                            ))
                        .toList(),
                    onChanged: (template) {
                      setState(() {
                        selectedTemplate = template;
                        if (template != null) {
                          startController.text = formatTimeOfDay(template.start);
                          endController.text = formatTimeOfDay(template.end);
                        }
                      });
                    },
                  ),
                  TextField(
                    controller: startController,
                    decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                    keyboardType: TextInputType.datetime,
                  ),
                  TextField(
                    controller: endController,
                    decoration: const InputDecoration(labelText: 'Ende (HH:mm)'),
                    keyboardType: TextInputType.datetime,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final startTime = parseTimeInput(startController.text);
                    final endTime = parseTimeInput(endController.text);
                    if (startTime != null && endTime != null) {
                      final start = DateTime(
                        day.year,
                        day.month,
                        day.day,
                        startTime.hour,
                        startTime.minute,
                      );
                      var end = DateTime(
                        day.year,
                        day.month,
                        day.day,
                        endTime.hour,
                        endTime.minute,
                      );
                      if (!end.isAfter(start)) {
                        end = end.add(const Duration(days: 1));
                      }
                      Navigator.pop(context, WorkSession(start: start, end: end));
                    }
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        sessions.insert(0, result);
        dayTypes[dayKey(day)] = DayType.worked;
      });
      await persistState();
      await syncWidgetData();
    }
  }

  Widget buildStatsTab() {
    final stats = buildStatsData();
    final weeklyBalances = buildWeeklyBalances(DateTime.now());
    const weekdayLabels = <int, String>{
      DateTime.monday: 'Mo',
      DateTime.tuesday: 'Di',
      DateTime.wednesday: 'Mi',
      DateTime.thursday: 'Do',
      DateTime.friday: 'Fr',
      DateTime.saturday: 'Sa',
      DateTime.sunday: 'So',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Statistiken', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Durchschnittlicher Arbeitstag: ${formatDuration(stats.averageWorkDay)}'),
                Text('Laengster Arbeitstag: ${formatDuration(stats.longestDay)}'),
                Text(
                  stats.monthOvertime.isNegative
                      ? 'Minusstunden im Monat: ${formatDuration(stats.monthOvertime)}'
                      : 'Ueberstunden im Monat: ${formatDuration(stats.monthOvertime)}',
                  style: TextStyle(
                    color: colorForBalance(stats.monthOvertime, context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: buildWeeklyBalanceChart(context, weeklyBalances),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arbeitszeit nach Wochentag',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...weekdayLabels.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.value),
                        Text(formatDuration(stats.byWeekday[entry.key] ?? Duration.zero)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Monatliche Sollstunden'),
                subtitle: Text('${settings.monthlyTargetHours.toStringAsFixed(1)} h'),
                trailing: const Icon(Icons.chevron_right),
                onTap: editMonthlyTargetHours,
              ),
              SwitchListTile(
                title: const Text('Erinnerung: Arbeitszeit vergessen?'),
                value: settings.reminderWorkForgotten,
                onChanged: (value) async {
                  setState(() {
                    settings = settings.copyWith(reminderWorkForgotten: value);
                  });
                  await persistState();
                },
              ),
              SwitchListTile(
                title: const Text('Erinnerung: Pause vergessen?'),
                value: settings.reminderBreakForgotten,
                onChanged: (value) async {
                  setState(() {
                    settings = settings.copyWith(reminderBreakForgotten: value);
                  });
                  await persistState();
                },
              ),
              SwitchListTile(
                title: const Text('Erinnerung: Feierabend?'),
                value: settings.reminderEndOfDay,
                onChanged: (value) async {
                  setState(() {
                    settings = settings.copyWith(reminderEndOfDay: value);
                  });
                  await persistState();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Export', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showExportSnackBar(exportPdf),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('PDF Monatsbericht'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showExportSnackBar(exportCsv),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('CSV Export'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Offline First: Alle Daten bleiben lokal auf dem Geraet. Keine Cloud, kein Account.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = [
      buildOverviewTab(),
      buildCalendarTab(),
      buildStatsTab(),
      buildSettingsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbeitszeit'),
      ),
      body: tabs[currentTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (index) {
          setState(() {
            currentTab = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timelapse), label: 'Heute'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Kalender'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Einstellungen'),
        ],
      ),
    );
  }
}
