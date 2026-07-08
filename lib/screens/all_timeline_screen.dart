import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/serit.dart';
import '../utils/id_generator.dart';

class AllTimelineScreen extends StatelessWidget {
  const AllTimelineScreen({super.key});

  static void showSeritFormDialog(BuildContext context, AppState appState, {Serit? existingSerit}) {
    final titleCtrl = TextEditingController(text: existingSerit?.title ?? '');
    DateTime start = existingSerit?.startDate ?? DateTime.now();
    DateTime end = existingSerit?.endDate ?? DateTime.now().add(const Duration(days: 7));
    int selectedColor = existingSerit?.colorValue ?? 0xFF2196F3;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(existingSerit == null ? 'Yeni Şerit Ekle' : 'Şerit Düzenle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Şerit Başlığı'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            child: Text('Başla: ${start.day}/${start.month}/${start.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: start,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => start = picked);
                              }
                            },
                          ),
                        ),
                        Expanded(
                          child: TextButton(
                            child: Text('Bitir: ${end.day}/${end.month}/${end.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: end,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => end = picked);
                              }
                            },
                          ),
                        ),
                      ],
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
                    final title = titleCtrl.text.trim();
                    if (title.isNotEmpty) {
                      final newSerit = Serit(
                        id: existingSerit?.id ?? IdGenerator.generate(title),
                        title: title,
                        startDate: start,
                        endDate: end,
                        colorValue: selectedColor,
                        isCompleted: existingSerit?.isCompleted ?? false,
                        isVisible: existingSerit?.isVisible ?? true,
                        parentSeritId: existingSerit?.parentSeritId,
                      );
                      if (existingSerit == null) {
                        appState.addSerit(newSerit);
                      } else {
                        appState.updateSerit(newSerit);
                      }
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Ekle'),
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
    final serits = appState.serits;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Şeritlerim'),
      ),
      body: serits.isEmpty
          ? const Center(child: Text('Henüz bir şerit eklenmemiş.'))
          : ListView.builder(
              itemCount: serits.length,
              itemBuilder: (context, index) {
                final serit = serits[index];
                return ListTile(
                  title: Text(serit.title),
                  subtitle: Text(
                    '${serit.startDate.day}/${serit.startDate.month}/${serit.startDate.year} - ${serit.endDate.day}/${serit.endDate.month}/${serit.endDate.year}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => showSeritFormDialog(context, appState, existingSerit: serit),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showSeritFormDialog(context, appState),
        child: const Icon(Icons.add),
      ),
    );
  }
}
