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
  late double _targetValue;
  bool _isArchived = false;
  late bool _trackPercentage;
  late bool _trackNumeric;
  late bool _trackDuration;
  late bool _trackNetHours;
  late bool _trackNote;
  late List<String> _dataOrder;

  late TextEditingController _defaultPercentageController;
  late TextEditingController _defaultNumericController;
  late TextEditingController _defaultDurationController;

  String _getDataOrderTitle(String type) {
    switch (type) {
      case 'BRUT':
        return 'Saat / Süre Girdisi';
      case 'PERCENTAGE':
        return 'Yüzdesel Başarı (%)';
      case 'NET':
        return 'Net Çalışma Saati';
      case 'NUMERIC':
        return 'Sayısal Değer';
      case 'NOTE':
        return 'Günlük Notlar';
      default:
        return type;
    }
  }

  @override
  void initState() {
    super.initState();
    final proj = widget.existingProject;
    _titleController = TextEditingController(text: proj?.title ?? '');
    _detailsController = TextEditingController(text: proj?.description ?? '');
    _tag = proj?.tag ?? 'Genel';
    _subTag = proj?.subTag;
    _targetValue = proj?.targetValue ?? 100.0;
    _isArchived = proj?.isArchived ?? false;
    _trackPercentage = proj?.trackPercentage ?? true;
    _trackNumeric = proj?.trackNumeric ?? false;
    _trackDuration = proj?.trackDuration ?? true;
    _trackNetHours = proj?.trackNetHours ?? true;
    _trackNote = proj?.trackNote ?? true;
    _dataOrder = List<String>.from(proj?.dataOrder ?? ['BRUT', 'PERCENTAGE', 'NET', 'NUMERIC', 'NOTE']);

    _defaultPercentageController = TextEditingController(
      text: proj?.defaultPercentage?.toStringAsFixed(0) ?? '',
    );
    _defaultNumericController = TextEditingController(
      text: proj?.defaultNumeric?.toString() ?? '',
    );
    _defaultDurationController = TextEditingController(
      text: proj?.defaultDuration?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _defaultPercentageController.dispose();
    _defaultNumericController.dispose();
    _defaultDurationController.dispose();
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
            const Text('Takip Edilecek Veriler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Yüzdesel Başarı (%)'),
              value: _trackPercentage,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _trackPercentage = val;
                    if (!val) {
                      _trackNetHours = false;
                    }
                  });
                }
              },
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            if (_trackPercentage)
              Padding(
                padding: const EdgeInsets.only(left: 32.0, right: 16.0, bottom: 8.0),
                child: TextFormField(
                  controller: _defaultPercentageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Varsayılan Yüzde Başarı Değeri (%)',
                    hintText: 'Örn: 80',
                    isDense: true,
                  ),
                ),
              ),
            CheckboxListTile(
              title: const Text('Sayısal Değer'),
              value: _trackNumeric,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _trackNumeric = val;
                  });
                }
              },
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            if (_trackNumeric)
              Padding(
                padding: const EdgeInsets.only(left: 32.0, right: 16.0, bottom: 8.0),
                child: TextFormField(
                  controller: _defaultNumericController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Varsayılan Sayısal Değer',
                    hintText: 'Örn: 5',
                    isDense: true,
                  ),
                ),
              ),
            CheckboxListTile(
              title: const Text('Süre Girdisi (Saat/Dakika)'),
              value: _trackDuration,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _trackDuration = val;
                    if (!val) {
                      _trackNetHours = false;
                    }
                  });
                }
              },
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            if (_trackDuration)
              Padding(
                padding: const EdgeInsets.only(left: 32.0, right: 16.0, bottom: 8.0),
                child: TextFormField(
                  controller: _defaultDurationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Varsayılan Süre Değeri (Saat)',
                    hintText: 'Örn: 3',
                    isDense: true,
                  ),
                ),
              ),
            if (_trackPercentage && _trackDuration)
              CheckboxListTile(
                title: const Text('Net Saat Hesaplaması (Yüzdeye göre)'),
                value: _trackNetHours,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _trackNetHours = val;
                    });
                  }
                },
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            CheckboxListTile(
              title: const Text('Not / Açıklama'),
              value: _trackNote,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _trackNote = val;
                  });
                }
              },
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            const SizedBox(height: 16),
            if (_trackNumeric) ...[
              TextFormField(
                initialValue: _targetValue.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sayısal Hedef Değer'),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null) {
                    _targetValue = parsed;
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
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
            const SizedBox(height: 16),
            const Text(
              'Matris Veri Gösterim Sırası (Sürükleyip Sıralayabilirsiniz)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (int index = 0; index < _dataOrder.length; index++) ...[
                    ListTile(
                      key: ValueKey(_dataOrder[index]),
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                      ),
                      title: Text(_getDataOrderTitle(_dataOrder[index])),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (index > 0)
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              onPressed: () {
                                setState(() {
                                  final item = _dataOrder.removeAt(index);
                                  _dataOrder.insert(index - 1, item);
                                });
                              },
                            ),
                          if (index < _dataOrder.length - 1)
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              onPressed: () {
                                setState(() {
                                  final item = _dataOrder.removeAt(index);
                                  _dataOrder.insert(index + 1, item);
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    if (index < _dataOrder.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
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
      
      final double? defPct = double.tryParse(_defaultPercentageController.text);
      final double? defNum = double.tryParse(_defaultNumericController.text);
      final double? defDur = double.tryParse(_defaultDurationController.text);

      final proj = Project(
        id: widget.existingProject?.id ?? IdGenerator.generate(_titleController.text),
        title: _titleController.text,
        description: _detailsController.text,
        colorValue: tagColor,
        tag: _tag,
        subTag: _subTag,
        evaluationType: _trackPercentage ? 'PERCENTAGE' : 'NUMERIC',
        targetValue: _targetValue,
        isArchived: _isArchived,
        trackPercentage: _trackPercentage,
        trackNumeric: _trackNumeric,
        trackDuration: _trackDuration,
        trackNetHours: _trackNetHours,
        trackNote: _trackNote,
        defaultPercentage: _trackPercentage ? defPct : null,
        defaultNumeric: _trackNumeric ? defNum : null,
        defaultDuration: _trackDuration ? defDur : null,
        dataOrder: _dataOrder,
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
