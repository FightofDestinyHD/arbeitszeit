import 'package:arbeitszeit/core/day_type.dart';
import 'package:arbeitszeit/data/models/active_work_session.dart';
import 'package:arbeitszeit/data/models/app_settings.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/shift_template.dart';
import 'package:arbeitszeit/data/models/update_manifest.dart';
import 'package:arbeitszeit/data/models/work_session.dart';

class OverviewData {
  const OverviewData({
	required this.today,
	required this.todayTarget,
	required this.todayBalance,
	required this.remainingToday,
	required this.isWorking,
	required this.monthWorked,
	required this.monthTarget,
	required this.monthPlanned,
	required this.monthOverUnder,
	required this.activeSince,
  });

  final Duration today;
  final Duration todayTarget;
  final Duration todayBalance;
  final Duration remainingToday;
  final bool isWorking;
  final Duration monthWorked;
  final Duration monthTarget;
  final Duration monthPlanned;
  final Duration monthOverUnder;
  final DateTime? activeSince;
}

class StatsData {
  const StatsData({
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

class WeeklyBalance {
  const WeeklyBalance({required this.label, required this.balance});

  final String label;
  final Duration balance;
}

class WorkTimeState {
  const WorkTimeState({
	required this.loading,
	required this.shiftTemplates,
	required this.sessions,
	required this.plannedShifts,
	required this.dayTypes,
	required this.activeWorkSession,
	required this.autoBreakPromptShown,
	required this.settings,
	required this.currentTab,
	required this.selectedDay,
	required this.focusedDay,
	required this.checkingUpdate,
	required this.installingUpdate,
	required this.updateMessage,
	required this.availableUpdate,
	required this.updateSource,
	required this.templateAssignMode,
	required this.deleteAssignMode,
	required this.activeCalendarTemplate,
  });

  final bool loading;
  final List<ShiftTemplate> shiftTemplates;
  final List<WorkSession> sessions;
  final Map<String, PlannedShift> plannedShifts;
  final Map<String, DayType> dayTypes;
  final ActiveWorkSession activeWorkSession;
  final bool autoBreakPromptShown;
  final AppSettings settings;
  final int currentTab;
  final DateTime selectedDay;
  final DateTime focusedDay;
  final bool checkingUpdate;
  final bool installingUpdate;
  final String? updateMessage;
  final UpdateManifest? availableUpdate;
  final String? updateSource;
  final bool templateAssignMode;
  final bool deleteAssignMode;
  final ShiftTemplate? activeCalendarTemplate;

  bool get isPaused => activeWorkSession.isPaused;

  bool get isWorking => activeWorkSession.isWorking;

  WorkTimeState copyWith({
	bool? loading,
	List<ShiftTemplate>? shiftTemplates,
	List<WorkSession>? sessions,
	Map<String, PlannedShift>? plannedShifts,
	Map<String, DayType>? dayTypes,
	ActiveWorkSession? activeWorkSession,
	bool? autoBreakPromptShown,
	AppSettings? settings,
	int? currentTab,
	DateTime? selectedDay,
	DateTime? focusedDay,
	bool? checkingUpdate,
	bool? installingUpdate,
	String? updateMessage,
	bool clearUpdateMessage = false,
	UpdateManifest? availableUpdate,
	bool clearAvailableUpdate = false,
	String? updateSource,
	bool clearUpdateSource = false,
	bool? templateAssignMode,
	bool? deleteAssignMode,
	ShiftTemplate? activeCalendarTemplate,
	bool clearActiveCalendarTemplate = false,
  }) {
	return WorkTimeState(
	  loading: loading ?? this.loading,
	  shiftTemplates: shiftTemplates ?? this.shiftTemplates,
	  sessions: sessions ?? this.sessions,
	  plannedShifts: plannedShifts ?? this.plannedShifts,
	  dayTypes: dayTypes ?? this.dayTypes,
	  activeWorkSession: activeWorkSession ?? this.activeWorkSession,
	  autoBreakPromptShown: autoBreakPromptShown ?? this.autoBreakPromptShown,
	  settings: settings ?? this.settings,
	  currentTab: currentTab ?? this.currentTab,
	  selectedDay: selectedDay ?? this.selectedDay,
	  focusedDay: focusedDay ?? this.focusedDay,
	  checkingUpdate: checkingUpdate ?? this.checkingUpdate,
	  installingUpdate: installingUpdate ?? this.installingUpdate,
	  updateMessage: clearUpdateMessage ? null : updateMessage ?? this.updateMessage,
	  availableUpdate: clearAvailableUpdate
		  ? null
		  : availableUpdate ?? this.availableUpdate,
	  updateSource: clearUpdateSource ? null : updateSource ?? this.updateSource,
	  templateAssignMode: templateAssignMode ?? this.templateAssignMode,
	  deleteAssignMode: deleteAssignMode ?? this.deleteAssignMode,
	  activeCalendarTemplate: clearActiveCalendarTemplate
		  ? null
		  : activeCalendarTemplate ?? this.activeCalendarTemplate,
	);
  }

  factory WorkTimeState.initial() {
	final now = DateTime.now();
	return WorkTimeState(
	  loading: true,
	  shiftTemplates: const [],
	  sessions: const [],
	  plannedShifts: const {},
	  dayTypes: const {},
	  activeWorkSession: const ActiveWorkSession(),
	  autoBreakPromptShown: false,
	  settings: AppSettings.defaults,
	  currentTab: 0,
	  selectedDay: now,
	  focusedDay: now,
	  checkingUpdate: false,
	  installingUpdate: false,
	  updateMessage: null,
	  availableUpdate: null,
	  updateSource: null,
	  templateAssignMode: false,
	  deleteAssignMode: false,
	  activeCalendarTemplate: null,
	);
  }
}
