import 'package:arbeitszeit/core/day_type.dart';
import 'package:arbeitszeit/data/models/calendar_entry_collections.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/work_session.dart';
import 'package:arbeitszeit/utils/date_time_utils.dart';

CalendarEntryCollections removeSessionEntryFromCollections({
  required List<WorkSession> sessions,
  required Map<String, PlannedShift> plannedShifts,
  required Map<String, DayType> dayTypes,
  required WorkSession session,
}) {
  final updatedSessions = List<WorkSession>.from(sessions);
  final updatedPlannedShifts = Map<String, PlannedShift>.from(plannedShifts);
  final updatedDayTypes = Map<String, DayType>.from(dayTypes);
  final key = calendarDayKey(session.start);

  final index = updatedSessions.indexWhere(
	(candidate) =>
		candidate.start == session.start &&
		candidate.end == session.end &&
		candidate.pausedDuration == session.pausedDuration,
  );
  if (index != -1) {
	updatedSessions.removeAt(index);
  }

  final hasPlannedShift = updatedPlannedShifts.containsKey(key);
  final hasSession = updatedSessions.any(
	(candidate) => calendarSameDay(candidate.start, session.start),
  );
  if (!hasPlannedShift && !hasSession && updatedDayTypes[key] == DayType.worked) {
	updatedDayTypes.remove(key);
  }

  return CalendarEntryCollections(
	sessions: updatedSessions,
	plannedShifts: updatedPlannedShifts,
	dayTypes: updatedDayTypes,
  );
}

CalendarEntryCollections removePlannedShiftEntryFromCollections({
  required List<WorkSession> sessions,
  required Map<String, PlannedShift> plannedShifts,
  required Map<String, DayType> dayTypes,
  required DateTime day,
}) {
  final updatedSessions = List<WorkSession>.from(sessions);
  final updatedPlannedShifts = Map<String, PlannedShift>.from(plannedShifts);
  final updatedDayTypes = Map<String, DayType>.from(dayTypes);
  final key = calendarDayKey(day);

  updatedPlannedShifts.remove(key);

  final hasPlannedShift = updatedPlannedShifts.containsKey(key);
  final hasSession = updatedSessions.any(
	(candidate) => calendarSameDay(candidate.start, day),
  );
  if (!hasPlannedShift && !hasSession && updatedDayTypes[key] == DayType.worked) {
	updatedDayTypes.remove(key);
  }

  return CalendarEntryCollections(
	sessions: updatedSessions,
	plannedShifts: updatedPlannedShifts,
	dayTypes: updatedDayTypes,
  );
}
