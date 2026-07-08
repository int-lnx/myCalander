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
    _to = event?.to ?? (widget.initialDate != null
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

  Future<String?> _showCreateProjectTagDialog(BuildContext context, AppState appState) async {
    final tagCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Proje Etiketi Ekle'),
        content: TextField(
          controller: tagCtrl,
          decoration: const InputDecoration(labelText: 'Etiket Adı'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final name = tagCtrl.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showCreateSubTagDialog(BuildContext context, AppState appState, String parentTag) async {
    final tagCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$parentTag için Alt Etiket Ekle'),
        content: TextField(
          controller: tagCtrl,
          decoration: const InputDecoration(labelText: 'Alt Etiket Adı'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('İptal')),
          ElevatedButton(
              onPressed: () {
                final name = tagCtrl.text.trim();
                if (name.isNotEmpty) {
                  appState.addEventSubTag(parentTag, name);
                  Navigator.pop(context, name);
                }
              },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<int?> _showCustomNotificationDialog(BuildContext context) async {
    final valCtrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Özel Bildirim Süresi (Dakika)'),
        content: TextField(
          controller: valCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Kaç dakika önce bildirim gelsin?'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(valCtrl.text.trim());
              if (val != null && val >= 0) Navigator.pop(context, val);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showCreateTagDialog(BuildContext context, AppState appState) async {
    final tagCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Tag Ekle'),
        content: TextField(
          controller: tagCtrl,
          decoration: const InputDecoration(labelText: 'Tag Adı'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              final name = tagCtrl.text.trim();
              if (name.isNotEmpty) {
                appState.addEventCategory(name);
                Navigator.pop(context, name);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<Project?> _showCreateProjectDialog(BuildContext context, AppState appState) async {
    final titleCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    int selectedColor = _colors[0];

    return showDialog<Project>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                  controller: descriptionCtrl,
                  decoration: const InputDecoration(labelText: 'Açıklama (İsteğe Bağlı)'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8.0,
                  children: _colors.map((color) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(color),
                        child: selectedColor == color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('İptal')),
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
        ),
      ),
    );
  }

  void _saveForm(BuildContext context, AppState appState) async {
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
        final oldEvent = widget.existingEvent!;
        appState.updateEvent(event);
        Navigator.pop(context, true);
        return;
      }
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Etkinlik Başlığı'),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Başlık gerekli' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _detailsController,
              decoration: const InputDecoration(labelText: 'Açıklama / Detaylar'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Tüm Gün'),
              value: _isAllDay,
              onChanged: (val) => setState(() => _isAllDay = val),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Başlangıç Zamanı'),
              subtitle: Text('${_from.day}/${_from.month}/${_from.year} ${_isAllDay ? "" : "${_from.hour}:${_from.minute}"}'),
              onTap: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: _from,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (pickedDate != null) {
                  setState(() {
                    _from = DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      _from.hour,
                      _from.minute,
                    );
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            const Text('Renk Seçimi', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              children: _colors.map((color) {
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = color),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(color),
                    child: _colorValue == color ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
