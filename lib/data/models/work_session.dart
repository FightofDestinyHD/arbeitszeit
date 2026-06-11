class WorkSession {
  const WorkSession({
	required this.start,
	required this.end,
	this.pausedDuration = Duration.zero,
  });

  final DateTime start;
  final DateTime end;
  final Duration pausedDuration;

  Duration get duration => end.difference(start) - pausedDuration;

  Map<String, dynamic> toJson() {
	return {
	  'start': start.toIso8601String(),
	  'end': end.toIso8601String(),
	  'paused_seconds': pausedDuration.inSeconds,
	};
  }

  static WorkSession fromJson(Map<String, dynamic> json) {
	return WorkSession(
	  start: DateTime.parse(json['start'] as String),
	  end: DateTime.parse(json['end'] as String),
	  pausedDuration: Duration(
		seconds: (json['paused_seconds'] as num?)?.toInt() ?? 0,
	  ),
	);
  }
}
