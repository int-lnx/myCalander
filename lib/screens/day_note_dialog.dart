import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/day_note.dart';

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
    final hasNote = idx != -1 && notes[idx].note.trim().isNotEmpty;

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
        width: 340,
        child: SingleChildScrollView(
          child: Text(
            _existingNote?.note ?? '',
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
        ),
      ),
      actions: [
        // Sil
        TextButton(
          onPressed: () {
            final backup = _existingNote?.note ?? '';
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
                      widget.appState.addOrUpdateDayNote(_normalizedDate, backup),
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
        // Düzenle → aynı dialog'u edit modda yeniden aç
        ElevatedButton.icon(
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Düzenle'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black87,
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
        ),
      ],
    );
  }

  // ─── Düzenleme görünümü ───────────────────────────────────────────────────
  Widget _buildEditView() {
    final hasNote = _existingNote != null && _existingNote!.note.trim().isNotEmpty;

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
        child: TextField(
          controller: _controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Bugün için notlarınızı buraya yazın...',
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.amber, width: 2.0),
            ),
          ),
        ),
      ),
      actions: [
        if (hasNote)
          TextButton(
            onPressed: () {
              final backup = _existingNote?.note ?? '';
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
                    onPressed: () => widget.appState
                        .addOrUpdateDayNote(_normalizedDate, backup),
                  ),
                ),
              );
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.appState.addOrUpdateDayNote(_normalizedDate, _controller.text);
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
          ),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isEditMode ? _buildEditView() : _buildReadView();
  }
}
