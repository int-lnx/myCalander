import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../models/topic_plan.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../dialogs/project_evaluation_dialog.dart';

class PlanScreen extends StatefulWidget {
  final String? projectId;
  final bool showAppBar;
  const PlanScreen({super.key, this.projectId, this.showAppBar = true});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final int _selectedYear = DateTime.now().year;
  late ScrollController _verticalScrollController;
  late ScrollController _cellsVerticalScrollController;
  late ScrollController _contentHorizontalController;
  bool _showPrediction = false;
  double _dailyCapacityHours = 2.0;
  late TextEditingController _capacityController;
  final List<int> _generalExcludedWeekdays = [];
  final List<ExcludedDateItem> _generalExcludedExclusions = [];
  bool _hasScrolledToToday = false;

  final List<String> _monthNames = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  final double _rowHeight = 48.0;
  final double _colWidth = 150.0;
  final double _dateColWidth = 100.0;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    double cap = prefs.getDouble('plan_dailyCapacityHours') ?? 2.0;
    List<int> wk = [];
    final wkList = prefs.getStringList('plan_generalExcludedWeekdays');
    if (wkList != null) wk.addAll(wkList.map(int.parse));
    List<ExcludedDateItem> dt = [];
    final dtList = prefs.getStringList('plan_generalExcludedDates');
    if (dtList != null) {
      dt.addAll(dtList.map((s) => ExcludedDateItem.fromJsonString(s)));
    }

    if (widget.projectId != null) {
      final appState = Provider.of<AppState>(context, listen: false);
      final remoteSettings = await appState.loadPlanSettings(widget.projectId!);
      if (remoteSettings != null) {
        if (remoteSettings['dailyCapacityHours'] != null) {
          cap = (remoteSettings['dailyCapacityHours'] as num).toDouble();
        }
        if (remoteSettings['excludedWeekdays'] != null) {
          wk = List<int>.from(remoteSettings['excludedWeekdays']);
        }
        if (remoteSettings['excludedDates'] != null) {
          dt = (remoteSettings['excludedDates'] as List<dynamic>)
              .map((s) => ExcludedDateItem.fromJsonString(s as String))
              .toList();
        }
        await prefs.setDouble('plan_dailyCapacityHours', cap);
        await prefs.setStringList('plan_generalExcludedWeekdays', wk.map((w) => w.toString()).toList());
        await prefs.setStringList('plan_generalExcludedDates', dt.map((e) => e.toJsonString()).toList());
      }
    }

