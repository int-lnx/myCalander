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
  late String _tag;
  String? _subTag;
  late String _evaluationType;
  late double _targetValue;
  bool _isArchived = false;

  @override
  void initState() {
    super.initState();
    final proj = widget.existingProject;
    _titleController = TextEditingController(text: proj?.title ?? '');
    _detailsController = TextEditingController(text: proj?.description ?? '');
    _tag = proj?.tag ?? 'Genel';
    _subTag = proj?.subTag;
    _evaluationType = proj?.evaluationType ?? 'PERCENTAGE';
    _targetValue = proj?.targetValue ?? 100.0;
    _isArchived = proj?.isArchived ?? false;
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
              initialValue: _evaluationType,
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
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: appState.eventTags.contains(_tag)
                  ? _tag
                  : (appState.eventTags.isNotEmpty ? appState.eventTags.first : 'Genel'),
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: appState.eventTags.map((t) {
                return DropdownMenuItem(value: t, child: Text(t));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _tag = val;
                    _subTag = null;
                  });
                }
              },
            ),
            if (_tag.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                key: ValueKey('project_subtag_$_tag'),
                initialValue: (appState.eventSubTags[_tag] ?? []).contains(_subTag) ? _subTag : null,
                decoration: const InputDecoration(labelText: 'Alt Kategori'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Hiçbiri')),
                  ...(appState.eventSubTags[_tag] ?? []).map((st) => DropdownMenuItem<String?>(value: st, child: Text(st))),
                ],
                onChanged: (val) {
                  setState(() {
                    _subTag = val;
                  });
                },
              ),
            ],
            if (widget.existingProject != null) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Projeyi Arşivle'),
                subtitle: const Text('Arşivlenen projeler matriste görüntülenmez.'),
                value: _isArchived,
                onChanged: (val) {
                  setState(() {
                    _isArchived = val;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _save(AppState appState) {
    if (_formKey.currentState!.validate()) {
      // Auto-assign project color from category tag
      final tagColor = appState.getEventTagColor(_tag) ?? 0xFF2196F3;
      
      final proj = Project(
        id: widget.existingProject?.id ?? IdGenerator.generate(_titleController.text),
        title: _titleController.text,
        description: _detailsController.text,
        colorValue: tagColor,
        tag: _tag,
        subTag: _subTag,
        evaluationType: _evaluationType,
        targetValue: _targetValue,
        isArchived: _isArchived,
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
