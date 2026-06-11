import 'package:arbeitszeit/core/day_type.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/work_session.dart';
import 'package:arbeitszeit/data/repositories/shared_preferences_repository.dart';
import 'package:arbeitszeit/utils/date_time_utils.dart';
import 'package:home_widget/home_widget.dart';

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri == null) {
	return;
  }

  final repository = SharedPreferencesRepository();
  final action = uri.host.isNotEmpty ? uri.host : uri.path.replaceFirst('/', '');
  final now = DateTime.now();
  final activeSession = await repository.loadActiveWorkSession();
  final widgetSessions = await repository.loadWidgetSessionCache();
  final widgetPlannedShifts = await repository.loadWidgetPlannedShiftCache();
  final dayTypes = await repository.loadDayTypes();
  final pendingSessions = await repository.loadPendingBackgroundSessions();

  var current = activeSession;
  final updatedDayTypes = Map<String, DayType>.from(dayTypes);
  final updatedPendingSessions = List<WorkSession>.from(pendingSessions);

  switch (action) {
	case 'start':
	  if (current.activeStart == null) {
		current = current.copyWith(
		  activeStart: now,
		  clearPauseStart: true,
		  currentSessionPaused: Duration.zero,
		);
	  }
	  break;
	case 'stop':
	  if (current.activeStart != null) {
		final startedAt = current.activeStart!;
		final pausedDuration = current.currentSessionPaused +
			(current.pauseStart == null
				? Duration.zero
				: now.difference(current.pauseStart!));
		updatedPendingSessions.add(
		  WorkSession(
			start: startedAt,
			end: now,
			pausedDuration: pausedDuration,
		  ),
		);
		updatedDayTypes[dayKey(startedAt)] = DayType.worked;
		current = current.copyWith(
		  clearActiveStart: true,
		  clearPauseStart: true,
		  currentSessionPaused: Duration.zero,
		);
	  }
	  break;
	case 'pause':
	  if (current.activeStart != null && current.pauseStart == null) {
		current = current.copyWith(pauseStart: now);
	  }
	  break;
	case 'resume':
	  if (current.activeStart != null && current.pauseStart != null) {
		current = current.copyWith(
		  clearPauseStart: true,
		  currentSessionPaused:
			  current.currentSessionPaused + now.difference(current.pauseStart!),
		);
	  }
	  break;
  }

  await repository.saveActiveWorkSession(current);
  await repository.saveDayTypes(updatedDayTypes);
  await repository.savePendingBackgroundSessions(updatedPendingSessions);

  await _syncWidgetData(
	repository: repository,
	now: now,
	currentActiveStart: current.activeStart,
	currentPauseStart: current.pauseStart,
	currentPaused: current.currentSessionPaused,
	sessions: [...widgetSessions, ...updatedPendingSessions],
	plannedShifts: widgetPlannedShifts,
	dayTypes: updatedDayTypes,
  );
}

Future<void> _syncWidgetData({
  required SharedPreferencesRepository repository,
  required DateTime now,
  required DateTime? currentActiveStart,
  required DateTime? currentPauseStart,
  required Duration currentPaused,
  required List<WorkSession> sessions,
  required List<PlannedShift> plannedShifts,
  required Map<String, DayType> dayTypes,
}) async {
  final isWorking = currentActiveStart != null;
  final isPausedNow = currentActiveStart != null && currentPauseStart != null;
  final todayDate = DateTime(now.year, now.month, now.day);
  final todayKey = dayKey(todayDate);

  Duration today = Duration.zero;
  if (currentActiveStart != null && isSameDay(currentActiveStart, todayDate)) {
	final span = now.difference(currentActiveStart);
	final ongoingPause = currentPauseStart != null
		? now.difference(currentPauseStart)
		: Duration.zero;
	today = span - currentPaused - ongoingPause;
  }

  for (final session in sessions) {
	if (isSameDay(session.start, todayDate)) {
	  today += session.duration;
	}
  }

  Duration todayTarget = Duration.zero;
  for (final shift in plannedShifts) {
	if (dayKey(shift.day) == todayKey) {
	  todayTarget = shift.duration;
	  break;
	}
  }

  if (todayTarget == Duration.zero && today > Duration.zero) {
	var dailyTargetHours = 8.0;
	try {
	  final settings = await repository.loadAppSettings();
	  dailyTargetHours = settings.dailyTargetHours;
	} catch (_) {}

	var isTargetDay =
		now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;
	final type = dayTypes[todayKey];
	if (type == DayType.free || type == DayType.vacation || type == DayType.sick) {
	  isTargetDay = false;
	}

	if (isTargetDay) {
	  todayTarget = Duration(minutes: (dailyTargetHours * 60).round());
	}
  }

  final hasTodayPlan = todayTarget > Duration.zero;
  final todayBalance = hasTodayPlan ? today - todayTarget : Duration.zero;
  final remainingToday = hasTodayPlan ? todayTarget - today : Duration.zero;

  await HomeWidget.saveWidgetData<bool>('is_working', isWorking);
  await HomeWidget.saveWidgetData<bool>('is_paused', isPausedNow);
  await HomeWidget.saveWidgetData<String>('today_duration', formatDuration(today));
  await HomeWidget.saveWidgetData<String>(
	'remaining_duration',
	formatDuration(remainingToday),
  );
  await HomeWidget.saveWidgetData<String>(
	'today_balance',
	formatDuration(todayBalance),
  );
  await HomeWidget.saveWidgetData<String?>(
	'active_start_millis',
	currentActiveStart?.millisecondsSinceEpoch.toString(),
  );
  await HomeWidget.updateWidget(
	name: 'ArbeitszeitWidgetProvider',
	iOSName: 'ArbeitszeitWidget',
  );
}
