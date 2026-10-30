import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/task_item.dart';
import '../utils/id_generator.dart';
import '../models/project.dart';
import '../utils/rrule_translator.dart';
import 'custom_recurrence_dialog.dart';

class TaskFormScreen extends StatefulWidget {
  final TaskItem? existingTask;
  final DateTime? initialDate;
  final bool isSingleOccurrenceEdit;
  final String? initialSuperTaskId;
  final String? initialTag;
  final String? initialSubTag;
  const TaskFormScreen({
    super.key,
    this.existingTask,
    this.initialDate,
    this.isSingleOccurrenceEdit = false,
    this.initialSuperTaskId,
    this.initialTag,
    this.initialSubTag,
  });

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _detailsController;
  DateTime? _from;
  DateTime? _to;
  late int _colorValue;
  late String _tag;
  late TextEditingController _tagController;
  String? _subTag;
  late int _importance;
  late bool _isAllDay;
  late bool _hasDate;
  String? _recurrenceRule;
  String? _projectId;
  String? _superTaskId;
  String? _projectTag;
  List<int> _notificationOffsets = [];
  late bool _showInMonthView;

  final List<int> _colors = const [
    0xFF2196F3, // Blue
    0xFFF44336, // Red
    0xFF4CAF50, // Green
    0xFFFF9800, // Orange
    0xFF9C27B0, // Purple
    0xFF009688, // Teal
    0xFFE91E63, // Pink
    0xFFFFC107, // Amber
    0xFF00BCD4, // Cyan
    0xFF8BC34A, // Light Green
    0xFFE040FB, // Orchid
    0xFFFF5722, // Deep Orange
    0xFF607D8B, // Blue Grey
    0xFF795548, // Brown
  ];

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    _titleController = TextEditingController(text: task?.title ?? '');
    _detailsController = TextEditingController(text: task?.details ?? '');
    _from = task?.from ?? widget.initialDate;
    _to = task?.to ?? (widget.initialDate?.add(const Duration(hours: 1)));
    _hasDate = _from != null;
    if (_hasDate) {
      _from ??= DateTime.now();
      _to ??= DateTime.now().add(const Duration(hours: 1));
    } else {
      _from = DateTime.now();
      _to = DateTime.now().add(const Duration(hours: 1));
    }
    _colorValue = task?.colorValue ?? _colors[2]; // Default Green
    _tag = task?.tag ?? widget.initialTag ?? 'Yapılacaklar';
    _tagController = TextEditingController(text: _tag);
    _subTag = task?.subTag ?? widget.initialSubTag;
    _importance = task?.importance ?? 0;
    _isAllDay = task?.isAllDay ?? false;
    _recurrenceRule = task?.recurrenceRule;
    _projectId = task?.projectId;
    _superTaskId = task?.superTaskId ?? widget.initialSuperTaskId;
    _projectTag = task?.projectTag;
    _notificationOffsets = task?.notificationOffsets != null
        ? List<int>.from(task!.notificationOffsets)
        : ((task?.hasNotification ?? false) && task?.notificationMinutesBefore != null
            ? [task!.notificationMinutesBefore!]
            : const []);
    _showInMonthView = task?.showInMonthView ?? true;
  }

  bool _isInit = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      if (_superTaskId != null && widget.existingTask == null) {
        final appState = Provider.of<AppState>(context, listen: false);
        try {
          final superTask = appState.tasks.firstWhere(
            (t) => t.id == _superTaskId,
          );
          _tag = superTask.tag;
          _tagController.text = _tag;
          _subTag = superTask.subTag;
        } catch (_) {}
      }
      if (widget.existingTask == null) {
        final appState = Provider.of<AppState>(context, listen: false);
        final tagColor = appState.getTaskTagColor(_tag);
        if (tagColor != null) {
          _colorValue = tagColor;
        }
      }
      _isInit = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _showProjectPickerDialog(BuildContext context, AppState appState) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Proje Seçin'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.layers_clear, color: Colors.grey),
                  title: const Text('Hiçbiri (Bağımsız)'),
                  trailing: _projectId == null ? const Icon(Icons.check, color: Colors.blue) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  selected: _projectId == null,
                  selectedTileColor: Colors.blue.withOpacity(0.08),
                  onTap: () => Navigator.pop(ctx, 'NONE'),
                ),
                const Divider(),
                ...appState.projects.map((p) {
                  final isSel = _projectId == p.id;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: Color(p.colorValue),
                    ),
                    title: Text(p.title),
                    subtitle: p.tag.isNotEmpty ? Text(p.tag, style: const TextStyle(fontSize: 11)) : null,
                    trailing: isSel ? const Icon(Icons.check, color: Colors.blue) : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    selected: isSel,
                    selectedTileColor: Colors.blue.withOpacity(0.08),
                    onTap: () => Navigator.pop(ctx, p.id),
                  );
                }),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.blue),
                  title: const Text('+ Yeni Proje Ekle...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.pop(ctx, 'NEW'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        ],
      ),
    );

    if (selected == 'NONE') {
      setState(() {
        _projectId = null;
        _projectTag = null;
      });
    } else if (selected == 'NEW') {
      final newProject = await _showCreateProjectDialog(context, appState);
      if (newProject != null) {
        setState(() {
          _projectId = newProject.id;
          _projectTag = null;
          _tag = newProject.tag;
          _tagController.text = _tag;
          _subTag = newProject.subTag;
        });
      }
    } else if (selected != null) {
      final p = appState.projects.firstWhere((p) => p.id == selected);
      setState(() {
        _projectId = p.id;
        _projectTag = null;
        if (p.tag.isNotEmpty) {
          _tag = p.tag;
          _tagController.text = _tag;
          _subTag = p.subTag;
        }
      });
    }
  }

  // ── Combined Date/Time picker helper ──────────────────────────────────────

  Future<void> _pickCombinedDateTime(BuildContext context, bool isStart) async {
    _from ??= DateTime.now();
    _to ??= _from!.add(const Duration(hours: 1));

    DateTime tempDate = isStart ? _from! : _to!;
    int tempHour = tempDate.hour;
    int tempMinute = tempDate.minute;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Row(
            children: [
              Icon(
                isStart ? Icons.play_circle_outline : Icons.stop_circle_outlined,
                color: isStart ? Colors.blue : Colors.indigo,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isStart ? 'Başlangıç Tarihi ve Saati' : 'Bitiş Tarihi ve Saati',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: Theme.of(ctx).colorScheme.copyWith(
                        primary: isStart ? Colors.blue : Colors.indigo,
                      ),
                    ),
                    child: CalendarDatePicker(
                      initialDate: tempDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      onDateChanged: (d) {
                        setDialogState(() {
                          tempDate = DateTime(d.year, d.month, d.day, tempHour, tempMinute);
                        });
                      },
                    ),
                  ),
                  if (!_isAllDay) ...[
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.access_time, size: 20, color: Colors.blueGrey),
                              const SizedBox(width: 8),
                              const Text('Saat:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: tempHour,
                                isDense: true,
                                underline: const SizedBox(),
                                items: List.generate(
                                  24,
                                  (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      i.toString().padLeft(2, '0'),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                ),
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => tempHour = val);
                                },
                              ),
                              const Text(' : ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              DropdownButton<int>(
                                value: tempMinute,
                                isDense: true,
                                underline: const SizedBox(),
                                items: List.generate(
                                  60,
                                  (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      i.toString().padLeft(2, '0'),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                ),
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => tempMinute = val);
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.watch_later_outlined, size: 20, color: Colors.blue),
                                tooltip: 'Saat Kadranından Seç',
                                onPressed: () async {
                                  final pTime = await showTimePicker(
                                    context: ctx,
                                    initialTime: TimeOfDay(hour: tempHour, minute: tempMinute),
                                  );
                                  if (pTime != null) {
                                    setDialogState(() {
                                      tempHour = pTime.hour;
                                      tempMinute = pTime.minute;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [0, 15, 30, 45].map((m) {
                              final isSel = tempMinute == m;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: InkWell(
                                  onTap: () => setDialogState(() => tempMinute = m),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSel ? (isStart ? Colors.blue : Colors.indigo) : Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSel ? Colors.transparent : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      ':${m.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                        color: isSel ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isStart ? Colors.blue : Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(
                  ctx,
                  DateTime(
                    tempDate.year,
                    tempDate.month,
                    tempDate.day,
                    _isAllDay ? 0 : tempHour,
                    _isAllDay ? 0 : tempMinute,
                  ),
                );
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          final diff = _to != null && _from != null ? _to!.difference(_from!) : const Duration(hours: 1);
          _from = picked;
          if (_to != null && (_to!.isBefore(_from!) || _to!.isAtSameMomentAs(_from!))) {
            _to = _from!.add(diff.inMinutes > 0 ? diff : const Duration(hours: 1));
          }
        } else {
          var newTo = picked;
          if (_from != null &&
              newTo.isBefore(_from!) &&
              newTo.year == _from!.year &&
              newTo.month == _from!.month &&
              newTo.day == _from!.day) {
            newTo = newTo.add(const Duration(days: 1));
          }
          _to = newTo;
        }
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    if (!_hasDate) return;
    final initialDate = isStart ? _from! : _to!;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      setState(() {
        if (isStart) {
          final diff = _to != null && _from != null ? _to!.difference(_from!) : const Duration(hours: 1);
          _from = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            _from!.hour,
            _from!.minute,
          );
          if (_to != null && _to!.isBefore(_from!)) {
            _to = _from!.add(diff.inMinutes > 0 ? diff : const Duration(hours: 1));
          }
        } else {
          _to = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            _to!.hour,
            _to!.minute,
          );
          if (_from != null &&
              _to!.isBefore(_from!) &&
              _to!.year == _from!.year &&
              _to!.month == _from!.month &&
              _to!.day == _from!.day) {
            _to = _to!.add(const Duration(days: 1));
          }
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    if (!_hasDate) return;
    final initialDate = isStart ? _from! : _to!;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    if (pickedTime != null) {
      setState(() {
        if (isStart) {
          final oldDiff = _to != null && _from != null ? _to!.difference(_from!) : const Duration(hours: 1);
          _from = DateTime(
            _from!.year,
            _from!.month,
            _from!.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (_to != null && (_to!.isBefore(_from!) || _to!.isAtSameMomentAs(_from!))) {
            _to = _from!.add(oldDiff.inMinutes > 0 ? oldDiff : const Duration(hours: 1));
          }
        } else {
          var newTo = DateTime(
            _to!.year,
            _to!.month,
            _to!.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          final isSameDay = _from != null &&
              _to!.year == _from!.year &&
              _to!.month == _from!.month &&
              _to!.day == _from!.day;
          // Gece yarısı (00:00 / 12 AM) veya başlangıçtan önce/eşit seçildiyse ertesi güne taşır
          if (isSameDay &&
              (pickedTime.hour == 0 && pickedTime.minute == 0 ||
                  newTo.isBefore(_from!) ||
                  newTo.isAtSameMomentAs(_from!))) {
            newTo = DateTime(_from!.year, _from!.month, _from!.day + 1, pickedTime.hour, pickedTime.minute);
          }
          _to = newTo;
        }
      });
    }
  }

  Widget _buildTimeIndicatorBadge() {
    if (_from == null || _to == null) return const SizedBox.shrink();
    final startStr =
        '${_from!.hour.toString().padLeft(2, '0')}:${_from!.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${_to!.hour.toString().padLeft(2, '0')}:${_to!.minute.toString().padLeft(2, '0')}';
    final isNextDay = _to!.day != _from!.day || _to!.month != _from!.month || _to!.year != _from!.year;
    final diff = _to!.difference(_from!);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final durationStr = hours > 0
        ? (minutes > 0 ? '$hours sa $minutes dk' : '$hours saat')
        : '$minutes dk';

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              Text(
                '24 Saat Göstergesi: $startStr → $endStr${isNextDay ? ' (+1 gün)' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Süre: $durationStr',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'İpucu: 12:00 AM = Gece Yarısı (00:00) | 12:00 PM = Öğlen (12:00)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySelector() {
    final priorities = [
      {'val': 0, 'label': 'Düşük', 'color': Colors.green, 'icon': Icons.arrow_downward},
      {'val': 1, 'label': 'Orta', 'color': Colors.orange, 'icon': Icons.remove},
      {'val': 2, 'label': 'Yüksek', 'color': Colors.red, 'icon': Icons.priority_high},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Önem Seviyesi',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: priorities.map((p) {
            final val = p['val'] as int;
            final isSelected = _importance == val;
            final color = p['color'] as Color;
            final label = p['label'] as String;
            final icon = p['icon'] as IconData;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: InkWell(
                  onTap: () => setState(() => _importance = val),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? color : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTagSection(AppState appState) {
    final sortedTags = appState.getSortedTaskTagsByUsage();
    final filterText = _tagController.text.trim().toLowerCase();
    final filteredTags = sortedTags.where((t) => t.toLowerCase().contains(filterText)).toList();
    final exactMatch = sortedTags.any((t) => t.toLowerCase() == filterText);
    final subTags = appState.taskSubTags[_tag] ?? [];
    final isProjectBound = _projectId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _tagController,
                enabled: !isProjectBound,
                decoration: InputDecoration(
                  labelText: 'Tag / Kategori',
                  hintText: 'Tag yazın veya aşağıdan seçin...',
                  prefixIcon: const Icon(Icons.label_outline, size: 20),
                  suffixIcon: _tagController.text.isNotEmpty && !isProjectBound
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() {
                              _tagController.clear();
                            });
                          },
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: (val) {
                  setState(() {
                    if (appState.taskTags.contains(val.trim())) {
                      _tag = val.trim();
                      _subTag = null;
                      final defaultColor = appState.getTaskTagColor(_tag);
                      if (defaultColor != null) _colorValue = defaultColor;
                    }
                  });
                },
              ),
            ),
          ],
        ),
        if (isProjectBound) ...[
          const SizedBox(height: 4),
          const Text(
            'Tag seçili projeye bağlıdır.',
            style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 8),

        // Yatay Tag Listesi (En çok kullanılanlar önde)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (!isProjectBound && filterText.isNotEmpty && !exactMatch) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 16, color: Colors.blue),
                    label: Text('"$filterText" Oluştur'),
                    onPressed: () {
                      final newName = _tagController.text.trim();
                      if (newName.isNotEmpty) {
                        appState.addTaskCategory(newName);
                        setState(() {
                          _tag = newName;
                          _tagController.text = newName;
                          _subTag = null;
                        });
                      }
                    },
                  ),
                ),
              ],
              ...filteredTags.map((t) {
                final isSelected = _tag == t;
                final tagColor = Color(appState.getTaskTagColor(t) ?? 0xFF2196F3);

                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: FilterChip(
                    selected: isSelected,
                    showCheckmark: false,
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: tagColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: Text(t),
                    selectedColor: tagColor.withOpacity(0.2),
                    side: BorderSide(
                      color: isSelected ? tagColor : Colors.grey.shade300,
                      width: isSelected ? 1.5 : 1,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? tagColor : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: isProjectBound
                        ? null
                        : (selected) {
                            setState(() {
                              _tag = t;
                              _tagController.text = t;
                              _subTag = null;
                              final defaultColor = appState.getTaskTagColor(t);
                              if (defaultColor != null) _colorValue = defaultColor;
                            });
                          },
                  ),
                );
              }),
            ],
          ),
        ),

        // Alt Tagler (SubTags) Yatay Şeridi
        if (_tag.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$_tag Alt Tagleri:',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              if (!isProjectBound) ...[
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final ns = await _showCreateSubTagDialog(context, appState, _tag);
                    if (ns != null) setState(() => _subTag = ns);
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 14, color: Colors.blue),
                      SizedBox(width: 4),
                      Text(
                        'Alt Tag Ekle',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: const Text('Yok'),
                    selected: _subTag == null,
                    onSelected: isProjectBound
                        ? null
                        : (selected) {
                            if (selected) setState(() => _subTag = null);
                          },
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: _subTag == null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                ...subTags.map((st) {
                  final isSelected = _subTag == st;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: Text(st),
                      selected: isSelected,
                      onSelected: isProjectBound
                          ? null
                          : (selected) {
                              setState(() {
                                _subTag = selected ? st : null;
                              });
                            },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDurationChip(BuildContext context, String label, int minutes) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(label),
        onPressed: () {
          setState(() {
            _to = _from!.add(Duration(minutes: minutes));
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    if (!appState.taskTags.contains(_tag)) {
      _tag = appState.taskTags.isNotEmpty ? appState.taskTags.first : '';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingTask == null ? 'Yeni Görev' : 'Görevi Düzenle',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              _saveForm(context, appState);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // ── Başlık & Detaylar (Kompakt) ─────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Görev Başlığı',
                            isDense: true,
                            prefixIcon: Icon(Icons.check_circle_outline, size: 20),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Başlık zorunludur' : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _detailsController,
                          decoration: const InputDecoration(
                            labelText: 'Açıklama / Detaylar',
                            isDense: true,
                            prefixIcon: Icon(Icons.notes, size: 20),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Tarih Ekle ve Tüm Gün (Madde 1: Yan Yana) ────────────
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _hasDate ? Theme.of(context).primaryColor.withOpacity(0.08) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _hasDate ? Theme.of(context).primaryColor.withOpacity(0.3) : Colors.grey.shade300,
                            ),
                          ),
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            dense: true,
                            title: const Text('Tarih Ekle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            value: _hasDate,
                            onChanged: (val) => setState(() => _hasDate = val),
                          ),
                        ),
                      ),
                      if (_hasDate) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isAllDay ? Colors.teal.withOpacity(0.08) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isAllDay ? Colors.teal.withOpacity(0.3) : Colors.grey.shade300,
                              ),
                            ),
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              dense: true,
                              title: const Text('Tüm Gün', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              value: _isAllDay,
                              onChanged: (val) => setState(() => _isAllDay = val),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ── Başlangıç & Bitiş (Madde 2: Yan Yana & Tek Pop-up) ───
                  if (_hasDate) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _pickCombinedDateTime(context, true),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.play_circle_outline, size: 14, color: Colors.blue.shade700),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Başlangıç',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_from!.day}/${_from!.month}/${_from!.year}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        if (!_isAllDay) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_from!.hour.toString().padLeft(2, '0')}:${_from!.minute.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade900,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _pickCombinedDateTime(context, false),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.stop_circle_outlined, size: 14, color: Colors.indigo.shade700),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Bitiş',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_to!.day}/${_to!.month}/${_to!.year}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        if (!_isAllDay) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_to!.hour.toString().padLeft(2, '0')}:${_to!.minute.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo.shade900,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!_isAllDay) ...[
                            const SizedBox(height: 8),
                            _buildTimeIndicatorBadge(),
                            const SizedBox(height: 4),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildDurationChip(context, 'Hatırlatıcı', 0),
                                  _buildDurationChip(context, '15 Dk', 15),
                                  _buildDurationChip(context, '30 Dk', 30),
                                  _buildDurationChip(context, '45 Dk', 45),
                                  _buildDurationChip(context, '1 Saat', 60),
                                  _buildDurationChip(context, '2 Saat', 120),
                                  _buildDurationChip(context, '3 Saat', 180),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // ── Renk Seçimi (Madde 3: Başlık Yok, Yatay Tek Satır) ─────
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _colors.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, index) {
                        final color = _colors[index];
                        final isSelected = _colorValue == color;
                        return GestureDetector(
                          onTap: () => setState(() => _colorValue = color),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: isSelected ? 38 : 32,
                            height: isSelected ? 38 : 32,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black87 : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Color(color).withOpacity(0.4),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Proje Seçimi (Madde 5: Pop-up Screen Açılır) ───────────
                  Builder(
                    builder: (ctx) {
                      final selectedProject = appState.projects.where((p) => p.id == _projectId).firstOrNull;
                      return Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _showProjectPickerDialog(context, appState),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.folder_outlined,
                                      size: 20,
                                      color: selectedProject != null ? Color(selectedProject.colorValue) : Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Proje', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                          Text(
                                            selectedProject != null ? selectedProject.title : 'Hiçbiri (Bağımsız)',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (selectedProject != null && selectedProject.tags.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: selectedProject.tags.contains(_projectTag) ? _projectTag : null,
                                decoration: const InputDecoration(
                                  labelText: 'Proje İçi Etiket',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Etiket Yok')),
                                  ...selectedProject.tags.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                                  const DropdownMenuItem<String?>(
                                    value: 'add_new_project_tag',
                                    child: Text('+ Yeni Etiket...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                onChanged: (val) async {
                                  if (val == 'add_new_project_tag') {
                                    final newTag = await _showCreateProjectTagDialog(context, appState, selectedProject);
                                    setState(() => _projectTag = newTag);
                                  } else {
                                    setState(() => _projectTag = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  if (_superTaskId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bu bir alt görevdir. Etiketi değiştirmek onu bağımsız bir görev yapar.',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Tag & Alt Tag ──────────────────────────────────────────
                  _buildTagSection(appState),
                  const SizedBox(height: 12),

                  // ── Önem Seviyesi ──────────────────────────────────────────
                  _buildPrioritySelector(),
                  const SizedBox(height: 12),

                  if (_hasDate && !widget.isSingleOccurrenceEdit)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tekrarlama', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        RRuleTranslator.translate(_recurrenceRule),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => _showRecurrenceOptions(context),
                    ),

                  // --- BİLDİRİM BÖLÜMÜ ---
                  if (_hasDate) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.notifications_outlined, size: 18, color: Colors.blueGrey),
                        SizedBox(width: 6),
                        Text(
                          'Bildirimler',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_notificationOffsets.isEmpty)
                      const Text(
                        'Bildirim ayarlanmadı.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _notificationOffsets.map((offset) {
                        String label = '';
                        if (offset == 0) {
                          label = 'Görev anında';
                        } else if (offset == 10) {
                          label = '10 dk önce';
                        } else if (offset == 30) {
                          label = '30 dk önce';
                        } else if (offset == 60) {
                          label = '1 saat önce';
                        } else if (offset == 120) {
                          label = '2 saat önce';
                        } else if (offset == 1440) {
                          label = '1 gün önce';
                        } else if (offset == 10080) {
                          label = '1 hafta önce';
                        } else if (offset % 10080 == 0) {
                          label = '${offset ~/ 10080} hafta önce';
                        } else if (offset % 1440 == 0) {
                          label = '${offset ~/ 1440} gün önce';
                        } else if (offset % 60 == 0) {
                          label = '${offset ~/ 60} saat önce';
                        } else if (offset >= 1440) {
                          label = '${offset ~/ 1440} gün ${offset % 1440 ~/ 60} saat önce';
                        } else if (offset >= 60) {
                          label = '${offset ~/ 60} saat ${offset % 60} dk önce';
                        } else {
                          label = '$offset dk önce';
                        }
                        return InputChip(
                          label: Text(label),
                          onDeleted: () {
                            setState(() {
                              _notificationOffsets.remove(offset);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: null,
                      hint: const Text('+ Bildirim Ekle'),
                      items: const [
                        DropdownMenuItem(
                          value: '0',
                          child: Text('Görev anında'),
                        ),
                        DropdownMenuItem(
                          value: '10',
                          child: Text('10 dakika önce'),
                        ),
                        DropdownMenuItem(
                          value: '30',
                          child: Text('30 dakika önce'),
                        ),
                        DropdownMenuItem(value: '60', child: Text('1 saat önce')),
                        DropdownMenuItem(
                          value: '120',
                          child: Text('2 saat önce'),
                        ),
                        DropdownMenuItem(
                          value: '1440',
                          child: Text('1 gün önce'),
                        ),
                        DropdownMenuItem(
                          value: '10080',
                          child: Text('1 hafta önce'),
                        ),
                        DropdownMenuItem(value: 'custom', child: Text('Özel...')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        if (val == 'custom') {
                          final customVal = await _showCustomNotificationDialog(
                            context,
                          );
                          if (customVal != null &&
                              !_notificationOffsets.contains(customVal)) {
                            setState(() {
                              _notificationOffsets.add(customVal);
                            });
                          }
                        } else {
                          final intVal = int.parse(val);
                          if (!_notificationOffsets.contains(intVal)) {
                            setState(() {
                              _notificationOffsets.add(intVal);
                            });
                          }
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── Aylık Görünüm Ayarı (Madde 6) ─────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: _showInMonthView ? Colors.purple.withOpacity(0.06) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _showInMonthView ? Colors.purple.withOpacity(0.25) : Colors.grey.shade300,
                      ),
                    ),
                    child: SwitchListTile(
                      dense: true,
                      secondary: Icon(
                        Icons.calendar_view_month,
                        color: _showInMonthView ? Colors.purple : Colors.grey,
                      ),
                      title: const Text(
                        'Aylık Takvimde Göster',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Kapalıyken bu görev takvimin aylık görünümünde hücreyi doldurmaz, görünümü sade tutar.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _showInMonthView,
                      onChanged: (v) => setState(() => _showInMonthView = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateRRule(String? rule) {
    setState(() => _recurrenceRule = rule);
    Navigator.pop(context);
  }

  void _showRecurrenceOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Tekrarlama (Yok)'),
                onTap: () => _updateRRule(null),
              ),
              ListTile(
                title: const Text('Her Gün'),
                onTap: () => _updateRRule('FREQ=DAILY'),
              ),
              ListTile(
                title: const Text('Her Hafta'),
                onTap: () {
                  const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
                  final date = _from ?? DateTime.now();
                  _updateRRule('FREQ=WEEKLY;BYDAY=${days[date.weekday - 1]}');
                },
              ),
              ListTile(
                title: const Text('Her Ay'),
                onTap: () => _updateRRule('FREQ=MONTHLY'),
              ),
              ListTile(
                title: const Text('Her Yıl'),
                onTap: () => _updateRRule('FREQ=YEARLY'),
              ),
              ListTile(
                title: const Text('Özel...'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await showDialog<String>(
                    context: context,
                    builder: (context) => CustomRecurrenceDialog(
                      initialRRule: _recurrenceRule,
                      eventDate: _from ?? DateTime.now(),
                    ),
                  );
                  if (result != null) {
                    setState(() => _recurrenceRule = result);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _saveForm(BuildContext context, AppState appState) async {
    if (_hasDate && _to != null && _from != null && _to!.isBefore(_from!)) {
      if (_to!.year == _from!.year && _to!.month == _from!.month && _to!.day == _from!.day) {
        _to = _to!.add(const Duration(days: 1));
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen zaman aralığına dikkat edin (Bitiş başlangıçtan önce olamaz)'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    if (_formKey.currentState!.validate()) {
      final resolvedColor = appState.getTaskTagColor(_tag) ?? _colors[2];
      final task = TaskItem(
        id:
            widget.existingTask?.id ??
            IdGenerator.generate(_titleController.text),
        title: _titleController.text,
        details: _detailsController.text,
        isCompleted: widget.existingTask?.isCompleted ?? false,
        from: _hasDate ? _from : null,
        to: _hasDate ? _to : null,
        isAllDay: _hasDate ? _isAllDay : false,
        colorValue: resolvedColor,
        tag: _tag,
        subTag: _subTag,
        importance: _importance,
        recurrenceRule: _hasDate ? _recurrenceRule : null,
        recurrenceExceptionDates: widget.existingTask?.recurrenceExceptionDates,
        projectId: _projectId,
        superTaskId: _superTaskId,
        projectTag: _projectId != null ? _projectTag : null,
        hasNotification: _hasDate && _notificationOffsets.isNotEmpty,
        notificationMinutesBefore: (_hasDate && _notificationOffsets.isNotEmpty)
            ? _notificationOffsets.first
            : null,
        notificationOffsets: _hasDate ? _notificationOffsets : const [],
        createdAt: widget.existingTask?.createdAt,
        showInMonthView: _showInMonthView,
      );

      if (widget.existingTask == null ||
          !appState.tasks.any((t) => t.id == task.id)) {
        appState.addTask(task);
      } else {
        final oldTask = widget.existingTask!;
        appState.updateTask(task);
        final date = task.from ?? DateTime.now();
        final normalizedDate = DateTime(date.year, date.month, date.day);
        final hasEval =
            task.projectId != null &&
            appState.evaluations.any(
              (e) =>
                  e.projectId == task.projectId &&
                  e.sessionDate == normalizedDate,
            );
        final snackBarText = hasEval
            ? '"${task.title}" güncellendi. Bu tarihe ait bir proje değerlendirmesi bulunuyor, lütfen onu da güncellemeyi unutmayın.'
            : '"${task.title}" güncellendi';
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackBarText),
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            showCloseIcon: true,
            closeIconColor: Colors.white70,
            action: SnackBarAction(
              label: 'Geri Al',
              textColor: Colors.amber,
              onPressed: () {
                appState.updateTask(oldTask);
              },
            ),
          ),
        );
      }
      Navigator.pop(context, true);
    }
  }

  Future<Project?> _showCreateProjectDialog(
    BuildContext context,
    AppState appState,
  ) async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    int selectedColor = _colors[0];

    return showDialog<Project>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Yeni Proje Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Proje Başlığı',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama (İsteğe Bağlı)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Renk Seçimi',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      children: _colors.map((color) {
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedColor = color),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(color),
                            child: selectedColor == color
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isNotEmpty) {
                      final newProj = Project(
                        id: IdGenerator.generate(title),
                        title: title,
                        description: descriptionCtrl.text.trim(),
                        colorValue: selectedColor,
                        evaluationType: 'PERCENTAGE',
                        targetValue: 100.0,
                      );
                      appState.addProject(newProj);
                      Navigator.pop(context, newProj);
                    }
                  },
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showCreateTagDialog(
    BuildContext context,
    AppState appState,
  ) async {
    final tagCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yeni Tag Ekle'),
          content: TextField(
            controller: tagCtrl,
            decoration: const InputDecoration(labelText: 'Tag Adı'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = tagCtrl.text.trim();
                if (name.isNotEmpty) {
                  appState.addTaskCategory(name);
                  Navigator.pop(context, name);
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showCreateSubTagDialog(
    BuildContext context,
    AppState appState,
    String tag,
  ) async {
    final subTagCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$tag — Yeni Alt Tag Ekle'),
          content: TextField(
            controller: subTagCtrl,
            decoration: const InputDecoration(labelText: 'Alt Tag Adı'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = subTagCtrl.text.trim();
                if (name.isNotEmpty) {
                  appState.addTaskSubTag(tag, name);
                  Navigator.pop(context, name);
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showCreateProjectTagDialog(
    BuildContext context,
    AppState appState,
    Project project,
  ) async {
    final tagCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yeni Proje Etiketi Ekle'),
          content: TextField(
            controller: tagCtrl,
            decoration: const InputDecoration(labelText: 'Etiket Adı'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = tagCtrl.text.trim();
                if (name.isNotEmpty) {
                  if (project.tags.contains(name)) {
                    Navigator.pop(context, name);
                  } else {
                    final updatedTags = List<String>.from(project.tags)
                      ..add(name);
                    final updatedProject = project.copyWith(tags: updatedTags);
                    appState.updateProject(updatedProject);
                    Navigator.pop(context, name);
                  }
                } else {
                  Navigator.pop(context, null);
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }
  Future<int?> _showCustomNotificationDialog(BuildContext context) async {
    final valueCtrl = TextEditingController(text: '15');
    String unit = 'minutes';

    return showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Özel Bildirim Ayarla'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Görev zamanından önce bildirim süresini ve birimini belirleyin:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: valueCtrl,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Sayı / Süre',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          value: unit,
                          decoration: const InputDecoration(
                            labelText: 'Birim',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'minutes', child: Text('Dakika (dk)')),
                            DropdownMenuItem(value: 'hours', child: Text('Saat')),
                            DropdownMenuItem(value: 'days', child: Text('Gün')),
                            DropdownMenuItem(value: 'weeks', child: Text('Hafta')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                unit = val;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final int? val = int.tryParse(valueCtrl.text.trim());
                    if (val == null || val <= 0) {
                      Navigator.pop(context, null);
                      return;
                    }
                    int multiplier = 1;
                    if (unit == 'hours') multiplier = 60;
                    if (unit == 'days') multiplier = 1440;
                    if (unit == 'weeks') multiplier = 10080;
                    Navigator.pop(context, val * multiplier);
                  },
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

