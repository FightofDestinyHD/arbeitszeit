import 'package:arbeitszeit/data/database/work_time_database.dart';
import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/work_session.dart';
import 'package:arbeitszeit/data/repositories/shared_preferences_repository.dart';

class WorkTimeRepository {
  WorkTimeRepository({
	required WorkTimeDatabase database,
	required SharedPreferencesRepository sharedPreferencesRepository,
  }) : _database = database,
	   _sharedPreferencesRepository = sharedPreferencesRepository;

  final WorkTimeDatabase _database;
  final SharedPreferencesRepository _sharedPreferencesRepository;

  Future<void> migrateLegacyDataIfNeeded() async {
	final migrationDone =
		await _sharedPreferencesRepository.isWorkTimeMigrationDone();
	if (migrationDone) {
	  return;
	}

	final legacySessions =
		await _sharedPreferencesRepository.loadLegacyWorkSessions();
	final legacyPlannedShifts =
		await _sharedPreferencesRepository.loadLegacyPlannedShifts();

	if (legacySessions.isNotEmpty) {
	  await _database.replaceWorkSessions(legacySessions);
	}
	if (legacyPlannedShifts.isNotEmpty) {
	  await _database.replacePlannedShifts(legacyPlannedShifts);
	}

	await _sharedPreferencesRepository.clearLegacyWorkTimeData();
	await _sharedPreferencesRepository.markWorkTimeMigrationDone();
  }

  Future<List<WorkSession>> loadSessions() {
	return _database.getWorkSessions();
  }

  Future<void> addSession(WorkSession session) {
	return _database.insertWorkSession(session);
  }

  Future<void> deleteSession(WorkSession session) {
	return _database.deleteWorkSession(session);
  }

  Future<void> deleteSessionsForDay(DateTime day) {
	return _database.deleteWorkSessionsForDay(day);
  }

  Future<List<PlannedShift>> loadPlannedShifts() {
	return _database.getPlannedShifts();
  }

  Future<void> savePlannedShift(PlannedShift shift) {
	return _database.upsertPlannedShift(shift);
  }

  Future<void> deletePlannedShiftForDay(DateTime day) {
	return _database.deletePlannedShiftForDay(day);
  }
}
