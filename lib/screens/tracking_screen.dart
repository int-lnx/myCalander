import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import 'project_details_screen.dart';
import '../dialogs/project_evaluation_dialog.dart';

class _TrackingDisplayItem {
  final Project project;
  final bool isChild;
  final Project? parent;

  _TrackingDisplayItem({
    required this.project,
    required this.isChild,
    this.parent,
  });
}

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  DateTime _focusedDate = DateTime.now();
  int _matrixDisplayIndex = 0; // 0: Yüzde, 1: Notlar

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
    final isDark = appState.isDarkMode;

    // Get current month days (newest to oldest)
    final monthDays = _getMonthDays(_focusedDate);
    final displayedDays = monthDays.reversed.toList();

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
                        _focusedDate = _focusedDate.subtract(const Duration(days: 30));
                      });
                    },
                  ),
                  Text(
                    _formatMonthRange(monthDays),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: () {
                      setState(() {
                        _focusedDate = _focusedDate.add(const Duration(days: 30));
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

          // Scrollable Grid Table (Horizontal View)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(24),  // Category name column (rotated vertically)
                    1: FixedColumnWidth(110), // Project name column width
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
                    // Header Row: Category | [Mode Selector] | Day 1 | Day 2 | ...
                    TableRow(
                      decoration: BoxDecoration(color: isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                      children: [
                        Container(
                          height: 40,
                          alignment: Alignment.center,
                          child: const Icon(Icons.category, size: 12, color: Colors.grey),
                        ),
                        _buildModeSelectorCell(),
                        ...displayedDays.map((day) {
                          const months = [
                            '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
                          ];
                          const weekdays = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
                          final dateLabel = '${day.day} ${months[day.month]}';
                          return _buildHeaderCell(dateLabel, subtitle: weekdays[day.weekday]);
                        }),
                      ],
                    ),
                    // Grouped Project Rows
                    ...() {
                      // Group projects by category
                      final Map<String, List<Project>> grouped = {};
                      for (var p in projects) {
                        final cat = p.tag.isNotEmpty ? p.tag : 'Genel';
                        grouped.putIfAbsent(cat, () => []).add(p);
                      }

                      final List<TableRow> rows = [];
                      grouped.forEach((category, projList) {
                        // Hiyerarşik ve tekrarlı sıralama:
                        // Bir üst proje varsa, hemen altına childProjectIds'de yer alan projeler eklenir.
                        // Bir alt proje 2 farklı üst projeye eklenmişse her iki üst projenin de altında listelenir.
                        // Üst projelere bağlı olmayan bağımsız projeler de kendi başlarına listelenir.

                        final List<_TrackingDisplayItem> orderedItems = [];
                        final parentProjects = projList.where((p) => p.isParentProject).toList();
                        final Set<String> childProjectIdsInThisCategory = {};

                        for (var parentP in parentProjects) {
                          orderedItems.add(_TrackingDisplayItem(project: parentP, isChild: false));

                          // Bu üst projeye bağlı olan alt projeleri tüm projeler havuzundan bul (veya bu kategoriden)
                          for (var childId in parentP.childProjectIds) {
                            final childProj = projects.where((p) => p.id == childId).firstOrNull;
                            if (childProj != null) {
                              orderedItems.add(_TrackingDisplayItem(project: childProj, isChild: true, parent: parentP));
                              childProjectIdsInThisCategory.add(childId);
                            }
                          }
                        }

                        // Üst proje olmayan normal projelerden, hiçbir üst projeye bağlı olmayanlar
                        // VEYA bağımsız olarak kendi yerinde de görünsün istenenler:
                        final nonParentProjects = projList.where((p) => !p.isParentProject).toList();
                        for (var p in nonParentProjects) {
                          // Eğer bir üst projede gösterilmediyse bağımsız olarak listele
                          if (!childProjectIdsInThisCategory.contains(p.id)) {
                            orderedItems.add(_TrackingDisplayItem(project: p, isChild: false));
                          }
                        }

                        for (int i = 0; i < orderedItems.length; i++) {
                          final item = orderedItems[i];
                          final p = item.project;
                          final isFirst = i == 0;
                          final categoryColorVal = appState.getEventTagColor(p.tag) ?? appState.getTaskTagColor(p.tag) ?? 0xFF9E9E9E;
                          final isChild = item.isChild;
                          final isParent = p.isParentProject;

                          rows.add(
                            TableRow(
                              children: [
                                // Category Name Rotated Vertically
                                Container(
                                  height: 40,
                                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                                  alignment: Alignment.center,
                                  child: isFirst
                                      ? RotatedBox(
                                          quarterTurns: 3,
                                          child: Text(
                                            category,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Color(categoryColorVal),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                // Project Name with Hierarchy Design
                                InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ProjectDetailsScreen(project: p),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    height: 40,
                                    padding: EdgeInsets.only(
                                      left: isChild ? 16.0 : 8.0,
                                      right: 8.0,
                                      top: 4.0,
                                      bottom: 4.0,
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      children: [
                                        if (isChild) ...[
                                          Icon(
                                            Icons.subdirectory_arrow_right,
                                            size: 13,
                                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Color(categoryColorVal), width: 1.5),
                                            ),
                                          ),
                                        ] else if (isParent) ...[
                                          Icon(
                                            Icons.folder_open,
                                            size: 15,
                                            color: Color(categoryColorVal),
                                          ),
                                        ] else ...[
                                          CircleAvatar(radius: 4, backgroundColor: Color(categoryColorVal)),
                                        ],
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            p.title,
                                            style: TextStyle(
                                              fontSize: isChild ? 10.5 : 11,
                                              fontWeight: isParent ? FontWeight.bold : (isChild ? FontWeight.normal : FontWeight.bold),
                                              color: isChild ? (isDark ? Colors.grey.shade300 : Colors.grey.shade800) : null,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Day cells
                                ...displayedDays.map((day) {
                                  final ev = _getMergedEvalForDay(appState, p, day);
                                  if (ev == null) {
                                    return InkWell(
                                      onTap: () => _showEvaluationDialog(context, p, day),
                                      child: _buildValueCell('-'),
                                    );
                                  }

                                  String displayVal = '';
                                  if (ev.isSkipped) {
                                    final count = appState.getPasCount(p.id, ev.sessionDate);
                                    displayVal = 'Pas $count';
                                  } else {
                                    displayVal = _getDisplayValueForProject(p, ev, _matrixDisplayIndex);
                                  }

                                  final cellBgColor = ev.isSkipped
                                      ? (isDark ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.red.shade50)
                                      : (ev.score >= 90 
                                          ? (isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50) 
                                          : (isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50));

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

                                  return InkWell(
                                    onTap: () => _showEvaluationDialog(context, p, day),
                                    child: ev.note != null && ev.note!.isNotEmpty
                                        ? Tooltip(
                                            message: ev.note!,
                                            child: cellWidget,
                                          )
                                        : cellWidget,
                                  );
                                }),
                              ],
                            ),
                          );
                        }
                      });
                      return rows;
                    }(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ProjectEvaluation? _getMergedEvalForDay(AppState appState, Project p, DateTime day) {
    // 1. Bu projeye ait doğrudan değerlendirme
    final originalEval = _getEvalForDay(appState.evaluations, p.id, day);

    // 2. Bu projeye ait görev/topic planları
    final dayKey = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final projectPlans = appState.topicPlans.where((tp) => tp.projectId == p.id).toList();
    
    double totalTaskHours = 0.0;
    final List<String> taskNotes = [];
    bool hasAnyTaskLog = false;
    
    for (var tp in projectPlans) {
      final report = tp.dayReports[dayKey];
      if (report != null) {
        if (report.hoursWorked > 0) {
          totalTaskHours += report.hoursWorked;
          hasAnyTaskLog = true;
        }
        if (report.note.isNotEmpty) {
          taskNotes.add(report.note);
          hasAnyTaskLog = true;
        }
      }
    }

    // 3. Alt projelerin kontrolü (Eğer bu bir Üst Proje ise)
    final childProjects = p.isParentProject
        ? appState.projects.where((child) => p.childProjectIds.contains(child.id) && !child.isArchived).toList()
        : <Project>[];
    final List<ProjectEvaluation> childEvals = [];

    for (var child in childProjects) {
      final childEval = _getMergedEvalForDay(appState, child, day);
      if (childEval != null && !childEval.isSkipped) {
        childEvals.add(childEval);
      }
    }

    if (originalEval == null && !hasAnyTaskLog && childEvals.isEmpty) {
      return null;
    }

    // Süre hesabı: Kendi saatleri + alt projelerin saatleri
    double childHours = childEvals.fold(0.0, (sum, ev) => sum + ev.durationHours);
    double mergedHours = (originalEval?.durationHours ?? 0.0) + totalTaskHours + childHours;
    
    // Notlar
    final List<String> allNotes = [];
    if (originalEval?.note != null && originalEval!.note!.isNotEmpty) {
      allNotes.add(originalEval.note!);
    }
    allNotes.addAll(taskNotes);
    for (var ce in childEvals) {
      if (ce.note != null && ce.note!.isNotEmpty) {
        allNotes.add(ce.note!);
      }
    }
    String mergedNote = allNotes.join(', ');

    // Skor / Başarı / Yüzde hesabı:
    // Eğer alt projeler varsa, üst projenin skoru kullanıcının seçtiği aggregation'a göre alt projelerden türetilir:
    double finalScore = originalEval?.score ?? 0.0;
    double? finalPerformancePercent = originalEval?.performancePercent;

    if (childEvals.isNotEmpty) {
      final scores = childEvals.map((e) => e.score).toList();
      final pcts = childEvals.where((e) => e.performancePercent != null).map((e) => e.performancePercent!).toList();

      switch (p.subProjectAggregation) {
        case 'MIN':
          finalScore = scores.reduce((a, b) => a < b ? a : b);
          if (pcts.isNotEmpty) {
            finalPerformancePercent = pcts.reduce((a, b) => a < b ? a : b);
          }
          break;
        case 'AVG':
          finalScore = scores.reduce((a, b) => a + b) / scores.length;
          if (pcts.isNotEmpty) {
            finalPerformancePercent = pcts.reduce((a, b) => a + b) / pcts.length;
          }
          break;
        case 'MAX':
        default:
          finalScore = scores.reduce((a, b) => a > b ? a : b);
          if (pcts.isNotEmpty) {
            finalPerformancePercent = pcts.reduce((a, b) => a > b ? a : b);
          }
          break;
      }
    }

    return ProjectEvaluation(
      id: originalEval?.id ?? 'merged_${p.id}_${day.millisecondsSinceEpoch}',
      projectId: p.id,
      sessionDate: day,
      score: finalScore,
      isSkipped: originalEval?.isSkipped ?? false,
      durationHours: mergedHours,
      note: mergedNote,
      performancePercent: finalPerformancePercent,
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

  Widget _buildHeaderCell(String text, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.normal),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  String _getDisplayValueForProject(Project p, ProjectEvaluation ev, int slotIndex) {
    if (slotIndex == 0) {
      final isMergedDummy = ev.id.startsWith('merged_') && ev.score == 0;
      if (isMergedDummy && ev.durationHours > 0) {
        return '${ev.durationHours.toStringAsFixed(ev.durationHours % 1 == 0 ? 0 : 1)} sa';
      }
      if (p.trackPercentage || ev.performancePercent != null) {
        final pct = ev.performancePercent ?? ev.score;
        return '%${pct.toStringAsFixed(0)}';
      } else if (p.trackNumeric) {
        return ev.score.toStringAsFixed(ev.score % 1 == 0 ? 0 : 1);
      } else if (p.trackDuration) {
        return '${ev.durationHours.toStringAsFixed(ev.durationHours % 1 == 0 ? 0 : 1)} sa';
      }
      return '-';
    } else {
      return (ev.note != null && ev.note!.isNotEmpty) ? ev.note! : '-';
    }
  }

  Widget _buildModeSelectorCell() {
    final isPercentage = _matrixDisplayIndex == 0;
    return Tooltip(
      message: 'Görünümü Değiştir (Yüzde / Not)',
      child: InkWell(
        onTap: () {
          setState(() {
            _matrixDisplayIndex = _matrixDisplayIndex == 0 ? 1 : 0;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(4.0),
          alignment: Alignment.center,
          height: 40,
          child: CircleAvatar(
            radius: 14,
            backgroundColor: Colors.blue.shade100,
            child: Icon(
              isPercentage ? Icons.percent : Icons.notes,
              size: 16,
              color: Colors.blue.shade900,
            ),
          ),
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
    showProjectEvaluationDialog(
      context: context,
      project: project,
      date: date,
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
