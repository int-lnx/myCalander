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
      final List<DateTime> list = List<DateTime>.from(
        SfCalendar.getRecurrenceDateTimeCollection(
          rrule,
          startDate,
          specificStartDate: specificStartDate,
          specificEndDate: specificEndDate,
        ),
      );

      final lower = rrule.toLowerCase();
      if (!lower.contains('freq=monthly') && !lower.contains('freq=yearly')) {
        return list;
      }

      // Parse target day D
      int targetDay = startDate.day;
      final byMonthDayMatch = RegExp(r'bymonthday=([-\d]+)').firstMatch(lower);
      if (byMonthDayMatch != null) {
        final val = int.tryParse(byMonthDayMatch.group(1) ?? '${startDate.day}') ?? startDate.day;
        if (val < 0) return list; // -1 is already handled by engine
        targetDay = val;
      }

      if (targetDay < 29) return list;

      // Check each month in the range
      DateTime current = DateTime(specificStartDate.year, specificStartDate.month, 1);
      final DateTime endLimit = DateTime(specificEndDate.year, specificEndDate.month, 1);

      int getMaxDays(int y, int m) {
        if (m == 2) {
          final isLeap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
          return isLeap ? 29 : 28;
        }
        const days = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        return days[m];
      }

      bool isMonthMatch(int y, int m, DateTime cloneDate) {
        int interval = 1;
        final intervalMatch = RegExp(r'interval=(\d+)').firstMatch(lower);
        if (intervalMatch != null) {
          interval = int.tryParse(intervalMatch.group(1) ?? '1') ?? 1;
        }

        final untilMatch = RegExp(r'until=(\d{8})').firstMatch(lower);
        if (untilMatch != null) {
          final dateStr = untilMatch.group(1)!;
          final untilDate = DateTime(
            int.parse(dateStr.substring(0, 4)),
            int.parse(dateStr.substring(4, 6)),
            int.parse(dateStr.substring(6, 8)),
            23, 59, 59
          );
          if (cloneDate.isAfter(untilDate)) return false;
        }

        if (lower.contains('freq=monthly')) {
          final diffMonths = (y - startDate.year) * 12 + (m - startDate.month);
          if (diffMonths < 0) return false;
          if (diffMonths % interval != 0) return false;
          return true;
        } else if (lower.contains('freq=yearly')) {
          int targetMonth = startDate.month;
          final byMonthMatch = RegExp(r'bymonth=(\d+)').firstMatch(lower);
          if (byMonthMatch != null) {
            targetMonth = int.tryParse(byMonthMatch.group(1) ?? '${startDate.month}') ?? startDate.month;
          }
          if (m != targetMonth) return false;

          final diffYears = y - startDate.year;
          if (diffYears < 0) return false;
          if (diffYears % interval != 0) return false;
          return true;
        }
        return false;
      }

      while (!current.isAfter(endLimit)) {
        final y = current.year;
        final m = current.month;
        final maxDays = getMaxDays(y, m);

        if (targetDay > maxDays) {
          final cloneDate = DateTime(y, m, maxDays, startDate.hour, startDate.minute);
          
          // Check if within bounds
          if (!cloneDate.isBefore(specificStartDate) && !cloneDate.isAfter(specificEndDate)) {
            if (isMonthMatch(y, m, cloneDate)) {
              // Check if not already in the list
              final exists = list.any((d) => d.year == y && d.month == m && d.day == maxDays);
              if (!exists) {
                list.add(cloneDate);
              }
            }
          }
        }
        current = DateTime(current.year, current.month + 1, 1);
      }

      list.sort((a, b) => a.compareTo(b));
      return list;
    } catch (_) {
      return [];
    }
  }
}
