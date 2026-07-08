import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../utils/id_generator.dart';

class ProjectFormScreen extends StatefulWidget {
  final Project? existingProject;

  const ProjectFormScreen({super.key, this.existingProject});

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _detailsController;
  late int _colorValue;
  late String _tag;
  String? _subTag;
  late String _evaluationType;
  late double _targetValue;

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
    final proj = widget.existingProject;
    _titleController = TextEditingController(text: proj?.title ?? '');
    _detailsController = TextEditingController(text: proj?.description ?? '');
    _colorValue = proj?.colorValue ?? _colors[0];
    _tag = proj?.tag ?? 'Genel';
    _subTag = proj?.subTag;
    _evaluationType = proj?.evaluationType ?? 'PERCENTAGE';
    _targetValue = proj?.targetValue ?? 100.0;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingProject != null ? 'Proje Düzenle' : 'Yeni Proje'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _save(appState),
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
              decoration: const InputDecoration(labelText: 'Proje Başlığı'),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Başlık gerekli' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _detailsController,
              decoration: const InputDecoration(labelText: 'Açıklama'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _evaluationType,
              decoration: const InputDecoration(labelText: 'Değerlendirme Tipi'),
              items: const [
                DropdownMenuItem(value: 'PERCENTAGE', child: Text('Yüzde (%)')),
                DropdownMenuItem(value: 'NUMERIC', child: Text('Sayısal')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _evaluationType = val;
                    _targetValue = val == 'PERCENTAGE' ? 100.0 : 10.0;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _targetValue.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hedef Değer'),
              onChanged: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null) {
                  _targetValue = parsed;
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
                    child: _colorValue == color
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _save(AppState appState) {
    if (_formKey.currentState!.validate()) {
      final proj = Project(
        id: widget.existingProject?.id ?? IdGenerator.generate(_titleController.text),
        title: _titleController.text,
        description: _detailsController.text,
        colorValue: _colorValue,
        tag: _tag,
        subTag: _subTag,
        evaluationType: _evaluationType,
        targetValue: _targetValue,
      );

      if (widget.existingProject == null) {
        appState.addProject(proj);
      } else {
        appState.updateProject(proj);
      }
      Navigator.pop(context);
    }
  }
}
