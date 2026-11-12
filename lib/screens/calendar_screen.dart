import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'daily_notes_screen.dart';
import 'package:my_plan/screens/plan_screen.dart' show PlanScreen;
import '../dialogs/project_evaluation_dialog.dart';
import '../dialogs/follow_up_log_dialog.dart';

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

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late EventDataSource _dataSource;
  List<DateTime> _visibleDates = [];
  bool _showWeekStrips = false;

  final Map<int, Offset> _activePointers = {};
  Offset? _lastPointerLocalPos;
  Offset? _lastPointerGlobalPos;
  double _baseTimeIntervalHeight = 60.0;
  double _timeIntervalHeight = 60.0;
  double _initialDistance = 0.0;
  DateTime? _lastSwipeTime;

  // Drag & Drop, Edge Resize & Copy-Paste State
  RenderBox? _timeGridRenderBox;
  final GlobalKey _calendarStackKey = GlobalKey();
  double _lastCalendarWidth = 400.0;
  double _lastActiveIntervalHeight = 60.0;
  double _lastStartHour = 0.0;
  double _lastEndHour = 24.0;
  SystemMouseCursor _calendarMouseCursor = SystemMouseCursors.basic;

  _InteractionMode _interactionMode = _InteractionMode.none;
  _CardHitResult? _activeHit;
  DateTime? _previewFrom;
  DateTime? _previewTo;
  int _previewDayIndex = 0;
  String? _manipulatedCardId;
  DateTime? _manipulatedCardFrom;
  late final AnimationController _marchingAntsController;

  dynamic _lastFocusedItem;
  DateTime? _lastFocusedOccurrenceFrom;
  dynamic _copiedItem;
  DateTime? _copiedOccurrenceFrom;
  bool _pasteUseOriginalTime = false;
  DateTime? _lastHoveredDateTime;
  final List<_CalendarUndoEntry> _undoStack = [];
  final List<_CalendarUndoEntry> _redoStack = [];
  List<ScrollPosition> _timeGridScrollPositions = [];
  final Map<ScrollPosition, double> _lockedScrollOffsets = {};
  bool _isScrollLocked = false;

  void _handlePointerDown(PointerDownEvent event) {
    _lastPointerLocalPos = event.localPosition;
    _lastPointerGlobalPos = event.position;
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

    if (_activePointers.length == 2 && _initialDistance > 0 && _interactionMode == _InteractionMode.none) {
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
    _marchingAntsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    _unlockCalendarScroll();
    _marchingAntsController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WakelockPlus.disable();
    super.dispose();
  }

  bool _isCardManipulated(String itemId, DateTime occFrom) {
    if (_manipulatedCardId == null || _manipulatedCardId != itemId) {
      return false;
    }
    if (_manipulatedCardFrom == null) return true;
    return _manipulatedCardFrom!.difference(occFrom).inMinutes.abs() <= 1;
  }

  void _activateCardManipulation(_CardHitResult hit) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _manipulatedCardId = hit.occurrence.id;
      _manipulatedCardFrom = hit.occurrence.fullFrom;
    });
  }

  void _clearCardManipulation() {
    if (!mounted || _manipulatedCardId == null) return;
    setState(() {
      _manipulatedCardId = null;
      _manipulatedCardFrom = null;
    });
  }

  void _lockCalendarScroll() {
    _isScrollLocked = true;
    for (final pos in _lockedScrollOffsets.keys) {
      pos.removeListener(_enforceLockedScroll);
    }
    _lockedScrollOffsets.clear();
    for (final pos in _timeGridScrollPositions) {
      if (pos.hasPixels) {
        _lockedScrollOffsets[pos] = pos.pixels;
        pos.isScrollingNotifier.value = false;
        pos.addListener(_enforceLockedScroll);
      }
    }
  }

  void _enforceLockedScroll() {
    if (!_isScrollLocked) return;
    for (final entry in _lockedScrollOffsets.entries) {
      final pos = entry.key;
      final target = entry.value;
      if (pos.hasPixels && (pos.pixels - target).abs() > 0.05) {
        pos.correctPixels(target);
      }
    }
  }

  void _unlockCalendarScroll() {
    _isScrollLocked = false;
    for (final pos in _lockedScrollOffsets.keys) {
      pos.removeListener(_enforceLockedScroll);
    }
    _lockedScrollOffsets.clear();
  }

  void _handleCardTap(_CardHitResult hit) {
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.isBulkMode) {
      if (hit.occurrence.originalItem is Event) {
        final Event e = hit.occurrence.originalItem as Event;
        if (e.id != 'dummy_t' && e.id != 'dummy_e' && e.id != 'dummy_eval') {
          final String selectionId = e.recurrenceRule != null
              ? "${e.id}_${hit.occurrence.fullFrom.millisecondsSinceEpoch}"
              : e.id;
          appState.toggleEventSelection(selectionId);
        }
      }
      return;
    }
    _showItemDetailsDialog(
      context,
      hit.occurrence.originalItem,
      tappedDate: hit.occurrence.fullFrom,
    );
  }

  DateTime _getDayForColumnIndex(int dayIndex, AppState appState) {
    final int numDays = appState.calendarView == CalendarView.week ? 7 : 1;
    if (numDays == 1) {
      final d = appState.calendarController.displayDate ?? DateTime.now();
      return DateTime(d.year, d.month, d.day);
    }
    if (_visibleDates.length > dayIndex) {
      final d = _visibleDates[dayIndex].toLocal();
      return DateTime(d.year, d.month, d.day);
    }
    final d = appState.calendarController.displayDate ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  void _captureTimeGridFromCard(BuildContext cardContext) {
    void tryResolve() {
      if (!mounted || !cardContext.mounted) return;
      final List<ScrollPosition> positions = [];
      cardContext.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final ScrollableState s = element.state as ScrollableState;
          positions.add(s.position);
        }
        return true;
      });
      if (positions.isNotEmpty) {
        _timeGridScrollPositions = positions;
      }
      final double expectedHeight =
          (_lastEndHour - _lastStartHour) * _lastActiveIntervalHeight;
      RenderObject? node = cardContext.findRenderObject()?.parent;
      while (node != null) {
        if (node is RenderBox &&
            node.hasSize &&
            node.size.width >= _lastCalendarWidth - 60.0 &&
            (node.size.height - expectedHeight).abs() < 40.0) {
          _timeGridRenderBox = node;
          return;
        }
        node = node.parent;
      }
    }

    tryResolve();
    if (_timeGridRenderBox == null || !_timeGridRenderBox!.attached) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryResolve());
    }
  }

  _CardHitResult? _hitTestDayWeekCard(Offset globalPos, {Offset? listenerLocalPos}) {
    if (!mounted) return null;
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.isBulkMode) return null;
    if (appState.calendarView != CalendarView.day &&
        appState.calendarView != CalendarView.week) {
      return null;
    }
    if (_timeGridRenderBox == null || !_timeGridRenderBox!.attached) {
      return null;
    }

    final Offset? localInListener = listenerLocalPos ?? _lastPointerLocalPos;
    if (localInListener != null) {
      if (localInListener.dy < 0) return null;
      final calDetails = appState.calendarController.getCalendarDetailsAtOffset
          ?.call(localInListener);
      if (calDetails != null &&
          (calDetails.targetElement == CalendarElement.allDayPanel ||
              calDetails.targetElement == CalendarElement.viewHeader)) {
        return null;
      }
    }

    final Offset gridPos = _timeGridRenderBox!.globalToLocal(globalPos);
    const double timeRulerWidth = 40.0;
    final double totalGridHeight =
        (_lastEndHour - _lastStartHour) * _lastActiveIntervalHeight;
    if (gridPos.dx < timeRulerWidth ||
        gridPos.dx > _lastCalendarWidth ||
        gridPos.dy < 0 ||
        gridPos.dy > totalGridHeight) {
      return null;
    }

    final int numDays = appState.calendarView == CalendarView.week ? 7 : 1;
    final double columnWidth = (_lastCalendarWidth - timeRulerWidth) / numDays;
    if (columnWidth <= 0) return null;

    final int dayIndex = numDays == 1
        ? 0
        : (((gridPos.dx - timeRulerWidth) / columnWidth).floor()).clamp(
            0,
            numDays - 1,
          );
    final DateTime targetDay = _getDayForColumnIndex(dayIndex, appState);
    final DateTime dayStart = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day,
    );
    final DateTime dayEnd = dayStart.add(const Duration(days: 1));

    final occurrences = _collectDayOccurrences(targetDay, appState);
    if (occurrences.isEmpty) return null;

    final layouts = _computeDayOverlapLayouts(
      occurrences: occurrences,
      activeIntervalHeight: _lastActiveIntervalHeight,
      fontSizeMultiplier: appState.fontSizeMultiplier,
    );

    final double colStart = timeRulerWidth + dayIndex * columnWidth;

    for (int i = occurrences.length - 1; i >= 0; i--) {
      final occ = occurrences[i];
      final layout = layouts[i];
      final double cardLeft = colStart + layout['leftRatio']! * columnWidth;
      double cardWidth = columnWidth * layout['widthRatio']!;
      if (cardWidth > 4.0) cardWidth -= 2.0;
      if (cardWidth < 10.0) cardWidth = 10.0;

      final double startHoursFromTop =
          (occ.from.difference(dayStart).inMinutes / 60.0) - _lastStartHour;
      final double endHoursFromTop =
          (occ.to.difference(dayStart).inMinutes / 60.0) - _lastStartHour;
      final double cardTop = startHoursFromTop * _lastActiveIntervalHeight;
      final double rawHeight =
          (endHoursFromTop - startHoursFromTop) * _lastActiveIntervalHeight;
      final bool isShortDuration =
          appState.expandShortDuration && rawHeight < 22.0;
      final double visualHeight = isShortDuration
          ? 18.0
          : math.max(14.0, rawHeight);
      final double cardBottom = cardTop + visualHeight;

      if (gridPos.dx >= cardLeft - 1.0 &&
          gridPos.dx <= cardLeft + cardWidth + 1.0 &&
          gridPos.dy >= cardTop &&
          gridPos.dy <= cardBottom) {
        final bool isCardManip = _isCardManipulated(occ.id, occ.fullFrom);
        final double edgeMargin = isCardManip
            ? (visualHeight * 0.28).clamp(5.0, 10.0)
            : (visualHeight * 0.25).clamp(3.0, 7.0);
        _CardHitZone zone = _CardHitZone.body;
        if (gridPos.dy <= cardTop + edgeMargin &&
            !occ.fullFrom.isBefore(dayStart)) {
          zone = _CardHitZone.topResize;
        } else if (gridPos.dy >= cardBottom - edgeMargin &&
            !occ.fullTo.isAfter(dayEnd)) {
          zone = _CardHitZone.bottomResize;
        }

        return _CardHitResult(
          occurrence: occ,
          zone: zone,
          dayIndex: dayIndex,
          cardRectInGrid: Rect.fromLTWH(
            cardLeft,
            cardTop,
            cardWidth,
            visualHeight,
          ),
          startGridPos: gridPos,
        );
      }
    }
    return null;
  }

  void _handleCalendarHover(PointerHoverEvent event) {
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    if (_interactionMode != _InteractionMode.none) return;

    if ((appState.calendarView == CalendarView.day ||
            appState.calendarView == CalendarView.week) &&
        _timeGridRenderBox != null &&
        _timeGridRenderBox!.attached) {
      final Offset gridPos = _timeGridRenderBox!.globalToLocal(event.position);
      const double timeRulerWidth = 40.0;
      final int numDays = appState.calendarView == CalendarView.week ? 7 : 1;
      final double columnWidth =
          (_lastCalendarWidth - timeRulerWidth) / numDays;
      if (gridPos.dx >= timeRulerWidth &&
          gridPos.dx <= _lastCalendarWidth &&
          gridPos.dy >= 0 &&
          columnWidth > 0) {
        final int dayIndex = numDays == 1
            ? 0
            : (((gridPos.dx - timeRulerWidth) / columnWidth).floor()).clamp(
                0,
                numDays - 1,
              );
        final DateTime day = _getDayForColumnIndex(dayIndex, appState);
        final int rawMinutes =
            ((_lastStartHour * 60.0) +
                    (gridPos.dy / _lastActiveIntervalHeight) * 60.0)
                .round();
        final int snappedMinutes = ((rawMinutes / 15.0).round() * 15).clamp(
          0,
          23 * 60 + 45,
        );
        _lastHoveredDateTime = DateTime(
          day.year,
          day.month,
          day.day,
          snappedMinutes ~/ 60,
          snappedMinutes % 60,
        );
      }
    } else if (appState.calendarView == CalendarView.month) {
      final calDetails = appState.calendarController.getCalendarDetailsAtOffset
          ?.call(event.localPosition);
      if (calDetails?.date != null) {
        _lastHoveredDateTime = calDetails!.date;
      }
    }

    final hit = _hitTestDayWeekCard(
      event.position,
      listenerLocalPos: event.localPosition,
    );
    SystemMouseCursor desiredCursor = SystemMouseCursors.basic;
    if (hit != null) {
      if (_isCardManipulated(hit.occurrence.id, hit.occurrence.fullFrom)) {
        if (hit.zone == _CardHitZone.topResize ||
            hit.zone == _CardHitZone.bottomResize) {
          desiredCursor = SystemMouseCursors.resizeUpDown;
        } else {
          desiredCursor = SystemMouseCursors.grab;
        }
      } else {
        desiredCursor = SystemMouseCursors.click;
      }
    } else if (_copiedItem != null) {
      desiredCursor = SystemMouseCursors.click;
    }

    if (_calendarMouseCursor != desiredCursor) {
      setState(() {
        _calendarMouseCursor = desiredCursor;
      });
    }
  }

  void _startCardInteraction(_CardHitResult hit, Offset downGlobalPos) {
    if (!mounted) return;
    _lockCalendarScroll();
    setState(() {
      _activeHit = hit;
      _previewFrom = hit.occurrence.fullFrom;
      _previewTo = hit.occurrence.fullTo;
      _previewDayIndex = hit.dayIndex;
      if (hit.zone == _CardHitZone.topResize) {
        _interactionMode = _InteractionMode.resizeTop;
        _calendarMouseCursor = SystemMouseCursors.resizeUpDown;
      } else if (hit.zone == _CardHitZone.bottomResize) {
        _interactionMode = _InteractionMode.resizeBottom;
        _calendarMouseCursor = SystemMouseCursors.resizeUpDown;
      } else {
        _interactionMode = _InteractionMode.move;
        _calendarMouseCursor = SystemMouseCursors.grabbing;
      }
    });
  }

  void _updateCardInteraction(Offset currentGlobalPos) {
    if (!mounted ||
        _interactionMode == _InteractionMode.none ||
        _activeHit == null ||
        _timeGridRenderBox == null ||
        !_timeGridRenderBox!.attached) {
      return;
    }
    final appState = Provider.of<AppState>(context, listen: false);
    final Offset gridPos = _timeGridRenderBox!.globalToLocal(currentGlobalPos);
    const double timeRulerWidth = 40.0;
    final int numDays = appState.calendarView == CalendarView.week ? 7 : 1;
    final double columnWidth = (_lastCalendarWidth - timeRulerWidth) / numDays;
    if (columnWidth <= 0) return;

    final double deltaY = gridPos.dy - _activeHit!.startGridPos.dy;
    final double rawDeltaMinutes =
        (deltaY / _lastActiveIntervalHeight) * 60.0;
    final int snappedDeltaMinutes = (rawDeltaMinutes / 15.0).round() * 15;

    final DateTime initialFrom = _activeHit!.occurrence.fullFrom;
    final DateTime initialTo = _activeHit!.occurrence.fullTo;
    final Duration duration = initialTo.difference(initialFrom);

    DateTime nextFrom = initialFrom;
    DateTime nextTo = initialTo;
    int nextDayIndex = _activeHit!.dayIndex;

    if (_interactionMode == _InteractionMode.move) {
      nextDayIndex = numDays == 1
          ? 0
          : (((gridPos.dx - timeRulerWidth) / columnWidth).floor()).clamp(
              0,
              numDays - 1,
            );
      final int dayDelta = nextDayIndex - _activeHit!.dayIndex;
      final DateTime dayShiftedFrom = DateTime(
        initialFrom.year,
        initialFrom.month,
        initialFrom.day + dayDelta,
        initialFrom.hour,
        initialFrom.minute,
      );
      if (deltaY.abs() < 6.0) {
        nextFrom = dayShiftedFrom;
      } else {
        final int origMinOfDay = initialFrom.hour * 60 + initialFrom.minute;
        final int newMinOfDay = (((origMinOfDay + rawDeltaMinutes) / 15.0)
                    .round() *
                15)
            .clamp(0, 23 * 60 + 45);
        nextFrom = DateTime(
          dayShiftedFrom.year,
          dayShiftedFrom.month,
          dayShiftedFrom.day,
          newMinOfDay ~/ 60,
          newMinOfDay % 60,
        );
      }
      nextTo = nextFrom.add(duration);
    } else if (_interactionMode == _InteractionMode.resizeTop) {
      nextFrom = initialFrom.add(Duration(minutes: snappedDeltaMinutes));
      final DateTime maxFrom = initialTo.subtract(const Duration(minutes: 15));
      if (nextFrom.isAfter(maxFrom)) {
        nextFrom = maxFrom;
      }
      nextTo = initialTo;
    } else if (_interactionMode == _InteractionMode.resizeBottom) {
      nextFrom = initialFrom;
      nextTo = initialTo.add(Duration(minutes: snappedDeltaMinutes));
      final DateTime minTo = initialFrom.add(const Duration(minutes: 15));
      if (nextTo.isBefore(minTo)) {
        nextTo = minTo;
      }
    }

    if (_previewFrom != nextFrom ||
        _previewTo != nextTo ||
        _previewDayIndex != nextDayIndex) {
      setState(() {
        _previewFrom = nextFrom;
        _previewTo = nextTo;
        _previewDayIndex = nextDayIndex;
      });
    }
  }

  void _endCardInteraction(Offset upGlobalPos) {
    _unlockCalendarScroll();
    if (!mounted ||
        _interactionMode == _InteractionMode.none ||
        _activeHit == null) {
      _cancelCardInteraction();
      return;
    }
    final appState = Provider.of<AppState>(context, listen: false);
    final hit = _activeHit!;
    final DateTime newFrom = _previewFrom ?? hit.occurrence.fullFrom;
    final DateTime newTo = _previewTo ?? hit.occurrence.fullTo;
    final bool isResize =
        _interactionMode == _InteractionMode.resizeTop ||
        _interactionMode == _InteractionMode.resizeBottom;

    setState(() {
      _interactionMode = _InteractionMode.none;
      _activeHit = null;
      _previewFrom = null;
      _previewTo = null;
      _manipulatedCardId = null;
      _manipulatedCardFrom = null;
      _calendarMouseCursor = SystemMouseCursors.basic;
    });

    if (newFrom != hit.occurrence.fullFrom || newTo != hit.occurrence.fullTo) {
      _commitMoveOrResize(
        appState: appState,
        item: hit.occurrence.originalItem,
        occurrenceStart: hit.occurrence.fullFrom,
        newFrom: newFrom,
        newTo: newTo,
        isResize: isResize,
      );
    }
  }

  void _cancelCardInteraction() {
    _unlockCalendarScroll();
    if (!mounted) return;
    if (_interactionMode != _InteractionMode.none ||
        _activeHit != null ||
        _manipulatedCardId != null) {
      setState(() {
        _interactionMode = _InteractionMode.none;
        _activeHit = null;
        _previewFrom = null;
        _previewTo = null;
        _manipulatedCardId = null;
        _manipulatedCardFrom = null;
        _calendarMouseCursor = SystemMouseCursors.basic;
      });
    }
  }

  void _commitMoveOrResize({
    required AppState appState,
    required dynamic item,
    required DateTime occurrenceStart,
    required DateTime newFrom,
    required DateTime newTo,
    required bool isResize,
  }) {
    if (item is Event) {
      final bool isRecurring =
          item.recurrenceRule != null && item.recurrenceRule!.isNotEmpty;
      if (isRecurring) {
        final Event previousParent = item;
        final DateTime baseStart = item.from.toLocal();
        final DateTime occLocal = occurrenceStart.toLocal();
        final DateTime exceptionDate = DateTime(
          occLocal.year,
          occLocal.month,
          occLocal.day,
          baseStart.hour,
          baseStart.minute,
        );
        final List<DateTime> updatedExceptions = List<DateTime>.from(
          item.recurrenceExceptionDates ?? [],
        )..add(exceptionDate);

        final Event updatedParent = item.copyWith(
          recurrenceExceptionDates: updatedExceptions,
        );
        appState.updateEvent(updatedParent);

        final Event detachedClone = item.copyWith(
          id: IdGenerator.generate('${item.title}_bireysel', date: newFrom),
          from: newFrom,
          to: newTo,
          clearRecurrenceRule: true,
          clearRecurrenceExceptionDates: true,
          createdAt: DateTime.now(),
        );
        appState.addEvent(detachedClone);

        _showUndoSnackBar(
          '"${item.title}" tekrardan çıkarılıp bireysel olarak ${isResize ? "güncellendi" : "taşındı"}',
          () {
            appState.deleteEvent(detachedClone.id);
            appState.updateEvent(previousParent);
          },
        );
      } else {
        final Event previousEvent = item;
        final Event updated = item.copyWith(from: newFrom, to: newTo);
        appState.updateEvent(updated);
        _showUndoSnackBar(
          '"${item.title}" ${isResize ? "süresi güncellendi" : "taşındı"}',
          () {
            appState.updateEvent(previousEvent);
          },
        );
      }
    } else if (item is TaskItem) {
      final bool isRecurring =
          item.recurrenceRule != null && item.recurrenceRule!.isNotEmpty;
      if (isRecurring) {
        final TaskItem previousParent = item;
        final DateTime baseStart = (item.from ?? occurrenceStart).toLocal();
        final DateTime occLocal = occurrenceStart.toLocal();
        final DateTime exceptionDate = DateTime(
          occLocal.year,
          occLocal.month,
          occLocal.day,
          baseStart.hour,
          baseStart.minute,
        );
        final List<DateTime> updatedExceptions = List<DateTime>.from(
          item.recurrenceExceptionDates ?? [],
        )..add(exceptionDate);

        final TaskItem updatedParent = item.copyWith(
          recurrenceExceptionDates: updatedExceptions,
        );
        appState.updateTask(updatedParent);

        final TaskItem detachedClone = item.copyWith(
          id: IdGenerator.generate('${item.title}_bireysel', date: newFrom),
          from: newFrom,
          to: newTo,
          clearRecurrenceRule: true,
          clearRecurrenceExceptionDates: true,
          createdAt: DateTime.now(),
        );
        appState.addTask(detachedClone);

        _showUndoSnackBar(
          '"${item.title}" tekrardan çıkarılıp bireysel olarak ${isResize ? "güncellendi" : "taşındı"}',
          () {
            appState.deleteTask(detachedClone.id);
            appState.updateTask(previousParent);
          },
        );
      } else {
        final TaskItem previousTask = item;
        final TaskItem updated = item.copyWith(from: newFrom, to: newTo);
        appState.updateTask(updated);
        _showUndoSnackBar(
          '"${item.title}" ${isResize ? "süresi güncellendi" : "taşındı"}',
          () {
            appState.updateTask(previousTask);
          },
        );
      }
    }
  }

  void _copyItemToClipboard(dynamic item, DateTime? occurrenceFrom) {
    if (item is! Event && item is! TaskItem) return;
    setState(() {
      _copiedItem = item;
      _copiedOccurrenceFrom = occurrenceFrom;
    });
    final String title = item is Event
        ? item.title
        : (item as TaskItem).title;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '📋 "$title" kopyalandı. Yapıştırmak istediğiniz güne/saate tıklayın veya Ctrl+V basın.',
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _pasteCopiedItemAt(
    DateTime targetDateTime,
    AppState appState, {
    required bool isMonthOrDateOnly,
  }) {
    final dynamic item = _copiedItem;
    if (item == null) return;

    if (item is Event) {
      final DateTime baseFrom = (_copiedOccurrenceFrom ?? item.from).toLocal();
      final Duration duration = item.to.difference(item.from);
      final DateTime newFrom = (item.isAllDay || isMonthOrDateOnly)
          ? DateTime(
              targetDateTime.year,
              targetDateTime.month,
              targetDateTime.day,
              baseFrom.hour,
              baseFrom.minute,
            )
          : DateTime(
              targetDateTime.year,
              targetDateTime.month,
              targetDateTime.day,
              targetDateTime.hour,
              targetDateTime.minute,
            );
      final DateTime newTo = newFrom.add(duration);
      final Event pasted = item.copyWith(
        id: IdGenerator.generate('${item.title}_kopya', date: newFrom),
        from: newFrom,
        to: newTo,
        clearRecurrenceRule: true,
        clearRecurrenceExceptionDates: true,
        createdAt: DateTime.now(),
      );
      appState.addEvent(pasted);
      final String timeStr =
          '${newFrom.day}.${newFrom.month}.${newFrom.year} ${newFrom.hour.toString().padLeft(2, '0')}:${newFrom.minute.toString().padLeft(2, '0')}';
      _showUndoSnackBar('"${item.title}" ($timeStr) yapıştırıldı', () {
        appState.deleteEvent(pasted.id);
      });
    } else if (item is TaskItem) {
      final DateTime baseFrom =
          (_copiedOccurrenceFrom ?? item.from ?? DateTime.now()).toLocal();
      final Duration duration = (item.from != null && item.to != null)
          ? item.to!.difference(item.from!)
          : const Duration(hours: 1);
      final DateTime newFrom = (item.isAllDay || isMonthOrDateOnly)
          ? DateTime(
              targetDateTime.year,
              targetDateTime.month,
              targetDateTime.day,
              baseFrom.hour,
              baseFrom.minute,
            )
          : DateTime(
              targetDateTime.year,
              targetDateTime.month,
              targetDateTime.day,
              targetDateTime.hour,
              targetDateTime.minute,
            );
      final DateTime newTo = newFrom.add(duration);
      final TaskItem pasted = item.copyWith(
        id: IdGenerator.generate('${item.title}_kopya', date: newFrom),
        from: newFrom,
        to: newTo,
        isCompleted: false,
        clearCompletedDate: true,
        clearRecurrenceRule: true,
        clearRecurrenceExceptionDates: true,
        createdAt: DateTime.now(),
      );
      appState.addTask(pasted);
      final String timeStr =
          '${newFrom.day}.${newFrom.month}.${newFrom.year} ${newFrom.hour.toString().padLeft(2, '0')}:${newFrom.minute.toString().padLeft(2, '0')}';
      _showUndoSnackBar('"${item.title}" ($timeStr) yapıştırıldı', () {
        appState.deleteTask(pasted.id);
      });
    }
  }

  Future<void> _showCopyToDateDialog(
    BuildContext context,
    dynamic item,
    DateTime? occurrenceFrom,
    AppState appState,
  ) async {
    final DateTime initialDate =
        (occurrenceFrom ??
                (item is Event
                    ? item.from
                    : (item is TaskItem ? item.from : null)) ??
                DateTime.now())
            .toLocal();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Kopyalanacak Günü Seçin',
      confirmText: 'Devam',
      cancelText: 'İptal',
    );
    if (pickedDate == null || !mounted) return;

    final bool isAllDay = item is Event
        ? item.isAllDay
        : (item is TaskItem ? item.isAllDay : false);
    TimeOfDay pickedTime = TimeOfDay(
      hour: initialDate.hour,
      minute: initialDate.minute,
    );

    if (!isAllDay) {
      final TimeOfDay? selectedTime = await showTimePicker(
        context: context,
        initialTime: pickedTime,
        helpText: 'Başlangıç Saatini Seçin (Aynı kalması için Tamam\'a basın)',
        confirmText: 'Kopyala',
        cancelText: 'İptal',
      );
      if (selectedTime == null || !mounted) return;
      pickedTime = selectedTime;
    }

    final DateTime targetDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (item is Event) {
      final Duration duration = item.to.difference(item.from);
      final DateTime newTo = targetDateTime.add(duration);
      final Event copy = item.copyWith(
        id: IdGenerator.generate('${item.title}_kopya', date: targetDateTime),
        from: targetDateTime,
        to: newTo,
        clearRecurrenceRule: true,
        clearRecurrenceExceptionDates: true,
        createdAt: DateTime.now(),
      );
      appState.addEvent(copy);
      _showUndoSnackBar(
        '"${item.title}" ${pickedDate.day}.${pickedDate.month}.${pickedDate.year} gününe kopyalandı',
        () {
          appState.deleteEvent(copy.id);
        },
      );
    } else if (item is TaskItem) {
      final Duration duration = (item.from != null && item.to != null)
          ? item.to!.difference(item.from!)
          : const Duration(hours: 1);
      final DateTime newTo = targetDateTime.add(duration);
      final TaskItem copy = item.copyWith(
        id: IdGenerator.generate('${item.title}_kopya', date: targetDateTime),
        from: targetDateTime,
        to: newTo,
        isCompleted: false,
        clearCompletedDate: true,
        clearRecurrenceRule: true,
        clearRecurrenceExceptionDates: true,
        createdAt: DateTime.now(),
      );
      appState.addTask(copy);
      _showUndoSnackBar(
        '"${item.title}" ${pickedDate.day}.${pickedDate.month}.${pickedDate.year} gününe kopyalandı',
        () {
          appState.deleteTask(copy.id);
        },
      );
    }
  }

  bool _isEditableTextFocused() {
    final focusNode = FocusManager.instance.primaryFocus;
    final focusContext = focusNode?.context;
    if (focusContext == null) return false;
    final w = focusContext.widget;
    if (w is EditableText || w is TextField || w is TextFormField) {
      return true;
    }
    if (focusContext.findAncestorStateOfType<EditableTextState>() != null ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null ||
        focusContext.findAncestorWidgetOfExactType<TextField>() != null ||
        focusContext.findAncestorWidgetOfExactType<TextFormField>() != null) {
      return true;
    }
    return false;
  }

  bool _isCalendarGridActive() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    if (Scaffold.maybeOf(context)?.isDrawerOpen == true) return false;
    if (_isEditableTextFocused()) return false;

    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.showPlanView ||
        appState.showSeritView ||
        appState.showRecentView ||
        appState.showDailyNotesView) {
      return false;
    }
    return appState.calendarView == CalendarView.day ||
        appState.calendarView == CalendarView.week ||
        appState.calendarView == CalendarView.month;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (!_isCalendarGridActive()) return false;

    final bool isCtrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_manipulatedCardId != null) {
        _clearCardManipulation();
        return true;
      }
      if (_copiedItem != null) {
        setState(() {
          _copiedItem = null;
          _copiedOccurrenceFrom = null;
        });
        return true;
      }
      return false;
    }

    if (isCtrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      final bool isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isShift) {
        if (_redoStack.isNotEmpty) {
          _performLastRedo();
          return true;
        }
        return false;
      }
      if (_undoStack.isNotEmpty) {
        _performLastUndo();
        return true;
      }
      return false;
    }

    if (isCtrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyY) {
      if (_redoStack.isNotEmpty) {
        _performLastRedo();
        return true;
      }
      return false;
    }

    if (isCtrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_copiedItem != null) {
        final appState = Provider.of<AppState>(context, listen: false);
        final DateTime target =
            _lastHoveredDateTime ??
            appState.calendarController.selectedDate ??
            appState.calendarController.displayDate ??
            DateTime.now();
        final bool dateOnly =
            appState.calendarView == CalendarView.month ||
            _pasteUseOriginalTime ||
            _lastHoveredDateTime == null;
        _pasteCopiedItemAt(target, appState, isMonthOrDateOnly: dateOnly);
        return true;
      }
    }
    return false;
  }

  void _applyHistorySnapshot(
    AppState appState,
    _CalendarHistorySnapshot target,
  ) {
    final nowEventIds = appState.events.map((e) => e.id).toSet();
    final targetEventIds = target.events.map((e) => e.id).toSet();
    for (final id in nowEventIds.difference(targetEventIds)) {
      appState.deleteEvent(id);
    }
    for (final e in target.events) {
      if (!nowEventIds.contains(e.id)) {
        appState.addEvent(e);
      } else {
        final current = appState.getEventById(e.id);
        if (current == null ||
            jsonEncode(current.toJson()) != target.eventJsonById[e.id]) {
          appState.updateEvent(e);
        }
      }
    }

    final nowTaskIds = appState.tasks.map((t) => t.id).toSet();
    final targetTaskIds = target.tasks.map((t) => t.id).toSet();
    for (final id in nowTaskIds.difference(targetTaskIds)) {
      appState.deleteTask(id, forceDeleteParent: true);
    }
    for (final t in target.tasks) {
      if (!nowTaskIds.contains(t.id)) {
        appState.addTask(t);
      } else {
        final idx = appState.tasks.indexWhere((x) => x.id == t.id);
        if (idx == -1 ||
            jsonEncode(appState.tasks[idx].toJson()) !=
                target.taskJsonById[t.id]) {
          appState.updateTask(t);
        }
      }
    }
  }

  void _pushUndoEntry(
    String message,
    VoidCallback onUndo, {
    VoidCallback? onRedo,
    bool clearRedo = true,
  }) {
    if (clearRedo) {
      _redoStack.clear();
    }
    _undoStack.add(
      _CalendarUndoEntry(message: message, onUndo: onUndo, onRedo: onRedo),
    );
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
  }

  void _executeUndoEntry(_CalendarUndoEntry entry, {bool showSnack = true}) {
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final afterSnapshot = _CalendarHistorySnapshot.capture(appState);
    entry.onUndo();
    final beforeSnapshot = _CalendarHistorySnapshot.capture(appState);

    final redoEntry = _CalendarUndoEntry(
      message: entry.message,
      onUndo: () => _applyHistorySnapshot(appState, beforeSnapshot),
      onRedo: entry.onRedo ?? () => _applyHistorySnapshot(appState, afterSnapshot),
    );
    _redoStack.add(redoEntry);
    if (_redoStack.length > 30) {
      _redoStack.removeAt(0);
    }

    if (showSnack) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geri alındı: ${entry.message}'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          showCloseIcon: true,
          closeIconColor: Colors.white70,
          action: SnackBarAction(
            label: 'İleri Al (Ctrl+Y)',
            textColor: Colors.amber,
            onPressed: () {
              if (_redoStack.isNotEmpty) {
                _performLastRedo();
              }
            },
          ),
        ),
      );
    }
  }

  void _performLastUndo() {
    if (_undoStack.isEmpty || !mounted) return;
    final entry = _undoStack.removeLast();
    _executeUndoEntry(entry, showSnack: true);
  }

  void _performLastRedo() {
    if (_redoStack.isEmpty || !mounted) return;
    final entry = _redoStack.removeLast();
    if (entry.onRedo != null) {
      entry.onRedo!();
    }
    _pushUndoEntry(
      entry.message,
      entry.onUndo,
      onRedo: entry.onRedo,
      clearRedo: false,
    );
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('İleri alındı: ${entry.message}'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCloseIcon: true,
        closeIconColor: Colors.white70,
        action: SnackBarAction(
          label: 'Geri Al (Ctrl+Z)',
          textColor: Colors.amber,
          onPressed: () {
            if (_undoStack.isNotEmpty) {
              _performLastUndo();
            }
          },
        ),
      ),
    );
  }

  Future<void> _pushRouteWithSnapshotUndo({
    required AppState appState,
    required String actionLabel,
    required Widget Function(BuildContext) builder,
    List<Event>? preCapturedEvents,
    List<TaskItem>? preCapturedTasks,
  }) async {
    final List<Event> prevEvents =
        preCapturedEvents ?? List<Event>.from(appState.events);
    final List<TaskItem> prevTasks =
        preCapturedTasks ?? List<TaskItem>.from(appState.tasks);
    final Map<String, String> prevEventMap = {
      for (final e in prevEvents) e.id: jsonEncode(e.toJson()),
    };
    final Map<String, String> prevTaskMap = {
      for (final t in prevTasks) t.id: jsonEncode(t.toJson()),
    };

    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    if (!mounted) return;

    final List<Event> curEvents = List<Event>.from(appState.events);
    final List<TaskItem> curTasks = List<TaskItem>.from(appState.tasks);
    final Map<String, String> curEventMap = {
      for (final e in curEvents) e.id: jsonEncode(e.toJson()),
    };
    final Map<String, String> curTaskMap = {
      for (final t in curTasks) t.id: jsonEncode(t.toJson()),
    };

    bool hasDiff =
        prevEventMap.length != curEventMap.length ||
        prevTaskMap.length != curTaskMap.length;
    if (!hasDiff) {
      for (final entry in curEventMap.entries) {
        if (prevEventMap[entry.key] != entry.value) {
          hasDiff = true;
          break;
        }
      }
    }
    if (!hasDiff) {
      for (final entry in curTaskMap.entries) {
        if (prevTaskMap[entry.key] != entry.value) {
          hasDiff = true;
          break;
        }
      }
    }

    if (hasDiff) {
      _pushUndoEntry(actionLabel, () {
        final nowEventIds = appState.events.map((e) => e.id).toSet();
        final oldEventIds = prevEvents.map((e) => e.id).toSet();
        for (final id in nowEventIds.difference(oldEventIds)) {
          appState.deleteEvent(id);
        }
        for (final e in prevEvents) {
          if (!nowEventIds.contains(e.id)) {
            appState.addEvent(e);
          } else {
            final current = appState.getEventById(e.id);
            if (current == null ||
                jsonEncode(current.toJson()) != prevEventMap[e.id]) {
              appState.updateEvent(e);
            }
          }
        }

        final nowTaskIds = appState.tasks.map((t) => t.id).toSet();
        final oldTaskIds = prevTasks.map((t) => t.id).toSet();
        for (final id in nowTaskIds.difference(oldTaskIds)) {
          appState.deleteTask(id, forceDeleteParent: true);
        }
        for (final t in prevTasks) {
          if (!nowTaskIds.contains(t.id)) {
            appState.addTask(t);
          } else {
            final idx = appState.tasks.indexWhere((x) => x.id == t.id);
            if (idx == -1 ||
                jsonEncode(appState.tasks[idx].toJson()) != prevTaskMap[t.id]) {
              appState.updateTask(t);
            }
          }
        }
      });
    }
  }

  void _showUndoSnackBar(String message, VoidCallback? onUndo) {
    _CalendarUndoEntry? entry;
    if (onUndo != null) {
      _redoStack.clear();
      entry = _CalendarUndoEntry(message: message, onUndo: onUndo);
      _undoStack.add(entry);
      if (_undoStack.length > 30) {
        _undoStack.removeAt(0);
      }
    }
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
                label: 'Geri Al (Ctrl+Z)',
                textColor: Colors.amber,
                onPressed: () {
                  if (entry != null && _undoStack.contains(entry)) {
                    _undoStack.remove(entry);
                    _executeUndoEntry(entry, showSnack: false);
                  } else if (entry != null) {
                    _executeUndoEntry(entry, showSnack: false);
                  } else {
                    onUndo();
                  }
                },
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

      if (!lower.contains('freq=monthly') && !lower.contains('freq=yearly')) {
        return;
      }

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

    // Add all-day events on this day (non-recurring only;
    // recurring all-day events are handled natively in calendarItems)
    for (var e in appState.filteredEvents) {
      if (!e.isAllDay) continue;
      // Skip recurring events – they are added directly to calendarItems
      // with their recurrenceRule so Syncfusion can render all occurrences.
      if (e.recurrenceRule != null && e.recurrenceRule!.isNotEmpty) continue;
      if (DateTime(e.from.year, e.from.month, e.from.day) == normalizedDate) {
        result.add(e);
      }
    }

    // Add all-day tasks on this day (non-recurring only;
    // recurring all-day tasks are handled natively in calendarItems)
    final List<TaskItem> tasks = appState.filteredTasks
        .where((t) => t.from != null)
        .toList();
    final List<TaskItem> dayTasks = [];

    for (var t in tasks) {
      if (!t.isAllDay) continue;
      // Skip recurring tasks – they are added directly to calendarItems
      if (t.recurrenceRule != null && t.recurrenceRule!.isNotEmpty) continue;
      if (DateTime(t.from!.year, t.from!.month, t.from!.day) ==
          normalizedDate) {
        dayTasks.add(t);
      }
    }

    // Add rollover tasks if date is today
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (normalizedDate == todayStart) {
      for (var t in tasks) {
        final bool isCompletedToday = t.isCompleted &&
            t.completedDate != null &&
            DateTime(t.completedDate!.year, t.completedDate!.month, t.completedDate!.day) == todayStart;

        if (!t.isCompleted || isCompletedToday) {
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
                  title: t.isCompleted ? t.title : '⚠️ ${t.title}',
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
                  completedDate: t.completedDate,
                ),
              );
            }
          } else if (!t.isCompleted) {
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
                  break; // Only show the single oldest uncompleted occurrence
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    // Sort tasks chronologically by 'from' date, fallback to createdAt descending
    dayTasks.sort((a, b) {
      if (a.from == null && b.from == null)
        return b.createdAt.compareTo(a.createdAt);
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

  int _compareOccurrences(OccurrenceInfo a, OccurrenceInfo b) {
    final aStartMin = DateTime(
      a.from.year,
      a.from.month,
      a.from.day,
      a.from.hour,
      a.from.minute,
    );
    final bStartMin = DateTime(
      b.from.year,
      b.from.month,
      b.from.day,
      b.from.hour,
      b.from.minute,
    );
    int comp = aStartMin.compareTo(bStartMin);
    if (comp != 0) return comp;

    // Rule 1: Earlier created event is always placed underneath (first)
    comp = a.createdAt.compareTo(b.createdAt);
    if (comp != 0) return comp;

    final durA = a.to.difference(a.from);
    final durB = b.to.difference(b.from);
    comp = durB.compareTo(durA);
    if (comp != 0) return comp;

    return a.id.compareTo(b.id);
  }

  List<OccurrenceInfo> _collectDayOccurrences(
    DateTime targetDay,
    AppState appState,
  ) {
    final dayStart = DateTime(targetDay.year, targetDay.month, targetDay.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final searchStart = dayStart.subtract(const Duration(days: 1));
    final List<OccurrenceInfo> occurrences = [];

    // Filter and expand events
    for (var e in appState.filteredEvents) {
      if (e.isAllDay) continue;
      if (e.from.isAtSameMomentAs(e.to)) continue; // Reminder

      if (e.recurrenceRule == null || e.recurrenceRule!.isEmpty) {
        final eFromLocal = e.from.toLocal();
        final eToLocal = e.to.toLocal();
        if (eFromLocal.isBefore(dayEnd) && eToLocal.isAfter(dayStart)) {
          final rawFrom = DateTime(
            eFromLocal.year,
            eFromLocal.month,
            eFromLocal.day,
            eFromLocal.hour,
            eFromLocal.minute,
          );
          final rawTo = DateTime(
            eToLocal.year,
            eToLocal.month,
            eToLocal.day,
            eToLocal.hour,
            eToLocal.minute,
          );
          final clampedFrom = rawFrom.isBefore(dayStart) ? dayStart : rawFrom;
          final clampedTo = rawTo.isAfter(dayEnd) ? dayEnd : rawTo;
          if (clampedFrom.isBefore(clampedTo)) {
            occurrences.add(
              OccurrenceInfo(
                originalItem: e,
                id: e.id,
                from: clampedFrom,
                to: clampedTo,
                fullFrom: rawFrom,
                fullTo: rawTo,
                createdAt: e.createdAt,
              ),
            );
          }
        }
      } else {
        try {
          final sanitizedRule = _sanitizeRRule(e.recurrenceRule, e.from)!;
          final instances = RecurrenceHelper.getOccurrences(
            rrule: sanitizedRule,
            startDate: e.from,
            specificStartDate: e.from.isUtc
                ? searchStart.toUtc()
                : searchStart.toLocal(),
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
            final occStart = DateTime(
              dateLocal.year,
              dateLocal.month,
              dateLocal.day,
              dateLocal.hour,
              dateLocal.minute,
            );
            final occEndRaw = dateLocal.add(duration);
            final occEnd = DateTime(
              occEndRaw.year,
              occEndRaw.month,
              occEndRaw.day,
              occEndRaw.hour,
              occEndRaw.minute,
            );
            if (occStart.isBefore(dayEnd) && occEnd.isAfter(dayStart)) {
              final clampedFrom =
                  occStart.isBefore(dayStart) ? dayStart : occStart;
              final clampedTo = occEnd.isAfter(dayEnd) ? dayEnd : occEnd;
              if (clampedFrom.isBefore(clampedTo)) {
                occurrences.add(
                  OccurrenceInfo(
                    originalItem: e,
                    id: e.id,
                    from: clampedFrom,
                    to: clampedTo,
                    fullFrom: occStart,
                    fullTo: occEnd,
                    createdAt: e.createdAt,
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    // Filter and expand tasks
    for (var t in appState.filteredTasks) {
      if (t.from == null || t.isAllDay) continue;
      final rawTTo = t.to ?? t.from!.add(const Duration(hours: 1));
      if (t.from!.isAtSameMomentAs(rawTTo)) continue; // Reminder

      if (t.recurrenceRule == null || t.recurrenceRule!.isEmpty) {
        final tFromLocal = t.from!.toLocal();
        final tToLocal = rawTTo.toLocal();
        if (tFromLocal.isBefore(dayEnd) && tToLocal.isAfter(dayStart)) {
          final rawFrom = DateTime(
            tFromLocal.year,
            tFromLocal.month,
            tFromLocal.day,
            tFromLocal.hour,
            tFromLocal.minute,
          );
          final rawTo = DateTime(
            tToLocal.year,
            tToLocal.month,
            tToLocal.day,
            tToLocal.hour,
            tToLocal.minute,
          );
          final clampedFrom = rawFrom.isBefore(dayStart) ? dayStart : rawFrom;
          final clampedTo = rawTo.isAfter(dayEnd) ? dayEnd : rawTo;
          if (clampedFrom.isBefore(clampedTo)) {
            occurrences.add(
              OccurrenceInfo(
                originalItem: t,
                id: t.id,
                from: clampedFrom,
                to: clampedTo,
                fullFrom: rawFrom,
                fullTo: rawTo,
                createdAt: t.createdAt,
              ),
            );
          }
        }
      } else {
        try {
          final sanitizedRule = _sanitizeRRule(t.recurrenceRule, t.from!)!;
          final instances = RecurrenceHelper.getOccurrences(
            rrule: sanitizedRule,
            startDate: t.from!,
            specificStartDate: t.from!.isUtc
                ? searchStart.toUtc()
                : searchStart.toLocal(),
            specificEndDate: t.from!.isUtc
                ? dayEnd.subtract(const Duration(milliseconds: 1)).toUtc()
                : dayEnd.subtract(const Duration(milliseconds: 1)).toLocal(),
          );
          final duration = rawTTo.difference(t.from!);
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
            final occStart = DateTime(
              dateLocal.year,
              dateLocal.month,
              dateLocal.day,
              dateLocal.hour,
              dateLocal.minute,
            );
            final occEndRaw = dateLocal.add(duration);
            final occEnd = DateTime(
              occEndRaw.year,
              occEndRaw.month,
              occEndRaw.day,
              occEndRaw.hour,
              occEndRaw.minute,
            );
            if (occStart.isBefore(dayEnd) && occEnd.isAfter(dayStart)) {
              final clampedFrom =
                  occStart.isBefore(dayStart) ? dayStart : occStart;
              final clampedTo = occEnd.isAfter(dayEnd) ? dayEnd : occEnd;
              if (clampedFrom.isBefore(clampedTo)) {
                occurrences.add(
                  OccurrenceInfo(
                    originalItem: t,
                    id: t.id,
                    from: clampedFrom,
                    to: clampedTo,
                    fullFrom: occStart,
                    fullTo: occEnd,
                    createdAt: t.createdAt,
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    occurrences.sort(_compareOccurrences);
    return occurrences;
  }

  List<Map<String, double>> _computeDayOverlapLayouts({
    required List<OccurrenceInfo> occurrences,
    required double activeIntervalHeight,
    required double fontSizeMultiplier,
  }) {
    final int n = occurrences.length;
    if (n == 0) return const [];

    // Estimate vertical height of the title area in minutes:
    // If two overlapping events start within this window, their titles collide (Rule 2.1).
    // Otherwise, the earlier event's title is unobstructed above the later event (Rule 2.2).
    final double titleHeightPx = (20.0 * fontSizeMultiplier).clamp(16.0, 32.0);
    final int titleCollisionMinutes =
        ((titleHeightPx / activeIntervalHeight) * 60.0).ceil().clamp(14, 40);

    const double indentStep = 0.12;
    const double maxBaseLeft = 0.56;

    final List<double> leftRatios = List.filled(n, 0.0);
    final List<double> widthRatios = List.filled(n, 1.0);
    final List<double> textWidthRatios = List.filled(n, 1.0);
    final List<double> groupBaseLefts = List.filled(n, 0.0);

    int i = 0;
    while (i < n) {
      final anchor = occurrences[i];
      final List<int> group = [i];
      DateTime groupMinEnd = anchor.to;
      DateTime lastStart = anchor.from;

      int j = i + 1;
      while (j < n) {
        final cand = occurrences[j];
        final int diffFromLastMin = cand.from.difference(lastStart).inMinutes;
        if (cand.from.isBefore(groupMinEnd) &&
            diffFromLastMin < titleCollisionMinutes) {
          group.add(j);
          if (cand.to.isBefore(groupMinEnd)) {
            groupMinEnd = cand.to;
          }
          lastStart = cand.from;
          j++;
        } else {
          break;
        }
      }

      // Check active underlying occurrences that started before this group
      double baseLeft = 0.0;
      for (int u = 0; u < i; u++) {
        final under = occurrences[u];
        if (under.to.isAfter(anchor.from)) {
          final int diffMin = anchor.from.difference(under.from).inMinutes;
          if (diffMin < titleCollisionMinutes) {
            // Underlying event's title still collides vertically with anchor
            final double rightOfUnderTitle =
                leftRatios[u] + textWidthRatios[u];
            if (rightOfUnderTitle > baseLeft) {
              baseLeft = rightOfUnderTitle;
            }
          } else {
            // Rule 2.2: No title collision -> shift slightly to the right
            final double shifted = groupBaseLefts[u] + indentStep;
            if (shifted > baseLeft) {
              baseLeft = shifted;
            }
          }
        }
      }
      if (baseLeft > maxBaseLeft) {
        baseLeft = maxBaseLeft;
      }

      final int k = group.length;
      final double availWidth = (1.0 - baseLeft).clamp(0.15, 1.0);

      if (k == 1) {
        final int idx = group[0];
        groupBaseLefts[idx] = baseLeft;
        leftRatios[idx] = baseLeft;
        widthRatios[idx] = availWidth;
        textWidthRatios[idx] = availWidth;
      } else {
        // Rule 2.1: Title collision among k events -> split available width into k equal parts
        final double partWidth = availWidth / k;
        for (int m = 0; m < k; m++) {
          final int idx = group[m];
          groupBaseLefts[idx] = baseLeft;
          leftRatios[idx] = baseLeft + m * partWidth;
          textWidthRatios[idx] = partWidth;

          if (m == k - 1) {
            widthRatios[idx] = partWidth;
          } else {
            final int nextIdx = group[m + 1];
            if (occurrences[idx].to.isAfter(occurrences[nextIdx].to)) {
              widthRatios[idx] = math.max(
                partWidth,
                (availWidth - m * partWidth) * 0.85,
              );
            } else {
              widthRatios[idx] = partWidth;
            }
          }
        }
      }

      i += k;
    }

    final List<Map<String, double>> results = [];
    for (int idx = 0; idx < n; idx++) {
      final occ = occurrences[idx];
      int overlapCount = 0;
      int lowerOverlapCount = 0;
      for (int other = 0; other < n; other++) {
        final o = occurrences[other];
        if (o.from.isBefore(occ.to) && o.to.isAfter(occ.from)) {
          overlapCount++;
          if (other < idx) {
            lowerOverlapCount++;
          }
        }
      }
      results.add({
        'leftRatio': leftRatios[idx],
        'widthRatio': widthRatios[idx],
        'textWidthRatio': textWidthRatios[idx],
        'zIndex': lowerOverlapCount.toDouble(),
        'totalOverlaps': math.max(1, overlapCount).toDouble(),
      });
    }
    return results;
  }

  int _getSortedSlotIndex({
    required dynamic appointment,
    required DateTime actualFrom,
    required DateTime actualTo,
    required AppState appState,
  }) {
    final actualFromLocal = actualFrom.toLocal();
    final occurrences = _collectDayOccurrences(actualFromLocal, appState);
    if (occurrences.isEmpty) return 0;

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
        final diff = (occ.from.difference(actualFromLocal)).inMilliseconds.abs();
        if (diff < minDiffMs) {
          minDiffMs = diff;
          currentOcc = occ;
        }
      }
    }

    if (currentOcc == null) return 0;

    final overlapping = occurrences.where((occ) {
      return occ.from.isBefore(currentOcc!.to) &&
          occ.to.isAfter(currentOcc.from);
    }).toList();

    final int index = overlapping.indexOf(currentOcc);
    return index >= 0 ? index : 0;
  }

  Map<String, double> _getOverlapLayoutInfo({
    required dynamic appointment,
    required DateTime actualFrom,
    required DateTime actualTo,
    required AppState appState,
    required double activeIntervalHeight,
  }) {
    final actualFromLocal = actualFrom.toLocal();
    final actualToLocal = actualTo.toLocal();
    final occurrences = _collectDayOccurrences(actualFromLocal, appState);
    if (occurrences.isEmpty) {
      return const {
        'leftRatio': 0.0,
        'widthRatio': 1.0,
        'textWidthRatio': 1.0,
        'zIndex': 0.0,
        'totalOverlaps': 1.0,
      };
    }

    final layouts = _computeDayOverlapLayouts(
      occurrences: occurrences,
      activeIntervalHeight: activeIntervalHeight,
      fontSizeMultiplier: appState.fontSizeMultiplier,
    );

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

    int matchedIndex = -1;
    int minDiffMs = 999999999;
    for (int i = 0; i < occurrences.length; i++) {
      final occ = occurrences[i];
      final bool isMatch =
          occ.id == currentId ||
          (currentId.isNotEmpty && currentId.startsWith(occ.id)) ||
          (occ.id.isNotEmpty && occ.id.startsWith(currentId));
      if (isMatch) {
        final diff =
            (occ.from.difference(actualFromLocal)).inMilliseconds.abs() +
            (occ.to.difference(actualToLocal)).inMilliseconds.abs();
        if (diff < minDiffMs) {
          minDiffMs = diff;
          matchedIndex = i;
        }
      }
    }

    if (matchedIndex >= 0 && matchedIndex < layouts.length) {
      return layouts[matchedIndex];
    }

    return const {
      'leftRatio': 0.0,
      'widthRatio': 1.0,
      'textWidthRatio': 1.0,
      'zIndex': 0.0,
      'totalOverlaps': 1.0,
    };
  }

  OccurrenceInfo? _resolveVisualTappedOccurrence({
    required DateTime targetDay,
    required DateTime? tappedTime,
    required double xRatio,
    required AppState appState,
    required double activeIntervalHeight,
    OccurrenceInfo? fallbackOcc,
  }) {
    final occurrences = _collectDayOccurrences(targetDay, appState);
    if (occurrences.isEmpty) return fallbackOcc;

    final layouts = _computeDayOverlapLayouts(
      occurrences: occurrences,
      activeIntervalHeight: activeIntervalHeight,
      fontSizeMultiplier: appState.fontSizeMultiplier,
    );

    // Search from top of Z-order (last) to bottom of Z-order (0)
    for (int i = occurrences.length - 1; i >= 0; i--) {
      final occ = occurrences[i];
      final layout = layouts[i];
      final double left = layout['leftRatio']!;
      final double right = left + layout['widthRatio']!;

      final bool xMatches = xRatio >= (left - 0.02) && xRatio <= (right + 0.02);
      if (!xMatches) continue;

      if (tappedTime != null) {
        if (!tappedTime.isBefore(occ.from) && tappedTime.isBefore(occ.to)) {
          return occ;
        }
      } else if (fallbackOcc != null) {
        if (occ.from.isBefore(fallbackOcc.to) &&
            occ.to.isAfter(fallbackOcc.from)) {
          return occ;
        }
      }
    }
    return fallbackOcc;
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
      strips.add(
        StripItem(
          id: s.id,
          title: s.title,
          startDate: s.startDate,
          endDate: s.endDate,
          color: color,
          originalItem: s,
        ),
      );
    }

    // 2. Add regular Events > 24 hours
    for (var e in appState.filteredEvents) {
      if (e.to.difference(e.from).inMinutes > 1440) {
        Color color = Colors.blue;
        if (e.colorValue != 0) {
          color = Color(e.colorValue);
        }
        strips.add(
          StripItem(
            id: e.id,
            title: e.title,
            startDate: e.from,
            endDate: e.to,
            color: color,
            originalItem: e,
          ),
        );
      }
    }

    // 3. Add regular Tasks > 24 hours
    for (var t in appState.filteredTasks) {
      if (t.from != null && t.to != null) {
        if (t.to!.difference(t.from!).inMinutes > 1440) {
          Color color = Colors.orange;
          final project = appState.projects
              .where((p) => p.id == t.projectId)
              .firstOrNull;
          if (project != null) {
            color = Color(project.colorValue);
          }
          strips.add(
            StripItem(
              id: t.id,
              title: t.title,
              startDate: t.from!,
              endDate: t.to!,
              color: color,
              originalItem: t,
            ),
          );
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
        if (s2.startDate.isBefore(s.endDate) &&
            s2.endDate.isAfter(s.startDate)) {
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
    final bool isStart =
        s.startDate.year == date.year &&
        s.startDate.month == date.month &&
        s.startDate.day == date.day;
    final bool isEnd =
        s.endDate.year == date.year &&
        s.endDate.month == date.month &&
        s.endDate.day == date.day;
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
    if (appState.showPlanView ||
        appState.showSeritView ||
        appState.showRecentView ||
        appState.showDailyNotesView) {
      if (_copiedItem != null || _manipulatedCardId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _copiedItem = null;
              _copiedOccurrenceFrom = null;
              _manipulatedCardId = null;
              _manipulatedCardFrom = null;
            });
          }
        });
      }
      if (appState.showPlanView) {
        return const PlanScreen();
      }
      if (appState.showSeritView) {
        return const AllTimelineScreen();
      }
      if (appState.showRecentView) {
        return const RecentItemsScreen();
      }
      return const DailyNotesScreen();
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
                break; // Only show the single oldest uncompleted occurrence
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

    // Add all-day recurring events/tasks directly so Syncfusion handles
    // their recurrence natively – same pipeline as timed recurring events.
    // Exception dates are returned by EventDataSource.getRecurrenceExceptionDates.
    final allDayRecurringEvents = events
        .where(
          (e) =>
              e.isAllDay &&
              e.recurrenceRule != null &&
              e.recurrenceRule!.isNotEmpty,
        )
        .toList();
    calendarItems.addAll(allDayRecurringEvents);

    final allDayRecurringTasks = tasks
        .where(
          (t) =>
              t.isAllDay &&
              t.from != null &&
              t.recurrenceRule != null &&
              t.recurrenceRule!.isNotEmpty,
        )
        .toList();
    calendarItems.addAll(allDayRecurringTasks);

    // Inject timed clones for short months
    final shortMonthClones = _getShortMonthClones(events, tasks);
    final timedClones = shortMonthClones.where((c) => !c.isAllDay).toList();
    calendarItems.addAll(timedClones);

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
        int remainingTasks = dayTasks.where((t) => !t.isCompleted).length -
            shownItems.whereType<TaskItem>().where((t) => !t.isCompleted).length;

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
        if (item is TaskItem &&
            item.from != null &&
            item.to != null &&
            item.to!.difference(item.from!).inMinutes > 1440) {
          continue;
        }
      }
      finalItems.add(item);
    }

    if (isDay) {
      final displayDate = calendarController.displayDate ?? DateTime.now();
      final dayStart = DateTime(
        displayDate.year,
        displayDate.month,
        displayDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));

      for (var serit in appState.serits) {
        if (!serit.isVisible) continue;
        if (serit.startDate.isBefore(dayEnd) &&
            serit.endDate.isAfter(dayStart)) {
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
        final hasStripOnDay = allStrips.any(
          (s) => s.startDate.isBefore(dateEnd) && s.endDate.isAfter(dateStart),
        );

        if (hasStripOnDay) {
          final hasOtherAllDay = finalItems.any((item) {
            if (item is Event &&
                item.isAllDay &&
                !item.id.startsWith('dummy_')) {
              final itemStart = DateTime(
                item.from.year,
                item.from.month,
                item.from.day,
              );
              return itemStart == dateStart;
            }
            if (item is TaskItem &&
                item.isAllDay &&
                !item.id.startsWith('dummy_')) {
              if (item.from != null) {
                final itemStart = DateTime(
                  item.from!.year,
                  item.from!.month,
                  item.from!.day,
                );
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

    finalItems.sort((a, b) {
      final rawStartA = a is Event
          ? a.from.toLocal()
          : (a is TaskItem
                ? (a.from?.toLocal() ?? DateTime(1970))
                : (a is ProjectEvaluation
                      ? a.sessionDate.toLocal()
                      : DateTime(1970)));
      final rawStartB = b is Event
          ? b.from.toLocal()
          : (b is TaskItem
                ? (b.from?.toLocal() ?? DateTime(1970))
                : (b is ProjectEvaluation
                      ? b.sessionDate.toLocal()
                      : DateTime(1970)));

      final startA = DateTime(
        rawStartA.year,
        rawStartA.month,
        rawStartA.day,
        rawStartA.hour,
        rawStartA.minute,
      );
      final startB = DateTime(
        rawStartB.year,
        rawStartB.month,
        rawStartB.day,
        rawStartB.hour,
        rawStartB.minute,
      );

      final startCompare = startA.compareTo(startB);
      if (startCompare != 0) return startCompare;

      // Rule 1: Earlier created event is always placed underneath (first)
      final createdA = a is Event
          ? a.createdAt
          : (a is TaskItem ? a.createdAt : DateTime(1970));
      final createdB = b is Event
          ? b.createdAt
          : (b is TaskItem ? b.createdAt : DateTime(1970));

      final createdCompare = createdA.compareTo(createdB);
      if (createdCompare != 0) return createdCompare;

      final durA = a is Event
          ? a.to.difference(a.from)
          : (a is TaskItem && a.from != null && a.to != null
                ? a.to!.difference(a.from!)
                : const Duration(hours: 1));
      final durB = b is Event
          ? b.to.difference(b.from)
          : (b is TaskItem && b.from != null && b.to != null
                ? b.to!.difference(b.from!)
                : const Duration(hours: 1));

      final durCompare = durB.compareTo(durA);
      if (durCompare != 0) return durCompare;

      final idA = a is Event ? a.id : (a is TaskItem ? a.id : '');
      final idB = b is Event ? b.id : (b is TaskItem ? b.id : '');
      return idA.compareTo(idB);
    });

    _dataSource.appState = appState;

    final List<dynamic> itemsToSet;
    if (appState.calendarView == CalendarView.month) {
      itemsToSet = finalItems.where((item) {
        if (item is Event && !item.id.startsWith('dummy_')) {
          return item.showInMonthView;
        }
        if (item is TaskItem && !item.id.startsWith('dummy_')) {
          return item.showInMonthView;
        }
        return true;
      }).toList();
    } else {
      itemsToSet = finalItems;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _dataSource.appointments = itemsToSet;
        _dataSource.notifyListeners(CalendarDataSourceAction.reset, itemsToSet);
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

          _lastCalendarWidth = constraints.maxWidth;
          _lastActiveIntervalHeight = activeIntervalHeight;
          _lastStartHour = startHour;
          _lastEndHour = endHour;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  key: _calendarStackKey,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top:
                            (appState.calendarView == CalendarView.day ||
                                appState.calendarView == CalendarView.week)
                            ? 55.0
                            : 0.0,
                      ),
                      child: MouseRegion(
                        cursor: _calendarMouseCursor,
                        onHover: _handleCalendarHover,
                        child: RawGestureDetector(
                          gestures: <Type, GestureRecognizerFactory>{
                            _CalendarInteractionGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _CalendarInteractionGestureRecognizer
                                >(
                                  () => _CalendarInteractionGestureRecognizer(
                                    onHitTest: (globalPos) =>
                                        _hitTestDayWeekCard(globalPos),
                                    isCardManipulated: (hit) =>
                                        _isCardManipulated(
                                          hit.occurrence.id,
                                          hit.occurrence.fullFrom,
                                        ),
                                    onActivateManipulation:
                                        _activateCardManipulation,
                                    onClearManipulation: _clearCardManipulation,
                                    onInteractionStart: _startCardInteraction,
                                    onInteractionUpdate: _updateCardInteraction,
                                    onInteractionEnd: _endCardInteraction,
                                    onInteractionCancel: _cancelCardInteraction,
                                    onCardTap: _handleCardTap,
                                    onLockScroll: _lockCalendarScroll,
                                    onUnlockScroll: _unlockCalendarScroll,
                                    onFocusItem: (occ) {
                                      _lastFocusedItem = occ.originalItem;
                                      _lastFocusedOccurrenceFrom = occ.fullFrom;
                                    },
                                  ),
                                  (_CalendarInteractionGestureRecognizer
                                      instance) {
                                    instance.onHitTest = (globalPos) =>
                                        _hitTestDayWeekCard(globalPos);
                                    instance.isCardManipulated = (hit) =>
                                        _isCardManipulated(
                                          hit.occurrence.id,
                                          hit.occurrence.fullFrom,
                                        );
                                    instance.onActivateManipulation =
                                        _activateCardManipulation;
                                    instance.onClearManipulation =
                                        _clearCardManipulation;
                                    instance.onInteractionStart =
                                        _startCardInteraction;
                                    instance.onInteractionUpdate =
                                        _updateCardInteraction;
                                    instance.onInteractionEnd =
                                        _endCardInteraction;
                                    instance.onInteractionCancel =
                                        _cancelCardInteraction;
                                    instance.onCardTap = _handleCardTap;
                                    instance.onLockScroll = _lockCalendarScroll;
                                    instance.onUnlockScroll =
                                        _unlockCalendarScroll;
                                    instance.onFocusItem = (occ) {
                                      _lastFocusedItem = occ.originalItem;
                                      _lastFocusedOccurrenceFrom = occ.fullFrom;
                                    };
                                  },
                                ),
                          },
                          child: Listener(
                            onPointerDown: _handlePointerDown,
                            onPointerMove: _handlePointerMove,
                            onPointerUp: _handlePointerUp,
                            onPointerCancel: _handlePointerUp,
                            onPointerSignal: (pointerSignal) {
                              if (_isScrollLocked ||
                                  _interactionMode != _InteractionMode.none) {
                                return;
                              }
                              if (pointerSignal is PointerScrollEvent) {
                                final dx = pointerSignal.scrollDelta.dx;
                                final dy = pointerSignal.scrollDelta.dy;
                                if (dx.abs() > dy.abs() && dx.abs() > 15) {
                                  final now = DateTime.now();
                                  if (_lastSwipeTime == null ||
                                      now.difference(_lastSwipeTime!).inMilliseconds > 600) {
                                    _lastSwipeTime = now;
                                    if (dx > 0) {
                                      calendarController.forward?.call();
                                    } else {
                                      calendarController.backward?.call();
                                    }
                                  }
                                }
                              }
                            },
                            child: SfCalendar(
                              controller: calendarController,
                              view: appState.calendarView,
                              firstDayOfWeek: appState.firstDayOfWeek,
                              headerHeight: 0,
                              viewHeaderHeight:
                                  (appState.calendarView == CalendarView.day ||
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
                                  final bool isDayOrWeek =
                                      appState.calendarView ==
                                          CalendarView.day ||
                                      appState.calendarView ==
                                          CalendarView.week;

                                  if (appState.isBulkMode) {
                                    if (isDayOrWeek &&
                                        details.targetElement !=
                                            CalendarElement.allDayPanel &&
                                        details.targetElement !=
                                            CalendarElement.viewHeader &&
                                        _lastPointerGlobalPos != null) {
                                      final hit = _hitTestDayWeekCard(
                                        _lastPointerGlobalPos!,
                                        listenerLocalPos: _lastPointerLocalPos,
                                      );
                                      if (hit != null &&
                                          hit.occurrence.originalItem
                                              is Event) {
                                        final Event e =
                                            hit.occurrence.originalItem
                                                as Event;
                                        if (e.id != 'dummy_t' &&
                                            e.id != 'dummy_e' &&
                                            e.id != 'dummy_eval') {
                                          final String selectionId =
                                              e.recurrenceRule != null
                                              ? "${e.id}_${hit.occurrence.fullFrom.millisecondsSinceEpoch}"
                                              : e.id;
                                          appState.toggleEventSelection(
                                            selectionId,
                                          );
                                        }
                                        return;
                                      }
                                    }
                                    if (details.targetElement ==
                                            CalendarElement.appointment &&
                                        details.appointments!.isNotEmpty) {
                                      final rawAppointment =
                                          details.appointments!.last;
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
                                            occurrenceFrom =
                                                rawAppointment.startTime;
                                          } else {
                                            occurrenceFrom = appointment.from;
                                          }
                                          final String selectionId =
                                              appointment.recurrenceRule != null
                                              ? "${appointment.id}_${occurrenceFrom.millisecondsSinceEpoch}"
                                              : appointment.id;
                                          appState.toggleEventSelection(
                                            selectionId,
                                          );
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
                                    final rawAppointment =
                                        details.appointments!.last;
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
                                    } else if (rawAppointment
                                        is ProjectEvaluation) {
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
                                        _showAllDayItemsSheet(
                                          context,
                                          normalizedDate,
                                        );
                                        return;
                                      }
                                    } else if (appointment is TaskItem) {
                                      isAllDay = appointment.isAllDay;
                                    } else if (appointment
                                        is ProjectEvaluation) {
                                      isAllDay = true;
                                    }

                                    if (isAllDay && date != null) {
                                      final normalizedDate = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                      );
                                      _showAllDayItemsSheet(
                                        context,
                                        normalizedDate,
                                      );
                                    } else {
                                      DateTime? occurrenceTime;
                                      if (rawAppointment is Appointment) {
                                        occurrenceTime =
                                            rawAppointment.startTime;
                                      }
                                      dynamic targetAppointment = appointment;
                                      DateTime? targetTappedDate =
                                          occurrenceTime ??
                                          details.date ??
                                          date;

                                      if (isDayOrWeek &&
                                          _lastPointerGlobalPos != null) {
                                        final hit = _hitTestDayWeekCard(
                                          _lastPointerGlobalPos!,
                                          listenerLocalPos:
                                              _lastPointerLocalPos,
                                        );
                                        if (hit != null) {
                                          targetAppointment =
                                              hit.occurrence.originalItem;
                                          targetTappedDate =
                                              hit.occurrence.fullFrom;
                                        }
                                      }

                                      _lastFocusedItem = targetAppointment;
                                      _lastFocusedOccurrenceFrom =
                                          targetTappedDate;
                                      _showItemDetailsDialog(
                                        context,
                                        targetAppointment,
                                        tappedDate: targetTappedDate,
                                      );
                                    }
                                  } else if (appState.calendarView ==
                                          CalendarView.month &&
                                      details.targetElement ==
                                          CalendarElement.calendarCell &&
                                      details.date != null) {
                                    if (_copiedItem != null) {
                                      _pasteCopiedItemAt(
                                        details.date!,
                                        appState,
                                        isMonthOrDateOnly: true,
                                      );
                                      return;
                                    }
                                    calendarController.displayDate =
                                        details.date;
                                    appState.setCalendarView(CalendarView.day);
                                  } else if (isDayOrWeek &&
                                      details.targetElement ==
                                          CalendarElement.calendarCell &&
                                      details.date != null) {
                                    final tappedTime = details.date!;
                                    if (_lastPointerGlobalPos != null) {
                                      final hit = _hitTestDayWeekCard(
                                        _lastPointerGlobalPos!,
                                        listenerLocalPos: _lastPointerLocalPos,
                                      );
                                      if (hit != null) {
                                        _lastFocusedItem =
                                            hit.occurrence.originalItem;
                                        _lastFocusedOccurrenceFrom =
                                            hit.occurrence.fullFrom;
                                        _showItemDetailsDialog(
                                          context,
                                          hit.occurrence.originalItem,
                                          tappedDate: hit.occurrence.fullFrom,
                                        );
                                        return;
                                      }
                                    }
                                    final double toleranceMinutes = 15.0;
                                    dynamic clickedReminder;

                                    for (var e in appState.filteredEvents) {
                                      if (!e.isAllDay &&
                                          e.from.isAtSameMomentAs(e.to)) {
                                        final diff = e.from
                                            .difference(tappedTime)
                                            .inMinutes
                                            .abs();
                                        if (diff <= toleranceMinutes &&
                                            e.from.day == tappedTime.day) {
                                          clickedReminder = e;
                                          break;
                                        }
                                      }
                                    }

                                    if (clickedReminder == null) {
                                      for (var t in appState.filteredTasks) {
                                        if (t.from != null &&
                                            t.to != null &&
                                            !t.isAllDay &&
                                            t.from!.isAtSameMomentAs(t.to!)) {
                                          final diff = t.from!
                                              .difference(tappedTime)
                                              .inMinutes
                                              .abs();
                                          if (diff <= toleranceMinutes &&
                                              t.from!.day == tappedTime.day) {
                                            clickedReminder = t;
                                            break;
                                          }
                                        }
                                      }
                                    }

                                    if (clickedReminder != null) {
                                      final remDate = clickedReminder is Event
                                          ? clickedReminder.from
                                          : clickedReminder.from;
                                      _lastFocusedItem = clickedReminder;
                                      _lastFocusedOccurrenceFrom = remDate;
                                      _showItemDetailsDialog(
                                        context,
                                        clickedReminder,
                                        tappedDate: remDate,
                                      );
                                      return;
                                    }

                                    if (_copiedItem != null) {
                                      _pasteCopiedItemAt(
                                        _lastHoveredDateTime ?? tappedTime,
                                        appState,
                                        isMonthOrDateOnly:
                                            _pasteUseOriginalTime,
                                      );
                                      return;
                                    }

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
                            if (calendarAppointmentDetails
                                .appointments
                                .isEmpty) {
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
                                appointment.id.startsWith(
                                  'dummy_all_day_placeholder_',
                                )) {
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
                                    ? '📊 ${proj.title}: Pas ${appState.getPasCount(proj.id, appointment.sessionDate)}'
                                    : (proj.evaluationType == 'PERCENTAGE'
                                        ? (appointment.performancePercent != null
                                            ? '📊 ${proj.title}: %${appointment.performancePercent!.toStringAsFixed(0)}'
                                            : (appointment.score > 0
                                                ? '📊 ${proj.title}: %${appointment.score.toStringAsFixed(0)}'
                                                : '📊 ${proj.title}'))
                                        : '📊 ${proj.title}: ${appointment.score.toStringAsFixed(0)} Puan');
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

                            if (title.isEmpty &&
                                rawAppointment is Appointment) {
                              title = rawAppointment.subject;
                            }

                            if (!isDummy &&
                                appState.calendarView ==
                                    CalendarView.schedule &&
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
                              final String? targetProjectId =
                                  appointment is Event
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
                                final bounds =
                                    calendarAppointmentDetails.bounds;
                                final double calendarWidth =
                                    constraints.maxWidth;
                                final int numDays =
                                    appState.calendarView == CalendarView.week
                                    ? 7
                                    : 1;
                                const double timeRulerWidth = 40.0;
                                final double columnWidth =
                                    (calendarWidth - timeRulerWidth) / numDays;
                                final int dayIndex = numDays == 1
                                    ? 0
                                    : ((from.weekday -
                                              appState.firstDayOfWeek) %
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
                                                  color: Colors.white
                                                      .withValues(alpha: 0.85),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                                  9 *
                                                  appState.fontSizeMultiplier,
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
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                                      ? Color(
                                                          project.colorValue,
                                                        )
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
                                // Determine exact rendered column index from SfCalendar's bounds.left
                                // so overnight segments on Day 2 stay in Day 2's column instead of shifting left to Day 1.
                                final int dayIndex = numDays == 1
                                    ? 0
                                    : (((bounds.left - timeRulerWidth + 1.0) /
                                                  columnWidth)
                                              .floor())
                                          .clamp(0, numDays - 1);

                                // Calculate start of column i
                                final double colStart =
                                    timeRulerWidth + dayIndex * columnWidth;

                                DateTime segmentDayStart;
                                if (numDays == 7 &&
                                    _visibleDates.length >= 7) {
                                  final d = _visibleDates[dayIndex];
                                  segmentDayStart = DateTime(
                                    d.year,
                                    d.month,
                                    d.day,
                                  );
                                } else if (numDays == 1) {
                                  final d =
                                      calendarController.displayDate ??
                                      calendarAppointmentDetails.date;
                                  segmentDayStart = DateTime(
                                    d.year,
                                    d.month,
                                    d.day,
                                  );
                                } else {
                                  final fromLoc = from.toLocal();
                                  final int fromDayIdx =
                                      (fromLoc.weekday -
                                          appState.firstDayOfWeek) %
                                      7;
                                  final weekStart = DateTime(
                                    fromLoc.year,
                                    fromLoc.month,
                                    fromLoc.day,
                                  ).subtract(Duration(days: fromDayIdx));
                                  segmentDayStart = weekStart.add(
                                    Duration(days: dayIndex),
                                  );
                                }
                                final DateTime segmentDayEnd = segmentDayStart
                                    .add(const Duration(days: 1));
                                final DateTime fromLocal = from.toLocal();
                                final DateTime toLocal = to.toLocal();
                                final DateTime segFrom =
                                    fromLocal.isBefore(segmentDayStart)
                                    ? segmentDayStart
                                    : fromLocal;
                                final DateTime segTo =
                                    toLocal.isAfter(segmentDayEnd)
                                    ? segmentDayEnd
                                    : toLocal;

                                final overlapInfo = _getOverlapLayoutInfo(
                                  appointment: appointment,
                                  actualFrom: segFrom,
                                  actualTo: segTo,
                                  appState: appState,
                                  activeIntervalHeight: activeIntervalHeight,
                                );
                                final double leftRatio =
                                    overlapInfo['leftRatio'] ?? 0.0;
                                final double widthRatio =
                                    overlapInfo['widthRatio'] ?? 1.0;
                                final double textWidthRatio =
                                    overlapInfo['textWidthRatio'] ?? widthRatio;
                                final bool isUpperOverlap =
                                    (overlapInfo['zIndex'] ?? 0.0) > 0.0 &&
                                    (overlapInfo['totalOverlaps'] ?? 1.0) > 1.0;

                                double cardLeft =
                                    colStart + leftRatio * columnWidth;
                                double cardWidth = columnWidth * widthRatio;
                                double textCardWidth =
                                    columnWidth * textWidthRatio;

                                // Add a small right margin (e.g. 2px) to look clean
                                if (cardWidth > 4.0) {
                                  cardWidth -= 2.0;
                                }
                                if (textCardWidth > 4.0) {
                                  textCardWidth -= 2.0;
                                }
                                if (cardWidth < 10.0) cardWidth = 10.0;
                                if (textCardWidth < 10.0) textCardWidth = 10.0;
                                final double extraRightPad =
                                    (cardWidth - textCardWidth).clamp(
                                      0.0,
                                      cardWidth,
                                    );
                                final Color opaqueCardBg = Color.alphaBlend(
                                  bgColor,
                                  Theme.of(context).scaffoldBackgroundColor,
                                );

                                // Kaydırma farkı
                                double leftShift = bounds.left - cardLeft;

                                final bool isShortDuration =
                                    appState.expandShortDuration &&
                                    bounds.height < 22.0;
                                final double visualHeight = isShortDuration
                                    ? 18.0
                                    : bounds.height;

                                return Builder(
                                  builder: (cardContext) {
                                    _captureTimeGridFromCard(cardContext);
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
                                                  color: opaqueCardBg,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border(
                                                    left: BorderSide(
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
                                                                : Colors.black),
                                                      width: isSelected
                                                          ? 3.2
                                                          : 2.2,
                                                    ),
                                                    right: BorderSide(
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
                                                                : Colors.black),
                                                      width: isSelected
                                                          ? 3.2
                                                          : 2.2,
                                                    ),
                                                  ),
                                                ),
                                                alignment: Alignment.topLeft,
                                                padding: EdgeInsets.only(
                                                  left: 4,
                                                  right: 4 + extraRightPad,
                                                  top: isShortDuration
                                                      ? 1.0
                                                      : 2.5,
                                                  bottom: isShortDuration
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
                                                                            project.colorValue,
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
                                                          color: opaqueCardBg,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                        alignment:
                                                            Alignment.topLeft,
                                                        padding:
                                                            EdgeInsets.only(
                                                              left: 4,
                                                              right:
                                                                  4 +
                                                                  extraRightPad,
                                                              top:
                                                                  isShortDuration
                                                                  ? 1.0
                                                                  : 2.5,
                                                              bottom:
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
                                                        color: opaqueCardBg,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        border: Border.all(
                                                          color: isSelected
                                                              ? Colors
                                                                    .green
                                                                    .shade400
                                                              : (isUpperOverlap
                                                                    ? Colors
                                                                          .black
                                                                          .withValues(
                                                                            alpha:
                                                                                0.7,
                                                                          )
                                                                    : Colors
                                                                          .white
                                                                          .withValues(
                                                                            alpha:
                                                                                0.25,
                                                                          )),
                                                          width: isSelected
                                                              ? 2.5
                                                              : (isUpperOverlap
                                                                    ? 1.15
                                                                    : 1.0),
                                                        ),
                                                      ),
                                                      alignment:
                                                          Alignment.topLeft,
                                                      padding: EdgeInsets.only(
                                                        left: 4,
                                                        right:
                                                            4 + extraRightPad,
                                                        top: isShortDuration
                                                            ? 1.0
                                                            : 2.5,
                                                        bottom: isShortDuration
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
                                                    ));
                                        final String itemId =
                                            appointment is Event
                                            ? appointment.id
                                            : (appointment is TaskItem
                                                  ? appointment.id
                                                  : '');
                                        final bool isBeingInteracted =
                                            _interactionMode !=
                                                _InteractionMode.none &&
                                            _activeHit != null &&
                                            _activeHit!.occurrence.id ==
                                                itemId &&
                                            (_activeHit!.occurrence.from
                                                    .difference(segFrom)
                                                    .inMinutes
                                                    .abs() <=
                                                1);
                                        final bool isManipulating =
                                            !appState.isBulkMode &&
                                            (_isCardManipulated(
                                                  itemId,
                                                  fromLocal,
                                                ) ||
                                                isBeingInteracted);

                                        Widget decoratedCard = c;
                                        if (isManipulating) {
                                          decoratedCard = CustomPaint(
                                            foregroundPainter:
                                                _MarchingAntsBorderPainter(
                                                  animation:
                                                      _marchingAntsController,
                                                  borderRadius: 6.0,
                                                ),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Positioned.fill(child: c),
                                                if (!fromLocal.isBefore(
                                                  segmentDayStart,
                                                ))
                                                  Positioned(
                                                    top: -2.0,
                                                    left: 0,
                                                    right: extraRightPad,
                                                    child: Center(
                                                      child: Container(
                                                        width: 24,
                                                        height: 6.0,
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .amberAccent,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                3,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors.black87,
                                                            width: 1.0,
                                                          ),
                                                        ),
                                                        child: Center(
                                                          child: Container(
                                                            width: 12,
                                                            height: 1.5,
                                                            color:
                                                                Colors.black87,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (!toLocal.isAfter(
                                                  segmentDayEnd,
                                                ))
                                                  Positioned(
                                                    bottom: -2.0,
                                                    left: 0,
                                                    right: extraRightPad,
                                                    child: Center(
                                                      child: Container(
                                                        width: 24,
                                                        height: 6.0,
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .amberAccent,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                3,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors.black87,
                                                            width: 1.0,
                                                          ),
                                                        ),
                                                        child: Center(
                                                          child: Container(
                                                            width: 12,
                                                            height: 1.5,
                                                            color:
                                                                Colors.black87,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }

                                        if (isHighImportance) {
                                          final Color protrusionColor =
                                              isSelected
                                              ? Colors.green.shade400
                                              : bgColor;
                                          decoratedCard = Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              decoratedCard,
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
                                        if (isBeingInteracted) {
                                          return Opacity(
                                            opacity: 0.35,
                                            child: decoratedCard,
                                          );
                                        }
                                        return decoratedCard;
                                      })(),
                                      isSelected: isSelected,
                                    ),
                                  ),
                                );
                              },
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
                                                            ? Colors
                                                                  .red
                                                                  .shade400
                                                            : Colors.black)
                                                      : Colors.black),
                                            width: isSelected ? 3.2 : 2.2,
                                          ),
                                          right: BorderSide(
                                            color: isSelected
                                                ? Colors.green.shade400
                                                : (isEvaluated
                                                      ? (isSkippedEval
                                                            ? Colors
                                                                  .red
                                                                  .shade400
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
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                          monthCellBuilder: (BuildContext buildContext, MonthCellDetails details) {
                            final resolvedAppointments = details.appointments
                                .map((appt) => _getOriginalItem(appt, appState))
                                .toList();

                            final dayEvents = resolvedAppointments
                                .whereType<Event>()
                                .where((e) => e.showInMonthView)
                                .toList();
                            final dayTasks = resolvedAppointments
                                .whereType<TaskItem>()
                                .where((t) => t.showInMonthView)
                                .toList();

                            final allStrips = _getActiveStrips(appState);
                            final stripSlots = _assignStripSlots(allStrips);

                            final DateTime dateStart = DateTime(
                              details.date.year,
                              details.date.month,
                              details.date.day,
                            );
                            final DateTime dateEnd = dateStart.add(
                              const Duration(days: 1),
                            );
                            final dayStrips = allStrips.where((s) {
                              return s.startDate.isBefore(dateEnd) &&
                                  s.endDate.isAfter(dateStart);
                            }).toList();

                            int maxSlot = -1;
                            for (var s in dayStrips) {
                              final slot = stripSlots[s.id] ?? 0;
                              if (slot > maxSlot) maxSlot = slot;
                            }

                            final bool hasStrips =
                                appState.showSeritOverlay &&
                                dayStrips.isNotEmpty;
                            final totalItems =
                                dayEvents.length +
                                dayTasks.length +
                                (hasStrips ? dayStrips.length : 0);

                            final now = DateTime.now();
                            final isToday =
                                details.date.year == now.year &&
                                details.date.month == now.month &&
                                details.date.day == now.day;

                            final noteIndex = appState.dayNotes.indexWhere((n) {
                              final localDate = n.date.toLocal();
                              return localDate.year == details.date.year &&
                                  localDate.month == details.date.month &&
                                  localDate.day == details.date.day;
                            });
                            final DayNote? dayNote = noteIndex != -1
                                ? appState.dayNotes[noteIndex]
                                : null;

                            final hasEmoji = dayNote != null &&
                                dayNote.emoji != null &&
                                dayNote.emoji!.trim().isNotEmpty;
                            final hasRating = dayNote != null &&
                                dayNote.rating != null &&
                                dayNote.rating! > 0;
                            final hasNote = dayNote != null &&
                                (dayNote.note.trim().isNotEmpty ||
                                    dayNote.entries.any((e) => e.text.trim().isNotEmpty || e.tags.isNotEmpty) ||
                                    hasEmoji ||
                                    hasRating);

                            Widget? noteInfoWidget;
                            if (hasNote) {
                              final List<Widget> rowChildren = [];
                              if (hasEmoji) {
                                rowChildren.add(
                                  Text(
                                    dayNote.emoji!,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                );
                                rowChildren.add(const SizedBox(width: 2));
                              }
                              if (hasRating) {
                                rowChildren.add(
                                  Text(
                                    '★${dayNote.rating}',
                                    style: TextStyle(
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade800,
                                    ),
                                  ),
                                );
                                rowChildren.add(const SizedBox(width: 2));
                              }
                              if (dayNote != null && dayNote.note.trim().isNotEmpty && !hasEmoji) {
                                rowChildren.add(
                                  Icon(
                                    Icons.note_alt_outlined,
                                    size: 9,
                                    color: Colors.orange.shade700,
                                  ),
                                );
                              }
                              if (rowChildren.isNotEmpty) {
                                noteInfoWidget = FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: rowChildren,
                                  ),
                                );
                              }
                            }

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
                                    if (noteInfoWidget != null)
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        left: 28,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: noteInfoWidget,
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

                            return DragTarget<Map<String, dynamic>>(
                              onWillAcceptWithDetails: (dragDetails) {
                                final data = dragDetails.data;
                                final srcDate = data['sourceDate'] as DateTime?;
                                if (srcDate == null) return false;
                                return srcDate.year != details.date.year ||
                                    srcDate.month != details.date.month ||
                                    srcDate.day != details.date.day;
                              },
                              onAcceptWithDetails: (dragDetails) {
                                final data = dragDetails.data;
                                final dynamic draggedItem = data['item'];
                                final DateTime srcDate =
                                    data['sourceDate'] as DateTime;
                                final DateTime targetDay = details.date;
                                if (draggedItem is Event) {
                                  final DateTime occStart = DateTime(
                                    srcDate.year,
                                    srcDate.month,
                                    srcDate.day,
                                    draggedItem.from.hour,
                                    draggedItem.from.minute,
                                  );
                                  final Duration dur = draggedItem.to
                                      .difference(draggedItem.from);
                                  final DateTime newFrom = DateTime(
                                    targetDay.year,
                                    targetDay.month,
                                    targetDay.day,
                                    draggedItem.from.hour,
                                    draggedItem.from.minute,
                                  );
                                  final DateTime newTo = dur.inMinutes > 0
                                      ? newFrom.add(dur)
                                      : newFrom.add(const Duration(hours: 1));
                                  _commitMoveOrResize(
                                    appState: appState,
                                    item: draggedItem,
                                    occurrenceStart: occStart,
                                    newFrom: newFrom,
                                    newTo: newTo,
                                    isResize: false,
                                  );
                                } else if (draggedItem is TaskItem) {
                                  final DateTime baseFrom =
                                      draggedItem.from ?? srcDate;
                                  final DateTime baseTo =
                                      draggedItem.to ??
                                      baseFrom.add(const Duration(hours: 1));
                                  final DateTime occStart = DateTime(
                                    srcDate.year,
                                    srcDate.month,
                                    srcDate.day,
                                    baseFrom.hour,
                                    baseFrom.minute,
                                  );
                                  final Duration dur = baseTo.difference(
                                    baseFrom,
                                  );
                                  final DateTime newFrom = DateTime(
                                    targetDay.year,
                                    targetDay.month,
                                    targetDay.day,
                                    baseFrom.hour,
                                    baseFrom.minute,
                                  );
                                  final DateTime newTo = dur.inMinutes > 0
                                      ? newFrom.add(dur)
                                      : newFrom.add(const Duration(hours: 1));
                                  _commitMoveOrResize(
                                    appState: appState,
                                    item: draggedItem,
                                    occurrenceStart: occStart,
                                    newFrom: newFrom,
                                    newTo: newTo,
                                    isResize: false,
                                  );
                                }
                              },
                              builder: (context, candidateData, rejectedData) {
                                final bool isDropTarget =
                                    candidateData.isNotEmpty;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: isDropTarget
                                        ? Theme.of(buildContext).primaryColor
                                              .withValues(alpha: 0.22)
                                        : (isToday
                                              ? Theme.of(buildContext)
                                                    .primaryColor
                                                    .withValues(alpha: 0.1)
                                              : null),
                                    border: Border.all(
                                      color: isDropTarget
                                          ? Theme.of(buildContext).primaryColor
                                          : Colors.grey.shade300,
                                      width: isDropTarget ? 1.5 : 0.5,
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

                                      final int stripsHeight =
                                          (appState.showSeritOverlay &&
                                              maxSlot >= 0)
                                          ? (maxSlot + 1) * 16
                                          : 0;

                                      final int availableHeight =
                                          (constraints.maxHeight -
                                                  28 -
                                                  stripsHeight)
                                              .toInt();
                                      final int maxLines = availableHeight > 0
                                          ? (availableHeight ~/ 14)
                                          : 0;

                                      List<Widget> itemWidgets = [];
                                      if (maxLines > 0 && allItems.isNotEmpty) {
                                        if (allItems.length <= maxLines) {
                                          for (var item in allItems) {
                                            itemWidgets.add(
                                              _buildCellItemLine(
                                                item,
                                                sourceDate: details.date,
                                              ),
                                            );
                                          }
                                        } else {
                                          for (
                                            int i = 0;
                                            i < maxLines - 1;
                                            i++
                                          ) {
                                            itemWidgets.add(
                                              _buildCellItemLine(
                                                allItems[i],
                                                sourceDate: details.date,
                                              ),
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
                                            padding: const EdgeInsets.all(4.0),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
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
                                                            ? Theme.of(context).primaryColor
                                                            : null,
                                                      ),
                                                    );

                                                    final List<Color> importantColors = [];
                                                    for (var e in dayEvents) {
                                                      if (e.importance == 2) {
                                                        importantColors.add(Color(e.colorValue));
                                                      }
                                                    }
                                                    for (var t in dayTasks) {
                                                      if (t.importance == 2) {
                                                        importantColors.add(Color(t.colorValue));
                                                      }
                                                    }

                                                    if (importantColors.isNotEmpty) {
                                                      final displayColors = importantColors.take(3).toList();
                                                      Widget currentWidget = dayText;
                                                      for (int i = 0; i < displayColors.length; i++) {
                                                        final color = displayColors[i];
                                                        final size = 26.0 + i * 5.0; // 26, 31, 36
                                                        currentWidget = Container(
                                                          width: size,
                                                          height: size,
                                                          decoration: BoxDecoration(
                                                            shape: BoxShape.circle,
                                                            border: Border.all(
                                                              color: color,
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                          alignment: Alignment.center,
                                                          child: currentWidget,
                                                        );
                                                      }
                                                      final double maxSize = 26.0 + (displayColors.length - 1) * 5.0;
                                                      return SizedBox(
                                                        width: maxSize,
                                                        height: maxSize,
                                                        child: Center(
                                                          child: currentWidget,
                                                        ),
                                                      );
                                                    } else {
                                                      return SizedBox(
                                                        width: 26,
                                                        height: 26,
                                                        child: Center(
                                                          child: dayText,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                                if (noteInfoWidget != null)
                                                  Expanded(
                                                    child: Align(
                                                      alignment: Alignment.centerRight,
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: noteInfoWidget,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (appState.showSeritOverlay &&
                                              maxSlot >= 0)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2.0,
                                                  ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: List.generate(
                                                  maxSlot + 1,
                                                  (slot) {
                                                    final s = dayStrips
                                                        .where(
                                                          (x) =>
                                                              stripSlots[x
                                                                  .id] ==
                                                              slot,
                                                        )
                                                        .firstOrNull;
                                                    if (s == null) {
                                                      return const SizedBox(
                                                        height: 16,
                                                      );
                                                    }
                                                    return _buildStripWidget(
                                                      s,
                                                      details.date,
                                                      appState,
                                                    );
                                                  },
                                                ),
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
                                                      CrossAxisAlignment.start,
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
                            );
                          },
                          onLongPress: (CalendarLongPressDetails details) {
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
                    _buildInteractionPreviewOverlay(appState),
                    if (_copiedItem != null) _buildCopyPasteBanner(appState),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInteractionPreviewOverlay(AppState appState) {
    if (_interactionMode == _InteractionMode.none ||
        _activeHit == null ||
        _previewFrom == null ||
        _previewTo == null ||
        _timeGridRenderBox == null ||
        !_timeGridRenderBox!.attached) {
      return const SizedBox.shrink();
    }

    final int numDays = appState.calendarView == CalendarView.week ? 7 : 1;
    const double timeRulerWidth = 40.0;
    final double columnWidth = (_lastCalendarWidth - timeRulerWidth) / numDays;
    if (columnWidth <= 0) return const SizedBox.shrink();

    final int dayIndex = _previewDayIndex.clamp(0, numDays - 1);
    final double colStart = timeRulerWidth + dayIndex * columnWidth;

    final double startHourVal =
        (_previewFrom!.hour + _previewFrom!.minute / 60.0) - _lastStartHour;
    final double totalDurHours =
        _previewTo!.difference(_previewFrom!).inMinutes / 60.0;
    final double clampedDurHours = totalDurHours.clamp(
      0.25,
      (_lastEndHour - _lastStartHour) - startHourVal,
    );
    final double gridTop = startHourVal * _lastActiveIntervalHeight;
    final double gridHeight = math.max(
      20.0,
      clampedDurHours * _lastActiveIntervalHeight,
    );

    final RenderBox? stackBox =
        _calendarStackKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset globalTopLeft = _timeGridRenderBox!.localToGlobal(
      Offset(colStart, gridTop),
    );
    final Offset stackTopLeft = stackBox != null
        ? stackBox.globalToLocal(globalTopLeft)
        : globalTopLeft;

    final dynamic item = _activeHit!.occurrence.originalItem;
    final Color baseColor = item is Event
        ? Color(item.colorValue)
        : (item is TaskItem ? Color(item.colorValue) : Colors.blue);
    final String title = item is Event
        ? item.title
        : (item is TaskItem ? item.title : '');
    final bool isRecurring =
        (item is Event &&
            item.recurrenceRule != null &&
            item.recurrenceRule!.isNotEmpty) ||
        (item is TaskItem &&
            item.recurrenceRule != null &&
            item.recurrenceRule!.isNotEmpty);

    const daysTr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final String dayName = daysTr[_previewFrom!.weekday - 1];
    final String fromStr =
        '${_previewFrom!.hour.toString().padLeft(2, '0')}:${_previewFrom!.minute.toString().padLeft(2, '0')}';
    final String toStr =
        '${_previewTo!.hour.toString().padLeft(2, '0')}:${_previewTo!.minute.toString().padLeft(2, '0')}';
    final String badgeText = isRecurring
        ? '$dayName $fromStr - $toStr • Bireysel'
        : '$dayName $fromStr - $toStr';

    return Positioned(
      left: stackTopLeft.dx,
      top: stackTopLeft.dy,
      width: math.max(16.0, columnWidth - 2.0),
      height: gridHeight,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                foregroundPainter: _MarchingAntsBorderPainter(
                  animation: _marchingAntsController,
                  borderRadius: 6.0,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: baseColor.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  child: Text(
                    title,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.5 * appState.fontSizeMultiplier,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -2.0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 24,
                  height: 6.0,
                  decoration: BoxDecoration(
                    color: Colors.amberAccent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black87, width: 1.0),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -2.0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 24,
                  height: 6.0,
                  decoration: BoxDecoration(
                    color: Colors.amberAccent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black87, width: 1.0),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -22,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amberAccent, width: 0.8),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyPasteBanner(AppState appState) {
    final dynamic item = _copiedItem;
    if (item == null) return const SizedBox.shrink();
    final String title = item is Event
        ? item.title
        : (item is TaskItem ? item.title : '');
    final DateTime origFrom =
        (_copiedOccurrenceFrom ??
                (item is Event
                    ? item.from
                    : (item is TaskItem ? item.from : null)) ??
                DateTime.now())
            .toLocal();
    final String origTimeStr =
        '${origFrom.hour.toString().padLeft(2, '0')}:${origFrom.minute.toString().padLeft(2, '0')}';
    final bool isDayOrWeek =
        appState.calendarView == CalendarView.day ||
        appState.calendarView == CalendarView.week;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: Colors.teal.shade900,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.content_paste_go,
                color: Colors.amberAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '"$title" kopyalandı',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      isDayOrWeek
                          ? (_pasteUseOriginalTime
                                ? 'Tıkladığınız güne kendi saatiyle ($origTimeStr) yapıştırılır'
                                : 'Takvimde tıkladığınız gün ve saate yapıştırılır (Ctrl+V)')
                          : 'Takvimde yapıştırmak istediğiniz güne tıklayın',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDayOrWeek) ...[
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      _pasteUseOriginalTime = !_pasteUseOriginalTime;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _pasteUseOriginalTime
                          ? Colors.amberAccent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _pasteUseOriginalTime
                            ? Colors.amberAccent
                            : Colors.white30,
                      ),
                    ),
                    child: Text(
                      _pasteUseOriginalTime
                          ? 'Saat: $origTimeStr'
                          : 'Tıklanan Saat',
                      style: TextStyle(
                        color: _pasteUseOriginalTime
                            ? Colors.amberAccent
                            : Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Kopyalamayı Kapat (Esc)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () {
                  setState(() {
                    _copiedItem = null;
                    _copiedOccurrenceFrom = null;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getShortDateString(DateTime date) {
    const months = [
      'oca',
      'şub',
      'mar',
      'nis',
      'may',
      'haz',
      'tem',
      'ağu',
      'eyl',
      'eki',
      'kas',
      'ara',
    ];
    return '${date.day}${months[date.month - 1]}';
  }

  Widget _buildCustomHeaderCell(
    DateTime date,
    AppState appState,
    bool isWeek,
    double width,
  ) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final noteIndex = appState.dayNotes.indexWhere((n) {
      final localDate = n.date.toLocal();
      return localDate.year == normalizedDate.year &&
          localDate.month == normalizedDate.month &&
          localDate.day == normalizedDate.day;
    });
    final DayNote? dayNote = noteIndex != -1
        ? appState.dayNotes[noteIndex]
        : null;

    final hasEmoji =
        dayNote != null &&
        dayNote.emoji != null &&
        dayNote.emoji!.trim().isNotEmpty;
    final hasRating =
        dayNote != null && dayNote.rating != null && dayNote.rating! > 0;
    final hasNote =
        dayNote != null &&
        (dayNote.note.trim().isNotEmpty ||
            dayNote.entries.any((e) => e.text.trim().isNotEmpty || e.tags.isNotEmpty) ||
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
              ? (isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.15)
                    : Colors.amber.shade50.withValues(alpha: 0.5))
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _getShortDateString(date),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: hasEmoji
                        ? Text(
                            dayNote.emoji!,
                            style: const TextStyle(fontSize: 14),
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
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHeaderRow(
    BuildContext context,
    AppState appState,
    BoxConstraints constraints,
  ) {
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
                color: appState.isDarkMode
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: appState.isDarkMode
                        ? Colors.white12
                        : Colors.grey.shade300,
                    width: 0.5,
                  ),
                  right: BorderSide(
                    color: appState.isDarkMode
                        ? Colors.white12
                        : Colors.grey.shade300,
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
      final DateTime date =
          appState.calendarController.displayDate ?? DateTime.now();
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
                color: appState.isDarkMode
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: appState.isDarkMode
                        ? Colors.white12
                        : Colors.grey.shade300,
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

  Widget _buildWeekStripsPanel(
    BuildContext context,
    AppState appState,
    BoxConstraints constraints,
  ) {
    final isWeek = appState.calendarView == CalendarView.week;
    if (!isWeek || _visibleDates.isEmpty) return const SizedBox.shrink();

    // Find all active strips for the week
    final allStrips = _getActiveStrips(appState);
    final weekStart = DateTime(
      _visibleDates.first.year,
      _visibleDates.first.month,
      _visibleDates.first.day,
    );
    final weekEnd = DateTime(
      _visibleDates.last.year,
      _visibleDates.last.month,
      _visibleDates.last.day,
    ).add(const Duration(days: 1));

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
            border: Border(
              top: BorderSide(
                color: appState.isDarkMode
                    ? Colors.white10
                    : Colors.grey.shade300,
              ),
            ),
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
                    color: appState.isDarkMode
                        ? Colors.white60
                        : Colors.black54,
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
                    startCol =
                        (s.startDate.weekday - appState.firstDayOfWeek) % 7;
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
    final appState = Provider.of<AppState>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.event, color: Colors.blue),
                title: const Text('Etkinlik Ekle'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pushRouteWithSnapshotUndo(
                    appState: appState,
                    actionLabel: 'Yeni etkinlik eklendi',
                    builder: (context) =>
                        EventFormScreen(initialDate: initialDate),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.rocket_launch, color: Colors.purple),
                title: const Text('Proje Ekle'),
                onTap: () {
                  Navigator.pop(sheetContext);
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
                  Navigator.pop(sheetContext);
                  _pushRouteWithSnapshotUndo(
                    appState: appState,
                    actionLabel: 'Yeni görev eklendi',
                    builder: (context) =>
                        TaskFormScreen(initialDate: initialDate),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Returns occurrences of recurring all-day events/tasks that fall on [date].
  /// Uses a month-wide search window so monthly/yearly rules are reliably found.
  List<dynamic> _getRecurringAllDayOccurrencesForDate(
    DateTime date,
    AppState appState,
  ) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final result = <dynamic>[];

    // Use the full month as search window to ensure monthly/yearly rules are found
    final searchStart = DateTime(normalizedDate.year, normalizedDate.month, 1);
    final searchEnd = DateTime(
      normalizedDate.year,
      normalizedDate.month + 1,
      1,
    ).subtract(const Duration(milliseconds: 1));

    // Recurring all-day events
    for (var e in appState.filteredEvents) {
      if (!e.isAllDay) continue;
      if (e.recurrenceRule == null || e.recurrenceRule!.isEmpty) continue;
      try {
        final dates = SfCalendar.getRecurrenceDateTimeCollection(
          _sanitizeRRule(e.recurrenceRule, e.from)!,
          e.from,
          specificStartDate: searchStart,
          specificEndDate: searchEnd,
        );
        for (var occ in dates) {
          final d = occ.toLocal();
          if (d.year != normalizedDate.year ||
              d.month != normalizedDate.month ||
              d.day != normalizedDate.day) {
            continue;
          }
          final isEx =
              e.recurrenceExceptionDates?.any(
                (ex) =>
                    ex.year == d.year && ex.month == d.month && ex.day == d.day,
              ) ??
              false;
          if (!isEx) {
            result.add(
              e.copyWith(
                id: 'occ_${e.id}_${occ.millisecondsSinceEpoch}',
                from: occ,
                to: occ.add(e.to.difference(e.from)),
                clearRecurrenceRule: true,
                clearRecurrenceExceptionDates: true,
              ),
            );
          }
        }
      } catch (_) {}
    }

    // Recurring all-day tasks
    final tasks = appState.filteredTasks
        .where(
          (t) =>
              t.from != null &&
              t.isAllDay &&
              t.recurrenceRule != null &&
              t.recurrenceRule!.isNotEmpty,
        )
        .toList();
    for (var t in tasks) {
      try {
        final dates = SfCalendar.getRecurrenceDateTimeCollection(
          _sanitizeRRule(t.recurrenceRule, t.from!)!,
          t.from!,
          specificStartDate: searchStart,
          specificEndDate: searchEnd,
        );
        for (var occ in dates) {
          final d = occ.toLocal();
          if (d.year != normalizedDate.year ||
              d.month != normalizedDate.month ||
              d.day != normalizedDate.day) {
            continue;
          }
          final isEx =
              t.recurrenceExceptionDates?.any(
                (ex) =>
                    ex.year == occ.year &&
                    ex.month == occ.month &&
                    ex.day == occ.day,
              ) ??
              false;
          if (!isEx) {
            final dur = t.to != null
                ? t.to!.difference(t.from!)
                : const Duration(hours: 1);
            result.add(
              t.copyWith(
                id: 'occ_${t.id}_${occ.millisecondsSinceEpoch}',
                from: occ,
                to: occ.add(dur),
                parentTaskId: t.id,
                clearRecurrenceRule: true,
                clearRecurrenceExceptionDates: true,
              ),
            );
          }
        }
      } catch (_) {}
    }

    return result;
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
              // Add recurring all-day items (not returned by _getAllDayItemsForDate)
              final recurringItems = _getRecurringAllDayOccurrencesForDate(
                date,
                appState,
              );
              final allRawItems = [...rawItems, ...recurringItems];
              final List<dynamic> displayItems = [];
              final seenIds = <String>{};
              for (var raw in allRawItems) {
                String idKey = '';
                if (raw is Event) {
                  idKey = raw.id;
                } else if (raw is TaskItem)
                  idKey = raw.id;
                else if (raw is Serit)
                  idKey = raw.id;
                else if (raw is ProjectEvaluation)
                  idKey = raw.id;

                if (idKey.isEmpty || !seenIds.contains(idKey)) {
                  if (idKey.isNotEmpty) seenIds.add(idKey);
                  displayItems.add(raw);
                }
              }

              // Sort completed TaskItems to the end
              displayItems.sort((a, b) {
                final aDone = (a is TaskItem && a.isCompleted);
                final bDone = (b is TaskItem && b.isCompleted);
                if (aDone && !bDone) return 1;
                if (!aDone && bDone) return -1;
                return 0;
              });

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
                                                        _pushRouteWithSnapshotUndo(
                                                          appState: appState,
                                                          actionLabel:
                                                              '"${originalItem.title}" düzenlendi',
                                                          builder: (context) =>
                                                              EventFormScreen(
                                                                existingEvent:
                                                                    originalItem,
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
                                                        _pushRouteWithSnapshotUndo(
                                                          appState: appState,
                                                          actionLabel:
                                                              '"${originalItem.title}" düzenlendi',
                                                          builder: (context) =>
                                                              TaskFormScreen(
                                                                existingTask:
                                                                    originalItem,
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
                                          ? (item.isSkipped
                                              ? '📊 ${linkedProject.title}: Pas ${appState.getPasCount(linkedProject.id, item.sessionDate)}'
                                              : (linkedProject.evaluationType == 'PERCENTAGE'
                                                  ? (item.performancePercent != null
                                                      ? '📊 ${linkedProject.title}: %${item.performancePercent!.toStringAsFixed(0)}'
                                                      : (item.score > 0
                                                          ? '📊 ${linkedProject.title}: %${item.score.toStringAsFixed(0)}'
                                                          : '📊 ${linkedProject.title}'))
                                                  : '📊 ${linkedProject.title}: ${item.score.toStringAsFixed(0)} Puan'))
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
    _lastFocusedItem = item;
    _lastFocusedOccurrenceFrom = tappedDate;
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
          final effectiveFrom = (item.recurrenceRule != null &&
                  item.recurrenceRule!.isNotEmpty &&
                  tappedDate != null)
              ? DateTime(
                  tappedDate.year,
                  tappedDate.month,
                  tappedDate.day,
                  item.from.hour,
                  item.from.minute,
                )
              : item.from;
          final duration = item.to.difference(item.from);
          final effectiveTo = effectiveFrom.add(duration);

          final startStr =
              "${effectiveFrom.day}/${effectiveFrom.month}/${effectiveFrom.year}${item.isAllDay ? '' : ' ${effectiveFrom.hour.toString().padLeft(2, '0')}:${effectiveFrom.minute.toString().padLeft(2, '0')}'}";
          final endStr =
              "${effectiveTo.day}/${effectiveTo.month}/${effectiveTo.year}${item.isAllDay ? '' : ' ${effectiveTo.hour.toString().padLeft(2, '0')}:${effectiveTo.minute.toString().padLeft(2, '0')}'}";
          dateInfo = item.isAllDay
              ? "Tüm Gün: ${effectiveFrom.day}/${effectiveFrom.month}/${effectiveFrom.year}"
              : "$startStr - $endStr";
        } else if (item is TaskItem && item.from != null) {
          final origFrom = item.from!;
          final effectiveFrom = (item.recurrenceRule != null &&
                  item.recurrenceRule!.isNotEmpty &&
                  tappedDate != null)
              ? DateTime(
                  tappedDate.year,
                  tappedDate.month,
                  tappedDate.day,
                  origFrom.hour,
                  origFrom.minute,
                )
              : origFrom;
          final toDate = item.to ?? origFrom;
          final duration = toDate.difference(origFrom);
          final effectiveTo = effectiveFrom.add(duration);

          final startStr =
              "${effectiveFrom.day}/${effectiveFrom.month}/${effectiveFrom.year}${item.isAllDay ? '' : ' ${effectiveFrom.hour.toString().padLeft(2, '0')}:${effectiveFrom.minute.toString().padLeft(2, '0')}'}";
          final endStr =
              "${effectiveTo.day}/${effectiveTo.month}/${effectiveTo.year}${item.isAllDay ? '' : ' ${effectiveTo.hour.toString().padLeft(2, '0')}:${effectiveTo.minute.toString().padLeft(2, '0')}'}";
          dateInfo = item.isAllDay
              ? "Tüm Gün: ${effectiveFrom.day}/${effectiveFrom.month}/${effectiveFrom.year}"
              : "$startStr - $endStr";
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
                    const Icon(
                      Icons.access_time_outlined,
                      size: 14,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateInfo,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey,
                        ),
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
                                    ? (eval.performancePercent != null
                                        ? '%${eval.performancePercent!.toStringAsFixed(0)}'
                                        : (eval.score > 0 ? '%${eval.score.toStringAsFixed(0)}' : 'Oran Girilmedi'))
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
              if (item is Event && item.parentEventId != null) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (ctx) {
                    final parentEv = appState.getEventById(item.parentEventId!);
                    final parentTitle = parentEv?.title ?? '(Silinmiş Etkinlik)';
                    final refText =
                        item.followUpReference == 'start' ? 'başlangıcına' : 'bitişine';
                    final offsetText = item.followUpOffsetMinutes == 0
                        ? 'hemen ardına'
                        : '${item.followUpOffsetMinutes} dk sonra';
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link, size: 16, color: Colors.blue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Bağlı: "$parentTitle" $refText göre $offsetText',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.link_off, size: 16),
                            tooltip: 'Bağlantıyı Kopar',
                            onPressed: () {
                              appState.unlinkFollowUp(item.id);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Bağlantı koparıldı (artık bağımsız).'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              if (item is Event) ...[
                Builder(
                  builder: (ctx) {
                    final children = appState.getFollowUpsOf(item.id);
                    if (children.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '🔗 Bu etkinliğe bağlı ${children.length} takip eden kayıt var',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    );
                  },
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
                    color: item.isInProgress
                        ? Colors.blueGrey
                        : Colors.amber.shade700,
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
                if (item is! ProjectEvaluation) ...[
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _copyItemToClipboard(item, tappedDate);
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Kopyala'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.teal.shade700,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCopyToDateDialog(
                        this.context,
                        item,
                        tappedDate,
                        appState,
                      );
                    },
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('Başka Güne Kopyala'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.indigo.shade700,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      FollowUpLogDialog.show(
                        context,
                        baseItem: item,
                        tappedDate: tappedDate,
                      );
                    },
                    icon: const Icon(Icons.playlist_add, size: 16),
                    label: const Text('Takip Eden Kayıt'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                    ),
                  ),
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
                ],
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
                        _pushRouteWithSnapshotUndo(
                          appState: appState,
                          actionLabel: '"${item.title}" düzenlendi',
                          builder: (context) =>
                              EventFormScreen(existingEvent: item),
                        );
                      } else if (item is TaskItem) {
                        _pushRouteWithSnapshotUndo(
                          appState: appState,
                          actionLabel: '"${item.title}" düzenlendi',
                          builder: (context) =>
                              TaskFormScreen(existingTask: item),
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

  Widget _buildCellItemLine(dynamic item, {DateTime? sourceDate}) {
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

    final Widget lineContent = Padding(
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

    if (sourceDate == null || (item is! Event && item is! TaskItem)) {
      return lineContent;
    }

    return LongPressDraggable<Map<String, dynamic>>(
      delay: const Duration(milliseconds: 380),
      data: {'item': item, 'sourceDate': sourceDate},
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: 0.92),
        child: CustomPaint(
          foregroundPainter: _MarchingAntsBorderPainter(
            animation: _marchingAntsController,
            borderRadius: 6.0,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: lineContent),
      child: lineContent,
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
    showProjectEvaluationDialog(
      context: context,
      project: project,
      date: sessionDate,
      onSaved: () {
        setState(() {});
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
                          .where(
                            (t) => t.seriesId == item.seriesId && t.isCompleted,
                          )
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
                      _showUndoSnackBar('Serideki tüm kopyalar silindi', () {
                        for (var e in deletedEvents) {
                          appState.addEvent(e);
                        }
                      });
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
    final List<Event> preRecurringEvents = List<Event>.from(appState.events);
    final List<TaskItem> preRecurringTasks = List<TaskItem>.from(
      appState.tasks,
    );
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
          _pushRouteWithSnapshotUndo(
            appState: appState,
            actionLabel: '"${item.title}" tüm serisi düzenlendi',
            preCapturedEvents: preRecurringEvents,
            preCapturedTasks: preRecurringTasks,
            builder: (context) => EventFormScreen(existingEvent: item),
          );
        } else if (item is TaskItem) {
          _pushRouteWithSnapshotUndo(
            appState: appState,
            actionLabel: '"${item.title}" tüm serisi düzenlendi',
            preCapturedEvents: preRecurringEvents,
            preCapturedTasks: preRecurringTasks,
            builder: (context) => TaskFormScreen(existingTask: item),
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

          _pushRouteWithSnapshotUndo(
            appState: appState,
            actionLabel: '"${item.title}" tekrarı düzenlendi',
            preCapturedEvents: preRecurringEvents,
            preCapturedTasks: preRecurringTasks,
            builder: (context) => EventFormScreen(
              existingEvent: clone,
              isSingleOccurrenceEdit: true,
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

          _pushRouteWithSnapshotUndo(
            appState: appState,
            actionLabel: '"${item.title}" tekrarı düzenlendi',
            preCapturedEvents: preRecurringEvents,
            preCapturedTasks: preRecurringTasks,
            builder: (context) => TaskFormScreen(
              existingTask: clone,
              isSingleOccurrenceEdit: true,
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

          _pushRouteWithSnapshotUndo(
            appState: appState,
            actionLabel: '"${item.title}" sonraki tekrarlar düzenlendi',
            preCapturedEvents: preRecurringEvents,
            preCapturedTasks: preRecurringTasks,
            builder: (context) => EventFormScreen(existingEvent: clone),
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

          _pushRouteWithSnapshotUndo(
            appState: appState,
            actionLabel: '"${item.title}" sonraki tekrarlar düzenlendi',
            preCapturedEvents: preRecurringEvents,
            preCapturedTasks: preRecurringTasks,
            builder: (context) => TaskFormScreen(existingTask: clone),
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
      if (!item.to.isAtSameMomentAs(item.from) &&
          (item.recurrenceRule == null || item.recurrenceRule!.isEmpty)) {
        final f = item.from;
        final msOffset = (index % 800) + 1;
        return f.isUtc
            ? DateTime.utc(f.year, f.month, f.day, f.hour, f.minute, 0, msOffset)
            : DateTime(f.year, f.month, f.day, f.hour, f.minute, 0, msOffset);
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
      final toVal = item.to ?? fromVal.add(const Duration(hours: 1));
      if (!toVal.isAtSameMomentAs(fromVal) &&
          (item.recurrenceRule == null || item.recurrenceRule!.isEmpty)) {
        final msOffset = (index % 800) + 1;
        return fromVal.isUtc
            ? DateTime.utc(
                fromVal.year,
                fromVal.month,
                fromVal.day,
                fromVal.hour,
                fromVal.minute,
                0,
                msOffset,
              )
            : DateTime(
                fromVal.year,
                fromVal.month,
                fromVal.day,
                fromVal.hour,
                fromVal.minute,
                0,
                msOffset,
              );
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
        if (item.isSkipped) return '📊 ${project.title}: Pas ${appState!.getPasCount(project.id, item.sessionDate)}';
        if (project.evaluationType == 'PERCENTAGE') {
          if (item.performancePercent != null) {
            return '📊 ${project.title}: %${item.performancePercent!.toStringAsFixed(0)}';
          } else if (item.score > 0) {
            return '📊 ${project.title}: %${item.score.toStringAsFixed(0)}';
          } else {
            return '📊 ${project.title}';
          }
        }
        return '📊 ${project.title}: ${item.score.toStringAsFixed(0)} Puan';
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
  final DateTime fullFrom;
  final DateTime fullTo;
  final DateTime createdAt;
  OccurrenceInfo({
    required this.originalItem,
    required this.id,
    required this.from,
    required this.to,
    DateTime? fullFrom,
    DateTime? fullTo,
    DateTime? createdAt,
  }) : fullFrom = fullFrom ?? from,
       fullTo = fullTo ?? to,
       createdAt = createdAt ?? DateTime(1970);
}

enum _CardHitZone { topResize, bottomResize, body }

enum _InteractionMode { none, move, resizeTop, resizeBottom }

class _CardHitResult {
  final OccurrenceInfo occurrence;
  final _CardHitZone zone;
  final int dayIndex;
  final Rect cardRectInGrid;
  final Offset startGridPos;

  _CardHitResult({
    required this.occurrence,
    required this.zone,
    required this.dayIndex,
    required this.cardRectInGrid,
    required this.startGridPos,
  });
}

class _CalendarInteractionGestureRecognizer
    extends OneSequenceGestureRecognizer {
  _CardHitResult? Function(Offset globalPos) onHitTest;
  bool Function(_CardHitResult hit) isCardManipulated;
  void Function(_CardHitResult hit) onActivateManipulation;
  VoidCallback onClearManipulation;
  void Function(_CardHitResult hit, Offset downGlobalPos) onInteractionStart;
  void Function(Offset currentGlobalPos) onInteractionUpdate;
  void Function(Offset upGlobalPos) onInteractionEnd;
  VoidCallback onInteractionCancel;
  void Function(_CardHitResult hit) onCardTap;
  VoidCallback onLockScroll;
  VoidCallback onUnlockScroll;
  void Function(OccurrenceInfo occ) onFocusItem;

  int? _activePointer;
  Offset? _downGlobalPos;
  _CardHitResult? _currentHit;
  bool _isDragging = false;
  bool _holdActivated = false;
  bool _wasAlreadyManipulatedOnDown = false;
  Timer? _holdTimer;

  _CalendarInteractionGestureRecognizer({
    required this.onHitTest,
    required this.isCardManipulated,
    required this.onActivateManipulation,
    required this.onClearManipulation,
    required this.onInteractionStart,
    required this.onInteractionUpdate,
    required this.onInteractionEnd,
    required this.onInteractionCancel,
    required this.onCardTap,
    required this.onLockScroll,
    required this.onUnlockScroll,
    required this.onFocusItem,
  });

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_activePointer != null) {
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final hit = onHitTest(event.position);
    if (hit == null) {
      onClearManipulation();
      return;
    }

    _activePointer = event.pointer;
    _downGlobalPos = event.position;
    _currentHit = hit;
    _isDragging = false;
    onFocusItem(hit.occurrence);
    startTrackingPointer(event.pointer, event.transform);

    if (isCardManipulated(hit)) {
      _wasAlreadyManipulatedOnDown = true;
      _holdActivated = true;
      onLockScroll();
      resolve(GestureDisposition.accepted);
    } else {
      onClearManipulation();
      _wasAlreadyManipulatedOnDown = false;
      _holdActivated = false;
      _holdTimer?.cancel();
      _holdTimer = Timer(const Duration(milliseconds: 380), () {
        if (_activePointer == null || _currentHit == null) return;
        _holdActivated = true;
        onActivateManipulation(_currentHit!);
        onLockScroll();
        resolve(GestureDisposition.accepted);
      });
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _activePointer) return;

    if (event is PointerMoveEvent) {
      if (_downGlobalPos == null || _currentHit == null) return;
      final double dist = (event.position - _downGlobalPos!).distance;

      if (!_holdActivated) {
        if (dist > 8.0) {
          _holdTimer?.cancel();
          _holdTimer = null;
          final int p = event.pointer;
          _cleanup();
          stopTrackingPointer(p);
          resolve(GestureDisposition.rejected);
        }
        return;
      }

      if (!_isDragging) {
        if (dist > 4.0) {
          _isDragging = true;
          if (event.kind != PointerDeviceKind.mouse) {
            HapticFeedback.selectionClick();
          }
          onInteractionStart(_currentHit!, _downGlobalPos!);
          onInteractionUpdate(event.position);
        }
      } else {
        onInteractionUpdate(event.position);
      }
    } else if (event is PointerUpEvent) {
      _holdTimer?.cancel();
      _holdTimer = null;
      final bool wasDragging = _isDragging;
      final bool wasHoldActivated = _holdActivated;
      final bool wasAlreadyManipulated = _wasAlreadyManipulatedOnDown;
      final _CardHitResult? hit = _currentHit;
      final int p = event.pointer;
      _cleanup();
      stopTrackingPointer(p);
      onUnlockScroll();
      if (wasDragging) {
        onInteractionEnd(event.position);
      } else if (!wasHoldActivated && hit != null) {
        resolve(GestureDisposition.accepted);
        onCardTap(hit);
      } else if (wasHoldActivated && wasAlreadyManipulated && hit != null) {
        onClearManipulation();
        onCardTap(hit);
      }
    } else if (event is PointerCancelEvent) {
      _holdTimer?.cancel();
      _holdTimer = null;
      final bool wasDragging = _isDragging;
      final int p = event.pointer;
      _cleanup();
      stopTrackingPointer(p);
      onUnlockScroll();
      if (wasDragging) {
        onInteractionCancel();
      }
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  void _cleanup() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _activePointer = null;
    _downGlobalPos = null;
    _currentHit = null;
    _isDragging = false;
    _holdActivated = false;
    _wasAlreadyManipulatedOnDown = false;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _holdTimer = null;
    onUnlockScroll();
    super.dispose();
  }

  @override
  String get debugDescription => 'calendarInteraction';
}

class _MarchingAntsBorderPainter extends CustomPainter {
  final Animation<double> animation;
  final double borderRadius;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  _MarchingAntsBorderPainter({
    required this.animation,
    this.borderRadius = 6.0,
    this.strokeWidth = 2.4,
    this.dashWidth = 6.0,
    this.dashSpace = 5.0,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        math.max(0.0, size.width - strokeWidth),
        math.max(0.0, size.height - strokeWidth),
      ),
      Radius.circular(borderRadius),
    );

    final Path path = Path()..addRRect(rrect);

    final Paint basePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, basePaint);

    final Paint dashPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double period = dashWidth + dashSpace;
    final double phase = animation.value * period;
    final Path dashedPath = Path();

    for (final PathMetric metric in path.computeMetrics()) {
      final double totalLen = metric.length;
      if (totalLen <= 0) continue;
      double start = -period + (phase % period);
      while (start < totalLen) {
        final double extractStart = math.max(0.0, start);
        final double extractEnd = math.min(totalLen, start + dashWidth);
        if (extractEnd > extractStart) {
          dashedPath.addPath(
            metric.extractPath(extractStart, extractEnd),
            Offset.zero,
          );
        }
        start += period;
      }
    }

    canvas.drawPath(dashedPath, dashPaint);
  }

  @override
  bool shouldRepaint(covariant _MarchingAntsBorderPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace;
  }
}

class _CalendarHistorySnapshot {
  final List<Event> events;
  final List<TaskItem> tasks;
  final Map<String, String> eventJsonById;
  final Map<String, String> taskJsonById;

  _CalendarHistorySnapshot({
    required this.events,
    required this.tasks,
    required this.eventJsonById,
    required this.taskJsonById,
  });

  factory _CalendarHistorySnapshot.capture(AppState appState) {
    final evs = List<Event>.from(appState.events);
    final tks = List<TaskItem>.from(appState.tasks);
    return _CalendarHistorySnapshot(
      events: evs,
      tasks: tks,
      eventJsonById: {for (final e in evs) e.id: jsonEncode(e.toJson())},
      taskJsonById: {for (final t in tks) t.id: jsonEncode(t.toJson())},
    );
  }
}

class _CalendarUndoEntry {
  final String message;
  final VoidCallback onUndo;
  final VoidCallback? onRedo;

  _CalendarUndoEntry({
    required this.message,
    required this.onUndo,
    this.onRedo,
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
