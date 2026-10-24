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

class _ProjectFormScreenState extends State<ProjectFormScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Ortak alanlar
  final _normalFormKey = GlobalKey<FormState>();
  final _parentFormKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _detailsController;
  late String _tag;
  String? _subTag;
  bool _isArchived = false;

  // Normal Proje Özel Alanları
  late double _targetValue;
  late bool _trackPercentage;
  late bool _trackNumeric;
  late bool _trackDuration;
  late bool _trackNetHours;
  late bool _trackNote;
  late List<String> _dataOrder;
  late TextEditingController _defaultPercentageController;
  late TextEditingController _defaultNumericController;
  late TextEditingController _defaultDurationController;
  List<ProjectStep> _checkSteps = [];

  // Üst Proje Özel Alanları
  late TextEditingController _parentTitleController;
  late TextEditingController _parentDetailsController;
  late String _parentTag;
  String? _parentSubTag;
  late String _subProjectAggregation; // 'MAX', 'AVG', 'MIN'
  List<String> _selectedChildProjectIds = [];

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
    final isExistingParent = proj?.isParentProject ?? false;

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: isExistingParent ? 1 : 0,
    );

    // Normal Proje Başlangıç Değerleri
    _titleController = TextEditingController(text: !isExistingParent ? (proj?.title ?? '') : '');
    _detailsController = TextEditingController(text: !isExistingParent ? (proj?.description ?? '') : '');
    _tag = (!isExistingParent && proj != null) ? proj.tag : 'Genel';
    _subTag = !isExistingParent ? proj?.subTag : null;
    _targetValue = proj?.targetValue ?? 100.0;
    _isArchived = proj?.isArchived ?? false;
    _trackPercentage = proj?.trackPercentage ?? true;
    _trackNumeric = proj?.trackNumeric ?? false;
    _trackDuration = proj?.trackDuration ?? true;
    _trackNetHours = proj?.trackNetHours ?? true;
    _trackNote = proj?.trackNote ?? true;
    _dataOrder = List<String>.from(proj?.dataOrder ?? ['BRUT', 'PERCENTAGE', 'NET', 'NUMERIC', 'NOTE']);
    _defaultPercentageController = TextEditingController(
      text: (!isExistingParent && proj?.defaultPercentage != null) ? proj!.defaultPercentage!.toStringAsFixed(0) : '',
    );
    _defaultNumericController = TextEditingController(
      text: (!isExistingParent && proj?.defaultNumeric != null) ? proj!.defaultNumeric!.toString() : '',
    );
    _defaultDurationController = TextEditingController(
      text: (!isExistingParent && proj?.defaultDuration != null) ? proj!.defaultDuration!.toString() : '',
    );
    _checkSteps = List<ProjectStep>.from(proj?.checkSteps ?? []);

    // Üst Proje Başlangıç Değerleri
    _parentTitleController = TextEditingController(text: isExistingParent ? (proj?.title ?? '') : '');
    _parentDetailsController = TextEditingController(text: isExistingParent ? (proj?.description ?? '') : '');
    _parentTag = (isExistingParent && proj != null) ? proj.tag : 'Genel';
    _parentSubTag = isExistingParent ? proj?.subTag : null;
    _subProjectAggregation = proj?.subProjectAggregation ?? 'MAX';
    _selectedChildProjectIds = List<String>.from(proj?.childProjectIds ?? []);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _detailsController.dispose();
    _defaultPercentageController.dispose();
    _defaultNumericController.dispose();
    _defaultDurationController.dispose();
    _parentTitleController.dispose();
    _parentDetailsController.dispose();
    super.dispose();
  }

  void _showStepDialog({int? editIndex}) {
    final isEditing = editIndex != null;
    final initialStep = isEditing ? _checkSteps[editIndex] : null;
    final titleCtrl = TextEditingController(text: initialStep?.title ?? '');
    final weightCtrl = TextEditingController(
      text: initialStep?.weight != null ? initialStep!.weight!.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Kontrol Adımını Düzenle' : 'Kontrol Adımı Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Adım Adı (örn: Spor)',
                hintText: 'Adım açıklamasını yazın',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightCtrl,
              decoration: const InputDecoration(
                labelText: 'Ağırlık Yüzdesi (Opsiyonel, Örn: 30)',
                hintText: 'Boş bırakılırsa kalan ağırlık eşit dağıtılır',
                suffixText: '%',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              if (title.isNotEmpty) {
                final weight = double.tryParse(weightCtrl.text.trim());
                setState(() {
                  final newStep = ProjectStep(title: title, weight: weight);
                  if (isEditing) {
                    _checkSteps[editIndex] = newStep;
                  } else {
                    _checkSteps.add(newStep);
                  }
                });
              }
              Navigator.pop(context);
            },
            child: Text(isEditing ? 'Güncelle' : 'Ekle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isEditing = widget.existingProject != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing
            ? (widget.existingProject!.isParentProject ? 'Üst Proje Düzenle' : 'Proje Düzenle')
            : 'Yeni Proje Ekle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _save(appState),
          ),
        ],
        bottom: isEditing
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.assignment), text: 'Normal Proje'),
                  Tab(icon: Icon(Icons.account_tree), text: 'Üst Proje Oluştur'),
                ],
              ),
      ),
      body: isEditing
          ? (widget.existingProject!.isParentProject
              ? _buildParentProjectForm(appState)
              : _buildNormalProjectForm(appState))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNormalProjectForm(appState),
                _buildParentProjectForm(appState),
              ],
            ),
    );
  }

  // NORMAL PROJE FORMU
  Widget _buildNormalProjectForm(AppState appState) {
    return Form(
      key: _normalFormKey,
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
                  if (!val) _trackNetHours = false;
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
                  if (!val) _trackNetHours = false;
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
          const Divider(),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kontrol Adımları (Opsiyonel)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (_checkSteps.isNotEmpty)
                Text(
                  '${_checkSteps.length} Adım',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_checkSteps.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'Henüz kontrol adımı eklenmedi.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _checkSteps.length; i++) ...[
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                      ),
                      title: Text(
                        _checkSteps[i].title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: _checkSteps[i].weight != null
                          ? Text(
                              'Ağırlık: %${_checkSteps[i].weight!.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                            )
                          : null,
                      onTap: () => _showStepDialog(editIndex: i),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                            tooltip: 'Düzenle',
                            onPressed: () => _showStepDialog(editIndex: i),
                          ),
                          if (i > 0)
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              tooltip: 'Yukarı Taşı',
                              onPressed: () {
                                setState(() {
                                  final item = _checkSteps.removeAt(i);
                                  _checkSteps.insert(i - 1, item);
                                });
                              },
                            ),
                          if (i < _checkSteps.length - 1)
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              tooltip: 'Aşağı Taşı',
                              onPressed: () {
                                setState(() {
                                  final item = _checkSteps.removeAt(i);
                                  _checkSteps.insert(i + 1, item);
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 19),
                            tooltip: 'Sil',
                            onPressed: () {
                              setState(() {
                                _checkSteps.removeAt(i);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    if (i < _checkSteps.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Kontrol Adımı Ekle', style: TextStyle(fontSize: 12)),
            onPressed: () => _showStepDialog(),
          ),
          const SizedBox(height: 16),
          if (widget.existingProject != null) ...[
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
    );
  }

  // ÜST PROJE OLUŞTURMA FORMU
  Widget _buildParentProjectForm(AppState appState) {
    // Alt proje olarak seçilebilecek projeler: Kendisi hariç ve başka üst proje olmayan projeler
    final availableProjects = appState.projects
        .where((p) => !p.isParentProject && p.id != widget.existingProject?.id && !p.isArchived)
        .toList();

    return Form(
      key: _parentFormKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Üst Proje, altında yer alan alt projelerin günlük log kayıtlarını seçtiğiniz kurala göre otomatik toplar ve matriste onların üstünde listelenir.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _parentTitleController,
            decoration: const InputDecoration(
              labelText: 'Üst Proje Başlığı (Örn: Düzenli Spor)',
              prefixIcon: Icon(Icons.folder_open),
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Üst proje başlığı gerekli' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _parentDetailsController,
            decoration: const InputDecoration(labelText: 'Açıklama (Opsiyonel)'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: appState.eventTags.contains(_parentTag)
                ? _parentTag
                : (appState.eventTags.isNotEmpty ? appState.eventTags.first : 'Genel'),
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: appState.eventTags.map((t) {
              return DropdownMenuItem(value: t, child: Text(t));
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _parentTag = val;
                  _parentSubTag = null;
                });
              }
            },
          ),
          if (_parentTag.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              key: ValueKey('parent_project_subtag_$_parentTag'),
              initialValue: (appState.eventSubTags[_parentTag] ?? []).contains(_parentSubTag) ? _parentSubTag : null,
              decoration: const InputDecoration(labelText: 'Alt Kategori'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Hiçbiri')),
                ...(appState.eventSubTags[_parentTag] ?? []).map((st) => DropdownMenuItem<String?>(value: st, child: Text(st))),
              ],
              onChanged: (val) {
                setState(() {
                  _parentSubTag = val;
                });
              },
            ),
          ],
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _subProjectAggregation,
            decoration: const InputDecoration(
              labelText: 'Değer Hesaplama Kuralı',
              helperText: 'Alt projelerin günlük logları üst projeye nasıl yansısın?',
              prefixIcon: Icon(Icons.calculate_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'MAX', child: Text('En Yüksek Olanı Al (Maksimum)')),
              DropdownMenuItem(value: 'AVG', child: Text('Alt Projelerin Ortalamasını Al')),
              DropdownMenuItem(value: 'MIN', child: Text('En Düşük Olanı Al (Minimum)')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _subProjectAggregation = val;
                });
              }
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bağlı Alt Projeler',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                '${_selectedChildProjectIds.length} proje seçildi',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Bu üst projenin altına dahil etmek istediğiniz projeleri işaretleyin. Bir alt proje birden fazla üst projeye eklenebilir.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (availableProjects.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text('Alt proje olarak eklenebilecek aktif proje bulunamadı.', style: TextStyle(color: Colors.grey)),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: availableProjects.map((p) {
                  final isSelected = _selectedChildProjectIds.contains(p.id);
                  final pColor = appState.getEventTagColor(p.tag) ?? p.colorValue;

                  return CheckboxListTile(
                    value: isSelected,
                    secondary: CircleAvatar(
                      radius: 6,
                      backgroundColor: Color(pColor),
                    ),
                    title: Text(p.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text('Kategori: ${p.tag} • ${p.evaluationType == "PERCENTAGE" ? "% Yüzdelik" : "Sayısal"}', style: const TextStyle(fontSize: 11)),
                    onChanged: (bool? checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedChildProjectIds.add(p.id);
                        } else {
                          _selectedChildProjectIds.remove(p.id);
                        }
                      });
                    },
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 24),
          if (widget.existingProject != null) ...[
            SwitchListTile(
              title: const Text('Üst Projeyi Arşivle'),
              subtitle: const Text('Arşivlenen üst projeler matriste görüntülenmez.'),
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
    );
  }

  void _save(AppState appState) {
    final bool isParentTab = widget.existingProject != null
        ? widget.existingProject!.isParentProject
        : (_tabController.index == 1);

    if (isParentTab) {
      // Üst Proje Kaydet
      if (_parentFormKey.currentState!.validate()) {
        final tagColor = appState.getEventTagColor(_parentTag) ?? 0xFF2196F3;

        final proj = Project(
          id: widget.existingProject?.id ?? IdGenerator.generate(_parentTitleController.text),
          title: _parentTitleController.text.trim(),
          description: _parentDetailsController.text.trim(),
          colorValue: tagColor,
          tag: _parentTag,
          subTag: _parentSubTag,
          evaluationType: 'PERCENTAGE',
          targetValue: 100.0,
          isArchived: _isArchived,
          isParentProject: true,
          childProjectIds: _selectedChildProjectIds,
          subProjectAggregation: _subProjectAggregation,
          trackPercentage: true,
          trackNumeric: false,
          trackDuration: true,
          trackNetHours: false,
          trackNote: true,
        );

        if (widget.existingProject == null) {
          appState.addProject(proj);
        } else {
          appState.updateProject(proj);
        }
        Navigator.pop(context);
      }
    } else {
      // Normal Proje Kaydet
      if (_normalFormKey.currentState!.validate()) {
        final tagColor = appState.getEventTagColor(_tag) ?? 0xFF2196F3;

        final double? defPct = double.tryParse(_defaultPercentageController.text);
        final double? defNum = double.tryParse(_defaultNumericController.text);
        final double? defDur = double.tryParse(_defaultDurationController.text);

        final proj = Project(
          id: widget.existingProject?.id ?? IdGenerator.generate(_titleController.text),
          title: _titleController.text.trim(),
          description: _detailsController.text.trim(),
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
          checkSteps: _checkSteps,
          isParentProject: false,
          childProjectIds: const [],
          subProjectAggregation: 'MAX',
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
}
