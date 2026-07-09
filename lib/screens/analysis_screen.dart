import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/event.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  DateTime _focusedDate = DateTime.now();
  String _timeRange = 'Haftalık'; // 'Günlük', 'Haftalık', 'Aylık'

  List<DateTime> _getMonthDays(DateTime date) {
    return List.generate(30, (i) => DateTime(date.year, date.month, date.day).subtract(Duration(days: 29 - i)));
  }

  String _formatMonthRange(List<DateTime> days) {
    final start = days.first;
    final end = days.last;
    final months = [
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return '${start.day} ${months[start.month]} ${start.year}';
    }
    if (start.month == end.month) {
      return '${start.day} - ${end.day} ${months[start.month]} ${start.year}';
    } else {
      return '${start.day} ${months[start.month]} - ${end.day} ${months[end.month]} ${start.year}';
    }
  }

  double _getEventHoursForDay(Event e, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day, 0, 0, 0);
    final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
    
    if (e.to.isBefore(dayStart) || e.from.isAfter(dayEnd)) {
      return 0.0;
    }
    
    final start = e.from.isBefore(dayStart) ? dayStart : e.from;
    final end = e.to.isAfter(dayEnd) ? dayEnd : e.to;
    
    return end.difference(start).inMinutes / 60.0;
  }

  double _getCategoryHoursForDay(List<Event> events, String category, DateTime day) {
    double sum = 0.0;
    for (var e in events) {
      final cat = e.tag.isNotEmpty ? e.tag : 'Genel';
      if (cat == category) {
        sum += _getEventHoursForDay(e, day);
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final events = appState.events;
    final isDark = appState.isDarkMode;
    final categories = appState.eventTags;

    // Get filter days based on selected time range
    List<DateTime> filterDays = [];
    if (_timeRange == 'Günlük') {
      filterDays = [DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day)];
    } else if (_timeRange == 'Haftalık') {
      filterDays = List.generate(7, (i) => DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day).subtract(Duration(days: 6 - i)));
    } else { // 'Aylık'
      filterDays = _getMonthDays(_focusedDate);
    }
    final displayedDays = filterDays.reversed.toList();

    // Calculate total hours per category in selected range
    final Map<String, double> categoryHours = {};
    double totalHours = 0.0;
    for (var cat in categories) {
      double catSum = 0.0;
      for (var day in filterDays) {
        catSum += _getCategoryHoursForDay(events, cat, day);
      }
      if (catSum > 0) {
        categoryHours[cat] = catSum;
        totalHours += catSum;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlik Analizi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Date Picker & Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 16),
                    onPressed: () {
                      setState(() {
                        int days = 30;
                        if (_timeRange == 'Günlük') days = 1;
                        if (_timeRange == 'Haftalık') days = 7;
                        _focusedDate = _focusedDate.subtract(Duration(days: days));
                      });
                    },
                  ),
                  Text(
                    _formatMonthRange(filterDays),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: () {
                      setState(() {
                        int days = 30;
                        if (_timeRange == 'Günlük') days = 1;
                        if (_timeRange == 'Haftalık') days = 7;
                        _focusedDate = _focusedDate.add(Duration(days: days));
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_month, color: Colors.blue),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _focusedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _focusedDate = picked);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Circle Chart Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Pie Chart representation
                  Center(
                    child: CustomPaint(
                      painter: PieChartPainter(
                        totalHours > 0
                            ? categoryHours.entries.map((entry) {
                                final catColor = appState.getEventTagColor(entry.key) ?? 0xFF2196F3;
                                return PieChartSegment(
                                  color: Color(catColor),
                                  percentage: entry.value / totalHours,
                                );
                              }).toList()
                            : [PieChartSegment(color: Colors.grey.shade400, percentage: 1.0)],
                      ),
                      child: Container(
                        width: 140,
                        height: 140,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Toplam',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            Text(
                              '${totalHours.toStringAsFixed(1)} sa',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (categoryHours.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: categoryHours.entries.map((entry) {
                        final cat = entry.key;
                        final value = entry.value;
                        final percentage = totalHours > 0 ? (value / totalHours) * 100 : 0.0;
                        final catColor = appState.getEventTagColor(cat) ?? 0xFF2196F3;
                        return Text(
                          '$cat %${percentage.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(catColor),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Pill Filters: Daily, Weekly, Monthly
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['Günlük', 'Haftalık', 'Aylık'].map((label) {
                      final isSelected = _timeRange == label;
                      return GestureDetector(
                        onTap: () => setState(() => _timeRange = label),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.shade100 : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? Colors.blue : Colors.transparent),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected ? Colors.blue.shade800 : (isDark ? Colors.white70 : Colors.black87),
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Scrollable Grid Table for Event Category Matrix
          if (categories.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: Text('Herhangi bir kategori bulunmuyor.')),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Table(
                    columnWidths: {
                      0: const FixedColumnWidth(85),
                      for (int i = 0; i < categories.length; i++)
                        i + 1: const FixedColumnWidth(95),
                    },
                    border: TableBorder(
                      left: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      right: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      horizontalInside: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      verticalInside: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                    ),
                    children: [
                      // Header Row
                      TableRow(
                        decoration: BoxDecoration(color: isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                        children: [
                          _buildHeaderCell('Tarih'),
                          ...categories.map((cat) => _buildHeaderCell(cat)),
                        ],
                      ),

                      // Total Row
                      TableRow(
                        children: [
                          _buildRowLabel('Toplam Süre'),
                          ...categories.map((cat) {
                            final hours = categoryHours[cat] ?? 0.0;
                            return _buildValueCell('${hours.toStringAsFixed(1)} sa');
                          }),
                        ],
                      ),

                      // Individual Days Rows
                      ...displayedDays.map((day) {
                        final months = [
                          '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
                        ];
                        final dateLabel = '${day.day} ${months[day.month]}';

                        return TableRow(
                          children: [
                            _buildRowLabel(dateLabel, isBold: true),
                            ...categories.map((cat) {
                              final hours = _getCategoryHoursForDay(events, cat, day);
                              return _buildValueCell(hours > 0 ? '${hours.toStringAsFixed(1)} sa' : '-');
                            }),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildRowLabel(String text, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
          color: Colors.blueGrey,
        ),
      ),
    );
  }

  Widget _buildValueCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class PieChartSegment {
  final Color color;
  final double percentage;

  PieChartSegment({required this.color, required this.percentage});
}

class PieChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;

  PieChartPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -3.141592653589793 / 2; // Start from top (-90 degrees)

    for (final segment in segments) {
      final sweepAngle = segment.percentage * 2 * 3.141592653589793;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = segment.color
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
