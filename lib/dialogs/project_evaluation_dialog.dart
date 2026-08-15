import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../providers/app_state.dart';
import '../utils/id_generator.dart';

void showProjectEvaluationDialog({
  required BuildContext context,
  required Project project,
  required DateTime date,
  VoidCallback? onSaved,
}) {
  final appState = Provider.of<AppState>(context, listen: false);
  final normalizedDate = DateTime(date.year, date.month, date.day);
  
  final existingEval = appState.evaluations.firstWhere(
    (e) => e.projectId == project.id && 
           e.sessionDate.year == normalizedDate.year &&
           e.sessionDate.month == normalizedDate.month &&
           e.sessionDate.day == normalizedDate.day,
    orElse: () => ProjectEvaluation(
      id: '',
      projectId: project.id,
      sessionDate: normalizedDate,
      score: 0,
      isSkipped: false,
      durationHours: 0,
    ),
  );

  final percentCtrl = TextEditingController(
    text: existingEval.id.isNotEmpty && !existingEval.isSkipped
        ? (existingEval.performancePercent ?? existingEval.score).toStringAsFixed(0)
        : (project.defaultPercentage?.toStringAsFixed(0) ?? ''),
  );
  final numericCtrl = TextEditingController(
    text: existingEval.id.isNotEmpty && !existingEval.isSkipped
        ? existingEval.score.toStringAsFixed(existingEval.score % 1 == 0 ? 0 : 1)
        : (project.defaultNumeric?.toString() ?? ''),
  );
  final hoursCtrl = TextEditingController(
    text: existingEval.id.isNotEmpty && !existingEval.isSkipped
        ? existingEval.durationHours.toInt().toString()
        : (project.defaultDuration?.toInt().toString() ?? ''),
  );
  final minutesCtrl = TextEditingController(
    text: existingEval.id.isNotEmpty && !existingEval.isSkipped
        ? ((existingEval.durationHours - existingEval.durationHours.toInt()) * 60).round().toString()
        : (project.defaultDuration != null
            ? ((project.defaultDuration! - project.defaultDuration!.toInt()) * 60).round().toString()
            : ''),
  );
  final noteCtrl = TextEditingController(text: existingEval.note ?? '');
  bool isSkipped = existingEval.id.isNotEmpty ? existingEval.isSkipped : false;
  final List<String> checkedSteps = List<String>.from(existingEval.checkedSteps);

  showDialog(
    context: context,
    builder: (context) {
      DateTime selectedDate = normalizedDate;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('${project.title} Değerlendirmesi'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = DateTime(picked.year, picked.month, picked.day);
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_month, size: 16, color: Colors.blue),
                          const SizedBox(width: 6),
                          Text(
                            "${selectedDate.day}/${selectedDate.month}/${selectedDate.year} tarihli oturum",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Bugünü Boş Geç (Pas)'),
                    value: isSkipped,
                    onChanged: (v) {
                      setState(() => isSkipped = v);
                    },
                  ),
                  if (!isSkipped) ...[
                    if (project.checkSteps.isNotEmpty) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Kontrol Adımları (Checklist)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...project.checkSteps.map((step) {
                        final isChecked = checkedSteps.contains(step.title);
                        
                        // Calculate weight dynamically
                        final explicitSum = project.checkSteps
                            .where((s) => s.weight != null)
                            .map((s) => s.weight!)
                            .fold(0.0, (a, b) => a + b);
                        final implicitCount = project.checkSteps.where((s) => s.weight == null).length;
                        double weight = 0.0;
                        if (step.weight != null) {
                          weight = step.weight!;
                        } else if (implicitCount > 0) {
                          final remaining = 100.0 - explicitSum;
                          weight = remaining > 0 ? remaining / implicitCount : 100.0 / project.checkSteps.length;
                        } else {
                          weight = 100.0 / project.checkSteps.length;
                        }

                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(step.title, style: const TextStyle(fontSize: 12)),
                          subtitle: Text('Ağırlık: %${weight.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10)),
                          value: isChecked,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                checkedSteps.add(step.title);
                              } else {
                                checkedSteps.remove(step.title);
                              }
                              
                              // Recalculate percentCtrl automatically
                              double totalPct = 0.0;
                              for (var s in project.checkSteps) {
                                if (checkedSteps.contains(s.title)) {
                                  double w = 0.0;
                                  if (s.weight != null) {
                                    w = s.weight!;
                                  } else if (implicitCount > 0) {
                                    final rem = 100.0 - explicitSum;
                                    w = rem > 0 ? rem / implicitCount : 100.0 / project.checkSteps.length;
                                  } else {
                                    w = 100.0 / project.checkSteps.length;
                                  }
                                  totalPct += w;
                                }
                              }
                              percentCtrl.text = totalPct.toStringAsFixed(0);
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      }),
                      const Divider(),
                    ],
                    if (project.trackPercentage) ...[
                      TextField(
                        controller: percentCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Başarı Yüzdesi (%)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (project.trackNumeric) ...[
                      TextField(
                        controller: numericCtrl,
                        decoration: InputDecoration(
                          labelText: 'Elde Edilen Sayı (Hedef: ${project.targetValue})',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (project.trackDuration) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: hoursCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Saat',
                                suffixText: 'saat',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: minutesCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Dakika',
                                suffixText: 'dk',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                  if (project.trackNote) ...[
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Not Ekle',
                        hintText: 'Oturumla ilgili notlar yazın...',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (existingEval.id.isNotEmpty)
                TextButton(
                  onPressed: () {
                    appState.deleteEvaluation(project.id, normalizedDate);
                    Navigator.pop(context);
                    if (onSaved != null) onSaved();
                  },
                  child: const Text(
                    'Sil',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  double score = 0.0;
                  double? pctVal;

                  if (!isSkipped) {
                    if (project.trackNumeric) {
                      score = double.tryParse(numericCtrl.text) ?? 0.0;
                    }
                    if (project.trackPercentage) {
                      final pVal = double.tryParse(percentCtrl.text) ?? 0.0;
                      pctVal = pVal;
                      if (!project.trackNumeric) {
                        score = pVal;
                      }
                    }
                  }

                  int hrs = int.tryParse(hoursCtrl.text) ?? 0;
                  int mins = int.tryParse(minutesCtrl.text) ?? 0;
                  double duration = hrs + (mins / 60.0);
                  if (duration < 0.0) duration = 0.0;

                  // Calculate skip count if skipped
                  double finalScore = score;
                  if (isSkipped) {
                    int skipCount = 1;
                    DateTime checkDate = normalizedDate.subtract(const Duration(days: 1));
                    while (true) {
                      ProjectEvaluation? checkEv;
                      for (final e in appState.evaluations) {
                        if (e.projectId == project.id &&
                            e.sessionDate.year == checkDate.year &&
                            e.sessionDate.month == checkDate.month &&
                            e.sessionDate.day == checkDate.day) {
                          checkEv = e;
                          break;
                        }
                      }
                      if (checkEv != null && checkEv.isSkipped) {
                        skipCount++;
                        checkDate = checkDate.subtract(const Duration(days: 1));
                      } else {
                        break;
                      }
                    }
                    finalScore = skipCount.toDouble();
                  }

                  // If date changed, delete the old evaluation
                  if (existingEval.id.isNotEmpty &&
                      (selectedDate.year != normalizedDate.year ||
                       selectedDate.month != normalizedDate.month ||
                       selectedDate.day != normalizedDate.day)) {
                    appState.deleteEvaluation(project.id, normalizedDate);
                  }

                  final eval = ProjectEvaluation(
                    id: existingEval.id.isNotEmpty &&
                        (selectedDate.year == normalizedDate.year &&
                         selectedDate.month == normalizedDate.month &&
                         selectedDate.day == normalizedDate.day)
                        ? existingEval.id
                        : IdGenerator.generate(
                            "degerlendirme_${project.title}",
                            date: selectedDate,
                          ),
                    projectId: project.id,
                    sessionDate: selectedDate,
                    score: isSkipped ? finalScore : score,
                    isSkipped: isSkipped,
                    durationHours: (isSkipped || !project.trackDuration) ? 0.0 : duration,
                    note: (project.trackNote && noteCtrl.text.trim().isNotEmpty) ? noteCtrl.text.trim() : null,
                    performancePercent: pctVal,
                    checkedSteps: checkedSteps,
                  );
                  
                  appState.addOrUpdateEvaluation(eval);
                  Navigator.pop(context);
                  if (onSaved != null) onSaved();
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
