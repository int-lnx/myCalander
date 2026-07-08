import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/event.dart';
import '../utils/id_generator.dart';
import '../models/project.dart';
import '../utils/rrule_translator.dart';
import 'custom_recurrence_dialog.dart';

class EventFormScreen extends StatefulWidget {
  final Event? existingEvent;
  final DateTime? initialDate;
  final bool isSingleOccurrenceEdit;
  const EventFormScreen({
    super.key,
    this.existingEvent,
    this.initialDate,
    this.isSingleOccurrenceEdit = false,
  });

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _detailsController;
  late DateTime _from;
  late DateTime _to;
  late int _colorValue;
  late String _tag;
  String? _subTag;
  late int _importance;
  late bool _isAllDay;
  String? _recurrenceRule;
  String? _projectId;
  late bool _isTrackingEnabled;
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
    final event = widget.existingEvent;
    _titleController = TextEditingController(text: event?.title ?? '');
    _detailsController = TextEditingController(text: event?.description ?? '');
    _from = event?.from ?? widget.initialDate ?? DateTime.now();
    _to = event?.to ??
        (widget.initialDate != null
            ? widget.initialDate!.add(const Duration(hours: 1))
            : DateTime.now().add(const Duration(hours: 1)));
    _colorValue = event?.colorValue ?? _colors[0];
    _tag = event?.tag ?? 'Genel';
    _subTag = event?.subTag;
    _importance = event?.importance ?? 0;
    _isAllDay = event?.isAllDay ?? false;
    _recurrenceRule = event?.recurrenceRule;
    _projectId = event?.projectId;
    _isTrackingEnabled = event?.isTrackingEnabled ?? false;
    _projectTag = event?.projectTag;
    _notificationOffsets = event?.notificationOffsets != null
        ? List<int>.from(event!.notificationOffsets)
        : [];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  // ── Helper dialogs ────────────────────────────────────────────────────────