    if (mounted) {
      setState(() {
        _dailyCapacityHours = cap;
        _capacityController.text = _dailyCapacityHours.toString();
        _generalExcludedWeekdays.clear();
        _generalExcludedWeekdays.addAll(wk);
        _generalExcludedExclusions.clear();
        _generalExcludedExclusions.addAll(dt);
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('plan_dailyCapacityHours', _dailyCapacityHours);
    await prefs.setStringList('plan_generalExcludedWeekdays', _generalExcludedWeekdays.map((w) => w.toString()).toList());
    await prefs.setStringList('plan_generalExcludedDates', _generalExcludedExclusions.map((e) => e.toJsonString()).toList());

    if (widget.projectId != null) {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.savePlanSettings(
        widget.projectId!,
        _dailyCapacityHours,
        _generalExcludedWeekdays,
        _generalExcludedExclusions.map((e) => e.toJsonString()).toList(),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _capacityController = TextEditingController(
      text: _dailyCapacityHours.toString(),
    );
    _loadSettings();
    _capacityController.addListener(() {
      final val = double.tryParse(_capacityController.text);
      if (val != null && val > 0 && val != _dailyCapacityHours) {
        setState(() {
          _dailyCapacityHours = val;
        });
        _saveSettings();
      }
    });
    _verticalScrollController = ScrollController();
    _cellsVerticalScrollController = ScrollController();
    _contentHorizontalController = ScrollController();

    _verticalScrollController.addListener(() {
      if (_cellsVerticalScrollController.hasClients &&
          _cellsVerticalScrollController.offset !=
              _verticalScrollController.offset) {
        _cellsVerticalScrollController.jumpTo(_verticalScrollController.offset);
      }
    });

    _cellsVerticalScrollController.addListener(() {
      if (_verticalScrollController.hasClients &&
          _verticalScrollController.offset !=
              _cellsVerticalScrollController.offset) {
        _verticalScrollController.jumpTo(_cellsVerticalScrollController.offset);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDate(DateTime.now());
    });
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _cellsVerticalScrollController.dispose();
    _contentHorizontalController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _scrollToDate(DateTime date) {
    if (_verticalScrollController.hasClients && date.year == _selectedYear) {
      final diff = date.difference(_timelineStartDate).inDays;
      final double offset = diff * _rowHeight;
      final double viewportHeight =
          _verticalScrollController.position.viewportDimension;
      final double target = max(0.0, offset - viewportHeight / 2);
      _verticalScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  DateTime get _timelineStartDate => DateTime(_selectedYear, 1, 1);
  DateTime get _timelineEndDate => DateTime(_selectedYear, 12, 31);

  int get _totalTimelineDays {
    return _timelineEndDate.difference(_timelineStartDate).inDays + 1;
  }

  String _getWeekdayShortName(int weekday) {
    const names = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return names[weekday - 1];
  }

  DateTime getPlanStartDate(TopicPlan plan) {
    DateTime? minDate;
    for (var key in plan.dayReports.keys) {
      final rep = plan.dayReports[key]!;
      if (rep.hoursWorked > 0) {
        try {
          final parsed = DateTime.parse(key);
          if (minDate == null || parsed.isBefore(minDate)) {
            minDate = parsed;
          }
        } catch (_) {}
      }
    }
    return minDate ?? plan.startDate;
  }

  DateTime getPlanEndDate(TopicPlan plan) {
    if (plan.status == 'Yapılanlar') {
      return DateTime(plan.endDate.year, plan.endDate.month, plan.endDate.day);
    }
    return DateTime(_selectedYear, 12, 31);
  }

  DateTime getHighlightEndDate(TopicPlan plan) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (plan.status == 'Yapılanlar') {
      return getPlanEndDate(plan);
    }
    final endLimit = getPlanEndDate(plan);
    return today.isBefore(endLimit) ? today : endLimit;
  }

  bool plansOverlap(TopicPlan a, TopicPlan b) {
    final startA = getPlanStartDate(a);
    final endA = getPlanEndDate(a);
    final startB = getPlanStartDate(b);
    final endB = getPlanEndDate(b);
    return !(endA.isBefore(startB) || startA.isAfter(endB));
  }

  void _handleLeftDateTap(DateTime clickedDate) {
    final appState = Provider.of<AppState>(context, listen: false);
    final allPlans = appState.topicPlans
        .where((p) => p.projectId == widget.projectId)
        .toList();
    if (allPlans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen önce Görev Havuzuna giderek bir adım/görev ekleyin.',
          ),
        ),
      );
      return;
    }
    // For date tap on the left side, we filter out completed plans for dates after their completion date
    final availablePlans = allPlans.where((plan) {
      if (plan.status == 'Yapılanlar') {
        final pEnd = getPlanEndDate(plan);
        if (clickedDate.isAfter(pEnd)) {
          return false;
        }
      }
      return true;
    }).toList();
    _showLeftDateHourEntryDialog(
      context,
      clickedDate,
      appState,
      allPlans,
      restrictedPlans: availablePlans,
    );
  }

  void _showLeftDateHourEntryDialog(
    BuildContext context,
    DateTime date,
    AppState appState,
    List<TopicPlan> allPlans, {
    String? initialPlanId,
    List<TopicPlan>? restrictedPlans,
  }) {
    final String dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    String? selectedPlanId = initialPlanId;
    final hoursController = TextEditingController();
    final noteController = TextEditingController();

    // Check if initial plan is already completed
    bool isCompletedChecked = false;
    if (selectedPlanId != null) {
      final p = allPlans.firstWhere(
        (plan) => plan.id == selectedPlanId,
        orElse: () => allPlans.first,
      );
      isCompletedChecked = p.status == 'Yapılanlar';
      final rep = p.dayReports[dateKey];
      hoursController.text = rep != null && rep.hoursWorked > 0
          ? rep.hoursWorked.toString()
          : '';
      noteController.text = rep?.note ?? '';
    }

    final dropdownPlans = restrictedPlans ?? allPlans;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasLogForDate =
                selectedPlanId != null &&
                allPlans
                    .firstWhere((plan) => plan.id == selectedPlanId)
                    .dayReports
                    .containsKey(dateKey);

            return AlertDialog(
              title: Text(
                'Tarihe Saat Girişi\n${date.day} ${_monthNames[date.month - 1]} ${date.year}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedPlanId != null) ...[
                      (() {
                        final p = allPlans.firstWhere(
                          (plan) => plan.id == selectedPlanId,
                        );
                        final totalWorkedHours = p.dayReports.values
                            .map((r) => r.hoursWorked)
                            .fold(0.0, (a, b) => a + b);
                        final target = p.targetHours;
                        final totalProgress = target > 0
                            ? (totalWorkedHours / target) * 100
                            : 0.0;
                        final remaining = target - totalWorkedHours;

                        double workedHoursUpToDate = 0.0;
                        for (var entry in p.dayReports.entries) {
                          try {
                            final entryDate = DateTime.parse(entry.key);
                            if (entryDate.isBefore(date) ||
                                entryDate.isAtSameMomentAs(date)) {
                              workedHoursUpToDate += entry.value.hoursWorked;
                            }
                          } catch (_) {}
                        }
                        final progressUpToDate = target > 0
                            ? (workedHoursUpToDate / target) * 100
                            : 0.0;

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Adım Durumu: ${p.status == 'Yapılanlar' ? 'Tamamlandı' : p.status}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Hedef Süre:',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    '${target.toStringAsFixed(1)} sa',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Toplam Çalışılan:',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    '${totalWorkedHours.toStringAsFixed(1)} sa',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Kalan Süre:',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    '${remaining > 0 ? remaining.toStringAsFixed(1) : 0.0} sa',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Toplam İlerleme:',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    '%${totalProgress.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Bu Güne Kadar İlerleme:',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    '%${progressUpToDate.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }()),
                    ],
                    DropdownButtonFormField<String?>(
                      initialValue: selectedPlanId,
                      decoration: const InputDecoration(
                        labelText: 'Adım Seçin',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Seçiniz'),
                        ),
                        ...dropdownPlans.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.title),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedPlanId = val;
                          if (val != null) {
                            final p = allPlans.firstWhere(
                              (plan) => plan.id == val,
                            );
                            isCompletedChecked = p.status == 'Yapılanlar';
                            final rep = p.dayReports[dateKey];
                            hoursController.text =
                                rep != null && rep.hoursWorked > 0
                                ? rep.hoursWorked.toString()
                                : '';
                            noteController.text = rep?.note ?? '';
                          } else {
                            isCompletedChecked = false;
                            hoursController.clear();
                            noteController.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: hoursController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Çalışılan Saat',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama / Not',
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Tamamlandı (Seriyi Bitir)',
                        style: TextStyle(fontSize: 14),
                      ),
                      value: isCompletedChecked,
                      onChanged: (val) {
                        setDialogState(() {
                          isCompletedChecked = val ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                if (hasLogForDate)
                  TextButton(
                    onPressed: () {
                      if (selectedPlanId != null) {
                        final p = allPlans.firstWhere(
                          (plan) => plan.id == selectedPlanId,
                        );
                        final Map<String, PlanDayReport> reports = Map.from(
                          p.dayReports,
                        );
                        reports.remove(dateKey);
                        appState.updateTopicPlan(
                          p.copyWith(
                            dayReports: reports,
                            status: isCompletedChecked
                                ? 'Yapılanlar'
                                : 'Yapılıyor',
                          ),
                        );
                      }
                      Navigator.pop(context);
                      setState(() {});
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Logu Sil'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedPlanId != null) {
                      final p = allPlans.firstWhere(
                        (plan) => plan.id == selectedPlanId,
                      );
                      final hours =
                          double.tryParse(hoursController.text) ?? 0.0;
                      final note = noteController.text.trim();

                      final Map<String, PlanDayReport> reports = Map.from(
                        p.dayReports,
                      );
                      reports[dateKey] = PlanDayReport(
                        hoursWorked: hours,
                        note: note,
                        offset: hours > 0 ? 0 : 1,
                      );

                      appState.updateTopicPlan(
                        p.copyWith(
                          status: isCompletedChecked
                              ? 'Yapılanlar'
                              : 'Yapılıyor',
                          endDate: isCompletedChecked ? date : p.endDate,
                          dayReports: reports,
                        ),
                      );
                    }
                    Navigator.pop(context);
                    setState(() {});
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

  void _showAddEvaluationDialog(
    BuildContext context,
    AppState appState,
    DateTime date, {
    ProjectEvaluation? existingEval,
  }) {
    if (widget.projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hata: Proje ID bulunamadı.')),
      );
      return;
    }

    final project = appState.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => const Project(
        id: '',
        title: '',
        colorValue: 0,
        evaluationType: 'PERCENTAGE',
        targetValue: 100,
      ),
    );

    showProjectEvaluationDialog(
      context: context,
      project: project,
      date: date,
      onSaved: () {
        setState(() {});
      },
    );
  }

  Color _getDistinctPredictionColor(String planId, int baseColorValue, bool isPredicted) {
    if (!isPredicted) return Color(baseColorValue);
    final hash = planId.hashCode;
    final hues = [45, 75, 105, 135, 165, 195, 220, 240, 265, 285];
    final hue = hues[hash.abs() % hues.length].toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.75, 0.42).toColor();
  }

  Future<String?> _showGetExclusionNoteDialog(BuildContext context, {String? initialValue}) async {
    final controller = TextEditingController(text: initialValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pas Günü Açıklaması'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Örn: Ara Tatil, Yıllık İzin (İsteğe bağlı)',
            labelText: 'Açıklama',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showManageExcludedDatesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pas Geçilecek Özel Tarihler'),
              content: SizedBox(
                width: 340,
                height: 400,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Tarih Ekle', style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              final note = await _showGetExclusionNoteDialog(context);
                              setState(() {
                                _generalExcludedExclusions.add(ExcludedDateItem(
                                  date: DateTime(picked.year, picked.month, picked.day),
                                  note: note,
                                ));
                              });
                              _saveSettings();
                              setDialogState(() {});
                            }
                          },
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.date_range, size: 16),
                          label: const Text('Aralık Ekle', style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            final pickedRange = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (pickedRange != null) {
                              final note = await _showGetExclusionNoteDialog(context);
                              setState(() {
                                _generalExcludedExclusions.add(ExcludedDateItem(
                                  start: DateTime(pickedRange.start.year, pickedRange.start.month, pickedRange.start.day),
                                  end: DateTime(pickedRange.end.year, pickedRange.end.month, pickedRange.end.day),
                                  note: note,
                                ));
                              });
                              _saveSettings();
                              setDialogState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: _generalExcludedExclusions.isEmpty
                          ? const Center(
                              child: Text(
                                'Eklenmiş özel pas günü bulunmuyor.',
                                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _generalExcludedExclusions.length,
                              itemBuilder: (context, index) {
                                final d = _generalExcludedExclusions[index];
                                String dateStr = '';
                                if (d.date != null) {
                                  dateStr = '${d.date!.day}.${d.date!.month}.${d.date!.year} (${_getWeekdayShortName(d.date!.weekday)})';
                                } else if (d.start != null && d.end != null) {
                                  dateStr = '${d.start!.day}.${d.start!.month}.${d.start!.year} - ${d.end!.day}.${d.end!.month}.${d.end!.year}';
                                }
                                return ListTile(
                                  dense: true,
                                  title: Text(dateStr, style: const TextStyle(fontSize: 12)),
                                  subtitle: d.note != null && d.note!.isNotEmpty
                                      ? Text(d.note!, style: const TextStyle(fontSize: 10, color: Colors.grey))
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                        onPressed: () async {
                                          if (d.date != null) {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: d.date!,
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2100),
                                            );
                                            if (picked != null) {
                                              final note = await _showGetExclusionNoteDialog(context, initialValue: d.note);
                                              setState(() {
                                                _generalExcludedExclusions[index] = ExcludedDateItem(
                                                  date: DateTime(picked.year, picked.month, picked.day),
                                                  note: note,
                                                );
                                              });
                                              _saveSettings();
                                              setDialogState(() {});
                                            }
                                          } else if (d.start != null && d.end != null) {
                                            final pickedRange = await showDateRangePicker(
                                              context: context,
                                              initialDateRange: DateTimeRange(start: d.start!, end: d.end!),
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2100),
                                            );
                                            if (pickedRange != null) {
                                              final note = await _showGetExclusionNoteDialog(context, initialValue: d.note);
                                              setState(() {
                                                _generalExcludedExclusions[index] = ExcludedDateItem(
                                                  start: DateTime(pickedRange.start.year, pickedRange.start.month, pickedRange.start.day),
                                                  end: DateTime(pickedRange.end.year, pickedRange.end.month, pickedRange.end.day),
                                                  note: note,
                                                );
                                              });
                                              _saveSettings();
                                              setDialogState(() {});
                                            }
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _generalExcludedExclusions.removeAt(index);
                                          });
                                          _saveSettings();
                                          setDialogState(() {});
                                        },
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;

    // Attempt auto-scroll to today
    if (!_hasScrolledToToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_verticalScrollController.hasClients) {
          _scrollToDate(DateTime.now());
          setState(() {
            _hasScrolledToToday = true;
          });
        }
      });
    }

    final projectPlans = appState.topicPlans
        .where((p) => p.projectId == widget.projectId)
        .toList();

    final evaluations = appState.evaluations
        .where((e) => e.projectId == widget.projectId)
        .toList();

    // Map to store predicted reports: planId -> Map<dayKey, hours>
    final Map<String, Map<String, double>> predictionMap = {};
    final Map<String, DateTime> planStartDates = {};

    if (_showPrediction) {
      // 1. Unfinished active/scheduled steps (status is Yapılıyor or Bekleyenler)
      final activeSteps = projectPlans
          .where((p) => p.status == 'Yapılıyor' || p.status == 'Bekleyenler')
          .toList();
      activeSteps.sort(
        (a, b) => getPlanStartDate(a).compareTo(getPlanStartDate(b)),
      );

      // 2. Unfinished pool steps (status is Yapılacak)
      final poolSteps = projectPlans
          .where((p) => p.status == 'Yapılacak')
          .toList();
      poolSteps.sort((a, b) => b.importance.compareTo(a.importance));

      final List<TopicPlan> predictionQueue = [];
      predictionQueue.addAll(activeSteps);
      predictionQueue.addAll(poolSteps);

      final Map<String, double> remainingHoursMap = {};

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (var plan in predictionQueue) {
        final totalLoggedHours = plan.dayReports.values
            .map((r) => r.hoursWorked)
            .fold(0.0, (a, b) => a + b);
        final remaining = plan.targetHours - totalLoggedHours;
        remainingHoursMap[plan.id] = remaining > 0 ? remaining : 0.0;

        DateTime? maxLoggedDate;
        for (var entry in plan.dayReports.entries) {
          if (entry.value.hoursWorked > 0) {
            try {
              final parsed = DateTime.parse(entry.key);
              if (maxLoggedDate == null || parsed.isAfter(maxLoggedDate)) {
                maxLoggedDate = parsed;
              }
            } catch (_) {}
          }
        }

        DateTime initialStart;
        if (maxLoggedDate != null) {
          final nextDay = maxLoggedDate.add(const Duration(days: 1));
          initialStart = nextDay.isBefore(today) ? today : nextDay;
        } else {
          initialStart = today;
        }

        planStartDates[plan.id] = DateTime(
          initialStart.year,
          initialStart.month,
          initialStart.day,
        );
        predictionMap[plan.id] = {};
      }

      if (predictionQueue.isNotEmpty) {
        DateTime current = today;

        int safetyDays = 0;
        while (predictionQueue.any((p) => remainingHoursMap[p.id]! > 0) &&
            safetyDays < 730) {
          safetyDays++;

          final isWeekend =
              current.weekday == DateTime.saturday ||
              current.weekday == DateTime.sunday;
          final isGenExcludedWeekday = _generalExcludedWeekdays.contains(
            current.weekday,
          );
          final isGenExcludedDate = _generalExcludedExclusions.any((e) => e.contains(current));

          if (!isGenExcludedWeekday && !isGenExcludedDate) {
            double availableCapacity = _dailyCapacityHours;

            for (var plan in predictionQueue) {
              if (availableCapacity <= 0) break;
              final rem = remainingHoursMap[plan.id]!;
              if (rem <= 0) continue;

              final pStart = planStartDates[plan.id]!;
              if (current.isBefore(pStart)) {
                continue;
              }

              final isPlanExcludedWeekend = plan.excludeWeekends && isWeekend;
              final isPlanExcludedWeekday = plan.excludedWeekdays.contains(
                current.weekday,
              );
              final isPlanExcludedDate = plan.excludedDates.any(
                (d) =>
                    d.year == current.year &&
                    d.month == current.month &&
                    d.day == current.day,
              );

              if (!isPlanExcludedWeekend &&
                  !isPlanExcludedWeekday &&
                  !isPlanExcludedDate) {
                final allocated = rem < availableCapacity
                    ? rem
                    : availableCapacity;
                final key =
                    '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';

                predictionMap[plan.id]![key] =
                    (predictionMap[plan.id]![key] ?? 0.0) + allocated;
                remainingHoursMap[plan.id] = rem - allocated;
                availableCapacity -= allocated;

                if (remainingHoursMap[plan.id]! <= 0) {
                  final nextPlanIdx = predictionQueue.indexOf(plan) + 1;
                  if (nextPlanIdx < predictionQueue.length) {
                    final nextPlan = predictionQueue[nextPlanIdx];
                    planStartDates[nextPlan.id] = current;
                  }
                }
              }
            }
          }
          current = current.add(const Duration(days: 1));
        }
      }
    }

    DateTime getVisualStartDate(TopicPlan plan) {
      // If it has logs, it always starts at the first log date
      final hasLogs = plan.dayReports.values.any((rep) => rep.hoursWorked > 0);
      if (hasLogs) {
        final d = getPlanStartDate(plan);
        return DateTime(d.year, d.month, d.day);
      }
      // If prediction is on and we have predicted dates for it, start at the first predicted date
      if (_showPrediction &&
          predictionMap.containsKey(plan.id) &&
          predictionMap[plan.id]!.isNotEmpty) {
        final keys = predictionMap[plan.id]!.keys.toList()..sort();
        final firstKey = keys.first;
        final parts = firstKey.split('-');
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
      final d = getPlanStartDate(plan);
      return DateTime(d.year, d.month, d.day);
    }

    DateTime getVisualEndDate(TopicPlan plan) {
      if (plan.status == 'Yapılanlar') {
        return DateTime(
          plan.endDate.year,
          plan.endDate.month,
          plan.endDate.day,
        );
      }
      if (_showPrediction &&
          predictionMap.containsKey(plan.id) &&
          predictionMap[plan.id]!.isNotEmpty) {
        final keys = predictionMap[plan.id]!.keys.toList()..sort();
        final lastKey = keys.last;
        final parts = lastKey.split('-');
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    bool plansOverlapVisual(TopicPlan a, TopicPlan b) {
      final startA = getVisualStartDate(a);
      final endA = getVisualEndDate(a);
      final startB = getVisualStartDate(b);
      final endB = getVisualEndDate(b);
      return !(endA.isBefore(startB) || startA.isAfter(endB));
    }

    // Filter to only plans that have at least one log entry with hours worked OR targetHours > 0 if showPrediction is enabled and not completed
    final loggedPlans = projectPlans.where((plan) {
      final hasLogs = plan.dayReports.values.any((rep) => rep.hoursWorked > 0);
      if (hasLogs) return true;
      if (_showPrediction &&
          predictionMap.containsKey(plan.id) &&
          predictionMap[plan.id]!.isNotEmpty)
        return true;
      return false;
    }).toList();

    // Sort plans by dynamic start date
    final sortedPlans = List<TopicPlan>.from(loggedPlans)
      ..sort((a, b) => getVisualStartDate(a).compareTo(getVisualStartDate(b)));

    // Tetris packing logic
    final List<List<TopicPlan>> dynamicColumns = [];
    for (var plan in sortedPlans) {
      int colIndex = -1;
      for (int i = 0; i < dynamicColumns.length; i++) {
        bool fits = true;
        for (var existingPlan in dynamicColumns[i]) {
          if (plansOverlapVisual(plan, existingPlan)) {
            fits = false;
            break;
          }
        }
        if (fits) {
          colIndex = i;
          break;
        }
      }
      if (colIndex != -1) {
        dynamicColumns[colIndex].add(plan);
      } else {
        dynamicColumns.add([plan]);
      }
    }

    return Scaffold(
      body: Column(
        children: [
          // Exclusions and Prediction Control Panel
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // Prediction Toggle Button
                ElevatedButton.icon(
                  icon: Icon(
                    _showPrediction
                        ? Icons.online_prediction
                        : Icons.psychology_outlined,
                    size: 18,
                    color: _showPrediction ? Colors.white : Colors.purple,
                  ),
                  label: Text(
                    _showPrediction ? 'Öngörü: Açık' : 'Öngörü: Kapalı',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _showPrediction ? Colors.white : Colors.purple,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showPrediction
                        ? Colors.purple
                        : Colors.purple.shade50,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _showPrediction = !_showPrediction;
                    });
                  },
                ),
                const SizedBox(width: 16),

                // Daily Capacity Hours Input
                const Text(
                  'Günlük Kapasite:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  height: 32,
                  child: TextField(
                    controller: _capacityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'saat',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 24),

                // Days to Skip Selection
                const Text(
                  'Pas Geçilecek Günler:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(7, (index) {
                        final weekday = index + 1;
                        final daysShort = [
                          'Pzt',
                          'Sal',
                          'Çar',
                          'Per',
                          'Cum',
                          'Cmt',
                          'Paz',
                        ];
                        final isSelected = _generalExcludedWeekdays.contains(
                          weekday,
                        );
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _generalExcludedWeekdays.remove(weekday);
                              } else {
                                _generalExcludedWeekdays.add(weekday);
                              }
                            });
                            _saveSettings();
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.red.shade100
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.red
                                    : Colors.grey.shade400,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              daysShort[index],
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? Colors.red.shade900
                                    : Colors.black87,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.date_range, color: Colors.red, size: 20),
                  tooltip: 'Özel Pas Günlerini Yönet',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showManageExcludedDatesDialog(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left fixed column: Tarih
                SizedBox(
                  width: _dateColWidth,
                  child: Column(
                    children: [
                      // Header Date
                      InkWell(
                        onTap: () => _scrollToDate(DateTime.now()),
                        child: Container(
                          height: 50,
                          color: Colors.grey.shade100,
                          alignment: Alignment.center,
                          child: const Text(
                            'Tarih 📍',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      // Body Dates List
                      Expanded(
                        child: ListView.builder(
                          controller: _verticalScrollController,
                          itemCount: _totalTimelineDays,
                          itemBuilder: (context, index) {
                            final date = _timelineStartDate.add(
                              Duration(days: index),
                            );
                            final dateText = '${date.day} ${_monthNames[date.month - 1]}';
                            final weekdayText = '(${_getWeekdayShortName(date.weekday)})';
                            final now = DateTime.now();
                            final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
                            return Container(
                              height: _rowHeight,
                              decoration: BoxDecoration(
                                border: isToday
                                    ? Border.all(color: Colors.orange.shade700, width: 2.0)
                                    : Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                              ),
                              child: InkWell(
                                onTap: () => _handleLeftDateTap(date),
                                child: Container(
                                  alignment: Alignment.center,
                                  color: isToday ? Colors.orange.shade100 : Colors.blue.shade50,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        dateText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                          color: isToday ? Colors.orange.shade900 : (isDark ? Colors.white70 : Colors.black87),
                                        ),
                                      ),
                                      Text(
                                        weekdayText,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: isToday ? Colors.orange.shade800 : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Right scrollable column: Genel + Kolonlar
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _contentHorizontalController,
                    child: SizedBox(
                      width: (dynamicColumns.length + 1) * _colWidth,
                      child: Column(
                        children: [
                          // Header Rows (Genel + Columns)
                          Container(
                            height: 50,
                            color: Colors.grey.shade100,
                            child: Row(
                              children: List.generate(
                                dynamicColumns.length + 1,
                                (index) {
                                  if (index == 0) {
                                    return Container(
                                      width: _colWidth,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50.withValues(
                                          alpha: 0.5,
                                        ),
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Genel 📝',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                        ),
                                      ),
                                    );
                                  }
                                  return Container(
                                    width: _colWidth,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'Kolon $index',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // Body Rows List
                          Expanded(
                            child: ListView.builder(
                              controller: _cellsVerticalScrollController,
                              itemCount: _totalTimelineDays,
                              itemBuilder: (context, index) {
                                final date = _timelineStartDate.add(
                                  Duration(days: index),
                                );
                                final dayKey =
                                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

                                ProjectEvaluation? dayEval;
                                for (var ev in evaluations) {
                                  if (ev.sessionDate.year == date.year &&
                                      ev.sessionDate.month == date.month &&
                                      ev.sessionDate.day == date.day) {
                                    dayEval = ev;
                                    break;
                                  }
                                }

                                String evalText = '';
                                Color evalBg = Colors.transparent;
                                if (dayEval != null) {
                                  evalBg = Colors.amber.shade50.withValues(
                                    alpha: 0.5,
                                  );
                                  final parts = <String>[];
                                  if (dayEval.isSkipped) {
                                    parts.add('Pas');
                                    ExcludedDateItem? matchedExc;
                                    for (var exc in _generalExcludedExclusions) {
                                      if (exc.contains(date)) {
                                        matchedExc = exc;
                                        break;
                                      }
                                    }
                                    if (matchedExc != null && matchedExc.note != null && matchedExc.note!.isNotEmpty) {
                                      parts.add('(${matchedExc.note})');
                                    }
                                  } else {
                                    if (dayEval.score > 0)
                                      parts.add(
                                        '%${dayEval.score.toStringAsFixed(0)}',
                                      );
                                    if (dayEval.durationHours > 0)
                                      parts.add(
                                        '${dayEval.durationHours.toStringAsFixed(1)} sa',
                                      );
                                  }
                                  evalText = parts.join(' - ');
                                  if (dayEval.note != null &&
                                      dayEval.note!.isNotEmpty) {
                                    evalText += '\n📝 ${dayEval.note}';
                                  }
                                }

                                return Container(
                                  height: _rowHeight,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: List.generate(dynamicColumns.length + 1, (
                                      tIndex,
                                    ) {
                                      if (tIndex == 0) {
                                        return InkWell(
                                          onTap: () => _showAddEvaluationDialog(
                                            context,
                                            appState,
                                            date,
                                            existingEval: dayEval,
                                          ),
                                          child: Container(
                                            width: _colWidth,
                                            decoration: BoxDecoration(
                                              color: evalBg,
                                              border: Border(
                                                right: BorderSide(
                                                  color: Colors.grey.shade200,
                                                ),
                                              ),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Center(
                                              child: Text(
                                                evalText,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.amber.shade900,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      final columnPlans =
                                          dynamicColumns[tIndex - 1];

                                      String cellText = '';
                                      Color cellColor = Colors.transparent;
                                      for (var plan in columnPlans) {
                                        final pStart = getVisualStartDate(plan);
                                        final pEnd = getVisualEndDate(plan);

                                        if ((date.isAfter(pStart) ||
                                                date.isAtSameMomentAs(
                                                  pStart,
                                                )) &&
                                            (date.isBefore(pEnd) ||
                                                date.isAtSameMomentAs(pEnd))) {
                                          final isFirstDay = date
                                              .isAtSameMomentAs(pStart);
                                          final isCompletedDay =
                                              plan.status == 'Yapılanlar' &&
                                              date.isAtSameMomentAs(pEnd);
                                          final rep = plan.dayReports[dayKey];
                                          final hours = rep?.hoursWorked ?? 0.0;

                                          final isPredicted =
                                              _showPrediction &&
                                              predictionMap.containsKey(
                                                plan.id,
                                              ) &&
                                              predictionMap[plan.id]!
                                                  .containsKey(dayKey);

                                          cellColor = _getDistinctPredictionColor(
                                            plan.id,
                                            plan.colorValue,
                                            isPredicted,
                                          ).withValues(alpha: 0.12);

                                          final isGenExcludedWeekday = _generalExcludedWeekdays.contains(date.weekday);
                                          final isGenExcludedDate = _generalExcludedExclusions.any(
                                            (e) => e.contains(date)
                                          );
                                          final isPlanExcludedWeekend = plan.excludeWeekends && (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday);
                                          final isPlanExcludedWeekday = plan.excludedWeekdays.contains(date.weekday);
                                          final isPlanExcludedDate = plan.excludedDates.any(
                                            (d) => d.year == date.year && d.month == date.month && d.day == date.day
                                          );
                                          
                                          ExcludedDateItem? matchedExclusion;
                                          for (var exc in _generalExcludedExclusions) {
                                            if (exc.contains(date)) {
                                              matchedExclusion = exc;
                                              break;
                                            }
                                          }
                                          final isExcluded = isGenExcludedWeekday || (matchedExclusion != null) || isPlanExcludedWeekend || isPlanExcludedWeekday || isPlanExcludedDate;

                                          if (isExcluded) {
                                            bool isFirstExclusionDay = false;
                                            if (matchedExclusion != null) {
                                              if (matchedExclusion.date != null) {
                                                isFirstExclusionDay = true;
                                              } else if (matchedExclusion.start != null) {
                                                isFirstExclusionDay = (date.year == matchedExclusion.start!.year &&
                                                                      date.month == matchedExclusion.start!.month &&
                                                                      date.day == matchedExclusion.start!.day);
                                              }
                                            }
                                            String noteText = '';
                                            if (isFirstExclusionDay && matchedExclusion?.note != null && matchedExclusion!.note!.isNotEmpty) {
                                              noteText = '\n(${matchedExclusion.note})';
                                            }

                                            if (isFirstDay) {
                                              cellText = '${plan.title}\n(Pas)$noteText';
                                            } else {
                                              cellText = 'Pas$noteText';
                                            }
                                            cellColor = Theme.of(context).brightness == Brightness.dark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50;
                                          } else if (isFirstDay) {
                                            if (isCompletedDay) {
                                              cellText = hours > 0
                                                  ? '🏁 ${plan.title}\n($hours sa)'
                                                  : '🏁 ${plan.title}';
                                            } else if (isPredicted) {
                                              final predHours =
                                                  predictionMap[plan
                                                      .id]![dayKey]!;
                                              cellText =
                                                  '🔮 ${plan.title}\n(${predHours.toStringAsFixed(1)} sa)';
                                            } else if (rep?.isWaiting == true) {
                                              cellText = '${plan.title}\n⌛';
                                            } else if (rep?.offset == 1) {
                                              final taskPasCount = appState.getTaskPasCount(plan, date);
                                              cellText = '${plan.title}\nPas $taskPasCount';
                                            } else {
                                              cellText = hours > 0
                                                  ? '${plan.title}\n($hours sa)'
                                                  : plan.title;
                                            }

                                            if (rep?.offset == 1) {
                                              cellColor = Theme.of(context).brightness == Brightness.dark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50;
                                            } else {
                                              cellColor = _getDistinctPredictionColor(
                                                plan.id,
                                                plan.colorValue,
                                                isPredicted,
                                              ).withValues(
                                                alpha: isPredicted
                                                    ? 0.2
                                                    : 0.35,
                                              );
                                            }
                                          } else {
                                            if (hours > 0 ||
                                                isCompletedDay ||
                                                isPredicted ||
                                                rep?.isWaiting == true ||
                                                rep?.offset == 1) {
                                              if (isCompletedDay) {
                                                cellText = hours > 0
                                                    ? '🏁\n($hours sa)'
                                                    : '🏁';
                                              } else if (isPredicted) {
                                                final predHours =
                                                    predictionMap[plan
                                                        .id]![dayKey]!;
                                                cellText =
                                                    '🔮\n(${predHours.toStringAsFixed(1)} sa)';
                                              } else if (rep?.isWaiting == true) {
                                                cellText = '⌛';
                                              } else if (rep?.offset == 1) {
                                                final taskPasCount = appState.getTaskPasCount(plan, date);
                                                cellText = 'Pas $taskPasCount';
                                              } else {
                                                cellText = '($hours sa)';
                                              }
                                              if (rep?.offset == 1) {
                                                cellColor = Theme.of(context).brightness == Brightness.dark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50;
                                              } else {
                                                cellColor = _getDistinctPredictionColor(
                                                  plan.id,
                                                  plan.colorValue,
                                                  isPredicted,
                                                ).withValues(
                                                  alpha: isPredicted
                                                      ? 0.2
                                                      : 0.35,
                                                );
                                              }
                                            }
                                          }
                                          break;
                                        }
                                      }

                                      String? activePlanId;
                                      for (var plan in columnPlans) {
                                        final pStart = getVisualStartDate(plan);
                                        final pEnd = getVisualEndDate(plan);
                                        if ((date.isAfter(pStart) ||
                                                date.isAtSameMomentAs(
                                                  pStart,
                                                )) &&
                                            (date.isBefore(pEnd) ||
                                                date.isAtSameMomentAs(pEnd))) {
                                          activePlanId = plan.id;
                                          break;
                                        }
                                      }

                                      return InkWell(
                                        onTap: () {
                                          final appState =
                                              Provider.of<AppState>(
                                                context,
                                                listen: false,
                                              );
                                          final allPlans = appState.topicPlans
                                              .where(
                                                (p) =>
                                                    p.projectId ==
                                                    widget.projectId,
                                              )
                                              .toList();

                                          TopicPlan? restrictedPlan;
                                          for (var plan in columnPlans) {
                                            if (plan.status != 'Yapılanlar') {
                                              final pStart = getVisualStartDate(
                                                plan,
                                              );
                                              if (date.isAfter(pStart) ||
                                                  date.isAtSameMomentAs(
                                                    pStart,
                                                  )) {
                                                restrictedPlan = plan;
                                                break;
                                              }
                                            }
                                          }

                                          final List<TopicPlan> dropdownPlans;
                                          if (restrictedPlan != null) {
                                            dropdownPlans = [restrictedPlan];
                                          } else {
                                            dropdownPlans = allPlans.where((
                                              plan,
                                            ) {
                                              if (plan.status == 'Yapılanlar') {
                                                final pEnd = getVisualEndDate(
                                                  plan,
                                                );
                                                if (date.isAfter(pEnd)) {
                                                  return false;
                                                }
                                              }
                                              return true;
                                            }).toList();
                                          }

                                          _showLeftDateHourEntryDialog(
                                            context,
                                            date,
                                            appState,
                                            allPlans,
                                            initialPlanId:
                                                activePlanId ??
                                                restrictedPlan?.id,
                                            restrictedPlans: dropdownPlans,
                                          );
                                        },
                                        child: Container(
                                          width: _colWidth,
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: cellColor,
                                            border: Border(
                                              right: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              cellText,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: cellText.contains('Pas') ? (isDark ? Colors.red.shade300 : Colors.red.shade800) : null,
                                                fontWeight: cellText.contains('Pas') ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExcludedDateItem {
  final DateTime? date; // For single date
  final DateTime? start; // For range
  final DateTime? end; // For range
  final String? note; // Note/description

  ExcludedDateItem({this.date, this.start, this.end, this.note});

  bool contains(DateTime d) {
    if (date != null) {
      return date!.year == d.year && date!.month == d.month && date!.day == d.day;
    }
    if (start != null && end != null) {
      final target = DateTime(d.year, d.month, d.day);
      final s = DateTime(start!.year, start!.month, start!.day);
      final e = DateTime(end!.year, end!.month, end!.day);
      return (target.isAfter(s) || target.isAtSameMomentAs(s)) &&
             (target.isBefore(e) || target.isAtSameMomentAs(e));
    }
    return false;
  }

  String toJsonString() {
    final notePart = note != null ? note! : '';
    if (date != null) {
      return 'SINGLE:${date!.toIso8601String()}|$notePart';
    } else {
      return 'RANGE:${start!.toIso8601String()}|${end!.toIso8601String()}|$notePart';
    }
  }

  factory ExcludedDateItem.fromJsonString(String s) {
    if (s.startsWith('SINGLE:')) {
      final content = s.substring(7);
      final parts = content.split('|');
      final date = DateTime.parse(parts[0]);
      final note = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
      return ExcludedDateItem(date: date, note: note);
    } else {
      final content = s.substring(6);
      final parts = content.split('|');
      final start = DateTime.parse(parts[0]);
      final end = DateTime.parse(parts[1]);
      final note = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
      return ExcludedDateItem(start: start, end: end, note: note);
    }
  }
}
