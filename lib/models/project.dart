import '../models/project_evaluation.dart';

class Project {
  final String id;
  final String title;
  final String description;
  final int colorValue;
  final String tag;
  final String? subTag;
  final String evaluationType; // 'PERCENTAGE' or 'NUMERIC'
  final double targetValue;
  final bool isArchived;
  final String status;
  final bool isNegativeGoal;
  final List<String> tags;

  const Project({
    required this.id,
    required this.title,
    this.description = '',
    required this.colorValue,
    this.tag = 'Genel',
    this.subTag,
    required this.evaluationType,
    required this.targetValue,
    this.isArchived = false,
    this.status = 'Aktif',
    this.isNegativeGoal = false,
    this.tags = const [],
  });

  double calculateSingleSuccessPercentage(double score) {
    if (evaluationType == 'PERCENTAGE') {
      return score.clamp(0.0, 100.0);
    } else {
      if (targetValue == 0) return 0.0;
      return ((score / targetValue) * 100).clamp(0.0, 100.0);
    }
  }

  double calculateSuccessPercentage(List<ProjectEvaluation> evaluations) {
    if (evaluations.isEmpty) return 0.0;
    
    double total = 0.0;
    int count = 0;
    for (var eval in evaluations) {
      if (eval.isSkipped) continue;
      total += calculateSingleSuccessPercentage(eval.score);
      count++;
    }
    
    if (count == 0) return 0.0;
    return (total / count).clamp(0.0, 100.0);
  }

  Project copyWith({
    String? id,
    String? title,
    String? description,
    int? colorValue,
    String? tag,
    String? subTag,
    String? evaluationType,
    double? targetValue,
    bool? isArchived,
    String? status,
    bool? isNegativeGoal,
    List<String>? tags,
    bool clearSubTag = false,
  }) {
    return Project(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
      tag: tag ?? this.tag,
      subTag: clearSubTag ? null : (subTag ?? this.subTag),
      evaluationType: evaluationType ?? this.evaluationType,
      targetValue: targetValue ?? this.targetValue,
      isArchived: isArchived ?? this.isArchived,
      status: status ?? this.status,
      isNegativeGoal: isNegativeGoal ?? this.isNegativeGoal,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'colorValue': colorValue,
      'tag': tag,
      'subTag': subTag,
      'evaluationType': evaluationType,
      'targetValue': targetValue,
      'isArchived': isArchived,
      'status': status,
      'isNegativeGoal': isNegativeGoal,
      'tags': tags,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    List<String> projectTags = [];
    if (json['tags'] is List) {
      projectTags = List<String>.from(json['tags']);
    }

    return Project(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
      tag: json['tag'] as String? ?? 'Genel',
      subTag: json['subTag'] as String?,
      evaluationType: json['evaluationType'] as String? ?? 'PERCENTAGE',
      targetValue: (json['targetValue'] as num?)?.toDouble() ?? 100.0,
      isArchived: json['isArchived'] as bool? ?? false,
      status: json['status'] as String? ?? 'Aktif',
      isNegativeGoal: json['isNegativeGoal'] as bool? ?? false,
      tags: projectTags,
    );
  }
}
