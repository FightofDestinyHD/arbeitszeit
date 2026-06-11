import 'package:arbeitszeit/data/models/planned_shift.dart';
import 'package:arbeitszeit/data/models/work_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class WorkTimeDatabase {
  WorkTimeDatabase({DatabaseFactory? databaseFactory})
	: _databaseFactory = databaseFactory;

  static const _databaseName = 'work_time.db';
  static const _databaseVersion = 1;
  static const workSessionsTable = 'work_sessions';
  static const plannedShiftsTable = 'planned_shifts';

  final DatabaseFactory? _databaseFactory;
  Database? _database;

  Future<Database> get database async {
	if (_database != null) {
	  return _database!;
	}

	final factory = _databaseFactory ?? databaseFactory;
	final databasesPath = await factory.getDatabasesPath();
	final path = p.join(databasesPath, _databaseName);
	_database = await factory.openDatabase(
	  path,
	  options: OpenDatabaseOptions(
		version: _databaseVersion,
		onCreate: (db, version) async {
		  await db.execute('''
			CREATE TABLE $workSessionsTable (
			  id INTEGER PRIMARY KEY AUTOINCREMENT,
			  start_millis INTEGER NOT NULL,
			  end_millis INTEGER NOT NULL,
			  paused_seconds INTEGER NOT NULL DEFAULT 0
			)
		  ''');
		  await db.execute('''
			CREATE TABLE $plannedShiftsTable (
			  day_key TEXT PRIMARY KEY,
			  day_millis INTEGER NOT NULL,
			  start_millis INTEGER NOT NULL,
			  end_millis INTEGER NOT NULL,
			  name TEXT NOT NULL,
			  color_value INTEGER NOT NULL,
			  paused_seconds INTEGER NOT NULL DEFAULT 0
			)
		  ''');
		},
	  ),
	);
	return _database!;
  }

  Future<List<WorkSession>> getWorkSessions() async {
	final db = await database;
	final rows = await db.query(
	  workSessionsTable,
	  orderBy: 'start_millis DESC',
	);
	return rows.map(_workSessionFromRow).toList();
  }

  Future<void> replaceWorkSessions(List<WorkSession> sessions) async {
	final db = await database;
	await db.transaction((txn) async {
	  await txn.delete(workSessionsTable);
	  for (final session in sessions) {
		await txn.insert(workSessionsTable, _workSessionToRow(session));
	  }
	});
  }

  Future<void> insertWorkSession(WorkSession session) async {
	final db = await database;
	await db.insert(workSessionsTable, _workSessionToRow(session));
  }

  Future<void> deleteWorkSession(WorkSession session) async {
	final db = await database;
	await db.delete(
	  workSessionsTable,
	  where: 'start_millis = ? AND end_millis = ? AND paused_seconds = ?',
	  whereArgs: [
		session.start.millisecondsSinceEpoch,
		session.end.millisecondsSinceEpoch,
		session.pausedDuration.inSeconds,
	  ],
	);
  }

  Future<void> deleteWorkSessionsForDay(DateTime day) async {
	final db = await database;
	final start = DateTime(day.year, day.month, day.day);
	final end = start.add(const Duration(days: 1));
	await db.delete(
	  workSessionsTable,
	  where: 'start_millis >= ? AND start_millis < ?',
	  whereArgs: [
		start.millisecondsSinceEpoch,
		end.millisecondsSinceEpoch,
	  ],
	);
  }

  Future<List<PlannedShift>> getPlannedShifts() async {
	final db = await database;
	final rows = await db.query(
	  plannedShiftsTable,
	  orderBy: 'day_millis ASC',
	);
	return rows.map(_plannedShiftFromRow).toList();
  }

  Future<void> replacePlannedShifts(List<PlannedShift> shifts) async {
	final db = await database;
	await db.transaction((txn) async {
	  await txn.delete(plannedShiftsTable);
	  for (final shift in shifts) {
		await txn.insert(
		  plannedShiftsTable,
		  _plannedShiftToRow(shift),
		  conflictAlgorithm: ConflictAlgorithm.replace,
		);
	  }
	});
  }

  Future<void> upsertPlannedShift(PlannedShift shift) async {
	final db = await database;
	await db.insert(
	  plannedShiftsTable,
	  _plannedShiftToRow(shift),
	  conflictAlgorithm: ConflictAlgorithm.replace,
	);
  }

  Future<void> deletePlannedShiftForDay(DateTime day) async {
	final db = await database;
	final normalized = DateTime(day.year, day.month, day.day);
	await db.delete(
	  plannedShiftsTable,
	  where: 'day_key = ?',
	  whereArgs: [_dayKey(normalized)],
	);
  }

  Map<String, Object?> _workSessionToRow(WorkSession session) {
	return {
	  'start_millis': session.start.millisecondsSinceEpoch,
	  'end_millis': session.end.millisecondsSinceEpoch,
	  'paused_seconds': session.pausedDuration.inSeconds,
	};
  }

  WorkSession _workSessionFromRow(Map<String, Object?> row) {
	return WorkSession(
	  start: DateTime.fromMillisecondsSinceEpoch(row['start_millis']! as int),
	  end: DateTime.fromMillisecondsSinceEpoch(row['end_millis']! as int),
	  pausedDuration: Duration(seconds: row['paused_seconds']! as int),
	);
  }

  Map<String, Object?> _plannedShiftToRow(PlannedShift shift) {
	final normalized = DateTime(shift.day.year, shift.day.month, shift.day.day);
	return {
	  'day_key': _dayKey(normalized),
	  'day_millis': normalized.millisecondsSinceEpoch,
	  'start_millis': shift.start.millisecondsSinceEpoch,
	  'end_millis': shift.end.millisecondsSinceEpoch,
	  'name': shift.name,
	  'color_value': shift.colorValue,
	  'paused_seconds': shift.pausedDuration.inSeconds,
	};
  }

  PlannedShift _plannedShiftFromRow(Map<String, Object?> row) {
	return PlannedShift(
	  day: DateTime.fromMillisecondsSinceEpoch(row['day_millis']! as int),
	  start: DateTime.fromMillisecondsSinceEpoch(row['start_millis']! as int),
	  end: DateTime.fromMillisecondsSinceEpoch(row['end_millis']! as int),
	  name: row['name']! as String,
	  colorValue: row['color_value']! as int,
	  pausedDuration: Duration(seconds: row['paused_seconds']! as int),
	);
  }

  String _dayKey(DateTime day) {
	return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }
}
