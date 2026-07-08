class DayNote {
  final String id;
  final DateTime date;
  final String note;

  DayNote({
    required this.id,
    required this.date,
    required this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'note': note,
    };
  }

  factory DayNote.fromJson(Map<String, dynamic> json) {
    return DayNote(
      id: json['id'] ?? '',
      date: DateTime.parse(json['date']),
      note: json['note'] ?? '',
    );
  }
}
