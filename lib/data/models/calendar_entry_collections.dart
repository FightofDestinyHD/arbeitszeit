import 'package:arbeitszeit/core/day_type.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/work_session.dart';

class CalendarEntryCollections {
  const CalendarEntryCollections({
	required this.sessions,
	required this.plannedShifts,
	required this.dayTypes,
  });

  final List<WorkSession> sessions;
  final Map<String, PlannedShift> plannedShifts;
  final Map<String, DayType> dayTypes;
}
