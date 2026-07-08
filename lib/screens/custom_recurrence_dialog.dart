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

  @override
  void initState() {
    super.initState();
    _freq = 'DAILY';
    _interval = 1;

    final rule = widget.initialRRule;
    if (rule != null && rule.isNotEmpty) {
      if (rule.contains('FREQ=DAILY')) _freq = 'DAILY';
      if (rule.contains('FREQ=WEEKLY')) _freq = 'WEEKLY';
      if (rule.contains('FREQ=MONTHLY')) _freq = 'MONTHLY';
      if (rule.contains('FREQ=YEARLY')) _freq = 'YEARLY';

      final match = RegExp(r'INTERVAL=(\d+)').firstMatch(rule);
      if (match != null) {
        _interval = int.tryParse(match.group(1) ?? '1') ?? 1;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tekrarlama Ayarı'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _freq,
            decoration: const InputDecoration(labelText: 'Sıklık'),
            items: const [
              DropdownMenuItem(value: 'DAILY', child: Text('Her gün')),
              DropdownMenuItem(value: 'WEEKLY', child: Text('Her hafta')),
              DropdownMenuItem(value: 'MONTHLY', child: Text('Her ay')),
              DropdownMenuItem(value: 'YEARLY', child: Text('Her yıl')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _freq = val);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _interval.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Aralık',
              hintText: 'Örn: 2 (2 periyotta bir tekrar eder)',
            ),
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null && parsed > 0) {
                _interval = parsed;
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'clear'),
          child: const Text('Temizle', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () {
            String rule = 'FREQ=$_freq;INTERVAL=$_interval';
            // weekly / monthly / yearly standard format
            if (_freq == 'WEEKLY') {
              const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
              rule += ';BYDAY=${days[widget.eventDate.weekday - 1]}';
            } else if (_freq == 'MONTHLY') {
              rule += ';BYMONTHDAY=${widget.eventDate.day}';
            } else if (_freq == 'YEARLY') {
              rule +=
                  ';BYMONTH=${widget.eventDate.month};BYMONTHDAY=${widget.eventDate.day}';
            }
            Navigator.pop(context, rule);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
