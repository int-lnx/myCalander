import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/topic.dart';
import '../models/topic_plan.dart';
import '../models/project_evaluation.dart';
import '../utils/id_generator.dart';

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
  late ScrollController _headerHorizontalController;
  late ScrollController _contentHorizontalController;
  bool _showPrediction = false;
  double _dailyCapacityHours = 2.0;
  late TextEditingController _capacityController;
  final List<int> _generalExcludedWeekdays = [];
  final Set<DateTime> _generalExcludedDates = {};
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

  @override
  void initState() {
    super.initState();
    _capacityController = TextEditingController(
      text: _dailyCapacityHours.toString(),
    );
    _capacityController.addListener(() {
      final val = double.tryParse(_capacityController.text);
      if (val != null && val > 0 && val != _dailyCapacityHours) {
        setState(() {
          _dailyCapacityHours = val;
        });
      }
    });
    _verticalScrollController = ScrollController();
    _headerHorizontalController = ScrollController();
    _contentHorizontalController = ScrollController();

    _contentHorizontalController.addListener(() {
      if (_headerHorizontalController.hasClients &&
          _headerHorizontalController.offset !=
              _contentHorizontalController.offset) {
        _headerHorizontalController.jumpTo(_contentHorizontalController.offset);
      }
    });

    _headerHorizontalController.addListener(() {
      if (_contentHorizontalController.hasClients &&
          _contentHorizontalController.offset !=
              _headerHorizontalController.offset) {
        _contentHorizontalController.jumpTo(_headerHorizontalController.offset);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDate(DateTime.now());
    });
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _headerHorizontalController.dispose();
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
          content: Text('Lütfen önce Görev Havuzuna giderek bir adım/görev ekleyin.'),
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
    _showLeftDateHourEntryDialog(context, clickedDate, appState, allPlans, restrictedPlans: availablePlans);
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
      final p = allPlans.firstWhere((plan) => plan.id == selectedPlanId, orElse: () => allPlans.first);
      isCompletedChecked = p.status == 'Yapılanlar';
      final rep = p.dayReports[dateKey];
      hoursController.text = rep != null && rep.hoursWorked > 0 ? rep.hoursWorked.toString() : '';
      noteController.text = rep?.note ?? '';
    }

    final dropdownPlans = restrictedPlans ?? allPlans;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasLogForDate = selectedPlanId != null &&
                allPlans.firstWhere((plan) => plan.id == selectedPlanId).dayReports.containsKey(dateKey);

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
                        final p = allPlans.firstWhere((plan) => plan.id == selectedPlanId);
                        final totalWorkedHours = p.dayReports.values.map((r) => r.hoursWorked).fold(0.0, (a, b) => a + b);
                        final target = p.targetHours;
                        final totalProgress = target > 0 ? (totalWorkedHours / target) * 100 : 0.0;
                        final remaining = target - totalWorkedHours;
                        
                        double workedHoursUpToDate = 0.0;
                        for (var entry in p.dayReports.entries) {
                          try {
                            final entryDate = DateTime.parse(entry.key);
                            if (entryDate.isBefore(date) || entryDate.isAtSameMomentAs(date)) {
                              workedHoursUpToDate += entry.value.hoursWorked;
                            }
                          } catch (_) {}
                        }
                        final progressUpToDate = target > 0 ? (workedHoursUpToDate / target) * 100 : 0.0;

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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Hedef Süre:', style: TextStyle(fontSize: 11)),
                                  Text('${target.toStringAsFixed(1)} sa', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Toplam Çalışılan:', style: TextStyle(fontSize: 11)),
                                  Text('${totalWorkedHours.toStringAsFixed(1)} sa', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Kalan Süre:', style: TextStyle(fontSize: 11)),
                                  Text('${remaining > 0 ? remaining.toStringAsFixed(1) : 0.0} sa', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const Divider(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Toplam İlerleme:', style: TextStyle(fontSize: 11)),
                                  Text('%${totalProgress.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Bu Güne Kadar İlerleme:', style: TextStyle(fontSize: 11)),
                                  Text('%${progressUpToDate.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        );
                      }()),
                    ],
                    DropdownButtonFormField<String?>(
                      value: selectedPlanId,
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
                        appState.updateTopicPlan(p.copyWith(
                          dayReports: reports,
                          status: isCompletedChecked ? 'Yapılanlar' : 'Yapılıyor',
                        ));
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

                      appState.updateTopicPlan(p.copyWith(
                        status: isCompletedChecked ? 'Yapılanlar' : 'Yapılıyor',
                        endDate: isCompletedChecked ? date : p.endDate,
                        dayReports: reports,
                      ));
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

  void _showAddEvaluationDialog(BuildContext context, AppState appState, DateTime date, {ProjectEvaluation? existingEval}) {
    if (widget.projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hata: Proje ID bulunamadı.')),
      );
      return;
    }

    final scoreController = TextEditingController(
      text: existingEval != null ? existingEval.score.toStringAsFixed(0) : '',
    );
    final durationController = TextEditingController(
      text: existingEval != null ? existingEval.durationHours.toString() : '',
    );
    final noteController = TextEditingController(
      text: existingEval?.note ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Değerlendirme / Genel Log\n${date.day} ${_monthNames[date.month - 1]} ${date.year}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: scoreController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Puan / Performans (%)'),
                    ),
                    TextField(
                      controller: durationController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Çalışılan Saat (Süre)'),
                    ),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Not / Açıklama'),
                    ),
                  ],
                ),
              ),
              actions: [
                if (existingEval != null)
                  TextButton(
                    onPressed: () {
                      appState.deleteEvaluation(widget.projectId!, date);
                      Navigator.pop(context);
                      setState(() {});
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Sil'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final score = double.tryParse(scoreController.text) ?? 0.0;
                    final duration = double.tryParse(durationController.text) ?? 0.0;
                    final note = noteController.text.trim();

                    final eval = ProjectEvaluation(
                      id: '${widget.projectId}_${date.millisecondsSinceEpoch}',
                      projectId: widget.projectId!,
                      sessionDate: DateTime(date.year, date.month, date.day),
                      score: score,
                      durationHours: duration,
                      note: note.isNotEmpty ? note : null,
                      isSkipped: false,
                    );
                    appState.addOrUpdateEvaluation(eval);
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

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    
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
      final activeSteps = projectPlans.where((p) =>
          p.status == 'Yapılıyor' || p.status == 'Bekleyenler'
      ).toList();
      activeSteps.sort((a, b) => getPlanStartDate(a).compareTo(getPlanStartDate(b)));

      // 2. Unfinished pool steps (status is Yapılacak)
      final poolSteps = projectPlans.where((p) =>
          p.status == 'Yapılacak'
      ).toList();
      poolSteps.sort((a, b) => b.importance.compareTo(a.importance));

      final List<TopicPlan> predictionQueue = [];
      predictionQueue.addAll(activeSteps);
      predictionQueue.addAll(poolSteps);

      final Map<String, double> remainingHoursMap = {};

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (var plan in predictionQueue) {
        final totalLoggedHours = plan.dayReports.values.map((r) => r.hoursWorked).fold(0.0, (a, b) => a + b);
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
        
        planStartDates[plan.id] = DateTime(initialStart.year, initialStart.month, initialStart.day);
        predictionMap[plan.id] = {};
      }

      if (predictionQueue.isNotEmpty) {
        DateTime current = today;
        
        int safetyDays = 0;
        while (predictionQueue.any((p) => remainingHoursMap[p.id]! > 0) && safetyDays < 730) {
          safetyDays++;
          
          final isWeekend = current.weekday == DateTime.saturday || current.weekday == DateTime.sunday;
          final isGenExcludedWeekday = _generalExcludedWeekdays.contains(current.weekday);
          final isGenExcludedDate = _generalExcludedDates.contains(current);

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
              final isPlanExcludedWeekday = plan.excludedWeekdays.contains(current.weekday);
              final isPlanExcludedDate = plan.excludedDates.any((d) => d.year == current.year && d.month == current.month && d.day == current.day);
              
              if (!isPlanExcludedWeekend && !isPlanExcludedWeekday && !isPlanExcludedDate) {
                final allocated = rem < availableCapacity ? rem : availableCapacity;
                final key = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
                
                predictionMap[plan.id]![key] = (predictionMap[plan.id]![key] ?? 0.0) + allocated;
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
      if (_showPrediction && predictionMap.containsKey(plan.id) && predictionMap[plan.id]!.isNotEmpty) {
        final keys = predictionMap[plan.id]!.keys.toList()..sort();
        final firstKey = keys.first;
        final parts = firstKey.split('-');
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
      final d = getPlanStartDate(plan);
      return DateTime(d.year, d.month, d.day);
    }

    DateTime getVisualEndDate(TopicPlan plan) {
      if (plan.status == 'Yapılanlar') {
        return DateTime(plan.endDate.year, plan.endDate.month, plan.endDate.day);
      }
      if (_showPrediction && predictionMap.containsKey(plan.id) && predictionMap[plan.id]!.isNotEmpty) {
        final keys = predictionMap[plan.id]!.keys.toList()..sort();
        final lastKey = keys.last;
        final parts = lastKey.split('-');
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
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
      if (_showPrediction && predictionMap.containsKey(plan.id) && predictionMap[plan.id]!.isNotEmpty) return true;
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // Prediction Toggle Button
                ElevatedButton.icon(
                  icon: Icon(
                    _showPrediction ? Icons.online_prediction : Icons.psychology_outlined,
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
                    backgroundColor: _showPrediction ? Colors.purple : Colors.purple.shade50,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        final daysShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
                        final isSelected = _generalExcludedWeekdays.contains(weekday);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _generalExcludedWeekdays.remove(weekday);
                              } else {
                                _generalExcludedWeekdays.add(weekday);
                              }
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.red.shade100 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.red : Colors.grey.shade400,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              daysShort[index],
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected ? Colors.red.shade900 : Colors.black87,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 50,
            color: Colors.grey.shade100,
            child: Row(
              children: [
                InkWell(
                  onTap: () => _scrollToDate(DateTime.now()),
                  child: Container(
                    width: _dateColWidth,
                    alignment: Alignment.center,
                    child: const Text(
                      'Tarih 📍',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Container(
                  width: _colWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50.withValues(alpha: 0.5),
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
                ),
                Expanded(
                  child: dynamicColumns.isEmpty
                      ? Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 16.0),
                          child: const Text(
                            'Soldaki mavi tarih sütununa tıklayarak ilk logunuzu ekleyin.',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _headerHorizontalController,
                          scrollDirection: Axis.horizontal,
                          itemCount: dynamicColumns.length,
                          itemBuilder: (context, index) {
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
                                'Kolon ${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _verticalScrollController,
                    itemCount: _totalTimelineDays,
                    itemBuilder: (context, index) {
                      final date = _timelineStartDate.add(
                        Duration(days: index),
                      );
                      final dateStr =
                          '${date.day} ${_monthNames[date.month - 1]}';
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
                        evalBg = Colors.amber.shade50.withValues(alpha: 0.5);
                        final parts = <String>[];
                        if (dayEval.score > 0) parts.add('%${dayEval.score.toStringAsFixed(0)}');
                        if (dayEval.durationHours > 0) parts.add('${dayEval.durationHours.toStringAsFixed(1)} sa');
                        evalText = parts.join(' - ');
                        if (dayEval.note != null && dayEval.note!.isNotEmpty) {
                          evalText += '\n📝 ${dayEval.note}';
                        }
                      }

                      return Container(
                        height: _rowHeight,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _handleLeftDateTap(date),
                              child: Container(
                                width: _dateColWidth,
                                alignment: Alignment.center,
                                color: Colors.blue.shade50,
                                child: Text(
                                  dateStr,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _showAddEvaluationDialog(context, appState, date, existingEval: dayEval),
                              child: Container(
                                width: _colWidth,
                                decoration: BoxDecoration(
                                  color: evalBg,
                                  border: Border(
                                    right: BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: ScrollController(
                                  initialScrollOffset: _contentHorizontalController.hasClients
                                      ? _contentHorizontalController.offset
                                      : 0.0,
                                ),
                                scrollDirection: Axis.horizontal,
                                itemCount: dynamicColumns.length,
                                itemBuilder: (context, tIndex) {
                                  final columnPlans = dynamicColumns[tIndex];

                                  String cellText = '';
                                  Color cellColor = Colors.transparent;
                                  for (var plan in columnPlans) {
                                    final pStart = getVisualStartDate(plan);
                                    final pEnd = getVisualEndDate(plan);
                                    final pHighlightEnd = getVisualEndDate(plan);

                                    if ((date.isAfter(pStart) || date.isAtSameMomentAs(pStart)) &&
                                        (date.isBefore(pEnd) || date.isAtSameMomentAs(pEnd))) {
                                      
                                      // Set light highlight color if date is between start and highlightEnd
                                      cellColor = Color(plan.colorValue).withValues(alpha: 0.12);

                                      final isFirstDay = date.isAtSameMomentAs(pStart);
                                      final isCompletedDay = plan.status == 'Yapılanlar' && date.isAtSameMomentAs(pEnd);
                                      final rep = plan.dayReports[dayKey];
                                      final hours = rep?.hoursWorked ?? 0.0;
                                      
                                      final isPredicted = _showPrediction &&
                                          predictionMap.containsKey(plan.id) &&
                                          predictionMap[plan.id]!.containsKey(dayKey);

                                      if (isFirstDay) {
                                        if (isCompletedDay) {
                                          cellText = hours > 0 ? '🏁 ${plan.title}\n($hours sa)' : '🏁 ${plan.title}';
                                        } else if (isPredicted) {
                                          final predHours = predictionMap[plan.id]![dayKey]!;
                                          cellText = '🔮 ${plan.title}\n(${predHours.toStringAsFixed(1)} sa)';
                                        } else {
                                          cellText = hours > 0 ? '${plan.title}\n($hours sa)' : plan.title;
                                        }
                                        cellColor = Color(plan.colorValue).withValues(alpha: isPredicted ? 0.2 : 0.35);
                                      } else {
                                        if (hours > 0 || isCompletedDay || isPredicted) {
                                          if (isCompletedDay) {
                                            cellText = hours > 0 ? '🏁\n($hours sa)' : '🏁';
                                          } else if (isPredicted) {
                                            final predHours = predictionMap[plan.id]![dayKey]!;
                                            cellText = '🔮\n(${predHours.toStringAsFixed(1)} sa)';
                                          } else {
                                            cellText = '($hours sa)';
                                          }
                                          cellColor = Color(plan.colorValue).withValues(alpha: isPredicted ? 0.2 : 0.35);
                                        }
                                      }
                                      break;
                                    }
                                  }

                                  // Find active plan in this column on this date to pre-select it
                                  String? activePlanId;
                                  for (var plan in columnPlans) {
                                    final pStart = getVisualStartDate(plan);
                                    final pEnd = getVisualEndDate(plan);
                                    if ((date.isAfter(pStart) || date.isAtSameMomentAs(pStart)) &&
                                        (date.isBefore(pEnd) || date.isAtSameMomentAs(pEnd))) {
                                      activePlanId = plan.id;
                                      break;
                                    }
                                  }

                                  return InkWell(
                                    onTap: () {
                                      final appState = Provider.of<AppState>(context, listen: false);
                                      final allPlans = appState.topicPlans
                                          .where((p) => p.projectId == widget.projectId)
                                          .toList();

                                      // Check if there is an ongoing plan in this column that started on or before this date
                                      TopicPlan? restrictedPlan;
                                      for (var plan in columnPlans) {
                                        if (plan.status != 'Yapılanlar') {
                                          final pStart = getVisualStartDate(plan);
                                          if (date.isAfter(pStart) || date.isAtSameMomentAs(pStart)) {
                                            restrictedPlan = plan;
                                            break;
                                          }
                                        }
                                      }

                                      final List<TopicPlan> dropdownPlans;
                                      if (restrictedPlan != null) {
                                        dropdownPlans = [restrictedPlan];
                                      } else {
                                        dropdownPlans = allPlans.where((plan) {
                                          if (plan.status == 'Yapılanlar') {
                                            final pEnd = getVisualEndDate(plan);
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
                                        initialPlanId: activePlanId ?? restrictedPlan?.id,
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
                                          style: const TextStyle(fontSize: 10),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
    );
  }
}
