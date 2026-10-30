import 'dart:html' as html;
import 'dart:async';

class _ScheduledWebNotif {
  final String id;
  final String title;
  final String body;
  final DateTime triggerTime;

  _ScheduledWebNotif({
    required this.id,
    required this.title,
    required this.body,
    required this.triggerTime,
  });
}

// Aktif Timer referansları
final Map<String, Timer> _activeWebTimers = {};

// Bekleyen tüm bildirim kayıtları (uzak tarihliler dahil)
final Map<String, _ScheduledWebNotif> _scheduledNotifications = {};

// Bu oturumda zaten gösterilmiş olan bildirimler (mükerrer patlamayı önler)
final Set<String> _deliveredNotificationIds = {};

// 32-bit setTimeout sınırına takılmadan uzun vadeli kontrolleri yapan periyodik zamanlayıcı
Timer? _periodicCheckTimer;

// JavaScript setTimeout 32-bit işaretli tamsayı sınırı: 2.147.483.647 ms ≈ 24.8 gün.
// Chrome'da taşma (overflow) yaşanıp 1ms'de hemen çalmaması için doğrudan zamanlayıcıyı en fazla 20 gün ile sınırlıyoruz.
const int _maxSafeTimeoutMs = 1728000000; // 20 gün (ms)

void _ensurePeriodicChecker() {
  if (_periodicCheckTimer != null && _periodicCheckTimer!.isActive) return;
  _periodicCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
    _checkPendingNotifications();
  });
}

void _checkPendingNotifications() {
  final now = DateTime.now();
  final List<String> toDeliver = [];

  _scheduledNotifications.forEach((id, notif) {
    if (_deliveredNotificationIds.contains(id)) return;

    final diff = notif.triggerTime.difference(now);
    // Vakti gelmiş bildirimler (son 5 dakika içinde olmalı, çok eski geçmiş olmamalı)
    if (diff.isNegative && diff.inMinutes.abs() <= 5) {
      toDeliver.add(id);
    } else if (!diff.isNegative &&
        diff.inMilliseconds <= _maxSafeTimeoutMs &&
        !_activeWebTimers.containsKey(id)) {
      // Güvenli pencereye giren bildirimi doğrudan Timer'a bağla
      _setSafeTimer(notif);
    }
  });

  for (final id in toDeliver) {
    final notif = _scheduledNotifications[id];
    if (notif != null) {
      _deliverNotification(notif);
    }
  }
}

void _setSafeTimer(_ScheduledWebNotif notif) {
  _activeWebTimers[notif.id]?.cancel();
  final now = DateTime.now();
  final diff = notif.triggerTime.difference(now);

  if (diff.isNegative) return;
  if (diff.inMilliseconds > _maxSafeTimeoutMs) {
    // 20 günden uzak; periyodik kontrol vakti yaklaşınca zamanlayıcıya alacak
    return;
  }

  // Minimum 500ms gecikme (anlık senkronize patlamaları önler)
  final delay =
      diff.inMilliseconds < 500 ? const Duration(milliseconds: 500) : diff;

  final timer = Timer(delay, () {
    _deliverNotification(notif);
  });
  _activeWebTimers[notif.id] = timer;
}

void _deliverNotification(_ScheduledWebNotif notif) {
  if (_deliveredNotificationIds.contains(notif.id)) return;
  _deliveredNotificationIds.add(notif.id);

  _activeWebTimers[notif.id]?.cancel();
  _activeWebTimers.remove(notif.id);
  _scheduledNotifications.remove(notif.id);

  showWebNotificationImpl(notif.title, notif.body);
}

Future<void> requestWebNotificationPermissionImpl() async {
  try {
    if (html.Notification.permission != 'granted') {
      await html.Notification.requestPermission();
    }
  } catch (e) {
    // Permission request error handling
  }
}

void showWebNotificationImpl(String title, String body) {
  try {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
    }
  } catch (e) {
    // Show notification error handling
  }
}

void scheduleWebNotificationImpl(
    String id, String title, String body, DateTime triggerTime) {
  _ensurePeriodicChecker();

  // Zaten gösterilmişse tekrar çalma
  if (_deliveredNotificationIds.contains(id)) {
    return;
  }

  cancelWebNotificationImpl(id);

  final now = DateTime.now();
  final difference = triggerTime.difference(now);

  // Eğer geçmişte kalmışsa (10 saniyeden eski), zamanlama yapma
  if (difference.inSeconds < -10) {
    return;
  }

  final notif = _ScheduledWebNotif(
    id: id,
    title: title,
    body: body,
    triggerTime: triggerTime,
  );
  _scheduledNotifications[id] = notif;

  // Güvenli pencere içindeyse (20 gün altı) Timer kur
  if (difference.inMilliseconds <= _maxSafeTimeoutMs) {
    _setSafeTimer(notif);
  }
}

void cancelWebNotificationImpl(String id) {
  if (_activeWebTimers.containsKey(id)) {
    _activeWebTimers[id]?.cancel();
    _activeWebTimers.remove(id);
  }
  _scheduledNotifications.remove(id);
}
