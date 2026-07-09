import 'package:flutter/material.dart';

class CustomRecurrenceDialog extends StatefulWidget {
  final String? initialRRule;
  final DateTime eventDate;

  const CustomRecurrenceDialog({
    super.key,
    this.initialRRule,
    required this.eventDate,
  });

  @override
  State<CustomRecurrenceDialog> createState() => _CustomRecurrenceDialogState();
}

class _CustomRecurrenceDialogState extends State<CustomRecurrenceDialog> {
  late String _freq; // 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'
  late int _interval;
  late Set<String> _selectedDays; // e.g. {'MO', 'TU'}
  
  // End options
  String _endType = 'NEVER'; // 'NEVER', 'DATE', 'COUNT'
  DateTime _untilDate = DateTime.now().add(const Duration(days: 90));
  int _count = 10;

  final List<String> _weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  final List<String> _weekdayLabels = ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'];

  @override
  void initState() {
    super.initState();
    _freq = 'DAILY';
    _interval = 1;
    _selectedDays = {_weekdays[widget.eventDate.weekday - 1]};

    final rule = widget.initialRRule;
    if (rule != null && rule.isNotEmpty) {
      final upper = rule.toUpperCase();
      if (upper.contains('FREQ=DAILY')) _freq = 'DAILY';
      if (upper.contains('FREQ=WEEKLY')) _freq = 'WEEKLY';
      if (upper.contains('FREQ=MONTHLY')) _freq = 'MONTHLY';
      if (upper.contains('FREQ=YEARLY')) _freq = 'YEARLY';

      final intervalMatch = RegExp(r'INTERVAL=(\d+)').firstMatch(upper);
      if (intervalMatch != null) {
        _interval = int.tryParse(intervalMatch.group(1) ?? '1') ?? 1;
      }

      // Parse BYDAY
      final bydayMatch = RegExp(r'BYDAY=([A-Z,]+)').firstMatch(upper);
      if (bydayMatch != null) {
        final daysList = bydayMatch.group(1)!.split(',');
        _selectedDays = Set<String>.from(daysList);
      }

      // Parse Ends
      if (upper.contains('COUNT=')) {
        _endType = 'COUNT';
        final countMatch = RegExp(r'COUNT=(\d+)').firstMatch(upper);
        if (countMatch != null) {
          _count = int.tryParse(countMatch.group(1) ?? '10') ?? 10;
        }
      } else if (upper.contains('UNTIL=')) {
        _endType = 'DATE';
        final untilMatch = RegExp(r'UNTIL=(\d{8})').firstMatch(upper);
        if (untilMatch != null) {
          final dateStr = untilMatch.group(1)!;
          try {
            _untilDate = DateTime(
              int.parse(dateStr.substring(0, 4)),
              int.parse(dateStr.substring(4, 6)),
              int.parse(dateStr.substring(6, 8)),
            );
          } catch (_) {}
        }
      }
    }
  }

  String _getFreqText(String f) {
    switch (f) {
      case 'DAILY':
        return 'gün';
      case 'WEEKLY':
        return 'hafta';
      case 'MONTHLY':
        return 'ay';
      case 'YEARLY':
        return 'yıl';
      default:
        return 'gün';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Colors.blue;

    return AlertDialog(
      title: const Text('Özel yineleme', style: TextStyle(fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Interval selector
              Row(
                children: [
                  const Text('Yineleme sıklığı: ', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    child: TextFormField(
                      initialValue: _interval.toString(),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          setState(() => _interval = parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _freq,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'DAILY', child: Text('gün')),
                      DropdownMenuItem(value: 'WEEKLY', child: Text('hafta')),
                      DropdownMenuItem(value: 'MONTHLY', child: Text('ay')),
                      DropdownMenuItem(value: 'YEARLY', child: Text('yıl')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _freq = val);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Weekdays (Only if WEEKLY)
              if (_freq == 'WEEKLY') ...[
                const Text('Şu günlerde yinele:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (idx) {
                    final day = _weekdays[idx];
                    final label = _weekdayLabels[idx];
                    final isSelected = _selectedDays.contains(day);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            if (_selectedDays.length > 1) {
                              _selectedDays.remove(day);
                            }
                          } else {
                            _selectedDays.add(day);
                          }
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? primaryColor
                              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
              ],

              // Ends selector ("Bitiş")
              const Text('Bitiş', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),

              // Radio option 1: Never
              Row(
                children: [
                  Radio<String>(
                    value: 'NEVER',
                    groupValue: _endType,
                    onChanged: (val) {
                      if (val != null) setState(() => _endType = val);
                    },
                  ),
                  const Text('Hiçbir zaman', style: TextStyle(fontSize: 14)),
                ],
              ),

              // Radio option 2: On date
              Row(
                children: [
                  Radio<String>(
                    value: 'DATE',
                    groupValue: _endType,
                    onChanged: (val) {
                      if (val != null) setState(() => _endType = val);
                    },
                  ),
                  const Text('Şu tarihte: ', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      setState(() => _endType = 'DATE');
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _untilDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setState(() => _untilDate = picked);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      '${_untilDate.day} ${_getMonthsTurkish(_untilDate.month - 1)} ${_untilDate.year}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),

              // Radio option 3: Count
              Row(
                children: [
                  Radio<String>(
                    value: 'COUNT',
                    groupValue: _endType,
                    onChanged: (val) {
                      if (val != null) setState(() => _endType = val);
                    },
                  ),
                  const Text('Yinelenme sayısı: ', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    child: TextFormField(
                      initialValue: _count.toString(),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          setState(() {
                            _endType = 'COUNT';
                            _count = parsed;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('tekrar', style: TextStyle(fontSize: 14)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('iptal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'clear'),
          child: const Text('Temizle', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () {
            String rule = 'FREQ=$_freq;INTERVAL=$_interval';
            
            if (_freq == 'WEEKLY') {
              rule += ';BYDAY=${_selectedDays.join(',')}';
            } else if (_freq == 'MONTHLY') {
              rule += ';BYMONTHDAY=${widget.eventDate.day}';
            } else if (_freq == 'YEARLY') {
              rule += ';BYMONTH=${widget.eventDate.month};BYMONTHDAY=${widget.eventDate.day}';
            }

            if (_endType == 'COUNT') {
              rule += ';COUNT=$_count';
            } else if (_endType == 'DATE') {
              final yStr = _untilDate.year.toString().padLeft(4, '0');
              final mStr = _untilDate.month.toString().padLeft(2, '0');
              final dStr = _untilDate.day.toString().padLeft(2, '0');
              rule += ';UNTIL=${yStr}${mStr}${dStr}T235959Z';
            }

            Navigator.pop(context, rule);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text('Bitti'),
        ),
      ],
    );
  }

  String _getMonthsTurkish(int idx) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    if (idx >= 0 && idx < 12) return months[idx];
    return '';
  }
}
