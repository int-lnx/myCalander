import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/weekly_matrix_model.dart';
import '../providers/app_state.dart';
import '../utils/id_generator.dart';

Future<void> showWeeklyKeywordRuleDialog(
  BuildContext context,
  AppState appState, {
  WeeklyKeywordRule? existingRule,
}) async {
  final keywordCtrl = TextEditingController(text: existingRule?.keyword ?? '');
  int selectedColorValue =
      existingRule?.colorValue ?? 0xFF8E24AA; // Varsayılan Mor
  String? selectedProjectId = existingRule?.linkedProjectId;
  String? selectedTag = existingRule?.linkedTag;
  int? selectedNotificationMinutes = existingRule?.notificationMinutesBefore;

  // 0: Özel Renk, 1: Proje Bağla, 2: Kategori/Etiket Bağla
  int linkMode = 0;
  if (selectedProjectId != null && selectedProjectId.isNotEmpty) {
    linkMode = 1;
  } else if (selectedTag != null && selectedTag.isNotEmpty) {
    linkMode = 2;
  }

  const List<int> colorPalette = [
    0xFF8E24AA, // Mor (Canik)
    0xFF43A047, // Yeşil (Havuz)
    0xFFFDD835, // Sarı (Sosyal)
    0xFF1E88E5, // Mavi
    0xFFE53935, // Kırmızı
    0xFFFB8C00, // Turuncu
    0xFF00ACC1, // Turkuaz
    0xFFD81B60, // Pembe
    0xFF3949AB, // İndigo
    0xFF00897B, // Teal
    0xFF6D4C41, // Kahverengi
    0xFF546E7A, // Mavi Gri
    0xFF7CB342, // Açık Yeşil
    0xFFF4511E, // Koyu Turuncu
    0xFF5E35B1, // Koyu Mor
    0xFFC0CA33, // Lime
  ];

  final allTags = <String>{
    ...appState.eventTags,
    ...appState.taskTags,
  }.toList();

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = appState.isDarkMode;

          int previewColorValue = selectedColorValue;
          if (linkMode == 1 && selectedProjectId != null) {
            final proj = appState.projects
                .where((p) => p.id == selectedProjectId)
                .firstOrNull;
            if (proj != null) {
              previewColorValue =
                  appState.getEventTagColor(proj.tag) ??
                  appState.getTaskTagColor(proj.tag) ??
                  proj.colorValue;
            }
          } else if (linkMode == 2 && selectedTag != null) {
            previewColorValue =
                appState.getEventTagColor(selectedTag!) ??
                appState.getTaskTagColor(selectedTag!) ??
                selectedColorValue;
          }

          final previewColor = Color(previewColorValue);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: previewColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    color: previewColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    existingRule == null
                        ? 'Anahtar Kelime Kuralı Ekle'
                        : 'Anahtar Kelimeyi Düzenle',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: keywordCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Anahtar Kelime (Örn: Canik, Havuz, İş)',
                        hintText: 'Hücrede geçecek kelimeyi yazın...',
                        isDense: true,
                        prefixIcon: const Icon(Icons.key, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Renk ve Bağlantı Kaynağı:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            label: const Center(
                              child: Text(
                                'Özel Renk',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                            selected: linkMode == 0,
                            onSelected: (sel) {
                              if (sel) {
                                setDialogState(() {
                                  linkMode = 0;
                                  selectedProjectId = null;
                                  selectedTag = null;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            label: const Center(
                              child: Text(
                                'Proje Bağla',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                            selected: linkMode == 1,
                            onSelected: (sel) {
                              if (sel) {
                                setDialogState(() {
                                  linkMode = 1;
                                  selectedTag = null;
                                  if (selectedProjectId == null &&
                                      appState.projects.isNotEmpty) {
                                    selectedProjectId =
                                        appState.projects.first.id;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            label: const Center(
                              child: Text(
                                'Etiket Bağla',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                            selected: linkMode == 2,
                            onSelected: (sel) {
                              if (sel) {
                                setDialogState(() {
                                  linkMode = 2;
                                  selectedProjectId = null;
                                  if (selectedTag == null &&
                                      allTags.isNotEmpty) {
                                    selectedTag = allTags.first;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (linkMode == 0) ...[
                      const Text(
                        'Renk Seçin:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: colorPalette.map((colVal) {
                          final isSelected = selectedColorValue == colVal;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedColorValue = colVal;
                              });
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Color(colVal),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? (isDark ? Colors.white : Colors.black)
                                      : Colors.transparent,
                                  width: isSelected ? 2.5 : 1,
                                ),
                                boxShadow: [
                                  if (isSelected)
                                    BoxShadow(
                                      color: Color(
                                        colVal,
                                      ).withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      size: 18,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ] else if (linkMode == 1) ...[
                      if (appState.projects.isEmpty)
                        const Text(
                          'Henüz oluşturulmuş bir proje bulunmuyor.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue:
                              appState.projects.any(
                                (p) => p.id == selectedProjectId,
                              )
                              ? selectedProjectId
                              : appState.projects.first.id,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Bağlanacak Proje',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: appState.projects.map((p) {
                            final pCol = Color(
                              appState.getEventTagColor(p.tag) ??
                                  appState.getTaskTagColor(p.tag) ??
                                  p.colorValue,
                            );
                            return DropdownMenuItem<String>(
                              value: p.id,
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: pCol,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      p.title,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedProjectId = val;
                            });
                          },
                        ),
                    ] else if (linkMode == 2) ...[
                      if (allTags.isEmpty)
                        const Text(
                          'Henüz kategori/etiket bulunmuyor.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: allTags.contains(selectedTag)
                              ? selectedTag
                              : allTags.first,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Bağlanacak Kategori / Etiket',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: allTags.map((tag) {
                            final tCol = Color(
                              appState.getEventTagColor(tag) ??
                                  appState.getTaskTagColor(tag) ??
                                  0xFF2196F3,
                            );
                            return DropdownMenuItem<String>(
                              value: tag,
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: tCol,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tag,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedTag = val;
                            });
                          },
                        ),
                    ],

                    const SizedBox(height: 14),
                    // Otomatik Bildirim Ayarı
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 16,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Otomatik Bildirim:',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (selectedNotificationMinutes != null)
                          Text(
                            WeeklyKeywordRule(
                              id: '',
                              keyword: '',
                              colorValue: 0,
                              notificationMinutesBefore: selectedNotificationMinutes,
                            ).notificationLabel ?? '',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('Kapalı', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == null,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = null);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Tam vaktinde', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == 0,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = 0);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('15 dk önce', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == 15,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = 15);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('30 dk önce', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == 30,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = 30);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('1 saat önce', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == 60,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = 60);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('2 saat önce', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == 120,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = 120);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('1 gün önce', style: TextStyle(fontSize: 11)),
                          selected: selectedNotificationMinutes == 1440,
                          onSelected: (val) {
                            if (val) {
                              setDialogState(() => selectedNotificationMinutes = 1440);
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    // Canlı Önizleme
                    const Text(
                      'Hücre Görünüm Önizlemesi:',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 38,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: previewColor.withValues(
                          alpha: isDark ? 0.45 : 0.35,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: previewColor, width: 1.5),
                      ),
                      child: Text(
                        keywordCtrl.text.trim().isEmpty
                            ? 'Örnek Etkinlik (30dk)'
                            : '${keywordCtrl.text.trim()} (30dk)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (existingRule != null)
                TextButton(
                  onPressed: () {
                    appState.deleteWeeklyKeywordRule(existingRule.id);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Sil', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final kw = keywordCtrl.text.trim();
                  if (kw.isEmpty) return;

                  final rule = WeeklyKeywordRule(
                    id: existingRule?.id ?? IdGenerator.generate('kw_$kw'),
                    keyword: kw,
                    colorValue: previewColorValue,
                    linkedProjectId: linkMode == 1 ? selectedProjectId : null,
                    linkedTag: linkMode == 2 ? selectedTag : null,
                    notificationMinutesBefore: selectedNotificationMinutes,
                  );

                  if (existingRule == null) {
                    appState.addWeeklyKeywordRule(rule);
                  } else {
                    appState.updateWeeklyKeywordRule(rule);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      );
    },
  );
}

class WeeklyMatrixScreen extends StatefulWidget {
  const WeeklyMatrixScreen({super.key});

  @override
  State<WeeklyMatrixScreen> createState() => _WeeklyMatrixScreenState();
}

class _WeeklyMatrixScreenState extends State<WeeklyMatrixScreen> {
  static const List<String> _dayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static const List<String> _shortDayNames = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  // Seçili Hücre Aralığı (Anchor -> Focus)
  int _anchorDay = 0;
  int _anchorHour = 8;
  int _focusDay = 0;
  int _focusHour = 8;

  // Düzenleme (Inline Edit) Durumu
  bool _isEditingCell = false;
  int? _editingDay;
  int? _editingHour;
  final TextEditingController _cellEditController = TextEditingController();
  final FocusNode _cellEditFocusNode = FocusNode();

  // Üst Formül Çubuğu (fx)
  final TextEditingController _formulaBarController = TextEditingController();
  final FocusNode _formulaBarFocusNode = FocusNode();

  // Klavye kısayolları için ana FocusNode
  final FocusNode _gridFocusNode = FocusNode();

  // Fare ile Sürükleyerek Seçim & Fill Handle (Tut-Çek) Durumu
  bool _isDraggingSelection = false;
  bool _isDraggingFillHandle = false;
  int? _fillTargetDay;
  int? _fillTargetHour;

  // Kopyala - Yapıştır Panosu (2D Matris)
  List<List<String>>? _copiedMatrix;

  // Geri Al / İleri Al (Undo / Redo) Yığınları
  final List<Map<String, String>> _undoStack = [];
  final List<Map<String, String>> _redoStack = [];

  // Grid Boyut Sabitleri (GlobalKey üzerinden koordinat hesabı için)
  final GlobalKey _gridBodyKey = GlobalKey();
  static const double _timeColWidth = 62.0;
  static const double _rowHeight = 44.0;

  int get _minSelDay => _anchorDay < _focusDay ? _anchorDay : _focusDay;
  int get _maxSelDay => _anchorDay > _focusDay ? _anchorDay : _focusDay;
  int get _minSelHour => _anchorHour < _focusHour ? _anchorHour : _focusHour;
  int get _maxSelHour => _anchorHour > _focusHour ? _anchorHour : _focusHour;

  @override
  void initState() {
    super.initState();
    _cellEditFocusNode.addListener(_onCellEditFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncFormulaBarWithSelection();
        _gridFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _cellEditFocusNode.removeListener(_onCellEditFocusChange);
    _cellEditController.dispose();
    _cellEditFocusNode.dispose();
    _formulaBarController.dispose();
    _formulaBarFocusNode.dispose();
    _gridFocusNode.dispose();
    super.dispose();
  }

  void _onCellEditFocusChange() {
    if (!_cellEditFocusNode.hasFocus && _isEditingCell) {
      _commitCellEdit();
    }
  }

  void _pushUndoSnapshot(AppState appState) {
    _undoStack.add(Map<String, String>.from(appState.idealWeekMatrix));
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _performUndo(AppState appState) {
    if (_isEditingCell) _commitCellEdit();
    if (_undoStack.isEmpty) return;
    _redoStack.add(Map<String, String>.from(appState.idealWeekMatrix));
    final prev = _undoStack.removeLast();
    appState.replaceIdealWeekMatrix(prev);
    _syncFormulaBarWithSelection();
  }

  void _performRedo(AppState appState) {
    if (_isEditingCell) _commitCellEdit();
    if (_redoStack.isEmpty) return;
    _undoStack.add(Map<String, String>.from(appState.idealWeekMatrix));
    final next = _redoStack.removeLast();
    appState.replaceIdealWeekMatrix(next);
    _syncFormulaBarWithSelection();
  }

  void _syncFormulaBarWithSelection() {
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final val = appState.getIdealWeekCell(_anchorDay, _anchorHour);
    if (_formulaBarController.text != val) {
      _formulaBarController.text = val;
    }
  }

  void _selectCell(int day, int hour, {bool extendSelection = false}) {
    if (_isEditingCell && (_editingDay != day || _editingHour != hour)) {
      _commitCellEdit();
    }
    setState(() {
      if (extendSelection) {
        _focusDay = day.clamp(0, 6);
        _focusHour = hour.clamp(0, 23);
      } else {
        _anchorDay = day.clamp(0, 6);
        _anchorHour = hour.clamp(0, 23);
        _focusDay = _anchorDay;
        _focusHour = _anchorHour;
      }
    });
    _syncFormulaBarWithSelection();
    if (!_isEditingCell && !_formulaBarFocusNode.hasFocus) {
      _gridFocusNode.requestFocus();
    }
  }

  void _startEditingCell(int day, int hour, {String? initialOverride}) {
    final appState = Provider.of<AppState>(context, listen: false);
    if (_isEditingCell && (_editingDay != day || _editingHour != hour)) {
      _commitCellEdit();
    }
    final existing = appState.getIdealWeekCell(day, hour);
    final textToSet = initialOverride ?? existing;

    setState(() {
      _anchorDay = day;
      _anchorHour = hour;
      _focusDay = day;
      _focusHour = hour;
      _isEditingCell = true;
      _editingDay = day;
      _editingHour = hour;
      _cellEditController.text = textToSet;
      _cellEditController.selection = TextSelection.collapsed(
        offset: textToSet.length,
      );
      _formulaBarController.text = textToSet;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isEditingCell) {
        _cellEditFocusNode.requestFocus();
      }
    });
  }

  void _commitCellEdit() {
    if (!_isEditingCell || _editingDay == null || _editingHour == null) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final day = _editingDay!;
    final hour = _editingHour!;
    final newVal = _cellEditController.text.trim();
    final oldVal = appState.getIdealWeekCell(day, hour);

    setState(() {
      _isEditingCell = false;
      _editingDay = null;
      _editingHour = null;
    });

    if (newVal != oldVal) {
      _pushUndoSnapshot(appState);
      appState.setIdealWeekCell(day, hour, newVal);
    }
    _syncFormulaBarWithSelection();
  }

  void _cancelCellEdit() {
    if (!_isEditingCell) return;
    setState(() {
      _isEditingCell = false;
      _editingDay = null;
      _editingHour = null;
    });
    _syncFormulaBarWithSelection();
    _gridFocusNode.requestFocus();
  }

  void _copySelection(AppState appState) {
    if (_isEditingCell) _commitCellEdit();
    final List<List<String>> matrix = [];
    final List<String> tsvRows = [];

    for (int h = _minSelHour; h <= _maxSelHour; h++) {
      final List<String> row = [];
      for (int d = _minSelDay; d <= _maxSelDay; d++) {
        row.add(appState.getIdealWeekCell(d, h));
      }
      matrix.add(row);
      tsvRows.add(row.join('\t'));
    }

    _copiedMatrix = matrix;
    Clipboard.setData(ClipboardData(text: tsvRows.join('\n')));

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${(_maxSelHour - _minSelHour + 1) * (_maxSelDay - _minSelDay + 1)} hücre kopyalandı',
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pasteSelection(AppState appState) async {
    if (_isEditingCell) _commitCellEdit();

    List<List<String>>? sourceMatrix = _copiedMatrix;

    // Sistem panosundan da kontrol et (Excel'den kopyalanmış olabilir)
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipData?.text != null && clipData!.text!.trim().isNotEmpty) {
        final rawClip = clipData.text!.replaceAll('\r\n', '\n');
        final lines = rawClip.split('\n');
        if (lines.isNotEmpty) {
          sourceMatrix = lines.map((line) => line.split('\t')).toList();
        }
      }
    } catch (_) {}

    if (sourceMatrix == null || sourceMatrix.isEmpty) return;

    _pushUndoSnapshot(appState);
    final Map<String, String> batchUpdates = {};

    final int srcRows = sourceMatrix.length;
    final int srcCols = sourceMatrix.first.length;
    final int selRows = _maxSelHour - _minSelHour + 1;
    final int selCols = _maxSelDay - _minSelDay + 1;

    // Eğer tek bir hücre kopyalandıysa ve çoklu alan seçildiyse tüm seçili alanı doldur
    if (srcRows == 1 && srcCols == 1 && (selRows > 1 || selCols > 1)) {
      final val = sourceMatrix[0][0];
      for (int h = _minSelHour; h <= _maxSelHour; h++) {
        for (int d = _minSelDay; d <= _maxSelDay; d++) {
          batchUpdates['${d}_$h'] = val;
        }
      }
    } else {
      for (int r = 0; r < srcRows; r++) {
        final targetHour = _minSelHour + r;
        if (targetHour > 23) break;
        final rowList = sourceMatrix[r];
        for (int c = 0; c < rowList.length; c++) {
          final targetDay = _minSelDay + c;
          if (targetDay > 6) break;
          batchUpdates['${targetDay}_$targetHour'] = rowList[c];
        }
      }
    }

    if (batchUpdates.isNotEmpty) {
      appState.setIdealWeekCellsBatch(batchUpdates);
      _syncFormulaBarWithSelection();
    }
  }

  void _deleteSelection(AppState appState) {
    if (_isEditingCell) _commitCellEdit();
    _pushUndoSnapshot(appState);
    final Map<String, String> batchUpdates = {};
    for (int h = _minSelHour; h <= _maxSelHour; h++) {
      for (int d = _minSelDay; d <= _maxSelDay; d++) {
        batchUpdates['${d}_$h'] = '';
      }
    }
    appState.setIdealWeekCellsBatch(batchUpdates);
    _syncFormulaBarWithSelection();
  }

  void _applyFillHandleDrag(AppState appState) {
    if (_fillTargetDay == null || _fillTargetHour == null) return;

    final int targetMinDay = _fillTargetDay! < _minSelDay
        ? _fillTargetDay!
        : _minSelDay;
    final int targetMaxDay = _fillTargetDay! > _maxSelDay
        ? _fillTargetDay!
        : _maxSelDay;
    final int targetMinHour = _fillTargetHour! < _minSelHour
        ? _fillTargetHour!
        : _minSelHour;
    final int targetMaxHour = _fillTargetHour! > _maxSelHour
        ? _fillTargetHour!
        : _maxSelHour;

    if (targetMinDay == _minSelDay &&
        targetMaxDay == _maxSelDay &&
        targetMinHour == _minSelHour &&
        targetMaxHour == _maxSelHour) {
      return;
    }

    final int srcRows = _maxSelHour - _minSelHour + 1;
    final int srcCols = _maxSelDay - _minSelDay + 1;

    _pushUndoSnapshot(appState);
    final Map<String, String> batchUpdates = {};

    for (int h = targetMinHour; h <= targetMaxHour; h++) {
      for (int d = targetMinDay; d <= targetMaxDay; d++) {
        if (h >= _minSelHour &&
            h <= _maxSelHour &&
            d >= _minSelDay &&
            d <= _maxSelDay) {
          continue; // Kaynak hücrelerin kendisi
        }
        final int srcH = _minSelHour + ((h - _minSelHour) % srcRows);
        final int srcD = _minSelDay + ((d - _minSelDay) % srcCols);
        final val = appState.getIdealWeekCell(srcD, srcH);
        batchUpdates['${d}_$h'] = val;
      }
    }

    if (batchUpdates.isNotEmpty) {
      appState.setIdealWeekCellsBatch(batchUpdates);
      setState(() {
        _anchorDay = targetMinDay;
        _anchorHour = targetMinHour;
        _focusDay = targetMaxDay;
        _focusHour = targetMaxHour;
      });
      _syncFormulaBarWithSelection();
    }
  }

  List<int> _getVisibleHours(AppState appState) {
    if (!appState.weekly2HideEmptyHours) {
      return List<int>.generate(24, (i) => i);
    }
    final List<int> nonEmptyHours = [];
    for (int h = 0; h < 24; h++) {
      bool hasContent = false;
      for (int d = 0; d < 7; d++) {
        if (appState.getIdealWeekCell(d, h).trim().isNotEmpty) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) {
        nonEmptyHours.add(h);
      }
    }
    if (nonEmptyHours.isEmpty) {
      // Tüm tablo boşsa kullanıcı yazabilsin diye 08:00 - 22:00 arasını göster
      return List<int>.generate(15, (i) => i + 8);
    }
    return nonEmptyHours;
  }

  (int, int)? _hitTestCellFromGlobalOffset(
    Offset globalPosition,
    List<int> visibleHours,
    double totalGridWidth,
  ) {
    final renderBox =
        _gridBodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final local = renderBox.globalToLocal(globalPosition);
    final double dayColWidth = (totalGridWidth - _timeColWidth) / 7.0;
    if (dayColWidth <= 0) return null;

    final int col = ((local.dx - _timeColWidth) / dayColWidth).floor().clamp(
      0,
      6,
    );
    final int rowIdx = (local.dy / _rowHeight).floor().clamp(
      0,
      visibleHours.length - 1,
    );
    return (col, visibleHours[rowIdx]);
  }

  KeyEventResult _handleGridKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isEditingCell || _formulaBarFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection(appState);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
        _pasteSelection(appState);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (isShift) {
          _performRedo(appState);
        } else {
          _performUndo(appState);
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyY) {
        _performRedo(appState);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyA) {
        setState(() {
          _anchorDay = 0;
          _anchorHour = 0;
          _focusDay = 6;
          _focusHour = 23;
        });
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelection(appState);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.f2) {
      _startEditingCell(_anchorDay, _anchorHour);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectCell(
        isShift ? _focusDay : _anchorDay,
        ((isShift ? _focusHour : _anchorHour) + 1).clamp(0, 23),
        extendSelection: isShift,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectCell(
        isShift ? _focusDay : _anchorDay,
        ((isShift ? _focusHour : _anchorHour) - 1).clamp(0, 23),
        extendSelection: isShift,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _selectCell(
        ((isShift ? _focusDay : _anchorDay) + 1).clamp(0, 6),
        isShift ? _focusHour : _anchorHour,
        extendSelection: isShift,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _selectCell(
        ((isShift ? _focusDay : _anchorDay) - 1).clamp(0, 6),
        isShift ? _focusHour : _anchorHour,
        extendSelection: isShift,
      );
      return KeyEventResult.handled;
    }

    // Doğrudan klavyeden harf/rakam basılırsa Excel gibi hücre içine yazmaya başla
    final char = event.character;
    if (!isCtrl &&
        char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 32 &&
        event.logicalKey != LogicalKeyboardKey.escape) {
      _startEditingCell(_anchorDay, _anchorHour, initialOverride: char);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _showFormulaGuideDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Haftalık-2 Formülasyon Rehberi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Her bir saatlik hücreye doğrudan metin yazabilir veya "//" ayracı ile bir saate birden fazla etkinlik sığdırabilirsiniz:',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                _buildGuideExampleCard(
                  title: '1. Dakika Aralığı Formatı',
                  formula: '00-İş:-30 // 30-Eve Dönüş:-40 // 40-Spor:',
                  result: 'İş (30dk) • Eve Dönüş (10dk) • Spor (20dk)',
                  desc:
                      '00\'dan 30\'a kadar İş (%50), 30-40 arası Eve Dönüş (%17), 40\'tan saat sonuna kadar Spor (%33) olarak yatay boyanır.',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildGuideExampleCard(
                  title: '2. Doğrudan Süre (::) Formatı',
                  formula: 'İş::30 // Spor::15 // Kitap::15',
                  result: 'İş (30dk) • Spor (15dk) • Kitap (15dk)',
                  desc:
                      'Başlangıç saati yerine doğrudan dakika süreleri girilir. Sürelerin oranına göre hücre yatayda renklere bölünür.',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildGuideExampleCard(
                  title: '3. Eşit Dağılım Formatı',
                  formula: 'Ev // Yemek',
                  result: 'Ev (30dk) • Yemek (30dk)',
                  desc:
                      'Süre belirtilmezse hücre eşit parçalara (%50 - %50) bölünür ve her parça kendi anahtar kelime rengini alır.',
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                const Text(
                  '💡 İpuçları:\n'
                  '• Hücreye çift tıklayarak (veya seçip direkt yazarak) formül düzenleyebilirsiniz.\n'
                  '• Seçili hücrenin sağ altındaki mavi noktayı (Fill Handle) tutup aşağı/sağa çekerek çoğaltabilirsiniz.\n'
                  '• Fare ile sürükleyip çoklu alan seçebilir, Ctrl+C / Ctrl+V / Ctrl+Z / Ctrl+Y kullanabilirsiniz.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideExampleCard({
    required String title,
    required String formula,
    required String result,
    required String desc,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white10
            : Colors.blue.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.blue.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.black38 : Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Formül:  $formula',
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Görünüm: $result',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            desc,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  bool _isCellInFillPreview(int day, int hour) {
    if (!_isDraggingFillHandle ||
        _fillTargetDay == null ||
        _fillTargetHour == null) {
      return false;
    }
    final int minD = _fillTargetDay! < _minSelDay
        ? _fillTargetDay!
        : _minSelDay;
    final int maxD = _fillTargetDay! > _maxSelDay
        ? _fillTargetDay!
        : _maxSelDay;
    final int minH = _fillTargetHour! < _minSelHour
        ? _fillTargetHour!
        : _minSelHour;
    final int maxH = _fillTargetHour! > _maxSelHour
        ? _fillTargetHour!
        : _maxSelHour;
    return day >= minD && day <= maxD && hour >= minH && hour <= maxH;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;
    final visibleHours = _getVisibleHours(appState);
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Focus(
      focusNode: _gridFocusNode,
      autofocus: true,
      onKeyEvent: _handleGridKeyEvent,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        body: Column(
          children: [
            // 1. Üst Araç Çubuğu (Toolbar)
            _buildTopToolbar(context, appState, isDark, isMobile),

            // 2. Excel Tarzı fx Formül Çubuğu
            _buildFormulaBar(context, appState, isDark),

            // 3. Ana Excel Tablosu (Grid)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double gridWidth = constraints.maxWidth;
                  final double dayColWidth =
                      (gridWidth - _timeColWidth) / 7.0;

                  return SizedBox(
                    width: gridWidth,
                    child: Column(
                      children: [
                        // Sabit Gün Başlıkları Satırı
                        _buildDayHeaderRow(
                          appState,
                          isDark,
                          isMobile,
                          dayColWidth,
                        ),

                        // Saat Satırları (Dikey Kaydırılabilir)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragEnd: isMobile
                                ? (details) {
                                    final vel = details.primaryVelocity ?? 0.0;
                                    if (vel < -200) {
                                      // Sola kaydırma -> Sonraki Hafta
                                      if (_isEditingCell) _commitCellEdit();
                                      appState.navigateCalendarForward();
                                      _syncFormulaBarWithSelection();
                                    } else if (vel > 200) {
                                      // Sağa kaydırma -> Önceki Hafta
                                      if (_isEditingCell) _commitCellEdit();
                                      appState.navigateCalendarBackward();
                                      _syncFormulaBarWithSelection();
                                    }
                                  }
                                : null,
                            child: SingleChildScrollView(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onPanStart: !isMobile
                                    ? (details) {
                                        if (_isEditingCell) _commitCellEdit();
                                        final hit =
                                            _hitTestCellFromGlobalOffset(
                                              details.globalPosition,
                                              visibleHours,
                                              gridWidth,
                                            );
                                        if (hit != null) {
                                          setState(() {
                                            _isDraggingSelection = true;
                                            _anchorDay = hit.$1;
                                            _anchorHour = hit.$2;
                                            _focusDay = hit.$1;
                                            _focusHour = hit.$2;
                                          });
                                          _syncFormulaBarWithSelection();
                                          _gridFocusNode.requestFocus();
                                        }
                                      }
                                    : null,
                                onPanUpdate: !isMobile
                                    ? (details) {
                                        if (!_isDraggingSelection) return;
                                        final hit =
                                            _hitTestCellFromGlobalOffset(
                                              details.globalPosition,
                                              visibleHours,
                                              gridWidth,
                                            );
                                        if (hit != null &&
                                            (hit.$1 != _focusDay ||
                                                hit.$2 != _focusHour)) {
                                          setState(() {
                                            _focusDay = hit.$1;
                                            _focusHour = hit.$2;
                                          });
                                        }
                                      }
                                    : null,
                                onPanEnd: !isMobile
                                    ? (_) {
                                        setState(() {
                                          _isDraggingSelection = false;
                                        });
                                      }
                                    : null,
                                child: Column(
                                  key: _gridBodyKey,
                                  children: visibleHours.map((hour) {
                                    return _buildHourRow(
                                      context,
                                      appState,
                                      hour,
                                      dayColWidth,
                                      gridWidth,
                                      visibleHours,
                                      isDark,
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar(
    BuildContext context,
    AppState appState,
    bool isDark,
    bool isMobile,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.blueGrey.shade50,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.grid_on_rounded, size: 18, color: Colors.blue),
            const SizedBox(width: 6),
            Text(
              'Haftalık-2 Planlayıcı',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.blueGrey.shade900,
              ),
            ),
            const SizedBox(width: 10),

            // Desktop Özel Hafta Geçiş Butonları (< Hafta >)
            if (!isMobile) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      tooltip: 'Önceki Hafta',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        if (_isEditingCell) _commitCellEdit();
                        appState.navigateCalendarBackward();
                        _syncFormulaBarWithSelection();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Builder(
                        builder: (context) {
                          final mon = appState.currentWeekMonday;
                          final sun = mon.add(const Duration(days: 6));
                          final str =
                              '${mon.day.toString().padLeft(2, '0')}.${mon.month.toString().padLeft(2, '0')} - ${sun.day.toString().padLeft(2, '0')}.${sun.month.toString().padLeft(2, '0')}.${sun.year}';
                          return Text(
                            str,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.blue.shade200
                                  : Colors.blue.shade800,
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      tooltip: 'Sonraki Hafta',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        if (_isEditingCell) _commitCellEdit();
                        appState.navigateCalendarForward();
                        _syncFormulaBarWithSelection();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Önceki Haftadan Kopyala Butonu
            ActionChip(
              avatar: const Icon(
                Icons.copy_all_outlined,
                size: 15,
                color: Colors.teal,
              ),
              label: const Text(
                'Önceki Haftadan Kopyala',
                style: TextStyle(fontSize: 11.5),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (_isEditingCell) _commitCellEdit();
                _pushUndoSnapshot(appState);
                appState.copyPreviousWeekToCurrentWeek();
                _syncFormulaBarWithSelection();
              },
            ),
            const SizedBox(width: 8),

            // Boş Saatleri Gizle Toggle
            FilterChip(
              label: const Text(
                'Boş Saatleri Gizle',
                style: TextStyle(fontSize: 11.5),
              ),
              selected: appState.weekly2HideEmptyHours,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => appState.toggleWeekly2HideEmptyHours(),
            ),
            const SizedBox(width: 8),

            // Anahtar Kelime Kuralı Ekle Kısayolu
            ActionChip(
              avatar: const Icon(
                Icons.palette_outlined,
                size: 15,
                color: Colors.purple,
              ),
              label: Text(
                'Kelime Renkleri (${appState.weeklyKeywordRules.length})',
                style: const TextStyle(fontSize: 11.5),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => showWeeklyKeywordRuleDialog(context, appState),
            ),
            const SizedBox(width: 8),

            // Undo / Redo
            IconButton(
              icon: const Icon(Icons.undo, size: 18),
              tooltip: 'Geri Al (Ctrl+Z)',
              visualDensity: VisualDensity.compact,
              onPressed: _undoStack.isNotEmpty
                  ? () => _performUndo(appState)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo, size: 18),
              tooltip: 'İleri Al (Ctrl+Y)',
              visualDensity: VisualDensity.compact,
              onPressed: _redoStack.isNotEmpty
                  ? () => _performRedo(appState)
                  : null,
            ),
            const SizedBox(width: 4),

            // Kopyala / Yapıştır / Sil
            IconButton(
              icon: const Icon(Icons.copy, size: 17),
              tooltip: 'Seçimi Kopyala (Ctrl+C)',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copySelection(appState),
            ),
            IconButton(
              icon: const Icon(Icons.paste, size: 17),
              tooltip: 'Yapıştır (Ctrl+V)',
              visualDensity: VisualDensity.compact,
              onPressed: () => _pasteSelection(appState),
            ),
            IconButton(
              icon: const Icon(
                Icons.backspace_outlined,
                size: 17,
                color: Colors.redAccent,
              ),
              tooltip: 'Seçili Hücreleri Temizle (Delete)',
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteSelection(appState),
            ),
            const SizedBox(width: 4),

            // Formül Rehberi
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () => _showFormulaGuideDialog(context, isDark),
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text(
                'Formül Rehberi',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaBar(
    BuildContext context,
    AppState appState,
    bool isDark,
  ) {
    final coordLabel =
        '${_shortDayNames[_anchorDay]} ${_anchorHour.toString().padLeft(2, '0')}:00';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181818) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Text(
              coordLabel,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'fx',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: _formulaBarController,
                focusNode: _formulaBarFocusNode,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText:
                      'Doğrudan yazın veya formül girin (örn: 00-İş:-30 // 30-Yemek:-60 veya İş::30 // Spor::30)',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                  ),
                ),
                onSubmitted: (val) {
                  _pushUndoSnapshot(appState);
                  appState.setIdealWeekCell(_anchorDay, _anchorHour, val);
                  _selectCell(_anchorDay, (_anchorHour + 1).clamp(0, 23));
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Hızlı sembol ekleme butonları (özellikle mobil/hızlı yazım için)
          InkWell(
            onTap: () {
              final ctrl = _isEditingCell
                  ? _cellEditController
                  : _formulaBarController;
              final newText = '${ctrl.text} // ';
              ctrl.text = newText;
              ctrl.selection = TextSelection.collapsed(offset: newText.length);
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '//',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              final ctrl = _isEditingCell
                  ? _cellEditController
                  : _formulaBarController;
              final newText = '${ctrl.text}::';
              ctrl.text = newText;
              ctrl.selection = TextSelection.collapsed(offset: newText.length);
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '::',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaderRow(
    AppState appState,
    bool isDark,
    bool isMobile,
    double dayColWidth,
  ) {
    final monday = appState.currentWeekMonday;
    final now = DateTime.now();

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222222) : Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white24 : Colors.grey.shade400,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _timeColWidth,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ),
            ),
            child: Text(
              'Saat',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.blueGrey.shade800,
              ),
            ),
          ),
          ...List.generate(7, (dayIndex) {
            final colDate = monday.add(Duration(days: dayIndex));
            final isToday =
                colDate.year == now.year &&
                colDate.month == now.month &&
                colDate.day == now.day;
            final isColSelected =
                dayIndex >= _minSelDay && dayIndex <= _maxSelDay;
            final dateBadge =
                '${colDate.day.toString().padLeft(2, '0')}.${colDate.month.toString().padLeft(2, '0')}';

            return Container(
              width: dayColWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday
                    ? Colors.blue.withValues(alpha: isDark ? 0.25 : 0.15)
                    : (isColSelected
                          ? Colors.blue.withValues(alpha: isDark ? 0.14 : 0.08)
                          : null),
                border: Border(
                  right: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isMobile ? _shortDayNames[dayIndex] : _dayNames[dayIndex],
                    style: TextStyle(
                      fontSize: isMobile ? 11 : 11.5,
                      fontWeight: (isColSelected || isToday)
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: (isColSelected || isToday)
                          ? Colors.blue
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    dateBadge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday
                          ? Colors.blue
                          : (isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHourRow(
    BuildContext context,
    AppState appState,
    int hour,
    double dayColWidth,
    double totalGridWidth,
    List<int> visibleHours,
    bool isDark,
  ) {
    final isRowSelected = hour >= _minSelHour && hour <= _maxSelHour;
    final hourStr = '${hour.toString().padLeft(2, '0')}:00';

    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          // Sol Saat Başlığı Hücresi
          Container(
            width: _timeColWidth,
            height: _rowHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isRowSelected
                  ? Colors.blue.withValues(alpha: isDark ? 0.18 : 0.1)
                  : (isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade50),
              border: Border(
                right: BorderSide(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
            ),
            child: Text(
              hourStr,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isRowSelected ? FontWeight.bold : FontWeight.w500,
                color: isRowSelected
                    ? Colors.blue
                    : (isDark ? Colors.white70 : Colors.blueGrey.shade700),
              ),
            ),
          ),

          // 7 Günlük Hücreler
          ...List.generate(7, (dayIndex) {
            return _buildGridCell(
              context,
              appState,
              dayIndex,
              hour,
              dayColWidth,
              totalGridWidth,
              visibleHours,
              isDark,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGridCell(
    BuildContext context,
    AppState appState,
    int dayIndex,
    int hour,
    double cellWidth,
    double totalGridWidth,
    List<int> visibleHours,
    bool isDark,
  ) {
    final rawValue = appState.getIdealWeekCell(dayIndex, hour);
    final isSelected =
        dayIndex >= _minSelDay &&
        dayIndex <= _maxSelDay &&
        hour >= _minSelHour &&
        hour <= _maxSelHour;
    final isAnchor = dayIndex == _anchorDay && hour == _anchorHour;
    final isBottomRightSelectionCorner =
        dayIndex == _maxSelDay && hour == _maxSelHour;
    final isEditingThis =
        _isEditingCell && _editingDay == dayIndex && _editingHour == hour;
    final isInFillPreview = _isCellInFillPreview(dayIndex, hour);

    final segments = WeeklyFormulaParser.parse(rawValue);
    final cleanSummary = WeeklyFormulaParser.formatCleanSummary(rawValue);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        _selectCell(dayIndex, hour, extendSelection: isShift);
      },
      onDoubleTap: () {
        _startEditingCell(dayIndex, hour);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: cellWidth,
            height: _rowHeight,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141414) : Colors.white,
              border: Border(
                right: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                  width: 0.8,
                ),
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                  width: 0.8,
                ),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. KATMAN: Yatay Oranlı Renk Dilimleri (Horizontal Proportional Color Bars)
                if (!isEditingThis && segments.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(segments.length, (idx) {
                      final seg = segments[idx];
                      final flexVal = (seg.ratio * 1000).round().clamp(1, 1000);
                      if (seg.isGap) {
                        return Expanded(
                          flex: flexVal,
                          child: const SizedBox.expand(),
                        );
                      }
                      final segColor = appState.resolveWeeklySegmentColor(
                        seg.title,
                        idx,
                      );
                      return Expanded(
                        flex: flexVal,
                        child: Container(
                          decoration: BoxDecoration(
                            color: segColor.withValues(
                              alpha: isDark ? 0.50 : 0.38,
                            ),
                            border: idx < segments.length - 1
                                ? Border(
                                    right: BorderSide(
                                      color: isDark
                                          ? Colors.black54
                                          : Colors.white70,
                                      width: 1.2,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),

                // 2. KATMAN: Seçili Alan Hafif Vurgusu
                if (isSelected && !isEditingThis)
                  Container(
                    color: Colors.blue.withValues(
                      alpha: isAnchor ? 0.08 : 0.14,
                    ),
                  ),

                // 3. KATMAN: Temizlenmiş Etiket Görünümü veya Inline Formül Kutusu
                if (isEditingThis)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.escape) {
                              _cancelCellEdit();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.tab) {
                              final nextDay = (dayIndex + 1).clamp(0, 6);
                              _commitCellEdit();
                              _selectCell(nextDay, hour);
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _cellEditController,
                          focusNode: _cellEditFocusNode,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            _formulaBarController.text = val;
                          },
                          onSubmitted: (_) {
                            final nextHour = (hour + 1).clamp(0, 23);
                            _commitCellEdit();
                            _selectCell(dayIndex, nextHour);
                          },
                        ),
                      ),
                    ),
                  )
                else if (cleanSummary.isNotEmpty)
                  Tooltip(
                    message: 'Formül: $rawValue\nGörünüm: $cleanSummary',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      child: Center(
                        child: Text(
                          cleanSummary,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 4. KATMAN: Seçim Çerçevesi veya Fill Preview Çerçevesi
                if (isSelected || isInFillPreview)
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isInFillPreview && !isSelected
                              ? Colors.green
                              : Colors.blue.shade600,
                          width: isAnchor ? 2.0 : 1.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 5. KATMAN: Excel Fill Handle (Sağ Alt Köşe Tutup Çekme Noktası)
          if (isBottomRightSelectionCorner && !isEditingThis)
            Positioned(
              right: -5,
              bottom: -5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  setState(() {
                    _isDraggingFillHandle = true;
                    _fillTargetDay = _maxSelDay;
                    _fillTargetHour = _maxSelHour;
                  });
                },
                onPanUpdate: (details) {
                  final hit = _hitTestCellFromGlobalOffset(
                    details.globalPosition,
                    visibleHours,
                    totalGridWidth,
                  );
                  if (hit != null &&
                      (hit.$1 != _fillTargetDay || hit.$2 != _fillTargetHour)) {
                    setState(() {
                      _fillTargetDay = hit.$1;
                      _fillTargetHour = hit.$2;
                    });
                  }
                },
                onPanEnd: (_) {
                  _applyFillHandleDrag(appState);
                  setState(() {
                    _isDraggingFillHandle = false;
                    _fillTargetDay = null;
                    _fillTargetHour = null;
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    color: Colors.transparent,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
