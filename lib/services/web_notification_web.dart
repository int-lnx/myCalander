import 'dart:html' as html;
import 'dart:async';

final Map<String, Timer> _activeWebTimers = {};

Future<void> requestWebNotificationPermissionImpl() async {
  try {
    print('Requesting web notification permission...');
    if (html.Notification.permission != 'granted') {
      final permission = await html.Notification.requestPermission();
      print('Web notification permission result: $permission');
    } else {
      print('Web notification permission is already granted.');
    }
  } catch (e) {
    print('Error requesting web notification permission: $e');
  }
}

void showWebNotificationImpl(String title, String body) {
  try {
    print('Attempting to show web notification. Permission: ${html.Notification.permission}');
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
      print('Web notification shown successfully.');
    } else {
      print('Cannot show notification: permission is not granted.');
    }
  } catch (e) {
    print('Error in showWebNotificationImpl: $e');
  }
}

void scheduleWebNotificationImpl(String id, String title, String body, DateTime triggerTime) {
  cancelWebNotificationImpl(id);
  final now = DateTime.now();
  final difference = triggerTime.difference(now);
  
  print('Scheduling web notification: "$title" - id: $id - triggerTime: $triggerTime - in ${difference.inSeconds} seconds');
  
  if (difference.isNegative) {
    print('Skipping schedule: triggerTime is in the past.');
    return;
  }

  final timer = Timer(difference, () {
    print('Web timer fired for notification: "$title" (id: $id)');
    showWebNotificationImpl(title, body);
    _activeWebTimers.remove(id);
  });
  _activeWebTimers[id] = timer;
}

void cancelWebNotificationImpl(String id) {
  if (_activeWebTimers.containsKey(id)) {
    print('Cancelling web notification timer for id: $id');
    _activeWebTimers[id]?.cancel();
    _activeWebTimers.remove(id);
  }
}
