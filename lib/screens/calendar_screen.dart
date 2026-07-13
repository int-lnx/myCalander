import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/id_generator.dart';
import '../utils/recurrence_helper.dart';
import '../providers/app_state.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/serit.dart';
import '../models/day_note.dart';
import 'day_note_dialog.dart';
import 'event_form_screen.dart';
import 'task_form_screen.dart';
import 'project_form_screen.dart';
import 'all_timeline_screen.dart';
import 'recent_items_screen.dart';
import 'package:my_plan/screens/plan_screen.dart' show PlanScreen;

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

class StripItem {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final Color color;
  final dynamic originalItem;

  StripItem({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.color,
    required this.originalItem,
  });
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late EventDataSource _dataSource;
  List<DateTime> _visibleDates = [];
  bool _showWeekStrips = false;

  final Map<int, Offset> _activePointers = {};
  double _baseTimeIntervalHeight = 60.0;
  double _timeIntervalHeight = 60.0;
  double _initialDistance = 0.0;

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      final pointers = _activePointers.values.toList();
      _initialDistance = (pointers[0] - pointers[1]).distance;
      _baseTimeIntervalHeight = _timeIntervalHeight;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.position;
    }

    if (_activePointers.length == 2 && _initialDistance > 0) {
      final pointers = _activePointers.values.toList();
      final currentDistance = (pointers[0] - pointers[1]).distance;
      final scale = currentDistance / _initialDistance;

      setState(() {
        _timeIntervalHeight = (_baseTimeIntervalHeight * scale).clamp(
          30.0,
          300.0,
        );
      });
    }
  }

  void _handlePointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _initialDistance = 0.0;
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _dataSource = EventDataSource([]);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  void _showUndoSnackBar(String message, VoidCallback? onUndo) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCloseIcon: true,
        closeIconColor: Colors.white70,
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: 'Geri Al',
                textColor: Colors.amber,
                onPressed: onUndo,
              ),
      ),
    );
  }

  dynamic _getOriginalItem(dynamic appointment, AppState appState) {
    String? id;
    if (appointment is Appointment) {
      id = appointment.id as String?;
    } else if (appointment is Event) {
      id = appointment.id;
    } else if (appointment is TaskItem) {
      id = appointment.id;
    } else if (appointment is ProjectEvaluation) {
      return appointment;
    } else if (appointment is DayNote) {
      return appointment;
    }

    if (id != null) {
      if (id.startsWith('daynote_')) {
        final realId = id.substring(8);
        try {
          return appState.dayNotes.firstWhere((n) => n.id == realId);
        } catch (_) {}
      }
      var realId = id;
      if (realId.startsWith('rollover_')) {
        realId = realId.substring(9);
      }
      if (realId.startsWith('occ_')) {
        final lastUnderscore = realId.lastIndexOf('_');
        if (lastUnderscore > 4) {
          realId = realId.substring(4, lastUnderscore);
        }
      }
      try {
        return appState.events.firstWhere(
          (e) => e.id == realId || realId.startsWith(e.id),
        );
      } catch (_) {}
      try {
        return appState.tasks.firstWhere(
          (t) => t.id == realId || realId.startsWith(t.id),
        );
      } catch (_) {}
      try {
        return appState.evaluations.firstWhere((e) => e.id == realId);
      } catch (_) {}
    }
    return appointment;
  }

  Widget? _buildSheetItemSubtitle(dynamic item, AppState appState) {
    final isTask = item is TaskItem;
    final isEvent = item is Event;

    bool isRecurring = false;
    DateTime? displayDate;

    if (isTask) {
      isRecurring =
          (item.recurrenceRule != null && item.recurrenceRule!.isNotEmpty) ||
          (item.parentTaskId != null && item.parentTaskId!.isNotEmpty) ||
          (item.id.contains('_occ_') || item.id.startsWith('occ_'));

      final realId = item.id.startsWith('rollover_')
          ? item.id.substring(9)
          : item.id;
      String parentId = realId;
      if (realId.startsWith('occ_')) {
        final lastUnderscore = realId.lastIndexOf('_');
        if (lastUnderscore > 4) {
          parentId = realId.substring(4, lastUnderscore);
        }
      }
      final updatedTask = appState.tasks.firstWhere(
        (t) => t.id == parentId,
        orElse: () => item,
      );
      if (!isRecurring) {
        isRecurring =
            updatedTask.recurrenceRule != null &&
            updatedTask.recurrenceRule!.isNotEmpty;
      }

      String tempId = item.id;
      if (tempId.startsWith('rollover_')) {
        tempId = tempId.substring(9);
      }
      if (tempId.startsWith('occ_')) {
        final lastUnderscore = tempId.lastIndexOf('_');
        if (lastUnderscore > 4) {
          final timestampStr = tempId.substring(lastUnderscore + 1);
          final timestamp = int.tryParse(timestampStr);
          if (timestamp != null) {
            displayDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          }
        }
      }
      if (displayDate == null && updatedTask.from != null) {
        displayDate = updatedTask.from!;
      }
    } else if (isEvent) {
      isRecurring =
          (item.recurrenceRule != null && item.recurrenceRule!.isNotEmpty) ||
          (item.id.contains('_occ_') || item.id.startsWith('occ_'));
      displayDate = item.from;
    }

    if (displayDate == null) return null;

    final monthsTurkish = [
      'ocak',
      'şubat',
      'mart',
      'nisan',
      'mayıs',
      'haziran',
      'temmuz',
      'ağustos',
      'eylül',
      'ekim',
      'kasım',
      'aralık',
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(
      displayDate.year,
      displayDate.month,
      displayDate.day,
    );
    final diffDays = today.difference(itemDate).inDays;

    String relativeSuffix = '';
    if (diffDays == 1) {
      relativeSuffix = ' (dün)';
    } else if (diffDays > 1) {
      relativeSuffix = ' ($diffDays gün önce)';
    }
    final dateStr =
        '${displayDate.day} ${monthsTurkish[displayDate.month - 1]}$relativeSuffix';

    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRecurring) ...[
            const Icon(Icons.repeat, size: 12, color: Colors.purple),
            const SizedBox(width: 4),
          ],
          Text(
            dateStr,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  List<dynamic> _getShortMonthClones(List<Event> events, List<TaskItem> tasks) {
    if (_visibleDates.isEmpty) return const [];

    final Set<int> visibleMonthsKey = {};
    for (var date in _visibleDates) {
      visibleMonthsKey.add(date.year * 100 + date.month);
    }

    final List<dynamic> clones = [];

    int getMaxDays(int y, int m) {
      if (m == 2) {
        final isLeap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
        return isLeap ? 29 : 28;
      }
      const days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      return days[m];
    }

    bool isMonthMatch(
      String rrule,
      DateTime start,
      int y,
      int m,
      DateTime cloneDate,
    ) {
      final lower = rrule.toLowerCase();
      int interval = 1;
      final intervalMatch = RegExp(r'interval=(\d+)').firstMatch(lower);
      if (intervalMatch != null) {
        interval = int.tryParse(intervalMatch.group(1) ?? '1') ?? 1;
      }

      final untilMatch = RegExp(r'until=(\d{8})').firstMatch(lower);
      if (untilMatch != null) {
        final dateStr = untilMatch.group(1)!;
        final untilDate = DateTime(
          int.parse(dateStr.substring(0, 4)),
          int.parse(dateStr.substring(4, 6)),
          int.parse(dateStr.substring(6, 8)),
          23,
          59,
          59,
        );
        if (cloneDate.isAfter(untilDate)) return false;
      }

      if (lower.contains('freq=monthly')) {
        final diffMonths = (y - start.year) * 12 + (m - start.month);
        if (diffMonths < 0) return false;
        if (diffMonths % interval != 0) return false;
        return true;
      } else if (lower.contains('freq=yearly')) {
        int targetMonth = start.month;
        final byMonthMatch = RegExp(r'bymonth=(\d+)').firstMatch(lower);
        if (byMonthMatch != null) {
          targetMonth =
              int.tryParse(byMonthMatch.group(1) ?? '${start.month}') ??
              start.month;
        }
        if (m != targetMonth) return false;

        final diffYears = y - start.year;
        if (diffYears < 0) return false;
        if (diffYears % interval != 0) return false;
        return true;
      }
      return false;
    }

    void processItem(dynamic item) {
      final String? rrule = item.recurrenceRule;
      if (rrule == null || rrule.isEmpty) return;

      final DateTime start = item.from ?? DateTime.now();
      final lower = rrule.toLowerCase();

      if (!lower.contains('freq=monthly') && !lower.contains('freq=yearly'))
        return;

      int targetDay = start.day;
      final byMonthDayMatch = RegExp(r'bymonthday=([-\d]+)').firstMatch(lower);
      if (byMonthDayMatch != null) {
        final val =
            int.tryParse(byMonthDayMatch.group(1) ?? '${start.day}') ??
            start.day;
        if (val < 0) return;
        targetDay = val;
      }

      if (targetDay < 29) return;

      for (var key in visibleMonthsKey) {
        final y = key ~/ 100;
        final m = key % 100;
        final maxDays = getMaxDays(y, m);

        if (targetDay > maxDays) {
          final cloneDateStart = DateTime(
            y,
            m,
            maxDays,
            start.hour,
            start.minute,
          );

          if (!isMonthMatch(rrule, start, y, m, cloneDateStart)) continue;

          final exceptions = item.recurrenceExceptionDates as List<DateTime>?;
          final isExcluded =
              exceptions?.any(
                (ex) =>
                    ex.year == cloneDateStart.year &&
                    ex.month == cloneDateStart.month &&
                    ex.day == cloneDateStart.day,
              ) ??
              false;
          if (isExcluded) continue;

          if (item is Event) {
            final duration = item.to.difference(item.from);
            clones.add(
              Event(
                id: 'short_occ_${item.id}_${y}_$m',
                title: item.title,
                description: item.description,
                from: cloneDateStart,
                to: cloneDateStart.add(duration),
                isAllDay: item.isAllDay,
                colorValue: item.colorValue,
                tag: item.tag,
                projectId: item.projectId,
                seriesId: item.id,
                recurrenceRule: null,
                recurrenceExceptionDates: null,
              ),
            );
          } else if (item is TaskItem) {
            final duration = item.to != null
                ? item.to!.difference(item.from!)
                : const Duration(hours: 1);
            clones.add(
              TaskItem(
                id: 'short_occ_${item.id}_${y}_$m',
                title: item.title,
                details: item.details,
                isCompleted: item.isCompleted,
                from: cloneDateStart,
                to: cloneDateStart.add(duration),
                isAllDay: item.isAllDay,
                colorValue: item.colorValue,
                tag: item.tag,
                subTag: item.subTag,
                importance: item.importance,
                projectId: item.projectId,
                parentTaskId: item.parentTaskId,
                superTaskId: item.superTaskId,
                isHidden: item.isHidden,
                projectTag: item.projectTag,
                seriesId: item.id,
                recurrenceRule: null,
                recurrenceExceptionDates: null,
              ),
            );
          }
        }
      }
    }

    for (var e in events) {
      processItem(e);
    }
    for (var t in tasks) {
      processItem(t);
    }

    return clones;
  }

  List<dynamic> _getAllDayItemsForDate(DateTime date, AppState appState) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final List<dynamic> result = [];

    // Add all-day events on this day
    for (var e in appState.filteredEvents) {
      if (!e.isAllDay) continue;
      if (e.recurrenceRule == null || e.recurrenceRule!.isEmpty) {
        if (DateTime(e.from.year, e.from.month, e.from.day) == normalizedDate) {
          result.add(e);
        }
      } else {
        try {
          final occurrences = RecurrenceHelper.getOccurrences(
            rrule: e.recurrenceRule!,
            startDate: e.from,
            specificStartDate: e.from.isUtc
                ? normalizedDate.toUtc()
                : normalizedDate.toLocal(),
            specificEndDate: e.from.isUtc
                ? normalizedDate
                      .add(const Duration(days: 1))
                      .subtract(const Duration(milliseconds: 1))
                      .toUtc()
                : normalizedDate
                      .add(const Duration(days: 1))
                      .subtract(const Duration(milliseconds: 1))
                      .toLocal(),
          );
          final hasOccurrenceOnDay = occurrences.any((occ) {
            final occDate = occ.toLocal();
            return occDate.year == normalizedDate.year &&
                occDate.month == normalizedDate.month &&
                occDate.day == normalizedDate.day;
          });
          if (hasOccurrenceOnDay) {
            final occ = occurrences.firstWhere((o) {
              final occDate = o.toLocal();
              return occDate.year == normalizedDate.year &&
                  occDate.month == normalizedDate.month &&
                  occDate.day == normalizedDate.day;
            });
            final duration = e.to.difference(e.from);
            final occEnd = occ.add(duration);
            result.add(
              e.copyWith(
                id: 'occ_${e.id}_${occ.millisecondsSinceEpoch}',
                from: occ,
                to: occEnd,
                clearRecurrenceRule: true,
                clearRecurrenceExceptionDates: true,
              ),
            );
          }
        } catch (_) {}
      }
    }

    // Add all-day tasks on this day
    final List<TaskItem> tasks = appState.filteredTasks
        .where((t) => t.from != null)
        .toList();
    final List<TaskItem> dayTasks = [];

    for (var t in tasks) {
      if (!t.isAllDay) continue;
      if (t.recurrenceRule == null || t.recurrenceRule!.isEmpty) {
        if (DateTime(t.from!.year, t.from!.month, t.from!.day) ==
            normalizedDate) {
          dayTasks.add(t);
        }
      } else {
        try {
          final occurrences = SfCalendar.getRecurrenceDateTimeCollection(
            _sanitizeRRule(t.recurrenceRule, t.from!)!,
            t.from!,
            specificStartDate: t.from!.isUtc
                ? normalizedDate.toUtc()
                : normalizedDate.toLocal(),
            specificEndDate: t.from!.isUtc
                ? normalizedDate
                      .add(const Duration(days: 1))
                      .subtract(const Duration(milliseconds: 1))
                      .toUtc()
                : normalizedDate
                      .add(const Duration(days: 1))
                      .subtract(const Duration(milliseconds: 1))
                      .toLocal(),
          );
          for (var occ in occurrences) {
            final occDate = occ.toLocal();
            if (occDate.year != normalizedDate.year ||
                occDate.month != normalizedDate.month ||
                occDate.day != normalizedDate.day) {
              continue;
            }
            bool isException =
                t.recurrenceExceptionDates?.any(
                  (ex) =>
                      ex.year == occ.year &&
                      ex.month == occ.month &&
                      ex.day == occ.day,
                ) ??
                false;
            if (!isException) {
              final duration = t.to != null
                  ? t.to!.difference(t.from!)
                  : const Duration(hours: 1);
              final occEnd = occ.add(duration);
              dayTasks.add(
                t.copyWith(
                  id: 'occ_${t.id}_${occ.millisecondsSinceEpoch}',
                  from: occ,
                  to: occEnd,
                  parentTaskId: t.id,
                  clearRecurrenceRule: true,
                  clearRecurrenceExceptionDates: true,
                ),
              );
            }
          }
        } catch (_) {}
      }
    }

    // Add rollover tasks if date is today
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (normalizedDate == todayStart) {
      for (var t in tasks) {
        if (!t.isCompleted) {
          if (t.recurrenceRule == null || t.recurrenceRule!.isEmpty) {
            final taskEnd = t.to ?? t.from!;
            final taskEndDate = DateTime(
              taskEnd.year,
              taskEnd.month,
              taskEnd.day,
            );
            if (taskEndDate.isBefore(todayStart)) {
              dayTasks.add(
                TaskItem(
                  id: 'rollover_${t.id}',
                  title: '⚠️ ${t.title}',
                  details: t.details,
                  isCompleted: t.isCompleted,
                  from: todayStart,
                  to: todayStart,
                  isAllDay: true,
                  colorValue: t.colorValue,
                  tag: t.tag,
                  subTag: t.subTag,
                  importance: t.importance,
                  projectId: t.projectId,
                  parentTaskId: t.parentTaskId,
                  superTaskId: t.superTaskId,
                  isHidden: t.isHidden,
                  projectTag: t.projectTag,
                  recurrenceRule: null,
                  recurrenceExceptionDates: null,
                ),
              );
            }
          } else {
            try {
              final occurrences = SfCalendar.getRecurrenceDateTimeCollection(
                _sanitizeRRule(t.recurrenceRule, t.from!)!,
                t.from!,
                specificStartDate: t.from!,
                specificEndDate: todayStart.subtract(
                  const Duration(milliseconds: 1),
                ),
              );
              for (var occ in occurrences) {
                final occDate = occ.toLocal();
                bool isException =
                    t.recurrenceExceptionDates?.any(
                      (ex) =>
                          ex.year == occDate.year &&
                          ex.month == occDate.month &&
                          ex.day == occDate.day,
                    ) ??
                    false;
                if (!isException) {
                  dayTasks.add(
                    TaskItem(
                      id: 'rollover_occ_${t.id}_${occ.millisecondsSinceEpoch}',
                      title: '⚠️ ${t.title}',
                      details: t.details,
                      isCompleted: false,
                      from: todayStart,
                      to: todayStart,
                      isAllDay: true,
                      colorValue: t.colorValue,
                      tag: t.tag,
                      subTag: t.subTag,
                      importance: t.importance,
                      projectId: t.projectId,
                      parentTaskId: t.parentTaskId,
                      superTaskId: t.superTaskId,
                      isHidden: t.isHidden,
                      projectTag: t.projectTag,
                      recurrenceRule: null,
                      recurrenceExceptionDates: null,
                    ),
                  );
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    // Sort tasks chronologically by 'from' date, fallback to createdAt descending
    dayTasks.sort((a, b) {
      if (a.from == null && b.from == null) return b.createdAt.compareTo(a.createdAt);
      if (a.from == null) return 1;
      if (b.from == null) return -1;
      final dateCompare = a.from!.compareTo(b.from!);
      if (dateCompare == 0) {
        return b.createdAt.compareTo(a.createdAt);
      }
      return dateCompare;
    });

    result.addAll(dayTasks);

    // Inject short month clones
    final events = appState.filteredEvents;
    final tasksList = appState.filteredTasks
        .where((t) => t.from != null)
        .toList();
    final clones = _getShortMonthClones(events, tasksList);
    for (var c in clones) {
      if (c.isAllDay) {
        final fromDate = c.from;
        if (DateTime(fromDate.year, fromDate.month, fromDate.day) ==
            normalizedDate) {
          result.add(c);
        }
      }
    }

    if (appState.calendarView == CalendarView.day) {
      final dayEnd = normalizedDate.add(const Duration(days: 1));
      final allStrips = _getActiveStrips(appState);
      
      for (var s in allStrips) {
        if (s.startDate.isBefore(dayEnd) && s.endDate.isAfter(normalizedDate)) {
          if (s.originalItem is Event) {
            final e = s.originalItem as Event;
            result.add(
              Event(
                id: e.id,
                title: e.title,
                description: e.description,
                from: normalizedDate,
                to: normalizedDate.add(const Duration(minutes: 15)),
                isAllDay: true,
                colorValue: e.colorValue,
                recurrenceRule: e.recurrenceRule,
              ),
            );
          } else if (s.originalItem is TaskItem) {
            final t = s.originalItem as TaskItem;
            result.add(
              TaskItem(
                id: t.id,
                title: t.title,
                isCompleted: t.isCompleted,
                from: normalizedDate,
                to: normalizedDate.add(const Duration(minutes: 15)),
                isAllDay: true,
                colorValue: t.colorValue,
                details: t.details,
              ),
            );
          } else if (s.originalItem is Serit) {
            final sr = s.originalItem as Serit;
            result.add(
              Event(
                id: sr.id,
                title: sr.title,
                description: sr.description,
                from: normalizedDate,
                to: normalizedDate.add(const Duration(minutes: 15)),
                isAllDay: true,
                colorValue: sr.colorValue,
              ),
            );
          }
        }
      }
    }

    // Sort all items: first priority is high importance (importance == 2),
    // then chronological order, then creation date descending
    result.sort((a, b) {
      int importanceA = 0;
      if (a is Event) importanceA = a.importance;
      if (a is TaskItem) importanceA = a.importance;

      int importanceB = 0;
      if (b is Event) importanceB = b.importance;
      if (b is TaskItem) importanceB = b.importance;

      // High importance (2) comes first
      if (importanceA != importanceB) {
        return importanceB.compareTo(importanceA);
      }

      // Chronological sort
      DateTime? fromA;
      if (a is Event) fromA = a.from;
      if (a is TaskItem) fromA = a.from;

      DateTime? fromB;
      if (b is Event) fromB = b.from;
      if (b is TaskItem) fromB = b.from;

      if (fromA != null && fromB != null) {
        final dateCompare = fromA.compareTo(fromB);
        if (dateCompare != 0) return dateCompare;
      } else if (fromA == null && fromB != null) {
        return 1;
      } else if (fromB == null && fromA != null) {
        return -1;
      }

      // Fallback: creation date descending (newest first)
      DateTime? createdA;
      if (a is Event) createdA = a.createdAt;
      if (a is TaskItem) createdA = a.createdAt;

      DateTime? createdB;
      if (b is Event) createdB = b.createdAt;
      if (b is TaskItem) createdB = b.createdAt;

      if (createdA != null && createdB != null) {
        return createdB.compareTo(createdA);
      }

      return 0;
    });

    // Evaluations will only be shown inside linked events details.

    return result;
  }

  int _getSortedSlotIndex({
    required dynamic appointment,
    required DateTime actualFrom,
    required DateTime actualTo,
    required AppState appState,
  }) {
    final actualFromLocal = actualFrom.toLocal();
    final actualToLocal = actualTo.toLocal();

    final dayStart = DateTime(
      actualFromLocal.year,
      actualFromLocal.month,
      actualFromLocal.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final List<OccurrenceInfo> occurrences = [];

    // Filter and expand events
    for (var e in appState.filteredEvents) {
      if (e.isAllDay) continue;
      if (e.from.isAtSameMomentAs(e.to)) continue; // Reminder

      if (e.recurrenceRule == null) {
        final eFromLocal = e.from.toLocal();
        final eToLocal = e.to.toLocal();
        if (eFromLocal.isBefore(dayEnd) && eToLocal.isAfter(dayStart)) {
          occurrences.add(
            OccurrenceInfo(
              originalItem: e,
              id: e.id,
              from: eFromLocal,
              to: eToLocal,
            ),
          );
        }
      } else {
        try {
          final dates = SfCalendar.getRecurrenceDateTimeCollection(
            _sanitizeRRule(e.recurrenceRule, e.from)!,
            e.from,
            specificStartDate: e.from,
            specificEndDate: e.from.isUtc ? dayEnd.toUtc() : dayEnd.toLocal(),
          );
          final duration = e.to.difference(e.from);
          for (var date in dates) {
            final dateLocal = date.toLocal();
            if (e.recurrenceExceptionDates != null &&
                e.recurrenceExceptionDates!.any(
                  (d) =>
                      d.toLocal().year == dateLocal.year &&
                      d.toLocal().month == dateLocal.month &&
                      d.toLocal().day == dateLocal.day,
                )) {
              continue;
            }
            final occStart = dateLocal;
            final occEnd = date.add(duration).toLocal();
            // Filter strictly for target day
            if (occStart.isBefore(dayEnd) && occEnd.isAfter(dayStart)) {
              occurrences.add(
                OccurrenceInfo(
                  originalItem: e,
                  id: e.id,
                  from: occStart,
                  to: occEnd,
                ),
              );
            }
          }
        } catch (_) {}
      }
    }

    // Filter and expand tasks
    for (var t in appState.filteredTasks) {
      if (t.isAllDay || t.from == null) continue;
      final tTo = t.to ?? t.from!;
      if (t.from!.isAtSameMomentAs(tTo)) continue; // Reminder

      if (t.recurrenceRule == null) {
        final tFromLocal = t.from!.toLocal();
        final tToLocal = tTo.toLocal();
        if (tFromLocal.isBefore(dayEnd) && tToLocal.isAfter(dayStart)) {
          occurrences.add(
            OccurrenceInfo(
              originalItem: t,
              id: t.id,
              from: tFromLocal,
              to: tToLocal,
            ),
          );
        }
      } else {
        try {
          final dates = SfCalendar.getRecurrenceDateTimeCollection(
            _sanitizeRRule(t.recurrenceRule, t.from!)!,
            t.from!,
            specificStartDate: t.from!,
            specificEndDate: t.from!.isUtc ? dayEnd.toUtc() : dayEnd.toLocal(),
          );
          final duration = tTo.difference(t.from!);
          for (var date in dates) {
            final dateLocal = date.toLocal();
            if (t.recurrenceExceptionDates != null &&
                t.recurrenceExceptionDates!.any(
                  (d) =>
                      d.toLocal().year == dateLocal.year &&
                      d.toLocal().month == dateLocal.month &&
                      d.toLocal().day == dateLocal.day,
                )) {
              continue;
            }
            final occStart = dateLocal;
            final occEnd = date.add(duration).toLocal();
            // Filter strictly for target day
            if (occStart.isBefore(dayEnd) && occEnd.isAfter(dayStart)) {
              occurrences.add(
                OccurrenceInfo(
                  originalItem: t,
                  id: t.id,
                  from: occStart,
                  to: occEnd,
                ),
              );
            }
          }
        } catch (_) {}
      }
    }

    final String currentId;
    if (appointment is Event) {
      currentId = appointment.id;
    } else if (appointment is TaskItem) {
      currentId = appointment.id;
    } else if (appointment is Appointment) {
      currentId = appointment.id?.toString() ?? '';
    } else {
      currentId = '';
    }

    OccurrenceInfo? currentOcc;
    int minDiffMs = 999999999;
    for (var occ in occurrences) {
      final bool isMatch =
          occ.id == currentId ||
          (currentId.isNotEmpty && currentId.startsWith(occ.id)) ||
          (occ.id.isNotEmpty && occ.id.startsWith(currentId));
      if (isMatch) {
        final diff = (occ.from.difference(
          actualFromLocal,
        )).inMilliseconds.abs();
        if (diff < minDiffMs) {
          minDiffMs = diff;
          currentOcc = occ;
        }
      }
    }

    currentOcc ??= OccurrenceInfo(
      originalItem: appointment,
      id: currentId,
      from: actualFromLocal,
      to: actualToLocal,
    );

    final overlapping = occurrences.where((occ) {
      return occ.from.isBefore(currentOcc!.to) &&
          occ.to.isAfter(currentOcc.from);
    }).toList();

    overlapping.sort((a, b) {
      int comp = a.from.compareTo(b.from);
      if (comp != 0) return comp;

      final durA = a.to.difference(a.from);
      final durB = b.to.difference(b.from);
      comp = durB.compareTo(durA);
      if (comp != 0) return comp;

      return a.id.compareTo(b.id);
    });

    int index = overlapping.indexOf(currentOcc);
    return index >= 0 ? index : 0;
  }

  Map<String, int> _getOverlapLayoutInfo({
    required dynamic appointment,
    required DateTime actualFrom,
    required DateTime actualTo,
    required AppState appState,
  }) {
    final actualFromLocal = actualFrom.toLocal();
    final actualToLocal = actualTo.toLocal();

    final dayStart = DateTime(
      actualFromLocal.year,
      actualFromLocal.month,
      actualFromLocal.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final List<OccurrenceInfo> occurrences = [];

    // Filter and expand events
    for (var e in appState.filteredEvents) {
      if (e.isAllDay) continue;
      if (e.from.isAtSameMomentAs(e.to)) continue; // Reminder

      if (e.recurrenceRule == null) {
        final eFromLocal = e.from.toLocal();
        final eToLocal = e.to.toLocal();
        if (eFromLocal.isBefore(dayEnd) && eToLocal.isAfter(dayStart)) {
          occurrences.add(
            OccurrenceInfo(
              originalItem: e,
              id: e.id,
              from: eFromLocal,
              to: eToLocal,
            ),
          );
        }
      } else {
        try {
          final instances = RecurrenceHelper.getOccurrences(
            rrule: e.recurrenceRule!,
            startDate: e.from,
            specificStartDate: e.from.isUtc
                ? dayStart.toUtc()
                : dayStart.toLocal(),
            specificEndDate: e.from.isUtc
                ? dayEnd.subtract(const Duration(milliseconds: 1)).toUtc()
                : dayEnd.subtract(const Duration(milliseconds: 1)).toLocal(),
          );
          final duration = e.to.difference(e.from);
          for (var date in instances) {
            final dateLocal = date.toLocal();
            if (e.recurrenceExceptionDates != null &&
                e.recurrenceExceptionDates!.any(
                  (d) =>
                      d.toLocal().year == dateLocal.year &&
                      d.toLocal().month == dateLocal.month &&
                      d.toLocal().day == dateLocal.day,
                )) {
              continue;
            }
            final occStart = dateLocal;
            final occEnd = dateLocal.add(duration);
            if (occStart.isBefore(dayEnd) && occEnd.isAfter(dayStart)) {
              occurrences.add(
                OccurrenceInfo(
                  originalItem: e,
                  id: e.id,
                  from: occStart,
                  to: occEnd,
                ),
              );
            }
          }
        } catch (_) {}
      }
    }

    // Filter and expand tasks
    for (var t in appState.filteredTasks) {
      if (t.from == null) continue;
      if (t.isAllDay) continue;

      if (t.recurrenceRule == null) {
        final tFromLocal = t.from!.toLocal();
        final tToLocal = (t.to ?? t.from!.add(const Duration(hours: 1))).toLocal();
        if (tFromLocal.isBefore(dayEnd) && tToLocal.isAfter(dayStart)) {
          occurrences.add(
            OccurrenceInfo(
              originalItem: t,
              id: t.id,
              from: tFromLocal,
              to: tToLocal,
            ),
          );
        }
      } else {
        try {
          final instances = RecurrenceHelper.getOccurrences(
            rrule: t.recurrenceRule!,
            startDate: t.from!,
            specificStartDate: t.from!.isUtc
                ? dayStart.toUtc()
                : dayStart.toLocal(),
            specificEndDate: t.from!.isUtc
                ? dayEnd.subtract(const Duration(milliseconds: 1)).toUtc()
                : dayEnd.subtract(const Duration(milliseconds: 1)).toLocal(),
          );
          final duration = (t.to ?? t.from!.add(const Duration(hours: 1)))
              .difference(t.from!);
          for (var date in instances) {
            final dateLocal = date.toLocal();
            if (t.recurrenceExceptionDates != null &&
                t.recurrenceExceptionDates!.any(
                  (d) =>
                      d.toLocal().year == dateLocal.year &&
                      d.toLocal().month == dateLocal.month &&
                      d.toLocal().day == dateLocal.day,
                )) {
              continue;
            }
            final occStart = dateLocal;
            final occEnd = date.add(duration).toLocal();
            if (occStart.isBefore(dayEnd) && occEnd.isAfter(dayStart)) {
              occurrences.add(
                OccurrenceInfo(
                  originalItem: t,
                  id: t.id,
                  from: occStart,
                  to: occEnd,
                ),
              );
            }
          }
        } catch (_) {}
      }
    }

    final String currentId;
    if (appointment is Event) {
      currentId = appointment.id;
    } else if (appointment is TaskItem) {
      currentId = appointment.id;
    } else if (appointment is Appointment) {
      currentId = appointment.id?.toString() ?? '';
    } else {
      currentId = '';
    }

    OccurrenceInfo? currentOcc;
    int minDiffMs = 999999999;
    for (var occ in occurrences) {
      final bool isMatch =
          occ.id == currentId ||
          (currentId.isNotEmpty && currentId.startsWith(occ.id)) ||
          (occ.id.isNotEmpty && occ.id.startsWith(currentId));
      if (isMatch) {
        final diff = (occ.from.difference(
          actualFromLocal,
        )).inMilliseconds.abs();
        if (diff < minDiffMs) {
          minDiffMs = diff;
          currentOcc = occ;
        }
      }
    }

    currentOcc ??= OccurrenceInfo(
      originalItem: appointment,
      id: currentId,
      from: actualFromLocal,
      to: actualToLocal,
    );

    final overlapping = occurrences.where((occ) {
      return occ.from.isBefore(currentOcc!.to) &&
          occ.to.isAfter(currentOcc.from);
    }).toList();

    overlapping.sort((a, b) {
      int comp = a.from.compareTo(b.from);
      if (comp != 0) return comp;

      final durA = a.to.difference(a.from);
      final durB = b.to.difference(b.from);
      comp = durB.compareTo(durA);
      if (comp != 0) return comp;

      return a.id.compareTo(b.id);
    });

    int index = overlapping.indexOf(currentOcc);
    return {
      'index': index >= 0 ? index : 0,
      'total': overlapping.length > 0 ? overlapping.length : 1,
    };
  }

  List<StripItem> _getActiveStrips(AppState appState) {
    final List<StripItem> strips = [];

    // 1. Add Serit models
    for (var s in appState.serits) {
      if (!s.isVisible) continue;
      Color color = Colors.blue;
      if (s.colorValue != 0) {
        color = Color(s.colorValue);
      }
      strips.add(StripItem(
        id: s.id,
        title: s.title,
        startDate: s.startDate,
        endDate: s.endDate,
        color: color,
        originalItem: s,
      ));
    }

    // 2. Add regular Events > 24 hours
    for (var e in appState.filteredEvents) {
      if (e.to.difference(e.from).inMinutes > 1440) {
        Color color = Colors.blue;
        if (e.colorValue != 0) {
          color = Color(e.colorValue);
        }
        strips.add(StripItem(
          id: e.id,
          title: e.title,
          startDate: e.from,
          endDate: e.to,
          color: color,
          originalItem: e,
        ));
      }
    }

    // 3. Add regular Tasks > 24 hours
    for (var t in appState.filteredTasks) {
      if (t.from != null && t.to != null) {
        if (t.to!.difference(t.from!).inMinutes > 1440) {
          Color color = Colors.orange;
          final project = appState.projects.where((p) => p.id == t.projectId).firstOrNull;
          if (project != null) {
            color = Color(project.colorValue);
          }
          strips.add(StripItem(
            id: t.id,
            title: t.title,
            startDate: t.from!,
            endDate: t.to!,
            color: color,
            originalItem: t,
          ));
        }
      }
    }

    // Sort by startDate, then duration descending
    strips.sort((a, b) {
      final comp = a.startDate.compareTo(b.startDate);
      if (comp != 0) return comp;
      final aDur = a.endDate.difference(a.startDate);
      final bDur = b.endDate.difference(b.startDate);
      return bDur.compareTo(aDur);
    });

    return strips;
  }

  Map<String, int> _assignStripSlots(List<StripItem> strips) {
    final Map<String, int> slots = {};
    for (var s in strips) {
      final Set<int> takenSlots = {};
      for (var assigned in slots.entries) {
        final s2 = strips.firstWhere((x) => x.id == assigned.key);
        if (s2.startDate.isBefore(s.endDate) && s2.endDate.isAfter(s.startDate)) {
          takenSlots.add(assigned.value);
        }
      }
      int slot = 0;
      while (takenSlots.contains(slot)) {
        slot++;
      }
      slots[s.id] = slot;
    }
    return slots;
  }

  Widget _buildStripWidget(StripItem s, DateTime date, AppState appState) {
    final bool isStart = s.startDate.year == date.year && s.startDate.month == date.month && s.startDate.day == date.day;
    final bool isEnd = s.endDate.year == date.year && s.endDate.month == date.month && s.endDate.day == date.day;
    final bool showText = isStart || date.weekday == DateTime.monday;

    return Container(
      height: 14,
      margin: const EdgeInsets.symmetric(vertical: 1.0),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.only(
          topLeft: isStart ? const Radius.circular(4) : Radius.zero,
          bottomLeft: isStart ? const Radius.circular(4) : Radius.zero,
          topRight: isEnd ? const Radius.circular(4) : Radius.zero,
          bottomRight: isEnd ? const Radius.circular(4) : Radius.zero,
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: showText
          ? Text(
              s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    if (appState.showPlanView) {
      return const PlanScreen();
    }
    if (appState.showSeritView) {
      return const AllTimelineScreen();
    }
    if (appState.showRecentView) {
      return const RecentItemsScreen();
    }
    final calendarController = appState.calendarController;
    final List<Event> events = appState.filteredEvents;
    final List<TaskItem> tasks = appState.filteredTasks
        .where((t) => t.from != null)
        .toList();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final List<TaskItem> rolloverTasks = [];
    for (var t in tasks) {
      if (!t.isCompleted) {
        if (t.recurrenceRule == null || t.recurrenceRule!.isEmpty) {
          final taskEnd = t.to ?? t.from!;
          final taskEndDate = DateTime(
            taskEnd.year,
            taskEnd.month,
            taskEnd.day,
          );
          if (taskEndDate.isBefore(todayStart)) {
            rolloverTasks.add(
              TaskItem(
                id: 'rollover_${t.id}',
                title: '⚠️ ${t.title}',
                details: t.details,
                isCompleted: t.isCompleted,
                from: todayStart,
                to: todayStart,
                isAllDay: true,
                colorValue: t.colorValue,
                tag: t.tag,
                subTag: t.subTag,
                importance: t.importance,
                projectId: t.projectId,
                parentTaskId: t.parentTaskId,
                superTaskId: t.superTaskId,
                isHidden: t.isHidden,
                projectTag: t.projectTag,
                recurrenceRule: null,
                recurrenceExceptionDates: null,
              ),
            );
          }
        } else {
          try {
            final occurrences = RecurrenceHelper.getOccurrences(
              rrule: t.recurrenceRule!,
              startDate: t.from!,
              specificStartDate: t.from!,
              specificEndDate: todayStart.subtract(
                const Duration(milliseconds: 1),
              ),
            );
            for (var occ in occurrences) {
              final occDate = occ.toLocal();
              bool isException =
                  t.recurrenceExceptionDates?.any(
                    (ex) =>
                        ex.year == occDate.year &&
                        ex.month == occDate.month &&
                        ex.day == occDate.day,
                  ) ??
                  false;
              if (!isException) {
                rolloverTasks.add(
                  TaskItem(
                    id: 'rollover_occ_${t.id}_${occ.millisecondsSinceEpoch}',
                    title: '⚠️ ${t.title}',
                    details: t.details,
                    isCompleted: false,
                    from: todayStart,
                    to: todayStart,
                    isAllDay: true,
                    colorValue: t.colorValue,
                    tag: t.tag,
                    subTag: t.subTag,
                    importance: t.importance,
                    projectId: t.projectId,
                    parentTaskId: t.parentTaskId,
                    superTaskId: t.superTaskId,
                    isHidden: t.isHidden,
                    projectTag: t.projectTag,
                    recurrenceRule: null,
                    recurrenceExceptionDates: null,
                  ),
                );
              }
            }
          } catch (_) {}
        }
      }
    }

    final List<TaskItem> allTasksToRender = [...tasks, ...rolloverTasks];

    double startHour = 0;
    double endHour = 24;

    if (appState.hideEmptyHours) {
      int minHour = 24;
      int maxHour = 0;

      for (var e in events) {
        if (!e.isAllDay) {
          if (e.from.hour < minHour) minHour = e.from.hour;
          if (e.to.hour > maxHour) maxHour = e.to.hour;
        }
      }
      for (var t in allTasksToRender) {
        if (!t.isAllDay && t.from != null) {
          if (t.from!.hour < minHour) minHour = t.from!.hour;
          final tEnd = t.to ?? t.from!;
          if (tEnd.hour > maxHour) maxHour = tEnd.hour;
        }
      }

      if (minHour <= maxHour && minHour != 24) {
        startHour = minHour > 0 ? (minHour - 1).toDouble() : 0;
        endHour = maxHour < 23 ? (maxHour + 2).toDouble() : 24;
      } else {
        startHour = 8;
        endHour = 20;
      }
    }

    final List<dynamic> calendarItems = [];

    // Split timed events into reminders and regular events
    final regularTimedEvents = events
        .where((e) => !e.isAllDay && !e.from.isAtSameMomentAs(e.to))
        .toList();
    final eventReminders = events
        .where((e) => !e.isAllDay && e.from.isAtSameMomentAs(e.to))
        .toList();

    // Split timed tasks into reminders and regular tasks
    final regularTimedTasks = allTasksToRender
        .where(
          (t) =>
              !t.isAllDay &&
              t.from != null &&
              (t.to == null || !t.from!.isAtSameMomentAs(t.to!)),
        )
        .toList();
    final taskReminders = allTasksToRender
        .where(
          (t) =>
              !t.isAllDay &&
              t.from != null &&
              t.to != null &&
              t.from!.isAtSameMomentAs(t.to!),
        )
        .toList();

    calendarItems.addAll(regularTimedEvents);
    calendarItems.addAll(regularTimedTasks);
    calendarItems.addAll(eventReminders);
    calendarItems.addAll(taskReminders);

    // Inject timed clones for short months
    final shortMonthClones = _getShortMonthClones(events, tasks);
    final timedClones = shortMonthClones.where((c) => !c.isAllDay).toList();
    calendarItems.addAll(timedClones);

    if (appState.calendarView == CalendarView.schedule) {
      for (var note in appState.dayNotes) {
        if (note.note.trim().isNotEmpty) {
          calendarItems.add(note);
        }
      }
    }

    // Group and limit all-day items for visible dates
    final List<DateTime> datesToProcess = _visibleDates.isNotEmpty
        ? _visibleDates
        : [DateTime.now()];

    for (var date in datesToProcess) {
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final dayItems = _getAllDayItemsForDate(normalizedDate, appState);

      if (dayItems.length <= 3) {
        calendarItems.addAll(dayItems);
      } else {
        final dayEvents = dayItems.whereType<Event>().toList();
        final dayTasks = dayItems.whereType<TaskItem>().toList();

        int maxToShow = 2;
        final testShown1 = dayItems.take(1).toList();
        int testShownEvents1 = testShown1.whereType<Event>().length;
        int testShownTasks1 = testShown1.whereType<TaskItem>().length;
        bool hasRemainingEvents1 = (dayEvents.length - testShownEvents1) > 0;
        bool hasRemainingTasks1 = (dayTasks.length - testShownTasks1) > 0;

        if (hasRemainingEvents1 && hasRemainingTasks1) {
          maxToShow = 1;
        } else {
          maxToShow = 2;
        }

        final shownItems = dayItems.take(maxToShow).toList();
        calendarItems.addAll(shownItems);

        int shownEvents = shownItems.whereType<Event>().length;
        int shownTasks = shownItems.whereType<TaskItem>().length;

        int remainingEvents = dayEvents.length - shownEvents;
        int remainingTasks = dayTasks.length - shownTasks;

        if (remainingEvents > 0) {
          calendarItems.add(
            Event(
              id: 'dummy_e',
              title: '+$remainingEvents Etkinlik',
              description: '',
              from: normalizedDate,
              to: normalizedDate.add(const Duration(minutes: 15)),
              isAllDay: true,
              colorValue: Colors.blue.shade600.value,
            ),
          );
        }
        if (remainingTasks > 0) {
          calendarItems.add(
            TaskItem(
              id: 'dummy_t',
              title: '+$remainingTasks Görev',
              isCompleted: false,
              from: normalizedDate,
              to: normalizedDate.add(const Duration(minutes: 15)),
              isAllDay: true,
              colorValue: Colors.orange.shade700.value,
            ),
          );
        }
      }
    }

    final isWeek = appState.calendarView == CalendarView.week;
    final isDay = appState.calendarView == CalendarView.day;
    final isDayOrWeek = isDay || isWeek;
    final List<dynamic> finalItems = [];
    for (var item in calendarItems) {
      if (isDayOrWeek) {
        if (item is Event && item.to.difference(item.from).inMinutes > 1440) {
          continue;
        }
        if (item is TaskItem && item.from != null && item.to != null && item.to!.difference(item.from!).inMinutes > 1440) {
          continue;
        }
      }
      finalItems.add(item);
    }

    if (isDay) {
      final displayDate = calendarController.displayDate ?? DateTime.now();
      final dayStart = DateTime(displayDate.year, displayDate.month, displayDate.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      
      for (var serit in appState.serits) {
        if (!serit.isVisible) continue;
        if (serit.startDate.isBefore(dayEnd) && serit.endDate.isAfter(dayStart)) {
          finalItems.add(
            Event(
              id: serit.id,
              title: serit.title,
              description: serit.description,
              from: dayStart,
              to: dayStart.add(const Duration(minutes: 15)),
              isAllDay: true,
              colorValue: serit.colorValue,
            ),
          );
        }
      }
    }

    if (isDayOrWeek) {
      final allStrips = _getActiveStrips(appState);
      for (var date in datesToProcess) {
        final DateTime dateStart = DateTime(date.year, date.month, date.day);
        final DateTime dateEnd = dateStart.add(const Duration(days: 1));
        final hasStripOnDay = allStrips.any((s) => s.startDate.isBefore(dateEnd) && s.endDate.isAfter(dateStart));
        
        if (hasStripOnDay) {
          final hasOtherAllDay = finalItems.any((item) {
            if (item is Event && item.isAllDay && !item.id.startsWith('dummy_')) {
              final itemStart = DateTime(item.from.year, item.from.month, item.from.day);
              return itemStart == dateStart;
            }
            if (item is TaskItem && item.isAllDay && !item.id.startsWith('dummy_')) {
              if (item.from != null) {
                final itemStart = DateTime(item.from!.year, item.from!.month, item.from!.day);
                return itemStart == dateStart;
              }
            }
            return false;
          });
          
          if (!hasOtherAllDay) {
            finalItems.add(
              Event(
                id: 'dummy_all_day_placeholder_${dateStart.millisecondsSinceEpoch}',
                title: '',
                description: '',
                from: dateStart,
                to: dateStart.add(const Duration(minutes: 15)),
                isAllDay: true,
                colorValue: Colors.transparent.value,
              ),
            );
          }
        }
      }
    }

    _dataSource.appState = appState;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _dataSource.appointments = finalItems;
        _dataSource.notifyListeners(
          CalendarDataSourceAction.reset,
          finalItems,
        );
      }
    });

    if (calendarController.view != appState.calendarView) {
      calendarController.view = appState.calendarView;
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          double activeIntervalHeight = _timeIntervalHeight;
          if (appState.fitToScreen) {
            final double totalHours = endHour - startHour;
            final double headerEst =
                105.0 +
                ((appState.calendarView == CalendarView.day ||
                        appState.calendarView == CalendarView.week)
                    ? 38.0
                    : 0.0);
            final double availableHeight = constraints.maxHeight - headerEst;
            if (totalHours > 0) {
              activeIntervalHeight = (availableHeight / totalHours).clamp(
                15.0,
                500.0,
              );
            }
          }

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: (appState.calendarView == CalendarView.day ||
                                appState.calendarView == CalendarView.week)
                            ? 55.0
                            : 0.0,
                      ),
                      child: Listener(
                        onPointerDown: _handlePointerDown,
                        onPointerMove: _handlePointerMove,
                        onPointerUp: _handlePointerUp,
                        onPointerCancel: _handlePointerUp,
                        child: SfCalendar(
                          controller: calendarController,
                          view: appState.calendarView,
                          firstDayOfWeek: appState.firstDayOfWeek,
                          headerHeight: 0,
                          viewHeaderHeight: (appState.calendarView == CalendarView.day ||
                                  appState.calendarView == CalendarView.week)
                              ? 0.0
                              : 55.0,
                        showWeekNumber:
                            appState.calendarView == CalendarView.week,

                        weekNumberStyle: const WeekNumberStyle(
                          textStyle: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: Color(0xFFE3F2FD),
                        ),
                        viewHeaderStyle: const ViewHeaderStyle(
                          dayTextStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          dateTextStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onViewChanged: (ViewChangedDetails details) {
                          _visibleDates = details.visibleDates;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              final state = Provider.of<AppState>(
                                context,
                                listen: false,
                              );
                              if (details.visibleDates.isNotEmpty) {
                                final midDate =
                                    details.visibleDates[details
                                            .visibleDates
                                            .length ~/
                                        2];
                                state.setDisplayDate(midDate);
                              }
                            }
                          });
                        },
                        timeSlotViewSettings: TimeSlotViewSettings(
                          startHour: startHour,
                          endHour: endHour,
                          timeIntervalHeight: activeIntervalHeight,
                          timeRulerSize: 40.0,
                          timeFormat: 'HH:mm',
                        ),

                        onTap: (CalendarTapDetails details) {
                          final appState = Provider.of<AppState>(
                            context,
                            listen: false,
                          );
                          if (appState.isBulkMode) {
                            if (details.targetElement ==
                                    CalendarElement.appointment &&
                                details.appointments!.isNotEmpty) {
                              final rawAppointment =
                                  details.appointments!.first;
                              final appointment = _getOriginalItem(
                                rawAppointment,
                                appState,
                              );
                              if (appointment is Event) {
                                if (appointment.id != 'dummy_t' &&
                                    appointment.id != 'dummy_e' &&
                                    appointment.id != 'dummy_eval') {
                                  DateTime? occurrenceFrom;
                                  if (rawAppointment is Appointment) {
                                    occurrenceFrom = rawAppointment.startTime;
                                  } else {
                                    occurrenceFrom = appointment.from;
                                  }
                                  final String selectionId =
                                      appointment.recurrenceRule != null
                                      ? "${appointment.id}_${occurrenceFrom.millisecondsSinceEpoch}"
                                      : appointment.id;
                                  appState.toggleEventSelection(selectionId);
                                }
                              }
                            }
                            return;
                          }
                          if (details.targetElement ==
                              CalendarElement.appointment) {
                            if (details.appointments == null ||
                                details.appointments!.isEmpty) {
                              return;
                            }
                            final rawAppointment = details.appointments!.first;
                            final appointment = _getOriginalItem(
                              rawAppointment,
                              appState,
                            );
                            if (appointment is DayNote) {
                              DayNoteDialog.show(
                                context,
                                appState,
                                DateTime(
                                  appointment.date.year,
                                  appointment.date.month,
                                  appointment.date.day,
                                ),
                              );
                              return;
                            }
                            bool isAllDay = false;
                            DateTime? date;

                            if (rawAppointment is Appointment) {
                              date = rawAppointment.startTime;
                            } else if (rawAppointment is Event) {
                              date = rawAppointment.from;
                            } else if (rawAppointment is TaskItem) {
                              date = rawAppointment.from;
                            } else if (rawAppointment is ProjectEvaluation) {
                              date = rawAppointment.sessionDate;
                            }

                            if (appointment is Event) {
                              isAllDay = appointment.isAllDay;
                              if (appointment.id == 'dummy_t' ||
                                  appointment.id == 'dummy_e' ||
                                  appointment.id == 'dummy_eval') {
                                final normalizedDate = DateTime(
                                  date!.year,
                                  date.month,
                                  date.day,
                                );
                                _showAllDayItemsSheet(context, normalizedDate);
                                return;
                              }
                            } else if (appointment is TaskItem) {
                              isAllDay = appointment.isAllDay;
                            } else if (appointment is ProjectEvaluation) {
                              isAllDay = true;
                            }

                            if (isAllDay && date != null) {
                              final normalizedDate = DateTime(
                                date.year,
                                date.month,
                                date.day,
                              );
                              _showAllDayItemsSheet(context, normalizedDate);
                            } else {
                              DateTime? occurrenceTime;
                              if (rawAppointment is Appointment) {
                                occurrenceTime = rawAppointment.startTime;
                              }
                              _showItemDetailsDialog(
                                context,
                                appointment,
                                tappedDate: occurrenceTime ?? details.date,
                              );
                            }
                          } else if (appState.calendarView ==
                                  CalendarView.month &&
                              details.targetElement ==
                                  CalendarElement.calendarCell &&
                              details.date != null) {
                            calendarController.displayDate = details.date;
                            appState.setCalendarView(CalendarView.day);
                          } else if ((appState.calendarView == CalendarView.day ||
                                  appState.calendarView == CalendarView.week) &&
                              details.targetElement ==
                                  CalendarElement.calendarCell &&
                              details.date != null) {
                            _showAddSelection(
                              context,
                              initialDate: details.date,
                            );
                          } else if (details.targetElement ==
                              CalendarElement.allDayPanel) {
                            final targetDate =
                                (appState.calendarView == CalendarView.day)
                                ? (calendarController.displayDate ??
                                      details.date ??
                                      DateTime.now())
                                : (details.date ?? DateTime.now());
                            final normalizedDate = DateTime(
                              targetDate.year,
                              targetDate.month,
                              targetDate.day,
                            );
                            _showAllDayItemsSheet(context, normalizedDate);
                          }
                        },
                        dataSource: _dataSource,
                        appointmentBuilder: (context, calendarAppointmentDetails) {
                          if (calendarAppointmentDetails.appointments.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final dynamic rawAppointment =
                              calendarAppointmentDetails.appointments.first;
                          final appState = Provider.of<AppState>(
                            context,
                            listen: false,
                          );
                          final dynamic appointment = _getOriginalItem(
                            rawAppointment,
                            appState,
                          );
                          if (appointment is Event &&
                              appointment.id.startsWith('dummy_all_day_placeholder_')) {
                            return const SizedBox.shrink();
                          }
                          DateTime? occurrenceFrom;
                          if (rawAppointment is Appointment) {
                            occurrenceFrom = rawAppointment.startTime;
                          } else if (appointment is Event) {
                            occurrenceFrom = appointment.from;
                          }
                          final String selectionId =
                              (appointment is Event &&
                                  appointment.recurrenceRule != null &&
                                  occurrenceFrom != null)
                              ? "${appointment.id}_${occurrenceFrom.millisecondsSinceEpoch}"
                              : (appointment is Event ? appointment.id : "");
                          final bool isSelected =
                              appState.isBulkMode &&
                              appState.selectedEventIds.contains(selectionId);

                          Widget wrapWithSelection(
                            Widget card, {
                            required bool isSelected,
                          }) {
                            if (!isSelected) return card;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                card,
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(1),
                                    child: const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          Project? project;
                          if (appointment is Event &&
                              appointment.projectId != null) {
                            try {
                              project = appState.projects.firstWhere(
                                (p) => p.id == appointment.projectId,
                              );
                            } catch (_) {}
                          } else if (appointment is TaskItem &&
                              appointment.projectId != null) {
                            try {
                              project = appState.projects.firstWhere(
                                (p) => p.id == appointment.projectId,
                              );
                            } catch (_) {}
                          }

                          final bool isTask = appointment is TaskItem;
                          final bool isHighImportance =
                              (appointment is Event &&
                                  appointment.importance == 2) ||
                              (appointment is TaskItem &&
                                  appointment.importance == 2);
                          Color bgColor = Colors.blue;
                          String title = '';
                          bool isDummy = false;
                          bool isCompleted = false;
                          bool isReminder = false;

                          DateTime? from;
                          DateTime? to;
                          bool isAllDay = false;

                          if (appointment is Event) {
                            bgColor = Color(appointment.colorValue);
                            title = appointment.title;
                            isAllDay = appointment.isAllDay;
                            if (rawAppointment is Appointment) {
                              from = rawAppointment.startTime;
                              to = rawAppointment.endTime;
                            } else {
                              from = appointment.from;
                              to = appointment.to;
                            }
                            if (appointment.id == 'dummy_t' ||
                                appointment.id == 'dummy_e' ||
                                appointment.id == 'dummy_eval') {
                              isDummy = true;
                              if (appointment.id == 'dummy_eval') {
                                bgColor = Colors.grey.shade300;
                              }
                            } else {
                              isReminder =
                                  !isAllDay && from.isAtSameMomentAs(to);
                              if (to.isBefore(DateTime.now())) {
                                bgColor = bgColor.withValues(alpha: 0.4);
                              }
                            }
                          } else if (appointment is TaskItem) {
                            bgColor = Color(appointment.colorValue);
                            title = appointment.title;
                            final rawId = rawAppointment is Appointment
                                ? rawAppointment.id
                                : null;
                            if (rawId is String &&
                                rawId.startsWith('rollover_')) {
                              title = '⚠️ $title';
                            }
                            isAllDay = appointment.isAllDay;
                            isCompleted = appointment.isCompleted;
                            if (rawAppointment is Appointment) {
                              from = rawAppointment.startTime;
                              to = rawAppointment.endTime;
                            } else {
                              from = appointment.from;
                              to = appointment.to ?? appointment.from;
                            }
                            isReminder =
                                !isAllDay &&
                                from != null &&
                                to != null &&
                                from.isAtSameMomentAs(to);
                            if (appointment.id == 'dummy_t' ||
                                appointment.id == 'dummy_e' ||
                                appointment.id == 'dummy_eval') {
                              isDummy = true;
                            } else if (isCompleted) {
                              bgColor = bgColor.withValues(alpha: 0.4);
                            }
                          } else if (appointment is ProjectEvaluation) {
                            isAllDay = true;
                            from = appointment.sessionDate;
                            to = appointment.sessionDate.add(
                              const Duration(hours: 1),
                            );
                            try {
                              final proj = appState.projects.firstWhere(
                                (p) => p.id == appointment.projectId,
                              );
                              bgColor = appointment.isSkipped
                                  ? Colors.red.shade400
                                  : Color(proj.colorValue);
                              title = appointment.isSkipped
                                  ? '📊 ${proj.title}: Pas'
                                  : '📊 ${proj.title}: %${appointment.score.toStringAsFixed(0)}';
                            } catch (_) {
                              bgColor = Colors.grey.shade400;
                              title = '📊 Değerlendirme';
                            }
                          } else if (appointment is DayNote) {
                            isAllDay = false;
                            from = DateTime(
                              appointment.date.year,
                              appointment.date.month,
                              appointment.date.day,
                              23,
                              59,
                            );
                            to = DateTime(
                              appointment.date.year,
                              appointment.date.month,
                              appointment.date.day,
                              23,
                              59,
                              59,
                            );
                            bgColor = Colors.teal.shade700;
                            title = appointment.note;
                            isReminder = false;
                          }

                          if (title.isEmpty && rawAppointment is Appointment) {
                            title = rawAppointment.subject;
                          }

                          if (!isDummy &&
                              appState.calendarView == CalendarView.schedule &&
                              from != null &&
                              to != null) {
                            if (appointment is DayNote) {
                              title = '📝 Günlük Not  •  $title';
                            } else {
                              final fromStr =
                                  '${from.hour.toString().padLeft(2, '0')}:${from.minute.toString().padLeft(2, '0')}';
                              String timeRange;
                              if (isAllDay) {
                                timeRange = 'Tüm Gün';
                              } else if (isReminder) {
                                timeRange = '$fromStr (Hatırlatıcı)';
                              } else {
                                final toStr =
                                    '${to.hour.toString().padLeft(2, '0')}:${to.minute.toString().padLeft(2, '0')}';
                                timeRange = '$fromStr - $toStr';
                              }
                              title = '$timeRange  •  $title';
                            }
                          }

                          final bool hasProject =
                              (appointment is Event &&
                                  appointment.projectId != null) ||
                              (appointment is TaskItem &&
                                  appointment.projectId != null);

                          bool isEvaluated = false;
                          bool isSkippedEval = false;
                          if (hasProject && from != null) {
                            final normalizedFrom = DateTime(
                              from.year,
                              from.month,
                              from.day,
                            );
                            final String? targetProjectId = appointment is Event
                                ? appointment.projectId
                                : (appointment is TaskItem
                                      ? appointment.projectId
                                      : null);
                            if (targetProjectId != null) {
                              try {
                                final eval = appState.evaluations.firstWhere(
                                  (e) =>
                                      e.projectId == targetProjectId &&
                                      e.sessionDate.year ==
                                          normalizedFrom.year &&
                                      e.sessionDate.month ==
                                          normalizedFrom.month &&
                                      e.sessionDate.day == normalizedFrom.day,
                                );
                                isEvaluated = true;
                                isSkippedEval = eval.isSkipped;
                              } catch (_) {
                                isEvaluated = false;
                                isSkippedEval = false;
                              }
                            }
                          }

                          if (isReminder) {
                            final Color reminderBorderColor = isSelected
                                ? Colors.green.shade600
                                : (hasProject && project != null
                                      ? (isEvaluated
                                            ? (isSkippedEval
                                                  ? Colors.red.shade400
                                                  : Colors.black)
                                            : Color(project.colorValue))
                                      : bgColor);

                            final bool isDayOrWeek =
                                appState.calendarView == CalendarView.day ||
                                appState.calendarView == CalendarView.week;

                            if (isDayOrWeek && from != null) {
                              final bounds = calendarAppointmentDetails.bounds;
                              final double calendarWidth = constraints.maxWidth;
                              final int numDays =
                                  appState.calendarView == CalendarView.week
                                  ? 7
                                  : 1;
                              const double timeRulerWidth = 40.0;
                              final double columnWidth =
                                  (calendarWidth - timeRulerWidth) / numDays;
                              final int dayIndex = numDays == 1
                                  ? 0
                                  : ((from.weekday - appState.firstDayOfWeek) %
                                        7);
                              final double colStart =
                                  timeRulerWidth + dayIndex * columnWidth;
                              final double leftShift = bounds.left - colStart;

                              return OverflowBox(
                                alignment: Alignment.topLeft,
                                maxWidth: columnWidth,
                                minWidth: columnWidth,
                                maxHeight: 24.0,
                                minHeight: 24.0,
                                child: Transform.translate(
                                  offset: Offset(-leftShift, -12.0),
                                  child: wrapWithSelection(
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: 12.0,
                                          child: Container(
                                            height: 1.5,
                                            color: reminderBorderColor,
                                          ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          top: 8.5,
                                          child: Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: reminderBorderColor,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.black,
                                                width: 1.0,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 12,
                                          bottom: 13.5,
                                          right: 4,
                                          child: Align(
                                            alignment: Alignment.bottomLeft,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.85,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: reminderBorderColor,
                                                  fontSize:
                                                      9 *
                                                      appState
                                                          .fontSizeMultiplier,
                                                  fontWeight: FontWeight.w600,
                                                  decoration: isCompleted
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    isSelected: isSelected,
                                  ),
                                ),
                              );
                            }

                            return wrapWithSelection(
                              hasProject
                                  ? CustomPaint(
                                      painter: DashedBorderPainter(
                                        color: reminderBorderColor,
                                        borderRadius: 4,
                                        strokeWidth: isEvaluated ? 1.0 : 1.5,
                                        isSolid: isEvaluated,
                                      ),
                                      child: Container(
                                        alignment: Alignment.topLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                          vertical: 1.5,
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                        child: Text(
                                          title,
                                          style: TextStyle(
                                            color: reminderBorderColor,
                                            fontSize:
                                                9 * appState.fontSizeMultiplier,
                                            fontWeight: FontWeight.normal,
                                            decoration: isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        border: Border(
                                          left: BorderSide(
                                            color: reminderBorderColor,
                                            width: 1.5,
                                          ),
                                          top: BorderSide(
                                            color: reminderBorderColor
                                                .withValues(alpha: 0.2),
                                            width: 0.5,
                                          ),
                                          right: BorderSide(
                                            color: reminderBorderColor
                                                .withValues(alpha: 0.2),
                                            width: 0.5,
                                          ),
                                          bottom: BorderSide(
                                            color: reminderBorderColor
                                                .withValues(alpha: 0.2),
                                            width: 0.5,
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      alignment: Alignment.topLeft,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 1.5,
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                      child: Text(
                                        title,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.green.shade600
                                              : (hasProject && project != null
                                                    ? Color(project.colorValue)
                                                    : bgColor),
                                          fontSize:
                                              9 * appState.fontSizeMultiplier,
                                          fontWeight: FontWeight.normal,
                                          decoration: isCompleted
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                              isSelected: isSelected,
                            );
                          }

                          final isDayOrWeek =
                              appState.calendarView == CalendarView.day ||
                              appState.calendarView == CalendarView.week;
                          if (isDayOrWeek &&
                              !isAllDay &&
                              !isReminder &&
                              !isDummy &&
                              from != null &&
                              to != null) {
                            final bounds = calendarAppointmentDetails.bounds;
                            final double calendarWidth = constraints.maxWidth;
                            final int numDays =
                                appState.calendarView == CalendarView.week
                                ? 7
                                : 1;

                            final double timeRulerWidth = 40.0;
                            // Compute exact day-column width — do NOT subtract scrollbar here;
                            // doing so breaks N and slotIndexSf calculations.
                            final double columnWidth =
                                (calendarWidth - timeRulerWidth) / numDays;

                            // Find N (overlap count) exactly
                            int N = (columnWidth / bounds.width).round();
                            if (N < 1) N = 1;

                            if (bounds.width > 0) {
                              // Get the exact day index (0 to 6) based on the appointment date
                              final int dayIndex = numDays == 1
                                  ? 0
                                  : ((from.weekday - appState.firstDayOfWeek) %
                                        7);

                              // Calculate start of column i
                              final double colStart =
                                  timeRulerWidth + dayIndex * columnWidth;

                              final overlapInfo = _getOverlapLayoutInfo(
                                appointment: appointment,
                                actualFrom: from,
                                actualTo: to,
                                appState: appState,
                              );
                              final int slotIndex = overlapInfo['index']!;
                              final int totalOverlaps = overlapInfo['total']!;

                              final double startRatio = slotIndex / totalOverlaps;
                              double cardLeft = colStart + startRatio * columnWidth;
                              double cardWidth = columnWidth * (1.0 - startRatio);

                              // Add a small right margin (e.g. 2px) to look clean
                              if (cardWidth > 4.0) {
                                cardWidth -= 2.0;
                              }
                              if (cardWidth < 10) cardWidth = 10;

                              // Kaydırma farkı
                              double leftShift = bounds.left - cardLeft;

                              final bool isShortDuration =
                                  appState.expandShortDuration &&
                                  bounds.height < 22.0;
                              final double visualHeight = isShortDuration
                                  ? 18.0
                                  : bounds.height;

                              return OverflowBox(
                                alignment: Alignment.topLeft,
                                maxWidth: cardWidth,
                                minWidth: cardWidth,
                                maxHeight: visualHeight,
                                minHeight: visualHeight,
                                child: Transform.translate(
                                  offset: Offset(-leftShift, 0),
                                  child: wrapWithSelection(
                                    (() {
                                      final Widget c = isTask
                                          ? Container(
                                              decoration: BoxDecoration(
                                                color: bgColor,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border(
                                                  left: BorderSide(
                                                    color: isSelected
                                                        ? Colors.green.shade400
                                                        : (isEvaluated
                                                              ? (isSkippedEval
                                                                    ? Colors
                                                                          .red
                                                                          .shade400
                                                                    : Colors
                                                                          .black)
                                                              : Colors.black),
                                                    width: isSelected
                                                        ? 3.2
                                                        : 2.2,
                                                  ),
                                                  right: BorderSide(
                                                    color: isSelected
                                                        ? Colors.green.shade400
                                                        : (isEvaluated
                                                              ? (isSkippedEval
                                                                    ? Colors
                                                                          .red
                                                                          .shade400
                                                                    : Colors
                                                                          .black)
                                                              : Colors.black),
                                                    width: isSelected
                                                        ? 3.2
                                                        : 2.2,
                                                  ),
                                                ),
                                              ),
                                              alignment: Alignment.topLeft,
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: isShortDuration
                                                    ? 1.0
                                                    : 2.5,
                                              ),
                                              clipBehavior: Clip.hardEdge,
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      maxLines: 15,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      softWrap: true,
                                                      style: TextStyle(
                                                        color: isDummy
                                                            ? Colors.black
                                                            : Colors.white,
                                                        fontSize:
                                                            (isShortDuration
                                                                ? 7.5
                                                                : 9.0) *
                                                            appState
                                                                .fontSizeMultiplier,
                                                        fontWeight: isDummy
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        decoration: isCompleted
                                                            ? TextDecoration
                                                                  .lineThrough
                                                            : null,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : (hasProject
                                                ? CustomPaint(
                                                    painter: DashedBorderPainter(
                                                      color: isSelected
                                                          ? Colors
                                                                .green
                                                                .shade400
                                                          : (isEvaluated
                                                                ? (isSkippedEval
                                                                      ? Colors
                                                                            .red
                                                                            .shade400
                                                                      : Colors
                                                                            .black)
                                                                : (project !=
                                                                          null
                                                                      ? Color(
                                                                          project
                                                                              .colorValue,
                                                                        )
                                                                      : bgColor)),
                                                      borderRadius: 6,
                                                      strokeWidth: isSelected
                                                          ? 3.2
                                                          : (isEvaluated
                                                                ? 1.0
                                                                : 2.2),
                                                      dashWidth: 5.0,
                                                      dashSpace: 3.5,
                                                      isSolid: isEvaluated,
                                                    ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: bgColor,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      alignment:
                                                          Alignment.topLeft,
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                            vertical:
                                                                isShortDuration
                                                                ? 1.0
                                                                : 2.5,
                                                          ),
                                                      clipBehavior:
                                                          Clip.hardEdge,
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              title,
                                                              maxLines: 15,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              softWrap: true,
                                                              style: TextStyle(
                                                                color: isDummy
                                                                    ? Colors
                                                                          .black
                                                                    : Colors
                                                                          .white,
                                                                fontSize:
                                                                    (isShortDuration
                                                                        ? 7.5
                                                                        : 9.0) *
                                                                    appState
                                                                        .fontSizeMultiplier,
                                                                fontWeight:
                                                                    isDummy
                                                                    ? FontWeight
                                                                          .bold
                                                                    : FontWeight
                                                                          .normal,
                                                                decoration:
                                                                    isCompleted
                                                                    ? TextDecoration
                                                                          .lineThrough
                                                                    : null,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                : Container(
                                                    decoration: BoxDecoration(
                                                      color: bgColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Colors
                                                                  .green
                                                                  .shade400
                                                            : Colors.white
                                                                  .withValues(
                                                                    alpha: 0.25,
                                                                  ),
                                                        width: isSelected
                                                            ? 2.5
                                                            : 1.0,
                                                      ),
                                                    ),
                                                    alignment:
                                                        Alignment.topLeft,
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical:
                                                              isShortDuration
                                                              ? 1.0
                                                              : 2.5,
                                                        ),
                                                    clipBehavior: Clip.hardEdge,
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            title,
                                                            maxLines: 15,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: true,
                                                            style: TextStyle(
                                                              color: isDummy
                                                                  ? Colors.black
                                                                  : Colors
                                                                        .white,
                                                              fontSize:
                                                                  (isShortDuration
                                                                      ? 7.5
                                                                      : 9.0) *
                                                                  appState
                                                                      .fontSizeMultiplier,
                                                              fontWeight:
                                                                  isDummy
                                                                  ? FontWeight
                                                                        .bold
                                                                  : FontWeight
                                                                        .normal,
                                                              decoration:
                                                                  isCompleted
                                                                  ? TextDecoration
                                                                        .lineThrough
                                                                  : null,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ));
                                      if (isHighImportance) {
                                        final Color protrusionColor = isSelected
                                            ? Colors.green.shade400
                                            : bgColor;
                                        return Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            c,
                                            Positioned(
                                              left: -6,
                                              top: visualHeight / 2 - 1,
                                              width: 6,
                                              height: 2,
                                              child: Container(
                                                color: protrusionColor,
                                              ),
                                            ),
                                            Positioned(
                                              right: -6,
                                              top: visualHeight / 2 - 1,
                                              width: 6,
                                              height: 2,
                                              child: Container(
                                                color: protrusionColor,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      return c;
                                    })(),
                                    isSelected: isSelected,
                                  ),
                                ),
                              );
                            }
                          }

                          return wrapWithSelection(
                            isTask
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border(
                                        left: BorderSide(
                                          color: isSelected
                                              ? Colors.green.shade400
                                              : (isEvaluated
                                                    ? (isSkippedEval
                                                          ? Colors.red.shade400
                                                          : Colors.black)
                                                    : Colors.black),
                                          width: isSelected ? 3.2 : 2.2,
                                        ),
                                        right: BorderSide(
                                          color: isSelected
                                              ? Colors.green.shade400
                                              : (isEvaluated
                                                    ? (isSkippedEval
                                                          ? Colors.red.shade400
                                                          : Colors.black)
                                                    : Colors.black),
                                          width: isSelected ? 3.2 : 2.2,
                                        ),
                                      ),
                                    ),
                                    alignment: Alignment.topLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2.5,
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: true,
                                            style: TextStyle(
                                              color: isDummy
                                                  ? Colors.black
                                                  : Colors.white,
                                              fontSize:
                                                  9.0 *
                                                  appState.fontSizeMultiplier,
                                              fontWeight: isDummy
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              decoration: isCompleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : (hasProject
                                      ? CustomPaint(
                                          painter: DashedBorderPainter(
                                            color: isSelected
                                                ? Colors.green.shade400
                                                : (isEvaluated
                                                      ? (isSkippedEval
                                                            ? Colors
                                                                  .red
                                                                  .shade400
                                                            : Colors.black)
                                                      : (project != null
                                                            ? Color(
                                                                project
                                                                    .colorValue,
                                                              )
                                                            : bgColor)),
                                            borderRadius: 6,
                                            strokeWidth: isSelected
                                                ? 3.2
                                                : (isEvaluated ? 1.0 : 2.2),
                                            dashWidth: 5.0,
                                            dashSpace: 3.5,
                                            isSolid: isEvaluated,
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: bgColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            alignment: Alignment.topLeft,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2.5,
                                            ),
                                            clipBehavior: Clip.hardEdge,
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    title,
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    softWrap: true,
                                                    style: TextStyle(
                                                      color: isDummy
                                                          ? Colors.black
                                                          : Colors.white,
                                                      fontSize:
                                                          9.0 *
                                                          appState
                                                              .fontSizeMultiplier,
                                                      fontWeight: isDummy
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                      decoration: isCompleted
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.green.shade400
                                                  : Colors.white.withValues(
                                                      alpha: 0.25,
                                                    ),
                                              width: isSelected ? 2.5 : 1.0,
                                            ),
                                          ),
                                          alignment: Alignment.topLeft,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2.5,
                                          ),
                                          clipBehavior: Clip.hardEdge,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  softWrap: true,
                                                  style: TextStyle(
                                                    color: isDummy
                                                        ? Colors.black
                                                        : Colors.white,
                                                    fontSize:
                                                        9.0 *
                                                        appState
                                                            .fontSizeMultiplier,
                                                    fontWeight: isDummy
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                    decoration: isCompleted
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                            isSelected: isSelected,
                          );
                        },
                        monthViewSettings: const MonthViewSettings(
                          appointmentDisplayMode:
                              MonthAppointmentDisplayMode.none,
                        ),
                        monthCellBuilder:
                            (
                              BuildContext buildContext,
                              MonthCellDetails details,
                            ) {
                              final resolvedAppointments = details.appointments
                                  .map(
                                    (appt) => _getOriginalItem(appt, appState),
                                  )
                                  .toList();

                              final dayEvents = resolvedAppointments
                                  .whereType<Event>()
                                  .toList();
                              final dayTasks = resolvedAppointments
                                  .whereType<TaskItem>()
                                  .toList();

                              final allStrips = _getActiveStrips(appState);
                              final stripSlots = _assignStripSlots(allStrips);
                              
                              final DateTime dateStart = DateTime(details.date.year, details.date.month, details.date.day);
                              final DateTime dateEnd = dateStart.add(const Duration(days: 1));
                              final dayStrips = allStrips.where((s) {
                                return s.startDate.isBefore(dateEnd) && s.endDate.isAfter(dateStart);
                              }).toList();
                              
                              int maxSlot = -1;
                              for (var s in dayStrips) {
                                final slot = stripSlots[s.id] ?? 0;
                                if (slot > maxSlot) maxSlot = slot;
                              }
                              
                              final bool hasStrips = appState.showSeritOverlay && dayStrips.isNotEmpty;
                              final totalItems = dayEvents.length + dayTasks.length + (hasStrips ? dayStrips.length : 0);

                              final now = DateTime.now();
                              final isToday =
                                  details.date.year == now.year &&
                                  details.date.month == now.month &&
                                  details.date.day == now.day;

                              final hasNote = appState.dayNotes.any(
                                (n) {
                                  final localDate = n.date.toLocal();
                                  return localDate.year == details.date.year &&
                                         localDate.month == details.date.month &&
                                         localDate.day == details.date.day &&
                                         n.note.trim().isNotEmpty;
                                },
                              );

                              if (totalItems == 0) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? Theme.of(
                                            buildContext,
                                          ).primaryColor.withValues(alpha: 0.1)
                                        : null,
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 4,
                                        left: 4,
                                        child: Text(
                                          details.date.day.toString(),
                                          style: TextStyle(
                                            fontWeight: isToday
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isToday
                                                ? Theme.of(
                                                    buildContext,
                                                  ).primaryColor
                                                : null,
                                          ),
                                        ),
                                      ),
                                      if (hasNote)
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: Icon(
                                            Icons.note_alt_outlined,
                                            size: 9,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }

                              int maxImportance = 0;
                              int highImportanceCount = 0;
                              for (var e in dayEvents) {
                                if (e.importance > maxImportance) {
                                  maxImportance = e.importance;
                                }
                                if (e.importance == 2) highImportanceCount++;
                              }
                              for (var t in dayTasks) {
                                if (t.importance > maxImportance) {
                                  maxImportance = t.importance;
                                }
                                if (t.importance == 2) highImportanceCount++;
                              }

                              return Container(
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? Theme.of(
                                          buildContext,
                                        ).primaryColor.withValues(alpha: 0.1)
                                      : null,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 0.5,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final List<dynamic> allItems = [
                                          ...dayEvents,
                                          ...dayTasks,
                                        ];
                                        allItems.sort((a, b) {
                                          bool aIsAllDay = a is Event
                                              ? a.isAllDay
                                              : (a as TaskItem).isAllDay;
                                          bool bIsAllDay = b is Event
                                              ? b.isAllDay
                                              : (b as TaskItem).isAllDay;

                                          if (aIsAllDay && !bIsAllDay) {
                                            return -1;
                                          }
                                          if (!aIsAllDay && bIsAllDay) return 1;

                                          if (!aIsAllDay && !bIsAllDay) {
                                            DateTime aFrom = a is Event
                                                ? a.from
                                                : (a as TaskItem).from!;
                                            DateTime bFrom = b is Event
                                                ? b.from
                                                : (b as TaskItem).from!;
                                            int timeCompare = aFrom.compareTo(
                                              bFrom,
                                            );
                                            if (timeCompare != 0) {
                                              return timeCompare;
                                            }
                                          }

                                          int impA = a is Event
                                              ? a.importance
                                              : (a as TaskItem).importance;
                                          int impB = b is Event
                                              ? b.importance
                                              : (b as TaskItem).importance;
                                          return impB.compareTo(impA);
                                        });

                                        final int stripsHeight = (appState.showSeritOverlay && maxSlot >= 0)
                                            ? (maxSlot + 1) * 16
                                            : 0;

                                        final int availableHeight =
                                            (constraints.maxHeight - 28 - stripsHeight)
                                                .toInt();
                                        final int maxLines = availableHeight > 0
                                            ? (availableHeight ~/ 14)
                                            : 0;

                                        List<Widget> itemWidgets = [];
                                        if (maxLines > 0 &&
                                            allItems.isNotEmpty) {
                                          if (allItems.length <= maxLines) {
                                            for (var item in allItems) {
                                              itemWidgets.add(
                                                _buildCellItemLine(item),
                                              );
                                            }
                                          } else {
                                            for (
                                              int i = 0;
                                              i < maxLines - 1;
                                              i++
                                            ) {
                                              itemWidgets.add(
                                                _buildCellItemLine(allItems[i]),
                                              );
                                            }
                                            itemWidgets.add(
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4.0,
                                                  top: 1.0,
                                                ),
                                                child: Text(
                                                  '+ ${allItems.length - (maxLines - 1)} daha',
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        } else if (allItems.isNotEmpty) {
                                          itemWidgets.add(
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4.0,
                                                top: 1.0,
                                              ),
                                              child: Text(
                                                '+ ${allItems.length} daha',
                                                maxLines: 1,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                4.0,
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Builder(
                                                    builder: (context) {
                                                      final dayText = Text(
                                                        details.date.day.toString(),
                                                        style: TextStyle(
                                                          fontWeight: isToday
                                                              ? FontWeight.bold
                                                              : FontWeight.normal,
                                                          color: isToday
                                                              ? Theme.of(
                                                                  context,
                                                                ).primaryColor
                                                              : null,
                                                        ),
                                                      );

                                                      if (highImportanceCount ==
                                                          0) {
                                                        return dayText;
                                                      }

                                                      final List<Widget>
                                                      children = [
                                                        Container(
                                                          width: 26,
                                                          height: 26,
                                                          decoration: BoxDecoration(
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: Colors.red,
                                                              width: 2,
                                                            ),
                                                          ),
                                                          alignment:
                                                              Alignment.center,
                                                          child: dayText,
                                                        ),
                                                      ];

                                                      final double radius = 13.0;
                                                      final double centerX = 13.0;
                                                      final double centerY = 13.0;
                                                      final double dotRadius = 2.0;

                                                      for (
                                                        int i = 0;
                                                        i < highImportanceCount;
                                                        i++
                                                      ) {
                                                        double angle =
                                                            -3.1415926535 / 2 +
                                                            (i *
                                                                2 *
                                                                3.1415926535 /
                                                                highImportanceCount);
                                                        double x =
                                                            centerX +
                                                            radius *
                                                                math.cos(angle) -
                                                            dotRadius;
                                                        double y =
                                                            centerY +
                                                            radius *
                                                                math.sin(angle) -
                                                            dotRadius;

                                                        children.add(
                                                          Positioned(
                                                            left: x,
                                                            top: y,
                                                            child: Container(
                                                              width: dotRadius * 2,
                                                              height: dotRadius * 2,
                                                              decoration:
                                                                  const BoxDecoration(
                                                                    color:
                                                                        Colors.red,
                                                                    shape: BoxShape
                                                                        .circle,
                                                                  ),
                                                            ),
                                                          ),
                                                        );
                                                      }

                                                      return SizedBox(
                                                        width: 26,
                                                        height: 26,
                                                        child: Stack(
                                                          clipBehavior: Clip.none,
                                                          children: children,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  if (hasNote)
                                                    Icon(
                                                      Icons.note_alt_outlined,
                                                      size: 9,
                                                      color: Colors.orange.shade700,
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (appState.showSeritOverlay && maxSlot >= 0)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: List.generate(maxSlot + 1, (slot) {
                                                    final s = dayStrips.where((x) => stripSlots[x.id] == slot).firstOrNull;
                                                    if (s == null) {
                                                      return const SizedBox(height: 16);
                                                    }
                                                    return _buildStripWidget(s, details.date, appState);
                                                  }),
                                                ),
                                              ),
                                            Expanded(
                                              child: Container(
                                                alignment: Alignment.bottomLeft,
                                                child: SingleChildScrollView(
                                                  physics:
                                                      const NeverScrollableScrollPhysics(),
                                                  reverse: true,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      ...itemWidgets,
                                                      const SizedBox(height: 2),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                        onLongPress: (CalendarLongPressDetails details) {
                          final appState = Provider.of<AppState>(
                            context,
                            listen: false,
                          );
                          if (details.targetElement ==
                                  CalendarElement.appointment &&
                              details.appointments!.isNotEmpty) {
                            final rawAppointment = details.appointments!.first;
                            final appointment = _getOriginalItem(
                              rawAppointment,
                              appState,
                            );
                            if (appointment is Event) {
                              if (appointment.id != 'dummy_t' &&
                                  appointment.id != 'dummy_e' &&
                                  appointment.id != 'dummy_eval') {
                                DateTime? occurrenceFrom;
                                if (rawAppointment is Appointment) {
                                  occurrenceFrom = rawAppointment.startTime;
                                } else {
                                  occurrenceFrom = appointment.from;
                                }
                                final String selectionId =
                                    appointment.recurrenceRule != null
                                    ? "${appointment.id}_${occurrenceFrom.millisecondsSinceEpoch}"
                                    : appointment.id;
                                appState.setBulkMode(true);
                                appState.toggleEventSelection(selectionId);
                                return;
                              }
                            }
                          }
                          if (details.date != null) {
                            _showAddSelection(
                              context,
                              initialDate: details.date,
                            );
                          }
                        },
                      ),
                    ),
                    ),
                     if (appState.calendarView == CalendarView.day ||
                        appState.calendarView == CalendarView.week)
                      Positioned(
                        left: 0,
                        top: 55.0,
                        width: 40.0,
                        bottom: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            appState.toggleExpandShortDuration();
                          },
                        ),
                      ),
                    _buildCustomHeaderRow(context, appState, constraints),
                    if (_showWeekStrips)
                      _buildWeekStripsPanel(context, appState, constraints),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCustomHeaderCell(DateTime date, AppState appState, bool isWeek, double width) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final noteIndex = appState.dayNotes.indexWhere(
      (n) {
        final localDate = n.date.toLocal();
        return localDate.year == normalizedDate.year &&
               localDate.month == normalizedDate.month &&
               localDate.day == normalizedDate.day;
      },
    );
    final DayNote? dayNote = noteIndex != -1 ? appState.dayNotes[noteIndex] : null;
    
    final hasEmoji = dayNote != null && dayNote.emoji != null && dayNote.emoji!.trim().isNotEmpty;
    final hasRating = dayNote != null && dayNote.rating != null && dayNote.rating! > 0;
    final hasNote = dayNote != null &&
        (dayNote.note.trim().isNotEmpty ||
            hasEmoji ||
            hasRating);
    
    final daysOfWeekTr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final String dayLetter = daysOfWeekTr[date.weekday - 1][0];
    final isDark = appState.isDarkMode;
    
    return GestureDetector(
      onTap: () {
        DayNoteDialog.show(context, appState, normalizedDate);
      },
      child: Container(
        width: width,
        height: 55.0,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hasNote
              ? (isDark ? Colors.amber.shade900.withValues(alpha: 0.15) : Colors.amber.shade50.withValues(alpha: 0.5))
              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              width: 0.5,
            ),
            right: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: hasEmoji
                    ? Text(
                        dayNote.emoji!,
                        style: const TextStyle(fontSize: 12),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            Text(
              dayLetter,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: hasRating
                    ? Text(
                        '★${dayNote.rating}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHeaderRow(BuildContext context, AppState appState, BoxConstraints constraints) {
    final isWeek = appState.calendarView == CalendarView.week;
    final isDay = appState.calendarView == CalendarView.day;
    if (!isWeek && !isDay) return const SizedBox.shrink();
    
    final double timeRulerWidth = 40.0;
    
    if (isWeek) {
      if (_visibleDates.length < 7) return const SizedBox.shrink();
      final double cellWidth = (constraints.maxWidth - timeRulerWidth) / 7;
      
      return Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: 55.0,
        child: Row(
          children: [
            Container(
              width: timeRulerWidth,
              height: 55.0,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: appState.isDarkMode ? Colors.white12 : Colors.grey.shade300,
                    width: 0.5,
                  ),
                  right: BorderSide(
                    color: appState.isDarkMode ? Colors.white12 : Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.view_stream,
                  size: 16,
                  color: appState.isDarkMode ? Colors.white60 : Colors.black54,
                ),
                onPressed: () {
                  setState(() {
                    _showWeekStrips = !_showWeekStrips;
                  });
                },
                tooltip: 'Haftalık Şeritler',
              ),
            ),
            ..._visibleDates.map((date) {
              return _buildCustomHeaderCell(date, appState, true, cellWidth);
            }),
          ],
        ),
      );
    } else {
      final DateTime date = appState.calendarController.displayDate ?? DateTime.now();
      final double cellWidth = constraints.maxWidth - timeRulerWidth;
      
      return Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: 55.0,
        child: Row(
          children: [
            Container(
              width: timeRulerWidth,
              height: 55.0,
              decoration: BoxDecoration(
                color: appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: appState.isDarkMode ? Colors.white12 : Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
              ),
            ),
            _buildCustomHeaderCell(date, appState, false, cellWidth),
          ],
        ),
      );
    }
  }

  Widget _buildWeekStripsPanel(BuildContext context, AppState appState, BoxConstraints constraints) {
    final isWeek = appState.calendarView == CalendarView.week;
    if (!isWeek || _visibleDates.isEmpty) return const SizedBox.shrink();
    
    // Find all active strips for the week
    final allStrips = _getActiveStrips(appState);
    final weekStart = DateTime(_visibleDates.first.year, _visibleDates.first.month, _visibleDates.first.day);
    final weekEnd = DateTime(_visibleDates.last.year, _visibleDates.last.month, _visibleDates.last.day).add(const Duration(days: 1));
    
    final weekStrips = allStrips.where((s) {
      return s.startDate.isBefore(weekEnd) && s.endDate.isAfter(weekStart);
    }).toList();
    
    if (weekStrips.isEmpty) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          height: 50,
          color: appState.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: appState.isDarkMode ? Colors.white10 : Colors.grey.shade300)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Text(
                  'Bu haftaya ait şerit bulunmamaktadır.',
                  style: TextStyle(
                    fontSize: 10,
                    color: appState.isDarkMode ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: () {
                  setState(() {
                    _showWeekStrips = false;
                  });
                },
              ),
            ],
          ),
        ),
      );
    }
    
    final stripSlots = _assignStripSlots(weekStrips);
    int maxSlot = -1;
    for (var s in weekStrips) {
      final slot = stripSlots[s.id] ?? 0;
      if (slot > maxSlot) maxSlot = slot;
    }
    
    final double panelHeight = (maxSlot + 1) * 20.0 + 36.0;
    final double columnWidth = (constraints.maxWidth - 40.0) / 7;
    final isDark = appState.isDarkMode;
    
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: panelHeight,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.grey.shade300,
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 5,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Haftalık Şeritler',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showWeekStrips = false;
                      });
                    },
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: weekStrips.map((s) {
                  final slot = stripSlots[s.id] ?? 0;
                  
                  // Calculate start column
                  int startCol = 0;
                  if (s.startDate.isAfter(weekStart)) {
                    startCol = (s.startDate.weekday - appState.firstDayOfWeek) % 7;
                  }
                  
                  // Calculate end column
                  int endCol = 6;
                  if (s.endDate.isBefore(weekEnd)) {
                    endCol = (s.endDate.weekday - appState.firstDayOfWeek) % 7;
                  }
                  
                  if (startCol < 0) startCol = 0;
                  if (endCol > 6) endCol = 6;
                  if (endCol < startCol) endCol = startCol;
                  
                  final double left = 40.0 + startCol * columnWidth;
                  final double width = (endCol - startCol + 1) * columnWidth;
                  
                  return Positioned(
                    left: left,
                    width: width,
                    top: slot * 20.0 + 2.0,
                    height: 16.0,
                    child: GestureDetector(
                      onTap: () {
                        if (s.originalItem is Serit) {
                          AllTimelineScreen.showSeritFormDialog(
                            context,
                            appState,
                            existingSerit: s.originalItem,
                          );
                        } else {
                          _showItemDetailsDialog(
                            context,
                            s.originalItem,
                            tappedDate: s.startDate,
                          );
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: s.color.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSelection(BuildContext context, {DateTime? initialDate}) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.event, color: Colors.blue),
                title: const Text('Etkinlik Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          EventFormScreen(initialDate: initialDate),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.rocket_launch, color: Colors.purple),
                title: const Text('Proje Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProjectFormScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.task_alt, color: Colors.green),
                title: const Text('Görev Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          TaskFormScreen(initialDate: initialDate),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAllDayItemsSheet(BuildContext context, DateTime date) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.95,
          child: Consumer<AppState>(
            builder: (context, appState, child) {
              final rawItems = _getAllDayItemsForDate(date, appState);
              final List<dynamic> displayItems = [];
              final seenIds = <String>{};
              for (var raw in rawItems) {
                final original = _getOriginalItem(raw, appState);
                String idKey = '';
                if (original is Event) idKey = original.id;
                else if (original is TaskItem) idKey = original.id;
                else if (original is Serit) idKey = original.id;
                else if (original is ProjectEvaluation) idKey = original.id;
                
                if (idKey.isEmpty || !seenIds.contains(idKey)) {
                  if (idKey.isNotEmpty) seenIds.add(idKey);
                  displayItems.add(original);
                }
              }
              final remainingEvents = 0;
              final remainingTasks = 0;

              return SafeArea(
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${date.day}/${date.month}/${date.year} Tüm Gün Planları',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: displayItems.isEmpty
                            ? const Center(child: Text('Plan yok'))
                            : Scrollbar(
                                thumbVisibility: true,
                                child: ListView.builder(
                                  itemCount: displayItems.length,
                                  itemBuilder: (context, index) {
                                    final item = displayItems[index];
                                    if (item is Event) {
                                      return Card(
                                        elevation: 0,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 4.0,
                                                          right: 8.0,
                                                        ),
                                                    child: Icon(
                                                      Icons.event,
                                                      color: Color(
                                                        item.colorValue,
                                                      ),
                                                      size: 20,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child:
                                                        _buildSheetItemSubtitle(
                                                          item,
                                                          appState,
                                                        ) ??
                                                        const SizedBox.shrink(),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      item.isHidden
                                                          ? Icons.visibility
                                                          : Icons
                                                                .visibility_off,
                                                      size: 20,
                                                      color: Colors.orange,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      appState.hideEvent(
                                                        item.id,
                                                        !item.isHidden,
                                                      );
                                                      _showUndoSnackBar(
                                                        item.isHidden
                                                            ? '"${item.title}" gösterildi'
                                                            : '"${item.title}" gizlendi',
                                                        () {
                                                          appState.hideEvent(
                                                            item.id,
                                                            item.isHidden,
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                      size: 20,
                                                      color: Colors.blueGrey,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      final originalItem =
                                                          _getOriginalItem(
                                                            item,
                                                            appState,
                                                          );
                                                      final hasRecurrence =
                                                          originalItem
                                                                  .recurrenceRule !=
                                                              null &&
                                                          originalItem
                                                              .recurrenceRule!
                                                              .isNotEmpty;
                                                      if (hasRecurrence) {
                                                        _handleRecurringAction(
                                                          context,
                                                          originalItem,
                                                          date,
                                                          false,
                                                        );
                                                      } else {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) =>
                                                                EventFormScreen(
                                                                  existingEvent:
                                                                      originalItem,
                                                                ),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      size: 20,
                                                      color: Colors.red,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      final originalItem =
                                                          _getOriginalItem(
                                                            item,
                                                            appState,
                                                          );
                                                      final hasRecurrence =
                                                          originalItem
                                                                  .recurrenceRule !=
                                                              null &&
                                                          originalItem
                                                              .recurrenceRule!
                                                              .isNotEmpty;
                                                      if (hasRecurrence) {
                                                        _handleRecurringAction(
                                                          context,
                                                          originalItem,
                                                          date,
                                                          true,
                                                        );
                                                      } else {
                                                        final deleted =
                                                            originalItem;
                                                        appState.deleteEvent(
                                                          originalItem.id,
                                                        );
                                                        _showUndoSnackBar(
                                                          '"${deleted.title}" silindi',
                                                          () {
                                                            appState.addEvent(
                                                              deleted,
                                                            );
                                                          },
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4.0,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.title,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    if (item
                                                        .description
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        item.description,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors
                                                              .grey
                                                              .shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    } else if (item is TaskItem) {
                                      return Card(
                                        elevation: 0,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Transform.translate(
                                                    offset: const Offset(-8, 0),
                                                    child: Checkbox(
                                                      value: item.isCompleted,
                                                      activeColor: Color(
                                                        item.colorValue,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                      visualDensity:
                                                          const VisualDensity(
                                                            horizontal: -4.0,
                                                            vertical: -4.0,
                                                          ),
                                                      onChanged: (bool? value) {
                                                        appState
                                                            .toggleTaskCompletion(
                                                              item.id,
                                                            );
                                                      },
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Transform.translate(
                                                      offset: const Offset(
                                                        -8,
                                                        0,
                                                      ),
                                                      child:
                                                          _buildSheetItemSubtitle(
                                                            item,
                                                            appState,
                                                          ) ??
                                                          const SizedBox.shrink(),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      item.isHidden
                                                          ? Icons.visibility
                                                          : Icons
                                                                .visibility_off,
                                                      size: 20,
                                                      color: Colors.orange,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      appState.hideTask(
                                                        item.id,
                                                        !item.isHidden,
                                                      );
                                                      _showUndoSnackBar(
                                                        item.isHidden
                                                            ? '"${item.title}" gösterildi'
                                                            : '"${item.title}" gizlendi',
                                                        () {
                                                          appState.hideTask(
                                                            item.id,
                                                            item.isHidden,
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                      size: 20,
                                                      color: Colors.blueGrey,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      final originalItem =
                                                          _getOriginalItem(
                                                            item,
                                                            appState,
                                                          );
                                                      final hasRecurrence =
                                                          !originalItem
                                                              .isCompleted &&
                                                          originalItem
                                                                  .recurrenceRule !=
                                                              null &&
                                                          originalItem
                                                              .recurrenceRule!
                                                              .isNotEmpty;
                                                      if (hasRecurrence) {
                                                        _handleRecurringAction(
                                                          context,
                                                          originalItem,
                                                          date,
                                                          false,
                                                        );
                                                      } else {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) =>
                                                                TaskFormScreen(
                                                                  existingTask:
                                                                      originalItem,
                                                                ),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      size: 20,
                                                      color: Colors.red,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      final originalItem =
                                                          _getOriginalItem(
                                                            item,
                                                            appState,
                                                          );
                                                      final hasRecurrence =
                                                          !originalItem
                                                              .isCompleted &&
                                                          originalItem
                                                                  .recurrenceRule !=
                                                              null &&
                                                          originalItem
                                                              .recurrenceRule!
                                                              .isNotEmpty;
                                                      if (hasRecurrence) {
                                                        _handleRecurringAction(
                                                          context,
                                                          originalItem,
                                                          date,
                                                          true,
                                                        );
                                                      } else {
                                                        final deleted =
                                                            originalItem;
                                                        appState.deleteTask(
                                                          originalItem.id,
                                                        );
                                                        _showUndoSnackBar(
                                                          '"${deleted.title}" silindi',
                                                          () {
                                                            appState.addTask(
                                                              deleted,
                                                            );
                                                          },
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4.0,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.id.startsWith(
                                                            'rollover_',
                                                          )
                                                          ? (item.title
                                                                    .startsWith(
                                                                      '⚠️',
                                                                    )
                                                                ? item.title
                                                                : '⚠️ ${item.title}')
                                                          : item.title,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                        decoration:
                                                            item.isCompleted
                                                            ? TextDecoration
                                                                  .lineThrough
                                                            : null,
                                                      ),
                                                    ),
                                                    if (item
                                                        .details
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        item.details,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors
                                                              .grey
                                                              .shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    } else if (item is ProjectEvaluation) {
                                      Project? linkedProject;
                                      try {
                                        linkedProject = appState.projects
                                            .firstWhere(
                                              (p) => p.id == item.projectId,
                                            );
                                      } catch (_) {}
                                      final titleText = linkedProject != null
                                          ? '📊 ${linkedProject.title}: ${item.isSkipped ? "Pas" : "%${item.score.toStringAsFixed(0)}"}'
                                          : '📊 Değerlendirme';
                                      final color = linkedProject != null
                                          ? (item.isSkipped
                                                ? Colors.red.shade400
                                                : Color(
                                                    linkedProject.colorValue,
                                                  ))
                                          : Colors.blue;
                                      return ListTile(
                                        leading: Icon(
                                          Icons.bar_chart,
                                          color: color,
                                        ),
                                        title: Text(titleText),
                                        trailing: linkedProject != null
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.edit,
                                                  size: 20,
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  _showProjectEvaluationDialog(
                                                    context,
                                                    linkedProject!,
                                                    item.sessionDate,
                                                  );
                                                },
                                              )
                                            : null,
                                        onTap: () {
                                          Navigator.pop(context);
                                          _showItemDetailsDialog(
                                            context,
                                            item,
                                            tappedDate: date,
                                          );
                                        },
                                      );
                                    } else if (item is Serit) {
                                      return Card(
                                        elevation: 0,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Checkbox(
                                                    value: item.isCompleted,
                                                    activeColor: Color(
                                                      item.colorValue,
                                                    ),
                                                    onChanged: (bool? val) {
                                                      appState.updateSerit(
                                                        item.copyWith(
                                                          isCompleted:
                                                              val ?? false,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Katman: ${item.title}',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 15,
                                                            decoration:
                                                                item.isCompleted
                                                                ? TextDecoration
                                                                      .lineThrough
                                                                : null,
                                                          ),
                                                        ),
                                                        Text(
                                                          '${item.startDate.day}/${item.startDate.month}/${item.startDate.year} - ${item.endDate.day}/${item.endDate.month}/${item.endDate.year}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      item.isVisible
                                                          ? Icons.visibility
                                                          : Icons
                                                                .visibility_off,
                                                      size: 20,
                                                      color: Colors.orange,
                                                    ),
                                                    onPressed: () {
                                                      appState.updateSerit(
                                                        item.copyWith(
                                                          isVisible:
                                                              !item.isVisible,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                      size: 20,
                                                      color: Colors.blueGrey,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      AllTimelineScreen.showSeritFormDialog(
                                                        context,
                                                        appState,
                                                        existingSerit: item,
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      size: 20,
                                                      color: Colors.red,
                                                    ),
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: const Text(
                                                            'Şeriti Sil',
                                                          ),
                                                          content: const Text(
                                                            'Bu şeriti silmek istediğinize emin misiniz?',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                  ),
                                                              child: const Text(
                                                                'İptal',
                                                              ),
                                                            ),
                                                            ElevatedButton(
                                                              onPressed: () {
                                                                appState
                                                                    .deleteSerit(
                                                                      item.id,
                                                                    );
                                                                Navigator.pop(
                                                                  context,
                                                                ); // Close dialog
                                                                Navigator.pop(
                                                                  context,
                                                                ); // Close bottom sheet
                                                              },
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    Colors.red,
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                              child: const Text(
                                                                'Sil',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                              if (item
                                                  .description
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 48.0,
                                                      ),
                                                  child: Text(
                                                    item.description,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox();
                                  },
                                ),
                              ),
                      ),
                      if (remainingEvents > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                          child: Text(
                            '+$remainingEvents Etkinlik',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      if (remainingTasks > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                          child: Text(
                            '+$remainingTasks görev',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showItemDetailsDialog(
    BuildContext context,
    dynamic item, {
    DateTime? tappedDate,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        final appState = Provider.of<AppState>(context, listen: false);
        Project? linkedProject;
        if (item is Event && item.projectId != null) {
          try {
            linkedProject = appState.projects.firstWhere(
              (p) => p.id == item.projectId,
            );
          } catch (_) {}
        } else if (item is TaskItem && item.projectId != null) {
          try {
            linkedProject = appState.projects.firstWhere(
              (p) => p.id == item.projectId,
            );
          } catch (_) {}
        } else if (item is ProjectEvaluation) {
          try {
            linkedProject = appState.projects.firstWhere(
              (p) => p.id == item.projectId,
            );
          } catch (_) {}
        }

        final DateTime? dateToCheck = item is Event
            ? item.from
            : (item is TaskItem
                  ? item.from
                  : (item is ProjectEvaluation ? item.sessionDate : null));
        ProjectEvaluation? dailyEval;
        if (item is ProjectEvaluation) {
          dailyEval = item;
        } else if (linkedProject != null && dateToCheck != null) {
          final normalizedDate = DateTime(
            dateToCheck.year,
            dateToCheck.month,
            dateToCheck.day,
          );
          try {
            dailyEval = appState.evaluations.firstWhere(
              (e) =>
                  e.projectId == linkedProject!.id &&
                  e.sessionDate == normalizedDate,
            );
          } catch (_) {}
        }

        final String? itemProjectId = (item is Event)
            ? item.projectId
            : ((item is TaskItem)
                  ? item.projectId
                  : (item is ProjectEvaluation ? item.projectId : null));
        final bool isDeletedProject =
            itemProjectId != null && itemProjectId.startsWith('deleted:');
        final String? deletedProjectTitle = isDeletedProject
            ? itemProjectId.substring(8)
            : null;

        String formatDuration(double hours) {
          if (hours <= 0) return '0 dk';
          final int wholeHours = hours.toInt();
          final int minutes = ((hours - wholeHours) * 60).round();
          if (wholeHours > 0 && minutes > 0) {
            return '$wholeHours saat $minutes dk';
          } else if (wholeHours > 0) {
            return '$wholeHours saat';
          } else {
            return '$minutes dk';
          }
        }

        String title = '';
        String tag = '';
        bool isHidden = false;
        bool isCompleted = false;

        if (item is Event) {
          title = item.title;
          tag = item.tag;
          isHidden = item.isHidden;
        } else if (item is TaskItem) {
          title = item.title;
          tag = item.tag;
          isHidden = item.isHidden;
          isCompleted = item.isCompleted;
        } else if (item is ProjectEvaluation) {
          title = linkedProject != null
              ? '📊 ${linkedProject.title} Değerlendirmesi'
              : '📊 Değerlendirme';
          tag = 'Performans Logu';
        }

        String dateInfo = '';
        if (item is Event) {
          final startStr = "${item.from.day}/${item.from.month}/${item.from.year}${item.isAllDay ? '' : ' ' + item.from.hour.toString().padLeft(2, '0') + ':' + item.from.minute.toString().padLeft(2, '0')}";
          final endStr = "${item.to.day}/${item.to.month}/${item.to.year}${item.isAllDay ? '' : ' ' + item.to.hour.toString().padLeft(2, '0') + ':' + item.to.minute.toString().padLeft(2, '0')}";
          dateInfo = item.isAllDay ? "Tüm Gün: ${item.from.day}/${item.from.month}/${item.from.year}" : "$startStr - $endStr";
        } else if (item is TaskItem && item.from != null) {
          final toDate = item.to ?? item.from!;
          final startStr = "${item.from!.day}/${item.from!.month}/${item.from!.year}${item.isAllDay ? '' : ' ' + item.from!.hour.toString().padLeft(2, '0') + ':' + item.from!.minute.toString().padLeft(2, '0')}";
          final endStr = "${toDate.day}/${toDate.month}/${toDate.year}${item.isAllDay ? '' : ' ' + toDate.hour.toString().padLeft(2, '0') + ':' + toDate.minute.toString().padLeft(2, '0')}";
          dateInfo = item.isAllDay ? "Tüm Gün: ${item.from!.day}/${item.from!.month}/${item.from!.year}" : "$startStr - $endStr";
        }

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item is Event && item.description.isNotEmpty)
                Text('Detay: ${item.description}'),
              if (item is TaskItem && item.details.isNotEmpty)
                Text('Detay: ${item.details}'),
              if (item is ProjectEvaluation &&
                  item.note != null &&
                  item.note!.isNotEmpty)
                Text('Detay/Not: ${item.note}'),
              if (dateInfo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time_outlined, size: 14, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateInfo,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text('Etiket: $tag'),
              if (linkedProject != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Bağlı Proje: ${linkedProject.title}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Performans: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        dailyEval != null
                            ? (() {
                                final eval = dailyEval!;
                                final proj = linkedProject!;
                                final successPercent = proj
                                    .calculateSingleSuccessPercentage(
                                      eval.score,
                                    );
                                final grossStr = formatDuration(
                                  eval.durationHours,
                                );
                                final netHours =
                                    eval.durationHours *
                                    (successPercent / 100.0);
                                final netStr = formatDuration(netHours);
                                final perfText =
                                    proj.evaluationType == 'PERCENTAGE'
                                    ? '%${eval.score.toStringAsFixed(0)}'
                                    : (proj.isNegativeGoal
                                          ? '${eval.score.toStringAsFixed(0)} (Hedef: ${proj.targetValue.toStringAsFixed(0)}), Başarı: %${successPercent.toStringAsFixed(0)}'
                                          : '${eval.score.toStringAsFixed(0)} (Hedef: ${proj.targetValue.toStringAsFixed(0)})');
                                return '$perfText, Brüt: $grossStr, Net: $netStr';
                              }())
                            : 'Değerlendirilmemiş',
                        style: TextStyle(
                          color: dailyEval != null
                              ? (dailyEval.isSkipped
                                    ? Colors.red
                                    : Colors.green.shade700)
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (dailyEval != null &&
                    dailyEval.note != null &&
                    dailyEval.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Performans Notu: ${dailyEval.note}',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    DateTime sessionDate = item is Event
                        ? item.from
                        : (item is TaskItem
                              ? item.from!
                              : (item as ProjectEvaluation).sessionDate);
                    double defaultDur = 1.0;
                    if (item is Event) {
                      defaultDur =
                          item.to.difference(item.from).inMinutes / 60.0;
                    } else if (item is TaskItem &&
                        item.from != null &&
                        item.to != null) {
                      defaultDur =
                          item.to!.difference(item.from!).inMinutes / 60.0;
                    } else if (item is ProjectEvaluation) {
                      defaultDur = item.durationHours;
                    }
                    _showProjectEvaluationDialog(
                      context,
                      linkedProject!,
                      sessionDate,
                      defaultDuration: defaultDur,
                    );
                  },
                  icon: const Icon(Icons.analytics, size: 16),
                  label: Text(
                    dailyEval != null
                        ? 'Değerlendirmeyi Düzenle'
                        : 'Projeyi Değerlendir',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade50,
                    foregroundColor: Colors.purple.shade700,
                    elevation: 0,
                    side: BorderSide(color: Colors.purple.shade200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ] else if (isDeletedProject && deletedProjectTitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Bağlı Proje: $deletedProjectTitle',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (item is TaskItem) ...[
              TextButton(
                onPressed: () {
                  String toggleId = item.id;
                  final hasRecurrence =
                      item.recurrenceRule != null &&
                      item.recurrenceRule!.isNotEmpty;
                  if (hasRecurrence && tappedDate != null) {
                    toggleId =
                        'occ_${item.id}_${tappedDate.millisecondsSinceEpoch}';
                  }
                  appState.toggleTaskInProgress(toggleId);
                  Navigator.pop(context);
                },
                child: Text(
                  item.isInProgress ? 'Yapılmıyor Yap' : 'Yapılıyor Yap',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: item.isInProgress ? Colors.blueGrey : Colors.amber.shade700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  String toggleId = item.id;
                  final hasRecurrence =
                      item.recurrenceRule != null &&
                      item.recurrenceRule!.isNotEmpty;
                  if (hasRecurrence && tappedDate != null) {
                    toggleId =
                        'occ_${item.id}_${tappedDate.millisecondsSinceEpoch}';
                  }
                  appState.toggleTaskCompletion(toggleId);
                  Navigator.pop(context);
                },
                child: Text(
                  item.isCompleted ? 'Tamamlanmadı' : 'Tamamlandı',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (item is! ProjectEvaluation)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (item is Event) {
                        appState.hideEvent(item.id, !isHidden);
                        _showUndoSnackBar(
                          isHidden
                              ? '"$title" gösterildi'
                              : '"$title" gizlendi',
                          () {
                            appState.hideEvent(item.id, isHidden);
                          },
                        );
                      } else if (item is TaskItem) {
                        appState.hideTask(item.id, !isHidden);
                        _showUndoSnackBar(
                          isHidden
                              ? '"$title" gösterildi'
                              : '"$title" gizlendi',
                          () {
                            appState.hideTask(item.id, isHidden);
                          },
                        );
                      }
                    },
                    child: Text(
                      isHidden ? 'Göster' : 'Gizle',
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final hasRecurrence =
                        (item is Event &&
                            item.recurrenceRule != null &&
                            item.recurrenceRule!.isNotEmpty) ||
                        (item is TaskItem &&
                            !item.isCompleted &&
                            item.recurrenceRule != null &&
                            item.recurrenceRule!.isNotEmpty);
                    if (hasRecurrence && tappedDate != null) {
                      _handleRecurringAction(context, item, tappedDate, false);
                    } else {
                      if (item is Event) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EventFormScreen(existingEvent: item),
                          ),
                        );
                      } else if (item is TaskItem) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                TaskFormScreen(existingTask: item),
                          ),
                        );
                      } else if (item is ProjectEvaluation &&
                          linkedProject != null) {
                        _showProjectEvaluationDialog(
                          context,
                          linkedProject,
                          item.sessionDate,
                        );
                      }
                    }
                  },
                  child: const Text('Düzenle'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final hasRecurrence =
                        (item is Event &&
                            item.recurrenceRule != null &&
                            item.recurrenceRule!.isNotEmpty) ||
                        (item is TaskItem &&
                            !item.isCompleted &&
                            item.recurrenceRule != null &&
                            item.recurrenceRule!.isNotEmpty);
                    if (hasRecurrence && tappedDate != null) {
                      _handleRecurringAction(context, item, tappedDate, true);
                    } else {
                      if (item is Event) {
                        final deleted = item;
                        appState.deleteEvent(item.id);
                        _showUndoSnackBar('"${deleted.title}" silindi', () {
                          appState.addEvent(deleted);
                        });
                      } else if (item is TaskItem) {
                        final deleted = item;
                        appState.deleteTask(item.id);
                        _showUndoSnackBar('"${deleted.title}" silindi', () {
                          appState.addTask(deleted);
                        });
                      } else if (item is ProjectEvaluation) {
                        appState.deleteEvaluation(
                          item.projectId,
                          item.sessionDate,
                        );
                      }
                    }
                  },
                  child: const Text('Sil', style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCellItemLine(dynamic item) {
    Color color = Colors.blue;
    String title = '';
    bool isPast = false;
    if (item is Event) {
      color = Color(item.colorValue);
      title = item.title;
      isPast = item.to.isBefore(DateTime.now());
    } else if (item is TaskItem) {
      color = Color(item.colorValue);
      title = item.title;
      isPast = item.isCompleted;
    } else if (item is ProjectEvaluation) {
      color = Colors.blue;
      title = 'Değerlendirme';
    }
    if (isPast) color = color.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 0.5),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 9,
                color: isPast ? Colors.black54 : Colors.black87,
                decoration: (item is TaskItem && isPast)
                    ? TextDecoration.lineThrough
                    : null,
                fontWeight:
                    (item is Event && item.importance == 2) ||
                        (item is TaskItem && item.importance == 2)
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showWarningDialog(
    BuildContext context,
    String actionText,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('İstatistik Uyarısı'),
              content: Text(
                'Bu değerlendirmeyi $actionText genel istatistiklerinizi etkileyecektir. Devam etmek istiyor musunuz?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hayır'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Evet, Devam Et'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showProjectEvaluationDialog(
    BuildContext context,
    Project project,
    DateTime sessionDate, {
    double? defaultDuration,
  }) {
    final appState = Provider.of<AppState>(context, listen: false);
    final normalizedDate = DateTime(
      sessionDate.year,
      sessionDate.month,
      sessionDate.day,
    );

    final existingEvalIndex = appState.evaluations.indexWhere(
      (e) => e.projectId == project.id && e.sessionDate == normalizedDate,
    );
    ProjectEvaluation? existingEval = existingEvalIndex != -1
        ? appState.evaluations[existingEvalIndex]
        : null;

    final double dur = defaultDuration ?? 1.0;
    final int initialHours = dur.toInt();
    final int initialMinutes = ((dur - initialHours) * 60).round();

    final TextEditingController scoreCtrl = TextEditingController(
      text: existingEval?.score.toString() ?? '',
    );
    final TextEditingController hoursCtrl = TextEditingController(
      text: existingEval != null
          ? existingEval.durationHours.toInt().toString()
          : initialHours.toString(),
    );
    final TextEditingController minutesCtrl = TextEditingController(
      text: existingEval != null
          ? ((existingEval.durationHours - existingEval.durationHours.toInt()) *
                    60)
                .round()
                .toString()
          : initialMinutes.toString(),
    );
    final TextEditingController noteCtrl = TextEditingController(
      text: existingEval?.note ?? '',
    );
    bool isSkipped = existingEval?.isSkipped ?? false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('${project.title} Değerlendirmesi'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${normalizedDate.day}/${normalizedDate.month}/${normalizedDate.year} tarihli oturum',
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Bugünü Boş Geçtim'),
                      value: isSkipped,
                      onChanged: (v) {
                        setState(() => isSkipped = v);
                      },
                    ),
                    if (!isSkipped) ...[
                      TextField(
                        controller: scoreCtrl,
                        decoration: InputDecoration(
                          labelText: project.evaluationType == 'PERCENTAGE'
                              ? 'Başarı Yüzdesi (%)'
                              : 'Elde Edilen Sayı (Hedef: ${project.targetValue})',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: hoursCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Saat',
                                suffixText: 'saat',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: minutesCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Dakika',
                                suffixText: 'dk',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Not Ekle',
                        hintText: 'Oturumla ilgili notlar yazın...',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                if (existingEval != null)
                  TextButton(
                    onPressed: () async {
                      final confirm = await _showWarningDialog(
                        context,
                        'silmek',
                      );
                      if (confirm && context.mounted) {
                        appState.deleteEvaluation(project.id, normalizedDate);
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      'Sil',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (existingEval != null) {
                      final confirm = await _showWarningDialog(
                        context,
                        'değiştirmek',
                      );
                      if (!confirm) return;
                    }
                    if (!context.mounted) return;
                    double score = double.tryParse(scoreCtrl.text) ?? 0.0;
                    int hrs = int.tryParse(hoursCtrl.text) ?? 0;
                    int mins = int.tryParse(minutesCtrl.text) ?? 0;
                    double duration = hrs + (mins / 60.0);
                    if (duration < 0.0) duration = 0.0;

                    final eval = ProjectEvaluation(
                      id:
                          existingEval?.id ??
                          IdGenerator.generate(
                            'degerlendirme_${project.title}',
                            date: normalizedDate,
                          ),
                      projectId: project.id,
                      sessionDate: normalizedDate,
                      score: isSkipped ? 0 : score,
                      isSkipped: isSkipped,
                      durationHours: isSkipped ? 0.0 : duration,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                    );
                    appState.addOrUpdateEvaluation(eval);
                    Navigator.pop(context);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleRecurringAction(
    BuildContext context,
    dynamic item,
    DateTime tappedDate,
    bool isDelete,
  ) {
    final isTask = item is TaskItem;
    final typeName = isTask ? 'Görevi' : 'Etkinliği';
    final pluralName = isTask ? 'Görevleri' : 'Etkinlikleri';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isDelete ? '$typeName Sil' : '$typeName Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  isDelete
                      ? 'Sadece bu $typeName sil'
                      : 'Sadece bu $typeName değiştir',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _executeRecurringAction(
                    context,
                    item,
                    tappedDate,
                    isDelete,
                    0,
                  );
                },
              ),
              ListTile(
                title: Text(
                  isDelete
                      ? 'Bundan ve sonraki $pluralName sil'
                      : 'Bundan ve sonraki $pluralName değiştir',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _executeRecurringAction(
                    context,
                    item,
                    tappedDate,
                    isDelete,
                    1,
                  );
                },
              ),
              if (isDelete && isTask)
                ListTile(
                  title: Text(
                    isTask
                        ? 'Bu serinin tamamlanmış tüm kopyalarını sil'
                        : 'Bu serinin tüm kopyalarını sil',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    final appState = Provider.of<AppState>(
                      context,
                      listen: false,
                    );
                    if (isTask) {
                      final deletedTasks = appState.tasks
                          .where((t) => t.seriesId == item.seriesId && t.isCompleted)
                          .toList();
                      appState.deleteCompletedTasksInSeries(item.seriesId);
                      _showUndoSnackBar(
                        'Serideki tamamlanmış kopyalar silindi',
                        () {
                          for (var t in deletedTasks) {
                            appState.addTask(t);
                          }
                        },
                      );
                    } else {
                      final deletedEvents = appState.events
                          .where((e) => e.seriesId == item.seriesId)
                          .toList();
                      appState.deleteEventSeries(item.seriesId);
                      _showUndoSnackBar(
                        'Serideki tüm kopyalar silindi',
                        () {
                          for (var e in deletedEvents) {
                            appState.addEvent(e);
                          }
                        },
                      );
                    }
                  },
                ),
              ListTile(
                title: Text(
                  isDelete
                      ? 'Tüm $pluralName sil (Tüm Seri)'
                      : 'Tüm $pluralName değiştir (Tüm Seri)',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _executeRecurringAction(
                    context,
                    item,
                    tappedDate,
                    isDelete,
                    2,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _executeRecurringAction(
    BuildContext context,
    dynamic item,
    DateTime tappedDate,
    bool isDelete,
    int option,
  ) {
    final appState = Provider.of<AppState>(context, listen: false);
    final resolved = _getOriginalItem(item, appState);
    item = resolved;

    DateTime originalStart = item is Event
        ? item.from
        : (item as TaskItem).from!;
    DateTime occurrenceStart = DateTime(
      tappedDate.year,
      tappedDate.month,
      tappedDate.day,
      originalStart.hour,
      originalStart.minute,
      originalStart.second,
    );

    DateTime originalEnd = item is Event
        ? item.to
        : (item as TaskItem).to ?? originalStart;
    Duration duration = originalEnd.difference(originalStart);
    DateTime occurrenceEnd = occurrenceStart.add(duration);

    if (option == 2) {
      if (isDelete) {
        if (item is Event) {
          final deleted = item;
          if (item.seriesId != null) {
            final deletedEvents = appState.events
                .where((e) => e.seriesId == item.seriesId)
                .toList();
            appState.deleteEventSeries(item.seriesId!);
            _showUndoSnackBar('"${deleted.title}" tüm serisi silindi', () {
              for (var e in deletedEvents) {
                appState.addEvent(e);
              }
            });
          }
        }
        if (item is TaskItem) {
          final deleted = item;
          final deletedTasks = appState.tasks
              .where((t) => t.seriesId == item.seriesId)
              .toList();
          appState.deleteTaskSeries(item.seriesId);
          _showUndoSnackBar('"${deleted.title}" tüm serisi silindi', () {
            for (var t in deletedTasks) {
              appState.addTask(t);
            }
          });
        }
      } else {
        if (item is Event) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventFormScreen(existingEvent: item),
            ),
          );
        } else if (item is TaskItem) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskFormScreen(existingTask: item),
            ),
          );
        }
      }
      return;
    }

    if (option == 0) {
      List<DateTime> exceptions = List.from(
        (item is Event
                ? item.recurrenceExceptionDates
                : (item as TaskItem).recurrenceExceptionDates) ??
            [],
      );
      exceptions.add(occurrenceStart);

      if (item is Event) {
        final originalEvent = item;
        final updatedOriginal = Event(
          id: item.id,
          title: item.title,
          description: item.description,
          from: item.from,
          to: item.to,
          isAllDay: item.isAllDay,
          colorValue: item.colorValue,
          tag: item.tag,
          importance: item.importance,
          reminderTime: item.reminderTime,
          recurrenceRule: item.recurrenceRule,
          recurrenceExceptionDates: exceptions,
          projectId: item.projectId,
        );
        appState.updateEvent(updatedOriginal);

        if (isDelete) {
          _showUndoSnackBar('"${item.title}" tekrarı silindi', () {
            appState.updateEvent(originalEvent);
          });
        }

        if (!isDelete) {
          final cloneId = IdGenerator.generate(
            '${item.title}_istisna_tekrar',
            date: occurrenceStart,
          );
          final clone = Event(
            id: cloneId,
            title: item.title,
            description: item.description,
            from: occurrenceStart,
            to: occurrenceEnd,
            isAllDay: item.isAllDay,
            colorValue: item.colorValue,
            tag: item.tag,
            importance: item.importance,
            reminderTime: item.reminderTime,
            recurrenceRule: null,
            recurrenceExceptionDates: null,
            projectId: item.projectId,
            seriesId: item.seriesId,
          );
          appState.addEvent(clone);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventFormScreen(
                existingEvent: clone,
                isSingleOccurrenceEdit: true,
              ),
            ),
          );
        }
      } else if (item is TaskItem) {
        final originalTask = item;
        final updatedOriginal = TaskItem(
          id: item.id,
          title: item.title,
          details: item.details,
          isCompleted: item.isCompleted,
          from: item.from,
          to: item.to,
          isAllDay: item.isAllDay,
          colorValue: item.colorValue,
          tag: item.tag,
          importance: item.importance,
          recurrenceRule: item.recurrenceRule,
          recurrenceExceptionDates: exceptions,
          projectId: item.projectId,
        );
        appState.updateTask(updatedOriginal);

        if (isDelete) {
          _showUndoSnackBar('"${item.title}" tekrarı silindi', () {
            appState.updateTask(originalTask);
          });
        }

        if (!isDelete) {
          final cloneId = IdGenerator.generate(
            '${item.title}_istisna_tekrar',
            date: occurrenceStart,
          );
          final clone = TaskItem(
            id: cloneId,
            title: item.title,
            details: item.details,
            isCompleted: item.isCompleted,
            from: occurrenceStart,
            to: occurrenceEnd,
            isAllDay: item.isAllDay,
            colorValue: item.colorValue,
            tag: item.tag,
            importance: item.importance,
            recurrenceRule: null,
            recurrenceExceptionDates: null,
            projectId: item.projectId,
            seriesId: item.seriesId,
          );
          appState.addTask(clone);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskFormScreen(
                existingTask: clone,
                isSingleOccurrenceEdit: true,
              ),
            ),
          );
        }
      }
      return;
    }

    if (option == 1) {
      DateTime untilDate = occurrenceStart.subtract(const Duration(days: 1));
      String untilStr =
          "${untilDate.year}${untilDate.month.toString().padLeft(2, '0')}${untilDate.day.toString().padLeft(2, '0')}T235959Z";

      String oldRule = item is Event
          ? item.recurrenceRule!
          : (item as TaskItem).recurrenceRule!;
      List<String> parts = oldRule.split(';');
      parts.removeWhere((p) => p.startsWith('UNTIL='));
      parts.add('UNTIL=$untilStr');
      String limitedRule = parts.join(';');

      if (item is Event) {
        final originalEvent = item;
        final updatedOriginal = Event(
          id: item.id,
          title: item.title,
          description: item.description,
          from: item.from,
          to: item.to,
          isAllDay: item.isAllDay,
          colorValue: item.colorValue,
          tag: item.tag,
          importance: item.importance,
          reminderTime: item.reminderTime,
          recurrenceRule: limitedRule,
          recurrenceExceptionDates: item.recurrenceExceptionDates,
          projectId: item.projectId,
        );
        appState.updateEvent(updatedOriginal);

        if (isDelete) {
          _showUndoSnackBar('"${item.title}" sonraki tekrarlar silindi', () {
            appState.updateEvent(originalEvent);
          });
        }

        if (!isDelete) {
          final cloneId = IdGenerator.generate(
            '${item.title}_istisna_tekrar',
            date: occurrenceStart,
          );
          final clone = Event(
            id: cloneId,
            title: item.title,
            description: item.description,
            from: occurrenceStart,
            to: occurrenceEnd,
            isAllDay: item.isAllDay,
            colorValue: item.colorValue,
            tag: item.tag,
            importance: item.importance,
            reminderTime: item.reminderTime,
            recurrenceRule: oldRule,
            recurrenceExceptionDates: null,
            projectId: item.projectId,
            seriesId: item.seriesId,
          );
          appState.addEvent(clone);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventFormScreen(existingEvent: clone),
            ),
          );
        }
      } else if (item is TaskItem) {
        final originalTask = item;
        final updatedOriginal = TaskItem(
          id: item.id,
          title: item.title,
          details: item.details,
          isCompleted: item.isCompleted,
          from: item.from,
          to: item.to,
          isAllDay: item.isAllDay,
          colorValue: item.colorValue,
          tag: item.tag,
          importance: item.importance,
          recurrenceRule: limitedRule,
          recurrenceExceptionDates: item.recurrenceExceptionDates,
          projectId: item.projectId,
        );
        appState.updateTask(updatedOriginal);

        if (isDelete) {
          _showUndoSnackBar('"${item.title}" sonraki tekrarlar silindi', () {
            appState.updateTask(originalTask);
          });
        }

        if (!isDelete) {
          final cloneId = IdGenerator.generate(
            '${item.title}_istisna_tekrar',
            date: occurrenceStart,
          );
          final clone = TaskItem(
            id: cloneId,
            title: item.title,
            details: item.details,
            isCompleted: item.isCompleted,
            from: occurrenceStart,
            to: occurrenceEnd,
            isAllDay: item.isAllDay,
            colorValue: item.colorValue,
            tag: item.tag,
            importance: item.importance,
            recurrenceRule: oldRule,
            recurrenceExceptionDates: null,
            projectId: item.projectId,
            seriesId: item.seriesId,
          );
          appState.addTask(clone);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskFormScreen(existingTask: clone),
            ),
          );
        }
      }
    }
  }
}

class EventDataSource extends CalendarDataSource {
  AppState? appState;
  EventDataSource(List<dynamic> source, {this.appState}) {
    appointments = source;
  }

  @override
  DateTime getStartTime(int index) {
    final item = appointments![index];
    if (item is Event) {
      if (item.isAllDay) {
        return item.from.isUtc
            ? DateTime.utc(item.from.year, item.from.month, item.from.day)
            : DateTime(item.from.year, item.from.month, item.from.day);
      }
      return item.from;
    }
    if (item is TaskItem) {
      final fromVal = item.from ?? DateTime.now();
      if (item.isAllDay) {
        return fromVal.isUtc
            ? DateTime.utc(fromVal.year, fromVal.month, fromVal.day)
            : DateTime(fromVal.year, fromVal.month, fromVal.day);
      }
      return fromVal;
    }
    if (item is ProjectEvaluation) return item.sessionDate;
    if (item is DayNote) {
      return DateTime(item.date.year, item.date.month, item.date.day, 23, 59);
    }
    return DateTime.now();
  }

  @override
  DateTime getEndTime(int index) {
    final item = appointments![index];
    if (item is Event) {
      if (item.isAllDay) {
        final toVal = item.to;
        return toVal.isUtc
            ? DateTime.utc(toVal.year, toVal.month, toVal.day, 23, 59, 59)
            : DateTime(toVal.year, toVal.month, toVal.day, 23, 59, 59);
      }
      if (item.to.isAtSameMomentAs(item.from)) {
        return item.from.add(const Duration(minutes: 15));
      }
      return item.to;
    }
    if (item is TaskItem) {
      final fromVal = item.from ?? DateTime.now();
      if (item.isAllDay) {
        final toVal = item.to ?? fromVal;
        return toVal.isUtc
            ? DateTime.utc(toVal.year, toVal.month, toVal.day, 23, 59, 59)
            : DateTime(toVal.year, toVal.month, toVal.day, 23, 59, 59);
      }
      if (item.to != null) {
        if (item.to!.isAtSameMomentAs(fromVal)) {
          return fromVal.add(const Duration(minutes: 15));
        }
        return item.to!;
      }
      return fromVal.add(const Duration(hours: 1));
    }
    if (item is ProjectEvaluation) {
      return item.sessionDate.add(const Duration(hours: 1));
    }
    if (item is DayNote) {
      return DateTime(
        item.date.year,
        item.date.month,
        item.date.day,
        23,
        59,
        59,
      );
    }
    return DateTime.now();
  }

  @override
  String getSubject(int index) {
    final item = appointments![index];
    if (item is Event) return item.title;
    if (item is TaskItem) return item.title;
    if (item is ProjectEvaluation && appState != null) {
      try {
        final project = appState!.projects.firstWhere(
          (p) => p.id == item.projectId,
        );
        if (item.isSkipped) return '📊 ${project.title}: Pas';
        return '📊 ${project.title}: %${item.score.toStringAsFixed(0)}';
      } catch (_) {
        return '📊 Değerlendirme';
      }
    }
    if (item is DayNote) return item.note;
    return '';
  }

  @override
  Color getColor(int index) {
    final item = appointments![index];
    if (item is Event) return Color(item.colorValue);
    if (item is TaskItem) return Color(item.colorValue);
    if (item is ProjectEvaluation && appState != null) {
      try {
        final project = appState!.projects.firstWhere(
          (p) => p.id == item.projectId,
        );
        return item.isSkipped ? Colors.red.shade400 : Color(project.colorValue);
      } catch (_) {}
    }
    if (item is DayNote) return Colors.teal.shade700;
    return Colors.blue;
  }

  @override
  bool isAllDay(int index) {
    final item = appointments![index];
    if (item is Event) return item.isAllDay;
    if (item is TaskItem) return item.isAllDay;
    if (item is DayNote) return false;
    return false;
  }

  @override
  Object? getId(int index) {
    final item = appointments![index];
    if (item is Event) return item.id;
    if (item is TaskItem) return item.id;
    if (item is DayNote) return 'daynote_${item.id}';
    return null;
  }

  @override
  String? getRecurrenceRule(int index) {
    final item = appointments![index];
    if (item is Event) return _sanitizeRRule(item.recurrenceRule, item.from);
    if (item is TaskItem) {
      return _sanitizeRRule(item.recurrenceRule, item.from ?? DateTime.now());
    }
    return null;
  }

  @override
  List<DateTime>? getRecurrenceExceptionDates(int index) {
    final item = appointments![index];
    if (item is Event) return item.recurrenceExceptionDates;
    if (item is TaskItem) return item.recurrenceExceptionDates;
    return null;
  }
}

class OccurrenceInfo {
  final dynamic originalItem;
  final String id;
  final DateTime from;
  final DateTime to;
  OccurrenceInfo({
    required this.originalItem,
    required this.id,
    required this.from,
    required this.to,
  });
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;
  final bool isSolid;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.dashWidth = 4.0,
    this.dashSpace = 3.0,
    this.borderRadius = 6.0,
    this.isSolid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(borderRadius),
    );

    final Path path = Path()..addRRect(rrect);

    if (isSolid) {
      canvas.drawPath(path, paint);
    } else {
      final Path dashedPath = Path();
      double distance = 0.0;
      for (final PathMetric measurePath in path.computeMetrics()) {
        while (distance < measurePath.length) {
          dashedPath.addPath(
            measurePath.extractPath(distance, distance + dashWidth),
            Offset.zero,
          );
          distance += dashWidth + dashSpace;
        }
      }
      canvas.drawPath(dashedPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isSolid != isSolid;
  }
}
