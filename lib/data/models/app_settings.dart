class AppSettings {
  const AppSettings({
	required this.monthlyTargetHours,
	required this.dailyTargetHours,
	required this.reminderWorkForgotten,
	required this.reminderBreakForgotten,
	required this.reminderEndOfDay,
  });

  final double monthlyTargetHours;
  final double dailyTargetHours;
  final bool reminderWorkForgotten;
  final bool reminderBreakForgotten;
  final bool reminderEndOfDay;

  AppSettings copyWith({
	double? monthlyTargetHours,
	double? dailyTargetHours,
	bool? reminderWorkForgotten,
	bool? reminderBreakForgotten,
	bool? reminderEndOfDay,
  }) {
	return AppSettings(
	  monthlyTargetHours: monthlyTargetHours ?? this.monthlyTargetHours,
	  dailyTargetHours: dailyTargetHours ?? this.dailyTargetHours,
	  reminderWorkForgotten:
		  reminderWorkForgotten ?? this.reminderWorkForgotten,
	  reminderBreakForgotten:
		  reminderBreakForgotten ?? this.reminderBreakForgotten,
	  reminderEndOfDay: reminderEndOfDay ?? this.reminderEndOfDay,
	);
  }

  Map<String, dynamic> toJson() {
	return {
	  'monthlyTargetHours': monthlyTargetHours,
	  'dailyTargetHours': dailyTargetHours,
	  'reminderWorkForgotten': reminderWorkForgotten,
	  'reminderBreakForgotten': reminderBreakForgotten,
	  'reminderEndOfDay': reminderEndOfDay,
	};
  }

  static AppSettings fromJson(Map<String, dynamic> json) {
	return AppSettings(
	  monthlyTargetHours:
		  (json['monthlyTargetHours'] as num?)?.toDouble() ?? 160,
	  dailyTargetHours: (json['dailyTargetHours'] as num?)?.toDouble() ?? 8.0,
	  reminderWorkForgotten: json['reminderWorkForgotten'] as bool? ?? true,
	  reminderBreakForgotten: json['reminderBreakForgotten'] as bool? ?? false,
	  reminderEndOfDay: json['reminderEndOfDay'] as bool? ?? true,
	);
  }

  static const defaults = AppSettings(
	monthlyTargetHours: 160,
	dailyTargetHours: 8.0,
	reminderWorkForgotten: true,
	reminderBreakForgotten: false,
	reminderEndOfDay: true,
  );
}
