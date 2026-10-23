import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/day_note.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../dialogs/project_evaluation_dialog.dart';
import '../utils/emoji_data.dart';
import '../utils/id_generator.dart';

class _NoteItemController {
  final String id;
  final TextEditingController textController;
  final FocusNode focusNode;
  final List<String> tags;
  bool isAddingTag;
  final TextEditingController tagController;
  final FocusNode tagFocusNode;

  _NoteItemController({
    required this.id,
    required this.textController,
    required this.focusNode,
    List<String>? tags,
  })  : tags = tags ?? [],
        isAddingTag = false,
        tagController = TextEditingController(),
        tagFocusNode = FocusNode();

  void dispose() {
    textController.dispose();
    focusNode.dispose();
    tagController.dispose();
    tagFocusNode.dispose();
  }
}

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
    final hasNote =
        idx != -1 &&
        (notes[idx].note.trim().isNotEmpty ||
            notes[idx].entries.any((e) => e.text.trim().isNotEmpty || e.tags.isNotEmpty) ||
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
      builder: (context) =>
          DayNoteDialog(appState: appState, date: date, editMode: true),
    );
  }

  @override
  State<DayNoteDialog> createState() => _DayNoteDialogState();
}

class _DayNoteDialogState extends State<DayNoteDialog> {
  final List<_NoteItemController> _noteItems = [];
  late TextEditingController _newNoteInputController;
  late FocusNode _newNoteInputFocusNode;
  late TextEditingController _emojiController;
  late DateTime _normalizedDate;
  DayNote? _existingNote;
  late bool _isEditMode;
  int? _rating;
  String? _emoji;
  bool _showEmojiPicker = false;
  String _emojiSearchQuery = '';

  void _onEmojiChanged() {
    final text = _emojiController.text.trim();
    if (_emoji != (text.isNotEmpty ? text : null)) {
      setState(() {
        _emoji = text.isNotEmpty ? text : null;
      });
    }
  }

  void _onNewNoteInputChanged(String text) {
    if (text.isEmpty) return;
    final newController = TextEditingController(text: text);
    newController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    final newFocusNode = FocusNode();
    final newItem = _NoteItemController(
      id: IdGenerator.generate('entry'),
      textController: newController,
      focusNode: newFocusNode,
      tags: [],
    );

    setState(() {
      _noteItems.add(newItem);
      _newNoteInputController.text = '';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      newFocusNode.requestFocus();
    });
  }

  void _addNewEmptyNote() {
    final newController = TextEditingController();
    final newFocusNode = FocusNode();
    final newItem = _NoteItemController(
      id: IdGenerator.generate('entry'),
      textController: newController,
      focusNode: newFocusNode,
      tags: [],
    );

    setState(() {
      _noteItems.add(newItem);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      newFocusNode.requestFocus();
    });
  }

  void _commitTag(_NoteItemController item) {
    final val = item.tagController.text.trim().replaceAll('#', '');
    if (val.isNotEmpty && !item.tags.contains(val)) {
      item.tags.add(val);
    }
    item.tagController.clear();
    setState(() {
      item.isAddingTag = false;
    });
  }

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

    _noteItems.clear();
    if (_existingNote != null && _existingNote!.entries.isNotEmpty) {
      for (final entry in _existingNote!.entries) {
        _noteItems.add(_NoteItemController(
          id: entry.id,
          textController: TextEditingController(text: entry.text),
          focusNode: FocusNode(),
          tags: List<String>.from(entry.tags),
        ));
      }
    } else if (_existingNote != null && _existingNote!.note.trim().isNotEmpty) {
      _noteItems.add(_NoteItemController(
        id: 'entry_0',
        textController: TextEditingController(text: _existingNote!.note),
        focusNode: FocusNode(),
        tags: [],
      ));
    } else {
      _noteItems.add(_NoteItemController(
        id: 'entry_0',
        textController: TextEditingController(),
        focusNode: FocusNode(),
        tags: [],
      ));
    }

    _newNoteInputController = TextEditingController();
    _newNoteInputFocusNode = FocusNode();

