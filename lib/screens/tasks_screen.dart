import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/task_item.dart';
import '../models/project.dart';
import 'task_form_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _selectedTab = '<Tüm>';

  String _getRelativeDateString(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(taskDay).inDays;
    if (diff == 0) {
      return 'Bugün';
    } else if (diff == 1) {
      return 'Dün';
    } else if (diff == -1) {
      return 'Yarın';
    } else if (diff > 1) {
      return '$diff gün önce';
    } else {
      return '${diff.abs()} gün sonra';
    }
  }

  String _getRecurrenceText(String rule) {
    if (rule.contains('FREQ=DAILY')) {
      return 'Günlük';
    }
    if (rule.contains('FREQ=WEEKLY')) {
      final daysMap = {
        'MO': 'Pzt',
        'TU': 'Sal',
        'WE': 'Çar',
        'TH': 'Per',
        'FR': 'Cum',
        'SA': 'Cmt',
        'SU': 'Paz',
      };
      String days = '';
      daysMap.forEach((key, val) {
        if (rule.contains(key)) {
          if (days.isNotEmpty) days += ', ';
          days += val;
        }
      });
      return 'Haftalık${days.isNotEmpty ? ' ($days)' : ''}';
    }
    if (rule.contains('FREQ=MONTHLY')) {
      return 'Aylık';
    }
    if (rule.contains('FREQ=YEARLY')) {
      return 'Yıllık';
    }
    return 'Tekrarlayan';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final tasks = appState.filteredTasks;
    final isDark = appState.isDarkMode;

    // Filter tasks based on selected horizontal tab
    final displayedTasks = tasks.where((t) {
      if (_selectedTab == '<Tüm>') return true;
      return t.tag == _selectedTab;
    }).toList();

    // Group tags
    final tabs = ['<Tüm>', ...appState.taskTags];

    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Blue circle date badge on the left
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                '${now.day} Tem',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (appState.firebaseUser != null) {
                await appState.syncDataWithFirebase();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Veriler senkronize edildi.')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Simple search popup
              showDialog(
                context: context,
                builder: (context) {
                  final searchCtrl = TextEditingController(text: appState.searchQuery);
                  return AlertDialog(
                    title: const Text('Görev Ara'),
                    content: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(hintText: 'Arama terimi girin...'),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          appState.setSearchQuery('');
                          Navigator.pop(context);
                        },
                        child: const Text('Temizle'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          appState.setSearchQuery(searchCtrl.text);
                          Navigator.pop(context);
                        },
                        child: const Text('Ara'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TaskFormScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Horizontal scrolling tab bar
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isSelected = tab == _selectedTab;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTab = tab;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue
                          : (isDark ? Colors.grey.shade800 : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey.shade300,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        tab,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Task List
          Expanded(
            child: displayedTasks.isEmpty
                ? Center(
                    child: Text(
                      'Seçili kategoride görev bulunmamaktadır.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    itemCount: displayedTasks.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final task = displayedTasks[index];
                      final isCompleted = task.isCompleted;
                      final dateLabel = task.from != null
                          ? '${task.from!.day}/${task.from!.month}/${task.from!.year}'
                          : 'Tarihsiz';

                      final relativeStr = _getRelativeDateString(task.from);
                      final isOverdue = task.from != null &&
                          task.from!.isBefore(DateTime.now()) &&
                          !isCompleted &&
                          relativeStr.contains('önce');

                      // Get project details to color circular checkbox border
                      final project = appState.projects.firstWhere(
                        (p) => p.id == task.projectId,
                        orElse: () => const Project(id: '', title: '', colorValue: 0xFF2196F3, evaluationType: 'PERCENTAGE', targetValue: 100.0),
                      );

                      final circleColor = task.projectId != null
                          ? Color(project.colorValue)
                          : (task.importance == 2
                              ? Colors.red
                              : (task.importance == 1 ? Colors.orange : Colors.blue));

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          leading: GestureDetector(
                            onTap: () {
                              appState.toggleTaskCompletion(task.id);
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: circleColor, width: 2),
                                color: isCompleted ? circleColor : Colors.transparent,
                              ),
                              child: isCompleted
                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                  : null,
                            ),
                          ),
                          title: Text(
                            task.title,
                            style: TextStyle(
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                              color: isCompleted ? Colors.grey : null,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (task.description.isNotEmpty)
                                Text(
                                  task.description,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    dateLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (relativeStr.isNotEmpty) ...[
                                    Icon(
                                      isOverdue ? Icons.warning_amber_rounded : Icons.calendar_today_outlined,
                                      size: 11,
                                      color: isOverdue ? Colors.red.shade700 : Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      relativeStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isOverdue ? Colors.red.shade700 : Colors.blue.shade700,
                                        fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                  if (task.recurrenceRule != null && task.recurrenceRule!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Icon(Icons.autorenew, size: 11, color: Colors.green.shade700),
                                    const SizedBox(width: 2),
                                    Text(
                                      _getRecurrenceText(task.recurrenceRule!),
                                      style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_note, color: Colors.blueGrey),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TaskFormScreen(existingTask: task),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  // Show delete confirmation dialog
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Görevi Sil'),
                                      content: const Text('Bu görevi silmek istediğinize emin misiniz?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Vazgeç'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          onPressed: () {
                                            appState.deleteTask(task.id);
                                            Navigator.pop(context);
                                          },
                                          child: const Text('Sil', style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TaskFormScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
