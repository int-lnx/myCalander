import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/topic_plan.dart';
import '../utils/id_generator.dart';
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
  String _matrixDisplayMode = 'PERCENTAGE'; // 'PERCENTAGE', 'BRUT', 'NET', 'NOTE'

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

  void _showArchivedProjectsDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final archived = appState.projects.where((p) => p.isArchived).toList();
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.archive_outlined, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Arşivlenmiş Projeler'),
                ],
              ),
              content: SizedBox(
                width: 350,
                height: 400,
                child: archived.isEmpty
                    ? const Center(
                        child: Text(
                          'Arşivlenmiş proje bulunamadı.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: archived.length,
                        itemBuilder: (context, index) {
                          final proj = archived[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 8,
                              backgroundColor: Color(proj.colorValue),
                            ),
                            title: Text(proj.title),
                            subtitle: Text(proj.tag),
                            trailing: IconButton(
                              icon: const Icon(Icons.unarchive, color: Colors.green),
                              tooltip: 'Arşivden Çıkar',
                              onPressed: () {
                                final updated = proj.copyWith(isArchived: false);
                                appState.updateProject(updated);
                                setDialogState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('"${proj.title}" arşivden çıkarıldı.'),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final projects = appState.projects.where((p) => !p.isArchived).toList();
    final evaluations = appState.evaluations;
    final isDark = appState.isDarkMode;

    // Get current month days (newest to oldest)
    final monthDays = _getMonthDays(_focusedDate);
    final displayedDays = monthDays.reversed.toList();

    // Group projects by category
    final Map<String, List<Project>> categorizedProjects = {};
    for (var p in projects) {
      final category = p.tag.isNotEmpty ? p.tag : 'Genel';
      categorizedProjects.putIfAbsent(category, () => []).add(p);
    }

    final categories = categorizedProjects.keys.toList();

    // Get filter days based on selected time range
    List<DateTime> filterDays = [];
    if (_timeRange == 'Günlük') {
      filterDays = [DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day)];
    } else if (_timeRange == 'Haftalık') {
      filterDays = List.generate(7, (i) => DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day).subtract(Duration(days: 6 - i)));
    } else { // 'Aylık'
      filterDays = _getMonthDays(_focusedDate);
    }

    // Calculate total hours in the selected time range and value type
    double totalWeekHours = 0.0;
    final Map<Project, double> projectHours = {};

    for (var p in projects) {
      double projSum = 0.0;
      for (var day in filterDays) {
        if (_valueType == 'Yapılan' || _valueType == 'Toplam') {
          final ev = _getEvalForDay(evaluations, p.id, day);
          if (ev != null && !ev.isSkipped) {
            projSum += ev.durationHours;
          }
        }
        if (_valueType == 'Yapılacak' || _valueType == 'Toplam') {
          projSum += _getPlannedHoursForDay(appState.topicPlans, p.id, day);
        }
      }
      if (projSum > 0) {
        projectHours[p] = projSum;
        totalWeekHours += projSum;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zaman Takibi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Arşivlenmiş Projeler',
            onPressed: () => _showArchivedProjectsDialog(context, appState),
          ),
        ],
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
                        totalWeekHours > 0
                            ? projectHours.entries.map((entry) {
                                return PieChartSegment(
                                  color: Color(entry.key.colorValue),
                                  percentage: entry.value / totalWeekHours,
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
                        final proj = entry.key;
                        final value = entry.value;
                        final percentage = totalWeekHours > 0 ? (value / totalWeekHours) * 100 : 0.0;
                        return Text(
                          '${proj.title} %${percentage.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(proj.colorValue),
                          ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Unified Category Header Row
                    Row(
                      children: [
                        Container(
                          width: 85,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                            border: Border(
                              left: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                              top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                              bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                              right: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                            ),
                          ),
                          child: _buildHeaderCell('Kategori'),
                        ),
                        ...categories.map((cat) {
                          final projs = categorizedProjects[cat] ?? [];
                          final totalWidth = 55.0 * projs.length;
                          return Container(
                            width: totalWidth,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                              border: Border(
                                top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                                bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                                right: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                              ),
                            ),
                            child: _buildHeaderCell(cat),
                          );
                        }),
                      ],
                    ),
                    // Projects Matrix Table
                    Table(
                      columnWidths: const {
                        0: FixedColumnWidth(85),
                      },
                      defaultColumnWidth: const FixedColumnWidth(55),
                      border: TableBorder(
                        left: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                        right: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                        bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                        horizontalInside: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                        verticalInside: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                      ),
                      children: [
                        // Header Row: Projects / Subcategories
                        TableRow(
                          decoration: BoxDecoration(color: isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                          children: [
                            _buildModeSelectorCell(),
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
                                for (var day in monthDays) {
                                  final ev = _getEvalForDay(evaluations, p.id, day);
                                  if (ev != null && p.trackNetHours) {
                                    final pct = ev.performancePercent ?? ev.score;
                                    netSum += ev.durationHours * (pct / 100.0);
                                  }
                                }
                                return _buildValueCell(p.trackNetHours ? netSum.toStringAsFixed(1) : '-');
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
                                for (var day in monthDays) {
                                  final ev = _getEvalForDay(evaluations, p.id, day);
                                  if (ev != null && p.trackDuration) {
                                    brutSum += ev.durationHours;
                                  }
                                }
                                return _buildValueCell(p.trackDuration ? brutSum.toStringAsFixed(1) : '-');
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
                                for (var day in monthDays) {
                                  final ev = _getEvalForDay(evaluations, p.id, day);
                                  if (ev != null && p.trackDuration) {
                                    totalSum += ev.durationHours;
                                  }
                                }
                                return _buildValueCell(p.trackDuration ? totalSum.toStringAsFixed(1) : '-');
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
                                    return InkWell(
                                      onTap: () => _showEvaluationDialog(context, p, day),
                                      child: _buildValueCell('-'),
                                    );
                                  }
                                  // Format cell based on evaluation type and display mode
                                  String displayVal = '';
                                  if (ev.isSkipped) {
                                    int skipCount = 0;
                                    DateTime checkDate = DateTime(day.year, day.month, day.day);
                                    while (true) {
                                      ProjectEvaluation? checkEv;
                                      for (final e in evaluations) {
                                        if (e.projectId == p.id &&
                                            e.sessionDate.year == checkDate.year &&
                                            e.sessionDate.month == checkDate.month &&
                                            e.sessionDate.day == checkDate.day) {
                                          checkEv = e;
                                          break;
                                        }
                                      }
                                      if (checkEv != null && checkEv.isSkipped) {
                                        skipCount++;
                                        checkDate = checkDate.subtract(const Duration(days: 1));
                                      } else {
                                        break;
                                      }
                                    }
                                    displayVal = 'Pas $skipCount';
                                  } else {
                                    switch (_matrixDisplayMode) {
                                      case 'PERCENTAGE':
                                        if (p.trackPercentage) {
                                          final pct = ev.performancePercent ?? ev.score;
                                          displayVal = '%${pct.toStringAsFixed(0)}';
                                        } else {
                                          displayVal = '-';
                                        }
                                        break;
                                      case 'NUMERIC':
                                        if (p.trackNumeric) {
                                          displayVal = ev.score.toStringAsFixed(ev.score % 1 == 0 ? 0 : 1);
                                        } else {
                                          displayVal = '-';
                                        }
                                        break;
                                      case 'BRUT':
                                        if (p.trackDuration) {
                                          displayVal = ev.durationHours.toStringAsFixed(1);
                                        } else {
                                          displayVal = '-';
                                        }
                                        break;
                                      case 'NET':
                                        if (p.trackNetHours) {
                                          final pct = ev.performancePercent ?? ev.score;
                                          final netVal = ev.durationHours * (pct / 100.0);
                                          displayVal = netVal.toStringAsFixed(1);
                                        } else {
                                          displayVal = '-';
                                        }
                                        break;
                                      case 'NOTE':
                                        if (p.trackNote) {
                                          displayVal = (ev.note != null && ev.note!.isNotEmpty) ? ev.note! : '-';
                                        } else {
                                          displayVal = '-';
                                        }
                                        break;
                                    }
                                  }

                                  final cellBgColor = ev.isSkipped
                                      ? Colors.red.shade50
                                      : (ev.score >= 90 ? Colors.green.shade50 : Colors.orange.shade50);

                                  final cellWidget = Container(
                                    color: cellBgColor,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 2.0),
                                    child: Text(
                                      displayVal,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: ev.isSkipped
                                            ? Colors.red.shade700
                                            : (ev.score >= 90 ? Colors.green.shade700 : Colors.orange.shade700),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  );

                                  final wrappedCell = InkWell(
                                    onTap: () => _showEvaluationDialog(context, p, day),
                                    child: cellWidget,
                                  );

                                  if (ev.note != null && ev.note!.isNotEmpty) {
                                    return Tooltip(
                                      message: ev.note!,
                                      child: wrappedCell,
                                    );
                                  }
                                  return wrappedCell;
                                });
                              }),
                            ],
                          );
                        }),
                      ],
                    ),
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

  double _getPlannedHoursForDay(List<TopicPlan> plans, String projectId, DateTime day) {
    double sum = 0.0;
    final normalizedDay = DateTime(day.year, day.month, day.day);
    for (var plan in plans) {
      if (plan.projectId == projectId) {
        final start = DateTime(plan.startDate.year, plan.startDate.month, plan.startDate.day);
        final end = DateTime(plan.endDate.year, plan.endDate.month, plan.endDate.day);
        if (normalizedDay.isAtSameMomentAs(start) || 
            normalizedDay.isAtSameMomentAs(end) || 
            (normalizedDay.isAfter(start) && normalizedDay.isBefore(end))) {
          final totalDays = end.difference(start).inDays + 1;
          if (totalDays > 0) {
            sum += plan.targetHours / totalDays;
          }
        }
      }
    }
    return sum;
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

  Widget _buildModeSelectorCell() {
    IconData icon;
    String tooltip;
    Color iconColor;

    switch (_matrixDisplayMode) {
      case 'PERCENTAGE':
        icon = Icons.percent;
        tooltip = 'Yüzdesel Başarı';
        iconColor = Colors.blue;
        break;
      case 'NUMERIC':
        icon = Icons.numbers;
        tooltip = 'Sayısal Değer';
        iconColor = Colors.teal;
        break;
      case 'BRUT':
        icon = Icons.hourglass_bottom;
        tooltip = 'Süre Girdisi (Saat)';
        iconColor = Colors.orange;
        break;
      case 'NET':
        icon = Icons.hourglass_full;
        tooltip = 'Net Çalışma Saati';
        iconColor = Colors.green;
        break;
      case 'NOTE':
        icon = Icons.chat;
        tooltip = 'Günlük Notlar';
        iconColor = Colors.purple;
        break;
      default:
        icon = Icons.percent;
        tooltip = 'Yüzdesel Başarı';
        iconColor = Colors.blue;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_matrixDisplayMode == 'PERCENTAGE') {
              _matrixDisplayMode = 'NUMERIC';
            } else if (_matrixDisplayMode == 'NUMERIC') {
              _matrixDisplayMode = 'BRUT';
            } else if (_matrixDisplayMode == 'BRUT') {
              _matrixDisplayMode = 'NET';
            } else if (_matrixDisplayMode == 'NET') {
              _matrixDisplayMode = 'NOTE';
            } else {
              _matrixDisplayMode = 'PERCENTAGE';
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(4.0),
          alignment: Alignment.center,
          height: 48,
          child: Icon(
            icon,
            size: 20,
            color: iconColor,
          ),
        ),
      ),
    );
  }

  Widget _buildProjectHeaderCell(Project p) {
    final appState = Provider.of<AppState>(context, listen: false);
    final categoryColor = appState.getEventTagColor(p.tag) ?? appState.getTaskTagColor(p.tag) ?? 0xFF9E9E9E;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                p.title,
                style: TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 11,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                  decoration: TextDecoration.none,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            CircleAvatar(radius: 4, backgroundColor: Color(categoryColor)),
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

  void _showEvaluationDialog(BuildContext context, Project project, DateTime date) {
    final appState = Provider.of<AppState>(context, listen: false);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    
    final existingEval = appState.evaluations.firstWhere(
      (e) => e.projectId == project.id && 
             e.sessionDate.year == normalizedDate.year &&
             e.sessionDate.month == normalizedDate.month &&
             e.sessionDate.day == normalizedDate.day,
      orElse: () => ProjectEvaluation(
        id: '',
        projectId: project.id,
        sessionDate: normalizedDate,
        score: 0,
        isSkipped: false,
        durationHours: 0,
      ),
    );

    final percentCtrl = TextEditingController(
      text: existingEval.id.isNotEmpty && !existingEval.isSkipped
          ? (existingEval.performancePercent ?? existingEval.score).toStringAsFixed(0)
          : (project.defaultPercentage?.toStringAsFixed(0) ?? ''),
    );
    final numericCtrl = TextEditingController(
      text: existingEval.id.isNotEmpty && !existingEval.isSkipped
          ? existingEval.score.toStringAsFixed(existingEval.score % 1 == 0 ? 0 : 1)
          : (project.defaultNumeric?.toString() ?? ''),
    );
    final hoursCtrl = TextEditingController(
      text: existingEval.id.isNotEmpty && !existingEval.isSkipped
          ? existingEval.durationHours.toInt().toString()
          : (project.defaultDuration?.toInt().toString() ?? ''),
    );
    final minutesCtrl = TextEditingController(
      text: existingEval.id.isNotEmpty && !existingEval.isSkipped
          ? ((existingEval.durationHours - existingEval.durationHours.toInt()) * 60).round().toString()
          : (project.defaultDuration != null
              ? ((project.defaultDuration! - project.defaultDuration!.toInt()) * 60).round().toString()
              : ''),
    );
    final noteCtrl = TextEditingController(text: existingEval.note ?? '');
    bool isSkipped = existingEval.id.isNotEmpty ? existingEval.isSkipped : false;

    showDialog(
      context: context,
      builder: (context) {
        DateTime selectedDate = normalizedDate;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('${project.title} Değerlendirmesi'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            selectedDate = DateTime(picked.year, picked.month, picked.day);
                          });
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_month, size: 16, color: Colors.blue),
                            const SizedBox(width: 6),
                            Text(
                              "${selectedDate.day}/${selectedDate.month}/${selectedDate.year} tarihli oturum",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Bugünü Boş Geç (Pas)'),
                      value: isSkipped,
                      onChanged: (v) {
                        setState(() => isSkipped = v);
                      },
                    ),
                    if (!isSkipped) ...[
                      if (project.trackPercentage) ...[
                        TextField(
                          controller: percentCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Başarı Yüzdesi (%)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (project.trackNumeric) ...[
                        TextField(
                          controller: numericCtrl,
                          decoration: InputDecoration(
                            labelText: 'Elde Edilen Sayı (Hedef: ${project.targetValue})',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (project.trackDuration) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: hoursCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Saat',
                                  suffixText: 'saat',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: minutesCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Dakika',
                                  suffixText: 'dk',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                    if (project.trackNote) ...[
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Not Ekle',
                          hintText: 'Oturumla ilgili notlar yazın...',
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (existingEval.id.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      appState.deleteEvaluation(project.id, normalizedDate);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Sil',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    double score = 0.0;
                    double? pctVal;

                    if (!isSkipped) {
                      if (project.trackNumeric) {
                        score = double.tryParse(numericCtrl.text) ?? 0.0;
                      }
                      if (project.trackPercentage) {
                        final pVal = double.tryParse(percentCtrl.text) ?? 0.0;
                        pctVal = pVal;
                        if (!project.trackNumeric) {
                          score = pVal;
                        }
                      }
                    }

                    int hrs = int.tryParse(hoursCtrl.text) ?? 0;
                    int mins = int.tryParse(minutesCtrl.text) ?? 0;
                    double duration = hrs + (mins / 60.0);
                    if (duration < 0.0) duration = 0.0;

                    // Calculate skip count if skipped
                    double finalScore = score;
                    if (isSkipped) {
                      int skipCount = 1; // starts at 1 for current day
                      DateTime checkDate = normalizedDate.subtract(const Duration(days: 1));
                      while (true) {
                        ProjectEvaluation? checkEv;
                        for (final e in appState.evaluations) {
                          if (e.projectId == project.id &&
                              e.sessionDate.year == checkDate.year &&
                              e.sessionDate.month == checkDate.month &&
                              e.sessionDate.day == checkDate.day) {
                            checkEv = e;
                            break;
                          }
                        }
                        if (checkEv != null && checkEv.isSkipped) {
                          skipCount++;
                          checkDate = checkDate.subtract(const Duration(days: 1));
                        } else {
                          break;
                        }
                      }
                      finalScore = skipCount.toDouble();
                    }

                    // If date changed, delete the old evaluation
                    if (existingEval.id.isNotEmpty &&
                        (selectedDate.year != normalizedDate.year ||
                         selectedDate.month != normalizedDate.month ||
                         selectedDate.day != normalizedDate.day)) {
                      appState.deleteEvaluation(project.id, normalizedDate);
                    }

                    final eval = ProjectEvaluation(
                      id: existingEval.id.isNotEmpty &&
                          (selectedDate.year == normalizedDate.year &&
                           selectedDate.month == normalizedDate.month &&
                           selectedDate.day == normalizedDate.day)
                          ? existingEval.id
                          : IdGenerator.generate(
                              "degerlendirme_${project.title}",
                              date: selectedDate,
                            ),
                      projectId: project.id,
                      sessionDate: selectedDate,
                      score: isSkipped ? finalScore : score,
                      isSkipped: isSkipped,
                      durationHours: (isSkipped || !project.trackDuration) ? 0.0 : duration,
                      note: (project.trackNote && noteCtrl.text.trim().isNotEmpty) ? noteCtrl.text.trim() : null,
                      performancePercent: pctVal,
                    );
                    
                    appState.addOrUpdateEvaluation(eval);
                    Navigator.pop(context);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
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
