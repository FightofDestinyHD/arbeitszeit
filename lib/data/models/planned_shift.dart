class PlannedShift {
  const PlannedShift({
	required this.day,
	required this.start,
	required this.end,
	required this.name,
	this.colorValue = 0xFFF5207B,
	this.pausedDuration = Duration.zero,
  });

  final DateTime day;
  final DateTime start;
  final DateTime end;
  final String name;
  final int colorValue;
  final Duration pausedDuration;

  Duration get duration => end.difference(start) - pausedDuration;

  Map<String, dynamic> toJson() {
	return {
	  'day': DateTime(day.year, day.month, day.day).toIso8601String(),
	  'start': start.toIso8601String(),
	  'end': end.toIso8601String(),
	  'name': name,
	  'color_value': colorValue,
	  'paused_seconds': pausedDuration.inSeconds,
	};
  }

  static PlannedShift fromJson(Map<String, dynamic> json) {
	return PlannedShift(
	  day: DateTime.parse(json['day'] as String),
	  start: DateTime.parse(json['start'] as String),
	  end: DateTime.parse(json['end'] as String),
	  name: (json['name'] as String? ?? '').trim(),
	  colorValue: (json['color_value'] as num?)?.toInt() ?? 0xFFF5207B,
	  pausedDuration: Duration(
		seconds: (json['paused_seconds'] as num?)?.toInt() ?? 0,
	  ),
	);
  }
}
