import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/project.dart';
import '../providers/app_state.dart';
import '../utils/id_generator.dart';
import '../screens/event_form_screen.dart';

enum FollowUpReferencePoint {
  end, // Bitiş noktası
  start, // Başlangıç noktası
}

enum FollowUpDurationType {
  duration, // Toplam süre (dk)
  endTime, // Bitiş saati
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

  DateTime _calculateEndTime(DateTime calculatedStart) {
    if (_durationType == FollowUpDurationType.duration) {
      final durationMins =
          int.tryParse(_durationMinutesController.text.trim()) ?? 60;
      return calculatedStart.add(Duration(minutes: durationMins));
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
    final calculatedStart = _calculateStartTime();
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
          width: 440,
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
                'Referans Noktası:',
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
                  const SizedBox(width: 8),
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
                ],
              ),
              const SizedBox(height: 10),

              // Süre veya Bitiş saati girişi
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
              ] else ...[
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
              ],
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
                      '• Toplam Süre: ${calculatedEnd.difference(calculatedStart).inMinutes} dk',
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
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EventFormScreen(
                  initialDate: calculatedStart,
                  initialTo: calculatedEnd,
                  initialTag: _tag,
                  initialSubTag: _subTag,
                  initialParentEventId: _baseEventId,
                  initialFollowUpOffsetMinutes: offsetMins,
                  initialFollowUpReference: refStr,
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
            final appState = Provider.of<AppState>(context, listen: false);
            final title = _titleController.text.trim().isEmpty
                ? '$_baseTitle (Takip)'
                : _titleController.text.trim();
            final offsetMins =
                int.tryParse(_offsetMinutesController.text.trim()) ?? 0;
            final refStr =
                _referencePoint == FollowUpReferencePoint.start ? 'start' : 'end';

            final newEvent = Event(
              id: IdGenerator.generate(title, date: calculatedStart),
              title: title,
              from: calculatedStart,
              to: calculatedEnd,
              colorValue: _colorValue,
              tag: _tag,
              subTag: _subTag,
              projectId: _projectId,
              parentEventId: _baseEventId,
              followUpOffsetMinutes: offsetMins,
              followUpReference: refStr,
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
