import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../providers/app_state.dart';
import '../utils/id_generator.dart';
import '../utils/recurrence_helper.dart';
import '../screens/event_form_screen.dart';

enum FollowUpReferencePoint {
  end, // Bitiş noktası
  start, // Başlangıç noktası
}

enum FollowUpDurationType {
  duration, // Toplam süre (dk)
  endTime, // Bitiş saati
  until, // Bir sonraki etkinliğe kadar (Until)
}

class _UntilCandidateEvent {
  final String eventId;
  final String title;
  final DateTime from;
  final DateTime to;
  final int colorValue;
  final bool isRecurring;

  const _UntilCandidateEvent({
    required this.eventId,
    required this.title,
    required this.from,
    required this.to,
    required this.colorValue,
    this.isRecurring = false,
  });

  String get uniqueKey => '${eventId}_${from.millisecondsSinceEpoch}';
}

class FollowUpLogDialog extends StatefulWidget {
  final dynamic baseItem; // Event or TaskItem
  final DateTime? tappedDate;

  const FollowUpLogDialog({
    super.key,
    required this.baseItem,
    this.tappedDate,
  });

  static Future<void> show(
    BuildContext context, {
    required dynamic baseItem,
    DateTime? tappedDate,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => FollowUpLogDialog(
        baseItem: baseItem,
        tappedDate: tappedDate,
      ),
    );
  }

  @override
  State<FollowUpLogDialog> createState() => _FollowUpLogDialogState();
}

class _FollowUpLogDialogState extends State<FollowUpLogDialog> {
  final _titleController = TextEditingController();
  final _offsetMinutesController = TextEditingController(text: '0');
  final _durationMinutesController = TextEditingController(text: '60');

  FollowUpReferencePoint _referencePoint = FollowUpReferencePoint.end;
  FollowUpDurationType _durationType = FollowUpDurationType.duration;
  TimeOfDay? _selectedEndTime;
  _UntilCandidateEvent? _selectedUntilCandidate;
  FollowUpReferencePoint _untilReferencePoint = FollowUpReferencePoint.start;
  bool _isDynamicLink = true;
  String? _baseEventId;
  late DateTime _baseStart;
  late DateTime _baseEnd;
  late String _baseTitle;
  String? _projectId;
  String _tag = 'Genel';
  String? _subTag;
  int _colorValue = 0xFF2196F3;

  @override
  void initState() {
    super.initState();
    final item = widget.baseItem;
    if (item is Event) {
      _baseEventId = item.id;
      final duration = item.to.difference(item.from);
      if (widget.tappedDate != null &&
          (item.recurrenceRule != null && item.recurrenceRule!.isNotEmpty)) {
        _baseStart = DateTime(
          widget.tappedDate!.year,
          widget.tappedDate!.month,
          widget.tappedDate!.day,
          item.from.hour,
          item.from.minute,
          item.from.second,
        );
        _baseEnd = _baseStart.add(duration);
      } else {
        _baseStart = item.from;
        _baseEnd = item.to;
      }
      _baseTitle = item.title;
      _projectId = item.projectId;
      _tag = item.tag;
      _subTag = item.subTag;
      _colorValue = item.colorValue;
    } else if (item is TaskItem) {
      _baseEventId = null; // Görevler için event bağı şimdilik null
      final origFrom = item.from ?? widget.tappedDate ?? DateTime.now();
      final origTo = item.to ?? origFrom.add(const Duration(hours: 1));
      final duration = origTo.difference(origFrom);

      if (widget.tappedDate != null &&
          (item.recurrenceRule != null && item.recurrenceRule!.isNotEmpty)) {
        _baseStart = DateTime(
          widget.tappedDate!.year,
          widget.tappedDate!.month,
          widget.tappedDate!.day,
          origFrom.hour,
          origFrom.minute,
          origFrom.second,
        );
        _baseEnd = _baseStart.add(duration);
      } else {
        _baseStart = origFrom;
        _baseEnd = origTo;
      }
      _baseTitle = item.title;
      _projectId = item.projectId;
      _tag = item.tag;
      _colorValue = item.colorValue;
    } else {
      _baseEventId = null;
      _baseStart = widget.tappedDate ?? DateTime.now();
      _baseEnd = _baseStart.add(const Duration(hours: 1));
      _baseTitle = 'Etkinlik';
    }

    _titleController.text = '$_baseTitle (Takip)';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _offsetMinutesController.dispose();
    _durationMinutesController.dispose();
    super.dispose();
  }

