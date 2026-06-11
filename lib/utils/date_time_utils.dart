import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat calendarDateKeyFormat = DateFormat('yyyy-MM-dd');

String calendarDayKey(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

String dayKey(DateTime day) {
  return calendarDateKeyFormat.format(DateTime(day.year, day.month, day.day));
}

bool calendarSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool isSameDay(DateTime a, DateTime b) {
  return calendarSameDay(a, b);
}

String formatDuration(Duration duration) {
  final negative = duration.isNegative;
  final absDuration = negative ? duration.abs() : duration;
  final hours = absDuration.inHours;
  final minutes = absDuration.inMinutes.remainder(60);
  final base = '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  return negative ? '-$base' : base;
}

String formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String normalizeTimeText(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[^0-9:]'), '');
  if (cleaned.isEmpty) {
	return '';
  }

  if (cleaned.contains(':')) {
	final idx = cleaned.indexOf(':');
	final left = cleaned.substring(0, idx).replaceAll(':', '');
	final right = cleaned.substring(idx + 1).replaceAll(':', '');
	final hh = left.length > 2 ? left.substring(0, 2) : left;
	final mm = right.length > 2 ? right.substring(0, 2) : right;
	return '$hh:$mm';
  }

  final digits = cleaned;
  if (digits.length <= 2) {
	return digits;
  }
  if (digits.length == 3) {
	return '${digits.substring(0, 1)}:${digits.substring(1)}';
  }
  final limited = digits.substring(0, 4);
  return '${limited.substring(0, 2)}:${limited.substring(2)}';
}

TimeOfDay? parseTimeInput(String input) {
  final normalized = normalizeTimeText(input);
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

void applyNormalizedTimeInput(TextEditingController controller, String raw) {
  final normalized = normalizeTimeText(raw);
  if (controller.text == normalized) {
	return;
  }

  controller.value = TextEditingValue(
	text: normalized,
	selection: TextSelection.collapsed(offset: normalized.length),
  );
}

int isoWeekNumber(DateTime date) {
  final mondayBasedWeekday = date.weekday == DateTime.sunday ? 7 : date.weekday;
  final thursday = date.add(Duration(days: 4 - mondayBasedWeekday));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstMondayBasedWeekday = firstThursday.weekday == DateTime.sunday
	  ? 7
	  : firstThursday.weekday;
  final firstWeekThursday = firstThursday.add(
	Duration(days: 4 - firstMondayBasedWeekday),
  );
  return 1 + thursday.difference(firstWeekThursday).inDays ~/ 7;
}

List<int> weekNumbersForMonth(DateTime month) {
  final firstDay = DateTime(month.year, month.month, 1);
  final startOfGrid = firstDay.subtract(
	Duration(
	  days: firstDay.weekday == DateTime.sunday
		  ? 6
		  : firstDay.weekday - DateTime.monday,
	),
  );

  return List<int>.generate(
	6,
	(index) => isoWeekNumber(startOfGrid.add(Duration(days: index * 7))),
  );
}