  Future<String?> _showCreateTagDialog(
      BuildContext context, AppState appState) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Kategori Ekle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Kategori Adı'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                appState.addEventCategory(name);
                Navigator.pop(ctx, name);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showCreateSubTagDialog(
      BuildContext context, AppState appState, String parentTag) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$parentTag için Alt Kategori Ekle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Alt Kategori Adı'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                appState.addEventSubTag(parentTag, name);
                Navigator.pop(ctx, name);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showCreateProjectTagDialog(
      BuildContext context, AppState appState, Project project) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Proje Etiketi Ekle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Etiket Adı'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) Navigator.pop(ctx, name);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<Project?> _showCreateProjectDialog(
      BuildContext context, AppState appState) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int selectedColor = _colors[0];
    return showDialog<Project>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Yeni Proje Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Proje Başlığı'),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Açıklama (İsteğe Bağlı)'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: _colors.map((c) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = c),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(c),
                        child: selectedColor == c
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isNotEmpty) {
                  final newProj = Project(
                    id: IdGenerator.generate(title),
                    title: title,
                    description: descCtrl.text.trim(),
                    colorValue: selectedColor,
                    evaluationType: 'PERCENTAGE',
                    targetValue: 100.0,
                  );
                  appState.addProject(newProj);
                  Navigator.pop(ctx, newProj);
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _showCustomNotificationDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Özel Bildirim Süresi (Dakika)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Kaç dakika önce bildirim gelsin?'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val >= 0) Navigator.pop(ctx, val);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  // ── Date/Time helpers ─────────────────────────────────────────────────────

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final initial = isStart ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _from = DateTime(picked.year, picked.month, picked.day, _from.hour, _from.minute);
          if (_to.isBefore(_from)) _to = _from.add(const Duration(hours: 1));
        } else {
          _to = DateTime(picked.year, picked.month, picked.day, _to.hour, _to.minute);
          if (_to.isBefore(_from)) _from = _to.subtract(const Duration(hours: 1));
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final initial = isStart ? _from : _to;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _from = DateTime(_from.year, _from.month, _from.day, picked.hour, picked.minute);
          if (_to.isBefore(_from)) _to = _from.add(const Duration(hours: 1));
        } else {
          _to = DateTime(_to.year, _to.month, _to.day, picked.hour, picked.minute);
          if (_to.isBefore(_from)) _from = _to.subtract(const Duration(hours: 1));
        }
      });
    }
  }

  Widget _buildDurationChip(String label, int minutes) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        onPressed: () => setState(() => _to = _from.add(Duration(minutes: minutes))),
      ),
    );
  }

  // ── Recurrence ────────────────────────────────────────────────────────────

  void _updateRRule(String? rule) {
    setState(() => _recurrenceRule = rule);
    Navigator.pop(context);
  }

  void _showRecurrenceOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Tekrarlama (Yok)'), onTap: () => _updateRRule(null)),
            ListTile(title: const Text('Her Gün'), onTap: () => _updateRRule('FREQ=DAILY')),
            ListTile(
              title: const Text('Her Hafta'),
              onTap: () {
                const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
                _updateRRule('FREQ=WEEKLY;BYDAY=${days[_from.weekday - 1]}');
              },
            ),
            ListTile(title: const Text('Her Ay'), onTap: () => _updateRRule('FREQ=MONTHLY')),
            ListTile(title: const Text('Her Yıl'), onTap: () => _updateRRule('FREQ=YEARLY')),
            ListTile(
              title: const Text('Özel...'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => CustomRecurrenceDialog(
                    initialRRule: _recurrenceRule,
                    eventDate: _from,
                  ),
                );
                if (result != null) setState(() => _recurrenceRule = result);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _saveForm(BuildContext context, AppState appState) {
    if (_formKey.currentState!.validate()) {
      final event = Event(
        id: widget.existingEvent?.id ?? IdGenerator.generate(_titleController.text),
        title: _titleController.text,
        description: _detailsController.text,
        from: _from,
        to: _to,
        isAllDay: _isAllDay,
        colorValue: _colorValue,
        tag: _tag,
        subTag: _subTag,
        importance: _importance,
        recurrenceRule: _recurrenceRule,
        recurrenceExceptionDates: widget.existingEvent?.recurrenceExceptionDates,
        projectId: _projectId,
        isTrackingEnabled: _isTrackingEnabled,
        projectTag: _projectId != null ? _projectTag : null,
        notificationOffsets: _notificationOffsets,
      );

      if (widget.existingEvent == null || !appState.events.any((e) => e.id == event.id)) {
        appState.addEvent(event);
      } else {
        appState.updateEvent(event);
      }
      Navigator.pop(context, true);
    }
  }

  // ── Notification label helper ─────────────────────────────────────────────

  String _offsetLabel(int offset) {
    if (offset == 0) return 'Etkinlik anında';
    if (offset == 10) return '10 dakika önce';
    if (offset == 30) return '30 dakika önce';
    if (offset == 60) return '1 saat önce';
    if (offset == 120) return '2 saat önce';
    if (offset == 1440) return '1 gün önce';
    if (offset == 10080) return '1 hafta önce';
    if (offset >= 1440) return '${offset ~/ 1440} gün önce';
    if (offset >= 60) return '${offset ~/ 60} saat önce';
    return '$offset dakika önce';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final eventTags = appState.eventTags;
    if (eventTags.isNotEmpty && !eventTags.contains(_tag)) {
      _tag = eventTags.first;
    }
    final eventSubTags = appState.eventSubTags[_tag] ?? [];
    final projects = appState.projects;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingEvent != null ? 'Etkinliği Düzenle' : 'Yeni Etkinlik'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _saveForm(context, appState),
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
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Başlık ──────────────────────────────────────────────
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Etkinlik Başlığı'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Başlık zorunludur' : null,
                  ),
                  const SizedBox(height: 16),

                  // ── Açıklama ────────────────────────────────────────────
                  TextFormField(
                    controller: _detailsController,
                    decoration: const InputDecoration(labelText: 'Açıklama / Detaylar'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  // ── Tüm Gün ────────────────────────────────────────────
                  SwitchListTile(
                    title: const Text('Tüm Gün (Saat Belirtme)'),
                    value: _isAllDay,
                    onChanged: (v) => setState(() => _isAllDay = v),
                  ),

                  // ── Başlangıç / Bitiş Tarihi & Saati ───────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Başlangıç Tarihi'),
                            subtitle: Text(
                                '${_from.day}/${_from.month}/${_from.year}'),
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
                                  '${_from.hour.toString().padLeft(2, '0')}:${_from.minute.toString().padLeft(2, '0')}'),
                              trailing: const Icon(Icons.access_time),
                              onTap: () => _selectTime(context, true),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Bitiş Tarihi'),
                            subtitle: Text('${_to.day}/${_to.month}/${_to.year}'),
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
                                  '${_to.hour.toString().padLeft(2, '0')}:${_to.minute.toString().padLeft(2, '0')}'),
                              trailing: const Icon(Icons.access_time),
                              onTap: () => _selectTime(context, false),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Hızlı Süre ─────────────────────────────────────────
                  if (!_isAllDay) ...[
                    const SizedBox(height: 4),
                    const Text('Hızlı Süre Seçimi',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDurationChip('Hatırlatıcı', 0),
                          _buildDurationChip('15 Dk', 15),
                          _buildDurationChip('30 Dk', 30),
                          _buildDurationChip('45 Dk', 45),
                          _buildDurationChip('1 Saat', 60),
                          _buildDurationChip('2 Saat', 120),
                          _buildDurationChip('3 Saat', 180),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── Renk ───────────────────────────────────────────────
                  const Text('Renk Seçimi',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _colors.map((c) {
                      return GestureDetector(
                        onTap: () => setState(() => _colorValue = c),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Color(c),
                          child: _colorValue == c
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Proje & Proje Etiketi ──────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: projects.any((p) => p.id == _projectId)
                              ? _projectId
                              : null,
                          decoration: const InputDecoration(
                              labelText: 'Proje (İsteğe Bağlı)'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Hiçbiri (Bağımsız)'),
                            ),
                            ...projects.map((p) => DropdownMenuItem<String?>(
                                  value: p.id,
                                  child: Text(p.title),
                                )),
                            const DropdownMenuItem<String?>(
                              value: 'add_new_project',
                              child: Text('+ Yeni Proje...',
                                  style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                          onChanged: (val) async {
                            if (val == 'add_new_project') {
                              final np =
                                  await _showCreateProjectDialog(context, appState);
                              setState(() {
                                _projectId = np?.id;
                                _projectTag = null;
                              });
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
                          child: Builder(builder: (ctx) {
                            final project = projects.firstWhere(
                              (p) => p.id == _projectId,
                              orElse: () => const Project(
                                  id: '',
                                  title: '',
                                  colorValue: 0,
                                  evaluationType: 'PERCENTAGE',
                                  targetValue: 100.0),
                            );
                            return DropdownButtonFormField<String?>(
                              initialValue:
                                  project.tags.contains(_projectTag)
                                      ? _projectTag
                                      : null,
                              decoration: const InputDecoration(
                                  labelText: 'Proje İçi Etiket'),
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null, child: Text('Etiket Yok')),
                                ...project.tags.map((t) =>
                                    DropdownMenuItem<String?>(
                                        value: t, child: Text(t))),
                                const DropdownMenuItem<String?>(
                                  value: 'add_new_project_tag',
                                  child: Text('+ Yeni Etiket...',
                                      style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                              onChanged: (val) async {
                                if (val == 'add_new_project_tag') {
                                  final nt =
                                      await _showCreateProjectTagDialog(
                                          context, appState, project);
                                  setState(() => _projectTag = nt);
                                } else {
                                  setState(() => _projectTag = val);
                                }
                              },
                            );
                          }),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Kategori (Tag) ──────────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: eventTags.contains(_tag)
                        ? _tag
                        : (eventTags.isNotEmpty ? eventTags.first : null),
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      ...eventTags.map((t) =>
                          DropdownMenuItem<String>(value: t, child: Text(t))),
                      const DropdownMenuItem<String>(
                        value: 'add_new_tag',
                        child: Text('+ Yeni Kategori Ekle...',
                            style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                    onChanged: (val) async {
                      if (val == 'add_new_tag') {
                        final nt =
                            await _showCreateTagDialog(context, appState);
                        if (nt != null) {
                          setState(() {
                            _tag = nt;
                            _subTag = null;
                          });
                        } else {
                          setState(() {
                            _tag = eventTags.isNotEmpty ? eventTags.first : '';
                            _subTag = null;
                          });
                        }
                      } else if (val != null) {
                        setState(() {
                          _tag = val;
                          _subTag = null;
                        });
                      }
                    },
                  ),

                  // ── Alt Kategori (SubTag) ───────────────────────────────
                  if (_tag.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('event_subtag_$_tag'),
                      initialValue:
                          eventSubTags.contains(_subTag) ? _subTag : null,
                      decoration:
                          const InputDecoration(labelText: 'Alt Kategori'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Hiçbiri')),
                        ...eventSubTags.map((st) => DropdownMenuItem<String?>(
                            value: st, child: Text(st))),
                        const DropdownMenuItem<String?>(
                          value: 'add_new_subtag',
                          child: Text('+ Yeni Alt Kategori Ekle...',
                              style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                      onChanged: (val) async {
                        if (val == 'add_new_subtag') {
                          final ns = await _showCreateSubTagDialog(
                              context, appState, _tag);
                          setState(() => _subTag = ns);
                        } else {
                          setState(() => _subTag = val);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── Önem Seviyesi ──────────────────────────────────────
                  DropdownButtonFormField<int>(
                    initialValue: _importance,
                    decoration:
                        const InputDecoration(labelText: 'Önem Seviyesi'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Düşük')),
                      DropdownMenuItem(value: 1, child: Text('Orta')),
                      DropdownMenuItem(
                          value: 2, child: Text('Yüksek (Kırmızı)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _importance = v);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Zaman Takibi ────────────────────────────────────────
                  SwitchListTile(
                    title: const Text('Zaman Takibini Etkinleştir'),
                    subtitle: const Text('Etkinlik için süre takibi yapılsın mı?'),
                    value: _isTrackingEnabled,
                    onChanged: (v) => setState(() => _isTrackingEnabled = v),
                  ),
                  const SizedBox(height: 8),

                  // ── Tekrarlama ─────────────────────────────────────────
                  if (!widget.isSingleOccurrenceEdit)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tekrarlama'),
                      subtitle:
                          Text(RRuleTranslator.translate(_recurrenceRule)),
                      trailing:
                          const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showRecurrenceOptions(context),
                    ),

                  // ── Bildirimler ────────────────────────────────────────
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Bildirimler',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_notificationOffsets.isEmpty)
                    const Text('Bildirim ayarlanmadı.',
                        style: TextStyle(
                            color: Colors.grey,
                            fontStyle: FontStyle.italic)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _notificationOffsets.map((o) {
                      return InputChip(
                        label: Text(_offsetLabel(o)),
                        onDeleted: () =>
                            setState(() => _notificationOffsets.remove(o)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: null,
                    hint: const Text('+ Bildirim Ekle'),
                    items: const [
                      DropdownMenuItem(value: '0', child: Text('Etkinlik anında')),
                      DropdownMenuItem(value: '10', child: Text('10 dakika önce')),
                      DropdownMenuItem(value: '30', child: Text('30 dakika önce')),
                      DropdownMenuItem(value: '60', child: Text('1 saat önce')),
                      DropdownMenuItem(value: '120', child: Text('2 saat önce')),
                      DropdownMenuItem(value: '1440', child: Text('1 gün önce')),
                      DropdownMenuItem(value: '10080', child: Text('1 hafta önce')),
                      DropdownMenuItem(value: 'custom', child: Text('Özel...')),
                    ],
                    onChanged: (val) async {
                      if (val == null) return;
                      if (val == 'custom') {
                        final cv =
                            await _showCustomNotificationDialog(context);
                        if (cv != null &&
                            !_notificationOffsets.contains(cv)) {
                          setState(() => _notificationOffsets.add(cv));
                        }
                      } else {
                        final iv = int.parse(val);
                        if (!_notificationOffsets.contains(iv)) {
                          setState(() => _notificationOffsets.add(iv));
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
