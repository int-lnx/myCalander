import 'tracking_value.dart';

class ProjectEvaluation {
  final String id;
  final String projectId;
  final DateTime sessionDate;
  final double score;
  final bool isSkipped;
  final double durationHours;
  final String? note;
  final String? stepId;
  final double? performancePercent;
  final bool isTimeless;
  final List<TrackingValue> trackingValues;

  const ProjectEvaluation({
    required this.id,
    required this.projectId,
    required this.sessionDate,
    required this.score,
    required this.isSkipped,
    required this.durationHours,
    this.note,
    this.stepId,
    this.performancePercent,
    this.isTimeless = false,
    this.trackingValues = const [],
  });

  ProjectEvaluation copyWith({
    String? id,
    String? projectId,
    DateTime? sessionDate,
    double? score,
    bool? isSkipped,
    double? durationHours,
    String? note,
    String? stepId,
    double? performancePercent,
    bool? isTimeless,
    List<TrackingValue>? trackingValues,
    bool clearNote = false,
    bool clearStepId = false,
    bool clearPerformancePercent = false,
  }) {
    return ProjectEvaluation(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      sessionDate: sessionDate ?? this.sessionDate,
      score: score ?? this.score,
      isSkipped: isSkipped ?? this.isSkipped,
      durationHours: durationHours ?? this.durationHours,
      note: clearNote ? null : (note ?? this.note),
      stepId: clearStepId ? null : (stepId ?? this.stepId),
      performancePercent: clearPerformancePercent ? null : (performancePercent ?? this.performancePercent),
      isTimeless: isTimeless ?? this.isTimeless,
      trackingValues: trackingValues ?? this.trackingValues,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'sessionDate': sessionDate.toIso8601String(),
      'score': score,
      'isSkipped': isSkipped,
      'durationHours': durationHours,
      'note': note,
      'stepId': stepId,
      'performancePercent': performancePercent,
      'isTimeless': isTimeless,
      'trackingValues': trackingValues.map((v) => v.toJson()).toList(),
    };
  }

  factory ProjectEvaluation.fromJson(Map<String, dynamic> json) {
    List<TrackingValue> tValues = [];
    final rawTValues = json['trackingValues'];
    if (rawTValues is List) {
      tValues = rawTValues
          .map((v) => TrackingValue.fromJson(v as Map<String, dynamic>))
          .toList();
    }

    return ProjectEvaluation(
      id: json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      sessionDate: DateTime.parse(json['sessionDate'] as String),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      isSkipped: json['isSkipped'] as bool? ?? false,
      durationHours: (json['durationHours'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String?,
      stepId: json['stepId'] as String?,
      performancePercent: (json['performancePercent'] as num?)?.toDouble(),
      isTimeless: json['isTimeless'] as bool? ?? false,
      trackingValues: tValues,
    );
  }
}
