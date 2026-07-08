class RRuleTranslator {
  /// RRule kuralını Türkçe bir açıklamaya çevirir.
  static String translate(String? rrule) {
    if (rrule == null || rrule.isEmpty) return 'Tekrarsız';

    final Map<String, String> translations = {
      'FREQ=DAILY': 'Her gün',
      'FREQ=WEEKLY': 'Her hafta',
      'FREQ=MONTHLY': 'Her ay',
      'FREQ=YEARLY': 'Her yıl',
    };

    String result = 'Tekrarlı';
    translations.forEach((key, value) {
      if (rrule.contains(key)) {
        result = value;
      }
    });

    if (rrule.contains('INTERVAL=')) {
      final match = RegExp(r'INTERVAL=(\d+)').firstMatch(rrule);
      if (match != null) {
        final interval = match.group(1);
        if (rrule.contains('FREQ=DAILY')) {
          result = '$interval günde bir';
        } else if (rrule.contains('FREQ=WEEKLY')) {
          result = '$interval haftada bir';
        } else if (rrule.contains('FREQ=MONTHLY')) {
          result = '$interval ayda bir';
        } else if (rrule.contains('FREQ=YEARLY')) {
          result = '$interval yılda bir';
        }
      }
    }

    return result;
  }
}
