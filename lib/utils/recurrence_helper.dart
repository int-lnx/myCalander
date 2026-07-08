import 'package:syncfusion_flutter_calendar/calendar.dart';

class RecurrenceHelper {
  /// RRule kuralına göre belirli bir tarihteki tekrar tarihlerini hesaplar.
  static List<DateTime> getOccurrences({
    required String rrule,
    required DateTime startDate,
    required DateTime specificStartDate,
    required DateTime specificEndDate,
  }) {
    try {
      return SfCalendar.getRecurrenceDateTimeCollection(
        rrule,
        startDate,
        specificStartDate: specificStartDate,
        specificEndDate: specificEndDate,
      );
    } catch (_) {
      return [];
    }
  }
}
