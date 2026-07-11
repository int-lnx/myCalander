import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/topic.dart';
import '../models/topic_plan.dart';
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
  final bool _showPrediction = false;
  final double _dailyCapacityHours = 2.0;
  late TextEditingController _capacityController;
  final List<int> _generalExcludedWeekdays = [];
  final Set<DateTime> _generalExcludedDates = {};

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
      _cleanLeftoverEmptyTopics();
    });
  }

  void _cleanLeftoverEmptyTopics() {
    final appState = Provider.of<AppState>(context, listen: false);
    final topics = appState.topics
        .where((t) => t.projectId == widget.projectId)
        .toList();
    for (final topic in topics) {
      final hasPlans = appState.topicPlans.any((p) => p.topicId == topic.id);
      if (!hasPlans) {
        appState.deleteTopic(topic.id);
      }
    }
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

  void _handleLeftDateTap(DateTime clickedDate) {
    final appState = Provider.of<AppState>(context, listen: false);
    List<Topic> topics = appState.topics
        .where((t) => t.projectId == widget.projectId)
        .toList();
    if (topics.isEmpty) {
      final newTopic = Topic(
        id: IdGenerator.generate('kolon_Kolon'),
        name: 'Kolon 1',
        projectId: widget.projectId ?? '',
      );
      appState.addTopic(newTopic);
      topics = [newTopic];
    }
    _showLeftDateHourEntryDialog(context, clickedDate, appState, topics);
  }

  void _showLeftDateHourEntryDialog(
    BuildContext context,
    DateTime date,
    AppState appState,
    List<Topic> topics,
  ) {
    final String dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final allPlans = appState.topicPlans
        .where((p) => p.projectId == widget.projectId)
        .toList();

    String? selectedPlanId;
    final hoursController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        ...allPlans.map(
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
                            final rep = p.dayReports[dateKey];
                            hoursController.text =
                                rep != null && rep.hoursWorked > 0
                                ? rep.hoursWorked.toString()
                                : '';
                            noteController.text = rep?.note ?? '';
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
                  ],
                ),
              ),
              actions: [
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

                      appState.updateTopicPlan(p.copyWith(dayReports: reports));
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

  void _showAddTopicDialog(BuildContext context, AppState appState) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        final projectTopics = appState.topics
            .where((t) => t.projectId == widget.projectId)
            .toList();
        return AlertDialog(
          title: const Text('Yeni Kolon Ekle'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Kolon Adı'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final newTopicNum = projectTopics.length + 1;
                final newTopic = Topic(
                  id: IdGenerator.generate('kolon_Kolon'),
                  name: nameController.text.trim().isEmpty
                      ? 'Kolon $newTopicNum'
                      : nameController.text.trim(),
                  projectId: widget.projectId ?? '',
                );
                appState.addTopic(newTopic);
                Navigator.pop(context);
                setState(() {});
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final topics = appState.topics
        .where((t) => t.projectId == widget.projectId)
        .toList();

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Proje Planı'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_box),
                  onPressed: () => _showAddTopicDialog(context, appState),
                ),
              ],
            )
          : null,
      floatingActionButton: widget.showAppBar
          ? null
          : FloatingActionButton(
              mini: true,
              child: const Icon(Icons.add),
              onPressed: () => _showAddTopicDialog(context, appState),
            ),
      body: topics.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Henüz kolon eklenmemiş.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Kolon Ekle'),
                    onPressed: () => _showAddTopicDialog(context, appState),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  height: 50,
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      Container(
                        width: _dateColWidth,
                        alignment: Alignment.center,
                        child: const Text(
                          'Tarih',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _headerHorizontalController,
                          scrollDirection: Axis.horizontal,
                          itemCount: topics.length,
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
                                topics[index].name,
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
                            Expanded(
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: topics.length,
                                itemBuilder: (context, tIndex) {
                                  final topic = topics[tIndex];
                                  final topicPlans = appState.topicPlans
                                      .where((p) => p.topicId == topic.id)
                                      .toList();

                                  String cellText = '';
                                  Color cellColor = Colors.transparent;

                                  for (var plan in topicPlans) {
                                    if (plan.dayReports.containsKey(dayKey)) {
                                      final rep = plan.dayReports[dayKey]!;
                                      if (rep.hoursWorked > 0) {
                                        cellText =
                                            '${plan.title}\n(${rep.hoursWorked} sa)';
                                        cellColor = Color(
                                          plan.colorValue,
                                        ).withValues(alpha: 0.2);
                                      }
                                    }
                                  }

                                  return Container(
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
