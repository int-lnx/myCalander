import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/topic_plan.dart';

class StepLogsScreen extends StatefulWidget {
  final String planId;
  const StepLogsScreen({super.key, required this.planId});

  @override
  State<StepLogsScreen> createState() => _StepLogsScreenState();
}

class _StepLogsScreenState extends State<StepLogsScreen> {
  final List<String> _monthNames = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  final List<String> _weekdayNames = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];

  String _formatDate(DateTime date) {
    return '${date.day} ${_monthNames[date.month - 1]} ${date.year}, ${_weekdayNames[date.weekday - 1]}';
  }

  void _showAddEditLogDialog(BuildContext context, AppState appState, TopicPlan plan, {DateTime? existingDate, PlanDayReport? existingReport}) {
    DateTime selectedDate = existingDate ?? DateTime.now();
    final hoursController = TextEditingController(
      text: existingReport != null && existingReport.hoursWorked > 0
          ? existingReport.hoursWorked.toString()
          : '',
    );
    final noteController = TextEditingController(text: existingReport?.note ?? '');
    bool isCompletedChecked = plan.status == 'Yapılanlar';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                existingReport == null ? 'Yeni Çalışma Kaydı' : 'Kayıt Düzenle',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (existingReport == null) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Tarih: ${selectedDate.day} ${_monthNames[selectedDate.month - 1]} ${selectedDate.year}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        trailing: const Icon(Icons.calendar_today, color: Colors.purple),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                      ),
                      const Divider(),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _formatDate(selectedDate),
                          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: hoursController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Çalışılan Saat',
                        prefixIcon: Icon(Icons.timer_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Not / Açıklama',
                        prefixIcon: Icon(Icons.note_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Bu adımı tamamlandı olarak işaretle',
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final hours = double.tryParse(hoursController.text) ?? 0.0;
                    final note = noteController.text.trim();
                    final String dateKey =
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

                    final Map<String, PlanDayReport> reports = Map.from(plan.dayReports);
                    reports[dateKey] = PlanDayReport(
                      hoursWorked: hours,
                      note: note,
                      offset: hours > 0 ? 0 : 1,
                    );

                    appState.updateTopicPlan(plan.copyWith(
                      status: isCompletedChecked ? 'Yapılanlar' : 'Yapılıyor',
                      endDate: isCompletedChecked ? selectedDate : plan.endDate,
                      dayReports: reports,
                    ));

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

  void _deleteLog(BuildContext context, AppState appState, TopicPlan plan, String dateKey) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydı Sil?'),
        content: const Text('Bu çalışma kaydını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final Map<String, PlanDayReport> reports = Map.from(plan.dayReports);
              reports.remove(dateKey);
              appState.updateTopicPlan(plan.copyWith(
                dayReports: reports,
              ));
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final TopicPlan plan;
    try {
      plan = appState.topicPlans.firstWhere((p) => p.id == widget.planId);
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kayıt Defteri')),
        body: const Center(child: Text('Hata: Adım bulunamadı.')),
      );
    }

    final sortedKeys = plan.dayReports.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Newest first

    // Filter to keys that have actual logs (either hours worked > 0 or a note entered)
    final logKeys = sortedKeys.where((key) {
      final rep = plan.dayReports[key]!;
      return rep.hoursWorked > 0 || rep.note.trim().isNotEmpty;
    }).toList();

    final totalWorkedHours = plan.dayReports.values.map((r) => r.hoursWorked).fold(0.0, (a, b) => a + b);
    final targetHours = plan.targetHours > 0 ? plan.targetHours : 1.0;
    final progress = (totalWorkedHours / targetHours).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text('${plan.title} - Log Defteri'),
        backgroundColor: Colors.purple.shade50,
      ),
      body: Column(
        children: [
          // Statistics Header Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade500, Colors.purple.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                if (plan.description.isNotEmpty)
                  Text(
                    plan.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tamamlanan / Hedef',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        Text(
                          '${totalWorkedHours.toStringAsFixed(1)} / ${plan.targetHours.toStringAsFixed(1)} saat',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '% ${(progress * 100).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),

          // Log List Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kayıt Geçmişi (${logKeys.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Log List
          Expanded(
            child: logKeys.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notes_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Henüz bu adıma ait çalışma kaydı bulunmuyor.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('İlk Kaydı Ekle'),
                          onPressed: () => _showAddEditLogDialog(context, appState, plan),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: logKeys.length,
                    itemBuilder: (context, index) {
                      final key = logKeys[index];
                      final rep = plan.dayReports[key]!;
                      final dateParts = key.split('-');
                      final date = DateTime(
                        int.parse(dateParts[0]),
                        int.parse(dateParts[1]),
                        int.parse(dateParts[2]),
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              // Date icon and circle
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Icon(Icons.calendar_today_outlined, color: Colors.purple.shade600, size: 20),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Log details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatDate(date),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${rep.hoursWorked} saat çalışıldı',
                                          style: TextStyle(
                                            color: Colors.grey.shade800,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (rep.note.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade200),
                                        ),
                                        child: Text(
                                          rep.note,
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Actions
                              Column(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                                    onPressed: () => _showAddEditLogDialog(
                                      context,
                                      appState,
                                      plan,
                                      existingDate: date,
                                      existingReport: rep,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    onPressed: () => _deleteLog(context, appState, plan, key),
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
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Yeni Kayıt Ekle'),
        onPressed: () => _showAddEditLogDialog(context, appState, plan),
      ),
    );
  }
}
