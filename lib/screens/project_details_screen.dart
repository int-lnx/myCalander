import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../utils/id_generator.dart';
import '../models/project_evaluation.dart';
import '../models/tracking_value.dart';
import 'project_form_screen.dart';
import 'plan_screen.dart';
import 'plan_form_screen.dart';
import '../models/topic_plan.dart';
import '../models/topic.dart';

String? _sanitizeRRule(String? rule, DateTime startDate) {
  if (rule == null || rule.isEmpty) return rule;
  String sanitized = rule;
  if (sanitized.contains('FREQ=WEEKLY') && !sanitized.contains('BYDAY=')) {
    const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final weekday = startDate.weekday;
    if (weekday >= 1 && weekday <= 7) {
      sanitized = '$sanitized;BYDAY=${days[weekday - 1]}';
    }
  }
  if (sanitized.contains('FREQ=MONTHLY') &&
      !sanitized.contains('BYMONTHDAY=') &&
      !sanitized.contains('BYDAY=')) {
    sanitized = '$sanitized;BYMONTHDAY=${startDate.day}';
  }
  if (sanitized.contains('FREQ=YEARLY') && !sanitized.contains('BYMONTH=')) {
    sanitized =
        '$sanitized;BYMONTH=${startDate.month};BYMONTHDAY=${startDate.day}';
  }
  return sanitized;
}

class AnalizOccurrenceInfo {
  final String title;
  final String tag;
  final String? subTag;
  final DateTime from;
  final DateTime to;
  final double hours;
  final bool isTask;

  AnalizOccurrenceInfo({
    required this.title,
    required this.tag,
    this.subTag,
    required this.from,

