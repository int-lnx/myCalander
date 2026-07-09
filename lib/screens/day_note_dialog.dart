import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/day_note.dart';
import '../models/project.dart';

class DayNoteDialog extends StatefulWidget {
  final AppState appState;
  final DateTime date;
  final bool editMode; // true → düzenleme, false → okuma

  const DayNoteDialog({
    super.key,
    required this.appState,
    required this.date,
    this.editMode = false,
  });

  /// Not varsa önce okuma sayfası, yoksa direkt düzenleme aç.
  static void show(BuildContext context, AppState appState, DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final notes = appState.dayNotes;
    final idx = notes.indexWhere(
      (n) =>
          n.date.year == normalizedDate.year &&
          n.date.month == normalizedDate.month &&
          n.date.day == normalizedDate.day,
    );
    final hasNote = idx != -1 &&
        (notes[idx].note.trim().isNotEmpty ||
            notes[idx].rating != null ||
            notes[idx].emoji != null);

    showDialog(
      context: context,
      builder: (context) => DayNoteDialog(
        appState: appState,
        date: normalizedDate,
        editMode: !hasNote, // not yoksa direkt düzenleme
      ),
    );
  }

  /// Sadece düzenleme modunda aç (FAB veya menüden).
  static void showEdit(BuildContext context, AppState appState, DateTime date) {
    showDialog(
      context: context,
      builder: (context) => DayNoteDialog(
        appState: appState,
        date: date,
        editMode: true,
      ),
    );
  }

  @override
  State<DayNoteDialog> createState() => _DayNoteDialogState();
}

class _DayNoteDialogState extends State<DayNoteDialog> {
  late TextEditingController _controller;
  late DateTime _normalizedDate;
  DayNote? _existingNote;
  late bool _isEditMode;
  int? _rating;
  String? _emoji;

  @override
  void initState() {
    super.initState();
    _normalizedDate = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    );
    _isEditMode = widget.editMode;

    final notes = widget.appState.dayNotes;
    final idx = notes.indexWhere(
      (n) =>
          n.date.year == _normalizedDate.year &&
          n.date.month == _normalizedDate.month &&
          n.date.day == _normalizedDate.day,
    );

    _existingNote = idx != -1 ? notes[idx] : null;
    _controller = TextEditingController(text: _existingNote?.note ?? '');
    _rating = _existingNote?.rating;
    _emoji = _existingNote?.emoji;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _dateStr =>
      '${_normalizedDate.day}.${_normalizedDate.month}.${_normalizedDate.year}';

