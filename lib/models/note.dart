class Note {
  final String id;
  final String title;
  final String content;
  final int colorValue; // Keep card color
  final bool isPinned;
  final List<String> tags; // e.g. ["2", "gelişim"]
  final DateTime createdAt;

  Note({
    required this.id,
    this.title = '',
    this.content = '',
    this.colorValue = 0xFFFFFFFF,
    this.isPinned = false,
    this.tags = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Note copyWith({
    String? id,
    String? title,
    String? content,
    int? colorValue,
    bool? isPinned,
    List<String>? tags,
    DateTime? createdAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      colorValue: colorValue ?? this.colorValue,
      isPinned: isPinned ?? this.isPinned,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'colorValue': colorValue,
      'isPinned': isPinned,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? 0xFFFFFFFF,
      isPinned: json['isPinned'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
