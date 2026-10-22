class DayNoteEntry {
  final String id;
  final String text;
  final List<String> tags;

  DayNoteEntry({
    required this.id,
    required this.text,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'tags': tags,
    };
  }

  factory DayNoteEntry.fromJson(Map<String, dynamic> json) {
    return DayNoteEntry(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? (json['note'] as String? ?? ''),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  DayNoteEntry copyWith({
    String? id,
    String? text,
    List<String>? tags,
  }) {
    return DayNoteEntry(
      id: id ?? this.id,
      text: text ?? this.text,
      tags: tags ?? this.tags,
    );
  }
}

class DayNote {
  final String id;
  final DateTime date;
  final String note;
  final List<DayNoteEntry> entries;
  final int? rating;
  final String? emoji;

  DayNote({
    required this.id,
    required this.date,
    this.note = '',
    List<DayNoteEntry>? entries,
    this.rating,
    this.emoji,
  }) : entries = entries ?? (note.trim().isNotEmpty ? [DayNoteEntry(id: 'entry_0', text: note)] : const []);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'note': note.isNotEmpty ? note : entries.map((e) => e.text).where((t) => t.trim().isNotEmpty).join('\n\n'),
      'entries': entries.map((e) => e.toJson()).toList(),
      'rating': rating,
      'emoji': emoji,
    };
  }

  factory DayNote.fromJson(Map<String, dynamic> json) {
    List<DayNoteEntry> parsedEntries = [];
    if (json['entries'] != null && json['entries'] is List) {
      parsedEntries = (json['entries'] as List)
          .whereType<Map>()
          .map((e) => DayNoteEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    final noteStr = json['note'] as String? ?? '';
    if (parsedEntries.isEmpty && noteStr.trim().isNotEmpty) {
      parsedEntries = [
        DayNoteEntry(
          id: 'entry_legacy',
          text: noteStr,
        ),
      ];
    }

    final computedNote = noteStr.isNotEmpty
        ? noteStr
        : parsedEntries.map((e) => e.text).where((t) => t.trim().isNotEmpty).join('\n\n');

    return DayNote(
      id: json['id'] ?? '',
      date: DateTime.parse(json['date']),
      note: computedNote,
      entries: parsedEntries,
      rating: json['rating'] as int?,
      emoji: json['emoji'] as String?,
    );
  }

  DayNote copyWith({
    String? id,
    DateTime? date,
    String? note,
    List<DayNoteEntry>? entries,
    int? rating,
    String? emoji,
    bool clearRating = false,
    bool clearEmoji = false,
  }) {
    final newEntries = entries ?? this.entries;
    return DayNote(
      id: id ?? this.id,
      date: date ?? this.date,
      note: note ?? (entries != null ? newEntries.map((e) => e.text).where((t) => t.trim().isNotEmpty).join('\n\n') : this.note),
      entries: newEntries,
      rating: clearRating ? null : (rating ?? this.rating),
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
    );
  }
}