  DateTime _calculateStartTime() {
    final baseRef = (_referencePoint == FollowUpReferencePoint.end)
        ? _baseEnd
        : _baseStart;
    final offsetMins = int.tryParse(_offsetMinutesController.text.trim()) ?? 0;
    return baseRef.add(Duration(minutes: offsetMins));
  }

  List<_UntilCandidateEvent> _getUntilCandidates(
    AppState appState,
    DateTime calculatedStart,
  ) {
    final List<_UntilCandidateEvent> candidates = [];
    final searchStart = DateTime(
      calculatedStart.year,
      calculatedStart.month,
      calculatedStart.day,
    ).subtract(const Duration(days: 1));
    final searchEnd = calculatedStart.add(const Duration(days: 7));

    for (final e in appState.events) {
      if (e.isAllDay) continue;
      final duration = e.to.difference(e.from);

      if (e.recurrenceRule == null || e.recurrenceRule!.isEmpty) {
        if (e.id == _baseEventId && e.from == _baseStart) continue;
        if (e.to.isAfter(calculatedStart) && e.from.isBefore(searchEnd)) {
          candidates.add(
            _UntilCandidateEvent(
              eventId: e.id,
              title: e.title,
              from: e.from,
              to: e.to,
              colorValue: e.colorValue,
              isRecurring: false,
            ),
          );
        }
      } else {
        final occDates = RecurrenceHelper.getOccurrences(
          rrule: e.recurrenceRule!,
          startDate: e.from,
          specificStartDate: searchStart,
          specificEndDate: searchEnd,
        );
        final exDates = e.recurrenceExceptionDates ?? const [];
        for (final occDate in occDates) {
          final isExcluded = exDates.any(
            (ex) =>
                ex.year == occDate.year &&
                ex.month == occDate.month &&
                ex.day == occDate.day,
          );
          if (isExcluded) continue;

          final occFrom = DateTime(
            occDate.year,
            occDate.month,
            occDate.day,
            e.from.hour,
            e.from.minute,
            e.from.second,
          );
          final occTo = occFrom.add(duration);
          if (e.id == _baseEventId && occFrom == _baseStart) continue;
          if (occTo.isAfter(calculatedStart) && occFrom.isBefore(searchEnd)) {
            candidates.add(
              _UntilCandidateEvent(
                eventId: e.id,
                title: e.title,
                from: occFrom,
                to: occTo,
                colorValue: e.colorValue,
                isRecurring: true,
              ),
            );
          }
        }
      }
    }

    candidates.sort((a, b) => a.from.compareTo(b.from));
    return candidates;
  }

