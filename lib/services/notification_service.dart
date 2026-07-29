import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../utils/recurrence_helper.dart';
import 'web_notification_helper.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (kIsWeb) {
      await WebNotificationHelper.requestPermission();
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      tz.initializeTimeZones();
      try {
        final String timeZoneName =
            (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(timeZoneName));
      } catch (_) {
        try {
          tz.setLocalLocation(tz.getLocation('UTC'));
        } catch (_) {}
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings();

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsDarwin,
          );

      await _notificationsPlugin.initialize(settings: initializationSettings);

      if (defaultTargetPlatform == TargetPlatform.android) {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'my_plan_events_channel',
          'Plan-A Etkinlik Bildirimleri',
          description: 'Etkinlik hatırlatıcıları için bildirim kanalı.',
          importance: Importance.max,
        );

        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(channel);
      }
    } catch (e) {
      debugPrint('NotificationService initialization failed: $e');
    }
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb) {
      await WebNotificationHelper.requestPermission();
      return;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();

        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestExactAlarmsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('NotificationService requestPermissions failed: $e');
    }
  }

  static String? _sanitizeRRule(String? rule, DateTime startDate) {
    if (rule == null || rule.isEmpty) return rule;
    String sanitized = rule;
    if (sanitized.contains('FREQ=WEEKLY') && !sanitized.contains('BYDAY=')) {
      const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
      final weekday = startDate.weekday;
      if (weekday >= 1 && weekday <= 7) {
        sanitized = '$sanitized;BYDAY=${days[weekday - 1]}';
      }
    }
    if (sanitized.contains('FREQ=MONTHLY') &&
        !sanitized.contains('BYMONTHDAY=') &&
        !sanitized.contains('BYDAY=')) {
      sanitized = '$sanitized;BYMONTHDAY=${startDate.day}';
    }
    if (sanitized.contains('FREQ=YEARLY') && !sanitized.contains('BYMONTH=')) {
      sanitized =
          '$sanitized;BYMONTH=${startDate.month};BYMONTHDAY=${startDate.day}';
    }
    return sanitized;
  }

  static List<DateTime> _getOccurrences(Event event) {
    if (event.recurrenceRule == null || event.recurrenceRule!.isEmpty) {
      return [event.from];
    }

    final start = DateTime.now().subtract(const Duration(days: 1));
    final end = DateTime.now().add(const Duration(days: 30));

    try {
      final dates = RecurrenceHelper.getOccurrences(
        rrule: event.recurrenceRule!,
        startDate: event.from,
        specificStartDate: start,
        specificEndDate: end,
      );
      return dates.where((occ) {
        final isException =
            event.recurrenceExceptionDates?.any(
              (ex) =>
                  ex.year == occ.year &&
                  ex.month == occ.month &&
                  ex.day == occ.day,
            ) ??
            false;
        return !isException;
      }).toList();
    } catch (_) {
      return [event.from];
    }
  }

  static Future<void> scheduleEventNotifications(Event event) async {
    await cancelEventNotifications(event);

    if (kIsWeb) {
      final occurrences = _getOccurrences(event);
      final now = DateTime.now();
      for (var occ in occurrences) {
        for (var offset in event.notificationOffsets) {
          final triggerTime = occ.subtract(Duration(minutes: offset));
          if (triggerTime.isBefore(now)) {
            continue;
          }
          final String uniqueId = 'event_${event.id}_${occ.millisecondsSinceEpoch}_$offset';
          final String body = offset == 0
              ? 'Etkinlik şimdi başlıyor!'
              : (offset >= 1440
                    ? 'Etkinliğe ${offset ~/ 1440} gün kaldı.'
                    : (offset >= 60
                          ? 'Etkinliğe ${offset ~/ 60} saat kaldı.'
                          : 'Etkinliğe $offset dakika kaldı.'));
          WebNotificationHelper.scheduleNotification(
            uniqueId,
            event.title,
            body,
            triggerTime,
          );
        }
      }
      return;
    }

    final occurrences = _getOccurrences(event);
    final now = DateTime.now();

    for (var occ in occurrences) {
      for (var offset in event.notificationOffsets) {
        final triggerTime = occ.subtract(Duration(minutes: offset));
        if (triggerTime.isBefore(now)) {
          continue;
        }

        final int id =
            (event.id.hashCode ^ (occ.millisecondsSinceEpoch ~/ 60000) ^ offset)
                .toSigned(32);
        final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
          triggerTime,
          tz.local,
        );

        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'my_plan_events_channel',
              'Plan-A Etkinlik Bildirimleri',
              channelDescription:
                  'Etkinlik hatırlatıcıları için bildirim kanalı.',
              importance: Importance.max,
              priority: Priority.high,
            );

        const NotificationDetails details = NotificationDetails(
          android: androidDetails,
        );

        try {
          await _notificationsPlugin.zonedSchedule(
            id: id,
            title: event.title,
            body: offset == 0
                ? 'Etkinlik şimdi başlıyor!'
                : (offset >= 1440
                      ? 'Etkinliğe ${offset ~/ 1440} gün kaldı.'
                      : (offset >= 60
                            ? 'Etkinliğe ${offset ~/ 60} saat kaldı.'
                            : 'Etkinliğe $offset dakika kaldı.')),
            scheduledDate: scheduledDate,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } catch (_) {
          try {
            await _notificationsPlugin.zonedSchedule(
              id: id,
              title: event.title,
              body: offset == 0
                  ? 'Etkinlik şimdi başlıyor!'
                  : (offset >= 1440
                        ? 'Etkinliğe ${offset ~/ 1440} gün kaldı.'
                        : (offset >= 60
                              ? 'Etkinliğe ${offset ~/ 60} saat kaldı.'
                              : 'Etkinliğe $offset dakika kaldı.')),
              scheduledDate: scheduledDate,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> cancelEventNotifications(Event event) async {
    if (kIsWeb) {
      final occurrences = _getOccurrences(event);
      final List<int> offsetsToCancel = [
        0,
        5,
        10,
        15,
        30,
        60,
        120,
        1440,
        10080,
        ...event.notificationOffsets,
      ];
      for (var occ in occurrences) {
        for (var offset in offsetsToCancel) {
          final String uniqueId = 'event_${event.id}_${occ.millisecondsSinceEpoch}_$offset';
          WebNotificationHelper.cancelNotification(uniqueId);
        }
      }
      return;
    }

    final start = DateTime.now().subtract(const Duration(days: 30));
    final end = DateTime.now().add(const Duration(days: 30));
    final List<int> offsetsToCancel = [
      0,
      5,
      10,
      15,
      30,
      60,
      120,
      1440,
      10080,
      ...event.notificationOffsets,
    ];

    try {
      final List<DateTime> occurrences = [];
      if (event.recurrenceRule != null && event.recurrenceRule!.isNotEmpty) {
        try {
          final dates = RecurrenceHelper.getOccurrences(
            rrule: event.recurrenceRule!,
            startDate: event.from,
            specificStartDate: start,
            specificEndDate: end,
          );
          occurrences.addAll(dates);
        } catch (_) {}
      } else {
        occurrences.add(event.from);
      }

      for (var occ in occurrences) {
        for (var offset in offsetsToCancel) {
          final int id =
              (event.id.hashCode ^
               (occ.millisecondsSinceEpoch ~/ 60000) ^
               offset).toSigned(32);
          await _notificationsPlugin.cancel(id: id);
        }
      }
    } catch (_) {}
  }

  static List<DateTime> _getTaskOccurrences(TaskItem task) {
    if (task.from == null) return [];
    if (task.recurrenceRule == null || task.recurrenceRule!.isEmpty) {
      return [task.from!];
    }

    final start = DateTime.now().subtract(const Duration(days: 1));
    final end = DateTime.now().add(const Duration(days: 30));

    try {
      final dates = RecurrenceHelper.getOccurrences(
        rrule: task.recurrenceRule!,
        startDate: task.from!,
        specificStartDate: start,
        specificEndDate: end,
      );
      return dates.where((occ) {
        final isException =
            task.recurrenceExceptionDates?.any(
              (ex) =>
                  ex.year == occ.year &&
                  ex.month == occ.month &&
                  ex.day == occ.day,
            ) ??
            false;
        return !isException;
      }).toList();
    } catch (_) {
      return [task.from!];
    }
  }

  static Future<void> scheduleTaskNotifications(TaskItem task) async {
    await cancelTaskNotifications(task);
    if (task.from == null) return;

    if (kIsWeb) {
      final occurrences = _getTaskOccurrences(task);
      final now = DateTime.now();
      for (var occ in occurrences) {
        for (var offset in task.notificationOffsets) {
          final triggerTime = occ.subtract(Duration(minutes: offset));
          if (triggerTime.isBefore(now)) {
            continue;
          }
          final String uniqueId = 'task_${task.id}_${occ.millisecondsSinceEpoch}_$offset';
          final String body = offset == 0
              ? 'Görev şimdi başlıyor!'
              : (offset >= 1440
                    ? 'Göreve ${offset ~/ 1440} gün kaldı.'
                    : (offset >= 60
                          ? 'Göreve ${offset ~/ 60} saat kaldı.'
                          : 'Göreve $offset dakika kaldı.'));
          WebNotificationHelper.scheduleNotification(
            uniqueId,
            task.title,
            body,
            triggerTime,
          );
        }
      }
      return;
    }

    final occurrences = _getTaskOccurrences(task);
    final now = DateTime.now();

    for (var occ in occurrences) {
      for (var offset in task.notificationOffsets) {
        final triggerTime = occ.subtract(Duration(minutes: offset));
        if (triggerTime.isBefore(now)) {
          continue;
        }

        final int id =
            (task.id.hashCode ^ (occ.millisecondsSinceEpoch ~/ 60000) ^ offset)
                .toSigned(32);
        final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
          triggerTime,
          tz.local,
        );

        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'my_plan_events_channel',
              'Plan-A Görev Bildirimleri',
              channelDescription: 'Görev hatırlatıcıları için bildirim kanalı.',
              importance: Importance.max,
              priority: Priority.high,
            );

        const NotificationDetails details = NotificationDetails(
          android: androidDetails,
        );

        try {
          await _notificationsPlugin.zonedSchedule(
            id: id,
            title: task.title,
            body: offset == 0
                ? 'Görev şimdi başlıyor!'
                : (offset >= 1440
                      ? 'Göreve ${offset ~/ 1440} gün kaldı.'
                      : (offset >= 60
                            ? 'Göreve ${offset ~/ 60} saat kaldı.'
                            : 'Göreve $offset dakika kaldı.')),
            scheduledDate: scheduledDate,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } catch (_) {
          try {
            await _notificationsPlugin.zonedSchedule(
              id: id,
              title: task.title,
              body: offset == 0
                  ? 'Görev şimdi başlıyor!'
                  : (offset >= 1440
                        ? 'Göreve ${offset ~/ 1440} gün kaldı.'
                        : (offset >= 60
                              ? 'Göreve ${offset ~/ 60} saat kaldı.'
                              : 'Göreve $offset dakika kaldı.')),
              scheduledDate: scheduledDate,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> cancelTaskNotifications(TaskItem task) async {
    if (task.from == null) return;

    if (kIsWeb) {
      final occurrences = _getTaskOccurrences(task);
      final List<int> offsetsToCancel = [
        0,
        5,
        10,
        15,
        30,
        60,
        120,
        1440,
        10080,
        ...task.notificationOffsets,
      ];
      for (var occ in occurrences) {
        for (var offset in offsetsToCancel) {
          final String uniqueId = 'task_${task.id}_${occ.millisecondsSinceEpoch}_$offset';
          WebNotificationHelper.cancelNotification(uniqueId);
        }
      }
      return;
    }

    final start = DateTime.now().subtract(const Duration(days: 30));
    final end = DateTime.now().add(const Duration(days: 30));
    final List<int> offsetsToCancel = [
      0,
      5,
      10,
      15,
      30,
      60,
      120,
      1440,
      10080,
      ...task.notificationOffsets,
    ];

    try {
      final List<DateTime> occurrences = [];
      if (task.recurrenceRule != null && task.recurrenceRule!.isNotEmpty) {
        try {
          final dates = RecurrenceHelper.getOccurrences(
            rrule: task.recurrenceRule!,
            startDate: task.from!,
            specificStartDate: start,
            specificEndDate: end,
          );
          occurrences.addAll(dates);
        } catch (_) {}
      } else {
        occurrences.add(task.from!);
      }

      for (var occ in occurrences) {
        for (var offset in offsetsToCancel) {
          final int id =
              (task.id.hashCode ^ (occ.millisecondsSinceEpoch ~/ 60000) ^ offset)
                  .toSigned(32);
          await _notificationsPlugin.cancel(id: id);
        }
      }
    } catch (_) {}
  }
}
