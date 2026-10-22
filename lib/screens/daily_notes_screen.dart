import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'day_note_dialog.dart';

class DailyNotesScreen extends StatelessWidget {
  const DailyNotesScreen({super.key});

  String _getTurkishDateFormat(DateTime date) {
    final months = [
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
      'Aralık'
    ];
    final days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${days[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isDark = appState.isDarkMode;

    // Filter to only get notes that have actual content (text, rating, or emoji)
    final dailyNotes = appState.dayNotes.where((note) {
      return note.note.trim().isNotEmpty ||
          note.entries.any((e) => e.text.trim().isNotEmpty || e.tags.isNotEmpty) ||
          (note.rating != null && note.rating! > 0) ||
          (note.emoji != null && note.emoji!.trim().isNotEmpty);
    }).toList();

    // Sort newest first
    dailyNotes.sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
      body: dailyNotes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    size: 64,
                    color: isDark ? Colors.white30 : Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz günlük not eklenmemiş.',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Takvimden bir güne tıklayarak not ekleyebilirsiniz.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: dailyNotes.length,
              itemBuilder: (context, index) {
                final note = dailyNotes[index];
                final hasEmoji = note.emoji != null && note.emoji!.trim().isNotEmpty;
                final hasRating = note.rating != null && note.rating! > 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      DayNoteDialog.show(context, appState, note.date);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Date display
                              Expanded(
                                child: Text(
                                  _getTurkishDateFormat(note.date),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (hasEmoji || hasRating) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (hasEmoji) ...[
                                  Text(
                                    note.emoji!,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (hasRating) ...[
                                  Row(
                                    children: List.generate(5, (starIdx) {
                                      return Icon(
                                        starIdx < note.rating!
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: Colors.amber,
                                        size: 16,
                                      );
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${note.rating}/5)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          // Note content
                          if (note.entries.isNotEmpty) ...[
                            const Divider(height: 16),
                            ...note.entries.asMap().entries.map((mapEntry) {
                              final idx = mapEntry.key;
                              final entry = mapEntry.value;
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: idx < note.entries.length - 1 ? 10.0 : 0.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (note.entries.length > 1)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Text(
                                          'Not ${idx + 1}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                                          ),
                                        ),
                                      ),
                                    if (entry.text.trim().isNotEmpty)
                                      Text(
                                        entry.text,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (entry.tags.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: entry.tags.map((tag) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.amber.shade900.withValues(alpha: 0.3)
                                                : Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isDark ? Colors.amber.shade700 : Colors.amber.shade300,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            '#$tag',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                                            ),
                                          ),
                                        )).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                          ] else if (note.note.trim().isNotEmpty) ...[
                            const Divider(height: 16),
                            Text(
                              note.note,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