  Future<void> _showUntilEventPickerDialog(
    BuildContext context,
    List<_UntilCandidateEvent> candidates,
    DateTime calculatedStart,
  ) async {
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu saatten sonra yakın tarihte uygun etkinlik bulunamadı.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final picked = await showDialog<_UntilCandidateEvent>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.event_available, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sonraki (Hedef) Etkinliği Seçin',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 340,
            child: ListView.separated(
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final c = candidates[index];
                final isSelected =
                    _selectedUntilCandidate?.uniqueKey == c.uniqueKey;
                final startsAfter = c.from.isAfter(calculatedStart);
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.12),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(c.colorValue),
                    child: Icon(
                      c.isRecurring ? Icons.repeat : Icons.event,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    c.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Başlangıç: ${_formatDateTime(c.from)}  •  Bitiş: ${_formatDateTime(c.to)}'
                    '${!startsAfter ? ' (Başlangıcı geçmiş, bitişi seçilebilir)' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.blue, size: 18)
                      : const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(ctx, c),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedUntilCandidate = picked;
        if (!picked.from.isAfter(calculatedStart) &&
            picked.to.isAfter(calculatedStart)) {
          _untilReferencePoint = FollowUpReferencePoint.end;
        }
      });
    }
  }

  DateTime _calculateEndTime(DateTime calculatedStart) {
    if (_durationType == FollowUpDurationType.duration) {
      final durationMins =
          int.tryParse(_durationMinutesController.text.trim()) ?? 60;
      return calculatedStart.add(Duration(minutes: durationMins));
    } else if (_durationType == FollowUpDurationType.until) {
      if (_selectedUntilCandidate != null) {
        final targetTime = _untilReferencePoint == FollowUpReferencePoint.start
            ? _selectedUntilCandidate!.from
            : _selectedUntilCandidate!.to;
        if (targetTime.isAfter(calculatedStart)) {
          return targetTime;
        }
        return calculatedStart.add(const Duration(minutes: 15));
      }
      return calculatedStart.add(const Duration(hours: 1));
    } else {
      if (_selectedEndTime != null) {
        var end = DateTime(
          calculatedStart.year,
          calculatedStart.month,
          calculatedStart.day,
          _selectedEndTime!.hour,
          _selectedEndTime!.minute,
        );
        // Eğer bitiş saati başlangıçtan önceyse bir sonraki güne kaydır
        if (end.isBefore(calculatedStart)) {
          end = end.add(const Duration(days: 1));
        }
        return end;
      }
      return calculatedStart.add(const Duration(hours: 1));
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final calculatedStart = _calculateStartTime();
    final untilCandidates = _getUntilCandidates(appState, calculatedStart);
    if (_durationType == FollowUpDurationType.until &&
        _selectedUntilCandidate == null &&
        untilCandidates.isNotEmpty) {
      _selectedUntilCandidate = untilCandidates.first;
      if (!_selectedUntilCandidate!.from.isAfter(calculatedStart) &&
          _selectedUntilCandidate!.to.isAfter(calculatedStart)) {
        _untilReferencePoint = FollowUpReferencePoint.end;
      }
    }
    final calculatedEnd = _calculateEndTime(calculatedStart);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.playlist_add, color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Takip Eden Kayıt Ekle',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Referans Etkinlik: $_baseTitle',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              // Başlık
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Kayıt / Etkinlik Başlığı',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Referans Noktası Seçimi (Başlangıç vs Bitiş)
              const Text(
                'İlk Etkinlik Referans Noktası:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<FollowUpReferencePoint>(
                      title: const Text('Bitiş', style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        _formatDateTime(_baseEnd),
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: FollowUpReferencePoint.end,
                      groupValue: _referencePoint,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        if (val != null) setState(() => _referencePoint = val);
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<FollowUpReferencePoint>(
                      title: const Text('Başlangıç', style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        _formatDateTime(_baseStart),
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: FollowUpReferencePoint.start,
                      groupValue: _referencePoint,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        if (val != null) setState(() => _referencePoint = val);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),

              // Offset (Öteleme Süresi)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _offsetMinutesController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Offset / Gecikme (dk)',
                        hintText: 'Örn: 30',
                        isDense: true,
                        prefixIcon: const Icon(Icons.timer_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 4,
                    children: [0, 15, 30, 60].map((m) {
                      final isSelected =
                          _offsetMinutesController.text == m.toString();
                      return ChoiceChip(
                        label: Text('$m dk', style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        padding: EdgeInsets.zero,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _offsetMinutesController.text = m.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Süre / Bitiş Belirleme Türü
              const Text(
                'Süre Belirleme Yöntemi:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                        child: Text('Toplam Süre (dk)', style: TextStyle(fontSize: 12)),
                      ),
                      selected: _durationType == FollowUpDurationType.duration,
                      onSelected: (selected) {
                        if (selected) {
                          setState(
                              () => _durationType = FollowUpDurationType.duration);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                        child: Text('Bitiş Saati Seç', style: TextStyle(fontSize: 12)),
                      ),
                      selected: _durationType == FollowUpDurationType.endTime,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _durationType = FollowUpDurationType.endTime;
                            _selectedEndTime ??= TimeOfDay.fromDateTime(
                              calculatedStart.add(const Duration(hours: 1)),
                            );
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                        child: Text('Until', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      selected: _durationType == FollowUpDurationType.until,
                      onSelected: (selected) async {
                        if (selected) {
                          setState(() {
                            _durationType = FollowUpDurationType.until;
                            if (_selectedUntilCandidate == null &&
                                untilCandidates.isNotEmpty) {
                              _selectedUntilCandidate = untilCandidates.first;
                            }
                          });
                          await _showUntilEventPickerDialog(
                            context,
                            untilCandidates,
                            calculatedStart,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Süre, Bitiş saati veya Until hedef etkinlik girişi
              if (_durationType == FollowUpDurationType.duration) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _durationMinutesController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Etkinlik Süresi (dk)',
                          isDense: true,
                          prefixIcon: const Icon(Icons.hourglass_bottom, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 4,
                      children: [30, 45, 60, 90, 120].map((m) {
                        final isSelected =
                            _durationMinutesController.text == m.toString();
                        return ChoiceChip(
                          label: Text('$m dk', style: const TextStyle(fontSize: 11)),
                          selected: isSelected,
                          padding: EdgeInsets.zero,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _durationMinutesController.text = m.toString();
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ] else if (_durationType == FollowUpDurationType.endTime) ...[
                InkWell(
                  onTap: () async {
                    final initial = _selectedEndTime ??
                        TimeOfDay.fromDateTime(
                          calculatedStart.add(const Duration(hours: 1)),
                        );
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: initial,
                    );
                    if (picked != null) {
                      setState(() => _selectedEndTime = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade400,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _selectedEndTime != null
                              ? 'Bitiş Saati: ${_selectedEndTime!.format(context)}'
                              : 'Bitiş Saati Seçin',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar, size: 18),
                      ],
                    ),
                  ),
                ),
              ] else if (_durationType == FollowUpDurationType.until) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey.shade900.withValues(alpha: 0.5)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.event_available,
                              size: 18, color: Colors.blue),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Sonraki (Hedef) Etkinlik:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showUntilEventPickerDialog(
                              context,
                              untilCandidates,
                              calculatedStart,
                            ),
                            icon: const Icon(Icons.swap_horiz, size: 15),
                            label: const Text(
                              'Etkinlik Seç',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_selectedUntilCandidate != null) ...[
                        InkWell(
                          onTap: () => _showUntilEventPickerDialog(
                            context,
                            untilCandidates,
                            calculatedStart,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black26 : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Color(_selectedUntilCandidate!.colorValue)
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Color(
                                        _selectedUntilCandidate!.colorValue),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedUntilCandidate!.title,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${_formatDateTime(_selectedUntilCandidate!.from)} - ${_formatDateTime(_selectedUntilCandidate!.to)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Hedef Etkinliğin Neresi Referans Alınsın?',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<FollowUpReferencePoint>(
                                title: const Text('Başlangıç',
                                    style: TextStyle(fontSize: 12.5)),
                                subtitle: Text(
                                  _formatDateTime(
                                      _selectedUntilCandidate!.from),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                value: FollowUpReferencePoint.start,
                                groupValue: _untilReferencePoint,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _untilReferencePoint = val);
                                  }
                                },
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<FollowUpReferencePoint>(
                                title: const Text('Bitiş',
                                    style: TextStyle(fontSize: 12.5)),
                                subtitle: Text(
                                  _formatDateTime(_selectedUntilCandidate!.to),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                value: FollowUpReferencePoint.end,
                                groupValue: _untilReferencePoint,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _untilReferencePoint = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'Yakın tarihte sonraki bir etkinlik bulunamadı. Lütfen "Etkinlik Seç" butonuna tıklayın.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Dinamik / Tek Seferlik Bağlantı Ayarı
              const Text(
                'Referans Bağlantı Tipi:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync, size: 15),
                            SizedBox(width: 4),
                            Text('Dinamik', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      selected: _isDynamicLink,
                      onSelected: (selected) {
                        if (selected) setState(() => _isDynamicLink = true);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_outlined, size: 15),
                            SizedBox(width: 4),
                            Text('Tek Seferlik', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      selected: !_isDynamicLink,
                      onSelected: (selected) {
                        if (selected) setState(() => _isDynamicLink = false);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _isDynamicLink
                    ? 'Dinamik: Referans alınan etkinliklerin saati değişirse bu kayıt da otomatik olarak güncellenir.'
                    : 'Tek Seferlik: Etkinlikleri yalnızca ilk oluşturma aşamasında referans alır, sonraki değişikliklerden etkilenmez.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 14),

              // Özet / Önizleme Kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.12)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.blue.withValues(alpha: 0.3)
                        : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 15, color: Colors.blue),
                        SizedBox(width: 6),
                        Text(
                          'Hesaplanan Zaman Çizelgesi:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Başlangıç: ${_formatDateTime(calculatedStart)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Bitiş: ${_formatDateTime(calculatedEnd)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Toplam Süre: ${calculatedEnd.difference(calculatedStart).inMinutes} dk (${_isDynamicLink ? "Dinamik Bağlı" : "Tek Seferlik"})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        // Gelişmiş formda aç
        TextButton.icon(
          onPressed: () {
            final offsetMins =
                int.tryParse(_offsetMinutesController.text.trim()) ?? 0;
            final refStr =
                _referencePoint == FollowUpReferencePoint.start ? 'start' : 'end';
            final untilRefStr =
                _untilReferencePoint == FollowUpReferencePoint.start
                    ? 'start'
                    : 'end';
            final effectiveParentId = _isDynamicLink ? _baseEventId : null;
            final effectiveUntilId = (_isDynamicLink &&
                    _durationType == FollowUpDurationType.until)
                ? _selectedUntilCandidate?.eventId
                : null;

            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EventFormScreen(
                  initialDate: calculatedStart,
                  initialTo: calculatedEnd,
                  initialTag: _tag,
                  initialSubTag: _subTag,
                  initialParentEventId: effectiveParentId,
                  initialFollowUpOffsetMinutes: offsetMins,
                  initialFollowUpReference: refStr,
                  initialUntilEventId: effectiveUntilId,
                  initialUntilOffsetMinutes: 0,
                  initialUntilReference: untilRefStr,
                ),
              ),
            );
          },
          icon: const Icon(Icons.open_in_new, size: 15),
          label: const Text('Detaylı Form'),
        ),
        // Hızlı kaydet
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final title = _titleController.text.trim().isEmpty
                ? '$_baseTitle (Takip)'
                : _titleController.text.trim();
            final offsetMins =
                int.tryParse(_offsetMinutesController.text.trim()) ?? 0;
            final refStr =
                _referencePoint == FollowUpReferencePoint.start ? 'start' : 'end';
            final untilRefStr =
                _untilReferencePoint == FollowUpReferencePoint.start
                    ? 'start'
                    : 'end';
            final effectiveParentId = _isDynamicLink ? _baseEventId : null;
            final effectiveUntilId = (_isDynamicLink &&
                    _durationType == FollowUpDurationType.until)
                ? _selectedUntilCandidate?.eventId
                : null;

            final newEvent = Event(
              id: IdGenerator.generate(title, date: calculatedStart),
              title: title,
              from: calculatedStart,
              to: calculatedEnd,
              colorValue: _colorValue,
              tag: _tag,
              subTag: _subTag,
              projectId: _projectId,
              parentEventId: effectiveParentId,
              followUpOffsetMinutes: offsetMins,
              followUpReference: refStr,
              untilEventId: effectiveUntilId,
              untilOffsetMinutes: 0,
              untilReference: untilRefStr,
            );

            appState.addEvent(newEvent);
            Navigator.pop(context);

            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text('Takip eden kayıt oluşturuldu: "$title"'),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                showCloseIcon: true,
                closeIconColor: Colors.white70,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                action: SnackBarAction(
                  label: 'Geri Al',
                  textColor: Colors.amber,
                  onPressed: () {
                    appState.deleteEvent(newEvent.id);
                  },
                ),
              ),
            );
          },
          child: const Text('Hızlı Ekle'),
        ),
      ],
    );
  }
}
