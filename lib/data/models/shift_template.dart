import 'package:flutter/material.dart';

class ShiftTemplate {
  const ShiftTemplate({
	required this.name,
	required this.start,
	required this.end,
	this.colorValue = 0xFFF5207B,
  });

  final String name;
  final TimeOfDay start;
  final TimeOfDay end;
  final int colorValue;

  Map<String, dynamic> toJson() => {
	'name': name,
	'start':
		'${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
	'end':
		'${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
	'color_value': colorValue,
  };

  static ShiftTemplate fromJson(Map<String, dynamic> json) {
	final startParts = (json['start'] as String).split(':');
	final endParts = (json['end'] as String).split(':');
	return ShiftTemplate(
	  name: json['name'] as String,
	  start: TimeOfDay(
		hour: int.parse(startParts[0]),
		minute: int.parse(startParts[1]),
	  ),
	  end: TimeOfDay(
		hour: int.parse(endParts[0]),
		minute: int.parse(endParts[1]),
	  ),
	  colorValue: (json['color_value'] as num?)?.toInt() ?? 0xFFF5207B,
	);
  }
}
