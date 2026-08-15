import 'project_evaluation.dart';

class ProjectStep {
  final String title;
  final double? weight;

  const ProjectStep({required this.title, this.weight});

  Map<String, dynamic> toJson() => {
    'title': title,
    'weight': weight,
  };

  factory ProjectStep.fromJson(Map<String, dynamic> json) => ProjectStep(
    title: json['title'] as String? ?? '',
    weight: (json['weight'] as num?)?.toDouble(),
  );
}

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
  final bool trackPercentage;
  final bool trackNumeric;
  final bool trackDuration;
  final bool trackNetHours;
  final bool trackNote;
  final double? defaultPercentage;
  final double? defaultNumeric;
  final double? defaultDuration;
  final List<String> dataOrder; // e.g. ['BRUT', 'PERCENTAGE', 'NET', 'NUMERIC', 'NOTE']
  final List<ProjectStep> checkSteps;

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
    this.trackPercentage = true,
    this.trackNumeric = false,
    this.trackDuration = true,
    this.trackNetHours = true,
    this.trackNote = true,
    this.defaultPercentage,
    this.defaultNumeric,
    this.defaultDuration,
    this.dataOrder = const ['BRUT', 'PERCENTAGE', 'NET', 'NUMERIC', 'NOTE'],
    this.checkSteps = const [],
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
    bool? trackPercentage,
    bool? trackNumeric,
    bool? trackDuration,
    bool? trackNetHours,
    bool? trackNote,
    double? defaultPercentage,
    double? defaultNumeric,
    double? defaultDuration,
    List<String>? dataOrder,
    List<ProjectStep>? checkSteps,
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
      trackPercentage: trackPercentage ?? this.trackPercentage,
      trackNumeric: trackNumeric ?? this.trackNumeric,
      trackDuration: trackDuration ?? this.trackDuration,
      trackNetHours: trackNetHours ?? this.trackNetHours,
      trackNote: trackNote ?? this.trackNote,
      defaultPercentage: defaultPercentage ?? this.defaultPercentage,
      defaultNumeric: defaultNumeric ?? this.defaultNumeric,
      defaultDuration: defaultDuration ?? this.defaultDuration,
      dataOrder: dataOrder ?? this.dataOrder,
      checkSteps: checkSteps ?? this.checkSteps,
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
      'trackPercentage': trackPercentage,
      'trackNumeric': trackNumeric,
      'trackDuration': trackDuration,
      'trackNetHours': trackNetHours,
      'trackNote': trackNote,
      'defaultPercentage': defaultPercentage,
      'defaultNumeric': defaultNumeric,
      'defaultDuration': defaultDuration,
      'dataOrder': dataOrder,
      'checkSteps': checkSteps.map((s) => s.toJson()).toList(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    List<String> projectTags = [];
    if (json['tags'] is List) {
      projectTags = List<String>.from(json['tags']);
    }

    final evalType = json['evaluationType'] as String? ?? 'PERCENTAGE';
    final trackPct = json['trackPercentage'] as bool? ?? (evalType == 'PERCENTAGE');
    final trackNum = json['trackNumeric'] as bool? ?? (evalType == 'NUMERIC');
    final trackDur = json['trackDuration'] as bool? ?? true;
    final trackNet = json['trackNetHours'] as bool? ?? (trackPct && trackDur);
    final trackNt = json['trackNote'] as bool? ?? true;
    
    final defaultPct = (json['defaultPercentage'] as num?)?.toDouble();
    final defaultNum = (json['defaultNumeric'] as num?)?.toDouble();
    final defaultDur = (json['defaultDuration'] as num?)?.toDouble();

    List<String> order = ['BRUT', 'PERCENTAGE', 'NET', 'NUMERIC', 'NOTE'];
    if (json['dataOrder'] is List) {
      order = List<String>.from(json['dataOrder']);
    }

    List<ProjectStep> steps = [];
    if (json['checkSteps'] is List) {
      steps = (json['checkSteps'] as List)
          .map((s) => ProjectStep.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return Project(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
      tag: json['tag'] as String? ?? 'Genel',
      subTag: json['subTag'] as String?,
      evaluationType: evalType,
      targetValue: (json['targetValue'] as num?)?.toDouble() ?? 100.0,
      isArchived: json['isArchived'] as bool? ?? false,
      status: json['status'] as String? ?? 'Aktif',
      isNegativeGoal: json['isNegativeGoal'] as bool? ?? false,
      tags: projectTags,
      trackPercentage: trackPct,
      trackNumeric: trackNum,
      trackDuration: trackDur,
      trackNetHours: trackNet,
      trackNote: trackNt,
      defaultPercentage: defaultPct,
      defaultNumeric: defaultNum,
      defaultDuration: defaultDur,
      dataOrder: order,
      checkSteps: steps,
    );
  }
}
