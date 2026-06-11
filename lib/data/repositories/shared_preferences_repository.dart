import 'dart:convert';

import 'package:arbeitszeit/core/app_storage_keys.dart';
import 'package:arbeitszeit/core/day_type.dart';
import 'package:arbeitszeit/data/models/active_work_session.dart';
import 'package:arbeitszeit/data/models/app_settings.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/shift_template.dart';
import 'package:arbeitszeit/data/models/work_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesRepository {
  SharedPreferencesRepository({SharedPreferences? preferences})
	: _preferences = preferences;

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
	return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<List<ShiftTemplate>> loadShiftTemplates() async {
	final prefs = await _prefs;
	final raw = prefs.getStringList(AppStorageKeys.shiftTemplates) ?? [];
	return raw
		.map(
		  (entry) => ShiftTemplate.fromJson(
			Map<String, dynamic>.from(jsonDecode(entry) as Map),
		  ),
		)
		.toList();
  }

  Future<void> saveShiftTemplates(List<ShiftTemplate> templates) async {
	final prefs = await _prefs;
	await prefs.setStringList(
	  AppStorageKeys.shiftTemplates,
	  templates.map((template) => jsonEncode(template.toJson())).toList(),
	);
  }

  Future<AppSettings> loadAppSettings() async {
	final prefs = await _prefs;
	final raw = prefs.getString(AppStorageKeys.settings);
	if (raw == null) {
	  return AppSettings.defaults;
	}
	return AppSettings.fromJson(
	  Map<String, dynamic>.from(jsonDecode(raw) as Map),
	);
  }

  Future<void> saveAppSettings(AppSettings settings) async {
	final prefs = await _prefs;
	await prefs.setString(AppStorageKeys.settings, jsonEncode(settings.toJson()));
  }

  Future<Map<String, DayType>> loadDayTypes() async {
	final prefs = await _prefs;
	final raw = prefs.getString(AppStorageKeys.dayTypes);
	if (raw == null) {
	  return <String, DayType>{};
	}

	final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
	return {
	  for (final entry in map.entries)
		entry.key: DayType.values.byName(entry.value as String),
	};
  }

  Future<void> saveDayTypes(Map<String, DayType> dayTypes) async {
	final prefs = await _prefs;
	final payload = {
	  for (final entry in dayTypes.entries) entry.key: entry.value.name,
	};
	await prefs.setString(AppStorageKeys.dayTypes, jsonEncode(payload));
  }

  Future<ActiveWorkSession> loadActiveWorkSession() async {
	final prefs = await _prefs;
	final activeStartRaw = prefs.getString(AppStorageKeys.activeStart);
	final pauseStartRaw = prefs.getString(AppStorageKeys.pauseStart);
	final pausedSeconds =
		prefs.getInt(AppStorageKeys.currentSessionPausedSeconds) ?? 0;

	return ActiveWorkSession(
	  activeStart: activeStartRaw == null ? null : DateTime.parse(activeStartRaw),
	  pauseStart: pauseStartRaw == null ? null : DateTime.parse(pauseStartRaw),
	  currentSessionPaused: Duration(seconds: pausedSeconds),
	);
  }

  Future<void> saveActiveWorkSession(ActiveWorkSession session) async {
	final prefs = await _prefs;
	if (session.activeStart == null) {
	  await prefs.remove(AppStorageKeys.activeStart);
	  await prefs.remove(AppStorageKeys.pauseStart);
	  await prefs.remove(AppStorageKeys.currentSessionPausedSeconds);
	  return;
	}

	await prefs.setString(
	  AppStorageKeys.activeStart,
	  session.activeStart!.toIso8601String(),
	);
	if (session.pauseStart == null) {
	  await prefs.remove(AppStorageKeys.pauseStart);
	} else {
	  await prefs.setString(
		AppStorageKeys.pauseStart,
		session.pauseStart!.toIso8601String(),
	  );
	}
	await prefs.setInt(
	  AppStorageKeys.currentSessionPausedSeconds,
	  session.currentSessionPaused.inSeconds,
	);
  }

  Future<List<WorkSession>> loadLegacyWorkSessions() async {
	final prefs = await _prefs;
	final rawSessions = prefs.getStringList(AppStorageKeys.sessions) ?? [];
	return rawSessions
		.map(
		  (entry) => WorkSession.fromJson(
			Map<String, dynamic>.from(jsonDecode(entry) as Map),
		  ),
		)
		.toList();
  }

  Future<List<PlannedShift>> loadLegacyPlannedShifts() async {
	final prefs = await _prefs;
	final rawShifts = prefs.getStringList(AppStorageKeys.plannedShifts) ?? [];
	return rawShifts
		.map(
		  (entry) => PlannedShift.fromJson(
			Map<String, dynamic>.from(jsonDecode(entry) as Map),
		  ),
		)
		.toList();
  }

  Future<bool> isWorkTimeMigrationDone() async {
	final prefs = await _prefs;
	return prefs.getBool(AppStorageKeys.workTimeMigrationDone) ?? false;
  }

  Future<void> markWorkTimeMigrationDone() async {
	final prefs = await _prefs;
	await prefs.setBool(AppStorageKeys.workTimeMigrationDone, true);
  }

  Future<void> clearLegacyWorkTimeData() async {
	final prefs = await _prefs;
	await prefs.remove(AppStorageKeys.sessions);
	await prefs.remove(AppStorageKeys.plannedShifts);
  }

  Future<List<WorkSession>> loadPendingBackgroundSessions() async {
	final prefs = await _prefs;
	final rawSessions =
		prefs.getStringList(AppStorageKeys.pendingBackgroundSessions) ?? [];
	return rawSessions
		.map(
		  (entry) => WorkSession.fromJson(
			Map<String, dynamic>.from(jsonDecode(entry) as Map),
		  ),
		)
		.toList();
  }

  Future<void> savePendingBackgroundSessions(List<WorkSession> sessions) async {
	final prefs = await _prefs;
	await prefs.setStringList(
	  AppStorageKeys.pendingBackgroundSessions,
	  sessions.map((session) => jsonEncode(session.toJson())).toList(),
	);
  }

  Future<void> clearPendingBackgroundSessions() async {
	final prefs = await _prefs;
	await prefs.remove(AppStorageKeys.pendingBackgroundSessions);
  }

  Future<List<WorkSession>> loadWidgetSessionCache() async {
	final prefs = await _prefs;
	final rawSessions = prefs.getStringList(AppStorageKeys.widgetSessionCache) ?? [];
	return rawSessions
		.map(
		  (entry) => WorkSession.fromJson(
			Map<String, dynamic>.from(jsonDecode(entry) as Map),
		  ),
		)
		.toList();
  }

  Future<void> saveWidgetSessionCache(List<WorkSession> sessions) async {
	final prefs = await _prefs;
	await prefs.setStringList(
	  AppStorageKeys.widgetSessionCache,
	  sessions.map((session) => jsonEncode(session.toJson())).toList(),
	);
  }

  Future<List<PlannedShift>> loadWidgetPlannedShiftCache() async {
	final prefs = await _prefs;
	final rawShifts = prefs.getStringList(AppStorageKeys.widgetPlannedShiftCache) ?? [];
	return rawShifts
		.map(
		  (entry) => PlannedShift.fromJson(
			Map<String, dynamic>.from(jsonDecode(entry) as Map),
		  ),
		)
		.toList();
  }

  Future<void> saveWidgetPlannedShiftCache(List<PlannedShift> shifts) async {
	final prefs = await _prefs;
	await prefs.setStringList(
	  AppStorageKeys.widgetPlannedShiftCache,
	  shifts.map((shift) => jsonEncode(shift.toJson())).toList(),
	);
  }
}
