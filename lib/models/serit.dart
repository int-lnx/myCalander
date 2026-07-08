class Serit {
  final String id;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final int colorValue;
  final bool isCompleted;
  final bool isVisible;
  final String? parentSeritId;

  const Serit({
    required this.id,
    required this.title,
    this.description = '',
    required this.startDate,
    required this.endDate,
    required this.colorValue,
    this.isCompleted = false,
    this.isVisible = true,
    this.parentSeritId,
  });

  Serit copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    int? colorValue,
    bool? isCompleted,
    bool? isVisible,
    String? parentSeritId,
    bool clearParent = false,
  }) {
    return Serit(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      colorValue: colorValue ?? this.colorValue,
      isCompleted: isCompleted ?? this.isCompleted,
      isVisible: isVisible ?? this.isVisible,
      parentSeritId: clearParent ? null : (parentSeritId ?? this.parentSeritId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'colorValue': colorValue,
      'isCompleted': isCompleted,
      'isVisible': isVisible,
      'parentSeritId': parentSeritId,
    };
  }

  factory Serit.fromJson(Map<String, dynamic> json) {
    return Serit(
      id: json['id'] as String? ?? '',
      title: (json['title'] ?? json['name'] ?? '') as String,
      description: json['description'] as String? ?? '',
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
      isCompleted: json['isCompleted'] as bool? ?? false,
      isVisible: json['isVisible'] as bool? ?? true,
      parentSeritId: json['parentSeritId'] as String?,
    );
  }
}
