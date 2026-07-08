class PlanDayReport {
  final int offset; // 1 if skipped, 0 otherwise
  final String note;
  final double hoursWorked;
  final bool isWaiting;
  final double? performancePercent;

  const PlanDayReport({
    this.offset = 0,
    this.note = '',
    this.hoursWorked = 0.0,
    this.isWaiting = false,
    this.performancePercent,
  });

  Map<String, dynamic> toJson() {
    return {
      'offset': offset,
      'note': note,
      'hoursWorked': hoursWorked,
      'isWaiting': isWaiting,
      'performancePercent': performancePercent,
    };
  }

  factory PlanDayReport.fromJson(Map<String, dynamic> json) {
    return PlanDayReport(
      offset: json['offset'] as int? ?? 0,
      note: json['note'] as String? ?? '',
      hoursWorked: (json['hoursWorked'] as num?)?.toDouble() ?? 0.0,
      isWaiting: json['isWaiting'] as bool? ?? false,
      performancePercent: (json['performancePercent'] as num?)?.toDouble(),
    );
  }
}

class TopicPlan {
  final String id;
  final String title;
  final String description;
  final String topicId;
  final String? projectId;
  final String? parentId;
  final String? dependsOnPlanId;
  final String status; // 'Yapılacak', 'Yapılıyor', 'Yapılanlar', 'Bekleyenler', 'Başlanmadı'
  final DateTime? waitingSince;
  final bool isInPool;
  final int? year;
  final Map<String, PlanDayReport> dayReports; // key: yyyy-MM-dd

  // Form ve Analiz Alanları
  final DateTime startDate;
  final DateTime endDate;
  final double targetHours;
  final int colorValue;
  final int importance;
  final int startMonth;
  final int startWeek;
  final int endMonth;
  final int endWeek;
  final int? durationDays;
  final bool excludeWeekends;
  final List<int> excludedWeekdays;
  final List<DateTime> excludedDates;
  final String? dependsOnType;

  const TopicPlan({
    required this.id,
    required this.title,
    this.description = '',
    required this.topicId,
    this.projectId,
    this.parentId,
    this.dependsOnPlanId,
    required this.status,
    this.waitingSince,
    this.isInPool = false,
    this.year,
    this.dayReports = const {},
    required this.startDate,
    required this.endDate,
    this.targetHours = 0.0,
    this.colorValue = 0xFF009688,
    this.importance = 0,
    this.startMonth = 1,
    this.startWeek = 1,
    this.endMonth = 1,
    this.endWeek = 1,
    this.durationDays,
    this.excludeWeekends = false,
    this.excludedWeekdays = const [],
    this.excludedDates = const [],
    this.dependsOnType,
  });

  DateTime get actualEndDate => endDate;

  TopicPlan copyWith({
    String? id,
    String? title,
    String? description,
    String? topicId,
    String? projectId,
    String? parentId,
    String? dependsOnPlanId,
    String? status,
    DateTime? waitingSince,
    bool? isInPool,
    int? year,
    Map<String, PlanDayReport>? dayReports,
    DateTime? startDate,
    DateTime? endDate,
    double? targetHours,
    int? colorValue,
    int? importance,
    int? startMonth,
    int? startWeek,
    int? endMonth,
    int? endWeek,
    int? durationDays,
    bool? excludeWeekends,
    List<int>? excludedWeekdays,
    List<DateTime>? excludedDates,
    String? dependsOnType,
    bool clearDependency = false,
    bool clearWaitingSince = false,
    bool clearParentId = false,
  }) {
    return TopicPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      topicId: topicId ?? this.topicId,
      projectId: projectId ?? this.projectId,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      dependsOnPlanId: clearDependency ? null : (dependsOnPlanId ?? this.dependsOnPlanId),
      status: status ?? this.status,
      waitingSince: clearWaitingSince ? null : (waitingSince ?? this.waitingSince),
      isInPool: isInPool ?? this.isInPool,
      year: year ?? this.year,
      dayReports: dayReports ?? this.dayReports,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      targetHours: targetHours ?? this.targetHours,
      colorValue: colorValue ?? this.colorValue,
      importance: importance ?? this.importance,
      startMonth: startMonth ?? this.startMonth,
      startWeek: startWeek ?? this.startWeek,
      endMonth: endMonth ?? this.endMonth,
      endWeek: endWeek ?? this.endWeek,
      durationDays: durationDays ?? this.durationDays,
      excludeWeekends: excludeWeekends ?? this.excludeWeekends,
      excludedWeekdays: excludedWeekdays ?? this.excludedWeekdays,
      excludedDates: excludedDates ?? this.excludedDates,
      dependsOnType: dependsOnType ?? this.dependsOnType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'topicId': topicId,
      'projectId': projectId,
      'parentId': parentId,
      'dependsOnPlanId': dependsOnPlanId,
      'status': status,
      'waitingSince': waitingSince?.toIso8601String(),
      'isInPool': isInPool,
      'year': year,
      'dayReports': dayReports.map((key, val) => MapEntry(key, val.toJson())),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'targetHours': targetHours,
      'colorValue': colorValue,
      'importance': importance,
      'startMonth': startMonth,
      'startWeek': startWeek,
      'endMonth': endMonth,
      'endWeek': endWeek,
      'durationDays': durationDays,
      'excludeWeekends': excludeWeekends,
      'excludedWeekdays': excludedWeekdays,
      'excludedDates': excludedDates.map((d) => d.toIso8601String()).toList(),
      'dependsOnType': dependsOnType,
    };
  }

  factory TopicPlan.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawReports = json['dayReports'] as Map<String, dynamic>? ?? {};
    final dayReports = rawReports.map((key, val) {
      return MapEntry(key, PlanDayReport.fromJson(val as Map<String, dynamic>));
    });

    List<int> exclWeekdays = [];
    if (json['excludedWeekdays'] is List) {
      exclWeekdays = List<int>.from(json['excludedWeekdays']);
    }

    List<DateTime> exclDates = [];
    if (json['excludedDates'] is List) {
      exclDates = (json['excludedDates'] as List).map((d) => DateTime.parse(d as String)).toList();
    }

    return TopicPlan(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      topicId: json['topicId'] as String? ?? '',
      projectId: json['projectId'] as String?,
      parentId: json['parentId'] as String?,
      dependsOnPlanId: json['dependsOnPlanId'] as String?,
      status: json['status'] as String? ?? 'Yapılacak',
      waitingSince: json['waitingSince'] != null ? DateTime.parse(json['waitingSince'] as String) : null,
      isInPool: json['isInPool'] as bool? ?? false,
      year: json['year'] as int?,
      dayReports: dayReports,
      startDate: json['startDate'] != null ? DateTime.parse(json['startDate'] as String) : DateTime.now(),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate'] as String) : DateTime.now(),
      targetHours: (json['targetHours'] as num?)?.toDouble() ?? 0.0,
      colorValue: json['colorValue'] as int? ?? 0xFF009688,
      importance: json['importance'] as int? ?? 0,
      startMonth: json['startMonth'] as int? ?? 1,
      startWeek: json['startWeek'] as int? ?? 1,
      endMonth: json['endMonth'] as int? ?? 1,
      endWeek: json['endWeek'] as int? ?? 1,
      durationDays: json['durationDays'] as int?,
      excludeWeekends: json['excludeWeekends'] as bool? ?? false,
      excludedWeekdays: exclWeekdays,
      excludedDates: exclDates,
      dependsOnType: json['dependsOnType'] as String?,
    );
  }
}
