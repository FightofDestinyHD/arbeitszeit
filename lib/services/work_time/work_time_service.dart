import 'dart:async';
import 'dart:io';

import 'package:arbeitszeit/core/day_type.dart';
import 'package:arbeitszeit/data/database/work_time_database.dart';
import 'package:arbeitszeit/data/models/active_work_session.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/shift_template.dart';
import 'package:arbeitszeit/data/models/work_session.dart';
import 'package:arbeitszeit/data/repositories/shared_preferences_repository.dart';
import 'package:arbeitszeit/data/repositories/work_time_repository.dart';
import 'package:arbeitszeit/services/update/update_service.dart';
import 'package:arbeitszeit/services/work_time/work_time_state.dart';
import 'package:arbeitszeit/utils/date_time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

final sharedPreferencesRepositoryProvider = Provider<SharedPreferencesRepository>((
  ref,
) {
  return SharedPreferencesRepository();
});

final workTimeDatabaseProvider = Provider<WorkTimeDatabase>((ref) {
  return WorkTimeDatabase();
});

final workTimeRepositoryProvider = Provider<WorkTimeRepository>((ref) {
  return WorkTimeRepository(
	database: ref.watch(workTimeDatabaseProvider),
	sharedPreferencesRepository: ref.watch(sharedPreferencesRepositoryProvider),
  );
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

final workTimeServiceProvider = NotifierProvider<WorkTimeService, WorkTimeState>(
  WorkTimeService.new,
);

class WorkTimeService extends Notifier<WorkTimeState> {
  SharedPreferencesRepository get _preferencesRepository =>
	  ref.read(sharedPreferencesRepositoryProvider);

  WorkTimeRepository get _workTimeRepository => ref.read(workTimeRepositoryProvider);

  UpdateService get _updateService => ref.read(updateServiceProvider);

  @override
  WorkTimeState build() {
	unawaited(_restoreState());
	return WorkTimeState.initial();
  }

  Future<void> _restoreState() async {
	await _workTimeRepository.migrateLegacyDataIfNeeded();

	var sessions = await _workTimeRepository.loadSessions();
	final plannedShiftList = await _workTimeRepository.loadPlannedShifts();
	final pendingBackgroundSessions =
		await _preferencesRepository.loadPendingBackgroundSessions();
	if (pendingBackgroundSessions.isNotEmpty) {
	  for (final session in pendingBackgroundSessions) {
		await _workTimeRepository.addSession(session);
	  }
	  await _preferencesRepository.clearPendingBackgroundSessions();
	  sessions = await _workTimeRepository.loadSessions();
	}

	final plannedShifts = <String, PlannedShift>{
	  for (final shift in plannedShiftList) dayKey(shift.day): shift,
	};

	final today = DateTime.now();
	final todayNormalized = DateTime(today.year, today.month, today.day);
	final todayKeyValue = dayKey(todayNormalized);
	final placeholderShift = plannedShifts[todayKeyValue];
	final hasFinishedSessionToday = sessions.any(
	  (session) => isSameDay(session.start, todayNormalized),
	);
	if (placeholderShift != null &&
		placeholderShift.name == 'Geplante Schicht' &&
		!hasFinishedSessionToday) {
	  plannedShifts.remove(todayKeyValue);
	  await _workTimeRepository.deletePlannedShiftForDay(todayNormalized);
	}

	final activeWorkSession = await _preferencesRepository.loadActiveWorkSession();
	final settings = await _preferencesRepository.loadAppSettings();
	final dayTypes = await _preferencesRepository.loadDayTypes();
	final shiftTemplates = await _preferencesRepository.loadShiftTemplates();

	var restoredActive = activeWorkSession;
	if (activeWorkSession.pauseStart != null && activeWorkSession.activeStart != null) {
	  final pauseDuration = DateTime.now().difference(activeWorkSession.pauseStart!);
	  if (pauseDuration.inSeconds > 0 && pauseDuration.inSeconds <= 4 * 3600) {
		restoredActive = activeWorkSession.copyWith(
		  clearPauseStart: true,
		  currentSessionPaused:
			  activeWorkSession.currentSessionPaused + pauseDuration,
		);
		await _preferencesRepository.saveActiveWorkSession(restoredActive);
	  }
	}

	state = state.copyWith(
	  loading: false,
	  sessions: sessions,
	  plannedShifts: plannedShifts,
	  activeWorkSession: restoredActive,
	  autoBreakPromptShown: false,
	  settings: settings,
	  dayTypes: dayTypes,
	  shiftTemplates: shiftTemplates,
	);

	await _preferencesRepository.saveWidgetSessionCache(sessions);
	await _preferencesRepository.saveWidgetPlannedShiftCache(plannedShiftList);
	await syncWidgetData();
  }

  Future<void> _persistLocalState() async {
	await _preferencesRepository.saveShiftTemplates(state.shiftTemplates);
	await _preferencesRepository.saveAppSettings(state.settings);
	await _preferencesRepository.saveDayTypes(state.dayTypes);
	await _preferencesRepository.saveActiveWorkSession(state.activeWorkSession);
	await _preferencesRepository.saveWidgetSessionCache(state.sessions);
	await _preferencesRepository.saveWidgetPlannedShiftCache(
	  state.plannedShifts.values.toList(),
	);
  }

  Future<void> startTracking() async {
	state = state.copyWith(
	  activeWorkSession: ActiveWorkSession(activeStart: DateTime.now()),
	  autoBreakPromptShown: false,
	);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> startPause() async {
	if (!state.isWorking || state.isPaused) {
	  return;
	}

	state = state.copyWith(
	  activeWorkSession: state.activeWorkSession.copyWith(pauseStart: DateTime.now()),
	);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> startSuggestedBreak() async {
	if (!state.isWorking) {
	  return;
	}
	if (!state.isPaused) {
	  await startPause();
	}
  }

  void setAutoBreakPromptShown(bool value) {
	state = state.copyWith(autoBreakPromptShown: value);
  }

  Future<void> resumeTracking() async {
	if (!state.isPaused || state.activeWorkSession.pauseStart == null) {
	  return;
	}

	state = state.copyWith(
	  activeWorkSession: state.activeWorkSession.copyWith(
		clearPauseStart: true,
		currentSessionPaused: state.activeWorkSession.currentSessionPaused +
			DateTime.now().difference(state.activeWorkSession.pauseStart!),
	  ),
	);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> stopTracking() async {
	if (!state.isWorking || state.activeWorkSession.activeStart == null) {
	  return;
	}

	final startedAt = state.activeWorkSession.activeStart!;
	final end = DateTime.now();
	final pausedDuration = state.activeWorkSession.currentSessionPaused +
		(state.activeWorkSession.pauseStart == null
			? Duration.zero
			: end.difference(state.activeWorkSession.pauseStart!));
	final session = WorkSession(
	  start: startedAt,
	  end: end,
	  pausedDuration: pausedDuration,
	);

	await _workTimeRepository.addSession(session);
	final sessions = [session, ...state.sessions];
	final dayTypes = Map<String, DayType>.from(state.dayTypes)
	  ..[dayKey(startedAt)] = DayType.worked;

	state = state.copyWith(
	  sessions: sessions,
	  dayTypes: dayTypes,
	  activeWorkSession: const ActiveWorkSession(),
	  autoBreakPromptShown: false,
	);
	await _persistLocalState();
	await syncWidgetData();
  }

  Duration activeSessionNetDuration({DateTime? now}) {
	final started = state.activeWorkSession.activeStart;
	if (started == null) {
	  return Duration.zero;
	}

	final currentNow = now ?? DateTime.now();
	final activeSpan = currentNow.difference(started);
	final ongoingPause = state.activeWorkSession.pauseStart == null
		? Duration.zero
		: currentNow.difference(state.activeWorkSession.pauseStart!);
	return activeSpan - state.activeWorkSession.currentSessionPaused - ongoingPause;
  }

  Duration todayDuration() {
	final now = DateTime.now();
	return countedWorkDurationForDay(DateTime(now.year, now.month, now.day));
  }

  Duration monthDuration(DateTime month, {DateTime? until}) {
	final firstDay = DateTime(month.year, month.month, 1);
	final monthLastDay = DateTime(month.year, month.month + 1, 0);
	final endDay = until == null
		? monthLastDay
		: DateTime(until.year, until.month, until.day).isBefore(monthLastDay)
		? DateTime(until.year, until.month, until.day)
		: monthLastDay;

	var total = Duration.zero;
	for (var day = firstDay; !day.isAfter(endDay); day = day.add(const Duration(days: 1))) {
	  total += countedWorkDurationForDay(day);
	}
	return total;
  }

  Duration monthDurationForOverview(DateTime month, {DateTime? until}) {
	final firstDay = DateTime(month.year, month.month, 1);
	final monthLastDay = DateTime(month.year, month.month + 1, 0);
	final endDay = until == null
		? monthLastDay
		: DateTime(until.year, until.month, until.day).isBefore(monthLastDay)
		? DateTime(until.year, until.month, until.day)
		: monthLastDay;

	var total = Duration.zero;
	for (var day = firstDay; !day.isAfter(endDay); day = day.add(const Duration(days: 1))) {
	  final hasPlannedShift = plannedDurationForDay(day) > Duration.zero;
	  final isActiveWorkday = state.activeWorkSession.activeStart != null &&
		  isSameDay(state.activeWorkSession.activeStart!, day);
	  if (!hasPlannedShift && !isActiveWorkday) {
		continue;
	  }
	  total += countedWorkDurationForDay(day);
	}
	return total;
  }

  Duration monthlyTargetDuration(DateTime month) {
	return Duration(minutes: (state.settings.monthlyTargetHours * 60).round());
  }

  Duration targetPerWorkday(DateTime month) {
	return Duration(minutes: (state.settings.dailyTargetHours * 60).round());
  }

  bool countsAsTargetWorkday(DateTime day) {
	final normalizedDay = DateTime(day.year, day.month, day.day);
	final hasPlannedShift = state.plannedShifts.containsKey(dayKey(normalizedDay));
	final explicitType = state.dayTypes[dayKey(normalizedDay)];

	if (hasPlannedShift) {
	  return true;
	}
	if (explicitType == DayType.free ||
		explicitType == DayType.vacation ||
		explicitType == DayType.sick) {
	  return false;
	}

	return normalizedDay.weekday >= DateTime.monday &&
		normalizedDay.weekday <= DateTime.friday;
  }

  Duration plannedDurationForDay(DateTime day) {
	return state.plannedShifts[dayKey(day)]?.duration ?? Duration.zero;
  }

  Duration targetDurationForDayBalance(DateTime day, {required Duration worked}) {
	final planned = plannedDurationForDay(day);
	if (planned > Duration.zero) {
	  return planned;
	}
	if (worked > Duration.zero && countsAsTargetWorkday(day)) {
	  return targetPerWorkday(day);
	}
	return Duration.zero;
  }

  Duration actualDurationForDay(DateTime day) {
	final plannedShift = state.plannedShifts[dayKey(day)];
	var total = state.sessions
		.where((session) => isSameDay(session.start, day))
		.where((session) {
		  if (plannedShift == null) {
			return true;
		  }

		  final sameStart =
			  session.start.year == plannedShift.start.year &&
			  session.start.month == plannedShift.start.month &&
			  session.start.day == plannedShift.start.day &&
			  session.start.hour == plannedShift.start.hour &&
			  session.start.minute == plannedShift.start.minute;
		  final sameEnd =
			  session.end.year == plannedShift.end.year &&
			  session.end.month == plannedShift.end.month &&
			  session.end.day == plannedShift.end.day &&
			  session.end.hour == plannedShift.end.hour &&
			  session.end.minute == plannedShift.end.minute;
		  final samePause = session.pausedDuration == plannedShift.pausedDuration;
		  if (sameStart && sameEnd && samePause) {
			return false;
		  }

		  final looksLikeSamePlannedDuration = session.duration == plannedShift.duration;
		  final startsSameDay = isSameDay(session.start, plannedShift.day);
		  if (startsSameDay &&
			  looksLikeSamePlannedDuration &&
			  session.start.hour == plannedShift.start.hour) {
			return false;
		  }
		  return true;
		})
		.fold(Duration.zero, (sum, session) => sum + session.duration);

	if (state.activeWorkSession.activeStart != null &&
		isSameDay(state.activeWorkSession.activeStart!, day)) {
	  total += activeSessionNetDuration();
	}
	return total;
  }

  Duration countedWorkDurationForDay(DateTime day) {
	final worked = actualDurationForDay(day);
	if (worked <= Duration.zero) {
	  return Duration.zero;
	}
	if (state.plannedShifts.containsKey(dayKey(day))) {
	  return worked;
	}
	if (state.dayTypes[dayKey(day)] == DayType.worked) {
	  return worked;
	}
	if (state.activeWorkSession.activeStart != null &&
		isSameDay(state.activeWorkSession.activeStart!, day)) {
	  return worked;
	}
	return Duration.zero;
  }

  Duration effectiveMonthTargetDuration(DateTime month, {DateTime? until}) {
	final firstDay = DateTime(month.year, month.month, 1);
	final monthLastDay = DateTime(month.year, month.month + 1, 0);
	final endDay = until == null
		? monthLastDay
		: DateTime(until.year, until.month, until.day).isBefore(monthLastDay)
		? DateTime(until.year, until.month, until.day)
		: monthLastDay;

	var total = Duration.zero;
	for (var day = firstDay; !day.isAfter(endDay); day = day.add(const Duration(days: 1))) {
	  total += plannedDurationForDay(day);
	}
	return total;
  }

  Duration legalBreakDeduction(Duration anwesenheit) {
	if (anwesenheit > const Duration(hours: 9)) {
	  return const Duration(minutes: 45);
	}
	if (anwesenheit > const Duration(hours: 6)) {
	  return const Duration(minutes: 30);
	}
	return Duration.zero;
  }

  OverviewData buildOverviewData() {
	final now = DateTime.now();
	final today = DateTime(now.year, now.month, now.day);
	final todayWorked = todayDuration();
	final todayTarget = targetDurationForDayBalance(today, worked: todayWorked);
	final hasTodayPlan = todayTarget > Duration.zero;
	final todayBalance = hasTodayPlan ? todayWorked - todayTarget : Duration.zero;
	final monthWorked = monthDurationForOverview(now, until: today);
	final monthTarget = monthlyTargetDuration(now);
	final monthPlanned = effectiveMonthTargetDuration(now);

	return OverviewData(
	  today: todayWorked,
	  todayTarget: todayTarget,
	  todayBalance: todayBalance,
	  remainingToday: hasTodayPlan ? todayTarget - todayWorked : Duration.zero,
	  isWorking: state.isWorking,
	  monthWorked: monthWorked,
	  monthTarget: monthTarget,
	  monthPlanned: monthPlanned,
	  monthOverUnder: monthWorked - monthTarget,
	  activeSince: state.activeWorkSession.activeStart,
	);
  }

  StatsData buildStatsData() {
	final now = DateTime.now();
	final today = DateTime(now.year, now.month, now.day);
	final byDay = <String, Duration>{};
	for (var day = DateTime(now.year, now.month, 1);
		!day.isAfter(today);
		day = day.add(const Duration(days: 1))) {
	  final worked = countedWorkDurationForDay(day);
	  if (worked > Duration.zero) {
		byDay[dayKey(day)] = worked;
	  }
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

	for (var day = DateTime(now.year, now.month, 1);
		!day.isAfter(today);
		day = day.add(const Duration(days: 1))) {
	  final worked = countedWorkDurationForDay(day);
	  if (worked > Duration.zero) {
		byWeekday[day.weekday] = (byWeekday[day.weekday] ?? Duration.zero) + worked;
	  }
	}

	final monthOvertime =
		monthDurationForOverview(now, until: DateTime(now.year, now.month, now.day)) -
		monthlyTargetDuration(now);

	return StatsData(
	  averageWorkDay: average,
	  longestDay: longest,
	  monthOvertime: monthOvertime,
	  byWeekday: byWeekday,
	);
  }

  List<WeeklyBalance> buildWeeklyBalances(DateTime month) {
	final firstDay = DateTime(month.year, month.month, 1);
	final lastDay = DateTime(month.year, month.month + 1, 0);
	final today = DateTime.now();
	final todayNormalized = DateTime(today.year, today.month, today.day);
	final weeks = <int, Duration>{};

	for (var day = firstDay; !day.isAfter(lastDay); day = day.add(const Duration(days: 1))) {
	  final normalizedDay = DateTime(day.year, day.month, day.day);
	  final weekIndex = ((normalizedDay.day - 1) ~/ 7) + 1;
	  final targetDay = countsAsTargetWorkday(normalizedDay);
	  final isPast = normalizedDay.isBefore(todayNormalized);
	  final planned = plannedDurationForDay(normalizedDay);
	  final worked = countedWorkDurationForDay(normalizedDay);
	  final targetForWorked = targetDurationForDayBalance(normalizedDay, worked: worked);

	  Duration dayBalance = Duration.zero;
	  if (worked > Duration.zero) {
		dayBalance = worked - targetForWorked;
	  } else if (planned > Duration.zero && targetDay && isPast) {
		dayBalance = -planned;
	  }
	  weeks[weekIndex] = (weeks[weekIndex] ?? Duration.zero) + dayBalance;
	}

	return weeks.entries
		.map((entry) => WeeklyBalance(label: 'W${entry.key}', balance: entry.value))
		.toList()
	  ..sort((left, right) => left.label.compareTo(right.label));
  }

  Future<void> syncWidgetData() async {
	final overview = buildOverviewData();
	await HomeWidget.saveWidgetData<String>('today_duration', formatDuration(overview.today));
	await HomeWidget.saveWidgetData<String>(
	  'remaining_duration',
	  formatDuration(overview.remainingToday),
	);
	await HomeWidget.saveWidgetData<String>(
	  'today_balance',
	  formatDuration(overview.todayBalance),
	);
	await HomeWidget.saveWidgetData<String>(
	  'status_text',
	  overview.isWorking ? (state.isPaused ? 'Pause läuft' : 'eingestempelt') : 'ausgestempelt',
	);
	await HomeWidget.saveWidgetData<String>(
	  'month_balance',
	  formatDuration(overview.monthOverUnder),
	);
	await HomeWidget.saveWidgetData<bool>('is_working', overview.isWorking);
	await HomeWidget.saveWidgetData<bool>('is_paused', state.isPaused);
	await HomeWidget.saveWidgetData<String>(
	  'action_label',
	  !state.isWorking ? 'Start' : (state.isPaused ? 'Pause beenden' : 'Pause starten'),
	);
	await HomeWidget.saveWidgetData<String?>(
	  'active_start_millis',
	  overview.activeSince?.millisecondsSinceEpoch.toString(),
	);
	await HomeWidget.saveWidgetData<String?>(
	  'pause_start_millis',
	  state.activeWorkSession.pauseStart?.millisecondsSinceEpoch.toString(),
	);
	await HomeWidget.updateWidget(
	  name: 'ArbeitszeitWidgetProvider',
	  iOSName: 'ArbeitszeitWidget',
	);
  }

  Future<void> setSelectedDayType(DayType type) async {
	final dayTypes = Map<String, DayType>.from(state.dayTypes)
	  ..[dayKey(state.selectedDay)] = type;
	state = state.copyWith(dayTypes: dayTypes);
	await _persistLocalState();
  }

  List<WorkSession> sessionsForDay(DateTime day) {
	final sessions = state.sessions
		.where((session) => isSameDay(session.start, day))
		.toList()
	  ..sort((left, right) => right.start.compareTo(left.start));
	return sessions;
  }

  void syncWorkedDayType(DateTime day) {
	final key = dayKey(day);
	final dayTypes = Map<String, DayType>.from(state.dayTypes);
	final hasPlannedShift = state.plannedShifts.containsKey(key);
	final hasSession = state.sessions.any((session) => isSameDay(session.start, day));
	final hasActiveSession = state.activeWorkSession.activeStart != null &&
		isSameDay(state.activeWorkSession.activeStart!, day);

	if (hasPlannedShift || hasSession || hasActiveSession) {
	  dayTypes[key] = DayType.worked;
	} else if (dayTypes[key] == DayType.worked) {
	  dayTypes.remove(key);
	}
	state = state.copyWith(dayTypes: dayTypes);
  }

  Future<void> deletePlannedShiftForDay(DateTime day) async {
	final key = dayKey(day);
	final plannedShifts = Map<String, PlannedShift>.from(state.plannedShifts)
	  ..remove(key);
	state = state.copyWith(plannedShifts: plannedShifts);
	syncWorkedDayType(day);
	await _workTimeRepository.deletePlannedShiftForDay(day);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> deleteSessionForDay(WorkSession session) async {
	final sessions = List<WorkSession>.from(state.sessions)
	  ..removeWhere(
		(candidate) =>
			candidate.start == session.start &&
			candidate.end == session.end &&
			candidate.pausedDuration == session.pausedDuration,
	  );
	state = state.copyWith(sessions: sessions);
	syncWorkedDayType(session.start);
	await _workTimeRepository.deleteSession(session);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> deleteEntriesForDay(DateTime day) async {
	final key = dayKey(day);
	final plannedShifts = Map<String, PlannedShift>.from(state.plannedShifts)
	  ..remove(key);
	final sessions = List<WorkSession>.from(state.sessions)
	  ..removeWhere((session) => isSameDay(session.start, day));
	state = state.copyWith(plannedShifts: plannedShifts, sessions: sessions);
	syncWorkedDayType(day);
	await _workTimeRepository.deletePlannedShiftForDay(day);
	await _workTimeRepository.deleteSessionsForDay(day);
	await _persistLocalState();
	await syncWidgetData();
  }

  void setCurrentTab(int index) {
	state = state.copyWith(currentTab: index);
  }

  void setSelectedAndFocusedDay(DateTime selected, DateTime focused) {
	state = state.copyWith(selectedDay: selected, focusedDay: focused);
  }

  void setFocusedDay(DateTime focused) {
	state = state.copyWith(focusedDay: focused);
  }

  Duration remainingToday() {
	final now = DateTime.now();
	final today = DateTime(now.year, now.month, now.day);
	final worked = todayDuration();
	final target = targetDurationForDayBalance(today, worked: worked);
	return target - worked;
  }

  DayType effectiveDayType(DateTime day) {
	final key = dayKey(day);
	final stored = state.dayTypes[key];
	if (stored != null) {
	  return stored;
	}
	final hasWork = state.sessions.any((session) => isSameDay(session.start, day));
	if (hasWork) {
	  return DayType.worked;
	}
	return DayType.free;
  }

  void activateTemplateAssignMode(ShiftTemplate template) {
	state = state.copyWith(
	  deleteAssignMode: false,
	  templateAssignMode: true,
	  activeCalendarTemplate: template,
	);
  }

  void activateDeleteAssignMode() {
	state = state.copyWith(
	  deleteAssignMode: true,
	  templateAssignMode: false,
	  clearActiveCalendarTemplate: true,
	);
  }

  void stopTemplateAssignMode() {
	state = state.copyWith(
	  templateAssignMode: false,
	  clearActiveCalendarTemplate: true,
	);
  }

  void stopDeleteAssignMode() {
	state = state.copyWith(deleteAssignMode: false);
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

	final shift = PlannedShift(
	  day: DateTime(day.year, day.month, day.day),
	  start: start,
	  end: end,
	  name: template.name,
	  colorValue: template.colorValue,
	  pausedDuration: legalBreakDeduction(end.difference(start)),
	);
	final plannedShifts = Map<String, PlannedShift>.from(state.plannedShifts)
	  ..[dayKey(day)] = shift;
	state = state.copyWith(plannedShifts: plannedShifts);
	syncWorkedDayType(day);
	await _workTimeRepository.savePlannedShift(shift);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> assignActiveTemplateToDay(DateTime day) async {
	final template = state.activeCalendarTemplate;
	if (!state.templateAssignMode || template == null) {
	  return;
	}
	await addShiftFromTemplate(template, day);
  }

  Future<void> saveTemplate(ShiftTemplate template, {int? index}) async {
	final templates = List<ShiftTemplate>.from(state.shiftTemplates);
	if (index == null) {
	  templates.add(template);
	} else {
	  templates[index] = template;
	}
	state = state.copyWith(shiftTemplates: templates);
	await _persistLocalState();
  }

  Future<void> deleteTemplateAt(int index) async {
	final templates = List<ShiftTemplate>.from(state.shiftTemplates);
	templates.removeAt(index);
	state = state.copyWith(shiftTemplates: templates);
	await _persistLocalState();
  }

  Future<void> savePlannedShift(PlannedShift shift) async {
	final plannedShifts = Map<String, PlannedShift>.from(state.plannedShifts)
	  ..[dayKey(shift.day)] = shift;
	state = state.copyWith(plannedShifts: plannedShifts);
	syncWorkedDayType(shift.day);
	await _workTimeRepository.savePlannedShift(shift);
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> updateMonthlyTargetHours(double value) async {
	state = state.copyWith(settings: state.settings.copyWith(monthlyTargetHours: value));
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> updateDailyTargetHours(double value) async {
	state = state.copyWith(settings: state.settings.copyWith(dailyTargetHours: value));
	await _persistLocalState();
	await syncWidgetData();
  }

  Future<void> updateReminderWorkForgotten(bool value) async {
	state = state.copyWith(
	  settings: state.settings.copyWith(reminderWorkForgotten: value),
	);
	await _persistLocalState();
  }

  Future<void> updateReminderBreakForgotten(bool value) async {
	state = state.copyWith(
	  settings: state.settings.copyWith(reminderBreakForgotten: value),
	);
	await _persistLocalState();
  }

  Future<void> updateReminderEndOfDay(bool value) async {
	state = state.copyWith(
	  settings: state.settings.copyWith(reminderEndOfDay: value),
	);
	await _persistLocalState();
  }

  Future<void> checkForUpdate() async {
	state = state.copyWith(
	  checkingUpdate: true,
	  clearUpdateMessage: true,
	  clearUpdateSource: true,
	);
	try {
	  final result = await _updateService.checkForUpdate();
	  state = state.copyWith(
		checkingUpdate: false,
		updateMessage: result.message,
		availableUpdate: result.availableUpdate,
		clearAvailableUpdate: result.availableUpdate == null,
		updateSource: result.source,
	  );
	} catch (e) {
	  state = state.copyWith(
		checkingUpdate: false,
		clearAvailableUpdate: true,
		updateMessage: 'Update-Pruefung fehlgeschlagen: $e',
	  );
	}
  }

  Future<void> installAvailableUpdate() async {
	final manifest = state.availableUpdate;
	if (manifest == null) {
	  return;
	}

	state = state.copyWith(
	  installingUpdate: true,
	  updateMessage: 'Update wird heruntergeladen...',
	);
	try {
	  final result = await _updateService.installAvailableUpdate(
		manifest,
		onProgress: (message) {
		  state = state.copyWith(updateMessage: message);
		},
	  );
	  state = state.copyWith(
		installingUpdate: false,
		updateMessage: result.message,
	  );
	} catch (e) {
	  state = state.copyWith(
		installingUpdate: false,
		updateMessage:
			'Update-Installation fehlgeschlagen: $e. Nutze "APK im Browser öffnen".',
	  );
	}
  }

  Future<void> openUpdateInBrowser() async {
	final manifest = state.availableUpdate;
	if (manifest == null) {
	  return;
	}
	try {
	  await _updateService.openUpdateInBrowser(manifest);
	} catch (e) {
	  state = state.copyWith(updateMessage: '$e');
	}
  }

  Future<String> exportCsv() async {
	final dir = await getApplicationDocumentsDirectory();
	final month = DateTime.now();
	final fileName =
		'arbeitszeit_${month.year}_${month.month.toString().padLeft(2, '0')}.csv';
	final file = File('${dir.path}/$fileName');

	final buffer = StringBuffer();
	buffer.writeln('Datum,Start,Ende,DauerMinuten');
	for (final session in state.sessions) {
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
}