    _rating = _existingNote?.rating;
    _emoji = _existingNote?.emoji;
    _emojiController = TextEditingController(text: _emoji ?? '');
    _emojiController.addListener(_onEmojiChanged);
  }

  @override
  void dispose() {
    _emojiController.removeListener(_onEmojiChanged);
    for (final item in _noteItems) {
      item.dispose();
    }
    _newNoteInputController.dispose();
    _newNoteInputFocusNode.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  String get _dateStr =>
      '${_normalizedDate.day}.${_normalizedDate.month}.${_normalizedDate.year}';

  // ─── Okuma görünümü ───────────────────────────────────────────────────────
  Widget _buildReadView() {
    final isDark = widget.appState.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // Filter project evaluations for this day
    final projectEvals = widget.appState.evaluations
        .where(
          (e) =>
              e.sessionDate.year == _normalizedDate.year &&
              e.sessionDate.month == _normalizedDate.month &&
              e.sessionDate.day == _normalizedDate.day,
        )
        .toList();

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 6.0 : 24.0,
        vertical: isMobile ? 12.0 : 24.0,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8.0 : 20.0,
        vertical: 12.0,
      ),
      title: Row(
        children: [
          const Icon(Icons.note_alt, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_dateStr Günlük Notu',
              style: TextStyle(fontSize: isMobile ? 15 : 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isMobile ? screenWidth : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji and Rating Display
              if ((_emoji != null && _emoji!.isNotEmpty) ||
                  (_rating != null && _rating! > 0)) ...[
                Row(
                  children: [
                    if (_emoji != null && _emoji!.isNotEmpty) ...[
                      Text(_emoji!, style: const TextStyle(fontSize: 28)),
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

              // Daily Note Text / Entries
              if (_existingNote != null &&
                  (_existingNote!.entries.isNotEmpty ||
                      _existingNote!.note.trim().isNotEmpty)) ...[
                ...(_existingNote!.entries.isNotEmpty
                        ? _existingNote!.entries
                        : [DayNoteEntry(id: 'entry_0', text: _existingNote!.note)])
                    .asMap()
                    .entries
                    .map((mapEntry) {
                  final idx = mapEntry.key;
                  final entry = mapEntry.value;
                  final totalEntries = _existingNote!.entries.isNotEmpty
                      ? _existingNote!.entries.length
                      : 1;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF222222)
                          : Colors.amber.shade50.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.amber.shade200,
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (totalEntries > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.notes,
                                  size: 14,
                                  color: Colors.amber.shade800,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Not ${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.amber.shade300
                                        : Colors.amber.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (entry.text.trim().isNotEmpty)
                          SelectableText(
                            entry.text,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        if (entry.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: entry.tags.map((tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.amber.shade900.withValues(alpha: 0.3)
                                    : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.amber.shade700
                                      : Colors.amber.shade300,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.label_outline,
                                    size: 11,
                                    color: isDark
                                        ? Colors.amber.shade200
                                        : Colors.amber.shade900,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.amber.shade200
                                          : Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
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
                  const Icon(
                    Icons.rocket_launch,
                    size: 18,
                    color: Colors.purple,
                  ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                ...projectEvals.map((eval) {
                  final project = widget.appState.projects.firstWhere(
                    (p) => p.id == eval.projectId,
                    orElse: () => const Project(
                      id: '',
                      title: 'Bilinmeyen Proje',
                      colorValue: 0xFF9E9E9E,
                      evaluationType: 'PERCENTAGE',
                      targetValue: 100.0,
                    ),
                  );
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50.withValues(
                        alpha: isDark ? 0.1 : 0.3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? Colors.purple.shade900
                            : Colors.purple.shade100,
                        width: 0.5,
                      ),
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
                                  ? 'Pas ${widget.appState.getPasCount(project.id, eval.sessionDate)}'
                                  : (project.evaluationType == 'PERCENTAGE'
                                        ? '%${eval.score.toStringAsFixed(0)}'
                                        : '${eval.score.toStringAsFixed(0)} Puan'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: eval.isSkipped
                                    ? Colors.red
                                    : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        if (eval.durationHours > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Süre: ${eval.durationHours.toStringAsFixed(1)} saat',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          (eval.note != null && eval.note!.trim().isNotEmpty)
                              ? eval.note!
                              : (eval.isSkipped
                                  ? 'Herhangi bir not girilmedi (Pas).'
                                  : (project.evaluationType == 'PERCENTAGE'
                                      ? 'Değer: %${eval.score.toStringAsFixed(0)} (Not girilmedi)'
                                      : 'Değer: ${eval.score.toStringAsFixed(0)} Puan (Not girilmedi)')),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            fontStyle: (eval.note == null || eval.note!.trim().isEmpty) ? FontStyle.italic : FontStyle.normal,
                            color: (eval.note == null || eval.note!.trim().isEmpty) ? Colors.grey : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
                final backupEntries = _existingNote?.entries;
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
                        entries: backupEntries,
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
                  Text(
                    'Düzenle',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final hasNote =
        _existingNote != null &&
        (_existingNote!.note.trim().isNotEmpty ||
            _existingNote!.entries.any((e) => e.text.trim().isNotEmpty || e.tags.isNotEmpty) ||
            _existingNote!.rating != null ||
            _existingNote!.emoji != null);

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 6.0 : 24.0,
        vertical: isMobile ? 12.0 : 24.0,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8.0 : 20.0,
        vertical: 12.0,
      ),
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_dateStr Günlük Notu',
              style: TextStyle(fontSize: isMobile ? 15 : 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: isMobile ? screenWidth : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji Selector & Rating Selector
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji Selector (Left)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bugünün Duygusu:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: isMobile ? 95 : 120,
                        child: TextField(
                          controller: _emojiController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18),
                          enableInteractiveSelection: true,
                          decoration: InputDecoration(
                            hintText: 'Seç',
                            hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: InkWell(
                              onTap: () {
                                setState(() {
                                  _showEmojiPicker = !_showEmojiPicker;
                                });
                              },
                              child: Icon(
                                _showEmojiPicker
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _emoji = val.trim().isNotEmpty ? val.trim() : null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: isMobile ? 10 : 20),
                  // Rating Selector (Right) - FittedBox ensures it NEVER overflows
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Günün Puanı:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(5, (index) {
                                final starVal = index + 1;
                                final isSelected =
                                    _rating != null && _rating! >= starVal;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _rating = (_rating == starVal)
                                          ? null
                                          : starVal;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                    child: Icon(
                                      isSelected ? Icons.star : Icons.star_border,
                                      color: Colors.amber,
                                      size: isMobile ? 25 : 28,
                                    ),
                                  ),
                                );
                              }),
                              if (_rating != null) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _rating = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.clear,
                                      size: 14,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Collapsible Emoji Selector List
              if (_showEmojiPicker) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50.withValues(
                      alpha: widget.appState.isDarkMode ? 0.15 : 0.95,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.search, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Emoji veya anahtar kelime ara...',
                                  hintStyle: const TextStyle(fontSize: 12),
                                  isDense: true,
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 14),
                                onChanged: (val) {
                                  setState(() {
                                    _emojiSearchQuery = val;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Seçmek için dokunun:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: searchEmojis(_emojiSearchQuery).map((emoItem) {
                                final emo = emoItem.emoji;
                                final isSelected = _emoji == emo;
                                return Tooltip(
                                  message: emoItem.name,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _emoji = isSelected ? null : emo;
                                        _emojiController.text = _emoji ?? '';
                                        _showEmojiPicker = false;
                                        _emojiSearchQuery = '';
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.amber.shade100
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.amber
                                              : Colors.transparent,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        emo,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Daily Notes Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Günlük Notlar:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    '${_noteItems.length} Not',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Note Items with Text and Tag Area
              ..._noteItems.asMap().entries.map((mapEntry) {
                final index = mapEntry.key;
                final item = mapEntry.value;
                return _buildNoteItemWidget(index, item, widget.appState.isDarkMode, isMobile);
              }),

              // Ek Yazı Yazma Barı (Yeni Not Ekleme Barı)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 8),
                decoration: BoxDecoration(
                  color: widget.appState.isDarkMode
                      ? const Color(0xFF1E1E1E)
                      : Colors.amber.shade50.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                child: TextField(
                  controller: _newNoteInputController,
                  focusNode: _newNoteInputFocusNode,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.add_circle, color: Colors.amber, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, color: Colors.amber, size: 20),
                      tooltip: 'Not Ekle',
                      onPressed: () {
                        if (_newNoteInputController.text.isNotEmpty) {
                          _onNewNoteInputChanged(_newNoteInputController.text);
                        } else {
                          _addNewEmptyNote();
                        }
                      },
                    ),
                    hintText: 'Başka bir not eklemek için buraya yazın...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: widget.appState.isDarkMode ? Colors.white38 : Colors.grey.shade500,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 10 : 12),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty) {
                      _onNewNoteInputChanged(val);
                    }
                  },
                  onSubmitted: (val) {
                    if (val.isNotEmpty) {
                      _onNewNoteInputChanged(val);
                    } else {
                      _addNewEmptyNote();
                    }
                  },
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Proje Girdileri Bölümü
              _buildProjectsSection(widget.appState.isDarkMode, isMobile),
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
                  final backupEntries = _existingNote?.entries;
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
                          entries: backupEntries,
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
                final emojiText = _emojiController.text.trim();
                final validEntries = _noteItems
                    .where((item) =>
                        item.textController.text.trim().isNotEmpty ||
                        item.tags.isNotEmpty)
                    .map((item) => DayNoteEntry(
                          id: item.id,
                          text: item.textController.text.trim(),
                          tags: List<String>.from(item.tags),
                        ))
                    .toList();

                widget.appState.addOrUpdateDayNote(
                  _normalizedDate,
                  validEntries.map((e) => e.text).join('\n\n'),
                  entries: validEntries,
                  rating: _rating,
                  emoji: emojiText.isNotEmpty ? emojiText : null,
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

  Widget _buildNoteItemWidget(int index, _NoteItemController item, bool isDark, bool isMobile) {
    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 18,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _noteItems.length > 1 ? 'Not ${index + 1}' : 'Not',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
              if (_noteItems.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade400,
                  tooltip: 'Bu notu sil',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      item.dispose();
                      _noteItems.removeAt(index);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: item.textController,
            focusNode: item.focusNode,
            minLines: 3,
            maxLines: 10,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: index == 0
                  ? 'Bugün için notlarınızı buraya yazın...'
                  : 'Ek notunuzu buraya yazın...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
              isDense: true,
              contentPadding: EdgeInsets.all(isMobile ? 8 : 10),
              filled: true,
              fillColor: isDark ? const Color(0xFF282828) : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.amber, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildTagAreaForItem(item, isDark),
        ],
      ),
    );
  }

  Widget _buildProjectsSection(bool isDark, bool isMobile) {
    final activeProjects = widget.appState.projects
        .where((p) => !p.isArchived)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.rocket_launch,
              size: 18,
              color: Colors.purple,
            ),
            const SizedBox(width: 8),
            Text(
              'Günün Projeleri',
              style: TextStyle(
                fontSize: isMobile ? 13 : 14,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
            const Spacer(),
            Text(
              '${activeProjects.length} Proje',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Projelerinizi değerlendirmek veya saat/dk/not girmek için dokunun:',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),

        if (activeProjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Kayıtlı aktif proje bulunmuyor.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ),
          )
        else
          ...activeProjects.map((project) {
            ProjectEvaluation? eval;
            try {
              eval = widget.appState.evaluations.firstWhere(
                (e) =>
                    e.projectId == project.id &&
                    e.sessionDate.year == _normalizedDate.year &&
                    e.sessionDate.month == _normalizedDate.month &&
                    e.sessionDate.day == _normalizedDate.day,
              );
            } catch (_) {
              eval = null;
            }

            final hasEval = eval != null &&
                (eval.isSkipped ||
                    eval.score > 0 ||
                    eval.durationHours > 0 ||
                    (eval.note != null && eval.note!.trim().isNotEmpty) ||
                    eval.checkedSteps.isNotEmpty);

            String durationStr = '';
            if (eval != null && eval.durationHours > 0) {
              final h = eval.durationHours.toInt();
              final m = ((eval.durationHours - h) * 60).round();
              if (h > 0 && m > 0) {
                durationStr = '$h sa $m dk';
              } else if (h > 0) {
                durationStr = '$h saat';
              } else {
                durationStr = '$m dakika';
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: hasEval
                    ? (isDark
                        ? Colors.purple.shade900.withValues(alpha: 0.2)
                        : Colors.purple.shade50.withValues(alpha: 0.5))
                    : (isDark
                        ? const Color(0xFF222222)
                        : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasEval
                      ? (isDark ? Colors.purple.shade700 : Colors.purple.shade200)
                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                  width: hasEval ? 1.2 : 0.8,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  showProjectEvaluationDialog(
                    context: context,
                    project: project,
                    date: _normalizedDate,
                    onSaved: () {
                      setState(() {});
                    },
                  );
                },
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 10.0 : 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(project.colorValue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              project.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 13 : 14,
                              ),
                            ),
                          ),
                          if (hasEval && eval != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: eval.isSkipped
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                eval.isSkipped
                                    ? 'Pas'
                                    : (project.evaluationType == 'PERCENTAGE'
                                        ? '%${eval.score.toStringAsFixed(0)}'
                                        : '${eval.score.toStringAsFixed(0)} Puan'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: eval.isSkipped ? Colors.red : Colors.green.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit, size: 14, color: Colors.purple),
                          ] else ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Doldur',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.add_circle_outline, size: 15, color: Colors.purple.shade700),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Detaylar / Aktif Özellikler
                      if (hasEval && eval != null && !eval.isSkipped) ...[
                        Row(
                          children: [
                            if (eval.durationHours > 0) ...[
                              Icon(Icons.schedule, size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                durationStr,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              const SizedBox(width: 10),
                            ],
                            if (eval.checkedSteps.isNotEmpty) ...[
                              Icon(Icons.check_box_outlined, size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '${eval.checkedSteps.length}/${project.checkSteps.length} Adım',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ],
                        ),
                        if (eval.note != null && eval.note!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            eval.note!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ] else if (!hasEval) ...[
                        // Henüz doldurulmamışsa projenin aktif özellik etiketlerini göster
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (project.trackDuration)
                              _buildFeatureBadge('Saat / Dk', isDark),
                            if (project.trackPercentage)
                              _buildFeatureBadge('Yüzde', isDark),
                            if (project.trackNumeric)
                              _buildFeatureBadge('Sayısal Değer', isDark),
                            if (project.checkSteps.isNotEmpty)
                              _buildFeatureBadge('${project.checkSteps.length} Adım', isDark),
                            if (project.trackNote)
                              _buildFeatureBadge('Proje Notu', isDark),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFeatureBadge(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: isDark ? Colors.white60 : Colors.grey.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTagAreaForItem(_NoteItemController item, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...item.tags.asMap().entries.map((mapEntry) {
              final tagIdx = mapEntry.key;
              final tag = mapEntry.value;
              return Container(
                padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.amber.shade900.withValues(alpha: 0.3)
                      : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.amber.shade700 : Colors.amber.shade300,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          item.tags.removeAt(tagIdx);
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (item.isAddingTag) ...[
              Container(
                width: 140,
                height: 30,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.amber, width: 1.2),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Text(
                      '#',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: item.tagController,
                        focusNode: item.tagFocusNode,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Etiket...',
                          hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _commitTag(item),
                      ),
                    ),
                    InkWell(
                      onTap: () => _commitTag(item),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.check, size: 16, color: Colors.green),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          item.tagController.clear();
                          item.isAddingTag = false;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.close, size: 15, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    item.isAddingTag = true;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    item.tagFocusNode.requestFocus();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add,
                        size: 13,
                        color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Etiket Ekle',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
