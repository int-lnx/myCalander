import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/event.dart';
import '../providers/app_state.dart';
import '../utils/id_generator.dart';

class RecordManagerDialog extends StatefulWidget {
  final int initialTabIndex;
  final String? initialKeyword;

  const RecordManagerDialog({
    super.key,
    this.initialTabIndex = 0,
    this.initialKeyword,
  });

  static Future<void> show(
    BuildContext context, {
    int initialTabIndex = 0,
    String? initialKeyword,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => RecordManagerDialog(
        initialTabIndex: initialTabIndex,
        initialKeyword: initialKeyword,
      ),
    );
  }

  @override
  State<RecordManagerDialog> createState() => _RecordManagerDialogState();
}

enum RecordScopeType {
  all,
  fromNow,
  dateRange,
}

enum RepeatFrequencyType {
  daily,
  weekdays,
  weekends,
  weekly,
  customDays,
}

class _RecordManagerDialogState extends State<RecordManagerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Düzelt Tab Değişkenleri ──
  final TextEditingController _editOldTitleCtrl = TextEditingController();
  final TextEditingController _editNewTitleCtrl = TextEditingController();
  RecordScopeType _editScope = RecordScopeType.all;
  DateTime _editFromDate = DateTime.now();
  DateTime _editToDate = DateTime.now().add(const Duration(days: 30));

  // ── Tekrarla Tab Değişkenleri ──
  final TextEditingController _repeatTitleCtrl = TextEditingController();
  TimeOfDay _repeatStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _repeatEndTime = const TimeOfDay(hour: 10, minute: 0);
  RepeatFrequencyType _repeatFrequency = RepeatFrequencyType.daily;
  Set<int> _customDays = {1, 2, 3, 4, 5}; // 1 = Pazartesi ... 7 = Pazar
  DateTime _repeatStartDate = DateTime.now();
  DateTime _repeatEndDate = DateTime.now().add(const Duration(days: 30));

  // ── Sil Tab Değişkenleri ──
  final TextEditingController _deleteTitleCtrl = TextEditingController();
  RecordScopeType _deleteScope = RecordScopeType.all;
  DateTime _deleteFromDate = DateTime.now();
  DateTime _deleteToDate = DateTime.now().add(const Duration(days: 30));
  bool _deleteDynamicRuleAlso = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );

    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _editOldTitleCtrl.text = widget.initialKeyword!;
      _repeatTitleCtrl.text = widget.initialKeyword!;
      _deleteTitleCtrl.text = widget.initialKeyword!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _editOldTitleCtrl.dispose();
    _editNewTitleCtrl.dispose();
    _repeatTitleCtrl.dispose();
    _deleteTitleCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  // ── Dynamic Rule Uyarı Modalı (3 Seçenekli) ──
  Future<int?> _showDynamicRulePrompt(
    BuildContext context, {
    required String oldTitle,
    required String newTitle,
  }) async {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Dinamik Kural Etkileşimi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Takvimdeki '),
                    TextSpan(
                      text: '"$oldTitle"',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const TextSpan(text: ' kayıtlarını '),
                    TextSpan(
                      text: '"$newTitle"',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const TextSpan(
                      text:
                          ' olarak güncelliyorsunuz.\n\nAncak bu kelime sol çekmecedeki Dinamik Özellikler listesinde tanımlı (renk, proje ve bildirim bağları mevcut).\n\nNasıl devam etmek istersiniz?',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Seçenek 1: Ayrı Dinamik Kayıt Olarak Oluştur
              _buildChoiceCard(
                ctx,
                title: 'Ayrı Dinamik Kayıt Olarak Oluştur',
                subtitle:
                    'Mevcut "$oldTitle" kuralının özelliklerini kopyalayarak sol çekmeceye "$newTitle" için yeni bir kural ekler. (Önerilen)',
                icon: Icons.copy_all,
                color: Colors.blue,
                isDark: isDark,
                onTap: () => Navigator.pop(ctx, 1),
              ),
              const SizedBox(height: 8),

              // Seçenek 2: Mevcut Dinamik Kuralı Güncelle
              _buildChoiceCard(
                ctx,
                title: 'Mevcut Dinamik Kuralı Güncelle',
                subtitle:
                    'Sol çekmecedeki "$oldTitle" kuralının doğrudan adını "$newTitle" olarak değiştirir.',
                icon: Icons.edit_attributes,
                color: Colors.teal,
                isDark: isDark,
                onTap: () => Navigator.pop(ctx, 2),
              ),
              const SizedBox(height: 8),

              // Seçenek 3: Dinamik Kayıt Oluşturmadan Devam Et
              _buildChoiceCard(
                ctx,
                title: 'Dinamik Kayıt Oluşturmadan Devam Et',
                subtitle:
                    'Sadece takvimdeki etkinliklerin başlığını değiştirir; sol çekmeceye dokunmaz.',
                icon: Icons.arrow_forward,
                color: Colors.grey,
                isDark: isDark,
                onTap: () => Navigator.pop(ctx, 3),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('İşlemi İptal Et'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChoiceCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune, color: Colors.blue, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kayıt Yöneticisi',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Takvim kayıtlarını toplu yönetin ve dinamik özelliklerle eşleştirin',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              indicatorColor: Colors.blue,
              labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  icon: Icon(Icons.edit_note, size: 18),
                  text: 'Toplu Düzelt',
                ),
                Tab(
                  icon: Icon(Icons.repeat, size: 18),
                  text: 'Tekrarla',
                ),
                Tab(
                  icon: Icon(Icons.delete_sweep, size: 18),
                  text: 'Toplu Sil',
                ),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEditTab(appState, isDark),
                  _buildRepeatTab(appState, isDark),
                  _buildDeleteTab(appState, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1: TOPLU DÜZELT
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildEditTab(AppState appState, bool isDark) {
    final uniqueTitles = appState.getUniqueEventTitles();
    final oldTitle = _editOldTitleCtrl.text.trim();

    DateTime? effectiveFrom;
    DateTime? effectiveTo;
    if (_editScope == RecordScopeType.fromNow) {
      effectiveFrom = _editFromDate;
    } else if (_editScope == RecordScopeType.dateRange) {
      effectiveFrom = _editFromDate;
      effectiveTo = _editToDate;
    }

    final matchingEvents = oldTitle.isEmpty
        ? <Event>[]
        : appState.findMatchingEvents(
            title: oldTitle,
            fromDate: effectiveFrom,
            toDate: effectiveTo,
          );

    final dynRule = oldTitle.isEmpty ? null : appState.findWeeklyKeywordRule(oldTitle);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eski Başlık
          const Text(
            'Değiştirilecek Kayıt Başlığı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return uniqueTitles;
              }
              return uniqueTitles.where((t) =>
                  t.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            initialValue: TextEditingValue(text: _editOldTitleCtrl.text),
            onSelected: (String selection) {
              setState(() {
                _editOldTitleCtrl.text = selection;
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (controller.text != _editOldTitleCtrl.text) {
                controller.text = _editOldTitleCtrl.text;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Örn: Sleep',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            controller.clear();
                            setState(() => _editOldTitleCtrl.clear());
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) {
                  setState(() => _editOldTitleCtrl.text = val);
                },
              );
            },
          ),

          if (oldTitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: matchingEvents.isNotEmpty
                        ? Colors.blue.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    matchingEvents.isNotEmpty
                        ? 'Takvimde ${matchingEvents.length} kayıt eşleşti'
                        : 'Bu başlıkla kayıt bulunamadı',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: matchingEvents.isNotEmpty ? Colors.blue : Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (dynRule != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Color(dynRule.colorValue).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Color(dynRule.colorValue), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 13, color: Color(dynRule.colorValue)),
                        const SizedBox(width: 3),
                        Text(
                          'Dinamik Kural Var',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(dynRule.colorValue),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 14),

          // Yeni Başlık
          const Text(
            'Yeni Başlık:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _editNewTitleCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Örn: Sleepp',
              prefixIcon: const Icon(Icons.edit_outlined, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 14),

          // Kapsam Seçimi
          const Text(
            'Değişiklik Kapsamı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildScopeSelector(
            currentScope: _editScope,
            fromDate: _editFromDate,
            toDate: _editToDate,
            onScopeChanged: (s) => setState(() => _editScope = s),
            onFromDateChanged: (d) => setState(() => _editFromDate = d),
            onToDateChanged: (d) => setState(() => _editToDate = d),
          ),

          const SizedBox(height: 20),

          // Uygula Butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: matchingEvents.isEmpty || _editNewTitleCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      final targetOld = _editOldTitleCtrl.text.trim();
                      final targetNew = _editNewTitleCtrl.text.trim();

                      if (targetOld.toLowerCase() == targetNew.toLowerCase()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Eski ve yeni başlık aynı olamaz.')),
                        );
                        return;
                      }

                      // Dinamik kural var mı kontrol et
                      final existingRule = appState.findWeeklyKeywordRule(targetOld);
                      if (existingRule != null) {
                        final choice = await _showDynamicRulePrompt(
                          context,
                          oldTitle: targetOld,
                          newTitle: targetNew,
                        );

                        if (choice == null) return; // İptal edildi

                        if (choice == 1) {
                          // Ayrı Dinamik Kayıt Olarak Oluştur
                          appState.duplicateWeeklyKeywordRule(targetOld, targetNew);
                        } else if (choice == 2) {
                          // Mevcut Dinamik Kuralı Güncelle
                          appState.renameWeeklyKeywordRule(targetOld, targetNew);
                        }
                        // choice == 3: Dinamik kayıt oluşturmadan devam et
                      }

                      // Etkinlikleri güncelle
                      final updated = appState.batchUpdateEvents(
                        oldTitle: targetOld,
                        newTitle: targetNew,
                        fromDate: effectiveFrom,
                        toDate: effectiveTo,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${updated.length} adet kayıt "$targetNew" olarak güncellendi.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.check, size: 18),
              label: Text(
                '${matchingEvents.length} Kaydı Güncelle',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2: TEKRARLA (TOPLU ÇOĞALTMA / OLUŞTURMA)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildRepeatTab(AppState appState, bool isDark) {
    final uniqueTitles = appState.getUniqueEventTitles();
    final title = _repeatTitleCtrl.text.trim();
    final dynRule = title.isEmpty ? null : appState.findWeeklyKeywordRule(title);

    // Kaç gün etkilenecek hesapla
    int targetDayCount = 0;
    var cursor = DateTime(
      _repeatStartDate.year,
      _repeatStartDate.month,
      _repeatStartDate.day,
    );
    final end = DateTime(
      _repeatEndDate.year,
      _repeatEndDate.month,
      _repeatEndDate.day,
    );
    while (!cursor.isAfter(end)) {
      final weekday = cursor.weekday; // 1 = Pazartesi .. 7 = Pazar
      bool matches = false;
      switch (_repeatFrequency) {
        case RepeatFrequencyType.daily:
          matches = true;
          break;
        case RepeatFrequencyType.weekdays:
          matches = weekday >= 1 && weekday <= 5;
          break;
        case RepeatFrequencyType.weekends:
          matches = weekday == 6 || weekday == 7;
          break;
        case RepeatFrequencyType.weekly:
          matches = weekday == _repeatStartDate.weekday;
          break;
        case RepeatFrequencyType.customDays:
          matches = _customDays.contains(weekday);
          break;
      }
      if (matches) targetDayCount++;
      cursor = cursor.add(const Duration(days: 1));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          const Text(
            'Tekrarlanacak Kayıt Başlığı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return uniqueTitles;
              }
              return uniqueTitles.where((t) =>
                  t.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            initialValue: TextEditingValue(text: _repeatTitleCtrl.text),
            onSelected: (String selection) {
              setState(() => _repeatTitleCtrl.text = selection);
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (controller.text != _repeatTitleCtrl.text) {
                controller.text = _repeatTitleCtrl.text;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Örn: Sleep',
                  prefixIcon: const Icon(Icons.title, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) {
                  setState(() => _repeatTitleCtrl.text = val);
                },
              );
            },
          ),

          if (dynRule != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Color(dynRule.colorValue).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Color(dynRule.colorValue), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Color(dynRule.colorValue)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dinamik Kural Bağlı: Renk, ${dynRule.linkedTag ?? "Kategori"} ve ${dynRule.notificationLabel ?? "Bildirim"} otomatik uygulanacak.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(dynRule.colorValue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Saat Aralığı
          const Text(
            'Saat Aralığı (Her Gün İçin):',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _repeatStartTime,
                    );
                    if (picked != null) {
                      setState(() => _repeatStartTime = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Başla: ${_repeatStartTime.format(context)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _repeatEndTime,
                    );
                    if (picked != null) {
                      setState(() => _repeatEndTime = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_filled, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Bitir: ${_repeatEndTime.format(context)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Tekrar Sıklığı
          const Text(
            'Tekrar Sıklığı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Her Gün', style: TextStyle(fontSize: 11.5)),
                selected: _repeatFrequency == RepeatFrequencyType.daily,
                onSelected: (val) {
                  if (val) setState(() => _repeatFrequency = RepeatFrequencyType.daily);
                },
              ),
              ChoiceChip(
                label: const Text('Hafta İçi (Pzt-Cum)', style: TextStyle(fontSize: 11.5)),
                selected: _repeatFrequency == RepeatFrequencyType.weekdays,
                onSelected: (val) {
                  if (val) setState(() => _repeatFrequency = RepeatFrequencyType.weekdays);
                },
              ),
              ChoiceChip(
                label: const Text('Hafta Sonu', style: TextStyle(fontSize: 11.5)),
                selected: _repeatFrequency == RepeatFrequencyType.weekends,
                onSelected: (val) {
                  if (val) setState(() => _repeatFrequency = RepeatFrequencyType.weekends);
                },
              ),
              ChoiceChip(
                label: const Text('Haftada Bir', style: TextStyle(fontSize: 11.5)),
                selected: _repeatFrequency == RepeatFrequencyType.weekly,
                onSelected: (val) {
                  if (val) setState(() => _repeatFrequency = RepeatFrequencyType.weekly);
                },
              ),
              ChoiceChip(
                label: const Text('Özel Günler', style: TextStyle(fontSize: 11.5)),
                selected: _repeatFrequency == RepeatFrequencyType.customDays,
                onSelected: (val) {
                  if (val) setState(() => _repeatFrequency = RepeatFrequencyType.customDays);
                },
              ),
            ],
          ),

          if (_repeatFrequency == RepeatFrequencyType.customDays) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                _buildDayFilterChip(1, 'Pzt'),
                _buildDayFilterChip(2, 'Sal'),
                _buildDayFilterChip(3, 'Çar'),
                _buildDayFilterChip(4, 'Per'),
                _buildDayFilterChip(5, 'Cum'),
                _buildDayFilterChip(6, 'Cmt'),
                _buildDayFilterChip(7, 'Paz'),
              ],
            ),
          ],

          const SizedBox(height: 14),

          // Tarih Aralığı
          const Text(
            'Tarih Aralığı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _repeatStartDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) {
                      setState(() {
                        _repeatStartDate = picked;
                        if (_repeatEndDate.isBefore(_repeatStartDate)) {
                          _repeatEndDate = _repeatStartDate.add(const Duration(days: 30));
                        }
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Başla: ${_formatDate(_repeatStartDate)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _repeatEndDate,
                      firstDate: _repeatStartDate,
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) {
                      setState(() => _repeatEndDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Bitir: ${_formatDate(_repeatEndDate)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Çoğalt Butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: title.isEmpty || targetDayCount == 0
                  ? null
                  : () {
                      final newEvents = <Event>[];
                      var cur = DateTime(
                        _repeatStartDate.year,
                        _repeatStartDate.month,
                        _repeatStartDate.day,
                      );
                      final last = DateTime(
                        _repeatEndDate.year,
                        _repeatEndDate.month,
                        _repeatEndDate.day,
                      );

                      final colorVal = dynRule != null
                          ? appState.resolveKeywordRuleColor(dynRule)
                          : 0xFF2196F3;
                      final tag = dynRule?.linkedTag ?? 'Genel';
                      final projId = dynRule?.linkedProjectId;
                      final notifOffset = dynRule?.notificationMinutesBefore != null
                          ? [dynRule!.notificationMinutesBefore!]
                          : <int>[];

                      while (!cur.isAfter(last)) {
                        final weekday = cur.weekday;
                        bool match = false;
                        switch (_repeatFrequency) {
                          case RepeatFrequencyType.daily:
                            match = true;
                            break;
                          case RepeatFrequencyType.weekdays:
                            match = weekday >= 1 && weekday <= 5;
                            break;
                          case RepeatFrequencyType.weekends:
                            match = weekday == 6 || weekday == 7;
                            break;
                          case RepeatFrequencyType.weekly:
                            match = weekday == _repeatStartDate.weekday;
                            break;
                          case RepeatFrequencyType.customDays:
                            match = _customDays.contains(weekday);
                            break;
                        }

                        if (match) {
                          final eventStart = DateTime(
                            cur.year,
                            cur.month,
                            cur.day,
                            _repeatStartTime.hour,
                            _repeatStartTime.minute,
                          );

                          var eventEnd = DateTime(
                            cur.year,
                            cur.month,
                            cur.day,
                            _repeatEndTime.hour,
                            _repeatEndTime.minute,
                          );

                          // Geceyi aşan saatler için (örn: 23:00 - 07:00)
                          if (!eventEnd.isAfter(eventStart)) {
                            eventEnd = eventEnd.add(const Duration(days: 1));
                          }

                          newEvents.add(
                            Event(
                              id: IdGenerator.generate(title, date: eventStart),
                              title: title,
                              from: eventStart,
                              to: eventEnd,
                              colorValue: colorVal,
                              tag: tag,
                              projectId: projId,
                              notificationOffsets: notifOffset,
                            ),
                          );
                        }

                        cur = cur.add(const Duration(days: 1));
                      }

                      appState.batchAddEvents(newEvents);

                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${newEvents.length} adet bağımsız "$title" kaydı takvime eklendi.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
              icon: const Icon(Icons.add_task, size: 18),
              label: Text(
                'Takvime $targetDayCount Kayıt Ekle',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayFilterChip(int dayIndex, String label) {
    final isSelected = _customDays.contains(dayIndex);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      onSelected: (val) {
        setState(() {
          if (val) {
            _customDays.add(dayIndex);
          } else {
            if (_customDays.length > 1) {
              _customDays.remove(dayIndex);
            }
          }
        });
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3: TOPLU SİL
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDeleteTab(AppState appState, bool isDark) {
    final uniqueTitles = appState.getUniqueEventTitles();
    final title = _deleteTitleCtrl.text.trim();

    DateTime? effectiveFrom;
    DateTime? effectiveTo;
    if (_deleteScope == RecordScopeType.fromNow) {
      effectiveFrom = _deleteFromDate;
    } else if (_deleteScope == RecordScopeType.dateRange) {
      effectiveFrom = _deleteFromDate;
      effectiveTo = _deleteToDate;
    }

    final matchingEvents = title.isEmpty
        ? <Event>[]
        : appState.findMatchingEvents(
            title: title,
            fromDate: effectiveFrom,
            toDate: effectiveTo,
          );

    final dynRule = title.isEmpty ? null : appState.findWeeklyKeywordRule(title);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Silinecek Başlık
          const Text(
            'Silinecek Kayıt Başlığı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return uniqueTitles;
              }
              return uniqueTitles.where((t) =>
                  t.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            initialValue: TextEditingValue(text: _deleteTitleCtrl.text),
            onSelected: (String selection) {
              setState(() => _deleteTitleCtrl.text = selection);
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (controller.text != _deleteTitleCtrl.text) {
                controller.text = _deleteTitleCtrl.text;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Örn: Sleep',
                  prefixIcon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) {
                  setState(() => _deleteTitleCtrl.text = val);
                },
              );
            },
          ),

          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: matchingEvents.isNotEmpty
                    ? Colors.red.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                matchingEvents.isNotEmpty
                    ? 'Silinecek ${matchingEvents.length} kayıt eşleşti'
                    : 'Bu başlıkla kayıt bulunamadı',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: matchingEvents.isNotEmpty ? Colors.red : Colors.grey,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Silme Kapsamı
          const Text(
            'Silme Kapsamı:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildScopeSelector(
            currentScope: _deleteScope,
            fromDate: _deleteFromDate,
            toDate: _deleteToDate,
            onScopeChanged: (s) => setState(() => _deleteScope = s),
            onFromDateChanged: (d) => setState(() => _deleteFromDate = d),
            onToDateChanged: (d) => setState(() => _deleteToDate = d),
          ),

          if (dynRule != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: CheckboxListTile(
                value: _deleteDynamicRuleAlso,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.red,
                title: Text(
                  'Sol çekmecedeki "$title" Dinamik Kuralını da sil',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'İşaretlenirse bu kelime için tanımlanan renk/proje kuralı da kaldırılır.',
                  style: TextStyle(fontSize: 10.5),
                ),
                onChanged: (val) {
                  setState(() => _deleteDynamicRuleAlso = val ?? false);
                },
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Sil Butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: matchingEvents.isEmpty
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Toplu Silme Onayı'),
                          content: Text(
                            'Takvimdeki ${matchingEvents.length} adet "$title" kaydı silinecek.\nBu işlem geri alınamaz. Devam etmek istiyor musunuz?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Vazgeç'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Evet, Sil'),
                            ),
                          ],
                        ),
                      );

                      if (confirm != true) return;

                      if (_deleteDynamicRuleAlso && dynRule != null) {
                        appState.deleteWeeklyKeywordRule(dynRule.id);
                      }

                      final deleted = appState.batchDeleteEvents(
                        title: title,
                        fromDate: effectiveFrom,
                        toDate: effectiveTo,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${deleted.length} adet "$title" kaydı silindi.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.delete_forever, size: 18),
              label: Text(
                '${matchingEvents.length} Kaydı Sil',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Kapsam Seçici Ortak Widget
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildScopeSelector({
    required RecordScopeType currentScope,
    required DateTime fromDate,
    required DateTime toDate,
    required ValueChanged<RecordScopeType> onScopeChanged,
    required ValueChanged<DateTime> onFromDateChanged,
    required ValueChanged<DateTime> onToDateChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('Tüm Zamanlar', style: TextStyle(fontSize: 11.5)),
              selected: currentScope == RecordScopeType.all,
              onSelected: (val) {
                if (val) onScopeChanged(RecordScopeType.all);
              },
            ),
            ChoiceChip(
              label: const Text('Şu Tarihten İtibaren', style: TextStyle(fontSize: 11.5)),
              selected: currentScope == RecordScopeType.fromNow,
              onSelected: (val) {
                if (val) onScopeChanged(RecordScopeType.fromNow);
              },
            ),
            ChoiceChip(
              label: const Text('Tarih Aralığı', style: TextStyle(fontSize: 11.5)),
              selected: currentScope == RecordScopeType.dateRange,
              onSelected: (val) {
                if (val) onScopeChanged(RecordScopeType.dateRange);
              },
            ),
          ],
        ),
        if (currentScope == RecordScopeType.fromNow) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: fromDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2040),
              );
              if (picked != null) onFromDateChanged(picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    '${_formatDate(fromDate)} tarihinden sonrakiler',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ] else if (currentScope == RecordScopeType.dateRange) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fromDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) onFromDateChanged(picked);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Başla: ${_formatDate(fromDate)}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: toDate,
                      firstDate: fromDate,
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) onToDateChanged(picked);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Bitir: ${_formatDate(toDate)}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

