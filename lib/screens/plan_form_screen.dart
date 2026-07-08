import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/id_generator.dart';
import '../providers/app_state.dart';
import '../models/topic.dart';
import '../models/topic_plan.dart';

class PlanFormScreen extends StatefulWidget {
  final Topic topic;
  final TopicPlan? plan; // If null, we are adding.
  final String? parentId; // If not null, we are adding a sub-tag.
  final String? projectId;
  final DateTime? initialStartDate;

  const PlanFormScreen({
    super.key,
    required this.topic,
    this.plan,
    this.parentId,
    this.projectId,
    this.initialStartDate,
  });

  @override
  State<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<PlanFormScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _targetHoursController;
  late int _colorValue;
  late int _importance;
  late String _status;
  String? _selectedTopicId;
  late List<int> _excludedWeekdays;

  final List<Map<String, dynamic>> _planColors = [
    {'name': 'teal', 'color': Colors.teal, 'value': 0xFF009688},
    {'name': 'blue', 'color': Colors.blue, 'value': 0xFF2196F3},
    {'name': 'orange', 'color': Colors.orange, 'value': 0xFFFF9800},
    {'name': 'red', 'color': Colors.red, 'value': 0xFFF44336},
    {'name': 'purple', 'color': Colors.purple, 'value': 0xFF9C27B0},
    {'name': 'green', 'color': Colors.green, 'value': 0xFF4CAF50},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _titleController = TextEditingController(text: p?.title ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _targetHoursController = TextEditingController(text: (p?.targetHours ?? 0.0).toString());
    _colorValue = p?.colorValue ?? (widget.parentId != null ? 0xFF4CAF50 : 0xFF009688);
    _importance = p?.importance ?? 0;
    _status = p?.status ?? 'Yapılacak';
    if (_status == 'Başlanmadı') {
      _status = 'Yapılacak';
    }
    _selectedTopicId = (p?.topicId == null || p!.topicId.isEmpty) ? widget.topic.id : p.topicId;
    _excludedWeekdays = List<int>.from(p?.excludedWeekdays ?? []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _targetHoursController.dispose();
    super.dispose();
  }

  int _getWeekOfMonth(DateTime date) {
    int day = date.day;
    if (day <= 7) return 1;
    if (day <= 14) return 2;
    if (day <= 21) return 3;
    return 4;
  }

  void _saveForm() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir başlık girin')),
      );
      return;
    }

    final double targetHours = double.tryParse(_targetHoursController.text.trim()) ?? 0.0;
    final DateTime targetDate = widget.initialStartDate ?? widget.plan?.startDate ?? DateTime.now();

    final appState = Provider.of<AppState>(context, listen: false);

    if (widget.plan == null) {
      final newPlan = TopicPlan(
        id: IdGenerator.generate(widget.parentId != null ? 'altplan_$title' : 'plan_$title'),
        topicId: _selectedTopicId ?? widget.topic.id,
        title: title,
        description: _descController.text.trim(),
        startMonth: targetDate.month,
        startWeek: _getWeekOfMonth(targetDate),
        endMonth: targetDate.month,
        endWeek: _getWeekOfMonth(targetDate),
        year: targetDate.year,
        colorValue: _colorValue,
        parentId: widget.parentId,
        dependsOnPlanId: null,
        dependsOnType: null,
        importance: _importance,
        projectId: widget.projectId,
        targetHours: targetHours,
        startDate: targetDate,
        endDate: targetDate,
        durationDays: null,
        excludeWeekends: false,
        status: _status,
        excludedWeekdays: _excludedWeekdays,
        excludedDates: const [],
      );
      appState.addTopicPlan(newPlan);
    } else {
      final updated = widget.plan!.copyWith(
        topicId: _selectedTopicId ?? widget.topic.id,
        title: title,
        description: _descController.text.trim(),
        startMonth: targetDate.month,
        startWeek: _getWeekOfMonth(targetDate),
        endMonth: targetDate.month,
        endWeek: _getWeekOfMonth(targetDate),
        colorValue: _colorValue,
        dependsOnPlanId: null,
        dependsOnType: null,
        importance: _importance,
        targetHours: targetHours,
        startDate: targetDate,
        endDate: targetDate,
        durationDays: null,
        excludeWeekends: false,
        status: _status,
        excludedWeekdays: _excludedWeekdays,
        excludedDates: const [],
        clearDependency: true,
        isInPool: false,
      );
      appState.updateTopicPlan(updated);
    }

    Navigator.pop(context);
  }

  void _confirmDeletePlan(BuildContext context, TopicPlan plan, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adımı Sil'),
        content: Text('"${plan.title}" adımını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              appState.deleteTopicPlan(plan.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isEdit = widget.plan != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit
              ? '${widget.parentId != null ? "Alt Tag" : "Üst Tag"} Düzenle'
              : '${widget.parentId != null ? "Alt Tag" : "Üst Tag"} Ekle',
        ),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeletePlan(context, widget.plan!, appState),
            ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveForm,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Başlık'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(labelText: 'Detaylar / Açıklama'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _targetHoursController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Hedef Süre (Saat)'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _importance,
            decoration: const InputDecoration(labelText: 'Önem Derecesi'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Düşük')),
              DropdownMenuItem(value: 1, child: Text('Orta')),
              DropdownMenuItem(value: 2, child: Text('Yüksek')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _importance = val);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Durum'),
            items: const [
              DropdownMenuItem(value: 'Yapılacak', child: Text('Yapılacak')),
              DropdownMenuItem(value: 'Yapılanlar', child: Text('Yapılanlar')),
              DropdownMenuItem(value: 'Bekleyenler', child: Text('Bekleyenler')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _status = val);
            },
          ),
          const SizedBox(height: 24),
          const Text('Renk Seçimi', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            children: _planColors.map((colorMap) {
              final int colorVal = colorMap['value'] as int;
              return GestureDetector(
                onTap: () => setState(() => _colorValue = colorVal),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(colorVal),
                  child: _colorValue == colorVal
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
