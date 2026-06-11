class ActiveWorkSession {
  const ActiveWorkSession({
	this.activeStart,
	this.pauseStart,
	this.currentSessionPaused = Duration.zero,
  });

  final DateTime? activeStart;
  final DateTime? pauseStart;
  final Duration currentSessionPaused;

  bool get isWorking => activeStart != null;

  bool get isPaused => activeStart != null && pauseStart != null;

  ActiveWorkSession copyWith({
	DateTime? activeStart,
	bool clearActiveStart = false,
	DateTime? pauseStart,
	bool clearPauseStart = false,
	Duration? currentSessionPaused,
  }) {
	return ActiveWorkSession(
	  activeStart: clearActiveStart ? null : activeStart ?? this.activeStart,
	  pauseStart: clearPauseStart ? null : pauseStart ?? this.pauseStart,
	  currentSessionPaused:
		  currentSessionPaused ?? this.currentSessionPaused,
	);
  }
}
