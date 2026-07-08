class TaskItem {
  final String id;
  final String seriesId;
  final String title;
  final String details;
  final bool isCompleted;
  final DateTime? from;
  final DateTime? to;
  final bool isAllDay;
  final int colorValue;
  final String tag;
  final String? subTag;
  final int importance; // 0: Düşük, 1: Orta, 2: Yüksek
  final String? recurrenceRule;
  final List<DateTime>? recurrenceExceptionDates;
  final String? projectId;
  final String? parentTaskId;
  final String? recurrenceRuleForDisplay;
  final String? superTaskId;
  final bool isHidden;
  final String? projectTag;
  final bool hasNotification;           // Bildirim aktif mi?
  final int? notificationMinutesBefore; // Kaç dakika önce bildirim?
  final List<int> notificationOffsets;

  TaskItem({
    required this.id,
    required this.title,
    this.details = '',
    this.isCompleted = false,
    DateTime? from,
    DateTime? to,
    this.isAllDay = false,
    this.colorValue = 0xFF4CAF50, // Default Colors.green
    this.tag = 'Genel',
    this.subTag,
    this.importance = 0,
    this.recurrenceRule,
    this.recurrenceExceptionDates,
    this.projectId,
    this.parentTaskId,
    this.recurrenceRuleForDisplay,
    this.superTaskId,
    this.isHidden = false,
    this.projectTag,
    this.hasNotification = false,
    this.notificationMinutesBefore,
    this.notificationOffsets = const [],
    String? seriesId,
  }) : seriesId = seriesId ?? id,
       from = (isAllDay && from != null) ? DateTime(from.year, from.month, from.day) : from,
       to = (isAllDay && to != null) ? DateTime(to.year, to.month, to.day) : to;

  TaskItem copyWith({
    String? id,
    String? title,
    String? details,
    bool? isCompleted,
    DateTime? from,
    DateTime? to,
    bool? isAllDay,
    int? colorValue,
    String? tag,
    String? subTag,
    int? importance,
    String? recurrenceRule,
    List<DateTime>? recurrenceExceptionDates,
    String? projectId,
    String? parentTaskId,
    String? recurrenceRuleForDisplay,
    String? superTaskId,
    bool? isHidden,
    String? projectTag,
    bool? hasNotification,
    int? notificationMinutesBefore,
    List<int>? notificationOffsets,
    bool clearRecurrenceRule = false,
    bool clearRecurrenceExceptionDates = false,
    String? seriesId,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      details: details ?? this.details,
      isCompleted: isCompleted ?? this.isCompleted,
      from: from ?? this.from,
      to: to ?? this.to,
      isAllDay: isAllDay ?? this.isAllDay,
      colorValue: colorValue ?? this.colorValue,
      tag: tag ?? this.tag,
      subTag: subTag ?? this.subTag,
      importance: importance ?? this.importance,
      recurrenceRule: clearRecurrenceRule ? null : (recurrenceRule ?? this.recurrenceRule),
      recurrenceExceptionDates: clearRecurrenceExceptionDates ? null : (recurrenceExceptionDates ?? this.recurrenceExceptionDates),
      projectId: projectId ?? this.projectId,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      recurrenceRuleForDisplay: recurrenceRuleForDisplay ?? this.recurrenceRuleForDisplay,
      superTaskId: superTaskId ?? this.superTaskId,
      isHidden: isHidden ?? this.isHidden,
      projectTag: projectTag ?? this.projectTag,
      hasNotification: hasNotification ?? this.hasNotification,
      notificationMinutesBefore: notificationMinutesBefore ?? this.notificationMinutesBefore,
      notificationOffsets: notificationOffsets ?? this.notificationOffsets,
      seriesId: seriesId ?? this.seriesId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seriesId': seriesId,
      'title': title,
      'details': details,
      'isCompleted': isCompleted,
      'from': from?.toIso8601String(),
      'to': to?.toIso8601String(),
      'isAllDay': isAllDay,
      'colorValue': colorValue,
      'tag': tag,
      'subTag': subTag,
      'importance': importance,
      'recurrenceRule': recurrenceRule,
      'recurrenceExceptionDates': recurrenceExceptionDates?.map((e) => e.toIso8601String()).toList(),
      'projectId': projectId,
      'parentTaskId': parentTaskId,
      'recurrenceRuleForDisplay': recurrenceRuleForDisplay,
      'superTaskId': superTaskId,
      'isHidden': isHidden,
      'projectTag': projectTag,
      'hasNotification': hasNotification,
      'notificationMinutesBefore': notificationMinutesBefore,
      'notificationOffsets': notificationOffsets,
    };
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final List<int> offsets = json['notificationOffsets'] != null
        ? List<int>.from(json['notificationOffsets'])
        : ((json['hasNotification'] ?? false) && json['notificationMinutesBefore'] != null
            ? [json['notificationMinutesBefore'] as int]
            : const []);

    return TaskItem(
      id: json['id'],
      title: json['title'],
      details: json['details'] ?? '',
      isCompleted: json['isCompleted'] ?? false,
      from: json['from'] != null ? DateTime.parse(json['from']) : null,
      to: json['to'] != null ? DateTime.parse(json['to']) : null,
      isAllDay: json['isAllDay'] ?? false,
      colorValue: json['colorValue'] ?? 0xFF4CAF50,
      tag: (json['tag'] == null || json['tag'].toString().trim().isEmpty) ? 'Genel' : json['tag'],
      subTag: json['subTag'],
      importance: json['importance'] ?? 0,
      recurrenceRule: json['recurrenceRule'],
      recurrenceExceptionDates: json['recurrenceExceptionDates'] != null
          ? (json['recurrenceExceptionDates'] as List).map((e) => DateTime.parse(e)).toList()
          : null,
      projectId: json['projectId'],
      parentTaskId: json['parentTaskId'],
      recurrenceRuleForDisplay: json['recurrenceRuleForDisplay'],
      superTaskId: json['superTaskId'],
      isHidden: json['isHidden'] ?? false,
      projectTag: json['projectTag'],
      hasNotification: json['hasNotification'] ?? false,
      notificationMinutesBefore: json['notificationMinutesBefore'],
      notificationOffsets: offsets,
      seriesId: json['seriesId'],
    );
  }
}

