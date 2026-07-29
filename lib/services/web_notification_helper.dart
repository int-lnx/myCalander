import 'web_notification_stub.dart'
    if (dart.library.html) 'web_notification_web.dart';

class WebNotificationHelper {
  static Future<void> requestPermission() async {
    await requestWebNotificationPermissionImpl();
  }

  static void showNotification(String title, String body) {
    showWebNotificationImpl(title, body);
  }

  static void scheduleNotification(String id, String title, String body, DateTime triggerTime) {
    scheduleWebNotificationImpl(id, title, body, triggerTime);
  }

  static void cancelNotification(String id) {
    cancelWebNotificationImpl(id);
  }
}
