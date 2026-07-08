import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import 'project_details_screen.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  DateTime _focusedDate = DateTime.now();
  String _timeRange = 'Haftalık'; // 'Günlük', 'Haftalık', 'Aylık'
  String _valueType = 'Yapılan'; // 'Yapılan', 'Yapılacak', 'Toplam'

  List<DateTime> _getWeekDays(DateTime date) {
    // Find the Monday of the week containing the date
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return List.generate(7, (i) => DateTime(monday.year, monday.month, monday.day).add(Duration(days: i)));
  }

  String _formatWeekRange(List<DateTime> days) {
    final start = days.first;
    final end = days.last;
    final months = [
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    return '${start.day} - ${end.day} ${months[start.month]} ${start.year}';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final projects = appState.projects;
    final evaluations = appState.evaluations;
    final isDark = appState.isDarkMode;

    // Get current week days (newest to oldest as shown in the screenshot: 7 Tem down to 1 Tem)
    final weekDays = _getWeekDays(_focusedDate);
    final displayedDays = weekDays.reversed.toList();

    // Group projects by category
    final Map<String, List<Project>> categorizedProjects = {};
    for (var p in projects) {
      final category = p.tag.isNotEmpty ? p.tag : 'Genel';
      categorizedProjects.putIfAbsent(category, () => []).add(p);
    }

    final categories = categorizedProjects.keys.toList();

    // Calculate total hours in the current week
    double totalWeekHours = 0.0;
    final Map<String, double> projectHours = {};

    for (var p in projects) {
      double projSum = 0.0;
      for (var day in weekDays) {
        final ev = _getEvalForDay(evaluations, p.id, day);
        if (ev != null) {
          projSum += ev.durationHours;
        }
      }
      if (projSum > 0) {
        projectHours[p.title] = projSum;
        totalWeekHours += projSum;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zaman Takibi'),
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
                        _focusedDate = _focusedDate.subtract(const Duration(days: 7));
                      });
                    },
                  ),
                  Text(
                    _formatWeekRange(weekDays),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: () {
                      setState(() {
                        _focusedDate = _focusedDate.add(const Duration(days: 7));
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
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orange.shade400, width: 14),
                      ),
                      child: Center(
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
                              '${totalWeekHours.toStringAsFixed(1)} sa',
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
                  if (projectHours.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: projectHours.entries.map((entry) {
                        final percentage = totalWeekHours > 0 ? (entry.value / totalWeekHours) * 100 : 0.0;
                        return Text(
                          '${entry.key} %${percentage.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Pill Filters Row 1: Daily, Weekly, Monthly
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
                  const SizedBox(height: 8),

                  // Pill Filters Row 2: Yapılan, Yapılacak, Toplam
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['Yapılan', 'Yapılacak', 'Toplam'].map((label) {
                      final isSelected = _valueType == label;
                      return GestureDetector(
                        onTap: () => setState(() => _valueType = label),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.purple.shade100 : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? Colors.purple : Colors.transparent),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected ? Colors.purple.shade800 : (isDark ? Colors.white70 : Colors.black87),
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

          // Scrollable Grid Table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(100),
                  border: TableBorder.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                  children: [
                    // Header Row 1: Categories
                    TableRow(
                      decoration: BoxDecoration(color: isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                      children: [
                        _buildHeaderCell('Kategori'),
                        ...categories.expand((cat) {
                          final projs = categorizedProjects[cat] ?? [];
                          return List.generate(projs.length, (i) => i == 0 ? _buildHeaderCell(cat) : const SizedBox());
                        }),
                      ],
                    ),
                    // Header Row 2: Projects / Subcategories
                    TableRow(
                      decoration: BoxDecoration(color: isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                      children: [
                        _buildHeaderCell('Proje'),
                        ...categories.expand((cat) {
                          final projs = categorizedProjects[cat] ?? [];
                          return projs.map((p) => _buildProjectHeaderCell(p));
                        }),
                      ],
                    ),
                    // Net Row
                    TableRow(
                      children: [
                        _buildRowLabel('Net'),
                        ...categories.expand((cat) {
                          final projs = categorizedProjects[cat] ?? [];
                          return projs.map((p) {
                            double netSum = 0.0;
                            for (var day in weekDays) {
                              final ev = _getEvalForDay(evaluations, p.id, day);
                              if (ev != null) {
                                netSum += ev.durationHours * (ev.score / 100.0);
                              }
                            }
                            return _buildValueCell('${netSum.toStringAsFixed(1)} sa');
                          });
                        }),
                      ],
                    ),
                    // Brüt Row
                    TableRow(
                      children: [
                        _buildRowLabel('Brüt'),
                        ...categories.expand((cat) {
                          final projs = categorizedProjects[cat] ?? [];
                          return projs.map((p) {
                            double brutSum = 0.0;
                            for (var day in weekDays) {
                              final ev = _getEvalForDay(evaluations, p.id, day);
                              if (ev != null) {
                                brutSum += ev.durationHours;
                              }
                            }
                            return _buildValueCell('${brutSum.toStringAsFixed(1)} sa');
                          });
                        }),
                      ],
                    ),
                    // Toplam Row
                    TableRow(
                      children: [
                        _buildRowLabel('Toplam'),
                        ...categories.expand((cat) {
                          final projs = categorizedProjects[cat] ?? [];
                          return projs.map((p) {
                            double totalSum = 0.0;
                            for (var day in weekDays) {
                              final ev = _getEvalForDay(evaluations, p.id, day);
                              if (ev != null) {
                                totalSum += ev.durationHours;
                              }
                            }
                            return _buildValueCell('${totalSum.toStringAsFixed(1)} sa');
                          });
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
                          ...categories.expand((cat) {
                            final projs = categorizedProjects[cat] ?? [];
                            return projs.map((p) {
                              final ev = _getEvalForDay(evaluations, p.id, day);
                              if (ev == null) {
                                return _buildValueCell('-');
                              }
                              // Format cell based on evaluation type
                              String displayVal = '';
                              if (ev.isSkipped) {
                                displayVal = 'Pas ${ev.score.toStringAsFixed(0)}';
                              } else if (p.evaluationType == 'PERCENTAGE') {
                                displayVal = '%${ev.score.toStringAsFixed(0)}';
                              } else {
                                displayVal = ev.score.toStringAsFixed(0);
                              }

                              final cellBgColor = ev.isSkipped
                                  ? Colors.red.shade50
                                  : (ev.score >= 90 ? Colors.green.shade50 : Colors.orange.shade50);

                              return Container(
                                color: cellBgColor,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  displayVal,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: ev.isSkipped
                                        ? Colors.red.shade700
                                        : (ev.score >= 90 ? Colors.green.shade700 : Colors.orange.shade700),
                                  ),
                                ),
                              );
                            });
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

  ProjectEvaluation? _getEvalForDay(List<ProjectEvaluation> evaluations, String projectId, DateTime day) {
    for (var e in evaluations) {
      if (e.projectId == projectId &&
          e.sessionDate.year == day.year &&
          e.sessionDate.month == day.month &&
          e.sessionDate.day == day.day) {
        return e;
      }
    }
    return null;
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildProjectHeaderCell(Project p) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectDetailsScreen(project: p),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(radius: 4, backgroundColor: Color(p.colorValue)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                p.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
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
