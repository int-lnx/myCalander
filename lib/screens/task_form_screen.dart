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
  String? _subTag;
  late int _importance;
  late bool _isAllDay;
  late bool _hasDate;
  String? _recurrenceRule;
  String? _projectId;
  String? _superTaskId;
  String? _projectTag;
  List<int> _notificationOffsets = [];

  final List<int> _colors = [
    0xFF2196F3, // Blue
    0xFFF44336, // Red
    0xFF4CAF50, // Green
    0xFFFF9800, // Orange
    0xFF9C27B0, // Purple
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
    _tag = task?.tag ?? widget.initialTag ?? 'Genel';
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
    super.dispose();
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
          _from = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            _from!.hour,
            _from!.minute,
          );
          if (_to!.isBefore(_from!)) {
            _to = _from!.add(const Duration(hours: 1));
          }
        } else {
          _to = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            _to!.hour,
            _to!.minute,
          );
          if (_to!.isBefore(_from!)) {
            _from = _to!.subtract(const Duration(hours: 1));
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
    );
    if (pickedTime != null) {
      setState(() {
        if (isStart) {
          _from = DateTime(
            _from!.year,
            _from!.month,
            _from!.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _to = _from!.add(const Duration(hours: 1));
        } else {
          _to = DateTime(
            _to!.year,
            _to!.month,
            _to!.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          if (_to!.isBefore(_from!)) {
            _from = _to!.subtract(const Duration(hours: 1));
          }
        }
      });
    }
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
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Başlık'),
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Başlık zorunludur' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _detailsController,
                    decoration: const InputDecoration(labelText: 'Detaylar'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Tarih Ekle'),
                    value: _hasDate,
                    onChanged: (val) {
                      setState(() => _hasDate = val);
                    },
                  ),
                  if (_hasDate) ...[
                    SwitchListTile(
                      title: const Text('Tüm Gün (Saat Belirtme)'),
                      value: _isAllDay,
                      onChanged: (val) {
                        setState(() => _isAllDay = val);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Başlangıç Tarihi'),
                              subtitle: Text(
                                '${_from!.day}/${_from!.month}/${_from!.year}',
                              ),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () => _selectDate(context, true),
                            ),
                          ),
                          if (!_isAllDay) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Başlangıç Saati'),
                                subtitle: Text(
                                  '${_from!.hour.toString().padLeft(2, '0')}:${_from!.minute.toString().padLeft(2, '0')}',
                                ),
                                trailing: const Icon(Icons.access_time),
                                onTap: () => _selectTime(context, true),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Bitiş Tarihi'),
                              subtitle: Text(
                                '${_to!.day}/${_to!.month}/${_to!.year}',
                              ),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () => _selectDate(context, false),
                            ),
                          ),
                          if (!_isAllDay) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Bitiş Saati'),
                                subtitle: Text(
                                  '${_to!.hour.toString().padLeft(2, '0')}:${_to!.minute.toString().padLeft(2, '0')}',
                                ),
                                trailing: const Icon(Icons.access_time),
                                onTap: () => _selectTime(context, false),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!_isAllDay) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Hızlı Süre Seçimi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  const Text(
                    'Renk Seçimi',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    children: _colors.map((color) {
                      return GestureDetector(
                        onTap: () => setState(() => _colorValue = color),
                        child: CircleAvatar(
                          backgroundColor: Color(color),
                          child: _colorValue == color
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue:
                              appState.projects.any((p) => p.id == _projectId)
                              ? _projectId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Proje (İsteğe Bağlı)',
                          ),
                          items: () {
                            final List<DropdownMenuItem<String?>> items = [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Hiçbiri (Bağımsız)'),
                              ),
                            ];
                            for (var p in appState.projects) {
                              items.add(
                                DropdownMenuItem<String?>(
                                  value: p.id,
                                  child: Text(p.title),
                                ),
                              );
                            }
                            items.add(
                              const DropdownMenuItem<String?>(
                                value: 'add_new_project',
                                child: Text(
                                  '+ Yeni Proje...',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                            return items;
                          }(),
                          onChanged: (val) async {
                            if (val == 'add_new_project') {
                              final newProject = await _showCreateProjectDialog(
                                context,
                                appState,
                              );
                              if (newProject != null) {
                                setState(() {
                                  _projectId = newProject.id;
                                  _projectTag = null;
                                });
                              } else {
                                setState(() {
                                  _projectId = null;
                                  _projectTag = null;
                                });
                              }
                            } else {
                              setState(() {
                                _projectId = val;
                                _projectTag = null;
                              });
                            }
                          },
                        ),
                      ),
                      if (_projectId != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final project = appState.projects.firstWhere(
                                (p) => p.id == _projectId,
                                orElse: () => const Project(id: '', title: '', colorValue: 0, evaluationType: 'PERCENTAGE', targetValue: 100.0),
                              );
                              return DropdownButtonFormField<String?>(
                                initialValue: project.tags.contains(_projectTag)
                                    ? _projectTag
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Proje İçi Etiket',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Etiket Yok'),
                                  ),
                                  ...project.tags.map(
                                    (t) => DropdownMenuItem<String?>(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  ),
                                  const DropdownMenuItem<String?>(
                                    value: 'add_new_project_tag',
                                    child: Text(
                                      '+ Yeni Etiket...',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) async {
                                  if (val == 'add_new_project_tag') {
                                    final newTag =
                                        await _showCreateProjectTagDialog(
                                          context,
                                          appState,
                                          project,
                                        );
                                    if (newTag != null) {
                                      setState(() {
                                        _projectTag = newTag;
                                      });
                                    } else {
                                      setState(() {
                                        _projectTag = null;
                                      });
                                    }
                                  } else {
                                    setState(() {
                                      _projectTag = val;
                                    });
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_superTaskId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
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
                  DropdownButtonFormField<String>(
                    initialValue: appState.taskTags.contains(_tag)
                        ? _tag
                        : (appState.taskTags.isNotEmpty ? appState.taskTags.first : null),
                    decoration: const InputDecoration(labelText: 'Tag'),
                    items: [
                      ...appState.taskTags.map((t) {
                        return DropdownMenuItem<String>(
                          value: t,
                          child: Text(t),
                        );
                      }),
                      const DropdownMenuItem<String>(
                        value: 'add_new_tag',
                        child: Text(
                          '+ Yeni Tag Ekle...',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) async {
                      if (val == 'add_new_tag') {
                        final newTag = await _showCreateTagDialog(
                          context,
                          appState,
                        );
                        if (newTag != null) {
                          setState(() {
                            _tag = newTag;
                            _subTag = null;
                          });
                        } else {
                          setState(() {
                            _tag = appState.taskTags.isNotEmpty ? appState.taskTags.first : '';
                            _subTag = null;
                          });
                        }
                      } else if (val != null) {
                        final defaultColor = appState.getTaskTagColor(val);
                        setState(() {
                          if (_tag != val) {
                            _superTaskId =
                                null; // Detach from super task if tag changes
                          }
                          _tag = val;
                          _subTag = null;
                          // Apply category default color only if task is new
                          if (widget.existingTask == null && defaultColor != null) {
                            _colorValue = defaultColor;
                          }
                        });
                      }
                    },
                  ),
                   if (_tag.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('subtag_dropdown_$_tag'),
                      initialValue:
                          (appState.taskSubTags[_tag] ?? []).contains(_subTag)
                          ? _subTag
                          : null,
                      decoration: const InputDecoration(labelText: 'Alt Tag'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Hiçbiri'),
                        ),
                        ...(appState.taskSubTags[_tag] ?? []).map(
                          (st) => DropdownMenuItem<String?>(
                            value: st,
                            child: Text(st),
                          ),
                        ),
                        const DropdownMenuItem<String?>(
                          value: 'add_new_subtag',
                          child: Text(
                            '+ Yeni Alt Tag Ekle...',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) async {
                        if (val == 'add_new_subtag') {
                          final newSubTag = await _showCreateSubTagDialog(
                            context,
                            appState,
                            _tag,
                          );
                          if (newSubTag != null) {
                            setState(() {
                              _subTag = newSubTag;
                            });
                          } else {
                            setState(() {
                              _subTag = null;
                            });
                          }
                        } else {
                          setState(() {
                            if (_subTag != val) {
                              _superTaskId =
                                  null; // Detach from super task if subtag changes
                            }
                            _subTag = val;
                          });
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _importance,
                    decoration: const InputDecoration(
                      labelText: 'Önem Seviyesi',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Düşük')),
                      DropdownMenuItem(value: 1, child: Text('Orta')),
                      DropdownMenuItem(
                        value: 2,
                        child: Text('Yüksek (Kırmızı)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _importance = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_hasDate && !widget.isSingleOccurrenceEdit)
                    ListTile(
                      title: const Text('Tekrarlama'),
                      subtitle: Text(
                        RRuleTranslator.translate(_recurrenceRule),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showRecurrenceOptions(context),
                    ),
                  // --- BİLDİRİM BÖLÜMÜ (Madde 4) ---
                  if (_hasDate) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Bildirimler',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                          label = '10 dakika önce';
                        } else if (offset == 30) {
                          label = '30 dakika önce';
                        } else if (offset == 60) {
                          label = '1 saat önce';
                        } else if (offset == 120) {
                          label = '2 saat önce';
                        } else if (offset == 1440) {
                          label = '1 gün önce';
                        } else if (offset == 10080) {
                          label = '1 hafta önce';
                        } else {
                          if (offset >= 1440) {
                            label = '${offset ~/ 1440} gün önce';
                          } else if (offset >= 60) {
                            label = '${offset ~/ 60} saat önce';
                          } else {
                            label = '$offset dakika önce';
                          }
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
    if (_formKey.currentState!.validate()) {
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
        colorValue: _colorValue,
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
              title: const Text('Özel Bildirim Süresi'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: valueCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Miktar',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: unit,
                        items: const [
                          DropdownMenuItem(
                            value: 'minutes',
                            child: Text('Dakika'),
                          ),
                          DropdownMenuItem(value: 'hours', child: Text('Saat')),
                          DropdownMenuItem(value: 'days', child: Text('Gün')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              unit = val;
                            });
                          }
                        },
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
                    final int? val = int.tryParse(valueCtrl.text);
                    if (val == null || val <= 0) {
                      Navigator.pop(context, null);
                      return;
                    }
                    int minutes = val;
                    if (unit == 'hours') {
                      minutes = val * 60;
                    } else if (unit == 'days') {
                      minutes = val * 1440;
                    }
                    Navigator.pop(context, minutes);
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

