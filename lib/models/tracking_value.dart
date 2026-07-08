class TrackingValue {
  final String id;
  final String projectId;
  final DateTime date;
  final double value;

  const TrackingValue({
    required this.id,
    required this.projectId,
    required this.date,
    required this.value,
  });

  TrackingValue copyWith({
    String? id,
    String? projectId,
    DateTime? date,
    double? value,
  }) {
    return TrackingValue(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      date: date ?? this.date,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'date': date.toIso8601String(),
      'value': value,
    };
  }

  factory TrackingValue.fromJson(Map<String, dynamic> json) {
    return TrackingValue(
      id: json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