  // ─── Okuma görünümü ───────────────────────────────────────────────────────
  Widget _buildReadView() {
    final isDark = widget.appState.isDarkMode;

    // Filter project evaluations for this day
    final projectEvals = widget.appState.evaluations.where((e) =>
        e.sessionDate.year == _normalizedDate.year &&
        e.sessionDate.month == _normalizedDate.month &&
        e.sessionDate.day == _normalizedDate.day &&
        e.note != null &&
        e.note!.trim().isNotEmpty
    ).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.note_alt, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_dateStr Günlük Notu',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji and Rating Display
              if ((_emoji != null && _emoji!.isNotEmpty) || (_rating != null && _rating! > 0)) ...[
                Row(
                  children: [
                    if (_emoji != null && _emoji!.isNotEmpty) ...[
                      Text(
                        _emoji!,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_rating != null && _rating! > 0) ...[
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < _rating! ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 20,
                          );
                        }),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($_rating/5)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
              ],

              // Daily Note Text
              if (_existingNote?.note != null && _existingNote!.note.trim().isNotEmpty) ...[
                Text(
                  _existingNote!.note,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: 16),
              ] else if (_emoji == null && _rating == null) ...[
                const Text(
                  'Bugün için yazılmış bir not bulunmuyor.',
                  style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),
              ],

              // Project Evaluation Notes Module (Diğer Kayıtlar ve Proje Notları)
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.rocket_launch, size: 18, color: Colors.purple),
                  const SizedBox(width: 8),
                  Text(
                    'Bugünün Proje Notları',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (projectEvals.isEmpty)
                Text(
                  'Bugün için girilmiş proje notu bulunmuyor.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                )
              else
                ...projectEvals.map((eval) {
                  final project = widget.appState.projects.firstWhere(
                    (p) => p.id == eval.projectId,
                    orElse: () => const Project(
                      id: '', title: 'Bilinmeyen Proje', colorValue: 0xFF9E9E9E,
                      evaluationType: 'PERCENTAGE', targetValue: 100.0,
                    ),
                  );
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50.withValues(alpha: isDark ? 0.1 : 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.purple.shade900 : Colors.purple.shade100, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(project.colorValue),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                project.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              eval.isSkipped
                                  ? 'Pas'
                                  : (project.evaluationType == 'PERCENTAGE'
                                      ? '%${eval.score.toStringAsFixed(0)}'
                                      : '${eval.score.toStringAsFixed(0)} Puan'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: eval.isSkipped ? Colors.red : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        if (eval.durationHours > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Süre: ${eval.durationHours.toStringAsFixed(1)} saat',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          eval.note ?? '',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  );
                }).toList(),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                final backupText = _existingNote?.note ?? '';
                final backupRating = _existingNote?.rating;
                final backupEmoji = _existingNote?.emoji;
                widget.appState.addOrUpdateDayNote(_normalizedDate, '');
                Navigator.pop(context);

                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Not silindi'),
                    duration: const Duration(seconds: 10),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    showCloseIcon: true,
                    closeIconColor: Colors.white70,
                    action: SnackBarAction(
                      label: 'Geri Al',
                      textColor: Colors.amber,
                      onPressed: () =>
                          widget.appState.addOrUpdateDayNote(
                            _normalizedDate,
                            backupText,
                            rating: backupRating,
                            emoji: backupEmoji,
                          ),
                    ),
                  ),
                );
              },
              child: const Text('Sil', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.amber.shade100,
                foregroundColor: Colors.amber.shade900,
              ),
              onPressed: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => DayNoteDialog(
                    appState: widget.appState,
                    date: _normalizedDate,
                    editMode: true,
                  ),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 14),
                  SizedBox(width: 4),
                  Text('Düzenle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Düzenleme görünümü ───────────────────────────────────────────────────
  Widget _buildEditView() {
    final hasNote = _existingNote != null &&
        (_existingNote!.note.trim().isNotEmpty ||
            _existingNote!.rating != null ||
            _existingNote!.emoji != null);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_dateStr Günlük Notu',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji Selector
              const Text(
                'Bugünün Duygusu / Emoji:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...['😊', '😐', '😢', '😡', '🎉', '💪', '🔥', '😴', '🥳', '😭', '❤️', '🌟', '🎯', '💼', '🏠', '✈️'].map((emo) {
                    final isSelected = _emoji == emo;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _emoji = isSelected ? null : emo;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.amber.shade100 : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.amber : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          emo,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // Rating Selector (1-5 stars)
              const Text(
                'Günün Puanı:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ...List.generate(5, (index) {
                    final starVal = index + 1;
                    final isSelected = _rating != null && _rating! >= starVal;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _rating = (_rating == starVal) ? null : starVal;
                        });
                      },
                      child: Icon(
                        isSelected ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                    );
                  }),
                  if (_rating != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _rating = null;
                        });
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Note Text
              const Text(
                'Günlük Not:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Bugün için notlarınızı buraya yazın...',
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.amber, width: 2.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (hasNote) ...[
              TextButton(
                onPressed: () {
                  final backupText = _existingNote?.note ?? '';
                  final backupRating = _existingNote?.rating;
                  final backupEmoji = _existingNote?.emoji;
                  widget.appState.addOrUpdateDayNote(_normalizedDate, '');
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Not silindi'),
                      duration: const Duration(seconds: 10),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      showCloseIcon: true,
                      closeIconColor: Colors.white70,
                      action: SnackBarAction(
                        label: 'Geri Al',
                        textColor: Colors.amber,
                        onPressed: () => widget.appState.addOrUpdateDayNote(
                          _normalizedDate,
                          backupText,
                          rating: backupRating,
                          emoji: backupEmoji,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Sil', style: TextStyle(color: Colors.red)),
              ),
              const Spacer(),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                widget.appState.addOrUpdateDayNote(
                  _normalizedDate,
                  _controller.text,
                  rating: _rating,
                  emoji: _emoji,
                );
                Navigator.pop(context);

                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Not kaydedildi'),
                    duration: const Duration(seconds: 4),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    showCloseIcon: true,
                    closeIconColor: Colors.white70,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black87,
                elevation: 0,
              ),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isEditMode ? _buildEditView() : _buildReadView();
  }
}
