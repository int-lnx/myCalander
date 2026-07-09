class DayNote {
  final String id;
  final DateTime date;
  final String note;
  final int? rating;
  final String? emoji;

  DayNote({
    required this.id,
    required this.date,
    required this.note,
    this.rating,
    this.emoji,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'note': note,
      'rating': rating,
      'emoji': emoji,
    };
  }

  factory DayNote.fromJson(Map<String, dynamic> json) {
    return DayNote(
      id: json['id'] ?? '',
      date: DateTime.parse(json['date']),
      note: json['note'] ?? '',
      rating: json['rating'] as int?,
      emoji: json['emoji'] as String?,
    );
  }

  DayNote copyWith({
    String? id,
    DateTime? date,
    String? note,
    int? rating,
    String? emoji,
    bool clearRating = false,
    bool clearEmoji = false,
  }) {
    return DayNote(
      id: id ?? this.id,
      date: date ?? this.date,
      note: note ?? this.note,
      rating: clearRating ? null : (rating ?? this.rating),
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
    );
  }
}
