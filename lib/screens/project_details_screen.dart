import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/topic.dart';
import '../models/topic_plan.dart';
import 'project_form_screen.dart';
import 'plan_screen.dart';
import 'plan_form_screen.dart';
import 'step_logs_screen.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final Project project;

  const ProjectDetailsScreen({super.key, required this.project});

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedGorevStatus = 'Yapılacak';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getRelativeTimeText(DateTime? date) {
    if (date == null) return 'Hiç çalışılmadı';
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) {
      final hours = diff.inHours % 24;
      return '${diff.inDays} gün $hours saat önce';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} saat önce';
    } else {
      return 'Yakın zamanda';
    }
  }

  Widget _buildGenelAnaliz(BuildContext context, AppState appState) {
    final evals = appState.evaluations.where((e) => e.projectId == widget.project.id).toList()
      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate)); // Newest first

    final lastEval = evals.isNotEmpty ? evals.first : null;
    final lastEvalDate = lastEval?.sessionDate;

    // Calculate stats
    double totalHours = 0.0;
    double verimliHours = 0.0;
    double sumPerformances = 0.0;
    int evalCount = evals.length;

    double thisWeekHours = 0.0;
    double thisWeekPerformance = 0.0;
    int thisWeekCount = 0;

    double thisMonthHours = 0.0;
    double thisMonthPerformance = 0.0;
    int thisMonthCount = 0;

    final now = DateTime.now();
    final oneWeekAgo = now.subtract(const Duration(days: 7));
    final oneMonthAgo = now.subtract(const Duration(days: 30));

    for (var ev in evals) {
      totalHours += ev.durationHours;
      verimliHours += ev.durationHours * (ev.score / 100.0);
      sumPerformances += ev.score;

      if (ev.sessionDate.isAfter(oneWeekAgo)) {
        thisWeekHours += ev.durationHours;
        thisWeekPerformance += ev.score;
        thisWeekCount++;
      }
      if (ev.sessionDate.isAfter(oneMonthAgo)) {
        thisMonthHours += ev.durationHours;
        thisMonthPerformance += ev.score;
        thisMonthCount++;
      }
    }

    final avgPerformance = evalCount > 0 ? sumPerformances / evalCount : 0.0;
    final avgWeekPerf = thisWeekCount > 0 ? thisWeekPerformance / thisWeekCount : 0.0;
    final avgMonthPerf = thisMonthCount > 0 ? thisMonthPerformance / thisMonthCount : 0.0;

    // Son 10 performans
    final last10 = evals.take(10).toList();
    final avgLast10Perf = last10.isNotEmpty
        ? last10.map((e) => e.score).reduce((a, b) => a + b) / last10.length
        : 0.0;

    // Çalışma Sıklığı
    double frequencyDays = 0.0;
    if (evals.length > 1) {
      final oldest = evals.last.sessionDate;
      final newest = evals.first.sessionDate;
      final diffDays = newest.difference(oldest).inDays;
      frequencyDays = diffDays / (evals.length - 1);
    }

    final isDark = appState.isDarkMode;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Description
        Text(
          widget.project.description.isNotEmpty ? widget.project.description : 'Açıklama belirtilmemiş.',
          style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87),
        ),
        const SizedBox(height: 4),
        Text(
          'Hedef: %${widget.project.targetValue.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
        ),
        const SizedBox(height: 16),

        // Proje Analizi Card
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Proje Analizi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                _buildAnalizRow('Son Çalışma:', _getRelativeTimeText(lastEvalDate)),
                _buildAnalizRow('Çalışma Sıklığı:', frequencyDays > 0 ? '${frequencyDays.toStringAsFixed(1)} günde bir' : 'Veri yetersiz'),
                _buildAnalizRow('Genel Performans (Ağırlıklı):', '%${avgPerformance.toStringAsFixed(1)}'),
                _buildAnalizRow('Bu Haftaki Verimli Çalışma:', '${thisWeekHours.toStringAsFixed(1)} sa (Perf: %${avgWeekPerf.toStringAsFixed(1)})'),
                _buildAnalizRow('Bu Ayki Verimli Çalışma:', '${thisMonthHours.toStringAsFixed(1)} sa (Perf: %${avgMonthPerf.toStringAsFixed(1)})'),
                _buildAnalizRow('Son 10 Kayıt Perf.:', '%${avgLast10Perf.toStringAsFixed(1)}'),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Toplam Çalışma: ${totalHours.toStringAsFixed(1)} sa (Net) | ${verimliHours.toStringAsFixed(1)} sa (Verimli)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Verimli Zaman Hedefleri Card
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Verimli Zaman Hedefleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.settings, size: 20),
                      onPressed: () {
                        // Settings placeholder
                      },
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Henüz verimli zaman hedefi eklenmemiş.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Hedef Ekle'),
                        onPressed: () {
                          // Add target
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Add Evaluation Button
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Tarih Seç ve Değerlendir'),
          onPressed: () => _showAddEvaluationDialog(context, appState),
        ),
        const SizedBox(height: 24),

        // Geçmiş Değerlendirmeler List
        const Text(
          'Geçmiş Değerlendirmeler',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const Divider(),
        if (evals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: Text('Henüz değerlendirme bulunmamaktadır.')),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: evals.length,
            itemBuilder: (context, index) {
              final ev = evals[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text('${ev.sessionDate.day}/${ev.sessionDate.month}/${ev.sessionDate.year}'),
                  subtitle: Text(
                    'Ort. Skor: %${ev.score.toStringAsFixed(1)} | Süre: ${ev.durationHours.toStringAsFixed(1)} sa | Not: ${ev.note ?? '-'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () {
                      appState.deleteEvaluation(ev.projectId, ev.sessionDate);
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showAddEvaluationDialog(BuildContext context, AppState appState) {
    DateTime selectedDate = DateTime.now();
    final scoreController = TextEditingController();
    final durationController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tarih Seç ve Değerlendir'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text('Seçilen Tarih: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                    ),
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
                      id: '${widget.project.id}_${selectedDate.millisecondsSinceEpoch}',
                      projectId: widget.project.id,
                      sessionDate: DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
                      score: score,
                      durationHours: duration,
                      note: note.isNotEmpty ? note : null,
                      isSkipped: false,
                    );
                    appState.addOrUpdateEvaluation(eval);
                    Navigator.pop(context);
                  },
                  child: const Text('Değerlendir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAnalizRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
        ],
      ),
    );
  }

  void _openPlanForm(BuildContext context, AppState appState, {TopicPlan? existingPlan}) async {
    var topics = appState.topics.where((t) => t.projectId == widget.project.id).toList();
    if (topics.isEmpty) {
      final newTopic = Topic(
        id: '${widget.project.id}_genel',
        projectId: widget.project.id,
        name: 'Genel',
      );
      appState.addTopic(newTopic);
      topics = [newTopic];
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlanFormScreen(
          topic: existingPlan != null
              ? (topics.firstWhere((t) => t.id == existingPlan.topicId, orElse: () => topics.first))
              : topics.first,
          plan: existingPlan,
          projectId: widget.project.id,
        ),
      ),
    );
  }

  Widget _buildGorevHavuzu(BuildContext context, AppState appState) {
    final plans = appState.topicPlans.where((p) => p.projectId == widget.project.id).toList();
    final filteredPlans = plans.where((p) {
      if (_selectedGorevStatus == 'Tamamlandı') return p.status == 'Yapılanlar';
      return p.status == _selectedGorevStatus;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and Add Step Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Görev Yönetimi & Havuzu',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Yeni Adım Ekle', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade50,
                  foregroundColor: Colors.purple,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _openPlanForm(context, appState),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Horizontal Pill Filters Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Yapılacak', 'Yapılıyor', 'Bekleyenler', 'Tamamlandı'].map((status) {
                final count = plans.where((p) {
                  if (status == 'Tamamlandı') return p.status == 'Yapılanlar';
                  return p.status == status;
                }).length;

                final isSelected = _selectedGorevStatus == status;

                return GestureDetector(
                  onTap: () => setState(() => _selectedGorevStatus = status),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.purple : (appState.isDarkMode ? Colors.grey.shade800 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          status,
                          style: TextStyle(
                            color: isSelected ? Colors.white : (appState.isDarkMode ? Colors.white70 : Colors.black87),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withOpacity(0.2) : (appState.isDarkMode ? Colors.black26 : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : (appState.isDarkMode ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Tasks List
          Expanded(
            child: filteredPlans.isEmpty
                ? const Center(child: Text('Bu sütunda adım bulunmuyor.'))
                : ListView.builder(
                    itemCount: filteredPlans.length,
                    itemBuilder: (context, idx) {
                      final plan = filteredPlans[idx];
                      final workedHours = plan.dayReports.values.map((r) => r.hoursWorked).fold(0.0, (a, b) => a + b);

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              // Reorder Handle
                              const Icon(Icons.reorder, color: Colors.grey, size: 20),
                              const SizedBox(width: 12),

                              // Content Info
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => StepLogsScreen(planId: plan.id),
                                      ),
                                    );
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Başlangıç: ${plan.startDate.day}/${plan.startDate.month}/${plan.startDate.year} (${plan.status == 'Yapılanlar' ? 'Tamamlandı' : plan.status})',
                                        style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Süre: ${workedHours.toStringAsFixed(1)} / ${plan.targetHours.toStringAsFixed(1)} sa',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Dropdown & Action Buttons
                              Row(
                                children: [
                                  // Status Dropdown
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: plan.status,
                                        icon: const Icon(Icons.arrow_drop_down, color: Colors.blue),
                                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                                        items: ['Yapılacak', 'Yapılıyor', 'Bekleyenler', 'Yapılanlar'].map((st) {
                                          return DropdownMenuItem(
                                            value: st,
                                            child: Text(st == 'Yapılanlar' ? 'Tamamlandı' : st),
                                          );
                                        }).toList(),
                                        onChanged: (newVal) {
                                           if (newVal != null) {
                                             DateTime completionDate = plan.endDate;
                                             if (newVal == 'Yapılanlar') {
                                               DateTime? maxDate;
                                               for (var key in plan.dayReports.keys) {
                                                 try {
                                                   final parsed = DateTime.parse(key);
                                                   if (maxDate == null || parsed.isAfter(maxDate)) {
                                                     maxDate = parsed;
                                                   }
                                                 } catch (_) {}
                                               }
                                               completionDate = maxDate ?? DateTime.now();
                                             }
                                             appState.updateTopicPlan(plan.copyWith(
                                               status: newVal,
                                               endDate: newVal == 'Yapılanlar' ? completionDate : plan.endDate,
                                             ));
                                           }
                                         },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Place in time plan button
                                  IconButton(
                                    icon: const Icon(Icons.calendar_today, color: Colors.blueGrey, size: 18),
                                    tooltip: 'Zaman Planına Yerleştir',
                                    onPressed: () {
                                      _tabController.animateTo(1);
                                    },
                                  ),

                                  // Edit Button
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                                    onPressed: () => _openPlanForm(context, appState, existingPlan: plan),
                                  ),

                                  // Delete Button
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Görevi Sil?'),
                                          content: const Text('Bu görevi silmek istediğinize emin misiniz?'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              onPressed: () {
                                                appState.deleteTopicPlan(plan.id);
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text('Sil', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtiketTakvimi(BuildContext context, AppState appState) {
    // Simply render calendar entries associated with this project
    final events = appState.events.where((e) => e.projectId == widget.project.id).toList();
    if (events.isEmpty) {
      return const Center(child: Text('Bu projeye ait etkinlik takvimi kaydı bulunamadı.'));
    }
    return ListView.builder(
      itemCount: events.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final ev = events[index];
        return ListTile(
          leading: const Icon(Icons.event, color: Colors.blue),
          title: Text(ev.title),
          subtitle: Text('${ev.from.day}/${ev.from.month} - ${ev.to.day}/${ev.to.month}'),
        );
      },
    );
  }

  Widget _buildEtiketler(BuildContext context, AppState appState) {
    final topics = appState.topics.where((t) => t.projectId == widget.project.id).toList();
    if (topics.isEmpty) {
      return const Center(child: Text('Kolon (Etiket) bulunmamaktadır.'));
    }
    return ListView.builder(
      itemCount: topics.length,
      itemBuilder: (context, idx) {
        final topic = topics[idx];
        return ListTile(
          leading: const Icon(Icons.label, color: Colors.purple),
          title: Text(topic.name),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
              appState.deleteTopic(topic.id);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.title),
        actions: [
          IconButton(
            icon: Icon(widget.project.isArchived ? Icons.unarchive : Icons.archive),
            tooltip: widget.project.isArchived ? 'Arşivden Çıkar' : 'Arşive Kaldır',
            onPressed: () {
              final updated = widget.project.copyWith(isArchived: !widget.project.isArchived);
              appState.updateProject(updated);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    widget.project.isArchived
                        ? 'Proje arşivden çıkarıldı.'
                        : 'Proje arşive kaldırıldı.',
                  ),
                ),
              );
              Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProjectFormScreen(existingProject: widget.project),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Projeyi Sil?'),
                  content: const Text('Bu projeyi sildiğinizde, projeye ait tüm kayıtlar ve planlar da silinecektir. Emin misiniz?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        appState.deleteProject(widget.project.id);
                        Navigator.pop(ctx); // Close dialog
                        Navigator.pop(context); // Close screen
                      },
                      child: const Text('Sil', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Genel Analiz'),
            Tab(icon: Icon(Icons.timeline), text: 'Zaman Planı'),
            Tab(icon: Icon(Icons.assignment), text: 'Görev Havuzu'),
            Tab(icon: Icon(Icons.calendar_month), text: 'Etiket Takvimi'),
            Tab(icon: Icon(Icons.label), text: 'Etiketler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGenelAnaliz(context, appState),
          PlanScreen(projectId: widget.project.id, showAppBar: false),
          _buildGorevHavuzu(context, appState),
          _buildEtiketTakvimi(context, appState),
          _buildEtiketler(context, appState),
        ],
      ),
    );
  }
}
