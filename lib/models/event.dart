class Event {
  final String id;
  final String title;
  final String description;
  final DateTime from;
  final DateTime to;
  final int colorValue;
  final String tag;
  final String? subTag;
  final int importance;
  final bool isAllDay;
  final String? recurrenceRule;
  final List<DateTime>? recurrenceExceptionDates;
  final String? projectId;
  final bool isTrackingEnabled;
  final String? projectTag;
  final bool isHidden;
  final List<int> notificationOffsets;
  final DateTime? reminderTime;
  final String? seriesId;

  const Event({
    required this.id,
    required this.title,
    this.description = '',
    required this.from,
    required this.to,
    required this.colorValue,
    this.tag = 'Genel',
    this.subTag,
    this.importance = 0,
    this.isAllDay = false,
    this.recurrenceRule,
    this.recurrenceExceptionDates,
    this.projectId,
    this.isTrackingEnabled = false,
    this.projectTag,
    this.isHidden = false,
    this.notificationOffsets = const [],
    this.reminderTime,
    this.seriesId,
  });

  Event copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? from,
    DateTime? to,
    int? colorValue,
    String? tag,
    String? subTag,
    int? importance,
    bool? isAllDay,
    String? recurrenceRule,
    List<DateTime>? recurrenceExceptionDates,
    String? projectId,
    bool? isTrackingEnabled,
    String? projectTag,
    bool? isHidden,
    List<int>? notificationOffsets,
    DateTime? reminderTime,
    String? seriesId,
    bool clearRecurrenceRule = false,
    bool clearRecurrenceExceptionDates = false,
    bool clearProjectId = false,
    bool clearSubTag = false,
    bool clearProjectTag = false,
    bool clearReminderTime = false,
    bool clearSeriesId = false,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      from: from ?? this.from,
      to: to ?? this.to,
      colorValue: colorValue ?? this.colorValue,
      tag: tag ?? this.tag,
      subTag: clearSubTag ? null : (subTag ?? this.subTag),
      importance: importance ?? this.importance,
      isAllDay: isAllDay ?? this.isAllDay,
      recurrenceRule: clearRecurrenceRule ? null : (recurrenceRule ?? this.recurrenceRule),
      recurrenceExceptionDates: clearRecurrenceExceptionDates ? null : (recurrenceExceptionDates ?? this.recurrenceExceptionDates),
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      isTrackingEnabled: isTrackingEnabled ?? this.isTrackingEnabled,
      projectTag: clearProjectTag ? null : (projectTag ?? this.projectTag),
      isHidden: isHidden ?? this.isHidden,
      notificationOffsets: notificationOffsets ?? this.notificationOffsets,
      reminderTime: clearReminderTime ? null : (reminderTime ?? this.reminderTime),
      seriesId: clearSeriesId ? null : (seriesId ?? this.seriesId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'colorValue': colorValue,
      'tag': tag,
      'subTag': subTag,
      'importance': importance,
      'isAllDay': isAllDay,
      'recurrenceRule': recurrenceRule,
      'recurrenceExceptionDates': recurrenceExceptionDates
          ?.map((d) => d.toIso8601String())
          .toList(),
      'projectId': projectId,
      'isTrackingEnabled': isTrackingEnabled,
      'projectTag': projectTag,
      'isHidden': isHidden,
      'notificationOffsets': notificationOffsets,
      'reminderTime': reminderTime?.toIso8601String(),
      'seriesId': seriesId,
    };
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    List<DateTime>? exceptionDates;
    final rawEx = json['recurrenceExceptionDates'];
    if (rawEx is List) {
      exceptionDates = rawEx
          .whereType<String>()
          .map((s) => DateTime.parse(s))
          .toList();
    }

    List<int> notifOffsets = [];
    final rawNotif = json['notificationOffsets'];
    if (rawNotif is List) {
      notifOffsets = rawNotif.whereType<int>().toList();
    }

    return Event(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
      tag: json['tag'] as String? ?? 'Genel',
      subTag: json['subTag'] as String?,
      importance: json['importance'] as int? ?? 0,
      isAllDay: json['isAllDay'] as bool? ?? false,
      recurrenceRule: json['recurrenceRule'] as String?,
      recurrenceExceptionDates: exceptionDates,
      projectId: json['projectId'] as String?,
      isTrackingEnabled: json['isTrackingEnabled'] as bool? ?? false,
      projectTag: json['projectTag'] as String?,
      isHidden: json['isHidden'] as bool? ?? false,
      notificationOffsets: notifOffsets,
      reminderTime: json['reminderTime'] != null ? DateTime.parse(json['reminderTime'] as String) : null,
      seriesId: json['seriesId'] as String?,
    );
  }
}
